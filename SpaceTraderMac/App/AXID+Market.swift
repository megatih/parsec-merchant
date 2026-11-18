// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine

extension AXID {
    /// Market (⌘2) identifiers (UI-SHELL §8 and §18). Row qualifiers are `TradeItemType` case names.
    nonisolated enum Market {
        static let table = "market.table"
        static let filter = "market.filter"
        static let footer = "market.footer"
        static func row(_ item: TradeItemType) -> String { "market.row.\(item)" }
        static func buy(_ item: TradeItemType) -> String { "market.row.\(item).buy" }
        static func sell(_ item: TradeItemType) -> String { "market.row.\(item).sell" }
        static func buyMax(_ item: TradeItemType) -> String { "market.row.\(item).buyMax" }
        static func sellAll(_ item: TradeItemType) -> String { "market.row.\(item).sellAll" }
        static func quantity(_ item: TradeItemType) -> String { "market.row.\(item).quantity" }
        static func chip(_ item: TradeItemType, _ chip: TradeChip) -> String { "market.row.\(item).chip.\(chip.idSuffix)" }
        static func menu(_ item: TradeItemType, _ action: String) -> String { "market.row.\(item).menu.\(action)" }
        static func jettison(_ item: TradeItemType) -> String { "market.row.\(item).jettison" }
        static func dump(_ item: TradeItemType) -> String { "market.row.\(item).dump" }
        /// The Held and Buy cells (read by UI flow 1).
        static func held(_ item: TradeItemType) -> String { "market.row.\(item).held" }
        static func buyPrice(_ item: TradeItemType) -> String { "market.row.\(item).buyPrice" }
        static let disposalSheet = "market.disposal.sheet"
        static let disposalQuantity = "market.disposal.quantity"
        static let disposalConfirm = "market.disposal.confirm"
        static let disposalCancel = "market.disposal.cancel"
        static let all: [String] = [table, filter, footer, disposalSheet, disposalQuantity, disposalConfirm, disposalCancel]
            + TradeItemType.allCases.flatMap { item in
                [row(item), buy(item), sell(item), quantity(item), jettison(item), dump(item), held(item), buyPrice(item)]
                    + TradeChip.allCases.map { chip(item, $0) }
            }
    }
}
