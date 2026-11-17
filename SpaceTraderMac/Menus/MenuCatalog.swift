// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// The menus of the menu bar that hold custom items (MENU §3).
nonisolated enum MenuName: String, CaseIterable, Sendable {
    case app, file, edit, view, game, encounter, window, help
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
    case bridge, market, shipyard, outfitter, crew, bank, galaxy, quests, logbook, galaxyChart, zoomIn, zoomOut, zoomFit
    // Game
    case warp, jump, previousTarget, nextTarget, track, findSystem, plotRoute, fillFuel, repair, newspaper, options, retire
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
        case .market: .market
        case .shipyard: .shipyard
        case .outfitter: .outfitter
        case .crew: .crew
        case .bank: .bank
        case .galaxy: .galaxy
        case .quests: .quests
        case .logbook: .logbook
        default: nil
        }
    }

    /// The View item of a section.
    static func item(for section: Section) -> MenuItemID {
        switch section {
        case .bridge: .bridge
        case .market: .market
        case .shipyard: .shipyard
        case .outfitter: .outfitter
        case .crew: .crew
        case .bank: .bank
        case .galaxy: .galaxy
        case .quests: .quests
        case .logbook: .logbook
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
        case .find: return MenuEntry(menu: .edit, titleKey: "Find…", shortcut: s("f", [.command]), identifier: "menu.edit.find", milestone: 7)
        case .bridge: return view("Bridge", s("1", [.command]), "bridge")
        case .market: return view("Market", s("2", [.command]), "market")
        case .shipyard: return view("Shipyard", s("3", [.command]), "shipyard")
        case .outfitter: return view("Outfitter", s("4", [.command]), "outfitter")
        case .crew: return view("Crew", s("5", [.command]), "crew")
        case .bank: return view("Bank", s("6", [.command]), "bank")
        case .galaxy: return view("Galaxy", s("7", [.command]), "galaxy", milestone: 8)
        case .quests: return view("Quests", s("8", [.command]), "quests")
        case .logbook: return view("Logbook", s("9", [.command]), "logbook", milestone: 10)
        case .galaxyChart: return view("Galaxy Chart", s("m", [.shift, .command]), "galaxyChart", milestone: 8)
        case .zoomIn: return view("Zoom In", s("+", [.command]), "zoomIn", milestone: 8)
        case .zoomOut: return view("Zoom Out", s("-", [.command]), "zoomOut", milestone: 8)
        case .zoomFit: return view("Fit", s("0", [.command]), "zoomFit", milestone: 8)
        case .warp: return game("Warp", s("j", [.command]), "warp")
        case .jump: return game("Use Singularity…", nil, "jump")
        case .previousTarget: return game("Previous Target", s("[", [.command]), "previousTarget")
        case .nextTarget: return game("Next Target", s("]", [.command]), "nextTarget")
        case .track: return game("Track Target", nil, "track")
        case .findSystem: return game("Find System…", s("f", [.option, .command]), "findSystem")
        case .plotRoute: return game("Plot Route…", nil, "plotRoute", milestone: 8)
        case .fillFuel: return game("Fill Fuel", s("f", [.shift, .command]), "fillFuel")
        case .repair: return game("Repair Hull", s("r", [.shift, .command]), "repair")
        case .newspaper: return game("Newspaper", s("n", [.shift, .command]), "newspaper", milestone: 9)
        case .options: return game("Options…", s("o", [.option, .command]), "options")
        case .retire: return game("Retire…", nil, "retire")
        case .encounterAttack, .encounterFlee, .encounterSurrender, .encounterIgnore, .encounterBribe, .encounterSubmit, .encounterTrade,
             .encounterPlunder, .encounterBoard, .encounterDrink, .encounterMeet, .encounterYield, .encounterAutoRepeat,
             .encounterResolve, .encounterStop:
            return encounterEntry(id)
        case .mainWindow: return MenuEntry(menu: .window, titleKey: "Parsec Merchant", shortcut: nil, identifier: "menu.window.main", milestone: 7)
        case .galaxyChartWindow:
            return MenuEntry(menu: .window, titleKey: "Galaxy Chart", shortcut: nil, identifier: "menu.window.galaxyChart", milestone: 8)
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
        case .view: [.bridge, .market, .shipyard, .outfitter, .crew, .bank, .galaxy, .quests, .logbook, .galaxyChart, .zoomIn, .zoomOut,
                     .zoomFit]
        case .game: [.warp, .jump, .previousTarget, .nextTarget, .track, .findSystem, .plotRoute, .fillFuel, .repair, .newspaper,
                     .options, .retire]
        case .encounter: MenuItemID.encounterItems
        case .window: [.mainWindow, .galaxyChartWindow, .highScores]
        case .help: [.help, .prices, .shortcuts, .credits, .github]
        }
    }

    /// Items followed by a separator (MENU-014, MENU-024).
    static let separatorAfter: Set<MenuItemID> = [.openRecent, .revert, .closeGame, .findSystem, .plotRoute, .repair, .newspaper, .options]

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
