// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import Testing
@testable import ParsecMerchant

/// A manual clock for UI-ENC-038: sleepers wake only when the test advances time. No real-time sleeps.
nonisolated final class TestClock: Clock, @unchecked Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration
        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (a: Instant, b: Instant) -> Bool { a.offset < b.offset }
    }

    private struct Sleeper {
        let id: Int
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let lock = NSLock()
    private var current = Instant(offset: .zero)
    private var sleepers: [Sleeper] = []
    private var nextID = 0

    var now: Instant { lock.withLock { current } }
    var minimumResolution: Duration { .zero }
    var sleeperCount: Int { lock.withLock { sleepers.count } }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let id = lock.withLock { () -> Int in
            nextID += 1
            return nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
                let fire: Bool = lock.withLock {
                    if Task.isCancelled { return false }
                    if deadline <= current { return true }
                    sleepers.append(Sleeper(id: id, deadline: deadline, continuation: c))
                    return false
                }
                if Task.isCancelled {
                    c.resume(throwing: CancellationError())
                } else if fire {
                    c.resume()
                }
            }
        } onCancel: {
            let cancelled: Sleeper? = lock.withLock {
                guard let i = sleepers.firstIndex(where: { $0.id == id }) else { return nil }
                return sleepers.remove(at: i)
            }
            cancelled?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Advances time and wakes every sleeper whose deadline has passed.
    func advance(by duration: Duration) {
        let due: [Sleeper] = lock.withLock {
            current = current.advanced(by: duration)
            let ready = sleepers.filter { $0.deadline <= current }
            sleepers.removeAll { $0.deadline <= current }
            return ready
        }
        for s in due { s.continuation.resume() }
    }
}

@MainActor
struct AutoRepeatTests {
    private typealias Machine = AutoRepeatMachine

    private func ready(_ change: (inout AutoRepeatState) -> Void = { _ in }) -> AutoRepeatState {
        var s = AutoRepeatState()
        s.canAutoRepeat = true
        s.inEncounter = true
        change(&s)
        return s
    }

    /// Lets the main actor run the driver's woken tasks until `done` holds (bounded; no real-time waits).
    private func settle(_ done: () -> Bool) async {
        for _ in 0..<200 where !done() { await Task.yield() }
    }

    // MARK: Machine (UI-ENC-037, -039, -040)

    @Test("UI-ENC-037 states, events and effects: interval 600 ms, schedule after an encounter step, tick sends once")
    func machineBasics() {
        #expect(AutoRepeat.interval == .milliseconds(600))
        let (s1, e1) = Machine.reduce(AutoRepeatState(), .stepApplied(canAutoRepeat: true, inEncounter: true))
        #expect(s1.mode == .scheduled(token: 1) && e1 == [.schedule(token: 1, after: .milliseconds(600))])
        let (s2, e2) = Machine.reduce(s1, .tick(token: 1))
        #expect(s2.mode == .idle && e2 == [.send(.encounter(.autoRepeat))])
        let (s3, e3) = Machine.reduce(s2, .tick(token: 1))
        #expect(s3 == s2 && e3.isEmpty)
        let (s4, e4) = Machine.reduce(s2, .stepApplied(canAutoRepeat: true, inEncounter: true))
        #expect(s4.mode == .scheduled(token: 2) && e4 == [.schedule(token: 2, after: AutoRepeat.interval)])
    }

    @Test("UI-ENC-039 rules: scheduling conditions, cancellation, suspension with a full interval, rejection never retries")
    func machineRules() {
        // Rule 1: no flag, leaving the encounter, the switch off, modal or a playback each prevent scheduling.
        #expect(Machine.reduce(AutoRepeatState(), .stepApplied(canAutoRepeat: false, inEncounter: true)).1.isEmpty)
        #expect(Machine.reduce(AutoRepeatState(), .stepApplied(canAutoRepeat: true, inEncounter: false)).1.isEmpty)
        #expect(Machine.reduce(ready { $0.enabled = false }, .stepApplied(canAutoRepeat: true, inEncounter: true)).0.mode == .idle)
        #expect(Machine.reduce(ready { $0.isModal = true }, .stepApplied(canAutoRepeat: true, inEncounter: true)).0.mode == .suspended)
        #expect(Machine.reduce(ready { $0.playbackRunning = true }, .stepApplied(canAutoRepeat: true, inEncounter: true)).0.mode == .suspended)
        // Rule 3: leaving the encounter, a manual action or the switch off cancel a scheduled repeat.
        let scheduled = Machine.reduce(AutoRepeatState(), .stepApplied(canAutoRepeat: true, inEncounter: true)).0
        #expect(Machine.reduce(scheduled, .stepApplied(canAutoRepeat: true, inEncounter: false)).1 == [.cancel])
        #expect(Machine.reduce(scheduled, .manualAction) == (ready { $0.canAutoRepeat = false; $0.lastToken = 1 }, [.cancel]))
        let off = Machine.reduce(scheduled, .toggle(enabled: false))
        #expect(off.0.mode == .idle && off.1 == [.cancel])
        // Turning it back on while a flag is set schedules a fresh repeat.
        #expect(Machine.reduce(off.0, .toggle(enabled: true)).1 == [.schedule(token: 2, after: AutoRepeat.interval)])
        // Rule 4: a presentation suspends; dismissing it resumes with a full interval and a new token.
        let suspended = Machine.reduce(scheduled, .presentationChanged(isModal: true))
        #expect(suspended.0.mode == .suspended && suspended.1 == [.cancel])
        let resumed = Machine.reduce(suspended.0, .presentationChanged(isModal: false))
        #expect(resumed.0.mode == .scheduled(token: 2) && resumed.1 == [.schedule(token: 2, after: AutoRepeat.interval)])
        #expect(Machine.reduce(suspended.0, .tick(token: 1)).1.isEmpty)
        let playing = Machine.reduce(scheduled, .playbackChanged(running: true))
        #expect(playing.0.mode == .suspended && Machine.reduce(playing.0, .playbackChanged(running: false)).0.isScheduled)
        // Rule 5: a rejected repeat arrives as a step without the flag: idle, no retry even when a dialog closes.
        let sent = Machine.reduce(scheduled, .tick(token: 1)).0
        let rejected = Machine.reduce(sent, .stepApplied(canAutoRepeat: false, inEncounter: true))
        #expect(rejected.0.mode == .idle && rejected.1.isEmpty)
        #expect(Machine.reduce(rejected.0, .presentationChanged(isModal: false)).1.isEmpty)
    }

    @Test("UI-ENC-040 Esc while canStop cancels and sends .stop; otherwise nothing; a later tick never sends")
    func escape() {
        let scheduled = Machine.reduce(AutoRepeatState(), .stepApplied(canAutoRepeat: true, inEncounter: true)).0
        let (afterEsc, effects) = Machine.reduce(scheduled, .escape(canStop: true))
        #expect(effects == [.cancel, .send(.encounter(.stop))] && afterEsc.mode == .idle)
        #expect(Machine.reduce(afterEsc, .tick(token: 1)).1.isEmpty)
        #expect(Machine.reduce(scheduled, .escape(canStop: false)) == (scheduled, []))
    }

    // MARK: Driver (UI-ENC-038)

    @Test("UI-ENC-038 the driver sleeps on the injected clock, ticks once per schedule and ignores stale ticks")
    func driver() async {
        let driver = AutoRepeatDriver()
        let clock = TestClock()
        driver.clock = clock
        var sent: [Command] = []
        driver.send = { sent.append($0) }
        driver.handle(.stepApplied(canAutoRepeat: true, inEncounter: true))
        await settle { clock.sleeperCount == 1 }
        clock.advance(by: .milliseconds(599))
        await settle { false }
        #expect(sent.isEmpty)
        clock.advance(by: .milliseconds(1))
        await settle { !sent.isEmpty }
        #expect(sent == [.encounter(.autoRepeat)] && driver.sentCommands == sent)
        // A superseded schedule never sends: schedule, toggle off (cancel), toggle on (new token), then run both.
        driver.handle(.stepApplied(canAutoRepeat: true, inEncounter: true))
        await settle { clock.sleeperCount == 1 }
        driver.handle(.toggle(enabled: false))
        driver.handle(.toggle(enabled: true))
        await settle { clock.sleeperCount == 1 }
        clock.advance(by: .seconds(1))
        await settle { sent.count == 2 }
        #expect(sent.count == 2)
        // A stale token fed by hand is ignored.
        driver.handle(.tick(token: 1))
        #expect(sent.count == 2)
    }

    // MARK: Determinism (UI-ENC-041, ENC-188)

    /// An encounter that lasts: an unarmed space monster fought by the player's ship.
    private func monsterSession() throws -> GameSession {
        try EncFx.session(.spaceMonsterAttack, opponent: .spaceMonster, weapons: [])
    }

    @Test("UI-ENC-041 ENC-188 Resolve through the session with a TestClock equals the direct engine loop")
    func determinism() async throws {
        let s = try monsterSession()
        let clock = TestClock()
        s.encounterUI.driver.clock = clock
        var direct = GameEngine(state: try #require(s.state))
        var directCommands: [Command] = [.encounter(.resolve)]
        _ = direct.perform(.encounter(.resolve))
        while direct.encounterPreview?.canAutoRepeat == true {
            _ = direct.perform(.encounter(.autoRepeat))
            directCommands.append(.encounter(.autoRepeat))
        }

        s.performEncounterAction(.resolve)
        var guardCount = 0
        while s.encounterUI.driver.isScheduled, guardCount < 500 {
            guardCount += 1
            let sentBefore = s.encounterUI.driver.sentCommands.count
            await settle { clock.sleeperCount == 1 }
            clock.advance(by: AutoRepeat.interval)
            await settle { s.encounterUI.driver.sentCommands.count > sentBefore }
        }
        #expect(guardCount > 1)
        #expect([.encounter(.resolve)] + s.encounterUI.driver.sentCommands == directCommands)
        #expect(s.state == direct.state)
    }

    @Test("UI-ENC-041 Esc after the second tick clears both flags and stays in the encounter")
    func escapeAfterTwoTicks() async throws {
        let s = try monsterSession()
        let clock = TestClock()
        s.encounterUI.driver.clock = clock
        s.performEncounterAction(.resolve)
        for expected in 1...2 {
            await settle { clock.sleeperCount == 1 }
            clock.advance(by: AutoRepeat.interval)
            await settle { s.encounterUI.driver.sentCommands.count >= expected }
        }
        #expect(s.encounterUI.driver.sentCommands == [.encounter(.autoRepeat), .encounter(.autoRepeat)])
        s.stopEncounter()
        let enc = try #require(s.state.flatMap(EncFx.encounter))
        #expect(!enc.continueAttacking && !enc.continueFleeing)
        #expect(!s.encounterUI.driver.isScheduled)
        // A tick after Esc never sends.
        clock.advance(by: .seconds(5))
        await settle { false }
        #expect(s.encounterUI.driver.sentCommands.last == .encounter(.stop) && s.encounterUI.driver.sentCommands.count == 3)
    }

    @Test("UI-ENC-039 a presentation suspends the session's repeat and a manual action cancels it")
    func sessionSuspension() async throws {
        let s = try monsterSession()
        s.encounterUI.driver.clock = TestClock()
        s.performEncounterAction(.resolve)
        #expect(s.encounterUI.driver.isScheduled)
        s.present(.sheet(.findSystem))
        #expect(s.encounterUI.driver.state.mode == .suspended)
        s.dismissPresentation()
        #expect(s.encounterUI.driver.isScheduled)
        s.performEncounterAction(.attack)
        // The manual attack re-enters rule 1 with its own result: still repeating under Resolve's forced flags.
        #expect(s.lastStep?.command == .encounter(.attack))
        s.setAutoRepeat(false)
        #expect(!s.encounterUI.driver.isScheduled)
    }
}
