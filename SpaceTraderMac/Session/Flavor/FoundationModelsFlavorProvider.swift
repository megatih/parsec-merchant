// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import ParsecInsights
import Synchronization
#if canImport(FoundationModels)
import FoundationModels
#endif

/// LLM-012: the model call, behind a protocol so tests inject fakes.
nonisolated protocol FlavorModelClient: Sendable {
    func respond(instructions: String, prompt: String) async throws -> String
}

#if canImport(FoundationModels)
/// LLM-012 / LLM-017: the production client: the on-device default model only (no network, no account, no PCC).
nonisolated struct SystemLanguageModelClient: FlavorModelClient {
    func respond(instructions: String, prompt: String) async throws -> String {
        let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
        return try await session.respond(to: prompt).content
    }
}
#endif

/// LLM-012…016: generated prose for one log entry, or nil (unavailable, timeout, error, invalid output).
nonisolated struct FoundationModelsFlavorProvider: FlavorProvider {
    static let defaultTimeout = Duration.seconds(4)

    let client: any FlavorModelClient
    let availability: @Sendable () -> FlavorAvailability
    let timeout: Duration
    let clock: any Clock<Duration>

    var source: FlavorSource { .foundationModels }

    init(client: any FlavorModelClient, availability: @escaping @Sendable () -> FlavorAvailability = { FlavorAvailability.current },
         timeout: Duration = defaultTimeout, clock: any Clock<Duration> = ContinuousClock()) {
        self.client = client
        self.availability = availability
        self.timeout = timeout
        self.clock = clock
    }

    /// The production provider, or nil when the framework is not in this build (`.unsupportedBuild`).
    static func system() -> FoundationModelsFlavorProvider? {
        #if canImport(FoundationModels)
        FoundationModelsFlavorProvider(client: SystemLanguageModelClient())
        #else
        nil
        #endif
    }

    func flavor(for request: FlavorRequest) async -> FlavorText? {
        await flavor(for: request, names: .empty)
    }

    /// LLM-013: checks availability first; LLM-014: races the call against the timeout; LLM-015: validates the output.
    func flavor(for request: FlavorRequest, names: FlavorNames) async -> FlavorText? {
        guard availability() == .available else { return nil }
        let prompt = FlavorPromptBuilder.prompt(for: request, names: names)
        guard let raw = await respondWithTimeout(prompt: prompt), let text = FlavorOutputValidator.validate(raw) else { return nil }
        return .generated(text: text)
    }

    /// The first of (the client's answer, the timeout) wins; the loser is cancelled. Never waits for a client that
    /// ignores cancellation.
    private func respondWithTimeout(prompt: String) async -> String? {
        let client = client
        let clock = clock
        let timeout = timeout
        let gate = ResumeOnce()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
                gate.install(continuation)
                let work = Task {
                    let answer = try? await client.respond(instructions: FlavorPromptBuilder.instructions, prompt: prompt)
                    gate.resume(answer)
                }
                let timer = Task {
                    try? await clock.sleep(for: timeout)
                    gate.resume(nil)
                }
                gate.onFinish {
                    work.cancel()
                    timer.cancel()
                }
            }
        } onCancel: {
            gate.resume(nil)
        }
    }
}

/// Resumes a continuation exactly once, from whichever task finishes first.
private nonisolated final class ResumeOnce: Sendable {
    private struct Box {
        var continuation: CheckedContinuation<String?, Never>?
        var pending: String??
        var done = false
        var finish: (@Sendable () -> Void)?
    }

    private let box = Mutex(Box())

    func install(_ c: CheckedContinuation<String?, Never>) {
        let early: String?? = box.withLock { b in
            if let p = b.pending { b.done = true; return .some(p) }
            b.continuation = c
            return nil
        }
        if let early { c.resume(returning: early) }
    }

    func onFinish(_ f: @escaping @Sendable () -> Void) {
        let runNow = box.withLock { b in
            if b.done { return true }
            b.finish = f
            return false
        }
        if runNow { f() }
    }

    func resume(_ value: String?) {
        let (c, f): (CheckedContinuation<String?, Never>?, (@Sendable () -> Void)?) = box.withLock { b in
            guard !b.done else { return (nil, nil) }
            guard let c = b.continuation else {
                if b.pending == nil { b.pending = .some(value) }
                return (nil, nil)
            }
            b.done = true
            b.continuation = nil
            let f = b.finish
            b.finish = nil
            return (c, f)
        }
        c?.resume(returning: value)
        f?()
    }
}
