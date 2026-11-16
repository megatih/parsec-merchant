// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine

/// Maps an engine decision to how the main window presents it (UI-SHELL-006). Pure and exhaustive (no `default`).
enum PresentationRouter {
    /// - Parameters:
    ///   - command: the command that raised the decision (resent on confirmation).
    ///   - acknowledged: warnings already acknowledged for that command.
    static func route(_ decision: PendingDecision, state: GameState, command: Command,
                      acknowledged: Set<WarningID> = []) -> Presentation {
        switch decision {
        case let .confirm(c):
            let pending = PendingConfirmation(command: command, confirmation: c, acknowledged: acknowledged)
            return routeConfirmation(pending)
        case .tradeInOrbit, .plunder, .scoop, .newspaper:
            return .sheet(.decision(decision))
        }
    }

    /// Confirmations: Retire is a sheet (ALR-104); Buy Ship opens the purchase review (UI-SHELL-072); others are dialogs.
    static func routeConfirmation(_ pending: PendingConfirmation) -> Presentation {
        switch pending.confirmation.warning {
        case .retire:
            return .sheet(.retire(pending))
        case .buyShip:
            switch pending.command {
            case let .buyShip(type, _): return .sheet(.shipPurchase(.ship(type)))
            case let .buildDesign(design, _): return .sheet(.shipPurchase(.design(design)))
            default: return .confirmation(pending)
            }
        case .attackPolice, .attackTrader, .attackCaptain, .fleeInspection, .fleeMariePolice, .submitWithNothingIllegal,
             .surrenderToPolice, .bribe, .buyEquipment, .sellEquipment, .fireMercenary, .stopInsurance,
             .wildLeavesWithoutLaser, .wildLeavesForReactor, .litteringWarning, .useSingularity, .jettisonAll,
             .drinkTonic, .boardMarieCeleste, .meetCaptain, .buyEscapePod, .surrenderArtifact, .acceptSpecialEvent,
             .submitInspection, .buyNewspaper:
            return .confirmation(pending)
        }
    }
}
