// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// UI-PTR-005, UI-PTR-007: the words of the Market row's chips, buttons and context menu.
enum MarketText {
    static func chip(_ chip: TradeChip) -> String {
        switch chip {
        case .one: String(localized: "1")
        case .five: String(localized: "5")
        case .twenty: String(localized: "20")
        case .max: String(localized: "Max")
        }
    }

    static func chipHelp(_ chip: TradeChip) -> String {
        switch chip {
        case .one: String(localized: "Trade 1 unit at a time")
        case .five: String(localized: "Trade 5 units at a time")
        case .twenty: String(localized: "Trade 20 units at a time")
        case .max: String(localized: "Trade as many as possible")
        }
    }

    /// The help tag of Sell and Buy: what the button does, with the accelerators for keyboard-and-mouse users.
    static func tradeHelp(sell: Bool, dump: Bool) -> String {
        if dump { return String(localized: "Dump the selected amount (⇧ 5, ⌘ 20, ⇧⌘ 100, ⌥ all)") }
        return sell ? String(localized: "Sell the selected amount (⇧ 5, ⌘ 20, ⇧⌘ 100, ⌥ all)")
            : String(localized: "Buy the selected amount (⇧ 5, ⌘ 20, ⇧⌘ 100, ⌥ max)")
    }

    static func menuBuy(_ chip: TradeChip, maximum: Int) -> String {
        switch chip {
        case .one: String(localized: "Buy 1")
        case .five: String(localized: "Buy 5")
        case .twenty: String(localized: "Buy 20")
        case .max: String(localized: "Buy Max (\(max(0, maximum)))")
        }
    }

    static func menuSell(_ chip: TradeChip, maximum: Int, dump: Bool) -> String {
        switch (chip, dump) {
        case (.one, false): String(localized: "Sell 1")
        case (.five, false): String(localized: "Sell 5")
        case (.twenty, false): String(localized: "Sell 20")
        case (.max, false): String(localized: "Sell All (\(max(0, maximum)))")
        case (.one, true): String(localized: "Dump 1")
        case (.five, true): String(localized: "Dump 5")
        case (.twenty, true): String(localized: "Dump 20")
        case (.max, true): String(localized: "Dump All (\(max(0, maximum)))")
        }
    }
}
