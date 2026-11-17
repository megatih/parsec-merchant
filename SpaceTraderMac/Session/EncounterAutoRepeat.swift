// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// UI-ENC-037: auto-repeat timing constants (ENC-188: 0.6 s; the C# timer was 1 s).
enum AutoRepeat {
    static let interval: Duration = .milliseconds(600)
}

/// UI-ENC-037: the machine's state: its mode plus the facts the rules of UI-ENC-039 read.
struct AutoRepeatState: Equatable, Sendable {
    enum Mode: Equatable, Sendable {
        case idle
        case scheduled(token: Int)
        /// A presentation or playback holds the repeat; it resumes with a full interval (UI-ENC-039 rule 4).
        case suspended
    }

    var mode: Mode = .idle
    /// The last token handed out; every schedule takes a fresh one, so stale ticks are recognisable (UI-ENC-038).
    var lastToken = 0
    /// The session-only Auto-repeat switch (UI-ENC-033), on by default.
    var enabled = true
    /// The engine's `encounterPreview.canAutoRepeat` after the last accepted step.
    var canAutoRepeat = false
    var inEncounter = false
    var isModal = false
    var playbackRunning = false

    /// Whether a repeat is wanted at all (rule 1 without the blocking conditions).
    var wantsRepeat: Bool { enabled && canAutoRepeat && inEncounter }
    var isBlocked: Bool { isModal || playbackRunning }
}

/// UI-ENC-037: what happens to the machine.
enum AutoRepeatEvent: Equatable, Sendable {
    case stepApplied(canAutoRepeat: Bool, inEncounter: Bool)
    case presentationChanged(isModal: Bool)
    case playbackChanged(running: Bool)
    case toggle(enabled: Bool)
    case manualAction
    case escape(canStop: Bool)
    case tick(token: Int)
}

/// UI-ENC-037: what the driver must do.
enum AutoRepeatEffect: Equatable, Sendable {
    case schedule(token: Int, after: Duration)
    case cancel
    case send(Command)
}

/// UI-ENC-037/039/040: the pure auto-repeat reducer. Effects are returned in the order the driver runs them (Esc
/// cancels and then sends Stop).
enum AutoRepeatMachine {
    static func reduce(_ state: AutoRepeatState, _ event: AutoRepeatEvent) -> (AutoRepeatState, [AutoRepeatEffect]) {
        var s = state
        switch event {
        case let .stepApplied(canAutoRepeat, inEncounter):
            // Rule 1 (and rule 5: a rejected repeat arrives here with `canAutoRepeat == false`). A step result always
            // starts a fresh interval.
            let wasScheduled = s.isScheduled
            s.canAutoRepeat = canAutoRepeat
            s.inEncounter = inEncounter
            s.mode = .idle
            let (next, settled) = settle(s)
            var effects = settled
            if wasScheduled, !effects.contains(.cancel) { effects.insert(.cancel, at: 0) }
            return (next, effects)
        case let .presentationChanged(isModal):
            s.isModal = isModal
            return settle(s)
        case let .playbackChanged(running):
            s.playbackRunning = running
            return settle(s)
        case let .toggle(enabled):
            s.enabled = enabled
            return settle(s)
        case .manualAction:
            // Rule 3: any other encounter command clears the engine flags (ENC-187); its result re-enters rule 1.
            s.canAutoRepeat = false
            return settle(s)
        case let .escape(canStop):
            guard canStop else { return (s, []) }
            s.canAutoRepeat = false
            s.mode = .idle
            return (s, [.cancel, .send(.encounter(.stop))])
        case let .tick(token):
            // Rule 2: a current tick sends exactly once; a stale one (cancelled or superseded) is ignored.
            guard s.mode == .scheduled(token: token) else { return (s, []) }
            s.mode = .idle
            s.canAutoRepeat = false
            return (s, [.send(.encounter(.autoRepeat))])
        }
    }

    /// Moves to the mode the facts call for: idle (nothing wanted), suspended (wanted but blocked) or scheduled.
    private static func settle(_ state: AutoRepeatState) -> (AutoRepeatState, [AutoRepeatEffect]) {
        var s = state
        let wasScheduled = s.isScheduled
        if !s.wantsRepeat {
            s.mode = .idle
            return (s, wasScheduled ? [.cancel] : [])
        }
        if s.isBlocked {
            s.mode = .suspended
            return (s, wasScheduled ? [.cancel] : [])
        }
        if wasScheduled { return (s, []) }
        s.lastToken += 1
        s.mode = .scheduled(token: s.lastToken)
        return (s, [.schedule(token: s.lastToken, after: AutoRepeat.interval)])
    }
}

extension AutoRepeatState {
    var isScheduled: Bool { if case .scheduled = mode { true } else { false } }
}

/// UI-ENC-038: runs the machine's effects. A `.schedule` starts a task that sleeps on the injected clock and then feeds
/// `.tick(token)`; a tick whose token is no longer current is ignored by the machine, so a cancelled or superseded
/// schedule never sends.
@MainActor
final class AutoRepeatDriver {
    private(set) var state = AutoRepeatState()
    /// `ContinuousClock` in the app; a manual clock in tests.
    var clock: any Clock<Duration> = ContinuousClock()
    /// Every command the driver sent, in order (the determinism test compares it with a direct engine loop).
    private(set) var sentCommands: [Command] = []
    /// Sends a command through the session (set by the session).
    var send: ((Command) -> Void)?
    private var task: Task<Void, Never>?

    var isScheduled: Bool { state.isScheduled }

    func handle(_ event: AutoRepeatEvent) {
        let (next, effects) = AutoRepeatMachine.reduce(state, event)
        state = next
        for effect in effects { run(effect) }
    }

    /// Forgets everything (load, new game, close), keeping the session-only switch.
    func reset() {
        task?.cancel()
        task = nil
        state = AutoRepeatState(lastToken: state.lastToken, enabled: state.enabled)
        sentCommands = []
    }

    private func run(_ effect: AutoRepeatEffect) {
        switch effect {
        case .cancel:
            task?.cancel()
            task = nil
        case let .schedule(token, after):
            task?.cancel()
            let clock = clock
            task = Task { [weak self] in
                do {
                    try await clock.sleep(for: after)
                } catch {
                    return
                }
                self?.handle(.tick(token: token))
            }
        case let .send(command):
            sentCommands.append(command)
            send?(command)
        }
    }
}
