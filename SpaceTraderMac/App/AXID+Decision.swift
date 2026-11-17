// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine

/// Decision sheet and dialog identifiers (UI-ENC §17 "Decisions"). The M7 interim strings are kept unchanged.
nonisolated extension AXID {
    enum Decision {
        static let plunderSheet = "decision.plunder.sheet"
        static func plunderRow(_ item: TradeItemType) -> String { "decision.plunder.row.\(item)" }
        static func plunderQuantity(_ item: TradeItemType) -> String { "decision.plunder.quantity.\(item)" }
        static func plunderTake(_ item: TradeItemType) -> String { "decision.plunder.take.\(item)" }
        static func plunderTakeAll(_ item: TradeItemType) -> String { "decision.plunder.takeAll.\(item)" }
        static let plunderFreeBays = "decision.plunder.freeBays"
        static let plunderDone = "decision.plunder.done"
        static let tradeSheet = "decision.trade.sheet"
        static let tradeQuantity = "decision.trade.quantity"
        static let tradeMax = "decision.trade.max"
        static let tradeAccept = "decision.trade.accept"
        static let tradeDecline = "decision.trade.decline"
        static let scoopAccept = "decision.scoop.accept"
        static let scoopDecline = "decision.scoop.decline"
        static let scoopMakeRoom = "decision.scoop.makeRoom"
        static let newspaperClose = "decision.newspaper.close"

        static let all: [String] = [plunderSheet, plunderFreeBays, plunderDone, tradeSheet, tradeQuantity, tradeMax,
                                    tradeAccept, tradeDecline, scoopAccept, scoopDecline, scoopMakeRoom, newspaperClose]
            + TradeItemType.allCases.flatMap { [plunderRow($0), plunderQuantity($0), plunderTake($0), plunderTakeAll($0)] }
    }
}
