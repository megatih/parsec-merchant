// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import Testing
@testable import ParsecMerchant

/// One fixture value per case of the engine enums the text functions cover.
enum TextFixtures {
    static let errors: [CommandError] = [
        .notAllowedInPhase, .pendingDecisionFirst, .invalidArgument, .debtTooLargeToTrade, .cargoNoneAvailable, .noEmptyBays,
        .insufficientFunds, .invalidQuantity, .cargoNoneToSell, .marketNotInterested, .tankFull, .noRepairsNeeded, .notSoldHere,
        .inDebt, .noFreeSlot, .equipmentAlreadyOwned, .extraBaysInUse, .notEnoughQuarters, .passengersNeedQuarters,
        .reactorOnBoard, .alreadyHaveEscapePod, .escapePodNotAvailable, .alreadyOwnThisShipType, .designNameEmpty,
        .designOverCapacity, .debtTooLargeForLoan, .noDebt, .invalidAmount, .exceedsAvailableLoan, .exceedsRepayable,
        .insuranceRequiresEscapePod, .insuranceAlreadyActive, .insuranceNotActive, .notForHire, .commanderNameRequired,
        .commanderNameTooLong, .invalidSkillAllocation, .noFreeQuarters, .notInCrew, .cannotFireSpecialPassenger, .gameOver,
        .debtTooLargeToTravel, .cannotPayMercenaries, .cannotPayInsurance, .cannotPayWormholeTax, .destinationOutOfRange,
        .noSingularity, .singularityTargetIsCurrentSystem, .singularityNoTarget, .wormholeNotAtCurrentSystem, .noWeapons,
        .noLasers, .noDisruptors, .surrenderRefused, .surrenderPrincess, .bribeNotAccepted, .bribeNotPossible,
        .encounterActionUnavailable, .noSpecialEvent, .wildRequiresLaser, .wildRefusesReactor,
    ]

    static let events: [GameEvent] = [
        .gameStarted(ruleset: .modern, seed: 1), .boughtCargo(item: .food, quantity: 2, total: 60),
        .soldCargo(item: .food, quantity: 2, total: 80, profit: 20), .dumpedCargo(item: .ore, quantity: 1, cost: 5),
        .jettisonedCargo(item: .ore, quantity: 1), .caughtLittering(newRecord: -1), .boughtFuel(units: 3, cost: 6),
        .repairedHull(points: 4, cost: 8), .boughtEquipment(price: 100), .soldEquipment(price: 75),
        .boughtShip(type: .firefly, netPrice: 20_000), .cannotTransfer(.escapePod), .cannotAffordTransfer(.fuelCompactor),
        .cannotAffordAllTransfers, .customShipBuilt(shipyard: .corellian),
        .combatRound(round: 1, playerHit: true, opponentHit: false, playerHull: 90, opponentHull: 100),
        .playerDestroyed, .bothDestroyed, .opponentDestroyed(.gnat), .opponentDisabled(.gnat), .playerEscaped(wasHit: true),
        .opponentEscaped, .encounterChanged(.pirateFlee), .bountyPaid(500), .departed(from: 0, to: 1, viaWormhole: false),
        .fabricRip(newDestination: 2), .encounterStarted(type: .pirateAttack, opponent: .gnat, clicks: 7, playerCloaked: false),
        .uneventfulTrip, .arrived(system: 3), .debtWarning(debt: 80_000), .debtReminder(debt: 1_000), .reactorWarning(status: 5),
        .reactorMeltdown, .tribblesChanged(from: 1, to: 2), .tribblesDied(.allFromReactor), .tribblesDied(.halfFromReactor),
        .tribblesDied(.narcotics(converted: 3)), .tribblesAteFood(eaten: 2), .tribbleInspectorWarning(count: 100_000),
        .passengerConcerned(crewID: CrewID.wild), .passengerImpatient(crewID: CrewID.jarek), .autoFuelFailed, .autoRepairFailed,
        .easterEgg, .easterEggNoShieldSlot, .escapePodUsed(insurancePayout: 9_000), .wildLeftShip, .singularityLost,
        .departureBlocked(.cannotPayInsurance), .gemulonInvaded, .experimentPerformed, .playerAttacked, .playerFled,
        .artifactRelinquished, .preciousHidden, .sculptureTaken, .blackmailed(100), .looted(units: 4), .wildJoinedPirates,
        .bribed(250), .fined(300), .inspectionClean, .reactorConfiscated, .yielded, .tonicConsumed(good: true),
        .captainTraining(skill: .fighter), .plundered(item: .games, quantity: 3), .scooped(.water), .scoopNoRoom,
        .arrested(term: 30, fine: 1_000, shipSold: false), .boughtEscapePod(price: 2_000), .hired(crewID: 5), .fired(crewID: 5),
        .borrowed(amount: 500), .repaid(amount: 500), .insuranceBought, .insuranceStopped, .optionsChanged,
        .orbitTradeCompleted(direction: .traderSells, item: .robots, quantity: 1, total: 4_000),
        .specialEventCompleted(.lottery), .specialEventRefused(.sculptureHiddenBays, reason: .noFreeSlot),
        .sealedCanisters(.robots), .gameEnded(.retired, score: 123), .cheatUsed, .cheatReadout(.remainingVeryRare([])),
    ]

    /// The case name of an encoded enum value (its single JSON key).
    static func caseName<T: Encodable>(_ v: T) -> String {
        guard let data = try? JSONEncoder().encode(v),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return "" }
        if let dict = obj as? [String: Any] { return dict.keys.first ?? "" }
        return "\(obj)"
    }
}

@MainActor
@Suite("Engine text")
struct TextTests {
    private func state() -> GameState { GameState(config: NewGameConfig(commanderName: "Text", seed: 1)) }

    @Test("UI-SHELL-007 ReasonText covers every CommandError with a non-empty English string")
    func reasons() {
        #expect(Set(TextFixtures.errors.map(TextFixtures.caseName)).count == TextFixtures.errors.count)
        for e in TextFixtures.errors {
            #expect(!ReasonText.string(for: e).isEmpty, "\(e)")
        }
        #expect(ReasonText.string(for: .commanderNameRequired) == "Enter a name.")
        #expect(ReasonText.string(for: .insufficientFunds) == "Not enough cash.")
    }

    @Test("UI-SHELL-007 ConfirmationText covers every WarningID; isDestructive matches the ALR (destructive) rows")
    func confirmations() {
        let destructive: Set<WarningID> = [.fireMercenary, .surrenderArtifact, .attackCaptain, .attackPolice, .attackTrader,
                                           .litteringWarning, .submitWithNothingIllegal, .fleeInspection, .surrenderToPolice,
                                           .fleeMariePolice, .retire, .stopInsurance, .wildLeavesWithoutLaser, .wildLeavesForReactor]
        let s = state()
        for w in WarningID.allCases {
            let c = ConfirmationText.content(for: Confirmation(w, amounts: [1_234, 56]), state: s)
            #expect(!c.title.isEmpty && !c.message.isEmpty && !c.confirmLabel.isEmpty, "\(w)")
            #expect(c.isDestructive == destructive.contains(w), "\(w)")
        }
        let bribe = ConfirmationText.content(for: Confirmation(.bribe, amounts: [1_234]), state: s)
        #expect(bribe.confirmLabel.contains("1,234"))
        let retire = ConfirmationText.content(for: Confirmation(.retire, amounts: [123]), state: s)
        #expect(retire.message.contains("12.3%"))
        let jump = ConfirmationText.content(for: Confirmation(.useSingularity, amounts: [4]), state: s)
        #expect(jump.confirmLabel.contains(Names.system(4, in: s)))
    }

    @Test("UI-SHELL-007 EventText covers every GameEvent with a non-empty English string")
    func events() {
        let s = state()
        #expect(Set(TextFixtures.events.map(TextFixtures.caseName)).count >= 80)
        for e in TextFixtures.events {
            #expect(!String(localized: EventText.text(for: e, state: s)).isEmpty, "\(e)")
        }
        #expect(String(localized: EventText.text(for: .arrived(system: 3), state: s)) == "Arrived at \(Names.system(3, in: s)).")
        #expect(String(localized: EventText.text(for: .note(.gameSaved), state: s)) == "Game saved.")
    }
}
