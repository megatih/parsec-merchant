// SPDX-License-Identifier: GPL-2.0-or-later
import CoreGraphics
import Foundation
import ParsecEngine
import ParsecInsights
import ParsecPersistence
import Testing
@testable import ParsecMerchant

/// Mirrors `UITestFixtures.achievementSeed`/`achievementItem` of the UI-test target (ACH-022); keep them in step.
enum AchievementFixtures {
    static let seed: UInt64 = 11
    static let item = TradeItemType.games
}

/// LOG §6 (session integration), STAT §1/§5/§6, ACH-018/022 and LLM-011/028 with the real journal recorder.
@MainActor
struct JournalSessionTests {
    static func kinds(_ s: GameSession) -> [LogEntryKind] { s.journal?.entries.map(\.kind) ?? [] }

    /// Waits until the STAT-003 rebuild has applied its result.
    static func waitForStats(_ s: GameSession) async {
        for _ in 0..<2_000 where s.careerStats == nil { await Task.yield() }
    }

    // MARK: LOG-025…028

    @Test("LOG-025 a new game starts a journal; accepted steps are recorded before persistence; Close Game clears it")
    func journalLifecycle() throws {
        let s = try TestSessions.playing(seed: AchievementFixtures.seed)
        let j = try #require(s.journal)
        guard case let .journalStarted(start) = j.entries.first?.kind else {
            Issue.record("entry 1 is journalStarted")
            return
        }
        #expect(start.origin == .newGame && j.entries.first?.id == 1)
        let count = j.entries.count
        s.send(.buyCargo(AchievementFixtures.item, quantity: 1))
        #expect((s.journal?.entries.count ?? 0) == count + 1)
        if case let .trade(t)? = s.journal?.entries.last?.kind { #expect(t.action == .buy && t.item == AchievementFixtures.item) }
        // A rejected step records nothing.
        s.send(.buyCargo(.robots, quantity: 100_000))
        #expect((s.journal?.entries.count ?? 0) == count + 1)
        s.closeGame()
        #expect(s.journal == nil && s.careerStats == nil)
    }

    @Test("LOG-026 LOG-007 save, autosave, load and export carry the journal unchanged")
    func savePath() throws {
        let s = try TestSessions.playing(seed: AchievementFixtures.seed)
        s.send(.buyCargo(AchievementFixtures.item, quantity: 1))
        s.save()
        let slot = try #require(s.currentSlotID)
        let saved = try #require(s.journal)
        let loaded = try s.slotStore.loadForPlay(slot: slot, revert: false, currentGameID: nil)
        #expect(loaded.journal == saved)
        s.send(.selectNextTarget(forward: true))
        s.send(.warp)
        let auto = try s.slotStore.loadForPlay(slot: SlotStore.autosaveID, revert: false, currentGameID: nil)
        #expect(auto.journal == s.journal)
        let exported = try SaveCodec.decode(try #require(try s.exportCurrentGame()))
        #expect(exported.journal == s.journal)
        s.install(loaded)
        #expect(s.journal == saved)
    }

    @Test("LOG-028 UI-ENC-099 a trip with an encounter, arrival report, special event and newspaper is in the journal")
    func scriptedTrip() throws {
        let s = try TestSessions.make()
        s.install(PirateAmbushScenario.make(), gameID: "ambush", slotID: nil)
        s.send(.warp)
        var attacks = 0
        while case .encounter = s.state?.phase, attacks < AmbushFixtures.ambushMaxAttacks {
            s.send(.encounter(.attack))
            attacks += 1
            TestSessions.resolvePresentation(s)
        }
        while s.presentation != nil { TestSessions.resolvePresentation(s) }
        let kinds = Self.kinds(s)
        #expect(kinds.contains { if case .encounter = $0 { true } else { false } })
        #expect(kinds.contains { if case let .arrived(a) = $0 { a.system == AmbushFixtures.ambushTarget } else { false } })
        #expect(kinds.contains { if case .departed = $0 { true } else { false } })
        s.send(.readNewspaper, acknowledging: [.buyNewspaper])
        #expect(Self.kinds(s).contains { if case .news = $0 { true } else { false } })
        let q = try TestSessions.make()
        q.install(EncounterFixtureScenario.makeSpecialEvent(), gameID: "special", slotID: nil)
        q.send(.specialEvent, acknowledging: [.acceptSpecialEvent])
        while q.presentation != nil { TestSessions.resolvePresentation(q) }
        #expect(Self.kinds(q).contains { if case .quest = $0 { true } else { false } })
    }

    @Test("LOG-023 every entry kind renders a non-empty localized text")
    func entryText() throws {
        let s = try TestSessions.playing()
        let st = try #require(s.state)
        let j = try #require(s.journal)
        let kills = st.commander.kills
        let record = EncounterRecord(type: .pirateAttack, opponent: .gnat, rounds: 2, outcome: .destroyed(.gnat), bounty: 100,
                                     minHullPercent: 50, killsAfter: kills)
        let start = JournalStart(origin: .resumed, rulesetID: .modern, difficulty: .normal, ironman: false, systemCount: 120,
                                 startSystem: 0, visitedSystems: [0], kills: kills)
        let kinds: [LogEntryKind] = [
            .journalStarted(start), .cheatsEnabled, .gameEnded(.retired, score: 1234), .achievementUnlocked(.firstProfit),
            .trade(TradeEntry(action: .sell, item: .ore, quantity: 2, total: 800, profit: 120)),
            .departed(from: 0, to: 1, viaWormhole: false, parsecs: 7),
            .arrived(TripArrival(system: 1, from: 0, viaWormhole: false, firstVisit: true, uneventful: false, encounterCount: 2)),
            .fabricRip(newDestination: 2), .singularityLost, .encounter(record),
            .police(.arrested(term: 10, fine: 500, shipSold: false)), .police(.caughtLittering), .police(.reactorConfiscated),
            .finance(.borrowed(amount: 500)), .finance(.repaid(amount: 500, remainingDebt: 0)), .finance(.insuranceBought),
            .finance(.insuranceStopped), .finance(.debtWarning(debt: 80_000)), .finance(.debtReminder(debt: 80_000)),
            .ship(.boughtShip(.gnat, netPrice: 1000)), .ship(.customShipBuilt(.corellian)), .ship(.equipment(.boughtWeapon(.pulseLaser), price: 2000)),
            .ship(.equipment(.soldShield(.energy), price: 2000)), .ship(.equipment(.boughtGadget(.navigatingSystem), price: 2000)),
            .ship(.boughtEscapePod(price: 2000)), .ship(.fuel(units: 3, cost: 6)), .ship(.repair(points: 4, cost: 8)),
            .ship(.autoFuelFailed), .ship(.autoRepairFailed), .ship(.escapePodUsed(insurancePayout: 1000)),
            .crew(.hired(crewID: 1)), .crew(.fired(crewID: 1)), .crew(.passengerConcerned(crewID: 1)), .crew(.passengerImpatient(crewID: 1)),
            .quest(.completed(.japoriDelivery)), .quest(.refused(.moon)), .quest(.tribbles(from: 1, to: 10)),
            .quest(.tribblesDied(.allFromReactor)), .quest(.tribblesAteFood(eaten: 3)), .quest(.tribbleInspectorWarning(count: 9)),
            .quest(.reactorWarning(status: 3)), .quest(.reactorMeltdown), .quest(.gemulonInvaded), .quest(.experimentPerformed),
            .quest(.wildLeftShip), .quest(.easterEgg(shieldInstalled: true)),
            .news(NewsEntry(headlines: [], cost: 10)),
            .status(.policeRecord(from: .clean, to: .lawful)), .status(.reputation(from: .harmless, to: .mostlyHarmless)),
        ]
        for kind in kinds {
            let text = LogEntryText.text(for: LogEntry(id: 1, day: 1, system: 0, worth: 0, kind: kind), journal: j, state: st)
            #expect(!text.isEmpty && !text.contains("%@") && !text.contains("%lld"), "\(kind): \(text)")
        }
        #expect(LogEntryText.encounterDetails(record).contains("2 rounds"))
    }

    // MARK: STAT

    @Test("STAT-002 STAT-003 the session folds the journal off the main actor on install and adds each step's entries")
    func incrementalStats() async throws {
        let s = try TestSessions.playing(seed: AchievementFixtures.seed)
        await Self.waitForStats(s)
        s.send(.buyCargo(AchievementFixtures.item, quantity: 1))
        s.send(.selectNextTarget(forward: true))
        s.send(.warp)
        #expect(s.careerStats == CareerStats.fold(try #require(s.journal).entries))
        s.save()
        let slot = try #require(s.currentSlotID)
        s.openSlot(slot)
        #expect(s.isRebuildingStats)
        await Self.waitForStats(s)
        #expect(s.careerStats == CareerStats.fold(try #require(s.journal).entries))
    }

    @Test("STAT-017 STAT-018 STAT-019 Statistics tiles, charts, notices and the copied Markdown table")
    func statisticsModel() throws {
        let s = try TestSessions.playing(seed: AchievementFixtures.seed)
        let item = AchievementFixtures.item
        s.send(.buyCargo(item, quantity: 1))
        s.send(.selectNextTarget(forward: true))
        s.send(.warp)
        s.send(.sellCargo(item, quantity: 1))
        let stats = CareerStats.fold(try #require(s.journal).entries)
        let m = StatisticsModel.make(stats: stats)
        #expect(m.tiles.map(\.kind) == StatFigureKind.allCases)
        #expect(m.profitBars.count == 1 && m.profitBars.first?.signText == "+" && m.killBars.isEmpty)
        #expect(m.sinceText == "Statistics since the start" && m.cheatNotice == nil)
        let md = StatisticsModel.copyText(stats: stats)
        #expect(md.hasPrefix("| Statistic | Value |") && md.contains("Days played"))
        #expect(StatFigureKind.allCases.map(AXID.Logbook.figure).allSatisfy { AXID.all.contains($0) })
        // A resumed journal is partial; a cheated game shows the notice.
        let resumed = CareerStats.fold(GameJournal.bootstrap(from: try #require(s.state)).entries)
        #expect(StatisticsModel.make(stats: resumed).sinceText.hasPrefix("Statistics since day"))
        var cheated = try #require(s.journal)
        cheated.entries.append(LogEntry(id: cheated.nextEntryID, day: 1, system: 0, worth: 0, kind: .cheatsEnabled))
        #expect(StatisticsModel.make(stats: CareerStats.fold(cheated.entries)).cheatNotice == "Cheats were used in this game")
    }

    @Test("STAT-021 STAT-022 the career card adds STAT totals when present and renders them in the shared image")
    func careerCard() throws {
        let s = try TestSessions.playing(seed: AchievementFixtures.seed)
        try TestSessions.edit(s) { $0.phase = .gameOver(.retired) }
        let st = try #require(s.state)
        let stats = CareerStats.fold(try #require(s.journal).entries)
        let without = CareerCard.make(state: st, end: .retired, recorded: nil)
        let with = CareerCard.make(state: st, end: .retired, recorded: nil, stats: stats)
        #expect(without.stats == nil && with.stats == CareerStatTotals(stats))
        #expect(with.piratesKilled == st.commander.kills.pirates && with.stats?.systemCount == st.galaxy.systems.count)
        #expect(CareerText.bestTrade(nil) == "None")
        let plain = try #require(CareerCardRenderer.image(card: without))
        let image = try #require(CareerCardRenderer.image(card: with))
        #expect(image.width == plain.width && image.height > plain.height)
    }

    // MARK: ACH

    @Test("ACH-018 achievements never change state: the same game with the real service and NoAchievements")
    func achievementDeterminism() throws {
        let real = try LogbookTests.sessionWithAchievements(seed: AchievementFixtures.seed)
        let none = try TestSessions.make(seed: AchievementFixtures.seed)
        for s in [real, none] { s.requestQuickStart() }
        let script: [Command] = [.buyCargo(AchievementFixtures.item, quantity: 1), .selectNextTarget(forward: true), .warp,
                                 .sellCargo(AchievementFixtures.item, quantity: 1)]
        for c in script {
            real.send(c)
            none.send(c)
            #expect(real.state == none.state)
        }
        #expect(real.achievements.records.map(\.id).contains("firstProfit"))
    }

    @Test("ACH-022 the achievement seed: an uneventful trip and a profitable sale of one fixture item unlock First Profit")
    func achievementSeed() throws {
        let s = try LogbookTests.sessionWithAchievements(seed: AchievementFixtures.seed)
        s.requestQuickStart()
        s.send(.buyCargo(AchievementFixtures.item, quantity: 1))
        s.send(.selectNextTarget(forward: true))
        s.send(.warp)
        #expect(s.state?.phase == .docked && s.feed.contains { $0.event == .uneventfulTrip })
        s.send(.sellCargo(AchievementFixtures.item, quantity: 1))
        #expect(s.feed.contains { $0.entry == .note(.achievementUnlocked(.firstProfit)) })
        let st = try #require(s.state)
        let m = AchievementsModel.make(stats: s.careerStats, ruleset: st.ruleset, records: s.achievements.records, journal: s.journal,
                                       cheatsUsed: st.cheatsUsed)
        let badge = try #require(m.badges.first { $0.id == .firstProfit })
        #expect(badge.unlocked && badge.unlockedText != nil && badge.inGameText != nil && badge.symbol != "lock.circle")
        #expect(m.headerText.hasPrefix("1 of "))
    }

    @Test("ACH-010 ACH-019 ACH-020 the badge grid: available ones in catalog order, progress, unavailable group, cheat banner")
    func achievementsModel() throws {
        let s = try TestSessions.playing()
        let st = try #require(s.state)
        let stats = CareerStats.fold(try #require(s.journal).entries)
        for r in RulesetID.allCases {
            let ruleset = Ruleset.named(r)
            let m = AchievementsModel.make(stats: stats, ruleset: ruleset, records: [], journal: s.journal, cheatsUsed: false)
            #expect(m.badges.map(\.id) == AchievementCatalog.available(in: ruleset))
            #expect(m.badges.count + m.unavailable.count == AchievementID.allCases.count && m.badges.count >= 30)
            #expect(m.disabledBanner == nil && m.badges.allSatisfy { !$0.unlocked && $0.symbol == "lock.circle" })
            #expect(m.badges.first { $0.id == .worth10k }?.progress?.target == 10_000)
        }
        let palm = AchievementsModel.make(stats: stats, ruleset: .named(.palm122), records: [], journal: nil, cheatsUsed: false)
        #expect(palm.unavailable.map(\.id).contains(.sculpture))
        let record = AchievementRecord(id: "firstProfit", unlockedAt: "2026-11-17T10:00:00Z", gameID: "g", rulesetID: "modern", day: 3)
        let cheated = AchievementsModel.make(stats: stats, ruleset: st.ruleset, records: [record], journal: s.journal, cheatsUsed: true)
        #expect(cheated.disabledBanner == "Achievements are disabled for this game because cheats were used.")
        #expect(cheated.badges.allSatisfy { $0.progress == nil })
        #expect(cheated.badges.first { $0.id == .firstProfit }?.unlocked == true)
        #expect(AchievementID.allCases.allSatisfy { !AchievementText.name($0).isEmpty && !AchievementText.description($0).isEmpty })
    }

    // MARK: LLM

    @Test("LLM-011 every template catalog key renders a localized line with its typed arguments")
    func catalogText() throws {
        let s = try TestSessions.playing()
        let st = try #require(s.state)
        for entry in TemplateFlavorProvider.catalog {
            let args: [FlavorArg] = entry.argTypes.map { t in
                switch t {
                case .system: .system(0)
                case .ship: .ship(.gnat)
                case .item: .item(.ore)
                case .count: .count(3)
                case .credits: .credits(100)
                case .skill: .skill(.pilot)
                }
            }
            let text = FlavorCatalogText.text(for: FlavorLine(key: entry.key, args: args), state: st)
            #expect(text?.isEmpty == false && text?.contains("%") == false, "\(entry.key)")
        }
        #expect(FlavorCatalogText.text(for: FlavorLine(key: "flavor.unknown.1", args: []), state: st) == nil)
        #expect(FlavorCatalogText.text(for: .generated(text: "Prose."), state: st) == "Prose.")
    }

    @Test("LLM-028 the same session behaves identically with templates, a fixed-prose model and a timing-out model")
    func behavesIdentically() async throws {
        func makeSession(_ flavor: FlavorService) throws -> GameSession {
            let id = UUID().uuidString
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("pm-llm-\(id)", isDirectory: true)
            var options = LaunchOptions()
            options.seed = AmbushFixtures.ambushSeed
            options.fastTravel = true
            return GameSession(stores: SessionStores(root: root, appVersion: "test"), launchOptions: options,
                               defaults: try #require(UserDefaults(suiteName: "pm-llm-\(id)")), flavor: flavor)
        }
        let prose = FlavorService(mode: .foundationModels) { { _, _ in .generated(text: "Fixed prose.") } }
        let timeout = FlavorService(mode: .foundationModels) { { _, _ in nil } }
        let sessions = try [makeSession(FlavorService(mode: .templateForced)), makeSession(prose), makeSession(timeout)]
        for s in sessions { s.install(PirateAmbushScenario.make(), gameID: "same", slotID: nil) }
        var script: [Command] = [.warp]
        script += Array(repeating: .encounter(.attack), count: AmbushFixtures.ambushMaxAttacks)
        for c in script {
            for s in sessions {
                if case .encounter = c, s.state.map({ if case .encounter = $0.phase { false } else { true } }) == true { continue }
                s.send(c)
                while s.presentation != nil { TestSessions.resolvePresentation(s) }
            }
            let first = sessions[0]
            for s in sessions.dropFirst() {
                #expect(s.state == first.state && s.stateGeneration == first.stateGeneration && s.feed == first.feed)
            }
        }
        for _ in 0..<200 { await Task.yield() }
        func stripped(_ j: GameJournal?) -> [LogEntry] {
            (j?.entries ?? []).map { var e = $0; e.flavor = nil; return e }
        }
        #expect(stripped(sessions[1].journal) == stripped(sessions[0].journal))
        #expect(stripped(sessions[2].journal) == stripped(sessions[0].journal))
        #expect(sessions[2].journal?.entries.allSatisfy { $0.flavor?.source != .foundationModels } == true)
    }
}
