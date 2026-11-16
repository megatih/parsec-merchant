// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// What the interim decision sheets offer and send (UI-SHELL-011; replaced by UI-ENC in M9). Pure.
enum InterimDecisionModel {
    /// Trade in orbit: the stepper's range, its start value, and the answer (0 declines).
    struct Trade: Equatable, Sendable {
        var offer: OrbitTradeOffer

        var range: ClosedRange<Int> { 0...max(0, offer.maxQuantity) }
        var initialQuantity: Int { max(0, offer.maxQuantity) }
        func canAccept(_ q: Int) -> Bool { q > 0 && range.contains(q) }
        func acceptCommand(_ q: Int) -> Command { .resolveTradeInOrbit(quantity: min(max(0, q), range.upperBound)) }
        var declineCommand: Command { .resolveTradeInOrbit(quantity: 0) }
    }

    /// Plunder: the victim's non-empty cargo rows, Take (clamped to what is there) and Done.
    enum Plunder {
        static func rows(cargo: [Int]) -> [(item: TradeItemType, available: Int)] {
            TradeItemType.allCases.compactMap { item in
                let i = item.rawValue
                return cargo.indices.contains(i) && cargo[i] > 0 ? (item, cargo[i]) : nil
            }
        }

        static func takeCommand(_ item: TradeItemType, amount: Int?, available: Int) -> Command {
            .plunderTake(item, quantity: min(max(1, amount ?? available), available))
        }

        static let doneCommand = Command.plunderDone
    }

    /// Scoop: Pick It Up / Leave It (ALR-070/071).
    static func scoopCommand(accept: Bool) -> Command { .resolveScoop(accept: accept) }

    /// Newspaper: one plain line per headline after the masthead.
    static func newspaperLines(_ paper: Newspaper, state: GameState) -> [LocalizedStringResource] {
        paper.headlines.map { NewspaperText.interimLine($0, state: state) }
    }
}
