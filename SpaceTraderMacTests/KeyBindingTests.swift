// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import SwiftUI
import Testing
@testable import ParsecMerchant

/// UI-KEYS §2 as a fixture: (action, display, context). Any new or changed binding must update the spec and this list.
enum KeyFixture {
    typealias Row = (action: String, display: String, context: String)

    static let menus: [Row] = [
        ("newGame", "⌘N", "global"), ("open", "⌘O", "global"), ("save", "⌘S", "global"), ("saveAs", "⇧⌘S", "global"),
        ("export", "⇧⌘E", "global"), ("find", "⌘F", "global"), ("bridge", "⌘1", "global"),
        ("shipyard", "⌘2", "global"), ("outfitter", "⌘3", "global"), ("crew", "⌘4", "global"), ("bank", "⌘5", "global"),
        ("commanderStatus", "⌘6", "global"), ("galaxy", "⌘8", "global"), ("quests", "⌘7", "global"), ("logbook", "⌘9", "global"),
        ("options", "⌥⌘O", "global"), ("galaxyChart", "⇧⌘M", "global"),
        ("zoomIn", "⌘+", "mapCanvas"), ("zoomOut", "⌘−", "mapCanvas"), ("zoomFit", "⌘0", "mapCanvas"), ("recentEvents", "⌘E", "global"),
        ("sellAllCargo", "⌥⌘S", "global"), ("priceDetails", "⌥⌘I", "global"), ("fillFuel", "⇧⌘F", "global"), ("repair", "⇧⌘R", "global"),
        ("warp", "⌘J", "global"), ("previousTarget", "⌘[", "global"), ("nextTarget", "⌘]", "global"),
        ("newspaper", "⇧⌘N", "global"), ("help", "⌘?", "global"),
        ("encounterAttack", "A", "encounter"), ("encounterFlee", "F", "encounter"), ("encounterSurrender", "S", "encounter"),
        ("encounterIgnore", "I", "encounter"), ("encounterBribe", "B", "encounter"), ("encounterSubmit", "U", "encounter"),
        ("encounterTrade", "T", "encounter"), ("encounterPlunder", "P", "encounter"), ("encounterBoard", "O", "encounter"),
        ("encounterDrink", "D", "encounter"), ("encounterMeet", "M", "encounter"), ("encounterYield", "Y", "encounter"),
        ("encounterAutoRepeat", "⌥A", "encounter"), ("encounterResolve", "R", "encounter"), ("encounterStop", "⎋", "encounter"),
    ]

    static let system: [Row] = [
        ("system.settings", "⌘,", "global"), ("system.hide", "⌘H", "global"), ("system.hideOthers", "⌥⌘H", "global"),
        ("system.quit", "⌘Q", "global"), ("system.closeWindow", "⌘W", "global"), ("system.closeAll", "⌥⌘W", "global"),
        ("system.undo", "⌘Z", "global"), ("system.redo", "⇧⌘Z", "global"), ("system.cut", "⌘X", "global"),
        ("system.copy", "⌘C", "global"), ("system.paste", "⌘V", "global"), ("system.selectAll", "⌘A", "global"),
        ("system.fullScreen", "⌃⌘F", "global"),
        ("system.minimize", "⌘M", "global"), ("system.minimizeAll", "⌥⌘M", "global"), ("system.cycleWindows", "⌘`", "global"),
        ("system.cycleWindowsBackward", "⇧⌘`", "global"),
    ]

    static let inView: [Row] = [
        ("market.buyOne", "B", "marketTable"), ("market.sellOne", "S", "marketTable"), ("market.buyMax", "⇧B", "marketTable"),
        ("market.sellAll", "⇧S", "marketTable"), ("market.selectPrevious", "↑", "marketTable"), ("market.selectNext", "↓", "marketTable"),
        ("market.buyTyped", "↩", "marketField"), ("market.sellTyped", "⇧↩", "marketField"),
        ("map.panLeft", "←", "mapCanvas"), ("map.panRight", "→", "mapCanvas"), ("map.panUp", "↑", "mapCanvas"),
        ("map.panDown", "↓", "mapCanvas"), ("zoomIn", "⌘=", "mapCanvas"), ("zoomOut", "⌘−", "mapCanvas"),
        ("zoomFit", "⌘0", "mapCanvas"), ("window.escape", "⎋", "mapCanvas"),
        ("search.previous", "↑", "searchField"), ("search.next", "↓", "searchField"), ("search.choose", "↩", "searchField"),
        ("window.escape", "⎋", "searchField"), ("window.escape", "⎋", "searchField"), ("window.escape", "⎋", "searchField"),
        ("encounter.defaultAction", "↩", "encounter"),
        ("quickStart", "↩", "mainWindow(welcome)"), ("newGame", "↩", "mainWindow(gameOver)"), ("transit.skip", "↩", "transit"),
        ("transit.skip", "⎋", "transit"), ("encounterStop", "⎋", "encounter"), ("window.escape", "⎋", "mainWindow(docked)"),
    ]

    /// §2.3: (surface, Return button, Esc button).
    static let sheets: [(String, String, String)] = [
        ("newGame", "next", "cancel"), ("openSavedGame", "open", "cancel"),
        ("findSystem", "select", "cancel"), ("shipPurchase", "buy", "cancel"), ("retire", "cancel", "cancel"),
        ("cheatConsole", "run", "close"), ("tradeInOrbit", "trade", "decline"), ("plunder", "done", "done"),
        ("jettison", "jettison", "cancel"), ("dump", "dump", "cancel"), ("newspaper", "close", "close"),
        ("narrativeOffer", "accept", "decline"), ("narrativeMessage", "continue", "continue"), ("report", "continue", "continue"),
        ("systemIntel", "done", "done"), ("about", "done", "done"), ("developerTester", "close", "close"),
        ("priceDetails", "done", "done"), ("serviceAmount", "buy", "cancel"),
        ("confirmationDestructive", "cancel", "cancel"), ("confirmation", "confirm", "cancel"), ("systemAlert", "ok", "ok"),
    ]

    static var all: [Row] {
        let sheetRows = sheets.flatMap { s -> [Row] in
            let context = s.0 == "systemAlert" ? "dialog" : "sheet(\(s.0))"
            return [("sheet.\(s.0).\(s.1)", "↩", context), ("sheet.\(s.0).\(s.2)", "⎋", context)]
        }
        return menus + system + inView + sheetRows
    }
}

@MainActor
@Suite("Keyboard: binding table and audit (UI-KEYS)")
struct KeyBindingTests {
    private func key(_ r: KeyFixture.Row) -> String { "\(r.action)|\(r.display)|\(r.context)" }

    // MARK: §1

    @Test("UI-KEYS-001 MENU-045 every MenuCatalog shortcut appears exactly once with owner .menu; in-view handlers accept exactly their bindings")
    func singleSource() {
        let all = KeyBindingTable.all
        for id in MenuItemID.allCases {
            let matches = all.filter { if case .menu(id) = $0.owner { true } else { false } }
            if MenuCatalog.letterKeyItems.contains(id) {
                // UI-NAV-011: the Trade menu shows the Cargo rows' own keys, which the table lists once (`MarketKeyAction`).
                #expect(matches.isEmpty && MarketKeyAction.bindings.contains { $0.shortcut == MenuCatalog.entry(for: id).shortcut }, "\(id)")
            } else if let sc = MenuCatalog.entry(for: id).shortcut {
                #expect(matches.count == 1 && matches.first?.shortcut == sc, "\(id)")
            } else {
                #expect(matches.isEmpty, "\(id)")
            }
        }
        // Market: every key × modifier combination is accepted iff the table's bindings list it.
        let marketKeys = Set(MarketKeyAction.bindings.filter { $0.context == .marketTable && $0.shortcut.key.count == 1 }
            .map { NormalizedShortcut(physical: $0.shortcut) })
        let combos: [EventModifiers] = [[], .shift, .command, .option, .control, [.shift, .command], [.shift, .option], [.command, .option]]
        for c in "abcdefghijklmnopqrstuvwxyz" {
            for m in combos {
                let typed = m.contains(.shift) ? String(c).uppercased() : String(c)
                let accepted = MarketKeyAction.make(characters: typed, modifiers: m) != nil
                let listed = marketKeys.contains(NormalizedShortcut(physical: MenuShortcut(String(c), MenuShortcut.modifiers(m))))
                #expect(accepted == listed, "\(typed) \(m.rawValue)")
            }
        }
        // Map canvas: the handler accepts exactly the canvas bindings.
        let mapListed = MapKeys.bindings.filter { $0.context == .mapCanvas }.map(\.shortcut)
        for sc in mapListed { #expect(MapKeys.action(for: sc) != nil, "\(sc.display)") }
        let others = [MenuShortcut("=", []), MenuShortcut("-", [.option]), MenuShortcut(MenuShortcut.leftArrowKey, [.command]),
                      MenuShortcut("b", []), MenuShortcut(MenuShortcut.returnKey, [])]
        for sc in others { #expect(MapKeys.action(for: sc) == nil, "\(sc.display)") }
        #expect(MapKeys.action(for: MenuShortcut("=", [.command])) == .zoomIn)
        #expect(MapKeys.action(for: MenuShortcut(MenuShortcut.rightArrowKey, [])) == .pan(dx: 1, dy: 0))
    }

    @Test("UI-KEYS-002 MAP-098 Help › Keyboard Shortcuts: one row per binding, grouped in §2 order, English titles, ⌘= right after ⌘+")
    func helpPage() {
        let page = KeyboardShortcutsPage.make()
        let rows = page.flatMap(\.rows)
        #expect(rows.count == KeyBindingTable.all.count)
        #expect(page.map(\.group) == ShortcutGroup.allCases)
        for r in rows { #expect(!r.title.isEmpty && !r.display.isEmpty, "\(r.action)") }
        let map = page.first { $0.group == .galaxyMap }?.rows ?? []
        let plus = map.firstIndex { $0.display == "⌘+" }
        let alias = map.firstIndex { $0.display == "⌘=" }
        #expect(plus != nil && alias == plus.map { $0 + 1 })
        // MAP-098: the map keys of MAP-015 are listed.
        for glyph in ["←", "→", "↑", "↓", "⌘−", "⌘0", "⎋"] { #expect(map.contains { $0.display == glyph }, "\(glyph)") }
        let text = HelpContent.text(.keyboardShortcuts)
        #expect(text.contains("## Menus") && text.contains("## Sheets and dialogs") && text.contains("**⌘J**  Warp"))
    }

    @Test("UI-KEYS-003 the binding table equals the §2 fixture")
    func fixture() {
        let actual = KeyBindingTable.all.map { key(($0.action.rawValue, $0.shortcut.display, $0.context.description)) }.sorted()
        let expected = KeyFixture.all.map(key).sorted()
        #expect(actual == expected)
        let a = Set(actual), e = Set(expected)
        #expect(a.subtracting(e).isEmpty, "not in the spec: \(a.subtracting(e).sorted())")
        #expect(e.subtracting(a).isEmpty, "missing: \(e.subtracting(a).sorted())")
    }

    @Test("UI-KEYS-004 display glyphs: ⌃⌥⇧⌘ order, ⎋ in menus and Esc on key caps, ↩ ⇥ arrows, uppercase letters")
    func glyphs() {
        #expect(MenuShortcut("s", [.command, .shift, .option, .control]).display == "⌃⌥⇧⌘S")
        #expect(MenuShortcut(EncounterKeys.escapeKey, []).display == "⎋" && EncounterKeys.keyCap(for: .stop) == "Esc")
        #expect(MenuShortcut(MenuShortcut.returnKey, [.shift]).display == "⇧↩" && MenuShortcut(MenuShortcut.tabKey, []).display == "⇥")
        #expect([MenuShortcut.leftArrowKey, MenuShortcut.rightArrowKey, MenuShortcut.upArrowKey, MenuShortcut.downArrowKey]
            .map { MenuShortcut($0, []).display } == ["←", "→", "↑", "↓"])
        #expect(MenuShortcut("a", []).display == "A")
        let order: [Character] = ["⌃", "⌥", "⇧", "⌘"]
        for b in KeyBindingTable.all {
            let d = b.shortcut.display
            let mods = d.filter { order.contains($0) }
            #expect(mods.map { order.firstIndex(of: $0) ?? 0 } == mods.map { order.firstIndex(of: $0) ?? 0 }.sorted(), "\(d)")
            #expect(d == d.uppercased() || d.contains("Space"), "\(d)")
            #expect(!d.unicodeScalars.contains { $0.value >= 0xF700 && $0.value <= 0xF8FF }, "\(d) shows a private-use key")
        }
    }

    // MARK: §3

    static let contexts: [KeyContext] = [.global, .marketTable, .marketField, .mapCanvas, .searchField, .textField, .encounter, .transit,
                                         .dialog, .sheet("retire"), .sheet("plunder")]
        + DetailModeKind.allCases.map { .mainWindow($0) }

    @Test("UI-KEYS-005 KeyContext.canCoexist is symmetric and has the listed exclusions")
    func coexistence() {
        for a in Self.contexts {
            for b in Self.contexts { #expect(KeyContext.canCoexist(a, b) == KeyContext.canCoexist(b, a), "\(a) \(b)") }
            #expect(KeyContext.canCoexist(.global, a))
        }
        let mainWindow: [KeyContext] = [.marketTable, .marketField, .mapCanvas, .searchField, .encounter, .transit]
            + DetailModeKind.allCases.map { .mainWindow($0) }
        for sheet in [KeyContext.sheet("retire"), .dialog] {
            for m in mainWindow { #expect(!KeyContext.canCoexist(sheet, m), "\(sheet) \(m)") }
        }
        #expect(!KeyContext.canCoexist(.sheet("retire"), .sheet("plunder")))
        #expect(KeyContext.canCoexist(.sheet("plunder"), .textField))
        for c in [KeyContext.marketTable, .marketField, .mainWindow(.docked)] { #expect(!KeyContext.canCoexist(.encounter, c), "\(c)") }
        for f in [KeyContext.textField, .searchField] {
            #expect(!KeyContext.canCoexist(f, .marketTable) && !KeyContext.canCoexist(f, .mapCanvas))
        }
        #expect(KeyContext.canCoexist(.mainWindow(.docked), .marketTable) && KeyContext.canCoexist(.mainWindow(.docked), .mapCanvas))
        #expect(!KeyContext.canCoexist(.mainWindow(.welcome), .marketTable))
    }

    /// The situations of UI-KEYS-006: MENU-015's contexts plus encounters, the focused Market table and the focused map.
    private func situations() -> [(String, MenuContext, Set<KeyContext>)] {
        let fx = MenuFixtures.self
        let docked = fx.ctx(fx.targeted())
        var mapFocused = docked
        mapFocused.focusedMap = .galaxy
        var out: [(String, MenuContext, Set<KeyContext>)] = [
            ("no game", fx.ctx(nil), [.mainWindow(.welcome)]),
            ("ended", fx.ctx(fx.ended), [.mainWindow(.gameOver)]),
            ("ironman", fx.ctx(fx.ironman), [.mainWindow(.docked)]),
            ("docked + Market table", docked, [.mainWindow(.docked), .marketTable]),
            ("docked + quantity field", docked, [.mainWindow(.docked), .marketField]),
            ("docked + search field", docked, [.mainWindow(.docked), .searchField]),
            ("docked + text field", docked, [.mainWindow(.docked), .textField]),
            ("docked + map", mapFocused, [.mainWindow(.docked), .mapCanvas]),
            ("transit", fx.ctx(fx.targeted()), [.transit]),
        ]
        for surface in SheetSurface.allCases {
            out.append(("modal \(surface)", fx.ctx(fx.targeted(), modal: true), [surface.context, .textField]))
        }
        for type in [EncounterType.pirateAttack, .policeInspect, .traderIgnore] {
            out.append(("encounter \(type)", fx.ctx(AudioFixtures.encounter(type: type)), [.encounter]))
        }
        return out
    }

    @Test("UI-KEYS-006 MENU-045 no conflicts: equal keys in coexisting contexts carry the same action, also under MenuRules")
    func noConflicts() {
        let all = KeyBindingTable.all
        let conflicts = KeyAudit.staticConflicts(all)
        #expect(conflicts.isEmpty, "\(conflicts.map(\.description))")
        for (name, ctx, active) in situations() {
            let live = KeyAudit.liveConflicts(all, active: active) { MenuRules.availability(of: $0, in: ctx).isEnabled }
            #expect(live.isEmpty, "\(name): \(live.map(\.description))")
        }
    }

    @Test("UI-KEYS-007 normalization: case, shifted symbols, ⌘+ = ⌘=, Esc = ⌘.")
    func normalization() {
        #expect(NormalizedShortcut(MenuShortcut("S", [.command])) == NormalizedShortcut(MenuShortcut("s", [.shift, .command])))
        #expect(NormalizedShortcut(MenuShortcut("s", [.command])) != NormalizedShortcut(MenuShortcut("s", [.shift, .command])))
        #expect(NormalizedShortcut(MenuShortcut("?", [.command])) == NormalizedShortcut(MenuShortcut("/", [.shift, .command])))
        #expect(NormalizedShortcut(MenuShortcut("+", [.command])) == NormalizedShortcut(MenuShortcut("=", [.command])))
        #expect(NormalizedShortcut(MenuShortcut(EncounterKeys.escapeKey, [])) == NormalizedShortcut(MenuShortcut(".", [.command])))
        #expect(NormalizedShortcut(physical: MenuShortcut(EncounterKeys.escapeKey, []))
            != NormalizedShortcut(physical: MenuShortcut(".", [.command])))
    }

    @Test("UI-KEYS-008 UI-KEYS-024 MENU-045 no custom binding uses a reserved macOS 27 or Full Keyboard Access shortcut; ⇥ and Space stay free")
    func reserved() {
        for b in KeyBindingTable.all where b.owner.isCustom {
            if case let .menu(id) = b.owner, MenuCatalog.standardRoleItems.contains(id) { continue }
            #expect(!SystemShortcuts.isReserved(b.shortcut), "\(b.owner) \(b.shortcut.display)")
            #expect(b.shortcut.key != MenuShortcut.tabKey && b.shortcut.key != " ", "\(b.owner)")
            let arrows = [MenuShortcut.upArrowKey, MenuShortcut.downArrowKey, MenuShortcut.leftArrowKey, MenuShortcut.rightArrowKey]
            if arrows.contains(b.shortcut.key) { #expect(b.context.isFocusedView, "\(b.owner) binds an arrow outside a focused view") }
        }
        #expect(SystemShortcuts.isReserved(MenuShortcut("a", [.control, .option])))
        #expect(SystemShortcuts.isReserved(MenuShortcut(" ", [.command])) && SystemShortcuts.isReserved(MenuShortcut("g", [.command])))
        #expect(SystemShortcuts.reserved.contains(NormalizedShortcut(physical: MenuShortcut("F5", [.command]))))
        #expect(!SystemShortcuts.isReserved(MenuShortcut("j", [.command])))
        // The system items keep their standard keys.
        for b in SystemMenuItem.keptShortcuts { #expect(SystemShortcuts.standardItems.contains(NormalizedShortcut(physical: b.shortcut))) }
    }

    @Test("UI-KEYS-009 standard items keep their standard shortcuts outside MenuCatalog; Help ⌘? is the only standard-list catalog key")
    func standardItems() {
        let standard: [MenuShortcut] = [MenuShortcut(","), MenuShortcut("w"), MenuShortcut("m"), MenuShortcut("f", [.control, .command]),
                                        MenuShortcut("s", [.control, .command]), MenuShortcut("i", [.control, .command])]
        for id in MenuItemID.allCases {
            guard let sc = MenuCatalog.entry(for: id).shortcut else { continue }
            #expect(!standard.contains(sc), "\(id)")
            let inStandardList = SystemShortcuts.standardItems.contains(NormalizedShortcut(physical: sc))
            #expect(inStandardList == MenuCatalog.standardRoleItems.contains(id), "\(id)")
        }
    }

    // MARK: §4

    @Test("UI-KEYS-012 Market keys are plain B/S and ⇧B/⇧S only; nothing with ⌘, ⌥ or ⌃")
    func marketKeys() {
        #expect(MarketKeyAction.make(characters: "s", modifiers: .command) == nil)
        #expect(MarketKeyAction.make(characters: "S", modifiers: [.shift, .command]) == nil)
        #expect(MarketKeyAction.make(characters: "b", modifiers: .option) == nil)
        #expect(MarketKeyAction.make(characters: "b", modifiers: .control) == nil)
        #expect(MarketKeyAction.make(characters: "B", modifiers: .shift) == .buyMax)
        #expect(MarketKeyAction.make(characters: "S", modifiers: .shift) == .sellAll)
        #expect(MarketKeyAction.make(characters: "b", modifiers: []) == .buy)
        #expect(MarketKeyAction.make(characters: "s", modifiers: .capsLock) == .sell)
    }

    @Test("UI-KEYS-015 the Encounter and Market letters B and S never coexist")
    func lettersNeverCoexist() {
        let all = KeyBindingTable.all
        for letter in ["b", "s"] {
            let enc = all.filter { $0.context == .encounter && $0.shortcut == MenuShortcut(letter, []) }
            let market = all.filter { $0.context == .marketTable && $0.shortcut == MenuShortcut(letter, []) }
            #expect(enc.count == 1 && market.count == 1)
            #expect(!KeyContext.canCoexist(.encounter, .marketTable))
        }
        for (name, ctx, _) in situations() where ctx.phase != .encounter {
            for id: MenuItemID in [.encounterBribe, .encounterSurrender] {
                #expect(!MenuRules.availability(of: id, in: ctx).isEnabled, "\(name) \(id)")
            }
        }
    }

    // MARK: §5

    @Test("UI-KEYS-017 Esc priority: dialog, sheet, field, map overlay, Stop, Skip, feed, compare, else nothing")
    func escapeRouter() {
        var c = EscapeContext()
        #expect(EscapeRouter.target(in: c) == nil)
        c.compareSelection = true
        #expect(EscapeRouter.target(in: c) == .clearCompare)
        c.feedOpen = true
        #expect(EscapeRouter.target(in: c) == .closeFeed)
        c.transitPlaying = true
        #expect(EscapeRouter.target(in: c) == .skipTransit)
        c.encounterCanStop = true
        #expect(EscapeRouter.target(in: c) == .stopEncounter)
        c.mapOverlayOpen = true
        #expect(EscapeRouter.target(in: c) == .closeMapOverlay)
        c.fieldHasText = true
        #expect(EscapeRouter.target(in: c) == .clearField)
        c.sheet = .tradeInOrbit
        #expect(EscapeRouter.target(in: c) == .sheet(.decline))
        c.dialogShown = true
        #expect(EscapeRouter.target(in: c) == .dialogCancel)
        #expect(EscapeRouter.target(in: EscapeContext(sheet: .plunder)) == .sheet(.done))
        #expect(EscapeRouter.target(in: EscapeContext(feedOpen: true, compareSelection: true)) == .closeFeed)
    }

    @Test("UI-KEYS-018 the window router runs registered handlers by level and each view removes only its own handler")
    func escapeRegistry() throws {
        let session = try TestSessions.playing()
        let registry = EscapeRegistry()
        var log: [String] = []
        let feed = UUID(), compare = UUID(), other = UUID()
        registry.register(.closeFeed, owner: feed) { log.append("feed") }
        registry.register(.clearCompare, owner: compare) { log.append("compare") }
        #expect(registry.handle(session: session))
        registry.register(.closeFeed, owner: feed, action: nil)
        #expect(registry.handle(session: session))
        #expect(log == ["feed", "compare"])
        registry.register(.clearCompare, owner: other, action: nil)
        #expect(registry.isActive(.clearCompare))
        registry.register(.clearCompare, owner: compare, action: nil)
        #expect(!registry.handle(session: session))
    }

    @Test("UI-KEYS-020 UI-KEYS-023 SheetKeys covers every SheetRoute; no destructive default; destructive confirmations default to Cancel")
    func sheetKeys() throws {
        let state = MenuFixtures.fresh()
        let pending = PendingConfirmation(command: .retire, confirmation: Confirmation(.retire, amounts: [1]), acknowledged: [])
        let routes: [SheetRoute] = [
            .newGame, .openSavedGame, .findSystem, .shipPurchase(.ship(.gnat)), .retire(pending), .cheatConsole,
            .tradeInOrbit(try RouteFixtures.offer()),
            .plunder(PlunderSheetContext(victimCargo: Array(repeating: 0, count: 10), source: .opponent)),
            .newspaper(try RouteFixtures.paper()), .narrative(.offer(.skill)),
            .narrative(.result(NarrativeResult(type: nil, title: "T", message: "M"))), .report(.arrest(ArrestReport())), .developerTester,
        ]
        for route in routes {
            let surface = SheetKeys.surface(for: route)
            #expect(surface.context == .sheet(surface.rawValue))
            #expect(!SheetKeys.table(for: route).defaultIsDestructive, "\(route.key)")
        }
        #expect(Set(routes.map { SheetKeys.surface(for: $0) }).count == routes.count)
        for s in SheetSurface.allCases { #expect(!SheetKeys.roles(s).defaultIsDestructive, "\(s)") }
        #expect(SheetKeys.table(for: .retire(pending)) == SheetKeyRoles(defaultAction: .cancel, escapeAction: .cancel))
        for w in WarningID.allCases {
            let c = ConfirmationText.content(for: Confirmation(w, amounts: [1_234, 56]), state: state)
            let roles = SheetKeys.roles(SheetKeys.dialogSurface(isDestructive: c.isDestructive))
            if c.isDestructive { #expect(roles == SheetKeyRoles(defaultAction: .cancel, escapeAction: .cancel), "\(w)") }
            #expect(DialogButtonPlan.make(isDestructive: c.isDestructive).cancelIsDefault == c.isDestructive, "\(w)")
        }
        let session = try TestSessions.make()
        for kind in AppConfirmationKind.allCases {
            let c = AppConfirmationText.content(for: kind.sample, session: session)
            let plan = DialogButtonPlan.make(isDestructive: c.isDestructive)
            #expect(plan.cancelIsDefault == c.isDestructive && plan.confirmIsDefault == !c.isDestructive, "\(kind)")
        }
    }

    // MARK: §7

    @Test("UI-KEYS-033 a menu title ends with … iff the item asks for more input first")
    func ellipsis() {
        let expected: Set<MenuItemID> = [.newGame, .open, .saveAs, .importSave, .export, .find, .plotRoute, .retire,
                                         .jump, .priceDetails, .buyFuelAmount, .repairAmount, .dumpCargo]
        for id in MenuItemID.allCases {
            let title = String(localized: MenuCatalog.entry(for: id).titleKey)
            #expect(title.hasSuffix("…") == expected.contains(id), "\(id) \(title)")
        }
    }

    @Test("UI-KEYS-035 menu titles use Title Case: every word capitalized except short articles, conjunctions and prepositions")
    func menuTitleCase() {
        let minor: Set<String> = ["a", "an", "the", "and", "but", "or", "nor", "for", "to", "of", "in", "on", "at", "by", "as", "via"]
        for id in MenuItemID.allCases {
            let title = String(localized: MenuCatalog.entry(for: id).titleKey)
            let words = title.split(separator: " ").map { $0.trimmingCharacters(in: CharacterSet.letters.inverted) }.filter { !$0.isEmpty }
            for (i, word) in words.enumerated() where i == 0 || i == words.count - 1 || !minor.contains(word.lowercased()) {
                #expect(word.first?.isUppercase == true || word.first?.isNumber == true, "\(id) “\(title)”: “\(word)” is not capitalized")
            }
        }
    }
}
