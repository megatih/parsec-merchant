// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import SwiftUI

/// UI-KEYS-001: what a binding does. Menu items use their `MenuItemID` raw value, so a view key that repeats a menu
/// item's job (Esc → Stop in the encounter view) carries the same action as the menu item.
nonisolated struct KeyActionID: RawRepresentable, Hashable, Sendable, Comparable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }

    static func menu(_ id: MenuItemID) -> KeyActionID { KeyActionID(id.rawValue) }
    static func system(_ item: SystemMenuItem) -> KeyActionID { KeyActionID("system.\(item.rawValue)") }
    static func < (a: KeyActionID, b: KeyActionID) -> Bool { a.rawValue < b.rawValue }
    var description: String { rawValue }

    // Market (UI-SHELL-062/064, UI-KEYS-012)
    static let marketBuyOne = KeyActionID("market.buyOne")
    static let marketSellOne = KeyActionID("market.sellOne")
    static let marketBuyMax = KeyActionID("market.buyMax")
    static let marketSellAll = KeyActionID("market.sellAll")
    static let marketSelectPrevious = KeyActionID("market.selectPrevious")
    static let marketSelectNext = KeyActionID("market.selectNext")
    static let marketBuyTyped = KeyActionID("market.buyTyped")
    static let marketSellTyped = KeyActionID("market.sellTyped")
    // Galaxy map (MAP-015, MAP-073, UI-KEYS-013)
    static let mapPanLeft = KeyActionID("map.panLeft")
    static let mapPanRight = KeyActionID("map.panRight")
    static let mapPanUp = KeyActionID("map.panUp")
    static let mapPanDown = KeyActionID("map.panDown")
    static let searchPrevious = KeyActionID("search.previous")
    static let searchNext = KeyActionID("search.next")
    static let searchChoose = KeyActionID("search.choose")
    // Window (UI-KEYS-017…019)
    /// The main window's Esc, routed by `EscapeRouter` (levels 3–8).
    static let escape = KeyActionID("window.escape")
    static let encounterDefault = KeyActionID("encounter.defaultAction")
    static let transitSkip = KeyActionID("transit.skip")

    /// A sheet or dialog button (§2.3).
    static func sheet(_ surface: SheetSurface, _ button: SheetButton) -> KeyActionID {
        KeyActionID("sheet.\(surface.rawValue).\(button.rawValue)")
    }
}

/// UI-KEYS-005: what kind of main-window content shows (encounter and transit have their own contexts).
nonisolated enum DetailModeKind: String, Hashable, Sendable, CaseIterable {
    case welcome, docked, gameOver
}

/// UI-KEYS-005: where a binding is live.
nonisolated enum KeyContext: Hashable, Sendable, CustomStringConvertible {
    /// The menu bar.
    case global
    case mainWindow(DetailModeKind)
    case marketTable
    case marketField
    case mapCanvas
    case searchField
    case textField
    case encounter
    case transit
    /// A presented sheet (or confirmation dialog), named by its `SheetSurface`.
    case sheet(String)
    /// A system alert.
    case dialog

    var description: String {
        switch self {
        case .global: "global"
        case let .mainWindow(k): "mainWindow(\(k.rawValue))"
        case .marketTable: "marketTable"
        case .marketField: "marketField"
        case .mapCanvas: "mapCanvas"
        case .searchField: "searchField"
        case .textField: "textField"
        case .encounter: "encounter"
        case .transit: "transit"
        case let .sheet(name): "sheet(\(name))"
        case .dialog: "dialog"
        }
    }

    /// The contexts that are a focused view; only one view has keyboard focus at a time.
    var isFocusedView: Bool {
        switch self {
        case .marketTable, .marketField, .mapCanvas, .searchField, .textField: true
        default: false
        }
    }

    private var isPresentation: Bool {
        switch self {
        case .sheet, .dialog: true
        default: false
        }
    }

    /// UI-KEYS-005: a pure, symmetric matrix of the contexts that can be live at the same time.
    static func canCoexist(_ a: KeyContext, _ b: KeyContext) -> Bool {
        if a == .global || b == .global { return true }
        // One presentation at a time (UI-SHELL-005); a sheet or dialog takes the keys from the whole main window.
        if a.isPresentation || b.isPresentation {
            if a.isPresentation && b.isPresentation { return a == b }
            let other = a.isPresentation ? b : a
            // A sheet's own text fields are the only other context live with it.
            return other == .textField && (a.isSheet || b.isSheet)
        }
        if a == b { return true }
        // Only one view has keyboard focus.
        if a.isFocusedView && b.isFocusedView { return false }
        switch (a, b) {
        case let (.mainWindow(x), .mainWindow(y)): return x == y
        case (.encounter, _), (_, .encounter), (.transit, _), (_, .transit):
            // The encounter and transit views replace the sections (UI-ENC-001); they hold no text field.
            return false
        case let (.mainWindow(k), other), let (other, .mainWindow(k)):
            // The Market, map, search and text fields exist only in the docked sections (Welcome and the game-over card
            // have none).
            return other.isFocusedView ? k == .docked : true
        default:
            return true
        }
    }

    private var isSheet: Bool {
        if case .sheet = self { return true }
        return false
    }
}

/// System menu items whose shortcut the app keeps (§2.1 rows marked "system").
nonisolated enum SystemMenuItem: String, CaseIterable, Sendable {
    case settings, hide, hideOthers, quit, closeWindow, closeAll, undo, redo, cut, copy, paste, selectAll
    case toggleSidebar, toggleInspector, fullScreen, minimize, minimizeAll, cycleWindows, cycleWindowsBackward

    var shortcut: MenuShortcut {
        switch self {
        case .settings: MenuShortcut(",")
        case .hide: MenuShortcut("h")
        case .hideOthers: MenuShortcut("h", [.option, .command])
        case .quit: MenuShortcut("q")
        case .closeWindow: MenuShortcut("w")
        case .closeAll: MenuShortcut("w", [.option, .command])
        case .undo: MenuShortcut("z")
        case .redo: MenuShortcut("z", [.shift, .command])
        case .cut: MenuShortcut("x")
        case .copy: MenuShortcut("c")
        case .paste: MenuShortcut("v")
        case .selectAll: MenuShortcut("a")
        case .toggleSidebar: MenuShortcut("s", [.control, .command])
        case .toggleInspector: MenuShortcut("i", [.control, .command])
        case .fullScreen: MenuShortcut("f", [.control, .command])
        case .minimize: MenuShortcut("m")
        case .minimizeAll: MenuShortcut("m", [.option, .command])
        case .cycleWindows: MenuShortcut("`")
        case .cycleWindowsBackward: MenuShortcut("`", [.shift, .command])
        }
    }

    var titleKey: LocalizedStringResource {
        switch self {
        case .settings: "Settings…"
        case .hide: "Hide Parsec Merchant"
        case .hideOthers: "Hide Others"
        case .quit: "Quit Parsec Merchant"
        case .closeWindow: "Close Window"
        case .closeAll: "Close All"
        case .undo: "Undo"
        case .redo: "Redo"
        case .cut: "Cut"
        case .copy: "Copy"
        case .paste: "Paste"
        case .selectAll: "Select All"
        case .toggleSidebar: "Show or Hide Sidebar"
        case .toggleInspector: "Show or Hide Inspector"
        case .fullScreen: "Enter Full Screen"
        case .minimize: "Minimize"
        case .minimizeAll: "Minimize All"
        case .cycleWindows: "Cycle Through Windows"
        case .cycleWindowsBackward: "Cycle Backward Through Windows"
        }
    }

    /// The kept system shortcuts, as bindings.
    static var keptShortcuts: [KeyBinding] {
        allCases.map { KeyBinding(action: .system($0), shortcut: $0.shortcut, context: .global, owner: .systemItem($0), titleKey: $0.titleKey) }
    }
}

/// A view that handles keys itself (§2.2).
nonisolated enum ViewKeySite: String, Hashable, Sendable, CaseIterable {
    case marketTable, marketQuantity, marketFilter, mapCanvas, mapSearch, logbookSearch, encounterView, transit, welcome,
         gameOverCard, windowRoot
}

/// The keyboard role of a sheet button (§2.3).
nonisolated enum SheetKeyRole: String, Hashable, Sendable {
    case defaultAction, cancelAction
}

/// UI-KEYS-001: who defines a binding.
nonisolated enum KeyOwner: Hashable, Sendable {
    case menu(MenuItemID)
    case systemItem(SystemMenuItem)
    case view(ViewKeySite)
    case sheet(SheetKeyRole)

    /// Custom bindings are checked against `SystemShortcuts.reserved` (UI-KEYS-008).
    var isCustom: Bool {
        if case .systemItem = self { return false }
        return true
    }
}

/// UI-KEYS-001: one keyboard binding.
nonisolated struct KeyBinding: Sendable {
    var action: KeyActionID
    var shortcut: MenuShortcut
    var context: KeyContext
    var owner: KeyOwner
    var titleKey: LocalizedStringResource
    /// A hidden alias of another binding's key (⌘= for ⌘+), listed right after its primary (UI-KEYS-002).
    var isAlias = false
}

/// UI-KEYS-001: the one list of every keyboard binding the app defines or keeps.
nonisolated enum KeyBindingTable {
    static var all: [KeyBinding] {
        menuBindings + SystemMenuItem.keptShortcuts + MarketKeyAction.bindings + MapKeys.bindings + EncounterKeys.viewBindings
            + WindowKeys.bindings + SheetKeys.bindings
    }

    /// Every `MenuCatalog` entry with a shortcut (all milestones), owner `.menu`.
    static var menuBindings: [KeyBinding] {
        MenuItemID.allCases.compactMap { id in
            let entry = MenuCatalog.entry(for: id)
            guard let shortcut = entry.shortcut else { return nil }
            return KeyBinding(action: .menu(id), shortcut: shortcut, context: menuContext(id), owner: .menu(id), titleKey: entry.titleKey)
        }
    }

    /// The context in which `MenuRules` can enable a menu item: Encounter items only in an encounter (UI-ENC-034), the
    /// zoom items only with a focused map (MENU-022); everything else is the menu bar.
    static func menuContext(_ id: MenuItemID) -> KeyContext {
        if MenuItemID.encounterItems.contains(id) { return .encounter }
        switch id {
        case .zoomIn, .zoomOut, .zoomFit: return .mapCanvas
        default: return .global
        }
    }
}

/// The main window's own keys (§2.2): Return on Welcome, Transit and the game-over card, and the one Esc router.
nonisolated enum WindowKeys {
    static let returnKey = MenuShortcut(MenuShortcut.returnKey, [])
    static let escapeKey = MenuShortcut(EncounterKeys.escapeKey, [])

    static var bindings: [KeyBinding] {
        [
            KeyBinding(action: .menu(.quickStart), shortcut: returnKey, context: .mainWindow(.welcome), owner: .view(.welcome),
                       titleKey: "Welcome: Quick Start"),
            KeyBinding(action: .menu(.newGame), shortcut: returnKey, context: .mainWindow(.gameOver), owner: .view(.gameOverCard),
                       titleKey: "Game over: New Game…"),
            KeyBinding(action: .transitSkip, shortcut: returnKey, context: .transit, owner: .view(.transit), titleKey: "Transit: Skip"),
            KeyBinding(action: .transitSkip, shortcut: escapeKey, context: .transit, owner: .view(.windowRoot), titleKey: "Transit: Skip"),
            KeyBinding(action: .menu(.encounterStop), shortcut: escapeKey, context: .encounter, owner: .view(.windowRoot),
                       titleKey: "Encounter: Stop the repeat"),
            KeyBinding(action: .escape, shortcut: escapeKey, context: .mainWindow(.docked), owner: .view(.windowRoot),
                       titleKey: "Close the event feed, then clear the Shipyard comparison"),
        ]
    }
}

nonisolated extension EncounterKeys {
    /// UI-ENC-029 / UI-ENC-036: Return runs the default action (never Attack or Surrender) or Continue Decision. The
    /// letters, R, ⌥A and Esc are Encounter menu items.
    static var viewBindings: [KeyBinding] {
        [KeyBinding(action: .encounterDefault, shortcut: WindowKeys.returnKey, context: .encounter, owner: .view(.encounterView),
                    titleKey: "Encounter: the default action")]
    }
}

nonisolated extension MenuShortcut {
    static let returnKey = "\r"
    static let tabKey = "\t"
    static let upArrowKey = "\u{F700}"
    static let downArrowKey = "\u{F701}"
    static let leftArrowKey = "\u{F702}"
    static let rightArrowKey = "\u{F703}"

    /// UI-KEYS-004: the key cap glyph ("⎋", "↩", "⇥", arrows; letters uppercase).
    var keyGlyph: String {
        switch key {
        case EncounterKeys.escapeKey: "⎋"
        case Self.returnKey: "↩"
        case Self.tabKey: "⇥"
        case Self.upArrowKey: "↑"
        case Self.downArrowKey: "↓"
        case Self.leftArrowKey: "←"
        case Self.rightArrowKey: "→"
        case " ": "Space"
        case "-": "−"
        default: key.uppercased()
        }
    }

    /// The SwiftUI modifiers as catalog modifiers (⌃⌥⇧⌘ only; Caps Lock, Fn and the keypad flag are ignored).
    static func modifiers(_ m: EventModifiers) -> Set<Modifier> {
        var out: Set<Modifier> = []
        if m.contains(.control) { out.insert(.control) }
        if m.contains(.option) { out.insert(.option) }
        if m.contains(.shift) { out.insert(.shift) }
        if m.contains(.command) { out.insert(.command) }
        return out
    }

    /// A pressed key as a catalog shortcut (letters lowercased; the arrow, Return, Esc and Tab keys by their key string).
    @MainActor
    init(press key: KeyEquivalent, characters: String, modifiers m: EventModifiers) {
        let special: [KeyEquivalent: String] = [.upArrow: Self.upArrowKey, .downArrow: Self.downArrowKey, .leftArrow: Self.leftArrowKey,
                                                .rightArrow: Self.rightArrowKey, .return: Self.returnKey, .escape: EncounterKeys.escapeKey,
                                                .tab: Self.tabKey]
        let k = special[key] ?? (characters.isEmpty ? String(key.character) : characters).lowercased()
        self.init(k, Self.modifiers(m))
    }
}
