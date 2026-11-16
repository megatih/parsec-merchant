// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// Localized inline reasons for every `CommandError` (UI-SHELL-007). Shown in help tags, footers and the status bar.
enum ReasonText {
    // An exhaustive mapping over every engine error: one line per case, so the case count is the complexity.
    // swiftlint:disable:next cyclomatic_complexity
    static func text(for error: CommandError) -> LocalizedStringResource {
        switch error {
        case .notAllowedInPhase: "Not possible right now."
        case .pendingDecisionFirst: "Finish the current decision first."
        case .invalidArgument: "That choice isn't valid."
        case .debtTooLargeToTrade: "Your debt is too large to trade."
        case .cargoNoneAvailable: "None available here."
        case .noEmptyBays: "No empty cargo bays."
        case .insufficientFunds: "Not enough cash."
        case .invalidQuantity: "Enter a valid quantity."
        case .cargoNoneToSell: "You have none to sell."
        case .marketNotInterested: "Nobody here buys this."
        case .tankFull: "Tank full."
        case .noRepairsNeeded: "No repairs needed."
        case .notSoldHere: "Not sold here."
        case .inDebt: "Pay off your debt first."
        case .noFreeSlot: "No free slot."
        case .equipmentAlreadyOwned: "You already have one."
        case .extraBaysInUse: "The extra bays are in use."
        case .notEnoughQuarters: "Not enough crew quarters."
        case .passengersNeedQuarters: "Your passengers need quarters."
        case .reactorOnBoard: "Not while the reactor is aboard."
        case .alreadyHaveEscapePod: "Escape pod installed."
        case .escapePodNotAvailable: "No escape pods for sale here."
        case .alreadyOwnThisShipType: "You already fly this type."
        case .designNameEmpty: "Enter a ship name."
        case .designOverCapacity: "Over 100% of the maximum units."
        case .debtTooLargeForLoan: "Your debt is too large for another loan."
        case .noDebt: "You have no debt."
        case .invalidAmount: "Enter a valid amount."
        case .exceedsAvailableLoan: "More than the bank will lend."
        case .exceedsRepayable: "More than you can repay."
        case .insuranceRequiresEscapePod: "Requires an escape pod."
        case .insuranceAlreadyActive: "Already insured."
        case .insuranceNotActive: "Not insured."
        case .notForHire: "Not for hire."
        case .commanderNameRequired: "Enter a name."
        case .commanderNameTooLong: "At most 20 characters."
        case .invalidSkillAllocation: "Distribute all points."
        case .noFreeQuarters: "No free quarters."
        case .notInCrew: "Not in your crew."
        case .cannotFireSpecialPassenger: "Passengers can't be fired."
        case .gameOver: "The game is over."
        case .debtTooLargeToTravel: "Your debt is too large to travel."
        case .cannotPayMercenaries: "You can't pay your mercenaries."
        case .cannotPayInsurance: "You can't pay your insurance."
        case .cannotPayWormholeTax: "You can't pay the wormhole tax."
        case .destinationOutOfRange: "Out of range."
        case .noSingularity: "You have no singularity."
        case .singularityTargetIsCurrentSystem: "Choose another system to jump to."
        case .singularityNoTarget: "Track a system to jump to."
        case .wormholeNotAtCurrentSystem: "That wormhole isn't here."
        case .noWeapons: "You have no weapons."
        case .noLasers: "You need a laser for this."
        case .noDisruptors: "You need a disruptor for this."
        case .surrenderRefused: "They won't accept your surrender."
        case .surrenderPrincess: "You can't surrender with the Princess aboard."
        case .bribeNotAccepted: "These police don't take bribes."
        case .bribeNotPossible: "A bribe isn't possible now."
        case .encounterActionUnavailable: "Not available in this encounter."
        case .noSpecialEvent: "Nothing special here."
        case .wildRequiresLaser: "Wild boards only with a beam laser or better."
        case .wildRefusesReactor: "Wild won't board while the reactor is aboard."
        }
    }

    /// Convenience for help tags and `Text`.
    static func string(for error: CommandError) -> String { String(localized: text(for: error)) }
}
