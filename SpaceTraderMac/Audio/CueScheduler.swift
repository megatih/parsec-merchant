// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecAudio

/// AUD-033 / AUD-034: plays a step's cues at their offsets (through the synth's request delay), holds the cues the
/// transit playback reveals later until it ends, ticks at clicks 5, 10, 15 and 20, and throttles.
@MainActor
final class CueScheduler {
    /// At most this many cues per step (AUD-034).
    static let maxPerStep = 6
    /// An identical cue and variant within this many seconds of a previous one is merged into it.
    static let mergeWindow = 0.06
    /// The transit clicks (flown) that tick (AUD-013).
    static let tickClicks: Set<Int> = [5, 10, 15, 20]

    private let now: () -> TimeInterval
    /// Receives each request (the audio output's `enqueue`).
    var sink: (CueRequest) -> Void
    private(set) var held: [ScheduledCue] = []
    private(set) var isPlaybackRunning = false
    private var lastStart: [UInt16: TimeInterval] = [:]

    /// - Parameter now: the clock in seconds (tests pass a fake).
    init(now: @escaping () -> TimeInterval, sink: @escaping (CueRequest) -> Void = { _ in }) {
        self.now = now
        self.sink = sink
    }

    /// Plays or holds one step's cues.
    func schedule(_ cues: [ScheduledCue]) {
        for c in Self.throttle(cues) {
            if isPlaybackRunning && c.revealedByPlayback {
                held.append(c)
            } else {
                play(c)
            }
        }
    }

    func handle(_ event: TransitAudioEvent) {
        switch event {
        case .started:
            isPlaybackRunning = true
        case let .tick(clicksFlown):
            if isPlaybackRunning && Self.tickClicks.contains(clicksFlown) { play(ScheduledCue(cue: .uiTick)) }
        case .ended:
            isPlaybackRunning = false
            let release = held
            held = []
            // Released together with the presentation: the earliest held cue plays at once, the rest keep their spacing.
            let shift = release.map(\.offset).min() ?? 0
            for c in release { play(c, shift: shift) }
        case .cancelled:
            isPlaybackRunning = false
            held = []
        }
    }

    /// AUD-034: merges identical cue/variant pairs within 60 ms, then keeps the 6 highest-priority cues (event order
    /// breaks ties) and returns them in time order.
    static func throttle(_ cues: [ScheduledCue]) -> [ScheduledCue] {
        var merged: [ScheduledCue] = []
        for c in cues {
            let duplicate = merged.contains {
                $0.cue == c.cue && $0.variant == c.variant && abs($0.offset - c.offset) < mergeWindow
            }
            if !duplicate { merged.append(c) }
        }
        let kept = merged.enumerated().sorted { a, b in
            if a.element.priority != b.element.priority { return a.element.priority > b.element.priority }
            if a.element.eventIndex != b.element.eventIndex { return a.element.eventIndex < b.element.eventIndex }
            return a.offset < b.offset
        }.prefix(maxPerStep)
        return kept.sorted { a, b in
            a.element.offset != b.element.offset ? a.element.offset < b.element.offset : a.offset < b.offset
        }.map(\.element)
    }

    private func play(_ c: ScheduledCue, shift: Double = 0) {
        let key = UInt16(c.cue.rawValue) << 8 | UInt16(c.variant)
        let start = now() + max(0, c.offset - shift)
        if let last = lastStart[key], abs(start - last) < Self.mergeWindow { return }
        lastStart[key] = start
        sink(c.request(offsetBy: shift))
    }
}
