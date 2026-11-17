// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import Foundation
import ParsecEngine

/// AUD-040: performs one haptic pattern. Production calls `NSHapticFeedbackManager`; tests inject a recorder.
@MainActor
protocol HapticPerforming {
    func perform(_ pattern: HapticPattern)
}

/// The Force Touch trackpad performer.
struct SystemHapticPerformer: HapticPerforming {
    func perform(_ pattern: HapticPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(Self.feedback(pattern), performanceTime: .now)
    }

    static func feedback(_ pattern: HapticPattern) -> NSHapticFeedbackManager.FeedbackPattern {
        switch pattern {
        case .alignment: .alignment
        case .generic: .generic
        case .levelChange: .levelChange
        }
    }
}

/// AUD-040 / AUD-041: haptics only while the app is active, at most once per 100 ms and once per step (one auto-repeat
/// round), and only with Settings › Sound › Haptics on. Each haptic has a visual twin (the quantity field at its
/// maximum, the Transit view, the screen shake or its Reduce Motion flash).
@MainActor
final class HapticsService: SessionHaptics {
    static let minimumInterval: TimeInterval = 0.1

    let performer: any HapticPerforming
    private let defaults: UserDefaults
    private let now: () -> TimeInterval
    private(set) var isAppActive = true
    private var lastFire: TimeInterval?

    init(performer: any HapticPerforming, defaults: UserDefaults,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.performer = performer
        self.defaults = defaults
        self.now = now
    }

    func perform(record: StepRecord) {
        if let pattern = HapticMap.pattern(for: record) { fire(pattern) }
    }

    func perform(app: AppHaptic) {
        fire(HapticMap.pattern(for: app))
    }

    func setAppActive(_ active: Bool) {
        isAppActive = active
    }

    private func fire(_ pattern: HapticPattern) {
        guard isAppActive, SoundSettings(defaults: defaults).hapticsEnabled else { return }
        let t = now()
        if let lastFire, t - lastFire < Self.minimumInterval { return }
        lastFire = t
        performer.perform(pattern)
    }
}

/// AUD-040: which steps and controls produce haptics. Pure; the event map is an exhaustive switch.
enum HapticMap {
    /// UI-ENC-098: a heavy hit is a hull loss of at least 15% of the player's maximum hull in one round.
    static let heavyHitPercent = 15

    static func pattern(for app: AppHaptic) -> HapticPattern {
        switch app {
        case .quantitySnap, .sliderFull: .alignment
        }
    }

    /// UI-SHELL-067: a market quantity snaps when the request reaches the cap (affordable, bays or stock).
    static func quantitySnaps(requested: Int, maximum: Int) -> Bool {
        maximum > 0 && requested >= maximum
    }

    /// The step's strongest haptic (one per step, so one per auto-repeat round).
    static func pattern(for record: StepRecord) -> HapticPattern? {
        let all = patterns(for: record)
        if all.contains(.levelChange) { return .levelChange }
        if all.contains(.generic) { return .generic }
        return all.first
    }

    static func patterns(for record: StepRecord) -> [HapticPattern] {
        let ship = record.before.commander.ship
        let maxHull = max(1, ship.hullStrength(record.before.ruleset))
        var hull = ship.hull
        var out: [HapticPattern] = []
        for event in record.events {
            if case let .combatRound(_, _, _, playerHull, _) = event {
                if (hull - playerHull) * 100 >= heavyHitPercent * maxHull { out.append(.levelChange) }
                hull = playerHull
            } else if let p = pattern(for: event) {
                out.append(p)
            }
        }
        return out
    }

    /// Exhaustive, no `default`: departure is `.generic`, the player's destruction `.levelChange`, nothing else.
    static func pattern(for event: GameEvent) -> HapticPattern? {
        switch event {
        case .departed: return .generic
        case .playerDestroyed, .bothDestroyed: return .levelChange
        case .combatRound: return nil  // heavy hits are measured across the step's rounds above
        case .gameStarted, .boughtCargo, .soldCargo, .dumpedCargo, .jettisonedCargo, .caughtLittering, .boughtFuel,
             .repairedHull, .boughtEquipment, .soldEquipment, .boughtShip, .cannotTransfer, .cannotAffordTransfer,
             .cannotAffordAllTransfers, .customShipBuilt, .opponentDestroyed, .opponentDisabled, .playerEscaped,
             .opponentEscaped, .encounterChanged, .bountyPaid, .fabricRip, .encounterStarted, .uneventfulTrip,
             .arrived, .debtWarning, .debtReminder, .reactorWarning, .reactorMeltdown, .tribblesChanged,
             .tribblesDied, .tribblesAteFood, .tribbleInspectorWarning, .passengerConcerned, .passengerImpatient,
             .autoFuelFailed, .autoRepairFailed, .easterEgg, .easterEggNoShieldSlot, .escapePodUsed, .wildLeftShip,
             .singularityLost, .departureBlocked, .gemulonInvaded, .experimentPerformed, .playerAttacked, .playerFled,
             .artifactRelinquished, .preciousHidden, .sculptureTaken, .blackmailed, .looted, .wildJoinedPirates,
             .bribed, .fined, .inspectionClean, .reactorConfiscated, .yielded, .tonicConsumed, .captainTraining,
             .plundered, .scooped, .scoopNoRoom, .arrested, .boughtEscapePod, .hired, .fired, .borrowed, .repaid,
             .insuranceBought, .insuranceStopped, .optionsChanged, .orbitTradeCompleted, .specialEventCompleted,
             .specialEventRefused, .sealedCanisters, .gameEnded, .cheatUsed, .cheatReadout:
            return nil
        }
    }
}
