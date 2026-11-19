// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import Foundation
import ParsecEngine
import ParsecPersistence
import Testing
@testable import ParsecMerchant

@MainActor
@Suite("Shell")
struct ShellTests {
    private func fresh(_ ruleset: RulesetID = .modern, seed: UInt64 = 1) -> GameState {
        GameState(config: NewGameConfig(commanderName: "Shell", ruleset: ruleset, seed: seed))
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: Launch and scenes

    @Test("UI-SHELL-013 launch arguments parse purely; Release honours only -PMScenario smoke")
    func launchOptions() {
        let args = ["app", "-PMSeed", "42", "-PMScenario", "smoke", "-PMFlavor", "template", "-PMFastTravel", "-PMAudio", "off",
                    "-PMResetState"]
        let o = LaunchOptions.parse(args, isDebug: true)
        #expect(o.seed == 42 && o.scenario == "smoke" && o.flavorTemplate && o.fastTravel && o.audioOff && o.resetState)
        let r = LaunchOptions.parse(args, isDebug: false)
        #expect(r == LaunchOptions(seed: nil, scenario: "smoke"))
        #expect(LaunchOptions.parse(["app", "-PMSeed", "x"], isDebug: true).seed == nil)
        #expect(LaunchOptions.parse(["app", "-PMFastTravel", "NO"], isDebug: true).fastTravel == false)
        #expect(LaunchOptions.parse(["app"], isDebug: true) == .none)
    }

    @Test("CHEAT-047 launch arguments are read by the app only and ignored in Release except the smoke scenario")
    func releaseIgnoresArguments() {
        #expect(LaunchOptions.parse(["app", "-PMSeed", "5", "-PMResetState"], isDebug: false) == .none)
        #expect(LaunchOptions.parse(["app", "-PMScenario", "other"], isDebug: false) == .none)
    }

    @Test("CHEAT-048 -PMSeed makes New Game and Quick Start use that seed without flagging cheats")
    func pmSeedQuickStart() throws {
        let s = try TestSessions.make(seed: 31_337)
        s.requestQuickStart()
        #expect(s.state?.seed == 31_337 && s.state?.cheatsUsed == false)
    }

    @Test("CHEAT-049 the smoke scenario round-trips a flagged game through a slot; unknown names fail")
    func smokeScenario() throws {
        let s = try TestSessions.make()
        #expect(ScenarioRunner.smoke(session: s))
        #expect(ScenarioRunner.run("nope", session: s) != 0)
        #expect(s.listSlots().isEmpty)
    }

    @Test("CHEAT-051 -PMResetState wipes the support folder and defaults domain before the stores are created")
    func resetState() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pm-reset-\(UUID().uuidString)")
        let domain = "pm-reset-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Corrupt"), withIntermediateDirectories: true)
        defaults.set("x", forKey: "k")
        AppPaths.resetState(root: root, defaults: defaults, domain: domain)
        #expect(!FileManager.default.fileExists(atPath: root.path))
        #expect((defaults.persistentDomain(forName: domain) ?? [:]).isEmpty)
        var options = LaunchOptions()
        options.resetState = true
        options.audioOff = true
        let s = AppBootstrap.makeSession(options: options, defaults: defaults, root: root)
        #expect(s.mode == .welcome && s.slotStore.root == root)
    }

    @Test("UI-SHELL-014 UI-DS-001 the main window: 1440×860 default, 1200×680 minimum, id main")
    func sceneMetrics() {
        #expect(SceneMetrics.mainDefaultSize == CGSize(width: 1440, height: 860))
        #expect(SceneMetrics.mainMinimumSize == CGSize(width: 1200, height: 680))
        #expect(SceneMetrics.mainWindowID == "main")
    }

    @Test("UI-SHELL-015 closing the last window keeps the app running; reopen and quit keep the session")
    func appDelegate() throws {
        let d = AppDelegate()
        #expect(!d.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
        #expect(d.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false))
    }

    @Test("UI-SHELL-016 a restored section falls back to Bridge when unknown or unavailable")
    func restoredSection() {
        let playing = SectionContext(hasGame: true, ended: false, hasShipyards: true, currentSystemHasShipyard: false)
        #expect(Section.restored(rawValue: "bank", context: playing) == .bank)
        #expect(Section.restored(rawValue: "logbook", context: playing) == .logbook)
        #expect(Section.restored(rawValue: "nonsense", context: playing) == .bridge)
        #expect(Section.restored(rawValue: nil, context: playing) == .bridge)
        #expect(Section.restored(rawValue: "bank", context: .noGame) == .bridge)
    }

    // MARK: Welcome

    @Test("UI-SHELL-017 Welcome identifiers and the credit line")
    func welcome() throws {
        #expect(AXID.Welcome.all.contains("welcome.quickStart") && AXID.Welcome.all.contains("welcome.import"))
        #expect(AXID.Welcome.recent("ab-12") == "welcome.recent.ab12")
        let s = try TestSessions.make()
        #expect(s.mode == .welcome && s.continueCandidate == nil)
    }

    @Test("UI-SHELL-018 recent saves: the 10 newest, newest first")
    func recentSlots() throws {
        let s = try TestSessions.playing()
        for _ in 0..<12 { s.saveAs() }
        let recent = s.recentSlots()
        #expect(recent.count == 10)
        #expect(zip(recent, recent.dropFirst()).allSatisfy { $0.modified >= $1.modified })
    }

    @Test("UI-SHELL-021 Continue makes the loaded save current with its manual-save day")
    func continueSetsDays() throws {
        let s = try TestSessions.playing(seed: 2)
        try TestSessions.edit(s) { $0.commander.days = 4 }
        s.writeAutosave()
        s.closeGame()
        #expect(s.continueGame())
        #expect(s.lastManualSaveDays == 4 && s.currentSlotID == nil && s.mode == .playing)
    }

    // MARK: Shell anatomy

    @Test("UI-SHELL-034 the playing window is shown for a loaded game; Welcome otherwise")
    func anatomy() throws {
        let s = try TestSessions.playing()
        #expect(s.mode == .playing && s.isDocked)
    }

    @Test("UI-SHELL-035 UI-NAV-002 LOG-029 dock buttons in order with ⌘1…⌘9 and identifiers")
    func sidebarRows() {
        #expect(Section.allCases == [.bridge, .shipyard, .outfitter, .crew, .bank, .status, .quests, .galaxy, .logbook, .options])
        #expect(Section.allCases.map(\.shortcutDigit) == ["1", "2", "3", "4", "5", "6", "7", "8", "9", nil])
        #expect(Section.allCases.map(\.axID) == ["dock.bridge", "dock.shipyard", "dock.outfitter", "dock.crew", "dock.bank", "dock.status",
                                                  "dock.quests", "dock.galaxy", "dock.logbook", "dock.options"])
        #expect(Section.bridge.keyCap == "⌘1" && Section.logbook.keyCap == "⌘9" && Section.options.keyCap == "⌥⌘O")
        #expect(AXID.SectionRoot.root(.logbook) == "logbook.root")
    }

    @Test("UI-SHELL-036 badges: special event, mercenaries for hire, debt warning at 75,000")
    func badges() {
        var st = fresh()
        st.galaxy.systems[st.commander.currentSystem].specialEvent = .lottery
        st.commander.debt = 75_000
        let b = SidebarBadges.make(state: st)
        #expect(b.bridgeSpecial == (st.specialEventAvailable != nil))
        #expect(b.badge(for: .bank) == .debtWarning)
        #expect(b.crewForHire == st.mercenariesForHire.count)
        st.commander.debt = 74_999
        #expect(SidebarBadges.make(state: st).badge(for: .bank) == nil)
        #expect(SidebarBadges.make(state: nil) == SidebarBadges(bridgeSpecial: false, crewForHire: 0, bankDebtWarning: false))
        #expect(String(localized: SidebarBadges.Badge.count(2).accessibilityLabel) == "2 mercenaries for hire")
    }

    @Test("UI-SHELL-037 not docked: rows locked with In transit / In encounter")
    func lock() throws {
        #expect(SidebarLock.make(phase: .docked) == .none)
        let enc = EncounterState(type: .pirateAttack, opponent: fresh().commander.ship)
        #expect(SidebarLock.make(phase: .encounter(enc)) == .inEncounter)
        #expect(String(localized: try #require(SidebarLock.inEncounter.label)) == "In encounter")
        #expect(String(localized: try #require(SidebarLock.inTransit.label)) == "In transit")
    }

    @Test("UI-SHELL-038 sections need a loaded, unended game; the Designer needs shipyards here")
    func sectionAvailability() {
        for r in RulesetID.allCases {
            var st = fresh(r)
            let ctx = SectionContext.make(state: st)
            #expect(Section.allCases.allSatisfy { $0.isAvailable(in: ctx) })
            #expect(!ctx.designerAvailable || r != .palm122)
            st.phase = .gameOver(.killed)
            // LOG-029: the Logbook is the only section of an ended game.
            #expect(Section.allCases.filter { $0.isAvailable(in: .make(state: st)) } == [.logbook])
        }
        #expect(Section.allCases.allSatisfy { !$0.isAvailable(in: .noGame) })
        let yard = SectionContext(hasGame: true, ended: false, hasShipyards: true, currentSystemHasShipyard: true)
        #expect(yard.designerAvailable)
        #expect(!SectionContext(hasGame: true, ended: false, hasShipyards: false, currentSystemHasShipyard: true).designerAvailable)
    }

    @Test("UI-SHELL-040 Warp is disabled without a target and shows costs or the reason")
    func toolbar() throws {
        var st = fresh()
        #expect(!WarpButtonModel.make(state: st, isModal: false).isEnabled)
        st.warpSystem = try #require(st.destinations.first)
        let m = WarpButtonModel.make(state: st, isModal: false)
        #expect(m.isEnabled && m.help.contains("Total"))
        #expect(!WarpButtonModel.make(state: st, isModal: true).isEnabled)
        st.commander.debt = 200_000
        #expect(WarpButtonModel.make(state: st, isModal: false).help == ReasonText.string(for: .debtTooLargeToTravel))
    }

    @Test("UI-SHELL-042 window title and subtitle per phase")
    func titles() throws {
        #expect(WindowTitles.make(state: nil).title == "Parsec Merchant" && WindowTitles.make(state: nil).subtitle == nil)
        var st = fresh()
        let docked = WindowTitles.make(state: st)
        #expect(docked.title == "Parsec Merchant — Cmdr. Shell")
        #expect(docked.subtitle == "Day 0 · \(Names.system(st.commander.currentSystem, in: st)) · Credits 1,000 · Debt 0")
        st.commander.shipName = "Rocinante"
        #expect(WindowTitles.make(state: st).title == "Parsec Merchant — Cmdr. Shell · “Rocinante”")
        let enc = EncounterState(type: .pirateAttack, opponent: st.commander.ship)
        let transitJSON = #"{"destination":5,"clicksRemaining":3,"viaWormhole":false,"raided":false,"inspected":false,"#
            + #""litterWarning":false,"hadEncounter":false}"#
        st.encounterTransit = try decode(transitJSON)
        st.phase = .encounter(enc)
        #expect(WindowTitles.make(state: st).subtitle == "Day 0 · In transit to \(Names.system(5, in: st))")
        st.phase = .gameOver(.killed)
        #expect(WindowTitles.make(state: st).subtitle == "Day 0 · Game over")
    }

    @Test("UI-SHELL-043 the titles update after every accepted command")
    func titlesUpdate() throws {
        let s = try TestSessions.playing()
        let before = WindowTitles.make(state: s.state).subtitle
        s.send(.borrow(500))
        #expect(WindowTitles.make(state: s.state).subtitle != before)
        #expect(WindowTitles.make(state: s.state).subtitle?.contains("Debt 500") == true)
    }

    @Test("UI-SHELL-044 status bar: bays, fuel, hull and the latest feed item; overlay lists the newest 50")
    func statusBar() throws {
        let s = try TestSessions.playing()
        let st = try #require(s.state)
        let m = StatusBarModel.make(state: st, feed: s.feed)
        #expect(m.filledBays == 0 && m.totalBays == st.commander.ship.cargoBays(st.ruleset))
        #expect(m.fuel == st.commander.ship.fuel && m.fuelCapacity == st.fuelCapacity && m.hullPercent == 100)
        #expect(m.latestFeed == s.feed.last)
        let many = (0..<80).map { FeedItem(id: $0, day: 0, systemIndex: 0, entry: .note(.gameSaved)) }
        let overlay = StatusBarModel.overlayItems(many)
        #expect(overlay.count == 50 && overlay.first?.id == 79)
    }

    @Test("UI-SHELL-045 a rejection is kept for the status bar and cleared by the next accepted command")
    func rejectionStatus() throws {
        let s = try TestSessions.playing()
        s.send(.repay(10))
        #expect(s.lastRejection != nil)
        s.send(.borrow(10))
        #expect(s.lastRejection == nil)
    }

    // MARK: Inspector

    @Test("UI-SHELL-046 the inspector model updates after every step")
    func inspectorLive() throws {
        let s = try TestSessions.playing()
        let before = InspectorModel.make(state: try #require(s.state))
        s.send(.borrow(1_000))
        let after = InspectorModel.make(state: try #require(s.state))
        #expect(after.cash == before.cash + 1_000 && after.debt == 1_000)
        #expect(AXID.Inspector.all.contains("inspector.hull"))
    }

    @Test("UI-SHELL-047 header: name, difficulty, day, ship, hull percent, shields or none")
    func inspectorHeader() throws {
        var st = fresh()
        st.commander.ship.hull = st.commander.ship.hullStrength(st.ruleset) / 2
        let m = InspectorModel.make(state: st)
        #expect(m.commanderName == "Shell" && m.difficulty == .normal && m.days == 0 && m.shipType == st.commander.ship.type)
        #expect(m.hullPercent == 50)
        #expect(m.shields == nil)
        st.commander.ship.shields = [try decode(#"{"type":0,"charge":50}"#)]
        let s2 = InspectorModel.make(state: st).shields
        #expect(s2?.charge == 50 && s2?.power == st.ruleset.tables.shield(.energy).power)
    }

    @Test("UI-SHELL-048 finances: cash, debt and the ruleset's worth")
    func inspectorFinances() {
        for r in RulesetID.allCases {
            let st = fresh(r)
            let m = InspectorModel.make(state: st)
            #expect(m.cash == st.commander.cash && m.debt == st.commander.debt && m.worth == st.worth)
        }
    }

    @Test("UI-SHELL-049 skills: base and effective values")
    func inspectorSkills() {
        let st = fresh()
        let m = InspectorModel.make(state: st)
        #expect(m.skills.map(\.base) == st.mercenaries[CrewID.commander].skills)
        #expect(m.skills.map(\.effective) == st.shipSkills)
    }

    @Test("UI-SHELL-050 notoriety: record, reputation, kills, bounty at Crook or worse, kingpins at Trusted or better")
    func inspectorNotoriety() {
        var st = fresh()
        st.commander.kills.pirates = 2
        st.commander.kills.police = 1
        st.commander.kills.traders = 3
        #expect(InspectorModel.make(state: st).kills == 6)
        #expect(InspectorModel.make(state: st).notoriety == .none)
        st.commander.policeRecordScore = -10
        #expect(InspectorModel.make(state: st).notoriety == .bounty(10_000))
        st.commander.policeRecordScore = 12
        #expect(InspectorModel.make(state: st).notoriety == .angryKingpins(2))
        #expect(InspectorModel.make(state: st).policeRecord == .trusted)
    }

    @Test("UI-SHELL-051 cargo with average cost, then special cargo in C# order")
    func inspectorCargo() {
        var st = fresh()
        st.commander.ship.cargo[TradeItemType.food.rawValue] = 4
        st.commander.priceCargo[TradeItemType.food.rawValue] = 100
        st.commander.ship.tribbles = 100_000
        st.quests.japori = QuestStatus.Japori.inTransit
        st.quests.reactor = 5
        st.quests.canSuperWarp = true
        let m = InspectorModel.make(state: st)
        #expect(m.cargo.count == 1 && m.cargo[0].units == 4 && m.cargo[0].averageCost == 25)
        #expect(m.specialCargo == [.tribblesInfestation, .antidote, .reactor(enrichedFuelBays: 8), .singularity])
        #expect(InspectorModel.make(state: fresh()).specialCargo.isEmpty)
        #expect(String(localized: InspectorText.specialCargo(.tribbles(3))) == "3 cute, furry tribbles.")
    }

    @Test("UI-SHELL-052 equipment counted by type, escape pod, hardened hull and free slots")
    func inspectorEquipment() {
        var st = fresh()
        st.commander.ship.weapons = [.pulseLaser]
        st.commander.ship.escapePod = true
        st.commander.ship.hullUpgraded = true
        let m = InspectorModel.make(state: st)
        #expect(m.weapons.count == 1 && m.weapons[0].count == 1)
        #expect(m.escapePod && m.hardenedHull)
        #expect(m.freeWeaponSlots == st.commander.ship.freeWeaponSlots(st.ruleset))
    }

    @Test("UI-SHELL-053 crew with wages, passengers marked, free quarters and daily costs")
    func inspectorCrew() {
        var st = fresh()
        st.commander.ship.crew.append(CrewID.wild)
        st.commander.debt = 1_000
        let m = InspectorModel.make(state: st)
        #expect(m.crew.contains { $0.crewID == CrewID.wild && $0.isPassenger })
        #expect(m.dailyCosts == st.dailyCosts(to: st.warpSystem))
        #expect(m.dailyCosts.interest == 100)
    }

    // MARK: Game over and identifiers

    @Test("UI-SHELL-097 the game-over card: ending, score X.Y% and the high-score outcome")
    func gameOverCard() {
        var st = fresh()
        st.phase = .gameOver(.retired)
        let m = GameOverCardModel.make(state: st, recorded: .outcome(.entered(rank: 3)), lastStep: nil, table: nil)
        #expect(m?.end == .retired && m?.career.scoreTenths == st.scoreTenths(for: .retired))
        #expect(m?.highScoreText == "You entered the high-score table at rank 3.")
        #expect(m?.scoreText == ScoreText.tenths(st.scoreTenths(for: .retired), ruleset: st.ruleset))
        #expect(GameOverCardModel.make(state: fresh(), recorded: nil, lastStep: nil, table: nil) == nil)
        #expect(AXID.GameOver.card == "gameOver.card" && AXID.GameOver.newGame == "gameOver.newGame"
            && AXID.GameOver.mainMenu == "gameOver.mainMenu")
    }

    @Test("UI-SHELL-096 Retire… sends .retire; its confirmation is the retire sheet with the score and a destructive Retire")
    func retireSheet() throws {
        let s = try TestSessions.playing()
        s.send(.retire)
        guard case let .sheet(.retire(pending)) = s.presentation, let st = s.state else {
            Issue.record("retire should present the retire sheet")
            return
        }
        let content = ConfirmationText.content(for: pending.confirmation, state: st)
        #expect(content.isDestructive)
        #expect(content.message == "Retiring now scores \(ScoreText.score(st.score(for: .retired), ruleset: st.ruleset)).")
        #expect(AXID.Dialog.all.contains("retire.confirm") && AXID.Dialog.all.contains("retire.cancel"))
        s.cancel()
        #expect(s.mode == .playing)
    }

    @Test("ALR-094 the discard question is a destructive app confirmation (Discard / Cancel)")
    func discardDialog() throws {
        let s = try TestSessions.make()
        let c = AppConfirmationText.content(for: .discardUnsavedGame, session: s)
        #expect(c.isDestructive && c.confirmLabel == "Discard")
    }

    @Test("UI-SHELL-128 AXID values are unique and match the identifier scheme")
    func axids() throws {
        let all = AXID.all
        #expect(Set(all).count == all.count)
        let regex = try Regex(AXID.pattern)
        for id in all {
            #expect(id.wholeMatch(of: regex) != nil, "\(id)")
        }
    }
}
