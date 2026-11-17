// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import Foundation
import ParsecEngine
import ParsecPersistence
import Testing
@testable import ParsecMerchant

/// Fixture contexts and states for the menu rules.
@MainActor
enum MenuFixtures {
    static func fresh(_ r: RulesetID = .modern, seed: UInt64 = 1) -> GameState {
        GameState(config: NewGameConfig(commanderName: "Menu", ruleset: r, seed: seed))
    }

    /// A docked game with a target in range.
    static func targeted(_ r: RulesetID = .modern) -> GameState {
        var s = fresh(r)
        if let d = s.destinations.first { s.warpSystem = d }
        return s
    }

    static func ctx(_ state: GameState?, modal: Bool = false) -> MenuContext {
        MenuContext.make(state: state, isModal: modal)
    }

    static var ended: GameState {
        var s = fresh()
        s.phase = .gameOver(.retired)
        return s
    }

    static var ironman: GameState {
        var s = fresh()
        s.ironman = true
        return s
    }

    /// A state in an encounter, reached by play (Quick Start games warping until one starts).
    static func encounterState() -> GameState? {
        for seed in UInt64(1)...60 {
            var e = GameEngine(config: NewGameConfig(commanderName: "Menu", seed: seed))
            for _ in 0..<4 {
                e.perform(.selectNextTarget(forward: true))
                e.perform(.warp)
                if case .encounter = e.state.phase { return e.state }
                guard e.state.phase == .docked else { break }
            }
        }
        return nil
    }

    /// The contexts of MENU-015.
    static var named: [(String, MenuContext)] {
        [("no game", ctx(nil)), ("docked", ctx(targeted())), ("ironman", ctx(ironman)), ("ended", ctx(ended)),
         ("modal", ctx(targeted(), modal: true))]
    }
}

@MainActor
@Suite("Menu bar")
struct MenuTests {
    private typealias Fx = MenuFixtures

    private func on(_ id: MenuItemID, _ c: MenuContext) -> Bool { MenuRules.availability(of: id, in: c).isEnabled }

    private func encounter() throws -> GameState {
        let found: GameState? = Fx.encounterState()
        return try #require(found, "no encounter reached in the fixture seeds")
    }

    // MARK: Model (§1)

    @Test("MENU-001 one catalog entry per MenuItemID case")
    func catalogCoversCases() {
        let ids = MenuItemID.allCases.map { MenuCatalog.entry(for: $0).identifier }
        #expect(Set(ids).count == MenuItemID.allCases.count)
        let laidOut = MenuName.allCases.flatMap(MenuCatalog.layout)
        #expect(Set(laidOut) == Set(MenuItemID.allCases) && laidOut.count == MenuItemID.allCases.count)
    }

    @Test("MENU-002 MenuContext is built from the session with no engine reference")
    func contextFromSession() throws {
        let s = try TestSessions.make()
        var c = MenuContext.make(session: s)
        #expect(c == .noGame || (!c.hasGame && c.phase == .none && c.recentSlots.isEmpty))
        s.requestQuickStart()
        c = MenuContext.make(session: s)
        #expect(c.hasGame && c.phase == .docked && !c.isModal && !c.isIronman && c.targetIsCurrentSystem)
        #expect(c.hasDestinations && !c.canBuyFuel && !c.canRepair && c.selectedSection == .bridge && c.searchContext == .other)
        #expect(c.focusedMap == nil && !c.galaxyIsKey)
        #expect(MenuContext.make(session: s, focusedMap: .galaxyWindow).focusedMap == .galaxyWindow)
        #expect(c.recentSlots.count == 1, "the creation autosave is listed")
        s.selectedSection = .market
        s.present(.sheet(.gameOptions))
        c = MenuContext.make(session: s)
        #expect(c.isModal && c.searchContext == .market)
    }

    @Test("MENU-003 catalog identifiers follow menu.<menu>.<item> and the AXID scheme; titles are localized resources")
    func catalogIdentifiers() throws {
        let regex = try Regex(AXID.pattern)
        for id in MenuItemID.allCases {
            let e = MenuCatalog.entry(for: id)
            #expect(e.identifier.hasPrefix("menu.\(e.menu.rawValue).") && e.identifier.wholeMatch(of: regex) != nil)
            #expect(!String(localized: e.titleKey).isEmpty)
        }
        #expect(MenuCatalog.entry(for: .save).identifier == "menu.file.save")
        #expect(MenuCatalog.entry(for: .warp).identifier == "menu.game.warp")
        #expect(MenuCatalog.entry(for: .warp).shortcut?.display == "⌘J")
        #expect(AXID.Menu.all.contains("menu.file.openRecent.9"))
    }

    @Test("MENU-004 MenuRules decides every item in every fixture context (exhaustive switch)")
    func rulesTotal() {
        for (_, c) in Fx.named {
            for id in MenuItemID.allCases {
                let a = MenuRules.availability(of: id, in: c)
                #expect(a.isEnabled == (a.reason == nil))
            }
        }
        // The toolbar Warp button uses the same rule.
        let st = Fx.targeted()
        #expect(WarpButtonModel.make(state: st, isModal: false).isEnabled == MenuRules.warp(Fx.ctx(st)).isEnabled)
        #expect(WarpButtonModel.make(state: Fx.fresh(), isModal: false).help == DisabledReason.targetIsCurrentSystem.text)
    }

    @Test("MENU-005 shortcut hygiene: unique, no standard shortcuts, every shortcut has ⌘ or ⌃")
    func shortcutHygiene() {
        var seen: Set<MenuShortcut> = []
        for id in MenuItemID.allCases {
            guard let sc = MenuCatalog.entry(for: id).shortcut else { continue }
            #expect(!seen.contains(sc), "duplicate shortcut \(sc.display)")
            seen.insert(sc)
            if !MenuCatalog.standardRoleItems.contains(id) {
                #expect(!MenuCatalog.reservedShortcuts.contains(sc), "\(id) uses reserved \(sc.display)")
            }
            // MENU-037: only the Encounter menu has shortcuts without ⌘ or ⌃ (UI-ENC-035 checks them).
            if MenuCatalog.entry(for: id).menu != .encounter {
                #expect(sc.modifiers.contains(.command) || sc.modifiers.contains(.control))
            }
        }
    }

    @Test("MENU-006 while modal every File, View and Game item is disabled; app, Window and Help items stay enabled")
    func modalDisables() {
        let c = Fx.ctx(Fx.targeted(), modal: true)
        for id in MenuItemID.allCases {
            let menu = MenuCatalog.entry(for: id).menu
            switch menu {
            case .file, .edit, .view, .game, .encounter: #expect(!on(id, c), "\(id)")
            case .app, .window, .help: #expect(on(id, c), "\(id)")
            }
        }
        #expect(!MenuRules.recentRowAvailability(0, in: c).isEnabled)
    }

    @Test("MENU-007 the menus are declared once with fixed Open Recent rows; item views read the session")
    func declaredOnce() throws {
        #expect(MenuCatalog.openRecentRows == 10)
        let s = try TestSessions.make()
        let commands = MenuCommands(session: s, helpRouter: HelpRouter())
        #expect(commands.session === s)
        // A context change is visible on the next read without rebuilding anything.
        #expect(!MenuRules.availability(of: .save, in: .make(session: s)).isEnabled)
        s.requestQuickStart()
        #expect(MenuRules.availability(of: .save, in: .make(session: s)).isEnabled)
    }

    @Test("MENU-008 every custom item carries its catalog identifier (UI tests fall back to English titles)")
    func identifiersRegistered() {
        let all = Set(AXID.all)
        for id in MenuItemID.allCases { #expect(all.contains(MenuCatalog.entry(for: id).identifier)) }
        #expect(String(localized: MenuCatalog.entry(for: .retire).titleKey) == "Retire…")
    }

    // MARK: Common rules (§2)

    @Test("MENU-009 game command: a loaded docked game and nothing modal")
    func gameCommand() throws {
        #expect(MenuRules.gameCommand(Fx.ctx(Fx.fresh())).isEnabled)
        #expect(MenuRules.gameCommand(Fx.ctx(nil)).reason == .noGame)
        #expect(MenuRules.gameCommand(Fx.ctx(Fx.ended)).reason == .gameEnded)
        #expect(MenuRules.gameCommand(Fx.ctx(Fx.fresh(), modal: true)).reason == .modal)
        let enc = try encounter()
        #expect(MenuRules.gameCommand(Fx.ctx(enc)).reason == .notDocked)
        var transit = Fx.ctx(Fx.fresh())
        transit.phase = .inTransit
        #expect(MenuRules.gameCommand(transit).reason == .notDocked)
    }

    @Test("MENU-010 session command: anything not modal")
    func sessionCommand() {
        #expect(MenuRules.sessionCommand(Fx.ctx(nil)).isEnabled && MenuRules.sessionCommand(Fx.ctx(Fx.ended)).isEnabled)
        #expect(!MenuRules.sessionCommand(Fx.ctx(nil, modal: true)).isEnabled)
    }

    // MARK: Application menu

    @Test("MENU-011 About replaces the standard panel, opens the about window and is always enabled")
    func about() {
        #expect(MenuCatalog.entry(for: .about).identifier == "menu.app.about" && AppWindowID.about == "about")
        for (_, c) in Fx.named { #expect(on(.about, c)) }
    }

    @Test("MENU-012 Settings is the Settings scene's standard item; no custom item takes ⌘,")
    func settingsItem() {
        #expect(!MenuItemID.allCases.contains { MenuCatalog.entry(for: $0).shortcut == MenuShortcut(",") })
        #expect(SettingsTab.allCases.count == 4)
    }

    @Test("MENU-013 quitting writes the autosave (or Ironman slot) and terminates without asking")
    func quitWritesAutosave() throws {
        let s = try TestSessions.playing()
        try TestSessions.edit(s) { $0.commander.cash = 4_321 }
        s.writeOnQuit()
        let info = try s.slotStore.info(slot: SlotStore.autosaveID)
        #expect(info.gameID == s.gameID)
        #expect(try s.slotStore.load(slot: SlotStore.autosaveID).state.commander.cash == 4_321)
        #expect(s.presentation == nil)
        if let delegate = NSApp.delegate as? AppDelegate {
            #expect(delegate.applicationShouldTerminate(NSApp) == .terminateNow)
        }
    }

    // MARK: File

    @Test("MENU-014 the File menu rows in order, with separators after Open Recent, Revert and Close Game")
    func fileOrder() {
        #expect(MenuCatalog.items(in: .file) == [.newGame, .quickStart, .open, .openRecent, .save, .saveAs, .revert, .importSave,
                                                 .export, .closeGame])
        #expect(MenuCatalog.separatorAfter.isSuperset(of: [.openRecent, .revert, .closeGame]))
        #expect(MenuCatalog.entry(for: .newGame).shortcut == MenuShortcut("n"))
    }

    @Test("MENU-015 File enablement over no game, docked, Ironman, encounter, ended and modal")
    func fileEnablement() throws {
        let enc = Fx.ctx(try encounter())
        let contexts = Fx.named + [("encounter", enc)]
        for (name, c) in contexts {
            let modal = c.isModal
            for id: MenuItemID in [.newGame, .quickStart, .open, .importSave] { #expect(on(id, c) == !modal, "\(name) \(id)") }
            let live = c.hasGame && c.phase != .gameOver && !modal
            #expect(on(.save, c) == live, "\(name)")
            #expect(on(.saveAs, c) == (live && !c.isIronman), "\(name)")
            #expect(on(.revert, c) == (c.canRevertToAutosave && !modal), "\(name)")
            #expect(on(.export, c) == (c.hasGame && !modal) && on(.closeGame, c) == (c.hasGame && !modal), "\(name)")
        }
        var revertable = Fx.ctx(Fx.fresh())
        revertable.canRevertToAutosave = true
        #expect(on(.revert, revertable))
    }

    @Test("MENU-016 Open Recent: the 10 newest slots titled with commander, day, system and ruleset, plus suffixes")
    func openRecent() throws {
        let s = try TestSessions.playing()
        var ended = try #require(s.state)
        ended.ironman = true
        ended.phase = .gameOver(.killed)
        _ = try s.slotStore.save(ended, slot: SlotStore.newSlotID(), gameID: "g2")
        for _ in 0..<11 { s.saveAs() }
        let c = MenuContext.make(session: s)
        #expect(c.recentSlots.count == 10)
        let slots = s.listSlots()
        #expect(c.recentSlots.map(\.id) == slots.prefix(10).map(\.id))
        let st = try #require(s.state)
        let first = try #require(slots.first)
        #expect(c.recentSlots[0].title == "Menu — Day 0, \(Names.system(st.commander.currentSystem, in: st)) (Modern)"
            || c.recentSlots[0].title == SlotText.recentTitle(first))
        let endedSlot = try #require(slots.first { $0.gameID == "g2" })
        let suffixed = SlotText.recentTitle(endedSlot)
        #expect(suffixed.hasSuffix(" · Ironman · Ended") && suffixed.contains("— Day 0, "))
        #expect(MenuContext.make(session: try TestSessions.make()).recentSlots.isEmpty)
    }

    @Test("MENU-017 Ironman: Save As and Revert disabled, Save rewrites the slot, its Open Recent row is disabled")
    func ironmanFile() throws {
        let s = try TestSessions.make()
        var config = s.quickStartConfig()
        config.ironman = true
        s.startNewGame(config)
        let c = MenuContext.make(session: s)
        #expect(c.isIronman && on(.save, c) && !on(.saveAs, c) && !on(.revert, c))
        let row = try #require(c.recentSlots.firstIndex { $0.id == s.gameID })
        #expect(c.recentSlots[row].isCurrentIronmanSlot)
        #expect(MenuRules.recentRowAvailability(row, in: c).reason == .currentIronmanSlot)
        let before = s.listSlots().count
        s.save()
        #expect(s.listSlots().count == before && s.presentation == nil)
    }

    // MARK: Edit and View

    @Test("MENU-018 Find… ⌘F is the context search: Market focuses its filter, other sections open Find System")
    func contextFind() throws {
        let s = try TestSessions.playing()
        #expect(MenuCatalog.entry(for: .find).shortcut == MenuShortcut("f") && MenuCatalog.entry(for: .find).identifier == "menu.edit.find")
        ContextSearch.perform(.other, focused: nil, session: s)
        #expect(s.presentation == .sheet(.findSystem))
        s.dismissPresentation()
        var focused = false
        ContextSearch.perform(.market, focused: ContextSearchAction { focused = true }, session: s)
        #expect(focused && s.presentation == nil)
        #expect(!on(.find, Fx.ctx(nil)) && on(.find, Fx.ctx(Fx.fresh())))
    }

    @Test("MENU-019 MENU-023 the View menu's section items in order with ⌘1–⌘9 (Galaxy ⌘7 from M8, Logbook ⌘9 from M10)")
    func viewOrder() {
        let sections = MenuCatalog.items(in: .view).filter { $0.section != nil }
        #expect(sections == [.bridge, .market, .shipyard, .outfitter, .crew, .bank, .galaxy, .quests, .logbook])
        #expect(sections.compactMap { MenuCatalog.entry(for: $0).shortcut?.key } == ["1", "2", "3", "4", "5", "6", "7", "8", "9"])
        #expect(MenuCatalog.entry(for: .logbook).identifier == "menu.view.logbook")
        #expect(sections.compactMap(\.section) == Section.allCases)
    }

    @Test("MENU-020 ⌘1…⌘6, ⌘8 select their sections; during an encounter they are disabled")
    func sectionShortcuts() throws {
        for s in Section.allCases {
            let id = MenuItemID.item(for: s)
            #expect(id.section == s && MenuCatalog.entry(for: id).shortcut?.key == String(s.shortcutDigit))
        }
        let enc = Fx.ctx(try encounter())
        #expect(Section.allCases.filter { $0 != .logbook }.allSatisfy { !on(MenuItemID.item(for: $0), enc) })
    }

    @Test("MENU-021 section items are enabled iff game command")
    func sectionEnablement() throws {
        let enc = Fx.ctx(try encounter())
        var transit = Fx.ctx(Fx.fresh())
        transit.phase = .inTransit
        for c in [Fx.ctx(nil), transit, enc, Fx.ctx(Fx.ended), Fx.ctx(Fx.fresh(), modal: true)] {
            #expect(Section.allCases.filter { $0 != .logbook }.allSatisfy { !on(MenuItemID.item(for: $0), c) })
        }
        #expect(Section.allCases.allSatisfy { on(MenuItemID.item(for: $0), Fx.ctx(Fx.fresh())) })
    }

    // MARK: Game

    @Test("MENU-024 the Game menu's rows in order (Plot Route… after Find System from M8) with separators")
    func gameOrder() {
        #expect(MenuCatalog.items(in: .game) == [.warp, .jump, .previousTarget, .nextTarget, .track, .findSystem, .plotRoute, .fillFuel,
                                                 .repair, .newspaper, .options, .retire])
        #expect(MenuCatalog.items(in: .game, milestone: 7).contains(.plotRoute) == false)
        #expect(MenuCatalog.separatorAfter.isSuperset(of: [.findSystem, .repair, .options]))
        #expect(MenuCatalog.items(in: .game, milestone: 9).contains(.newspaper) && MenuCatalog.items(in: .game, milestone: 8).contains(.plotRoute))
    }

    @Test("MENU-025 Retire… has no shortcut and goes through the retire sheet (Cancel default)")
    func retire() throws {
        #expect(MenuCatalog.entry(for: .retire).shortcut == nil)
        let s = try TestSessions.playing()
        s.send(.retire)
        guard case .sheet(.retire) = s.presentation else {
            Issue.record("retire must present the retire sheet")
            return
        }
        s.cancel()
        #expect(s.mode == .playing)
    }

    @Test("MENU-026 Options… ⌥⌘O is disabled with no game, after the end and outside docked")
    func optionsItem() throws {
        #expect(MenuCatalog.entry(for: .options).shortcut == MenuShortcut("o", [.option, .command]))
        #expect(!on(.options, Fx.ctx(nil)) && !on(.options, Fx.ctx(Fx.ended)) && on(.options, Fx.ctx(Fx.fresh())))
        #expect(!on(.options, Fx.ctx(try encounter())))
    }

    @Test("MENU-027 ⇧⌘F / ⇧⌘R buy the full tank and repair; Fill Fuel is disabled at full tank and enabled after a warp")
    func fillFuel() throws {
        let s = try TestSessions.make(seed: FlowFixtures.flowSeed)
        s.requestQuickStart()
        #expect(!on(.fillFuel, .make(session: s)))
        s.send(.selectNextTarget(forward: true))
        s.send(.warp)
        let c = MenuContext.make(session: s)
        #expect(c.phase == .docked && on(.fillFuel, c))
        let cost = try #require(s.state).fullTankCost
        let cash = try #require(s.state).commander.cash
        s.send(.buyFuel(credits: cost))
        #expect(try #require(s.state).commander.cash == cash - cost)
        #expect(!on(.fillFuel, .make(session: s)))
        #expect(MenuCatalog.entry(for: .repair).shortcut == MenuShortcut("r", [.shift, .command]))
    }

    @Test("MENU-028 canBuyFuel / canRepair agree with the engine on full, partly empty and broke states per ruleset")
    func fuelRepairAgreeWithEngine() {
        for r in RulesetID.allCases {
            var partly = Fx.fresh(r)
            partly.commander.ship.fuel = max(0, partly.commander.ship.fuel - 3)
            partly.commander.ship.hull = max(1, partly.commander.ship.hull - 5)
            var broke = partly
            broke.commander.cash = 0
            var poor = partly
            poor.commander.cash = 1
            for st in [Fx.fresh(r), partly, broke, poor] {
                let c = Fx.ctx(st)
                var e = GameEngine(state: st)
                let fuel = e.perform(.buyFuel(credits: st.fullTankCost))
                #expect(c.canBuyFuel == (fuel.rejection == nil), "fuel \(r) cash \(st.commander.cash) fuel \(st.commander.ship.fuel)")
                e = GameEngine(state: st)
                let repair = e.perform(.repairHull(credits: st.fullRepairCost))
                #expect(c.canRepair == (repair.rejection == nil), "repair \(r) cash \(st.commander.cash)")
            }
        }
    }

    @Test("MENU-029 ⌘[ and ⌘] cycle the target through the systems in range")
    func cycleTargets() throws {
        let s = try TestSessions.playing()
        let st = try #require(s.state)
        #expect(MenuCatalog.entry(for: .nextTarget).shortcut == MenuShortcut("]") && MenuCatalog.entry(for: .previousTarget).shortcut == MenuShortcut("["))
        s.send(.selectNextTarget(forward: true))
        let first = try #require(s.state).warpSystem
        #expect(st.destinations.contains(first))
        s.send(.selectNextTarget(forward: true))
        s.send(.selectNextTarget(forward: false))
        #expect(try #require(s.state).warpSystem == first)
    }

    @Test("MENU-030 Warp: each disabling reason, and enabled agrees with perform(.warp) per ruleset")
    func warpRule() {
        for r in RulesetID.allCases {
            let current = Fx.fresh(r)
            #expect(MenuRules.warp(Fx.ctx(current)).reason == .targetIsCurrentSystem)
            var far = current
            if let out = far.galaxy.systems.indices.first(where: { !far.destinationOK($0) && $0 != far.commander.currentSystem }) {
                far.warpSystem = out
                #expect(MenuRules.warp(Fx.ctx(far)).reason == .engine(.destinationOutOfRange))
            }
            var debt = Fx.targeted(r)
            debt.commander.debt = 200_000
            #expect(MenuRules.warp(Fx.ctx(debt)).reason == .engine(.debtTooLargeToTravel))
            #expect(MenuRules.warp(Fx.ctx(Fx.targeted(r), modal: true)).reason == .modal)
            for st in [current, far, debt, Fx.targeted(r)] {
                var e = GameEngine(state: st)
                let result = e.perform(.warp)
                #expect(MenuRules.warp(Fx.ctx(st)).isEnabled == (result.rejection == nil), "\(r)")
            }
        }
    }

    @Test("MENU-031 ⌘J performs the same warp as the toolbar button")
    func commandJ() throws {
        #expect(MenuCatalog.entry(for: .warp).shortcut == MenuShortcut("j"))
        let a = try TestSessions.playing(seed: FlowFixtures.flowSeed)
        let b = try TestSessions.playing(seed: FlowFixtures.flowSeed)
        for s in [a, b] { s.send(.selectNextTarget(forward: true)) }
        #expect(on(.warp, .make(session: a)) && WarpButtonModel.make(state: b.state, isModal: b.isModal).isEnabled)
        a.send(.warp)
        b.send(.warp)
        #expect(a.state?.commander.currentSystem == b.state?.commander.currentSystem && a.state?.commander.days == 1)
    }

    @Test("MENU-032 Use Singularity… is shown only with canSuperWarp and enabled iff the jump preview is available")
    func singularity() {
        var st = Fx.targeted()
        #expect(!MenuRules.isShown(.jump, in: Fx.ctx(st)))
        st.quests.canSuperWarp = true
        let c = Fx.ctx(st)
        #expect(MenuRules.isShown(.jump, in: c) && on(.jump, c) == st.jumpPreview.available)
        st.warpSystem = st.commander.currentSystem
        #expect(MenuRules.availability(of: .jump, in: Fx.ctx(st)).reason == .engine(.singularityTargetIsCurrentSystem))
    }

    @Test("MENU-033 Previous/Next Target need destinations")
    func targetsNeedDestinations() {
        var st = Fx.fresh()
        #expect(on(.nextTarget, Fx.ctx(st)) && on(.previousTarget, Fx.ctx(st)))
        st.commander.ship.fuel = 0
        if st.destinations.isEmpty {
            #expect(MenuRules.availability(of: .nextTarget, in: Fx.ctx(st)).reason == .noDestinations)
        }
    }

    @Test("MENU-034 Track/Stop Tracking title and command; disabled for the current system")
    func track() {
        var st = Fx.targeted()
        let name = st.systemName(st.warpSystem)
        var c = Fx.ctx(st)
        #expect(MenuRules.trackTitle(c) == "Track “\(name)”" && MenuRules.trackCommand(c, warpSystem: st.warpSystem) == .track(st.warpSystem))
        st.trackedSystem = st.warpSystem
        c = Fx.ctx(st)
        #expect(MenuRules.trackTitle(c) == "Stop Tracking “\(name)”" && MenuRules.trackCommand(c, warpSystem: st.warpSystem) == .track(nil))
        #expect(on(.track, c))
        #expect(MenuRules.availability(of: .track, in: Fx.ctx(Fx.fresh())).reason == .targetIsCurrentSystem)
    }

    @Test("MENU-035 Find System… ⌥⌘F is always the system search; both finds are game commands")
    func findSystem() {
        #expect(MenuCatalog.entry(for: .findSystem).shortcut == MenuShortcut("f", [.option, .command]))
        #expect(on(.findSystem, Fx.ctx(Fx.fresh())) && !on(.findSystem, Fx.ctx(nil)) && !on(.find, Fx.ctx(Fx.ended)))
    }

    // MARK: Window and Help

    @Test("MENU-038 Window › Parsec Merchant reopens the main window; Galaxy Chart from M8; High Scores is M9")
    func windowMenu() {
        #expect(MenuCatalog.items(in: .window) == [.mainWindow, .galaxyChartWindow, .highScores])
        #expect(MenuCatalog.items(in: .window, milestone: 8) == [.mainWindow, .galaxyChartWindow])
        #expect(MenuCatalog.entry(for: .galaxyChartWindow).identifier == "menu.window.galaxyChart")
        for (_, c) in Fx.named { #expect(on(.galaxyChartWindow, c)) }
        #expect(MenuCatalog.entry(for: .mainWindow).identifier == "menu.window.main" && SceneMetrics.mainWindowID == "main")
        #expect(MenuCatalog.entry(for: .highScores).milestone == 9)
        for (_, c) in Fx.named { #expect(on(.mainWindow, c)) }
    }

    @Test("MENU-039 the Help menu rows, all always enabled")
    func helpMenu() {
        #expect(MenuCatalog.items(in: .help) == [.help, .prices, .shortcuts, .credits, .github])
        #expect(MenuCatalog.entry(for: .help).shortcut == MenuShortcut("?"))
        #expect(MenuCatalog.githubURL.absoluteString == "https://github.com/megatih/parsec-merchant")
        for (_, c) in Fx.named { #expect(MenuCatalog.items(in: .help).allSatisfy { on($0, c) }) }
    }

    // MARK: Cross-checks

    @Test("MENU-040 later-milestone entries are absent at M10")
    func milestoneFilter() {
        #expect(MenuCatalog.currentMilestone == 10)
        let present = MenuName.allCases.flatMap { MenuCatalog.items(in: $0) }
        #expect(!present.contains { MenuCatalog.entry(for: $0).milestone > 10 })
        #expect(MenuItemID.encounterItems.allSatisfy { present.contains($0) && MenuCatalog.entry(for: $0).milestone == 9 })
        for id: MenuItemID in [.galaxy, .galaxyChart, .zoomIn, .zoomOut, .zoomFit, .plotRoute, .galaxyChartWindow, .logbook] {
            #expect(present.contains(id))
        }
    }

    @Test("MENU-022 Galaxy ⌘7, Galaxy Chart ⇧⌘M and the zoom items; zoom is enabled only while a map has focus")
    func galaxyViewItems() {
        #expect(MenuCatalog.entry(for: .galaxy).shortcut == MenuShortcut("7"))
        #expect(MenuCatalog.entry(for: .galaxyChart).shortcut == MenuShortcut("m", [.shift, .command]))
        #expect(MenuCatalog.items(in: .view).suffix(4) == [.galaxyChart, .zoomIn, .zoomOut, .zoomFit])
        let unfocused = Fx.ctx(Fx.fresh())
        #expect([MenuItemID.zoomIn, .zoomOut, .zoomFit].allSatisfy { !on($0, unfocused) })
        #expect(MenuRules.availability(of: .zoomIn, in: unfocused).reason == .noMapFocus)
        let focused = MenuContext.make(state: Fx.fresh(), isModal: false, focusedMap: .galaxy)
        #expect([MenuItemID.zoomIn, .zoomOut, .zoomFit].allSatisfy { on($0, focused) })
        #expect(on(.galaxyChart, unfocused) && !on(.galaxyChart, Fx.ctx(nil)))
    }

    @Test("MENU-041 enabled game items map to commands the engine accepts; engine reasons match its rejections")
    func agreesWithEngine() throws {
        var mid = try TestSessions.playing(seed: FlowFixtures.flowSeed)
        mid.send(.selectNextTarget(forward: true))
        mid.send(.warp)
        var states = RulesetID.allCases.map { Fx.targeted($0) } + [Fx.ended]
        states.append(try #require(mid.state))
        states.append(try encounter())
        var singular = Fx.targeted()
        singular.quests.canSuperWarp = true
        states.append(singular)
        for st in states {
            let c = Fx.ctx(st)
            let mapped: [(MenuItemID, Command)] = [
                (.warp, .warp), (.jump, .jump), (.previousTarget, .selectNextTarget(forward: false)),
                (.nextTarget, .selectNextTarget(forward: true)), (.track, MenuRules.trackCommand(c, warpSystem: st.warpSystem)),
                (.fillFuel, .buyFuel(credits: st.fullTankCost)), (.repair, .repairHull(credits: st.fullRepairCost)),
                (.options, .setOptions(st.options)), (.retire, .retire),
            ]
            for (id, command) in mapped {
                var e = GameEngine(state: st)
                let result = e.perform(command)
                let a = MenuRules.availability(of: id, in: c)
                if a.isEnabled {
                    #expect(result.rejection == nil, "\(id) enabled but rejected \(String(describing: result.rejection))")
                } else if case let .engine(reason) = a.reason {
                    #expect(result.rejection == reason, "\(id)")
                }
            }
        }
        mid = try TestSessions.make()
        #expect(mid.engine == nil)
    }

    @Test("MENU-042 no game: only session and app items; after Quick Start, Warp waits for Next Target")
    func scenarioNoGame() throws {
        let s = try TestSessions.make()
        var c = MenuContext.make(session: s)
        for id: MenuItemID in [.save, .saveAs, .revert, .export, .closeGame] { #expect(!on(id, c)) }
        #expect(MenuCatalog.items(in: .view).allSatisfy { !on($0, c) } && MenuCatalog.items(in: .game).allSatisfy { !on($0, c) })
        for id: MenuItemID in [.newGame, .quickStart, .open, .importSave, .about] { #expect(on(id, c)) }
        #expect(MenuCatalog.items(in: .help).allSatisfy { on($0, c) })
        s.requestQuickStart()
        c = MenuContext.make(session: s)
        #expect(s.selectedSection == .bridge)
        for id: MenuItemID in [.save, .export, .options, .retire] { #expect(on(id, c)) }
        #expect(MenuCatalog.items(in: .view).filter { $0.section != nil || $0 == .galaxyChart }.allSatisfy { on($0, c) })
        #expect(!on(.warp, c))
        s.send(.selectNextTarget(forward: true))
        #expect(on(.warp, .make(session: s)))
    }

    @Test("MENU-043 Retire: Cancel keeps the game; confirming ends it and leaves only Export and Close Game")
    func scenarioRetire() throws {
        let s = try TestSessions.playing()
        s.send(.retire)
        s.cancel()
        #expect(s.mode == .playing)
        s.send(.retire)
        guard case let .sheet(.retire(pending)) = s.presentation else {
            Issue.record("expected the retire sheet")
            return
        }
        s.confirm(pending)
        #expect(s.mode == .gameOver(.retired))
        let c = MenuContext.make(session: s)
        for id: MenuItemID in [.save, .options, .retire, .warp] { #expect(!on(id, c)) }
        #expect(MenuCatalog.items(in: .view).filter { $0.section != nil && $0 != .logbook }.allSatisfy { !on($0, c) })
        #expect(on(.export, c) && on(.closeGame, c) && on(.logbook, c))
    }

    @Test("MENU-044 Help › Keyboard Shortcuts lists ⌘J Warp and ⌥⌘O Options… from the catalog; Credits opens About")
    func scenarioHelpAbout() {
        let rows = HelpContent.shortcutRows()
        #expect(rows.contains { $0.shortcut == "⌘J" && $0.title == "Warp" })
        #expect(rows.contains { $0.shortcut == "⌥⌘O" && $0.title == "Options…" })
        #expect(HelpContent.text(.keyboardShortcuts).contains("⌘J"))
        #expect(AboutContent.credits.contains { $0.names == "Pieter Spronck" })
        #expect(String(localized: AboutContent.gplNotice).contains("GNU General Public License"))
    }
}
