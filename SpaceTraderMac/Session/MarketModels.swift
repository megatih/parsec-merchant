// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import Foundation
import ParsecEngine
import ParsecInsights
import SwiftUI

/// The quantity a modifier-click or B/S key trades (UI-SHELL-062, -063): plain 1, ⇧ 5, ⌘ 20, ⇧⌘ 100, ⌥ all.
enum TradeQuantity {
    static func resolve(modifiers: EventModifiers, maximum: Int) -> Int {
        let maximum = max(0, maximum)
        let requested: Int = if modifiers.contains(.option) {
            maximum
        } else if modifiers.contains(.shift), modifiers.contains(.command) {
            100
        } else if modifiers.contains(.command) {
            20
        } else if modifiers.contains(.shift) {
            5
        } else {
            1
        }
        return min(max(0, requested), maximum)
    }

    /// AUD-040 / UI-SHELL-067: the request reaches the cap (most affordable, free bays or stock): the snap haptic.
    static func snaps(modifiers: EventModifiers, maximum: Int) -> Bool {
        HapticMap.quantitySnaps(requested: resolve(modifiers: modifiers, maximum: .max), maximum: maximum)
    }

    /// The SwiftUI modifiers of an AppKit event's flags (button actions read `NSEvent.modifierFlags`).
    static func modifiers(from flags: NSEvent.ModifierFlags) -> EventModifiers {
        var m: EventModifiers = []
        if flags.contains(.shift) { m.insert(.shift) }
        if flags.contains(.command) { m.insert(.command) }
        if flags.contains(.option) { m.insert(.option) }
        if flags.contains(.control) { m.insert(.control) }
        return m
    }

    /// The modifiers held right now (for button clicks).
    static var current: EventModifiers { modifiers(from: NSEvent.modifierFlags) }
}

/// The C# target-price columns for one item (Form_SpaceTrader.cs UpdateCargo): the target's standard price from
/// what the player knows (the resource only once visited), and the difference to the buy price here.
struct TargetQuote: Equatable, Sendable {
    var price: Int
    /// `price − buyPrice` per unit, i.e. per bay; nil when the item is not sold here.
    var difference: Int?
    /// `100 × difference / buyPrice` (integer, as C#); nil when the item is not sold here.
    var percent: Int?

    static func make(state: GameState, item: TradeItemType, buyPrice: Int, snapshot: IntelSnapshot? = nil) -> TargetQuote? {
        let target = state.warpSystem
        guard target != state.commander.currentSystem, state.destinationOK(target) else { return nil }
        // INT-040: the one standard-price estimate (the resource only once visited, INT-013).
        let price = TradeIntel.estimate(item: item, system: target, snapshot: snapshot ?? IntelSnapshot(state))
        guard price > 0 else { return nil }
        guard buyPrice > 0 else { return TargetQuote(price: price, difference: nil, percent: nil) }
        let diff = price - buyPrice
        return TargetQuote(price: price, difference: diff, percent: 100 * diff / buyPrice)
    }
}

/// One row of the merged trade table (UI-SHELL-061, -062). Pure over the state.
struct MarketRowModel: Identifiable, Equatable, Sendable {
    var row: MarketRow
    var buyBlocker: CommandError?
    var sellBlocker: CommandError?
    var target: TargetQuote?
    /// Jettison is offered only where the engine accepts it (in space; ECO-055).
    var canJettison: Bool

    var id: TradeItemType { row.item }
    var item: TradeItemType { row.item }
    var isIllegal: Bool { item == .firearms || item == .narcotics }
    /// "—" when nil.
    var buyPrice: Int? { row.buyPrice > 0 ? row.buyPrice : nil }
    var sellPrice: Int? { row.sellPrice > 0 ? row.sellPrice : nil }
    /// Nobody here buys it: the sell controls dump instead (ECO-052).
    var isDumpMode: Bool { row.dumpCostPerUnit != nil }
    /// "Dump N cr." shown in the Sell cell when the item is held and unsellable.
    var dumpCostShown: Int? { row.held > 0 ? row.dumpCostPerUnit : nil }
    /// Profit or loss per unit if sold here; nil when none held or unsellable.
    var profitPerUnit: Int? {
        guard row.held > 0, let sell = sellPrice else { return nil }
        return sell - row.costBasisPerUnit
    }

    var canDump: Bool { isDumpMode && row.held > 0 }

    static func rows(state: GameState) -> [MarketRowModel] {
        let docked = state.phase == .docked
        let snapshot = IntelSnapshot(state)
        return state.marketRows.map { row in
            let buy: CommandError? = if case let .failure(e) = state.marketBuyCheck(row.item) { e } else { nil }
            let sellCheck = state.marketSellCheck(row.item, dump: row.dumpCostPerUnit != nil)
            let sell: CommandError? = switch sellCheck {
            case let .failure(e): e
            case let .success(q): q > 0 ? nil : .insufficientFunds
            }
            return MarketRowModel(row: row, buyBlocker: docked ? buy : .notAllowedInPhase,
                                  sellBlocker: docked ? sell : .notAllowedInPhase,
                                  target: TargetQuote.make(state: state, item: row.item, buyPrice: row.buyPrice, snapshot: snapshot),
                                  canJettison: !docked && row.held > 0)
        }
    }

    /// `min(requested, maxBuy)`; nil when nothing can be bought, so a modifier never causes a rejection.
    func buyCommand(requested: Int) -> Command? {
        let q = min(requested, row.maxBuy)
        guard buyBlocker == nil, q > 0 else { return nil }
        return .buyCargo(item, quantity: q)
    }

    /// `min(requested, maxSell)` as a sale, or as a dump when nobody here buys the item.
    func sellCommand(requested: Int) -> Command? {
        let q = min(requested, row.maxSell)
        guard sellBlocker == nil, q > 0 else { return nil }
        return isDumpMode ? .dumpCargo(item, quantity: q) : .sellCargo(item, quantity: q)
    }

    func buyCommand(modifiers: EventModifiers) -> Command? {
        buyCommand(requested: TradeQuantity.resolve(modifiers: modifiers, maximum: row.maxBuy))
    }

    func sellCommand(modifiers: EventModifiers) -> Command? {
        sellCommand(requested: TradeQuantity.resolve(modifiers: modifiers, maximum: row.maxSell))
    }

    var buyMaxCommand: Command? { buyCommand(requested: row.maxBuy) }
    var sellAllCommand: Command? { sellCommand(requested: row.maxSell) }

    /// The quantity field: Return buys its value, ⇧Return sells it, clamped the same way.
    func fieldCommand(text: String, sell: Bool) -> Command? {
        guard let n = Int(text.trimmingCharacters(in: .whitespaces)), n > 0 else { return nil }
        return sell ? sellCommand(requested: n) : buyCommand(requested: n)
    }
}

/// The B / S keys of the focused trade table (UI-SHELL-064, amended by UI-KEYS-012).
enum MarketKeyAction: Equatable, Sendable {
    case buy(EventModifiers)
    case sell(EventModifiers)
    case buyMax
    case sellAll

    /// UI-KEYS-012: plain B buys 1 and plain S sells 1; ⇧B is Buy Max and ⇧S is Sell All. Nothing with ⌘, ⌥ or ⌃: menu
    /// key equivalents win over `.onKeyPress` (⌘S is Save). Keys are looked up in `bindings`, never matched here.
    static func make(characters: String, modifiers: EventModifiers) -> MarketKeyAction? {
        let pressed = NormalizedShortcut(physical: MenuShortcut(characters.lowercased(), MenuShortcut.modifiers(modifiers)))
        let binding = bindings.first { $0.context == .marketTable && NormalizedShortcut(physical: $0.shortcut) == pressed }
        switch binding?.action {
        case .marketBuyOne?: return .buy([])
        case .marketSellOne?: return .sell([])
        case .marketBuyMax?: return .buyMax
        case .marketSellAll?: return .sellAll
        default: return nil
        }
    }

    /// UI-KEYS-001: the Market's keys (the table's letters and arrows, the quantity field's Return).
    nonisolated static var bindings: [KeyBinding] {
        let table: [(KeyActionID, MenuShortcut, LocalizedStringResource)] = [
            (.marketBuyOne, MenuShortcut("b", []), "Market: buy one unit of the selected item"),
            (.marketSellOne, MenuShortcut("s", []), "Market: sell or dump one unit of the selected item"),
            (.marketBuyMax, MenuShortcut("b", [.shift]), "Market: Buy Max"),
            (.marketSellAll, MenuShortcut("s", [.shift]), "Market: Sell All"),
            (.marketSelectPrevious, MenuShortcut(MenuShortcut.upArrowKey, []), "Market: select the previous item"),
            (.marketSelectNext, MenuShortcut(MenuShortcut.downArrowKey, []), "Market: select the next item"),
        ]
        let field: [(KeyActionID, MenuShortcut, LocalizedStringResource)] = [
            (.marketBuyTyped, MenuShortcut(MenuShortcut.returnKey, []), "Market quantity: buy the typed quantity"),
            (.marketSellTyped, MenuShortcut(MenuShortcut.returnKey, [.shift]), "Market quantity: sell the typed quantity"),
        ]
        return table.map { KeyBinding(action: $0.0, shortcut: $0.1, context: .marketTable, owner: .view(.marketTable), titleKey: $0.2) }
            + field.map { KeyBinding(action: $0.0, shortcut: $0.1, context: .marketField, owner: .view(.marketQuantity), titleKey: $0.2) }
    }

    func command(for row: MarketRowModel) -> Command? {
        switch self {
        case let .buy(m): row.buyCommand(modifiers: m)
        case let .sell(m): row.sellCommand(modifiers: m)
        case .buyMax: row.buyMaxCommand
        case .sellAll: row.sellAllCommand
        }
    }
}

/// The trade table's footer (UI-SHELL-066).
struct MarketFooterModel: Equatable, Sendable {
    var usedBays: Int
    var totalBays: Int
    /// Free bays for buying, honouring "leave N bays empty" (ECO-046).
    var freeForBuying: Int
    /// Cash available, honouring "reserve money" (ECO-042).
    var cashAvailable: Int

    static func make(state: GameState) -> MarketFooterModel {
        MarketFooterModel(usedBays: state.filledCargoBays, totalBays: state.commander.ship.cargoBays(state.ruleset),
                          freeForBuying: state.marketFreeBays, cashAvailable: state.cashToSpend)
    }
}

/// The item filter (UI-SHELL-067): case- and diacritic-insensitive "contains" on the localized name.
enum MarketFilter {
    static func matches(name: String, filter: String) -> Bool {
        let f = filter.trimmingCharacters(in: .whitespaces)
        guard !f.isEmpty else { return true }
        return name.range(of: f, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    static func filtered(_ rows: [MarketRowModel], filter: String) -> [MarketRowModel] {
        rows.filter { matches(name: String(localized: Names.item($0.item)), filter: filter) }
    }
}

/// The quantity sheet behind the Held cell's Jettison… and Dump… (UI-SHELL-065).
struct CargoDisposal: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable { case jettison, dump }

    var kind: Kind
    var item: TradeItemType
    var maximum: Int

    var id: String { "\(kind)-\(item)" }

    static func jettison(_ row: MarketRowModel) -> CargoDisposal? {
        row.canJettison ? CargoDisposal(kind: .jettison, item: row.item, maximum: row.row.held) : nil
    }

    static func dump(_ row: MarketRowModel) -> CargoDisposal? {
        row.canDump && row.row.maxSell > 0 ? CargoDisposal(kind: .dump, item: row.item, maximum: row.row.maxSell) : nil
    }

    /// The command for a chosen quantity (clamped to `1…maximum`); confirmations follow UI-SHELL-004.
    func command(quantity: Int) -> Command? {
        guard maximum > 0 else { return nil }
        let q = min(max(1, quantity), maximum)
        return kind == .jettison ? .jettisonCargo(item, quantity: q) : .dumpCargo(item, quantity: q)
    }
}

/// ⌘F in Market focuses the item filter (UI-SHELL-067, MENU-018): the Market publishes this action as a focused
/// scene value and the Find menu item calls it when present.
struct MarketFilterFocusAction {
    let focus: () -> Void
    func callAsFunction() { focus() }
}

extension FocusedValues {
    @Entry var marketFilterFocus: MarketFilterFocusAction?
}
