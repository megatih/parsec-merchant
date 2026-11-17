// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// UI-ENC-052: how one finished encounter ended.
enum EncounterOutcome: Equatable, Sendable {
    // Combat.
    case destroyed(ShipType, bounty: Int?)
    case disabled
    case escaped(wasHit: Bool)
    case opponentEscaped
    // Plunder and trade.
    case plundered([TradeItemType: Int])
    case traded(direction: OrbitTradeDirection, item: TradeItemType, quantity: Int, total: Int)
    // Police.
    case bribed(Int)
    case fined(Int)
    case inspectedClean
    case yielded
    case arrested
    // Pirates and aliens.
    case raided(units: Int)
    case artifactSurrendered
    // Very rare.
    case drank(good: Bool)
    case trained(SkillType)
    // Endings.
    case escapePod
    case killed
    /// Ignore, or the opponent ignored you.
    case passed

    // swiftlint:disable cyclomatic_complexity
    /// Summarizes the encounter's events (all steps). The most consequential outcome wins: endings, arrest, combat
    /// results, then plunder, trade, police and the very rare encounters.
    static func derive(events: [GameEvent], endedBy: Command?) -> EncounterOutcome {
        var destroyed: ShipType?
        var bounty: Int?
        var disabled = false
        var escaped: Bool?
        var opponentEscaped = false
        var plundered: [TradeItemType: Int] = [:]
        var traded: EncounterOutcome?
        var bribe: Int?
        var fine: Int?
        var clean = false
        var yielded = false
        var arrested = false
        var raided: Int?
        var artifact = false
        var drank: Bool?
        var trained: SkillType?
        var pod = false
        var killed = false
        for e in events {
            switch e {
            case let .opponentDestroyed(type): destroyed = type
            case let .bountyPaid(amount): bounty = (bounty ?? 0) + amount
            case .opponentDisabled: disabled = true
            case let .playerEscaped(wasHit): escaped = wasHit
            case .opponentEscaped: opponentEscaped = true
            case let .plundered(item, quantity): plundered[item, default: 0] += quantity
            case let .orbitTradeCompleted(direction, item, quantity, total):
                traded = .traded(direction: direction, item: item, quantity: quantity, total: total)
            case let .bribed(amount): bribe = amount
            case let .fined(amount): fine = amount
            case .inspectionClean: clean = true
            case .yielded, .reactorConfiscated: yielded = true
            case .arrested: arrested = true
            case let .looted(units): raided = (raided ?? 0) + units
            case .blackmailed, .sculptureTaken, .preciousHidden, .wildJoinedPirates: raided = raided ?? 0
            case .artifactRelinquished: artifact = true
            case let .tonicConsumed(good): drank = good
            case let .captainTraining(skill): trained = skill
            case .escapePodUsed: pod = true
            case .playerDestroyed, .bothDestroyed: killed = true
            case .gameStarted, .boughtCargo, .soldCargo, .dumpedCargo, .jettisonedCargo, .caughtLittering, .boughtFuel,
                 .repairedHull, .boughtEquipment, .soldEquipment, .boughtShip, .cannotTransfer, .cannotAffordTransfer,
                 .cannotAffordAllTransfers, .customShipBuilt, .combatRound, .encounterChanged, .departed, .fabricRip,
                 .encounterStarted, .uneventfulTrip, .arrived, .debtWarning, .debtReminder, .reactorWarning, .reactorMeltdown,
                 .tribblesChanged, .tribblesDied, .tribblesAteFood, .tribbleInspectorWarning, .passengerConcerned,
                 .passengerImpatient, .autoFuelFailed, .autoRepairFailed, .easterEgg, .easterEggNoShieldSlot, .wildLeftShip,
                 .singularityLost, .departureBlocked, .gemulonInvaded, .experimentPerformed, .playerAttacked, .playerFled,
                 .scooped, .scoopNoRoom, .boughtEscapePod, .hired, .fired, .borrowed, .repaid, .insuranceBought,
                 .insuranceStopped, .optionsChanged, .specialEventCompleted, .specialEventRefused, .sealedCanisters,
                 .gameEnded, .cheatUsed, .cheatReadout:
                break
            }
        }
        if pod { return .escapePod }
        if killed { return .killed }
        if arrested { return .arrested }
        if let destroyed { return .destroyed(destroyed, bounty: bounty) }
        if !plundered.isEmpty { return .plundered(plundered) }
        if disabled { return .disabled }
        if let escaped { return .escaped(wasHit: escaped) }
        if opponentEscaped { return .opponentEscaped }
        if let traded { return traded }
        if let bribe { return .bribed(bribe) }
        if let fine { return .fined(fine) }
        if clean { return .inspectedClean }
        if yielded { return .yielded }
        if let raided { return .raided(units: raided) }
        if artifact { return .artifactSurrendered }
        if let drank { return .drank(good: drank) }
        if let trained { return .trained(trained) }
        return .passed
    }
    // swiftlint:enable cyclomatic_complexity
}

/// UI-ENC-053: one finished encounter of a trip.
struct EncounterSummary: Equatable, Sendable {
    var type: EncounterType
    var opponent: ShipType
    var badge: EncounterBadge
    var clicks: Int
    var outcome: EncounterOutcome
    /// The frozen combat log lines of the encounter (supplied by the combat-log consumer, UI-ENC-022).
    var log: [String]
}

/// UI-ENC-051: the costs paid at departure, from the state before the departing step. The engine charges exactly this
/// preview (TRV-086…088), so it is not recomputed afterwards.
enum DepartureCosts {
    static func make(command: Command, before: GameState) -> DailyCosts {
        if command == .jump { return before.dailyCosts(to: before.jumpPreview.destination) }
        return before.warpTargetPreview(before.warpSystem).costs
    }
}

/// UI-ENC-053: a trip from departure to its end.
struct Trip: Equatable, Sendable {
    enum End: Equatable, Sendable {
        case arrived(system: Int)
        case gameOver
    }

    var departureCosts: DailyCosts
    /// The state before the departing step.
    var before: GameState
    /// The state after the trip's last step.
    var after: GameState
    var from: Int
    var destination: Int
    var viaWormhole: Bool
    var fabricRip: Int?
    var encounters: [EncounterSummary] = []
    /// Every event of the trip that is not part of an encounter, in order.
    var events: [GameEvent] = []
    /// Every event of the trip, in order.
    var allEvents: [GameEvent] = []
    var end: End?

    func contains(_ test: (GameEvent) -> Bool) -> Bool { allEvents.contains(where: test) }
}

/// UI-ENC-053: the pure fold over step records that collects a trip and finishes it at `arrived(system:)` or the end
/// of the game.
struct TripAccumulator: Equatable, Sendable {
    private struct OpenEncounter: Equatable, Sendable {
        var type: EncounterType
        var opponent: ShipType
        var clicks: Int
        var events: [GameEvent] = []
        var log: [String] = []
    }

    private(set) var trip: Trip?
    private var open: OpenEncounter?

    var isTripInProgress: Bool { trip != nil }

    /// Folds `step` in; returns the trip when the step finished it. `log` holds the step's combat log lines.
    mutating func fold(_ step: StepRecord, log: [String] = []) -> Trip? {
        var pendingLog = log
        var finished: Trip?
        resumeIfNeeded(before: step.before, command: step.command)
        for e in step.events {
            if case let .departed(from, to, viaWormhole) = e {
                open = nil
                trip = Trip(departureCosts: DepartureCosts.make(command: step.command, before: step.before), before: step.before,
                            after: step.after, from: from, destination: to, viaWormhole: viaWormhole)
            }
            guard var t = trip else { continue }
            t.allEvents.append(e)
            switch e {
            case let .encounterStarted(type, opponent, clicks, _):
                close(into: &t, endedBy: step.command, log: &pendingLog)
                open = OpenEncounter(type: type, opponent: opponent, clicks: clicks)
                open?.events.append(e)
            case let .arrived(system):
                close(into: &t, endedBy: step.command, log: &pendingLog)
                t.events.append(e)
                t.destination = system
                t.end = .arrived(system: system)
            case .gameEnded:
                close(into: &t, endedBy: step.command, log: &pendingLog)
                t.events.append(e)
                t.end = .gameOver
            case let .fabricRip(destination):
                t.fabricRip = destination
                t.destination = destination
                t.events.append(e)
            default:
                if open != nil, Self.isEncounterEvent(e) {
                    open?.events.append(e)
                } else {
                    // A transit or arrival event means the encounter is over; other events (littering, jettisoned
                    // cargo) happen beside it.
                    if Self.isTripLevelEvent(e) { close(into: &t, endedBy: step.command, log: &pendingLog) }
                    t.events.append(e)
                }
            }
            trip = t
        }
        guard var t = trip else { return nil }
        if case .encounter = step.after.phase {
            if !pendingLog.isEmpty { open?.log += pendingLog }
        } else {
            close(into: &t, endedBy: step.command, log: &pendingLog)
        }
        t.after = step.after
        if t.end != nil {
            finished = t
            trip = nil
            open = nil
        } else {
            trip = t
        }
        return finished
    }

    /// A game loaded in an encounter (or put there by a fixture) has no departing step: the trip resumes from the
    /// encounter, so its end still shows the arrival card or report sheet. The departure costs were paid before the save.
    private mutating func resumeIfNeeded(before: GameState, command: Command) {
        guard trip == nil, case let .encounter(enc) = before.phase else { return }
        var none = DepartureCosts.make(command: command, before: before)
        (none.mercenaries, none.insurance, none.interest, none.wormholeTax) = (0, 0, 0, 0)
        let transit = before.encounterTransit
        trip = Trip(departureCosts: none, before: before, after: before, from: before.commander.currentSystem,
                    destination: transit?.destination ?? before.warpSystem, viaWormhole: transit?.viaWormhole ?? false)
        open = OpenEncounter(type: enc.type, opponent: enc.opponent.type, clicks: enc.clicks)
    }

    private mutating func close(into t: inout Trip, endedBy: Command, log: inout [String]) {
        guard var enc = open else { return }
        enc.log += log
        log = []
        open = nil
        t.encounters.append(EncounterSummary(type: enc.type, opponent: enc.opponent, badge: enc.type.badge(opponent: enc.opponent),
                                             clicks: enc.clicks, outcome: EncounterOutcome.derive(events: enc.events, endedBy: endedBy),
                                             log: enc.log))
    }

    /// Transit and arrival events: they come only after the encounter in progress ended.
    static func isTripLevelEvent(_ e: GameEvent) -> Bool {
        switch e {
        case .departed, .fabricRip, .encounterStarted, .arrived, .uneventfulTrip, .debtWarning, .debtReminder, .reactorWarning,
             .reactorMeltdown, .tribblesChanged, .tribblesDied, .tribblesAteFood, .tribbleInspectorWarning, .passengerConcerned,
             .passengerImpatient, .autoFuelFailed, .autoRepairFailed, .boughtFuel, .repairedHull, .easterEgg,
             .easterEggNoShieldSlot, .gameEnded, .gemulonInvaded, .experimentPerformed, .wildLeftShip:
            return true
        default:
            return false
        }
    }

    /// Events that belong to the encounter in progress (combat, outcomes, plunder, police and the endings).
    static func isEncounterEvent(_ e: GameEvent) -> Bool {
        switch e {
        case .combatRound, .playerDestroyed, .bothDestroyed, .opponentDestroyed, .opponentDisabled, .playerEscaped,
             .opponentEscaped, .encounterChanged, .bountyPaid, .playerAttacked, .playerFled, .artifactRelinquished,
             .preciousHidden, .sculptureTaken, .blackmailed, .looted, .wildJoinedPirates, .bribed, .fined, .inspectionClean,
             .reactorConfiscated, .yielded, .tonicConsumed, .captainTraining, .plundered, .scooped, .scoopNoRoom, .arrested,
             .escapePodUsed, .orbitTradeCompleted:
            return true
        default:
            return false
        }
    }
}
