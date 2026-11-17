// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// The localized content of a confirmation dialog.
struct ConfirmationContent: Equatable {
    var title: String
    var message: String
    var confirmLabel: String
    /// Matches the ALR §4 "(destructive)" marking; Cancel is then the default action.
    var isDestructive: Bool
}

/// Text for every engine `WarningID` (UI-SHELL-007, ALR §4 "New presentation" column).
enum ConfirmationText {
    /// The ALR rows marked "(destructive)".
    static func isDestructive(_ w: WarningID) -> Bool {
        switch w {
        case .attackPolice, .attackTrader, .attackCaptain, .fleeInspection, .fleeMariePolice, .submitWithNothingIllegal,
             .surrenderToPolice, .fireMercenary, .stopInsurance, .wildLeavesWithoutLaser, .wildLeavesForReactor,
             .litteringWarning, .retire, .surrenderArtifact:
            true
        case .bribe, .buyEquipment, .sellEquipment, .buyShip, .useSingularity, .jettisonAll, .drinkTonic,
             .boardMarieCeleste, .meetCaptain, .buyEscapePod, .acceptSpecialEvent, .submitInspection, .buyNewspaper:
            false
        }
    }

    static func content(for c: Confirmation, state: GameState) -> ConfirmationContent {
        let (title, message, label) = strings(for: c, state: state)
        return ConfirmationContent(title: String(localized: title), message: String(localized: message),
                                   confirmLabel: String(localized: label), isDestructive: isDestructive(c.warning))
    }

    private static func credits(_ n: Int) -> String { n.formatted() }

    private static func strings(for c: Confirmation, state: GameState)
        -> (LocalizedStringResource, LocalizedStringResource, LocalizedStringResource) {
        let a0 = c.amounts.first ?? 0
        let a1 = c.amounts.count > 1 ? c.amounts[1] : 0
        switch c.warning {
        case .attackPolice:
            return ("Attack the Police?", "Your police record will drop to \(recordWord(a0)).", "Attack")
        case .attackTrader:
            return ("Attack the Trader?", "Attacking a peaceful trader is a crime. Your police record will drop to \(recordWord(a0)).", "Attack")
        case .attackCaptain:
            return ("Really Attack?", "Famous captains are well loved. Your record drops to Villain and the news will report it.", "Attack")
        case .fleeInspection, .submitWithNothingIllegal:
            return ("You Have Nothing Illegal", "You carry nothing illegal, so submitting costs you nothing. Do it anyway?", "Do It Anyway")
        case .fleeMariePolice:
            return ("Criminal Act!", "Fleeing the customs police is a criminal act and will be reported.", "Flee")
        case .surrenderToPolice:
            return ("Surrender?", "The police will confiscate illegal cargo and passengers, and you'll be arrested.", "Surrender")
        case .bribe:
            return ("Bribe the Police?", "These police will let you go for \(credits(a0)) credits.", "Pay \(credits(a0)) cr.")
        case .buyEquipment:
            return ("Buy Equipment?", "This costs \(credits(a0)) credits.", "Buy for \(credits(a0)) cr.")
        case .sellEquipment:
            return ("Sell Equipment?", "You'll get \(credits(a0)) credits.", "Sell for \(credits(a0)) cr.")
        case .buyShip:
            return ("Buy This Ship?", "Net price \(credits(a0)) credits, plus \(credits(a1)) credits for transferred equipment.", "Buy Ship")
        case .fireMercenary:
            return ("Fire \(Names.crew(a0, in: state))?", "They'll leave your ship at this system.", "Fire")
        case .stopInsurance:
            return ("Stop Insurance?", "Your no-claim discount will be lost.", "Stop Insurance")
        case .wildLeavesWithoutLaser:
            return ("Wild Won't Stay Aboard", "Jonathan Wild won't travel without a beam laser or better. He'll leave the ship.", "Leave Without Wild")
        case .wildLeavesForReactor:
            return ("Wild Won't Stay Aboard", "Jonathan Wild won't stay aboard with the reactor. He'll leave the ship.", "Leave Wild Behind")
        case .litteringWarning:
            return ("Space Littering", "Dumping cargo in space is littering. The police may fine you and your record suffers.", "Jettison")
        case .useSingularity:
            return ("Use the Singularity?", "Jump to \(Names.system(a0, in: state)). The singularity is used up.", "Jump to \(Names.system(a0, in: state))")
        case .retire:
            return ("Retire?", "Retiring now scores \(tenths(a0, state: state))%.", "Retire")
        case .jettisonAll:
            return ("Jettison Everything?", "You paid \(credits(a0)) credits for these goods.", "Jettison")
        case .drinkTonic:
            return ("Drink the Contents?", "The bottle may hold a tonic, or something worse.", "Drink")
        case .boardMarieCeleste:
            return ("Board the Ship?", "The derelict seems deserted. Its cargo is yours for the taking.", "Take Cargo")
        case .meetCaptain:
            return ("Meet the Captain?", "The captain offers to trade equipment with you.", meetLabel(state))
        case .buyEscapePod:
            return ("Buy an Escape Pod?", "This costs \(credits(a0)) credits.", "Buy for \(credits(a0)) cr.")
        case .surrenderArtifact:
            return ("Surrender the Artifact?", "The aliens will take the artifact. Your quest ends here.", "Surrender Artifact")
        case .acceptSpecialEvent:
            return a0 > 0
                ? ("Accept the Offer?", "This costs \(credits(a0)) credits.", "Accept")
                : ("Accept the Offer?", "Do you want to accept?", "Accept")
        case .submitInspection:
            return ("Submit to Inspection?", "\(InspectionFindings.make(state: state).message)", "Submit")
        case .buyNewspaper:
            return ("Buy a Newspaper?", "The local paper costs \(credits(a0)) credits.", "Buy for \(credits(a0)) cr.")
        }
    }

    /// UI-ENC-030: the `PoliceRecordType` word for a record score ("Criminal").
    static func recordWord(_ score: Int) -> String {
        String(localized: Names.policeRecord(PoliceRecordType(score: score)))
    }

    /// UI-ENC-050 (ALR-121): Captain Ahab trades for a shield; Conrad and Huie for a laser.
    private static func meetLabel(_ state: GameState) -> LocalizedStringResource {
        if case let .encounter(enc) = state.phase, enc.type == .captainAhab { return "Trade Shield" }
        return "Trade Laser"
    }

    /// The dialog's cancel button (ALR-052, ALR-119…121: Leave It / Decline; otherwise Cancel).
    static func cancelLabel(for w: WarningID) -> String {
        switch w {
        case .boardMarieCeleste, .drinkTonic: String(localized: "Leave It")
        case .meetCaptain: String(localized: "Decline")
        case .attackPolice, .attackTrader, .attackCaptain, .fleeInspection, .fleeMariePolice, .submitWithNothingIllegal,
             .surrenderToPolice, .bribe, .buyEquipment, .sellEquipment, .buyShip, .fireMercenary, .stopInsurance,
             .wildLeavesWithoutLaser, .wildLeavesForReactor, .litteringWarning, .useSingularity, .retire, .jettisonAll,
             .buyEscapePod, .surrenderArtifact, .acceptSpecialEvent, .submitInspection, .buyNewspaper:
            String(localized: "Cancel")
        }
    }

    /// SCORE-024/025: the score in tenths of a percent, formatted "X.Y" (Palm scores are already scaled by the engine).
    static func tenths(_ score: Int, state: GameState) -> String {
        let t = state.ruleset.flags.travel.scoreFormula == .palm ? score / 5 : score
        return "\(t / 10).\(abs(t % 10))"
    }
}
