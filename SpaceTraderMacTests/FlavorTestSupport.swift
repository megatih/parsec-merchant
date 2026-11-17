// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecInsights
import Synchronization
@testable import ParsecMerchant

/// A clock that only moves when a test advances it (LLM-014, LLM-019).
final class ManualClock: Clock, Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration
        func advanced(by d: Duration) -> Instant { Instant(offset: offset + d) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (a: Instant, b: Instant) -> Bool { a.offset < b.offset }
    }

    private struct Sleeper {
        var id: Int
        var deadline: Instant
        var continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now = Instant(offset: .zero)
        var sleepers: [Sleeper] = []
        var nextID = 0
    }

    private let state = Mutex(State())

    var now: Instant { state.withLock { $0.now } }
    var minimumResolution: Duration { .zero }
    var sleeperCount: Int { state.withLock { $0.sleepers.count } }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let id = state.withLock { s in
            s.nextID += 1
            return s.nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
                let resumeNow: Bool = state.withLock { s in
                    if deadline <= s.now { return true }
                    s.sleepers.append(Sleeper(id: id, deadline: deadline, continuation: c))
                    return false
                }
                if resumeNow { c.resume() }
            }
        } onCancel: {
            let c = state.withLock { s -> CheckedContinuation<Void, any Error>? in
                guard let i = s.sleepers.firstIndex(where: { $0.id == id }) else { return nil }
                return s.sleepers.remove(at: i).continuation
            }
            c?.resume(throwing: CancellationError())
        }
    }

    func advance(by d: Duration) {
        let due = state.withLock { s -> [CheckedContinuation<Void, any Error>] in
            s.now = s.now.advanced(by: d)
            let ready = s.sleepers.filter { $0.deadline <= s.now }
            s.sleepers.removeAll { $0.deadline <= s.now }
            return ready.map(\.continuation)
        }
        for c in due { c.resume() }
    }

    /// Waits (yielding) until at least `n` tasks sleep on this clock.
    func waitForSleepers(_ n: Int = 1) async {
        for _ in 0..<10_000 where sleeperCount < n { await Task.yield() }
    }
}

/// A model client that answers with fixed text, throws, or never answers until cancelled (LLM-014/015).
final class FakeModelClient: FlavorModelClient {
    enum Behaviour: Sendable { case answer(String), fail, hang }
    let behaviour: Behaviour
    private let count = Mutex(0)
    var calls: Int { count.withLock { $0 } }

    init(_ behaviour: Behaviour) {
        self.behaviour = behaviour
    }

    func respond(instructions: String, prompt: String) async throws -> String {
        count.withLock { $0 += 1 }
        switch behaviour {
        case let .answer(text): return text
        case .fail: throw CancellationError()
        case .hang:
            try await Task.sleep(for: .seconds(3600))
            return "late"
        }
    }
}

/// A generator controlled by the test: each request waits until released (or answers immediately).
final class GatedGenerator: Sendable {
    private struct State {
        var started: [Int] = []
        var waiting: [Int: CheckedContinuation<FlavorText?, Never>] = [:]
    }

    private let state = Mutex(State())
    let immediate: FlavorText?

    init(immediate: FlavorText? = nil) {
        self.immediate = immediate
    }

    var started: [Int] { state.withLock { $0.started } }

    var generator: FlavorService.Generator {
        { [self] request, _ in
            if let immediate {
                self.state.withLock { $0.started.append(request.entryID) }
                return immediate
            }
            return await withCheckedContinuation { c in
                self.state.withLock { s in
                    s.started.append(request.entryID)
                    s.waiting[request.entryID] = c
                }
            }
        }
    }

    func release(_ entryID: Int, with text: FlavorText?) {
        let c = state.withLock { $0.waiting.removeValue(forKey: entryID) }
        c?.resume(returning: text)
    }

    func waitForStart(count: Int) async {
        for _ in 0..<10_000 where started.count < count { await Task.yield() }
    }
}
