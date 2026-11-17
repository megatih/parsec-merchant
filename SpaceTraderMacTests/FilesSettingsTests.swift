// SPDX-License-Identifier: GPL-2.0-or-later
import AppIntents
import AppKit
import Foundation
import ParsecEngine
import ParsecPersistence
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import ParsecMerchant

@MainActor
@Suite("Files, options, settings, About, Help, intents, cheats")
struct FilesSettingsTests {
    private func session(_ r: RulesetID = .modern, ironman: Bool = false, seed: UInt64 = 1) throws -> GameSession {
        let s = try TestSessions.make(seed: seed)
        var config = s.quickStartConfig()
        config.ruleset = r
        config.ironman = ironman
        #expect(s.startNewGame(config) == nil)
        return s
    }

    /// A save written by a "newer" app: a valid envelope with a future schema version.
    private func futureSave(_ s: GameSession) throws -> Data {
        let data = try #require(try s.exportCurrentGame())
        var raw = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        raw["schemaVersion"] = 99
        return try JSONSerialization.data(withJSONObject: raw)
    }

    // MARK: SAV

    @Test("SAV-030 import/export use the .parsecsave UTType; default export name; failures alert")
    func fileType() throws {
        #expect(SaveFileType.identifier == "io.github.megatih.parsecmerchant.save" && SaveFileType.fileExtension == "parsecsave")
        #expect(UTType.parsecSave.identifier == SaveFileType.identifier)
        let declared = Bundle.main.object(forInfoDictionaryKey: "UTExportedTypeDeclarations") as? [[String: Any]] ?? []
        #expect(declared.contains { $0["UTTypeIdentifier"] as? String == SaveFileType.identifier })
        #expect(SlotText.exportFileName(commander: "Jameson", day: 12) == "Jameson – Day 12.parsecsave")
        #expect(SlotText.exportBaseName(commander: "Jameson", day: 12) == "Jameson – Day 12")
        let s = try TestSessions.make()
        s.importSave(Data("nope".utf8))
        guard case .systemAlert(.openFailed) = s.presentation else {
            Issue.record("an unreadable import shows openFailed")
            return
        }
    }

    @Test("SAV-039 Revert needs a loaded non-Ironman game whose own autosave has not ended")
    func revertCondition() throws {
        let s = try session()
        #expect(s.canRevertToAutosave)
        #expect(!(try session(ironman: true)).canRevertToAutosave)
        let other = try session()
        // Another game's autosave in the same store is not this game's.
        _ = try s.slotStore.autosave(try #require(other.state), gameID: "someone-else")
        #expect(!s.canRevertToAutosave)
        s.writeAutosave()
        s.send(.retire)
        if case let .sheet(.retire(p)) = s.presentation { s.confirm(p) }
        #expect(!s.canRevertToAutosave, "the autosave now holds the ended state")
    }

    @Test("SAV-042 Open lists slots newest first; an ended save opens to its game-over card")
    func openListsAndEnded() throws {
        let s = try session()
        s.saveAs()
        var ended = try #require(s.state)
        ended.phase = .gameOver(.killed)
        let endedID = SlotStore.newSlotID()
        _ = try s.slotStore.save(ended, slot: endedID, gameID: "ended-game")
        let model = OpenSavedModel.make(slots: s.listSlots(), ironmanSlotID: nil)
        #expect(model.rows.first?.id == endedID && model.rows.count == 3)
        #expect(model.rows.allSatisfy { $0.canOpen })
        s.lastManualSaveDays = s.state?.commander.days ?? 0
        s.requestOpen(slotID: endedID)
        #expect(s.mode == .gameOver(.killed))
        #expect(MenuContext.make(session: s).phase == .gameOver)
    }

    @Test("SAV-047 Ironman: own slot not openable, Save As/Revert off, switching writes the slot without asking")
    func ironmanRules() throws {
        let s = try session(ironman: true)
        let id = try #require(s.gameID)
        let model = OpenSavedModel.make(slots: s.listSlots(), ironmanSlotID: id)
        #expect(model.row(id)?.canOpen == false && !model.canOpen(id))
        let c = MenuContext.make(session: s)
        #expect(!MenuRules.availability(of: .saveAs, in: c).isEnabled && !MenuRules.availability(of: .revert, in: c).isEnabled)
        let other = SlotStore.newSlotID()
        _ = try s.slotStore.save(MenuFixtures.fresh(), slot: other, gameID: "other")
        s.send(.selectNextTarget(forward: true))
        s.requestOpen(slotID: other)
        #expect(s.presentation == nil && s.gameID == "other")
        #expect(try s.slotStore.load(slot: id).state.ironman)
    }

    @Test("SAV-052 a save from a newer app reports 'made by a newer version' and stays where it was")
    func futureVersion() throws {
        let s = try session()
        let data = try futureSave(s)
        s.importSave(data)
        guard case let .systemAlert(.openFailed(reason, _)) = s.presentation else {
            Issue.record("expected openFailed")
            return
        }
        #expect(reason.contains("newer version"))
        s.dismissPresentation()
        let id = SlotStore.newSlotID()
        let url = s.slotStore.url(forSlot: id)
        try data.write(to: url)
        s.openSlot(id)
        guard case let .systemAlert(.openFailed(reason2, _)) = s.presentation else {
            Issue.record("expected openFailed on open")
            return
        }
        #expect(reason2.contains("newer version") && FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: UI-SHELL §14

    @Test("UI-SHELL-088 the Open sheet opens a slot with loadForPlay and makes it the current slot")
    func openSheet() throws {
        let s = try session()
        s.save()
        let saved = try #require(s.currentSlotID)
        s.send(.selectNextTarget(forward: true))
        s.send(.warp)
        s.present(.sheet(.openSavedGame))
        #expect(s.isModal)
        s.dismissPresentation()
        s.requestOpen(slotID: saved)
        if case .appConfirmation(.discardUnsavedGame) = s.presentation { s.confirm(.discardUnsavedGame) }
        #expect(s.currentSlotID == saved && s.state?.commander.days == 0)
        #expect(AXID.Files.all == ["openSaved.list", "openSaved.open", "openSaved.export", "openSaved.delete", "openSaved.cancel"])
    }

    @Test("UI-SHELL-089 Save writes the slot, records the day, sets the current slot and notes it; failures alert")
    func saveWrites() throws {
        let s = try session()
        s.send(.selectNextTarget(forward: true))
        s.send(.warp)
        s.save()
        #expect(s.currentSlotID != nil && s.lastManualSaveDays == s.state?.commander.days)
        #expect(s.feed.last?.entry == .note(.gameSaved))
        // A store whose root is a file can't be written.
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("pm-file-\(UUID().uuidString)")
        try Data().write(to: file)
        let broken = GameSession(stores: SessionStores(root: file, appVersion: "test"),
                                 defaults: try #require(UserDefaults(suiteName: "pm-\(UUID().uuidString)")))
        broken.install(GameEngine(state: MenuFixtures.fresh()), gameID: "g", slotID: nil)
        broken.save()
        guard case .systemAlert(.saveFailed) = broken.presentation else {
            Issue.record("expected saveFailed")
            return
        }
    }

    @Test("UI-SHELL-090 Revert asks first, then loads the autosave as a reload")
    func revert() throws {
        let s = try session()
        let reloadsBefore = try #require(s.state).reloadCount
        s.present(.appConfirmation(.revertToAutosave))
        #expect(AppConfirmationText.content(for: .revertToAutosave, session: s).isDestructive)
        s.confirm(.revertToAutosave)
        #expect(try #require(s.state).reloadCount == reloadsBefore + 1)
    }

    @Test("UI-SHELL-091 deleting the current slot keeps the game loaded with no current slot")
    func deleteCurrent() throws {
        let s = try session()
        s.save()
        let id = try #require(s.currentSlotID)
        s.confirm(.deleteSlot(id))
        #expect(s.currentSlotID == nil && s.engine != nil && !s.listSlots().contains { $0.id == id })
    }

    @Test("UI-SHELL-092 Export: the current game stamped with its game id, or a stored slot")
    func export() throws {
        let s = try session()
        let pending = try #require(s.makeCurrentExport())
        let envelope = try SaveCodec.decode(pending.document.data)
        #expect(envelope.gameID == s.gameID && envelope.state == s.state)
        #expect(pending.defaultName == "Jameson – Day 0")
        let slot = try #require(s.listSlots().first)
        let fromSlot = try #require(s.makeSlotExport(slot))
        #expect(try SaveCodec.decode(fromSlot.document.data).gameID == slot.gameID)
        s.requestExport()
        #expect(s.isExporterPresented)
    }

    @Test("UI-SHELL-093 Import (and Finder open, one file at a time) adds a slot and offers to load it")
    func importAndFinderOpen() throws {
        let s = try session()
        let data = try #require(try s.exportCurrentGame())
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pm-open-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let a = dir.appendingPathComponent("a.parsecsave"), b = dir.appendingPathComponent("b.parsecsave")
        try data.write(to: a)
        try data.write(to: b)
        let before = s.listSlots().count
        s.openFromFinder([a, b])
        #expect(s.listSlots().count == before + 2)
        guard case let .appConfirmation(.loadImportedSave(first)) = s.presentation else {
            Issue.record("expected the load offer")
            return
        }
        #expect(s.pendingPresentations.count == 1)
        s.lastManualSaveDays = s.state?.commander.days ?? 0
        s.confirm(.loadImportedSave(first))
        #expect(s.currentSlotID == first)
        s.requestImport()
        #expect(s.isImporterPresented)
    }

    @Test("UI-SHELL-094 a backup-recovered slot opens with a note; a quarantined one names the Corrupt folder")
    func recoveryAndQuarantine() throws {
        let s = try session()
        s.save()
        let id = try #require(s.currentSlotID)
        s.save()
        try Data("garbage".utf8).write(to: s.slotStore.url(forSlot: id))
        s.openSlot(id)
        #expect(s.feed.contains { $0.entry == .note(.recoveredFromBackup) })
        let lone = SlotStore.newSlotID()
        try Data("{\"format\":\"parsec-merchant-save\"}".utf8).write(to: s.slotStore.url(forSlot: lone))
        s.openSlot(lone)
        guard case let .systemAlert(.openFailed(_, suggestion)) = s.presentation else {
            Issue.record("expected openFailed")
            return
        }
        #expect(suggestion?.contains("Corrupt") == true)
    }

    @Test("UI-SHELL-095 Close Game from the menu returns to Welcome")
    func closeGameFromMenu() throws {
        let s = try session()
        #expect(MenuRules.availability(of: .closeGame, in: .make(session: s)).isEnabled)
        s.requestCloseGame()
        #expect(s.mode == .welcome && s.gameID == nil && s.feed.isEmpty)
    }

    // MARK: Options (OPT, UI-SHELL-098/099)

    @Test("OPT-025 Options groups, docked-only enablement, OK sends setOptions and Cancel discards")
    func optionsSheet() throws {
        #expect(OptionsDraft.Group.allCases.flatMap(\.fields) == OptionsDraft.Field.allCases)
        let s = try session()
        let before = try #require(s.state).options
        var d = OptionsDraft(options: before, ruleset: .modern)
        d.set(.autoFuel, !before.autoFuel)
        d.setLeaveEmpty(3)
        s.present(.sheet(.gameOptions))
        s.dismissPresentation()
        #expect(s.state?.options == before, "Cancel changes nothing")
        s.send(d.commit())
        #expect(s.state?.options.autoFuel == !before.autoFuel && s.state?.options.leaveEmpty == 3)
        d.setLeaveEmpty(500)
        #expect(d.leaveEmpty == 99)
        #expect(OptionsDraft.Field.allCases.allSatisfy { !String(localized: $0.label).isEmpty })
    }

    @Test("OPT-026 dependents are disabled and off while the parent is off (Modern/Windows); Palm hides two")
    func optionDependencies() {
        for r: RulesetID in [.modern, .windows201] {
            var d = OptionsDraft(options: GameOptions.defaults(for: r), ruleset: r)
            d.set(.alwaysIgnoreTraders, true)
            d.set(.alwaysIgnoreTradeInOrbit, true)
            #expect(d.isEnabled(.alwaysIgnoreTradeInOrbit) && d.value(.alwaysIgnoreTradeInOrbit))
            d.set(.alwaysIgnoreTraders, false)
            #expect(!d.isEnabled(.alwaysIgnoreTradeInOrbit) && !d.value(.alwaysIgnoreTradeInOrbit))
            #expect(d.isVisible(.newsAutoShow) == Ruleset.named(r).flags.travel.newsAutoShowAvailable)
        }
        var palm = OptionsDraft(options: GameOptions.defaults(for: .palm122), ruleset: .palm122)
        #expect(!palm.isVisible(.newsAutoShow) && !palm.isVisible(.disableOpponents))
        palm.set(.continuousAttack, false)
        #expect(palm.isEnabled(.continuousAttackFleeing))
    }

    @Test("OPT-027 Save as Defaults writes defaultGameOptions.<ruleset>; Load uses it or the ruleset defaults")
    func optionsDefaults() throws {
        let s = try TestSessions.make()
        var d = OptionsDraft(options: GameOptions.defaults(for: .modern), ruleset: .modern)
        d.loadDefaults(s.defaults)
        #expect(d.options == GameOptions.defaults(for: .modern).normalized(for: Ruleset.named(.modern)))
        d.set(.autoRepair, true)
        d.saveAsDefaults(s.defaults)
        #expect(s.defaults.data(forKey: "defaultGameOptions.modern") != nil)
        var fresh = OptionsDraft(options: GameOptions(), ruleset: .modern)
        fresh.loadDefaults(s.defaults)
        #expect(fresh.value(.autoRepair))
        #expect(s.quickStartConfig().options?.autoRepair == true)
    }

    @Test("OPT-028 app settings live in UserDefaults and never reach the engine")
    func settingsStayOutOfEngine() throws {
        let a = try TestSessions.make(seed: 5)
        let b = try TestSessions.make(seed: 5)
        b.defaults.set(true, forKey: AppSettingsKey.fastTravel)
        b.defaults.set(TextSizeSetting.accessibility3.rawValue, forKey: AppSettingsKey.textSize)
        b.defaults.set(false, forKey: AppSettingsKey.tacticalReadout)
        a.requestQuickStart()
        b.requestQuickStart()
        #expect(a.state == b.state)
        #expect(AppSettings(defaults: b.defaults).fastTravel && AppSettings(defaults: b.defaults).textSize == .accessibility3)
    }

    @Test("UI-SHELL-098 the options sheet identifiers")
    func optionsIdentifiers() {
        let expected = ["options.autoFuel", "options.autoRepair", "options.newsAutoPay", "options.newsAutoShow", "options.showTrackedRange",
                        "options.trackAutoOff", "options.remindLoans", "options.reserveMoney", "options.leaveEmpty",
                        "options.alwaysIgnorePirates", "options.alwaysIgnorePolice", "options.alwaysIgnoreTraders",
                        "options.alwaysIgnoreTradeInOrbit", "options.continuousAttack", "options.continuousAttackFleeing",
                        "options.disableOpponents"]
        #expect(OptionsDraft.Field.allCases.map(AXID.Options.field) == expected)
        #expect([AXID.Options.saveDefaults, AXID.Options.loadDefaults, AXID.Options.ok, AXID.Options.cancel]
            == ["options.saveDefaults", "options.loadDefaults", "options.ok", "options.cancel"])
    }

    @Test("UI-SHELL-099 OptionsDraft isEnabled/isVisible per ruleset and commit() = .setOptions")
    func optionsDraftPure() {
        for r in RulesetID.allCases {
            let o = GameOptions.defaults(for: r)
            let d = OptionsDraft(options: o, ruleset: r)
            #expect(d.commit() == .setOptions(o.normalized(for: Ruleset.named(r))))
            for f in OptionsDraft.Field.allCases where !d.isVisible(f) { #expect(!d.isEnabled(f)) }
        }
    }

    // MARK: Settings (UI-SHELL-100/101/104)

    @Test("UI-SHELL-100 Settings tabs and General settings with their defaults")
    func settingsTabs() {
        #expect(SettingsTab.allCases.map(AXID.Settings.tab)
            == ["settings.tab.general", "settings.tab.sound", "settings.tab.intelligence", "settings.tab.advanced"])
        #expect(TextSizeSetting.allCases.first?.dynamicTypeSize == .small && TextSizeSetting.allCases.last?.dynamicTypeSize == .accessibility3)
        #expect(TextSizeSetting.standard.dynamicTypeSize == .large)
        let empty = AppSettings(defaults: UserDefaults(suiteName: "pm-\(UUID().uuidString)") ?? .standard)
        #expect(empty.textSize == .large && !empty.fastTravel && empty.arrivalReportStyle == .card && empty.tacticalReadout)
        #expect(SettingsTab.allCases.allSatisfy { $0.arrivesIn == nil })
        #expect([AppSettingsKey.textSize, AppSettingsKey.fastTravel, AppSettingsKey.arrivalReportStyle, AppSettingsKey.tacticalReadout]
            == ["settings.textSize", "settings.fastTravel", "settings.arrivalReportStyle", "settings.tacticalReadout"])
    }

    @Test("UI-SHELL-101 Clear High Scores asks (destructive) and clears that ruleset's table")
    func clearHighScores() throws {
        let s = try session()
        s.send(.retire)
        if case let .sheet(.retire(p)) = s.presentation { s.confirm(p) }
        #expect(!(try s.highScoreStore.table(for: .modern)).entries.isEmpty)
        #expect(AppConfirmationText.content(for: .clearHighScores(.modern), session: s).isDestructive)
        s.confirm(.clearHighScores(.modern))
        #expect(try s.highScoreStore.table(for: .modern).entries.isEmpty)
        #expect(RulesetID.allCases.map(AXID.Settings.clearHighScores)
            == ["settings.clearHighScores.modern", "settings.clearHighScores.windows201", "settings.clearHighScores.palm122"])
    }

    @Test("UI-SHELL-104 Settings shows the loaded game's galaxy code with Copy, or no game")
    func settingsGalaxyCode() throws {
        #expect(SettingsGalaxyCode.text(state: nil) == nil)
        let st = MenuFixtures.fresh()
        let code = try #require(SettingsGalaxyCode.text(state: st))
        #expect(code == GalaxyCode(st).string)
        let board = NSPasteboard(name: NSPasteboard.Name("pm-test-\(UUID().uuidString)"))
        SettingsGalaxyCode.copy(code, to: board)
        #expect(board.string(forType: .string) == code)
    }

    // MARK: Cheats (CHEAT-013/046/050, UI-SHELL-105)

    @Test("CHEAT-013 Find text: searches stay searches; Cheetah opens the console; codes then run")
    func findHook() throws {
        let s = try session()
        #expect(s.submitFind("Scratch 5000") == .search("Scratch 5000"))
        #expect(s.state?.cheatsUsed == false)
        #expect(s.submitFind("Cheetah") == .openedConsole)
        #expect(s.state?.cheatsUsed == true && s.presentation == .sheet(.cheatConsole))
        s.dismissPresentation()
        #expect(s.submitFind("Scratch 5000") == .cheatSent)
        #expect(s.state?.commander.cash == 5_000)
        #expect(CheatForm.codes(for: .windows).allSatisfy { $0.set == .windows } && CheatForm.codes(for: .palm).contains(.moolah))
    }

    @Test("CHEAT-046 Palm Timewarp warns or asks, then opens the Open sheet; refused in Ironman")
    func timewarp() throws {
        let s = try session(.palm122)
        #expect(s.submitFind("Timewarp") == .timewarp)
        #expect(s.presentation == .appConfirmation(.timewarpLoad(reloaded: false)))
        s.confirm(.timewarpLoad(reloaded: false))
        #expect(s.presentation == .sheet(.openSavedGame))
        #expect(s.state?.cheatsUsed == false)
        let iron = try session(.palm122, ironman: true)
        iron.submitFind("Timewarp")
        guard case .systemAlert(.openFailed) = iron.presentation else {
            Issue.record("Ironman refuses Timewarp")
            return
        }
        let windows = try session()
        #expect(windows.submitFind("Timewarp") == .search("Timewarp"))
    }

    @Test("CHEAT-050 -PMFastTravel / -PMAudio off / -PMFlavor template change no game state")
    func launchFlagsInert() throws {
        var flags = LaunchOptions()
        flags.seed = 9
        flags.fastTravel = true
        flags.audioOff = true
        flags.flavorTemplate = true
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pm-\(UUID().uuidString)")
        let d = try #require(UserDefaults(suiteName: "pm-\(UUID().uuidString)"))
        let flagged = GameSession(stores: SessionStores(root: root, appVersion: "t"), launchOptions: flags, defaults: d)
        let plain = try TestSessions.make(seed: 9)
        flagged.requestQuickStart()
        plain.requestQuickStart()
        #expect(flagged.state == plain.state && flagged.state?.cheatsUsed == false)
        #expect(AppSettings(defaults: d).isFastTravel(launch: flags) && !AppSettings(defaults: d).isFastTravel(launch: .none))
    }

    @Test("UI-SHELL-105 the cheat console form: pre-filled values, codes of the set, and running a code")
    func cheatConsole() throws {
        let s = try session()
        s.submitFind("Cheetah")
        let st = try #require(s.state)
        let form = CheatForm.prefilled(.scratch, state: st)
        #expect(form.number == st.commander.cash && form.cheatCode() == .scratch(st.commander.cash))
        var iou = CheatForm.prefilled(.iou, state: st)
        iou.number = 1_234
        s.dismissPresentation()
        s.send(.cheat(iou.cheatCode()))
        #expect(s.state?.commander.debt == 1_234)
        #expect(CheatForm.Code.allCases.allSatisfy { CheatForm(code: $0).cheatCode().belongs(to: $0.set) })
        #expect(AXID.CheatConsole.all.allSatisfy { $0.hasPrefix("cheatConsole.") })
    }

    // MARK: About and Help

    @Test("UI-SHELL-106 About: version, engine, credits with links, GPL notice, license, GitHub")
    func about() {
        #expect(!AboutContent.engineVersion.isEmpty && !AboutContent.appVersion.isEmpty)
        let names = AboutContent.credits.map(\.names)
        #expect(names == ["Pieter Spronck", "Sam Anderson and Samuel Goldstein", "Matt Lee", "Jay French", "David Pierron"])
        #expect(String(localized: AboutContent.basedOn) == "Based on Space Trader by Pieter Spronck.")
        #expect(String(localized: AboutContent.gplNotice) == """
            Parsec Merchant is free software under the GNU General Public License, version 2 or later. \
            It comes with ABSOLUTELY NO WARRANTY.
            """)
        #expect(AboutContent.licenseText.contains("GNU GENERAL PUBLIC LICENSE"))
        #expect(AXID.About.all.contains("about.link.spronck") && AXID.About.all.contains("about.github"))
    }

    @Test("UI-SHELL-107 the LICENSE and CREDITS texts are bundled")
    func bundledLegal() {
        let license = AboutContent.licenseText
        #expect(license.hasPrefix("                    GNU GENERAL PUBLIC LICENSE") && license.count > 10_000)
        let credits = AboutContent.bundledText("AppCredits", "md")
        #expect(credits.hasPrefix("# Credits") && credits.contains("Pieter Spronck") && credits.contains("Jay French"))
    }

    @Test("UI-SHELL-109 the Help topics and identifiers")
    func helpTopics() {
        #expect(HelpTopic.allCases.map(\.rawValue) == ["gettingStarted", "bridge", "market", "shipyard", "outfitter", "crew", "bank", "quests",
                                                        "travel", "encounters", "howPricesWork", "rulesets", "keyboardShortcuts", "credits"])
        #expect(AXID.Help.all.contains("help.window") && AXID.Help.all.contains("help.topic.howPricesWork"))
        let blocks = MarkdownBlock.parse("# T\n\nA\nb\n- i\n## H")
        #expect(blocks == [.heading(1, "T"), .paragraph("A b"), .item("i"), .heading(2, "H")])
    }

    @Test("UI-SHELL-110 Keyboard Shortcuts is generated from every catalog shortcut plus the in-view keys")
    func shortcutsTopic() {
        let text = HelpContent.text(.keyboardShortcuts)
        for id in MenuName.allCases.flatMap({ MenuCatalog.items(in: $0) }) {
            guard let sc = MenuCatalog.entry(for: id).shortcut, MenuCatalog.entry(for: id).menu != .app else { continue }
            #expect(text.contains(sc.display), "\(id)")
        }
        #expect(text.contains("**B**") && text.contains("**S**"))
    }

    @Test("UI-SHELL-111 every Help topic resolves to a non-empty bundled Markdown file")
    func helpFiles() {
        for t in HelpContent.topics { #expect(!HelpContent.markdown(t).isEmpty, "\(t)") }
    }

    // MARK: App Intents

    @Test("UI-SHELL-112 the two intents and their App Shortcuts")
    func intentsMetadata() {
        #expect(String(localized: ContinueGameIntent.title) == "Continue Game")
        #expect(String(localized: ShowCommanderStatusIntent.title) == "Show Commander Status")
        #expect(ContinueGameIntent.supportedModes == .foreground && ShowCommanderStatusIntent.supportedModes == .background)
    }

    @Test("UI-SHELL-113 Continue Game: continues the autosave, only brings a loaded game forward, never discards")
    func continueIntent() throws {
        let empty = try TestSessions.make()
        #expect(empty.continueFromIntent() == .nothingToContinue)
        #expect(ContinueOutcome.nothingToContinue.dialogText == "There's no game to continue.")
        let s = try session(seed: FlowFixtures.flowSeed)
        s.send(.selectNextTarget(forward: true))
        s.send(.warp)
        let day = s.state?.commander.days
        #expect(day == 1 && s.state?.phase == .docked)
        #expect(s.continueFromIntent() == .alreadyLoaded && s.presentation == nil && s.state?.commander.days == day)
        s.requestCloseGame()
        if case .appConfirmation(.discardUnsavedGame) = s.presentation { s.confirm(.discardUnsavedGame) }
        #expect(s.engine == nil)
        let outcome = s.continueFromIntent()
        #expect(outcome == .continued)
        #expect(s.state?.commander.days == day)
        #expect(s.currentSlotID == nil)
    }

    @Test("UI-SHELL-114 Commander status reads the loaded game, else the Continue save, without loading for play")
    func statusQuery() throws {
        let empty = try TestSessions.make()
        #expect(CommanderStatusQuery.current(store: empty.slotStore, session: empty) == nil)
        #expect(CommanderStatus.noSaveText == "No saved game yet.")
        let s = try session()
        let st = try #require(s.state)
        let loaded = try #require(CommanderStatusQuery.current(store: s.slotStore, session: s))
        #expect(loaded.dialogText == "Commander Jameson, day 0, at \(st.systemName(st.commander.currentSystem)). 1,000 credits, debt 0, worth \(st.worth.formatted()).")
        let bytes = try Data(contentsOf: s.slotStore.url(forSlot: SlotStore.autosaveID))
        let fromSave = try #require(CommanderStatusQuery.current(store: s.slotStore, loaded: nil))
        #expect(fromSave == loaded)
        #expect(try Data(contentsOf: s.slotStore.url(forSlot: SlotStore.autosaveID)) == bytes)
    }
}
