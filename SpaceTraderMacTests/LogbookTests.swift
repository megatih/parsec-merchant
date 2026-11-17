// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import Foundation
import ParsecEngine
import ParsecInsights
import ParsecPersistence
import Testing
import UniformTypeIdentifiers
@testable import ParsecMerchant

/// LOG §6–§7 (session integration and the Logbook), STAT §5–§6 (Statistics tab, career card) and ACH §4 (service and
/// presentation).
@MainActor
struct LogbookTests {
    /// A session with a real achievement store in a temporary folder.
    static func sessionWithAchievements(seed: UInt64 = 1) throws -> GameSession {
        let id = UUID().uuidString
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pm-ach-\(id)", isDirectory: true)
        let defaults = try #require(UserDefaults(suiteName: "pm-ach-\(id)"))
        var options = LaunchOptions()
        options.seed = seed
        options.fastTravel = true
        let stores = SessionStores(root: root, appVersion: "test")
        return GameSession(stores: stores, launchOptions: options, defaults: defaults,
                           achievements: AchievementService(store: stores.achievementStore))
    }

    // MARK: Section, tabs and links

    @Test("LOG-029 the Logbook (⌘9, logbook.root) is available with a game, and is the only section of an ended game")
    func section() throws {
        let s = try TestSessions.playing()
        #expect(Section.logbook.isAvailable(in: s.sectionContext) && Section.logbook.shortcutDigit == "9")
        #expect(AXID.SectionRoot.root(.logbook) == "logbook.root" && Section.logbook.axID == "sidebar.logbook")
        try TestSessions.edit(s) { $0.phase = .gameOver(.retired) }
        #expect(Section.allCases.filter { $0.isAvailable(in: s.sectionContext) } == [.logbook])
        // An ended game shows its card unless the Logbook was chosen; it reopens on the card.
        #expect(DetailMode.derive(state: s.state, playback: nil, selected: .bridge) == .gameOver(.retired))
        #expect(DetailMode.derive(state: s.state, playback: nil, selected: .logbook) == .section(.logbook))
        #expect(Section.restored(rawValue: "logbook", context: s.sectionContext) == .bridge)
        #expect(!Section.logbook.isAvailable(in: .noGame))
    }

    @Test("MENU-023 LOG-029 Logbook ⌘9 is enabled whenever a game is loaded, including an ended game, unless modal")
    func logbookMenuItem() throws {
        func on(_ c: MenuContext) -> Bool { MenuRules.availability(of: .logbook, in: c).isEnabled }
        let enc = try #require(MenuFixtures.encounterState())
        #expect(on(MenuFixtures.ctx(MenuFixtures.fresh())) && on(MenuFixtures.ctx(MenuFixtures.ended)) && on(MenuFixtures.ctx(enc)))
        #expect(!on(MenuFixtures.ctx(nil)) && !on(MenuFixtures.ctx(MenuFixtures.fresh(), modal: true)))
        #expect(MenuContext.make(state: MenuFixtures.fresh(), isModal: false, selectedSection: .logbook).searchContext == .logbook)
    }

    @Test("LOG-030 the tab control and its three tabs, with identifiers")
    func tabs() {
        #expect(LogbookTab.allCases == [.log, .statistics, .achievements])
        #expect(LogbookTab.allCases.map(AXID.Logbook.tab) == ["logbook.tab.log", "logbook.tab.statistics", "logbook.tab.achievements"])
        #expect(AXID.Logbook.tab == "logbook.tab" && LogbookTab.log.title == "Captain's Log")
    }

    @Test("LOG-035 Show Logbook from the feed (disabled under the encounter lock) and the game-over card; Back to Summary")
    func links() throws {
        let s = try TestSessions.playing()
        let state = try #require(s.state)
        #expect(LogbookLinks.feedShowLogbookEnabled(state: state, inputLocked: false))
        #expect(!LogbookLinks.feedShowLogbookEnabled(state: state, inputLocked: true))
        s.showLogbook(tab: .log)
        #expect(s.selectedSection == .logbook && s.logbookTab == .log)
        try TestSessions.edit(s) { $0.phase = .gameOver(.killed) }
        #expect(LogbookLinks.feedShowLogbookEnabled(state: try #require(s.state), inputLocked: false))
        s.showLogbook()
        #expect(DetailMode.derive(state: s.state, playback: nil, selected: s.selectedSection) == .section(.logbook))
        s.backToSummary()
        #expect(DetailMode.derive(state: s.state, playback: nil, selected: s.selectedSection) == .gameOver(.killed))
        #expect([AXID.LogbookLinks.feedShowLogbook, AXID.LogbookLinks.gameOverShowLogbook, AXID.Logbook.backToSummary]
            == ["status.feed.showLogbook", "gameOver.showLogbook", "logbook.backToSummary"])
    }

    @Test("STAT-020 the inspector's Show Statistics selects Logbook › Statistics")
    func showStatistics() throws {
        let s = try TestSessions.playing()
        #expect(LogbookLinks.showStatisticsEnabled(sectionContext: s.sectionContext, inputLocked: false))
        #expect(!LogbookLinks.showStatisticsEnabled(sectionContext: s.sectionContext, inputLocked: true))
        #expect(!LogbookLinks.showStatisticsEnabled(sectionContext: .noGame, inputLocked: false))
        s.showLogbook(tab: .statistics)
        #expect(s.selectedSection == .logbook && s.logbookTab == .statistics)
        #expect(AXID.LogbookLinks.inspectorShowStatistics == "inspector.showStatistics")
    }

    @Test("LOG-036 every Logbook identifier is in AXID.all, unique and scheme-conformant")
    func identifiers() throws {
        let all = AXID.all
        let ids = AXID.insightsAll + [AXID.SectionRoot.root(.logbook), AXID.Sidebar.row(.logbook)]
        let regex = try Regex(AXID.pattern)
        #expect(ids.allSatisfy { all.contains($0) && $0.wholeMatch(of: regex) != nil })
        #expect(Set(all).count == all.count)
        for c in LogCategory.allCases { #expect(all.contains("logbook.filter.\(c.rawValue)")) }
        #expect(all.contains("logbook.log.list") && all.contains("logbook.search") && all.contains("logbook.export"))
    }

    // MARK: Captain's Log

    static func journal(_ kinds: [(day: Int, system: Int, kind: LogEntryKind)]) throws -> GameJournal {
        var j = GameJournal.start(state: try fixtureState())
        for k in kinds {
            j.entries.append(LogEntry(id: j.nextEntryID, day: k.day, system: k.system, worth: 1000, kind: k.kind,
                                      flavor: k.kind.flavorSubject.map { _ in .template(FlavorLine(key: "flavor.achievement.1", args: [])) }))
            j.nextEntryID += 1
        }
        return j
    }

    static func fixtureState() throws -> GameState {
        switch GameEngine.newGame(NewGameConfig(commanderName: "Tester", difficulty: .normal, skills: [5, 5, 5, 5], ruleset: .modern,
                                                seed: 1, ironman: false, shipName: nil, options: nil)) {
        case let .success(e): return e.state
        case let .failure(e): throw e
        }
    }

    @Test("LOG-032 LOG-023 search matches text or flavor ignoring case and diacritics; category filter and Clear; empty result")
    func searchAndFilter() throws {
        #expect(LogbookModel.matches(query: "ROBOTS", text: "Sold 3 robots", flavor: nil))
        #expect(LogbookModel.matches(query: "cafe", text: "x", flavor: "A quiet Café"))
        #expect(!LogbookModel.matches(query: "zzz", text: "x", flavor: "y"))
        #expect(LogbookModel.matches(query: "  ", text: "anything", flavor: nil))
        var m = LogbookModel()
        #expect(!m.isFiltered)
        m.toggle(.trade)
        #expect(m.filter.categories == [.trade] && m.isFiltered)
        m.toggle(.trade)
        m.toggle(.achievement)
        let j = try Self.journal([(4, 1, .achievementUnlocked(.firstProfit)), (4, 1, .cheatsEnabled), (6, 2, .achievementUnlocked(.moon))])
        let groups = m.groups(journal: j, text: { "entry \($0.id)" }, flavor: { _ in nil })
        #expect(groups.flatMap(\.entries).allSatisfy { $0.kind.category == .achievement })
        #expect(groups.first?.day == 6)  // newest group first
        m.clearFilters()
        m.searchText = "nothing matches this"
        #expect(m.groups(journal: j, text: { "entry \($0.id)" }, flavor: { _ in nil }).isEmpty && m.isFiltered)
        #expect(AXID.Logbook.search == "logbook.search" && AXID.Logbook.filterClear == "logbook.filter.clear")
    }

    @Test("LOG-034 Copy puts the selected rows' bullet lines on the pasteboard, oldest first")
    func copy() throws {
        let j = try Self.journal([(4, 1, .cheatsEnabled), (5, 1, .achievementUnlocked(.firstProfit))])
        var m = LogbookModel()
        #expect(m.copyText(journal: j, text: { _ in "x" }, flavor: { _ in nil }) == nil)
        let ids = j.entries.suffix(2).map(\.id)
        m.selection = Set(ids)
        let text = m.copyText(journal: j, text: { "row \($0.id)" }, flavor: { _ in nil })
        #expect(text == "- row \(ids[0])\n- row \(ids[1])\n")
    }

    @Test("LOG-033 Export writes a .md plain-text document named after the commander")
    func export() throws {
        #expect(LogMarkdownDocument.markdown.preferredFilenameExtension == "md")
        #expect(LogMarkdownDocument.markdown.conforms(to: .plainText))
        #expect(LogbookModel.exportName(commander: "Jameson") == "Jameson – Captain's Log")
        let s = try TestSessions.playing()
        let state = try #require(s.state)
        let journal = try #require(s.journal)
        let md = LogExport.markdown(journal: journal, state: state, filter: LogFilter(), showFlavor: true)
        #expect(md.hasPrefix("# \(state.commander.name) – Captain"))
        #expect(LogExport.header(state: state).metadata.contains(GalaxyCode(state).string))
    }

    @Test("LOG-031 LOG-010 rows show the category symbol; every category has a symbol and a title")
    func categoryStyle() {
        #expect(Set(LogCategory.allCases.map(LogCategoryStyle.symbol)).count == LogCategory.allCases.count)
        #expect(LogCategoryStyle.symbol(.trade) == FeedCategory.trade.symbol && LogCategoryStyle.symbol(.news) == FeedCategory.news.symbol)
        for c in LogCategory.allCases { #expect(!String(localized: LogCategoryStyle.title(c)).isEmpty) }
    }

    // MARK: Achievements service and Settings

    @Test("ACH-016 ACH-017 unlocks go to the store; only newly added ids produce a feed note")
    func achievementService() throws {
        let s = try Self.sessionWithAchievements()
        s.requestQuickStart()
        let state = try #require(s.state)
        let output = JournalStepOutput(newEntries: [], unlocked: [.firstProfit])
        #expect(s.achievements.observe(output, gameID: "g1", state: state) == [.firstProfit])
        #expect(s.achievements.observe(output, gameID: "g2", state: state).isEmpty)
        #expect(s.achievements.records.map(\.id) == ["firstProfit"] && s.achievements.records.first?.gameID == "g1")
        #expect(String(localized: EventText.text(for: FeedNote.achievementUnlocked(.firstProfit))) == "Achievement unlocked: First Profit")
        #expect(FeedStyle.classify(FeedNote.achievementUnlocked(.firstProfit)) == FeedStyle(.system, .notice))
        #expect(NoAchievements().observe(output, gameID: "g", state: state).isEmpty)
    }

    @Test("ACH-021 ACH-014 Reset Achievements asks a destructive confirmation and empties the store")
    func resetAchievements() throws {
        let s = try Self.sessionWithAchievements()
        s.requestQuickStart()
        _ = s.achievements.observe(JournalStepOutput(newEntries: [], unlocked: [.firstProfit]), gameID: "g", state: try #require(s.state))
        let c = AppConfirmationText.content(for: .resetAchievements, session: s)
        #expect(c.isDestructive && c.title == "Reset all achievements?" && c.message == "This can't be undone.")
        let revision = s.achievementsRevision
        s.confirm(.resetAchievements)
        #expect(s.achievements.records.isEmpty && s.achievementsRevision == revision + 1)
        #expect(AXID.IntelSettings.resetAchievements == "settings.resetAchievements")
        #expect(AppConfirmationKind(.resetAchievements) == .resetAchievements)
    }

    @Test("ACH-015 -PMResetState clears the achievement store with the rest of the sandbox data")
    func resetState() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pm-reset-\(UUID().uuidString)", isDirectory: true)
        var store = AchievementStore(root: root)
        _ = try store.unlock(["firstProfit"], gameID: "g", rulesetID: "modern", day: 1)
        #expect(!(try AchievementStore(root: root).records()).isEmpty)
        let defaults = try #require(UserDefaults(suiteName: "pm-reset-\(UUID().uuidString)"))
        AppPaths.resetState(root: root, defaults: defaults, domain: nil)
        #expect((try AchievementStore(root: root).records()).isEmpty)
    }
}
