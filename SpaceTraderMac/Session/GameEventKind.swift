// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// UI-ENC-004: every `GameEvent` case without its payload, with one fixture per case. The `init` is an exhaustive
/// `switch` with no `default`, so a new engine event fails to compile until it is presented.
enum GameEventKind: String, CaseIterable, Sendable {
    case gameStarted, boughtCargo, soldCargo, dumpedCargo, jettisonedCargo, caughtLittering, boughtFuel
    case repairedHull, boughtEquipment, soldEquipment, boughtShip, cannotTransfer, cannotAffordTransfer
    case cannotAffordAllTransfers, customShipBuilt, combatRound, playerDestroyed, bothDestroyed, opponentDestroyed
    case opponentDisabled, playerEscaped, opponentEscaped, encounterChanged, bountyPaid, departed, fabricRip
    case encounterStarted, uneventfulTrip, arrived, debtWarning, debtReminder, reactorWarning, reactorMeltdown
    case tribblesChanged, tribblesDied, tribblesAteFood, tribbleInspectorWarning, passengerConcerned
    case passengerImpatient, autoFuelFailed, autoRepairFailed, easterEgg, easterEggNoShieldSlot, escapePodUsed
    case wildLeftShip, singularityLost, departureBlocked, gemulonInvaded, experimentPerformed, playerAttacked
    case playerFled, artifactRelinquished, preciousHidden, sculptureTaken, blackmailed, looted, wildJoinedPirates
    case bribed, fined, inspectionClean, reactorConfiscated, yielded, tonicConsumed, captainTraining, plundered
    case scooped, scoopNoRoom, arrested, boughtEscapePod, hired, fired, borrowed, repaid, insuranceBought
    case insuranceStopped, optionsChanged, orbitTradeCompleted, specialEventCompleted, specialEventRefused
    case sealedCanisters, gameEnded, cheatUsed, cheatReadout

    // An exhaustive mapping over every engine event: one line per case, so the case count is the complexity.
    // swiftlint:disable:next cyclomatic_complexity
    init(_ event: GameEvent) {
        switch event {
        case .gameStarted: self = .gameStarted
        case .boughtCargo: self = .boughtCargo
        case .soldCargo: self = .soldCargo
        case .dumpedCargo: self = .dumpedCargo
        case .jettisonedCargo: self = .jettisonedCargo
        case .caughtLittering: self = .caughtLittering
        case .boughtFuel: self = .boughtFuel
        case .repairedHull: self = .repairedHull
        case .boughtEquipment: self = .boughtEquipment
        case .soldEquipment: self = .soldEquipment
        case .boughtShip: self = .boughtShip
        case .cannotTransfer: self = .cannotTransfer
        case .cannotAffordTransfer: self = .cannotAffordTransfer
        case .cannotAffordAllTransfers: self = .cannotAffordAllTransfers
        case .customShipBuilt: self = .customShipBuilt
        case .combatRound: self = .combatRound
        case .playerDestroyed: self = .playerDestroyed
        case .bothDestroyed: self = .bothDestroyed
        case .opponentDestroyed: self = .opponentDestroyed
        case .opponentDisabled: self = .opponentDisabled
        case .playerEscaped: self = .playerEscaped
        case .opponentEscaped: self = .opponentEscaped
        case .encounterChanged: self = .encounterChanged
        case .bountyPaid: self = .bountyPaid
        case .departed: self = .departed
        case .fabricRip: self = .fabricRip
        case .encounterStarted: self = .encounterStarted
        case .uneventfulTrip: self = .uneventfulTrip
        case .arrived: self = .arrived
        case .debtWarning: self = .debtWarning
        case .debtReminder: self = .debtReminder
        case .reactorWarning: self = .reactorWarning
        case .reactorMeltdown: self = .reactorMeltdown
        case .tribblesChanged: self = .tribblesChanged
        case .tribblesDied: self = .tribblesDied
        case .tribblesAteFood: self = .tribblesAteFood
        case .tribbleInspectorWarning: self = .tribbleInspectorWarning
        case .passengerConcerned: self = .passengerConcerned
        case .passengerImpatient: self = .passengerImpatient
        case .autoFuelFailed: self = .autoFuelFailed
        case .autoRepairFailed: self = .autoRepairFailed
        case .easterEgg: self = .easterEgg
        case .easterEggNoShieldSlot: self = .easterEggNoShieldSlot
        case .escapePodUsed: self = .escapePodUsed
        case .wildLeftShip: self = .wildLeftShip
        case .singularityLost: self = .singularityLost
        case .departureBlocked: self = .departureBlocked
        case .gemulonInvaded: self = .gemulonInvaded
        case .experimentPerformed: self = .experimentPerformed
        case .playerAttacked: self = .playerAttacked
        case .playerFled: self = .playerFled
        case .artifactRelinquished: self = .artifactRelinquished
        case .preciousHidden: self = .preciousHidden
        case .sculptureTaken: self = .sculptureTaken
        case .blackmailed: self = .blackmailed
        case .looted: self = .looted
        case .wildJoinedPirates: self = .wildJoinedPirates
        case .bribed: self = .bribed
        case .fined: self = .fined
        case .inspectionClean: self = .inspectionClean
        case .reactorConfiscated: self = .reactorConfiscated
        case .yielded: self = .yielded
        case .tonicConsumed: self = .tonicConsumed
        case .captainTraining: self = .captainTraining
        case .plundered: self = .plundered
        case .scooped: self = .scooped
        case .scoopNoRoom: self = .scoopNoRoom
        case .arrested: self = .arrested
        case .boughtEscapePod: self = .boughtEscapePod
        case .hired: self = .hired
        case .fired: self = .fired
        case .borrowed: self = .borrowed
        case .repaid: self = .repaid
        case .insuranceBought: self = .insuranceBought
        case .insuranceStopped: self = .insuranceStopped
        case .optionsChanged: self = .optionsChanged
        case .orbitTradeCompleted: self = .orbitTradeCompleted
        case .specialEventCompleted: self = .specialEventCompleted
        case .specialEventRefused: self = .specialEventRefused
        case .sealedCanisters: self = .sealedCanisters
        case .gameEnded: self = .gameEnded
        case .cheatUsed: self = .cheatUsed
        case .cheatReadout: self = .cheatReadout
        }
    }

    /// One representative event of this kind (UI-ENC-004 fixtures; the developer tester's samples, UI-ENC-092).
    var fixture: GameEvent {
        switch self {
        case .gameStarted: .gameStarted(ruleset: .modern, seed: 1)
        case .boughtCargo: .boughtCargo(item: .water, quantity: 2, total: 60)
        case .soldCargo: .soldCargo(item: .water, quantity: 2, total: 80, profit: 20)
        case .dumpedCargo: .dumpedCargo(item: .water, quantity: 1, cost: 10)
        case .jettisonedCargo: .jettisonedCargo(item: .water, quantity: 1)
        case .caughtLittering: .caughtLittering(newRecord: -5)
        case .boughtFuel: .boughtFuel(units: 5, cost: 10)
        case .repairedHull: .repairedHull(points: 5, cost: 10)
        case .boughtEquipment: .boughtEquipment(price: 2000)
        case .soldEquipment: .soldEquipment(price: 1000)
        case .boughtShip: .boughtShip(type: .firefly, netPrice: 20000)
        case .cannotTransfer: .cannotTransfer(.escapePod)
        case .cannotAffordTransfer: .cannotAffordTransfer(.escapePod)
        case .cannotAffordAllTransfers: .cannotAffordAllTransfers
        case .customShipBuilt: .customShipBuilt(shipyard: .corellian)
        case .combatRound: .combatRound(round: 1, playerHit: true, opponentHit: true, playerHull: 80, opponentHull: 40)
        case .playerDestroyed: .playerDestroyed
        case .bothDestroyed: .bothDestroyed
        case .opponentDestroyed: .opponentDestroyed(.gnat)
        case .opponentDisabled: .opponentDisabled(.gnat)
        case .playerEscaped: .playerEscaped(wasHit: false)
        case .opponentEscaped: .opponentEscaped
        case .encounterChanged: .encounterChanged(.pirateFlee)
        case .bountyPaid: .bountyPaid(250)
        case .departed: .departed(from: 0, to: 1, viaWormhole: false)
        case .fabricRip: .fabricRip(newDestination: 2)
        case .encounterStarted: .encounterStarted(type: .pirateAttack, opponent: .gnat, clicks: 7, playerCloaked: false)
        case .uneventfulTrip: .uneventfulTrip
        case .arrived: .arrived(system: 1)
        case .debtWarning: .debtWarning(debt: 80_000)
        case .debtReminder: .debtReminder(debt: 1000)
        case .reactorWarning: .reactorWarning(status: 2)
        case .reactorMeltdown: .reactorMeltdown
        case .tribblesChanged: .tribblesChanged(from: 10, to: 20)
        case .tribblesDied: .tribblesDied(.allFromReactor)
        case .tribblesAteFood: .tribblesAteFood(eaten: 3)
        case .tribbleInspectorWarning: .tribbleInspectorWarning(count: 100_000)
        case .passengerConcerned: .passengerConcerned(crewID: CrewID.jarek)
        case .passengerImpatient: .passengerImpatient(crewID: CrewID.jarek)
        case .autoFuelFailed: .autoFuelFailed
        case .autoRepairFailed: .autoRepairFailed
        case .easterEgg: .easterEgg
        case .easterEggNoShieldSlot: .easterEggNoShieldSlot
        case .escapePodUsed: .escapePodUsed(insurancePayout: 0)
        case .wildLeftShip: .wildLeftShip
        case .singularityLost: .singularityLost
        case .departureBlocked: .departureBlocked(.cannotPayMercenaries)
        case .gemulonInvaded: .gemulonInvaded
        case .experimentPerformed: .experimentPerformed
        case .playerAttacked: .playerAttacked
        case .playerFled: .playerFled
        case .artifactRelinquished: .artifactRelinquished
        case .preciousHidden: .preciousHidden
        case .sculptureTaken: .sculptureTaken
        case .blackmailed: .blackmailed(500)
        case .looted: .looted(units: 5)
        case .wildJoinedPirates: .wildJoinedPirates
        case .bribed: .bribed(500)
        case .fined: .fined(300)
        case .inspectionClean: .inspectionClean
        case .reactorConfiscated: .reactorConfiscated
        case .yielded: .yielded
        case .tonicConsumed: .tonicConsumed(good: true)
        case .captainTraining: .captainTraining(skill: .pilot)
        case .plundered: .plundered(item: .furs, quantity: 2)
        case .scooped: .scooped(.water)
        case .scoopNoRoom: .scoopNoRoom
        case .arrested: .arrested(term: 30, fine: 500, shipSold: false)
        case .boughtEscapePod: .boughtEscapePod(price: 2000)
        case .hired: .hired(crewID: 1)
        case .fired: .fired(crewID: 1)
        case .borrowed: .borrowed(amount: 500)
        case .repaid: .repaid(amount: 500)
        case .insuranceBought: .insuranceBought
        case .insuranceStopped: .insuranceStopped
        case .optionsChanged: .optionsChanged
        case .orbitTradeCompleted: .orbitTradeCompleted(direction: .traderSells, item: .ore, quantity: 3, total: 300)
        case .specialEventCompleted: .specialEventCompleted(.moon)
        case .specialEventRefused: .specialEventRefused(.sculptureHiddenBays, reason: .noFreeSlot)
        case .sealedCanisters: .sealedCanisters(.robots)
        case .gameEnded: .gameEnded(.retired, score: 123)
        case .cheatUsed: .cheatUsed
        case .cheatReadout: .cheatReadout(.remainingVeryRare([]))
        }
    }
}
