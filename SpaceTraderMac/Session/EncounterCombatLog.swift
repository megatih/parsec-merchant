// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// One row of the combat log (UI-ENC-021). Round rows carry their round number ("R3"); outcome and stance rows do not.
struct CombatLogLine: Equatable, Sendable {
    var round: Int?
    var text: String

    /// The row as shown and copied: "R3  You hit the Gnat. The Gnat missed you."
    var display: String { round.map { "R\($0)  \(text)" } ?? text }
}

/// UI-ENC-023: an outcome line is a log line without a round.
typealias CombatLogEntry = CombatLogLine

/// UI-ENC-022/023: builds the combat log from a step record, reusing the C# encounter strings (Strings.cs:74-83) with a
/// "(−N hull)" suffix for hull losses. Pure.
enum CombatLog {
    // MARK: C# wording

    /// C# `EncounterShipText`: the ship type name, or "Captain", or the pirate/police/trader noun forms.
    static func shipText(type: EncounterType, opponent: ShipType) -> String {
        switch type {
        case .famousCaptainAttack, .famousCaptDisabled:
            String(localized: "Captain")
        case .pirateAttack, .pirateDisabled, .pirateFlee, .pirateSurrender:
            if opponent == .mantis { String(localized: "alien ship") } else { String(localized: "pirate ship") }
        case .policeAttack, .policeDisabled, .policeFlee:
            String(localized: "police ship")
        case .traderAttack, .traderDisabled, .traderFlee, .traderSurrender:
            String(localized: "trader ship")
        case .bottleGood, .bottleOld, .captainAhab, .captainConrad, .captainHuie, .dragonflyAttack, .dragonflyIgnore, .marieCeleste,
             .marieCelestePolice, .pirateIgnore, .policeIgnore, .policeInspect, .policeSurrender, .scarabAttack, .scarabIgnore,
             .scorpionAttack, .scorpionIgnore, .spaceMonsterAttack, .spaceMonsterIgnore, .traderIgnore, .traderBuy, .traderSell:
            String(localized: Names.ship(opponent))
        }
    }

    /// C# `EncounterText`, first line: the player's side of the round.
    static func playerSentence(cmdrFleeing: Bool, opponentHit: Bool, ship: String) -> String {
        if cmdrFleeing { return String(localized: "The \(ship) is still following you.") }
        return opponentHit ? String(localized: "You hit the \(ship).") : String(localized: "You missed the \(ship).")
    }

    /// C# `EncounterText`, second line: the opponent's side of the round.
    static func opponentSentence(oppFleeingPrev: Bool, playerHit: Bool, ship: String) -> String {
        if oppFleeingPrev { return String(localized: "The \(ship) didn't get away.") }
        return playerHit ? String(localized: "The \(ship) hits you.") : String(localized: "The \(ship) missed you.")
    }

    /// C# `EncounterAction`: the opponent's stance after a round.
    static func stance(type: EncounterType, opponent: ShipType, disabled: Bool, oppFleeing: Bool) -> String {
        let ship = shipText(type: type, opponent: opponent)
        if disabled { return String(localized: "The \(ship) has been disabled.") }
        if oppFleeing {
            if type == .pirateSurrender || type == .traderSurrender {
                return String(localized: "The \(ship) hails that they wish to surrender to you.")
            }
            return String(localized: "The \(ship) is fleeing.")
        }
        return String(localized: "The \(ship) attacks.")
    }

    static func stance(_ enc: EncounterState) -> String {
        stance(type: enc.type, opponent: enc.opponent.type, disabled: enc.opponentDisabled, oppFleeing: enc.oppFleeing)
    }

    /// "(−12 hull)".
    static func hullLoss(_ loss: Int) -> String { String(localized: "(−\(loss) hull)") }

    static func isFleeOrSurrender(_ t: EncounterType) -> Bool {
        [.pirateFlee, .pirateSurrender, .policeFlee, .traderFlee, .traderSurrender].contains(t)
    }

    static func isDisabledType(_ t: EncounterType) -> Bool {
        [.pirateDisabled, .policeDisabled, .traderDisabled, .famousCaptDisabled].contains(t)
    }

    // MARK: Step → lines (UI-ENC-022)

    /// The log lines of one step, for the encounter in progress after the step. Events before a new
    /// `encounterStarted` in the same step belong to the previous encounter and are skipped.
    static func lines(for step: StepRecord) -> [CombatLogLine] {
        let events = step.events
        let startIndex = events.lastIndex { if case .encounterStarted = $0 { true } else { false } }
        let slice = startIndex.map { Array(events[($0 + 1)...]) } ?? events
        // The encounter before the step is this one only when the step started none.
        let beforeEnc: EncounterState? = if startIndex == nil, case let .encounter(e) = step.before.phase { e } else { nil }
        let afterEnc: EncounterState? = if case let .encounter(e) = step.after.phase { e } else { nil }
        if startIndex == nil, afterEnc == nil, beforeEnc == nil { return [] }
        let shipEnc = afterEnc ?? beforeEnc
        let ship = shipEnc.map { shipText(type: $0.type, opponent: $0.opponent.type) } ?? ""
        let sameEncounterAfter = startIndex == nil ? afterEnc : nil
        let cmdrFleeing: Bool = if let sameEncounterAfter {
            sameEncounterAfter.cmdrFleeing
        } else {
            switch step.command {
            case .encounter(.flee): true
            case .encounter(.autoRepeat): (beforeEnc?.cmdrFleeing ?? false) || (beforeEnc?.continueFleeing ?? false)
            default: false
            }
        }
        let oppFleeingPrev = beforeEnc?.oppFleeing ?? false
        var prevPlayerHull = step.before.commander.ship.hull
        var prevOppHull = beforeEnc?.opponent.hull
        var lines: [CombatLogLine] = []
        var hadRound = false
        for event in slice {
            if case let .combatRound(round, playerHit, opponentHit, playerHull, opponentHull) = event {
                hadRound = true
                var first = playerSentence(cmdrFleeing: cmdrFleeing, opponentHit: opponentHit, ship: ship)
                if let prev = prevOppHull, prev > opponentHull { first += " " + hullLoss(prev - opponentHull) }
                var second = opponentSentence(oppFleeingPrev: oppFleeingPrev, playerHit: playerHit, ship: ship)
                if prevPlayerHull > playerHull { second += " " + hullLoss(prevPlayerHull - playerHull) }
                prevPlayerHull = playerHull
                prevOppHull = opponentHull
                lines.append(CombatLogLine(round: round, text: first + " " + second))
                continue
            }
            if case .encounterChanged = event, hadRound { continue }
            if let entry = entry(for: event, state: step.after) { lines.append(entry) }
        }
        if hadRound, let sameEncounterAfter { lines.append(CombatLogLine(round: nil, text: stance(sameEncounterAfter))) }
        return lines
    }

    // MARK: Event → outcome line (UI-ENC-023)

    /// The log line of an outcome event, or nil for events the log does not show. Exhaustive, no `default`.
    static func entry(for event: GameEvent, state: GameState) -> CombatLogEntry? {
        func outcome() -> CombatLogEntry { CombatLogLine(round: nil, text: String(localized: EventText.text(for: event, state: state))) }
        switch event {
        case let .encounterChanged(type):
            let opponent: ShipType = if case let .encounter(e) = state.phase { e.opponent.type } else { state.lastOpponent?.type ?? .gnat }
            return CombatLogLine(round: nil, text: stance(type: type, opponent: opponent, disabled: isDisabledType(type),
                                                          oppFleeing: isFleeOrSurrender(type)))
        // Combat outcomes.
        case .opponentDisabled, .opponentDestroyed, .opponentEscaped, .playerEscaped, .playerDestroyed, .bothDestroyed, .escapePodUsed,
             .bountyPaid:
            return outcome()
        // Scoop and plunder.
        case .scooped, .scoopNoRoom, .plundered:
            return outcome()
        // Police.
        case .bribed, .fined, .inspectionClean, .yielded, .reactorConfiscated, .arrested:
            return outcome()
        // Pirate raids.
        case .looted, .blackmailed, .sculptureTaken, .preciousHidden, .wildJoinedPirates, .artifactRelinquished:
            return outcome()
        // Very rare encounters and trade.
        case .tonicConsumed, .captainTraining, .orbitTradeCompleted:
            return outcome()
        // The round itself is built by `lines(for:)`; everything else is not a combat-log line.
        case .combatRound, .gameStarted, .boughtCargo, .soldCargo, .dumpedCargo, .jettisonedCargo, .caughtLittering, .boughtFuel,
             .repairedHull, .boughtEquipment, .soldEquipment, .boughtShip, .cannotTransfer, .cannotAffordTransfer,
             .cannotAffordAllTransfers, .customShipBuilt, .departed, .fabricRip, .encounterStarted, .uneventfulTrip, .arrived,
             .debtWarning, .debtReminder, .reactorWarning, .reactorMeltdown, .tribblesChanged, .tribblesDied, .tribblesAteFood,
             .tribbleInspectorWarning, .passengerConcerned, .passengerImpatient, .autoFuelFailed, .autoRepairFailed, .easterEgg,
             .easterEggNoShieldSlot, .wildLeftShip, .singularityLost, .departureBlocked, .gemulonInvaded, .experimentPerformed,
             .playerAttacked, .playerFled, .boughtEscapePod, .hired, .fired, .borrowed, .repaid, .insuranceBought,
             .insuranceStopped, .optionsChanged, .specialEventCompleted, .specialEventRefused, .sealedCanisters, .gameEnded,
             .cheatUsed, .cheatReadout:
            return nil
        }
    }
}
