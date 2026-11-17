// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// UI-ENC-007: the app-side replay of a trip's clicks. The engine state is already final; the playback only animates
/// the click count from `fromClick` down to `toClick` (20 = departure, 0 = arrival) and never changes results.
struct TransitPlayback: Equatable, Sendable {
    /// How the played-back part of the trip ends.
    enum End: String, Equatable, Sendable {
        case arrival, encounter, gameOver, report
    }

    static let totalClicks = 20
    /// One click per tick; a full trip (20 ticks) takes 1.2 s.
    static let tickInterval: Duration = .milliseconds(60)

    var destination: Int
    var viaWormhole: Bool
    var fromClick: Int
    var toClick: Int
    var end: End
    /// The system a space-time fabric rip redirected the trip to (UI-ENC-012), shown as a banner.
    var fabricRip: Int?
    /// A resting `.inTransit` phase from a hand-edited save: shown frozen with "Transit interrupted" (UI-ENC-013).
    var isFrozen = false

    /// Number of ticks the playback runs (one click each).
    var tickCount: Int { isFrozen ? 0 : max(0, fromClick - toClick) }

    /// The click shown at `tick` (0-based; clamped to the playback's range).
    func click(atTick tick: Int) -> Int {
        isFrozen ? fromClick : max(toClick, fromClick - max(0, tick))
    }

    /// "Click N of 20" for the progress track: how many clicks of the trip are behind the ship.
    func clicksFlown(atTick tick: Int) -> Int { Self.totalClicks - click(atTick: tick) }

    /// UI-ENC-013: the static playback for a resting `.inTransit` phase.
    static func frozen(_ t: TransitState) -> TransitPlayback {
        TransitPlayback(destination: t.destination, viaWormhole: t.viaWormhole, fromClick: t.clicksRemaining,
                        toClick: t.clicksRemaining, end: .arrival, fabricRip: nil, isFrozen: true)
    }

    /// UI-ENC-007: the playback for `step`, or nil when the step neither departs nor ends an encounter mid-trip, when the
    /// encounter itself ended the trip (arrest, escape pod, destruction), or when `fast` (the playback is skipped).
    static func make(step: StepRecord, fast: Bool) -> TransitPlayback? {
        guard !fast else { return nil }
        let events = step.events
        var departure: (to: Int, viaWormhole: Bool)?
        var rip: Int?
        var arrived: Int?
        var tripEndedInEncounter = false
        var critical = false
        for e in events {
            switch e {
            case let .departed(_, to, viaWormhole): departure = (to, viaWormhole)
            case let .fabricRip(newDestination): rip = newDestination
            case let .arrived(system): arrived = system
            case .arrested, .escapePodUsed, .playerDestroyed, .bothDestroyed: tripEndedInEncounter = true
            case .reactorMeltdown: critical = true
            case let .reactorWarning(status) where status == ReactorStatus.temperatureWarning: critical = true
            default: break
            }
        }
        let fromClick: Int
        let viaWormhole: Bool
        var destination: Int
        if let departure {
            fromClick = totalClicks
            viaWormhole = departure.viaWormhole
            destination = departure.to
        } else {
            // Resumed trip: the step ended an encounter and the click loop continued (TRV-042).
            guard case let .encounter(enc) = step.before.phase, !tripEndedInEncounter else { return nil }
            guard !isEncounter(step.after.phase) || step.encounterStarted != nil else { return nil }
            guard let transit = step.before.transitPreview else { return nil }
            fromClick = max(0, enc.clicks - 1)
            viaWormhole = transit.viaWormhole
            destination = transit.destination
        }
        if let rip { destination = rip }
        if let arrived { destination = arrived }
        let end: End
        let toClick: Int
        if let started = step.encounterStarted {
            end = .encounter
            toClick = started.clicks
        } else if GameSession.isGameOver(step.after.phase) {
            end = .gameOver
            toClick = 0
        } else {
            end = critical ? .report : .arrival
            toClick = 0
        }
        return TransitPlayback(destination: destination, viaWormhole: viaWormhole, fromClick: fromClick,
                               toClick: min(toClick, fromClick), end: end, fabricRip: rip)
    }

    /// Still in an encounter after the step without a new `encounterStarted` means the encounter went on.
    private static func isEncounter(_ phase: GamePhase) -> Bool {
        if case .encounter = phase { return true }
        return false
    }
}

/// The reactor warning status values the app distinguishes (ALR-131…133, QST-REACTOR).
enum ReactorStatus {
    /// ALR-133: "the reactor is overheating" (the critical temperature warning).
    static let temperatureWarning = 18
}

/// UI-ENC-010: the Dock tile progress bar's fraction.
enum DockTileProgress {
    /// `(20 − click) / 20` at `tick`, or nil without a playback.
    static func fraction(playback: TransitPlayback?, tick: Int) -> Double? {
        guard let playback else { return nil }
        return Double(TransitPlayback.totalClicks - playback.click(atTick: tick)) / Double(TransitPlayback.totalClicks)
    }
}

/// UI-ENC-011: the Dock badge while an encounter waits for the player and the app is inactive.
enum DockAttention {
    static func badge(phase: GamePhase?, isActive: Bool) -> String? {
        guard !isActive, case .encounter = phase else { return nil }
        return "!"
    }
}
