// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine

/// Maps an engine decision to how the main window presents it (UI-SHELL-006, UI-ENC-003). Pure and exhaustive (no
/// `default`).
enum PresentationRouter {
    /// - Parameters:
    ///   - command: the command that raised the decision (resent on confirmation).
    ///   - acknowledged: warnings already acknowledged for that command.
    static func route(_ decision: PendingDecision, state: GameState, command: Command,
                      acknowledged: Set<WarningID> = []) -> Presentation {
        switch decision {
        case let .confirm(c):
            let pending = PendingConfirmation(command: command, confirmation: c, acknowledged: acknowledged)
            return routeConfirmation(pending, state: state)
        case let .tradeInOrbit(offer):
            return .sheet(.tradeInOrbit(offer))
        case let .plunder(cargo):
            let source: PlunderSheetContext.Source = command == .encounter(.board) ? .marieCeleste : .opponent
            return .sheet(.plunder(PlunderSheetContext(victimCargo: cargo, source: source)))
        case let .scoop(item):
            return .scoop(item)
        case let .newspaper(paper):
            return .sheet(.newspaper(paper))
        }
    }

    /// Confirmations: Retire is a sheet (ALR-104); Buy Ship opens the purchase review (UI-SHELL-072); accepting a special
    /// event is the narrative sheet's offer page (UI-ENC-076); others are dialogs.
    static func routeConfirmation(_ pending: PendingConfirmation, state: GameState? = nil) -> Presentation {
        switch pending.confirmation.warning {
        case .retire:
            return .sheet(.retire(pending))
        case .buyShip:
            switch pending.command {
            case let .buyShip(type, _): return .sheet(.shipPurchase(.ship(type)))
            case let .buildDesign(design, _): return .sheet(.shipPurchase(.design(design)))
            default: return .confirmation(pending)
            }
        case .acceptSpecialEvent:
            guard let type = state?.specialEventAvailable else { return .confirmation(pending) }
            return .sheet(.narrative(.offer(type)))
        case .attackPolice, .attackTrader, .attackCaptain, .fleeInspection, .fleeMariePolice, .submitWithNothingIllegal,
             .surrenderToPolice, .bribe, .buyEquipment, .sellEquipment, .fireMercenary, .stopInsurance,
             .wildLeavesWithoutLaser, .wildLeavesForReactor, .litteringWarning, .useSingularity, .jettisonAll,
             .drinkTonic, .boardMarieCeleste, .meetCaptain, .buyEscapePod, .surrenderArtifact,
             .submitInspection, .buyNewspaper:
            return .confirmation(pending)
        }
    }
}
