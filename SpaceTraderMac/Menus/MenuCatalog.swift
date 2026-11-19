// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// The menus of the menu bar that hold custom items (MENU §3).
nonisolated enum MenuName: String, CaseIterable, Sendable {
    case app, file, edit, view, trade, game, encounter, window, help
}

/// One case per custom menu item (MENU-001). System items (Hide, Services, Minimize, Enter Full Screen…) are not cases.
nonisolated enum MenuItemID: String, CaseIterable, Sendable {
    // Parsec Merchant
    case about
    // File
    case newGame, quickStart, open, openRecent, save, saveAs, revert, importSave, export, closeGame
    // Edit
    case find
    // View
    case bridge, shipyard, outfitter, crew, bank, commanderStatus, galaxy, quests, logbook, options, galaxyChart, zoomIn, zoomOut, zoomFit
    case recentEvents
    // Trade (UI-HIG-001, PRD-UI-Revamp §4.15)
    case tradeBuy, tradeBuyMax, tradeSell, tradeSellAll, sellAllCargo, dumpCargo, priceDetails, buyFuelAmount, fillFuel, repairAmount, repair
    // Game
    case warp, previousTarget, nextTarget, track, plotRoute, jump, newspaper, retire
    // Encounter (UI-ENC-034)
    case encounterAttack, encounterFlee, encounterSurrender, encounterIgnore, encounterBribe, encounterSubmit, encounterTrade
    case encounterPlunder, encounterBoard, encounterDrink, encounterMeet, encounterYield, encounterAutoRepeat, encounterResolve
    case encounterStop
    // Window
    case mainWindow, galaxyChartWindow, highScores
    // Help
    case help, prices, shortcuts, credits, github

    /// The sidebar section a View item selects.
    var section: Section? {
        switch self {
        case .bridge: .bridge
        case .shipyard: .shipyard
        case .outfitter: .outfitter
        case .crew: .crew
        case .bank: .bank
        case .commanderStatus: .status
        case .galaxy: .galaxy
        case .quests: .quests
        case .logbook: .logbook
        case .options: .options
        default: nil
        }
    }

    /// The View item of a section.
    static func item(for section: Section) -> MenuItemID {
        switch section {
        case .bridge: .bridge
        case .shipyard: .shipyard
        case .outfitter: .outfitter
        case .crew: .crew
        case .bank: .bank
        case .galaxy: .galaxy
        case .quests: .quests
        case .logbook: .logbook
        case .status: .commanderStatus
        case .options: .options
        }
    }
}

/// A keyboard shortcut as plain data (so the catalog stays `Sendable` and testable without SwiftUI types).
nonisolated struct MenuShortcut: Hashable, Sendable {
    enum Modifier: String, Hashable, Sendable, CaseIterable {
        case control, option, shift, command
    }

    var key: String
    var modifiers: Set<Modifier>

    init(_ key: String, _ modifiers: Set<Modifier> = [.command]) {
        self.key = key
        self.modifiers = modifiers
    }

    /// The menu-style glyphs, e.g. "⇧⌘S" (for Help › Keyboard Shortcuts; modifiers ⌃⌥⇧⌘, UI-KEYS-004).
    var display: String {
        let order: [(Modifier, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return order.filter { modifiers.contains($0.0) }.map(\.1).joined() + keyGlyph
    }
}

/// The single source of a custom item's menu, title, shortcut, identifier and milestone (MENU-003).
nonisolated struct MenuEntry: Sendable {
    var menu: MenuName
    var titleKey: LocalizedStringResource
    var shortcut: MenuShortcut?
    var identifier: String
    var milestone: Int
}

nonisolated enum MenuCatalog {
    /// Entries tagged above this milestone are absent from the menu bar (MENU-040).
    static let currentMilestone = 10
    static let githubURL = URL(string: "https://github.com/megatih/parsec-merchant") ?? URL(fileURLWithPath: "/")
    static let openRecentRows = 10

    // swiftlint:disable:next cyclomatic_complexity
    static func entry(for id: MenuItemID) -> MenuEntry {
        switch id {
        case .about: return MenuEntry(menu: .app, titleKey: "About Parsec Merchant", shortcut: nil, identifier: "menu.app.about", milestone: 7)
        case .newGame: return file("New Game…", s("n", [.command]), "newGame")
        case .quickStart: return file("Quick Start", nil, "quickStart")
        case .open: return file("Open Saved Game…", s("o", [.command]), "open")
        case .openRecent: return file("Open Recent", nil, "openRecent")
        case .save: return file("Save", s("s", [.command]), "save")
        case .saveAs: return file("Save As…", s("s", [.shift, .command]), "saveAs")
        case .revert: return file("Revert to Autosave", nil, "revert")
        case .importSave: return file("Import…", nil, "import")
        case .export: return file("Export…", s("e", [.shift, .command]), "export")
        case .closeGame: return file("Close Game", nil, "closeGame")
        case .find: return MenuEntry(menu: .edit, titleKey: "Find System…", shortcut: s("f", [.command]), identifier: "menu.edit.find", milestone: 7)
        case .bridge: return view("Bridge", s("1", [.command]), "bridge")
        case .shipyard: return view("Shipyard", s("2", [.command]), "shipyard")
        case .outfitter: return view("Equipment", s("3", [.command]), "outfitter")
        case .crew: return view("Personnel", s("4", [.command]), "crew")
        case .bank: return view("Bank", s("5", [.command]), "bank")
        case .commanderStatus: return view("Commander Status", s("6", [.command]), "commanderStatus")
        case .galaxy: return view("Galactic Chart", s("8", [.command]), "galaxy", milestone: 8)
        case .quests: return view("Quests", s("7", [.command]), "quests")
        case .logbook: return view("Logbook", s("9", [.command]), "logbook", milestone: 10)
        case .galaxyChart: return view("Galactic Chart Window", s("m", [.shift, .command]), "galaxyChart", milestone: 8)
        case .zoomIn: return view("Zoom In", s("+", [.command]), "zoomIn", milestone: 8)
        case .zoomOut: return view("Zoom Out", s("-", [.command]), "zoomOut", milestone: 8)
        case .zoomFit: return view("Fit Range", s("0", [.command]), "zoomFit", milestone: 8)
        case .recentEvents: return view("Recent Events", s("e", [.command]), "recentEvents")
        case .warp: return game("Warp", s("j", [.command]), "warp")
        case .jump: return game("Jump…", nil, "jump")
        case .previousTarget: return game("Previous Target", s("[", [.command]), "previousTarget")
        case .nextTarget: return game("Next Target", s("]", [.command]), "nextTarget")
        case .track: return game("Track Target", nil, "track")
        case .plotRoute: return game("Plot Route…", nil, "plotRoute", milestone: 8)
        case .tradeBuy: return trade("Buy", s("b", []), "buy")
        case .tradeBuyMax: return trade("Buy Maximum", s("b", [.shift]), "buyMaximum")
        case .tradeSell: return trade("Sell", s("s", []), "sell")
        case .tradeSellAll: return trade("Sell All", s("s", [.shift]), "sellAll")
        case .sellAllCargo: return trade("Sell All Cargo", s("s", [.option, .command]), "sellAllCargo")
        case .dumpCargo: return trade("Dump…", nil, "dump")
        case .priceDetails: return trade("Price Details…", s("i", [.option, .command]), "priceDetails")
        case .buyFuelAmount: return trade("Buy Fuel…", nil, "buyFuelAmount")
        case .fillFuel: return trade("Fill Tank", s("f", [.shift, .command]), "fillFuel")
        case .repairAmount: return trade("Repair…", nil, "repairAmount")
        case .repair: return trade("Repair Hull", s("r", [.shift, .command]), "repair")
        case .newspaper: return game("Read Newspaper", s("n", [.shift, .command]), "newspaper", milestone: 9)
        case .options: return view("Options", s("o", [.option, .command]), "options")
        case .retire: return game("Retire…", nil, "retire")
        case .encounterAttack, .encounterFlee, .encounterSurrender, .encounterIgnore, .encounterBribe, .encounterSubmit, .encounterTrade,
             .encounterPlunder, .encounterBoard, .encounterDrink, .encounterMeet, .encounterYield, .encounterAutoRepeat,
             .encounterResolve, .encounterStop:
            return encounterEntry(id)
        case .mainWindow: return MenuEntry(menu: .window, titleKey: "Parsec Merchant", shortcut: nil, identifier: "menu.window.main", milestone: 7)
        case .galaxyChartWindow:
            return MenuEntry(menu: .window, titleKey: "Galactic Chart", shortcut: nil, identifier: "menu.window.galaxyChart", milestone: 8)
        case .highScores:
            return MenuEntry(menu: .window, titleKey: "High Scores", shortcut: nil, identifier: "menu.window.highScores", milestone: 9)
        case .help: return help("Parsec Merchant Help", s("?", [.command]), "help")
        case .prices: return help("How Prices Work", nil, "prices")
        case .shortcuts: return help("Keyboard Shortcuts", nil, "shortcuts")
        case .credits: return help("Credits & License", nil, "credits")
        case .github: return help("GitHub Project", nil, "github")
        }
    }

    private static func s(_ key: String, _ modifiers: Set<MenuShortcut.Modifier>) -> MenuShortcut {
        MenuShortcut(key, modifiers)
    }

    private static func file(_ t: LocalizedStringResource, _ sc: MenuShortcut?, _ name: String) -> MenuEntry {
        MenuEntry(menu: .file, titleKey: t, shortcut: sc, identifier: "menu.file.\(name)", milestone: 7)
    }

    private static func view(_ t: LocalizedStringResource, _ sc: MenuShortcut?, _ name: String, milestone: Int = 7) -> MenuEntry {
        MenuEntry(menu: .view, titleKey: t, shortcut: sc, identifier: "menu.view.\(name)", milestone: milestone)
    }

    private static func trade(_ t: LocalizedStringResource, _ sc: MenuShortcut?, _ name: String) -> MenuEntry {
        MenuEntry(menu: .trade, titleKey: t, shortcut: sc, identifier: "menu.trade.\(name)", milestone: 7)
    }

    private static func game(_ t: LocalizedStringResource, _ sc: MenuShortcut?, _ name: String, milestone: Int = 7) -> MenuEntry {
        MenuEntry(menu: .game, titleKey: t, shortcut: sc, identifier: "menu.game.\(name)", milestone: milestone)
    }

    /// UI-ENC-034: `menu.encounter.<EncounterAction>` / `autoRepeat`, shortcuts from `EncounterKeys`, milestone 9.
    private static func encounterEntry(_ id: MenuItemID) -> MenuEntry {
        guard let action = id.encounterAction else {
            return MenuEntry(menu: .encounter, titleKey: "Auto-repeat", shortcut: EncounterKeys.autoRepeatToggle,
                             identifier: "menu.encounter.autoRepeat", milestone: 9)
        }
        let title: LocalizedStringResource = switch action {
        case .attack: "Attack"
        case .flee: "Flee"
        case .surrender: "Surrender"
        case .ignore: "Ignore"
        case .bribe: "Bribe"
        case .submit: "Submit"
        case .trade: "Trade"
        case .plunder: "Plunder"
        case .board: "Board"
        case .drink: "Drink"
        case .meet: "Meet"
        case .yield: "Yield"
        case .resolve: "Resolve"
        case .stop: "Stop"
        case .autoRepeat: "Auto-repeat"
        }
        return MenuEntry(menu: .encounter, titleKey: title, shortcut: EncounterKeys.shortcut(for: action),
                         identifier: "menu.encounter.\(action.rawValue)", milestone: 9)
    }

    private static func help(_ t: LocalizedStringResource, _ sc: MenuShortcut?, _ name: String) -> MenuEntry {
        MenuEntry(menu: .help, titleKey: t, shortcut: sc, identifier: "menu.help.\(name)", milestone: 7)
    }

    /// The identifier of an Open Recent row (`menu.file.openRecent.<n>`, n = 0…9).
    static func openRecentRowIdentifier(_ row: Int) -> String { "menu.file.openRecent.\(row)" }

    /// The custom items of a menu present at `milestone`, in menu order (MENU-014, -019, -024, -038, -039, -040).
    static func items(in menu: MenuName, milestone: Int = currentMilestone) -> [MenuItemID] {
        layout(menu).filter { entry(for: $0).milestone <= milestone }
    }

    /// Menu order including later-milestone items.
    static func layout(_ menu: MenuName) -> [MenuItemID] {
        switch menu {
        case .app: [.about]
        case .file: [.newGame, .quickStart, .open, .openRecent, .save, .saveAs, .revert, .importSave, .export, .closeGame]
        case .edit: [.find]
        case .view: [.bridge, .shipyard, .outfitter, .crew, .bank, .commanderStatus, .quests, .galaxy, .logbook, .options, .galaxyChart, .zoomIn,
                     .zoomOut, .zoomFit, .recentEvents]
        case .trade: [.tradeBuy, .tradeBuyMax, .tradeSell, .tradeSellAll, .sellAllCargo, .dumpCargo, .priceDetails, .buyFuelAmount, .fillFuel,
                      .repairAmount, .repair]
        case .game: [.warp, .previousTarget, .nextTarget, .track, .plotRoute, .jump, .newspaper, .retire]
        case .encounter: MenuItemID.encounterItems
        case .window: [.mainWindow, .galaxyChartWindow, .highScores]
        case .help: [.help, .prices, .shortcuts, .credits, .github]
        }
    }

    /// Items followed by a separator (MENU-014, MENU-024).
    static let separatorAfter: Set<MenuItemID> = [.openRecent, .revert, .closeGame, .options, .zoomFit, .tradeSellAll, .dumpCargo, .priceDetails,
                                                  .track, .jump, .newspaper]

    /// UI-NAV-011: the single-letter Trade keys; bound only while the Bridge is the page and no text field has the focus.
    static let letterKeyItems: Set<MenuItemID> = [.tradeBuy, .tradeBuyMax, .tradeSell, .tradeSellAll]

    /// Shortcuts that stay with standard macOS items (MENU-005).
    static let reservedShortcuts: Set<MenuShortcut> = [
        MenuShortcut("c"), MenuShortcut("v"), MenuShortcut("x"), MenuShortcut("a"), MenuShortcut("z"), MenuShortcut("z", [.shift, .command]),
        MenuShortcut("h"), MenuShortcut("h", [.option, .command]), MenuShortcut("m"), MenuShortcut("q"), MenuShortcut("w"),
        MenuShortcut(","), MenuShortcut("?"), MenuShortcut("g", [.shift, .command]),
    ]

    /// Items whose shortcut is the standard one of their role (Help ⌘?).
    static let standardRoleItems: Set<MenuItemID> = [.help]
}

extension MenuShortcut {
    /// The SwiftUI shortcut.
    var keyboardShortcut: KeyboardShortcut {
        var m: EventModifiers = []
        if modifiers.contains(.command) { m.insert(.command) }
        if modifiers.contains(.shift) { m.insert(.shift) }
        if modifiers.contains(.option) { m.insert(.option) }
        if modifiers.contains(.control) { m.insert(.control) }
        return KeyboardShortcut(KeyEquivalent(Character(key)), modifiers: m)
    }
}
