// SPDX-License-Identifier: GPL-2.0-or-later
// STAT (docs/specs/STAT.md): career statistics as a fold over the log.
import Testing
@testable import ParsecEngine
@testable import ParsecInsights

private func arrival(_ system: Int, encounters: Int = 0) -> LogEntryKind {
    .arrived(TripArrival(system: system, from: 0, viaWormhole: false, firstVisit: true, uneventful: encounters == 0,
                         encounterCount: encounters))
}

private func sale(_ item: TradeItemType, _ q: Int, total: Int, profit: Int, orbit: Bool = false) -> LogEntryKind {
    .trade(TradeEntry(action: orbit ? .orbitSell : .sell, item: item, quantity: q, total: total, profit: profit))
}

private func buy(_ item: TradeItemType, _ q: Int, total: Int, orbit: Bool = false) -> LogEntryKind {
    .trade(TradeEntry(action: orbit ? .orbitBuy : .buy, item: item, quantity: q, total: total))
}

@Suite("STAT statistics")
struct StatsSpecTests {
    @Test("STAT-001 fold equals reduce over add; an empty log gives the zero value")
    func fold() {
        #expect(CareerStats.fold([]) == CareerStats())
        let zero = CareerStats()
        #expect(zero.daysPlayed == 0 && zero.entryCount == 0 && zero.peakWorth == nil && zero.bestSale == nil)
        var b = EntryBuilder(start: EntryBuilder.start())
        b.add(buy(.ore, 2, total: 100), day: 1)
        b.add(sale(.ore, 2, total: 160, profit: 60), day: 2)
        var manual = CareerStats()
        for e in b.entries { manual.add(e) }
        #expect(CareerStats.fold(b.entries) == manual && manual.entryCount == 3)
    }

    @Test("STAT-002 incremental equivalence over recorded fuzz games: whole fold = per-step adds = prefix + rest",
          arguments: RulesetID.allCases)
    func incremental(_ r: RulesetID) {
        for game in 0..<50 {
            var g = RecordedGame(r, seed: 7_000 + UInt64(game))
            var running = CareerStats.fold(g.journal.entries)
            var r2 = Xoshiro256StarStar(seed: UInt64(game))
            for _ in 0..<60 {
                if case .gameOver = g.state.phase { break }
                let out = g.send(InsightsFuzz.pickCommand(g.state, &r2))
                _ = out
                for e in g.outputs.last?.newEntries ?? [] { running.add(e) }
            }
            let entries = g.journal.entries
            let whole = CareerStats.fold(entries)
            #expect(whole == running)
            #expect(g.journal.stats == whole)
            let cut = entries.count / 2
            var prefix = CareerStats.fold(Array(entries[..<cut]))
            for e in entries[cut...] { prefix.add(e) }
            #expect(prefix == whole)
        }
    }

    @Test("STAT-004 a resumed journal is a partial history")
    func partial() {
        #expect(!EntryBuilder(start: EntryBuilder.start()).stats.isPartial)
        #expect(EntryBuilder(start: EntryBuilder.start(.resumed)).stats.isPartial)
        #expect(CareerStats.fold(GameJournal.bootstrap(from: freshState()).entries).isPartial)
    }

    @Test("STAT-005 time and travel: days, warps, wormhole jumps, parsecs, arrivals, rips, visited systems")
    func travel() {
        var b = EntryBuilder(start: EntryBuilder.start(systems: 10, visited: [2, 5]))
        b.add(.departed(from: 2, to: 3, viaWormhole: false, parsecs: 7), day: 4)
        b.add(arrival(3), day: 6)
        b.add(.departed(from: 3, to: 9, viaWormhole: true, parsecs: 0))
        b.add(.fabricRip(newDestination: 8))
        b.add(arrival(8), day: 9)
        b.add(arrival(3))
        b.add(arrival(99))
        let s = b.stats
        #expect(s.startDay == 0 && s.lastDay == 9 && s.daysPlayed == 9)
        #expect(s.warps == 2 && s.wormholeJumps == 1 && s.parsecsTravelled == 7 && s.arrivals == 4 && s.fabricRips == 1)
        #expect(s.systemCount == 10 && s.visitedCount == 4)
        #expect(s.visitedSystems.enumerated().filter(\.element).map(\.offset) == [2, 3, 5, 8])
    }

    @Test("STAT-006 trade: counts, units, totals, profit by item, items traded, best sale, first profit, plunder, scoop, dump")
    func trade() {
        var b = EntryBuilder(start: EntryBuilder.start())
        b.add(buy(.ore, 3, total: 150), day: 1)
        b.add(buy(.robots, 1, total: 900, orbit: true))
        b.add(sale(.ore, 1, total: 40, profit: -10), day: 2)
        b.add(sale(.ore, 2, total: 200, profit: 100), day: 3, system: 4)
        b.add(sale(.robots, 1, total: 1_000, profit: 100, orbit: true), day: 5)
        b.add(.trade(TradeEntry(action: .plunder, item: .furs, quantity: 4, total: 0)))
        b.add(.trade(TradeEntry(action: .scoop, item: .water, quantity: 1, total: 0)))
        b.add(.trade(TradeEntry(action: .dump, item: .water, quantity: 1, total: 15)))
        b.add(.trade(TradeEntry(action: .jettison, item: .water, quantity: 1, total: 0)))
        b.add(.trade(TradeEntry(action: .sealedCanisters, item: .narcotics, quantity: 3, total: 0)))
        let s = b.stats
        #expect(s.buys == 2 && s.sells == 3 && s.unitsBought == 4 && s.unitsSold == 4)
        #expect(s.spentOnCargo == 1_050 && s.earnedFromCargo == 1_240)
        #expect(s.profitByItem[TradeItemType.ore.rawValue] == 90 && s.profitByItem[TradeItemType.robots.rawValue] == 100)
        #expect(s.totalTradeProfit == 190 && s.firstProfitDay == 3)
        #expect(s.bestSale == BestSale(item: .ore, quantity: 2, profit: 100, day: 3, system: 4))
        #expect(s.itemsBought[TradeItemType.robots.rawValue] && s.itemsSold[TradeItemType.ore.rawValue] && !s.itemsSold[0])
        #expect(s.plunderedUnits == 4 && s.scoopedUnits == 1 && s.dumpCosts == 15)
    }

    @Test("STAT-007 worth: one sample per day (last entry of the day), peak and latest")
    func worth() {
        var b = EntryBuilder(start: EntryBuilder.start())
        b.add(.cheatsEnabled, day: 0, worth: 3_000)
        b.add(.singularityLost, day: 2, worth: 9_000)
        b.add(.singularityLost, day: 2, worth: 4_000)
        b.add(.singularityLost, day: 5, worth: 5_000)
        let s = b.stats
        #expect(s.worthSamples == [WorthSample(day: 0, worth: 3_000), WorthSample(day: 2, worth: 4_000), WorthSample(day: 5, worth: 5_000)])
        #expect(s.peakWorth == 9_000 && s.latestWorth == 5_000)
    }

    @Test("STAT-008 STAT-009 combat: encounters by type, destroyed by ship, engine kills, bounties, lowest hull survived, results")
    func combat() {
        var b = EntryBuilder(start: EntryBuilder.start())
        #expect(b.stats.kills == Kills())
        b.add(.encounter(record(.destroyed(.wasp), bounty: 500, kills: Kills(pirates: 1))))
        b.add(.encounter(record(.escaped, type: .policeAttack, hull: 7)))
        b.add(.encounter(record(.raided(units: 2), hull: 3)))
        b.add(.encounter(record(.killed, hull: 0, kills: Kills(pirates: 2, police: 1, traders: 0))))
        b.add(.encounter(record(.passed, type: .traderIgnore, bounty: 0, kills: Kills(pirates: 2, police: 1, traders: 0))))
        let s = b.stats
        #expect(s.encounters == 5 && s.encountersByType[EncounterType.pirateAttack.rawValue] == 3)
        #expect(s.destroyedByShipType[ShipType.wasp.rawValue] == 1 && s.bountiesCollected == 1 && s.bountyTotal == 500)
        #expect(s.kills == Kills(pirates: 2, police: 1, traders: 0))
        #expect(s.lowestHullPercentSurvived == 3)
        #expect([s.count(.won), s.count(.fled), s.count(.surrendered), s.count(.lost), s.count(.other)] == [1, 1, 1, 1, 1])
    }

    @Test("STAT-010 law and money: arrests, fines, bribes, inspections, record extremes, loans, payouts, pods")
    func lawAndMoney() {
        var b = EntryBuilder(start: EntryBuilder.start())
        b.add(.encounter(record(.fined(300), type: .policeInspect)))
        b.add(.encounter(record(.bribed(200), type: .policeInspect)))
        b.add(.encounter(record(.inspectedClean, type: .policeInspect)))
        b.add(.police(.arrested(term: 30, fine: 1_000, shipSold: false)))
        b.add(.status(.policeRecord(from: .clean, to: .villain)))
        b.add(.status(.policeRecord(from: .villain, to: .lawful)))
        b.add(.status(.reputation(from: .harmless, to: .average)))
        b.add(.finance(.borrowed(amount: 500)))
        b.add(.finance(.repaid(amount: 200, remainingDebt: 300)))
        b.add(.finance(.repaid(amount: 300, remainingDebt: 0)))
        b.add(.ship(.escapePodUsed(insurancePayout: 4_000)))
        let s = b.stats
        #expect(s.arrests == 1 && s.finesPaid == 1_300 && s.bribesPaid == 200 && s.inspectionsPassed == 1)
        #expect(s.policeRecordLowest == .villain && s.policeRecordHighest == .lawful && s.reputationHighest == .average)
        #expect(s.borrowedTotal == 500 && s.repaidTotal == 500 && s.loansPaidOff == 1 && s.insurancePayouts == 4_000 && s.escapePodsUsed == 1)
    }

    @Test("STAT-011 ship, crew and quests: ships, custom ships, equipment, fuel, repairs, hires, quests, tribbles, news, rare meets")
    func shipCrewQuests() {
        var b = EntryBuilder(start: EntryBuilder.start())
        b.add(.ship(.boughtShip(.beetle, netPrice: 9_000)))
        b.add(.ship(.customShipBuilt(.sienar)))
        b.add(.ship(.equipment(.boughtWeapon(.beamLaser), price: 1)))
        b.add(.ship(.equipment(.boughtGadget(.navigatingSystem), price: 1)))
        b.add(.ship(.equipment(.soldShield(.energy), price: 1)))
        b.add(.ship(.fuel(units: 5, cost: 10)))
        b.add(.ship(.repair(points: 3, cost: 9)))
        b.add(.ship(.boughtEscapePod(price: 2_000)))
        b.add(.crew(.hired(crewID: 3)))
        b.add(.crew(.fired(crewID: 3)))
        b.add(.quest(.completed(.japoriDelivery)))
        b.add(.quest(.tribbles(from: 1, to: 500)))
        b.add(.quest(.tribbles(from: 500, to: 20)))
        b.add(.news(NewsEntry(headlines: [], cost: 3)))
        b.add(.encounter(record(.passed, type: .marieCeleste)))
        b.add(.encounter(record(.passed, type: .captainConrad)))
        let s = b.stats
        #expect(s.shipsBought == 2 && s.customShipsBuilt == 1 && s.equipmentBought == 2 && s.equipmentSold == 1)
        #expect(s.fuelSpent == 10 && s.repairsSpent == 9 && s.mercenariesHired == 1)
        #expect(s.completed(.japoriDelivery) && !s.completed(.japori) && s.maxTribbles == 500 && s.newspapersRead == 1)
        #expect(s.marieCelesteFound && s.famousCaptainsMet == [false, true, false])
    }

    @Test("STAT-012 game: ruleset, difficulty, Ironman, cheats, ending, score, achievements")
    func game() {
        var b = EntryBuilder(start: EntryBuilder.start(ruleset: .palm122, difficulty: .hard, ironman: true))
        b.add(.achievementUnlocked(.firstProfit))
        b.add(.cheatsEnabled)
        b.add(.gameEnded(.boughtMoon, score: 12_345))
        let s = b.stats
        #expect(s.ruleset == .palm122 && s.difficulty == .hard && s.ironman && s.cheatsUsed)
        #expect(s.ended == .boughtMoon && s.finalScore == 12_345 && s.achievementsUnlocked == 1)
    }

    @Test("STAT-013 worthSeries: unchanged when short; bucketed by day otherwise, first and last kept (10, 500, 5000 samples)")
    func worthSeries() {
        for n in [10, 500, 5_000] {
            var b = EntryBuilder()
            for d in 0..<n { b.add(.singularityLost, day: d * 3, worth: d) }
            let s = b.stats
            let series = s.worthSeries(maxPoints: 400)
            if n <= 400 {
                #expect(series == s.worthSamples)
            } else {
                #expect(series.count <= 400 && series.first == s.worthSamples.first && series.last == s.worthSamples.last)
                #expect(zip(series, series.dropFirst()).allSatisfy { $0.day < $1.day })
                #expect(series == s.worthSeries(maxPoints: 400))
            }
        }
        var b = EntryBuilder()
        for d in 0..<5 { b.add(.singularityLost, day: d, worth: d) }
        #expect(b.stats.worthSeries(maxPoints: 0).isEmpty && b.stats.worthSeries(maxPoints: 1) == [WorthSample(day: 4, worth: 4)])
    }

    @Test("STAT-014 figures: the tiles in fixed order with typed values")
    func figures() {
        var b = EntryBuilder(start: EntryBuilder.start(systems: 5, visited: [0]))
        b.add(.departed(from: 0, to: 1, viaWormhole: true, parsecs: 0), day: 3)
        b.add(arrival(1))
        b.add(buy(.ore, 1, total: 10))
        b.add(sale(.ore, 1, total: 30, profit: 20), worth: 7_000)
        b.add(.encounter(record(.destroyed(.gnat), bounty: 50, kills: Kills(pirates: 1, police: 2, traders: 3))))
        b.add(.encounter(record(.fined(5), kills: Kills(pirates: 1, police: 2, traders: 3))))
        b.add(.police(.arrested(term: 1, fine: 10, shipSold: false)))
        let f = b.stats.figures
        #expect(f.map(\.kind) == StatFigureKind.allCases)
        let v = Dictionary(uniqueKeysWithValues: f.map { ($0.kind, $0.value) })
        #expect(v[.daysPlayed] == .days(3) && v[.parsecsTravelled] == .parsecs(0) && v[.systemsVisited] == .systems(visited: 2, of: 5))
        #expect(v[.wormholeJumps] == .count(1) && v[.trades] == .count(2) && v[.totalTradeProfit] == .credits(20))
        #expect(v[.bestTrade] == .trade(BestSale(item: .ore, quantity: 1, profit: 20, day: 3, system: 0)))
        #expect(v[.encountersWon] == .count(1) && v[.encountersFled] == .count(0) && v[.encountersSurrendered] == .count(0))
        #expect(v[.killsPirates] == .count(1) && v[.killsPolice] == .count(2) && v[.killsTraders] == .count(3))
        #expect(v[.bounties] == .credits(50) && v[.finesAndBribes] == .credits(15) && v[.arrests] == .count(1) && v[.peakWorth] == .credits(7_000))
    }

    @Test("STAT-015 agreement with the engine on fuzz games without cheats: kills, days, visited systems, worth",
          arguments: RulesetID.allCases)
    func engineAgreement(_ r: RulesetID) {
        for game in 0..<20 {
            var g = RecordedGame(r, seed: 8_000 + UInt64(game), difficulty: Difficulty(rawValue: game % 5) ?? .normal)
            var rng = Xoshiro256StarStar(seed: UInt64(game) &+ 5)
            for _ in 0..<300 {
                if case .gameOver = g.state.phase { break }
                g.send(InsightsFuzz.pickCommand(g.state, &rng))
                guard case .docked = g.state.phase, !g.state.hasPendingDecision else { continue }
                let s = g.journal.stats
                let state = g.state
                #expect(s.kills == state.commander.kills)
                #expect(s.daysPlayed == state.commander.days - (s.startDay ?? 0))
                #expect(s.visitedCount == state.galaxy.systems.filter(\.visited).count)
                #expect(s.latestWorth == state.worth, "game \(game)")
            }
        }
    }

    @Test("STAT-016 sales at known prices: profit by item, total profit, best sale, including an orbit sale's cost basis")
    func knownPrices() throws {
        var s = freshState(.windows201, seed: 17)
        s.commander.cash = 50_000
        let item = try #require(TradeItemType.allCases.first { s.buyPrices[$0.rawValue] > 0 && s.currentSystem.tradeItems[$0.rawValue] >= 3 })
        let buyPrice = s.buyPrices[item.rawValue], sellPrice = s.sellPrices[item.rawValue]
        var g = RecordedGame(s)
        g.send(.buyCargo(item, quantity: 3))
        g.send(.sellCargo(item, quantity: 2))
        let docked = 2 * sellPrice - (3 * buyPrice) * 2 / 3
        // An orbit sale of the last unit: profit = total − cost-basis difference (LOG §3a).
        let before = g.state
        var after = before
        after.commander.priceCargo[item.rawValue] = 0
        after.commander.ship.cargo[item.rawValue] = 0
        let basis = before.commander.priceCargo[item.rawValue]
        JournalRecorder.record(JournalStep(command: .resolveTradeInOrbit(quantity: 1), before: before,
                                           result: StepResult(events: [.orbitTradeCompleted(direction: .traderBuys, item: item,
                                                                                             quantity: 1, total: basis + 500)]),
                                           after: after), into: &g.journal)
        let stats = g.journal.stats
        #expect(stats.profitByItem[item.rawValue] == docked + 500 && stats.totalTradeProfit == docked + 500)
        #expect(stats.bestSale?.profit == max(docked, 500))
        #expect(stats.sells == 2 && stats.unitsSold == 3)
    }

    @Test("STAT-019 StatsMarkdown renders a two-column table with supplied labels and values")
    func statsMarkdown() {
        var b = EntryBuilder(start: EntryBuilder.start(systems: 3))
        b.add(sale(.ore, 1, total: 30, profit: 20), day: 2)
        let md = StatsMarkdown.render(stats: b.stats, header: ("Statistic", "Value"), labels: { "L|\($0.rawValue)" }, values: { "\($0)" })
        let lines = md.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines[0] == "| Statistic | Value |" && lines[1] == "|---|---:|")
        #expect(lines[2] == "| L\\|daysPlayed | days(2) |")
        #expect(lines.count == StatFigureKind.allCases.count + 3 && md.hasSuffix("|\n"))
    }
}
