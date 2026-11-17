// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// UI-ENC-004: where an event's outcome is shown (ALR §4 "New presentation"). Every event also reaches the feed
/// (UI-SHELL-008); the Captain's Log mirrors the feed from M10.
enum EventSurface: String, CaseIterable, Sendable {
    case feed, combatLog, arrivalReport, reportSheet, gameOverCard, narrativeResult, transitBanner, comm
}

/// UI-ENC-004: the surfaces of every `GameEvent` case. Exhaustive, no `default`.
enum EventSurfaces {
    static func surfaces(for event: GameEvent) -> Set<EventSurface> {
        var s: Set<EventSurface> = [.feed]
        switch event {
        // Docked, economy, crew, bank, options and cheats: the feed only.
        case .gameStarted, .boughtCargo, .soldCargo, .dumpedCargo, .jettisonedCargo, .boughtEquipment, .soldEquipment,
             .boughtShip, .cannotTransfer, .cannotAffordTransfer, .cannotAffordAllTransfers, .customShipBuilt,
             .boughtEscapePod, .hired, .fired, .borrowed, .repaid, .insuranceBought, .insuranceStopped, .optionsChanged,
             .cheatUsed, .cheatReadout, .departureBlocked, .singularityLost, .departed, .arrived, .encounterStarted,
             .playerAttacked, .playerFled:
            break
        // Combat rounds and stance changes: the combat log (UI-ENC-022/023).
        case .combatRound, .encounterChanged:
            s.insert(.combatLog)
        // Encounter outcomes: combat log, then the arrival report's encounter summary (UI-ENC-023, -052).
        case .opponentDisabled, .opponentDestroyed, .opponentEscaped, .playerEscaped, .bountyPaid, .scooped, .plundered,
             .bribed, .fined, .inspectionClean, .yielded, .reactorConfiscated, .looted, .blackmailed, .sculptureTaken,
             .preciousHidden, .wildJoinedPirates, .artifactRelinquished, .tonicConsumed, .captainTraining,
             .orbitTradeCompleted:
            s.formUnion([.combatLog, .arrivalReport])
        case .scoopNoRoom:
            s.insert(.combatLog)
        // Endings during combat: combat log, then the game-over card (ALR-043, ALR-077).
        case .playerDestroyed, .bothDestroyed:
            s.formUnion([.combatLog, .gameOverCard])
        // Critical steps: the report sheet (UI-ENC-056, -058).
        case .arrested, .escapePodUsed:
            s.formUnion([.combatLog, .reportSheet])
        case .reactorMeltdown:
            s.formUnion([.reportSheet, .gameOverCard])
        case let .reactorWarning(status):
            s.insert(status == ReactorStatus.temperatureWarning ? .reportSheet : .arrivalReport)
        case .gameEnded:
            s.insert(.gameOverCard)
        // Arrival report sections (UI-ENC-054).
        case .uneventfulTrip, .boughtFuel, .repairedHull, .autoFuelFailed, .autoRepairFailed, .tribblesChanged,
             .tribblesDied, .tribblesAteFood, .tribbleInspectorWarning, .debtWarning, .debtReminder, .caughtLittering,
             .gemulonInvaded, .experimentPerformed, .wildLeftShip, .easterEgg, .easterEggNoShieldSlot:
            s.insert(.arrivalReport)
        case .fabricRip:
            s.formUnion([.arrivalReport, .transitBanner])
        // Passenger chatter: a "Ship's comm" line (UI-ENC-066) and the arrival report's quest section.
        case .passengerConcerned, .passengerImpatient:
            s.formUnion([.comm, .arrivalReport])
        // Special-event results: the narrative result page (UI-ENC-077/078).
        case .specialEventCompleted, .specialEventRefused, .sealedCanisters:
            s.insert(.narrativeResult)
        }
        return s
    }
}
