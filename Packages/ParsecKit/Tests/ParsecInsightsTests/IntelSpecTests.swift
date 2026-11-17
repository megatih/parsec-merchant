// SPDX-License-Identifier: GPL-2.0-or-later
// INT (docs/specs/INT.md): fairness, the intel book, quotes, estimates, explanations, recommendations, heatmaps and risk.
import Foundation
import Testing
@testable import ParsecEngine
@testable import ParsecInsights

/// The classic Average Price List value, written independently from the spec (Palm Traveler.c `StandardPrice` with
/// `Visited ? SpecialResources : -1`).
private func classicStandardPrice(_ item: TradeItemType, _ s: StarSystem, _ r: Ruleset) -> Int {
    let spec = r.tables.item(item)
    let pol = r.tables.politics(s.politics)
    if (item == .narcotics && !pol.drugsOK) || (item == .firearms && !pol.firearmsOK) || s.techLevel < spec.techUsage { return 0 }
    var p = spec.priceLowTech + s.techLevel.rawValue * spec.priceIncrease
    if pol.wanted == item { p = p * 4 / 3 }
    p = p * (100 - 2 * pol.activityTraders.rawValue) / 100
    p = p * (100 - s.size.rawValue) / 100
    if s.visited {
        if s.specialResource == spec.resourceLowPrice { p = p * 3 / 4 } else if s.specialResource == spec.resourceHighPrice { p = p * 4 / 3 }
    }
    return p
}

/// A state copy that differs only in hidden fields (INT-004).
private func hiddenVariant(_ s: GameState, salt: Int) -> GameState {
    var h = s
    for i in h.galaxy.systems.indices where i != s.commander.currentSystem {
        h.galaxy.systems[i].tradeItems = h.galaxy.systems[i].tradeItems.map { $0 + 7 + salt }
        h.galaxy.systems[i].countDown += 3
        h.galaxy.systems[i].pressure = SystemPressure(rawValue: (i + salt) % 8) ?? .none
        if !h.galaxy.systems[i].visited {
            h.galaxy.systems[i].specialResource = SpecialResource(rawValue: (i + salt) % 13) ?? .nothing
        }
        h.galaxy.systems[i].specialEvent = (i + salt) % 5 == 0 ? .lottery : nil
    }
    h.rng = GameState(config: NewGameConfig(commanderName: "x", ruleset: s.rulesetID, seed: s.seed &+ 99)).rng
    return h
}

private func docked(_ r: RulesetID = .windows201, seed: UInt64 = 8) -> (GameState, IntelSnapshot, IntelBook) {
    let s = freshState(r, seed: seed)
    return (s, IntelSnapshot(s), GameJournal.start(state: s).intel)
}

private func obs(day: Int, sell: Int = 100, buy: Int = 110, stock: Int = 5, pressure: SystemPressure = .none) -> MarketObservation {
    MarketObservation(day: day, buy: Array(repeating: buy, count: 10), sell: Array(repeating: sell, count: 10),
                      stock: Array(repeating: stock, count: 10), pressure: pressure)
}

/// A system other than the current one.
private func other(_ snap: IntelSnapshot, _ k: Int = 1) -> Int { (snap.currentSystem + k) % snap.systems.count }

@Suite("INT trade intelligence")
struct IntelSpecTests {
    // MARK: §1 fairness and inputs

    @Test("INT-001 INT-041 every public INT function takes only the book, the snapshot and explicit parameters")
    func inputs() {
        let (_, snap, book) = docked()
        let t = other(snap)
        _ = TradeIntel.quote(item: .ore, system: t, book: book, snapshot: snap)
        _ = TradeIntel.profitPerBay(item: .ore, target: t, book: book, snapshot: snap)
        _ = TradeIntel.bestBuys(for: t, book: book, snapshot: snap)
        _ = TradeIntel.holdValue(at: t, book: book, snapshot: snap)
        _ = TradeIntel.bestDestinations(book: book, snapshot: snap)
        _ = TradeIntel.sellAdvice(item: .ore, book: book, snapshot: snap)
        _ = TradeIntel.sells(item: .ore, system: t, book: book, snapshot: snap)
        _ = TradeIntel.estimate(item: .ore, system: t, snapshot: snap)
        _ = HeatmapModel.values(mode: .holdProfit, intel: book, snapshot: snap)
        #expect(snap.systems.count == book.systems.count)
    }

    @Test("INT-002 the snapshot copies only public facts: no unvisited resource or shipyard, current market only")
    func snapshotFacts() {
        let (s, snap, _) = docked(.modern)
        #expect(snap.day == s.commander.days && snap.currentSystem == s.commander.currentSystem && snap.isDocked)
        for (i, f) in snap.systems.enumerated() {
            let sys = s.galaxy.systems[i]
            #expect(f.x == sys.x && f.y == sys.y && f.size == sys.size && f.techLevel == sys.techLevel && f.politics == sys.politics)
            #expect(f.visited == sys.visited && f.knownResource == sys.knownResource)
            if !sys.visited { #expect(f.knownResource == .nothing && f.shipyard == nil) }
        }
        #expect(snap.buyPrices == s.buyPrices && snap.sellPrices == s.sellPrices && snap.stock == s.currentSystem.tradeItems)
        #expect(snap.destinations == s.destinations && snap.maxBuy == s.marketRows.map(\.maxBuy) && snap.policeRecordScore == 0)
        var transit = s
        transit.phase = .inTransit(TransitState(destination: 1, clicksRemaining: 3, viaWormhole: false))
        #expect(!IntelSnapshot(transit).isDocked)
    }

    @Test("INT-003 snapshot and book are Sendable values usable off the main actor")
    func sendable() async {
        let (_, snap, book) = docked()
        let t = other(snap)
        let off = await Task.detached { TradeIntel.bestBuys(for: t, book: book, snapshot: snap) }.value
        #expect(off == TradeIntel.bestBuys(for: t, book: book, snapshot: snap))
    }

    @Test("INT-004 MAP-097 MAP-094 fairness: hidden fields never change the snapshot, quotes, heatmaps or risk routes (50 seeds)",
          arguments: RulesetID.allCases)
    func fairness(_ r: RulesetID) {
        for seed in 0..<50 {
            var g = RecordedGame(r, seed: 300 + UInt64(seed))
            g.fuzz(40, seed: UInt64(seed))
            let s = g.state
            let h = hiddenVariant(s, salt: seed)
            let a = IntelSnapshot(s), b = IntelSnapshot(h)
            #expect(a == b)
            #expect(RouteSnapshot(s) == RouteSnapshot(h))
            let book = g.journal.intel
            for system in stride(from: 0, to: a.systems.count, by: 9) {
                for item in TradeItemType.allCases {
                    #expect(TradeIntel.quote(item: item, system: system, book: book, snapshot: a)
                            == TradeIntel.quote(item: item, system: system, book: book, snapshot: b))
                }
                #expect(TradeIntel.bestBuys(for: system, book: book, snapshot: a) == TradeIntel.bestBuys(for: system, book: book, snapshot: b))
            }
            for mode in [HeatmapMode.price(.robots), .holdProfit, .police, .pirates, .techLevel, .lastVisited] {
                #expect(HeatmapModel.values(mode: mode, intel: book, snapshot: a) == HeatmapModel.values(mode: mode, intel: book, snapshot: b))
            }
            let to = other(a, 17)
            #expect(RoutePlanner.plan(from: a.currentSystem, to: to, in: RouteSnapshot(s), objective: .lowestRisk)
                    == RoutePlanner.plan(from: a.currentSystem, to: to, in: RouteSnapshot(h), objective: .lowestRisk))
        }
    }

    @Test("INT-005 public facts give estimates for never-visited systems (size, tech level, government)")
    func publicFacts() {
        let (s, snap, book) = docked()
        guard let u = s.galaxy.systems.indices.first(where: {
            !s.galaxy.systems[$0].visited && s.galaxy.systems[$0].techLevel >= .industrial
        }) else { return }
        let q = TradeIntel.quote(item: .water, system: u, book: book, snapshot: snap)
        #expect(q.source == .estimate && q.sell == classicStandardPrice(.water, s.galaxy.systems[u], s.ruleset))
    }

    @Test("INT-006 a read newspaper's external-pressure headline becomes a news hint; unread papers contribute nothing")
    func newsHints() {
        var book = IntelBook(systemCount: 5)
        book.read([.externalPressure(template: 1, pressure: .war, system: 3), .internalPressure(.plague)], day: 9)
        #expect(book.systems[3].pressureHint == PressureHint(pressure: .war, day: 9, source: .news))
        #expect(book.systems.enumerated().filter { $0.element.pressureHint != nil }.map(\.offset) == [3])
        var g = RecordedGame(.windows201, seed: 21)
        let result = g.send(.readNewspaper)
        if case let .newspaper(paper)? = result.decision {
            for case let .externalPressure(_, pressure, system) in paper.headlines {
                #expect(g.journal.intel.systems[system].pressureHint?.pressure == pressure)
            }
        }
    }

    // MARK: §2 the intel book

    @Test("INT-007 one SystemIntel per system; observations hold one value per item; arrays and integers only")
    func bookShape() throws {
        let (s, _, book) = docked()
        #expect(book.systems.count == s.galaxy.systems.count)
        let latest = try #require(book.systems[s.commander.currentSystem].latest)
        #expect(latest.buy.count == 10 && latest.sell.count == 10 && latest.stock.count == 10)
        let text = try #require(String(data: JSONEncoder().encode(book), encoding: .utf8))
        #expect(text.hasPrefix("{\"systems\":[") && !text.contains("."))
        #expect(book.intel(-1) == SystemIntel() && book.intel(10_000) == SystemIntel())
    }

    @Test("INT-008 docked observation: same day replaces, identical is not repeated, nothing outside docking")
    func observationRule() {
        var book = IntelBook(systemCount: 3)
        book.observe(obs(day: 1), at: 0)
        book.observe(obs(day: 1, sell: 90), at: 0)
        #expect(book.systems[0].history == [obs(day: 1, sell: 90)])
        book.observe(obs(day: 2, sell: 90), at: 0)
        #expect(book.systems[0].history.count == 2)
        var same = obs(day: 2, sell: 90)
        same.day = 2
        book.observe(same, at: 0)
        #expect(book.systems[0].history.count == 2)
        book.observe(obs(day: 5), at: 7)
        #expect(book.systems.allSatisfy { $0.history.count <= 2 })
        let s = freshState()
        for phase: GamePhase in [.inTransit(TransitState(destination: 1, clicksRemaining: 1, viaWormhole: false)), .gameOver(.retired)] {
            var t = s
            t.phase = phase
            var b = IntelBook(systemCount: s.galaxy.systems.count)
            b.observe(t)
            #expect(b.systems.allSatisfy { $0.history.isEmpty })
        }
    }

    @Test("INT-009 history keeps the newest 24 observations, oldest first")
    func historyLimit() {
        var book = IntelBook(systemCount: 1)
        for day in 1...30 { book.observe(obs(day: day, sell: day), at: 0) }
        #expect(book.systems[0].history.count == IntelPolicy.historyLimit)
        #expect(book.systems[0].history.map(\.day) == Array(7...30))
    }

    @Test("INT-010 visits set the last visit day and count; a bootstrapped journal marks visited systems date-unknown")
    func visits() {
        var book = IntelBook(systemCount: 3)
        book.visit(1, day: 4)
        book.visit(1, day: 9)
        book.visit(8, day: 1)
        #expect(book.systems[1].lastVisitDay == 9 && book.systems[1].visitCount == 2 && !book.systems[1].visitDateUnknown)
        var g = RecordedGame(.modern, seed: 13)
        g.fuzz(200, seed: 13)
        let s = g.state
        let j = GameJournal.bootstrap(from: s)
        for (i, sys) in s.galaxy.systems.enumerated() {
            let intel = j.intel.systems[i]
            if i == s.commander.currentSystem {
                #expect(intel.lastVisitDay == s.commander.days && intel.visitCount == 1)
            } else if sys.visited {
                #expect(intel.visitDateUnknown && intel.visitCount == 1)
            } else {
                #expect(intel.visitCount == 0 && intel.lastVisitDay == nil)
            }
        }
        // Recorded arrivals set the visit day.
        for entry in g.journal.entries {
            if case let .arrived(a) = entry.kind { #expect(g.journal.intel.systems[a.system].visitCount >= 1) }
        }
    }

    @Test("INT-011 the newest hint wins; a later observation replaces a news hint")
    func hintPrecedence() {
        var book = IntelBook(systemCount: 2)
        book.hear(PressureHint(pressure: .war, day: 5, source: .news), about: 1)
        book.hear(PressureHint(pressure: .plague, day: 3, source: .news), about: 1)
        #expect(book.systems[1].pressureHint?.pressure == .war)
        book.observe(obs(day: 6, pressure: .drought), at: 1)
        #expect(book.systems[1].pressureHint == PressureHint(pressure: .drought, day: 6, source: .observed))
        book.observe(obs(day: 7), at: 1)
        #expect(book.systems[1].pressureHint == nil)
        book.hear(PressureHint(pressure: .cold, day: 1, source: .news), about: 9)
    }

    // MARK: §3 quotes

    @Test("INT-012 quote source order: live when docked here, then the newest observation, then the estimate; 0 is nil")
    func quoteOrder() {
        let (s, snap0, book0) = docked()
        var snap = snap0, book = book0
        let here = snap.currentSystem, t = other(snap)
        let live = TradeIntel.quote(item: .water, system: here, book: book, snapshot: snap)
        #expect(live.source == .live && live.age == 0 && live.sell == (s.sellPrices[0] > 0 ? s.sellPrices[0] : nil))
        #expect(TradeIntel.quote(item: .water, system: t, book: book, snapshot: snap).source == .estimate)
        book.observe(obs(day: snap.day - 3, sell: 0), at: t)
        let o = TradeIntel.quote(item: .water, system: t, book: book, snapshot: snap)
        #expect(o.source == .observed(day: snap.day - 3) && o.age == 3 && o.sell == nil && o.buy == 110 && o.stock == 5)
        snap.isDocked = false
        #expect(TradeIntel.quote(item: .water, system: here, book: book, snapshot: snap).source == .observed(day: s.commander.days))
    }

    @Test("INT-013 the estimate equals the Average Price List value, visited and unvisited, in every ruleset", arguments: RulesetID.allCases)
    func estimates(_ r: RulesetID) {
        var g = RecordedGame(r, seed: 61)
        g.fuzz(120, seed: 61)
        let s = g.state
        let snap = IntelSnapshot(s)
        for (i, sys) in s.galaxy.systems.enumerated() {
            for item in TradeItemType.allCases {
                #expect(TradeIntel.estimate(item: item, system: i, snapshot: snap) == classicStandardPrice(item, sys, s.ruleset))
            }
        }
    }

    @Test("INT-014 staleness: live, fresh at ages 0 and 7, old at 8, estimate")
    func staleness() {
        var (_, snap, book) = docked()
        let t = other(snap)
        snap.day = 20
        for (age, expected) in [(0, Staleness.fresh), (7, .fresh), (8, .old)] {
            var b = book
            b.observe(obs(day: 20 - age), at: t)
            #expect(TradeIntel.quote(item: .ore, system: t, book: b, snapshot: snap).staleness == expected)
        }
        #expect(TradeIntel.quote(item: .ore, system: other(snap, 2), book: book, snapshot: snap).staleness == .estimate)
        book.observe(obs(day: 1), at: snap.currentSystem)
        #expect(TradeIntel.quote(item: .ore, system: snap.currentSystem, book: book, snapshot: snap).staleness == .live)
    }

    @Test("INT-015 profit per bay is target sell minus here buy, when bought here and the target has a sell price")
    func profitPerBay() {
        var (_, snap, book) = docked()
        let t = other(snap)
        snap.buyPrices[0] = 40
        book.observe(obs(day: snap.day, sell: 100), at: t)
        #expect(TradeIntel.profitPerBay(item: .water, target: t, book: book, snapshot: snap) == 60)
        snap.buyPrices[0] = 0
        #expect(TradeIntel.profitPerBay(item: .water, target: t, book: book, snapshot: snap) == nil)
        snap.buyPrices[0] = 40
        book.observe(obs(day: snap.day + 1, sell: 0), at: t)
        #expect(TradeIntel.profitPerBay(item: .water, target: t, book: book, snapshot: snap) == nil)
    }

    @Test("INT-016 a known pressure hint matching the item's price hike is attached to estimates and older observations")
    func pressureHints() {
        let (_, snap, base) = docked()
        let t = other(snap)
        let hike = snap.ruleset.tables.item(.water).pressurePriceHike  // drought
        var book = base
        book.hear(PressureHint(pressure: hike, day: 10, source: .news), about: t)
        let est = TradeIntel.quote(item: .water, system: t, book: book, snapshot: snap)
        #expect(est.pressureHint?.day == 10 && est.sell == TradeIntel.quote(item: .water, system: t, book: base, snapshot: snap).sell)
        var older = base
        older.observe(obs(day: 5), at: t)
        older.hear(PressureHint(pressure: hike, day: 10, source: .news), about: t)
        #expect(TradeIntel.quote(item: .water, system: t, book: older, snapshot: snap).pressureHint != nil)
        older.observe(obs(day: 12), at: t)
        #expect(TradeIntel.quote(item: .water, system: t, book: older, snapshot: snap).pressureHint == nil)
    }

    // MARK: §4 explanation

    @Test("INT-017 the explanation lists every factor in order with deltas; sell and buy match the breakdown")
    func explanation() {
        let b = PriceBreakdown(item: .robots, base: 5_000, afterWanted: 6_666, afterTraderActivity: 6_266, afterSize: 6_015,
                               afterResource: 4_511, afterPressure: 6_766, afterCriminal: 6_089, fluctuation: -40, buyMarkup: 320)
        let e = PriceExplanation.make(b)
        #expect(e.steps.map(\.factor) == PriceFactor.allCases && e.item == .robots)
        #expect(e.steps.map(\.delta) == [5_000, 1_666, -400, -251, -1_504, 2_255, -677, -40, 320])
        #expect(e.sellPrice == 6_049 && e.buyPrice == 6_369 && e.steps.allSatisfy { !$0.isNeutral })
        let flat = PriceExplanation.make(PriceBreakdown(item: .ore, base: 100, afterWanted: 100, afterTraderActivity: 100, afterSize: 100,
                                                        afterResource: 100, afterPressure: 100, afterCriminal: 100, fluctuation: 0,
                                                        buyMarkup: 5))
        #expect(flat.steps.filter(\.isNeutral).map(\.factor) == [.wanted, .traderActivity, .size, .resource, .pressure, .criminal, .fluctuation])
    }

    @Test("INT-018 for the docked system the explanation reproduces the visible prices (fluctuation = visible difference)")
    func explanationFairness() {
        for r in RulesetID.allCases {
            let s = freshState(r, seed: 33)
            for item in TradeItemType.allCases where s.sellPrices[item.rawValue] > 0 {
                let e = PriceExplanation.make(s.priceBreakdown(item))
                #expect(e.sellPrice == s.sellPrices[item.rawValue] && e.buyPrice == s.buyPrices[item.rawValue])
            }
        }
    }

    // MARK: §5 recommendations

    @Test("INT-019 best buys: bought here with stock and profit, by profit then item; units = maxBuy; empty for here")
    func bestBuys() {
        var (_, snap, book) = docked()
        let t = other(snap)
        snap.buyPrices = [10, 10, 10, 0, 10, 10, 10, 10, 10, 10]
        snap.stock = [5, 5, 0, 5, 5, 5, 5, 5, 5, 5]
        snap.maxBuy = Array(repeating: 4, count: 10)
        var o = obs(day: snap.day)
        o.sell = [30, 50, 99, 99, 50, 5, 10, 20, 0, 40]
        book.observe(o, at: t)
        let recs = TradeIntel.bestBuys(for: t, book: book, snapshot: snap)
        #expect(recs.map(\.item) == [.furs, .games, .robots])
        #expect(recs[0] == TradeRecommendation(item: .furs, profitPerBay: 40, units: 4, projectedProfit: 160,
                                               quoteSource: .observed(day: snap.day), staleness: .fresh))
        #expect(TradeIntel.bestBuys(for: t, book: book, snapshot: snap, limit: 10).count == 5)
        #expect(TradeIntel.bestBuys(for: snap.currentSystem, book: book, snapshot: snap).isEmpty)
    }

    @Test("INT-020 hold value: revenue and cost basis of sellable items, unsellable listed, estimates flagged")
    func holdValue() {
        var (_, snap, book) = docked()
        let t = other(snap)
        snap.cargo = [2, 0, 0, 0, 0, 0, 0, 0, 1, 0]
        snap.priceCargo = [60, 0, 0, 0, 0, 0, 0, 0, 500, 0]
        var o = obs(day: snap.day, sell: 50)
        o.sell[8] = 0
        book.observe(o, at: t)
        let v = TradeIntel.holdValue(at: t, book: book, snapshot: snap)
        #expect(v == HoldValue(revenue: 100, costBasis: 60, profit: 40, unsellable: [.narcotics], usesEstimates: false))
        let est = TradeIntel.holdValue(at: other(snap, 2), book: book, snapshot: snap)
        #expect(est.usesEstimates || est.revenue == 0)
    }

    @Test("INT-021 best destinations: in range, positive hold profit, by profit, distance, index; empty hold gives none")
    func bestDestinations() {
        var (_, snap, book) = docked()
        snap.cargo = Array(repeating: 0, count: 10)
        #expect(TradeIntel.bestDestinations(book: book, snapshot: snap).isEmpty)
        snap.cargo[0] = 1
        snap.priceCargo[0] = 10
        let dests = Array(snap.destinations.prefix(3))
        guard dests.count == 3 else { return }
        for (k, d) in dests.enumerated() { book.observe(obs(day: snap.day, sell: k == 2 ? 5 : 40), at: d) }
        let recs = TradeIntel.bestDestinations(book: book, snapshot: snap, limit: 10)
        let observed = recs.filter { dests.contains($0.system) }
        #expect(observed.map(\.system).sorted() == Array(dests.prefix(2)).sorted())
        #expect(recs == recs.sorted {
            $0.profit != $1.profit ? $0.profit > $1.profit : ($0.distance != $1.distance ? $0.distance < $1.distance : $0.system < $1.system)
        })
    }

    @Test("INT-022 sell advice: profit here per unit and the best known or estimated system in range; nil when not held")
    func sellAdvice() throws {
        var (_, snap, book) = docked()
        #expect(TradeIntel.sellAdvice(item: .ore, book: book, snapshot: snap) == nil)
        snap.cargo[3] = 4
        snap.priceCargo[3] = 200
        snap.sellPrices[3] = 70
        let dests = Array(snap.destinations.prefix(2))
        guard dests.count == 2 else { return }
        book.observe(obs(day: snap.day, sell: 1_000), at: dests[1])
        let a = try #require(TradeIntel.sellAdvice(item: .ore, book: book, snapshot: snap))
        #expect(a.herePerUnit == 20 && a.bestSystem == dests[1] && a.bestSell == 1_000 && a.bestPerUnit == 950 && a.bestAge == 0)
        snap.sellPrices[3] = 0
        #expect(TradeIntel.sellAdvice(item: .ore, book: book, snapshot: snap)?.herePerUnit == nil)
    }

    @Test("INT-023 recommendations ignore another system's live prices and stock until the player docks there")
    func recommendationsFair() {
        var g = RecordedGame(.modern, seed: 71)
        g.fuzz(60, seed: 71)
        var s = g.state
        let target = s.destinations.first ?? (s.commander.currentSystem + 1) % s.galaxy.systems.count
        let before = (TradeIntel.bestBuys(for: target, book: g.journal.intel, snapshot: IntelSnapshot(s)),
                      TradeIntel.bestDestinations(book: g.journal.intel, snapshot: IntelSnapshot(s)))
        s.galaxy.systems[target].tradeItems = s.galaxy.systems[target].tradeItems.map { $0 * 3 + 11 }
        let after = (TradeIntel.bestBuys(for: target, book: g.journal.intel, snapshot: IntelSnapshot(s)),
                     TradeIntel.bestDestinations(book: g.journal.intel, snapshot: IntelSnapshot(s)))
        #expect(before.0 == after.0 && before.1 == after.1)
    }

    // MARK: §6 heatmaps, risk, search

    @Test("INT-024 INT-025 MAP-097 heatmap modes: one value per system, notes, ages and the scale")
    func heatmaps() {
        let (s, snap0, book0) = docked()
        var snap = snap0, book = book0
        let t = other(snap)
        book.observe(obs(day: snap.day - 2, sell: 77), at: t)
        let price = HeatmapModel.values(mode: .price(.water), intel: book, snapshot: snap)
        #expect(price.values.count == snap.systems.count)
        #expect(price.values[t] == HeatmapValue(value: 77, age: 2))
        #expect(price.values[snap.currentSystem].age == 0)
        let u = other(snap, 3)
        if price.values[u].value != nil { #expect(price.values[u].isEstimate) }
        let present = price.values.compactMap(\.value)
        #expect(price.scale == HeatmapScale(min: present.min() ?? 0, max: present.max() ?? 0))
        #expect(HeatmapModel.values(mode: .none, intel: book, snapshot: snap).values.allSatisfy { $0.value == nil })
        #expect(HeatmapModel.values(mode: .none, intel: book, snapshot: snap).scale == HeatmapScale(min: 0, max: 0))
        let tech = HeatmapModel.values(mode: .techLevel, intel: book, snapshot: snap)
        #expect(tech.values.map(\.value) == s.galaxy.systems.map { $0.techLevel.rawValue })
        let police = HeatmapModel.values(mode: .police, intel: book, snapshot: snap)
        let pirates = HeatmapModel.values(mode: .pirates, intel: book, snapshot: snap)
        for (i, sys) in s.galaxy.systems.enumerated() {
            let pol = s.ruleset.tables.politics(sys.politics)
            #expect(police.values[i].value == (pol.activityPolice == .na ? 0 : pol.activityPolice.rawValue))
            #expect(pirates.values[i].value == (pol.activityPirates == .na ? 0 : pol.activityPirates.rawValue))
        }
        // Hold profit: nil for an empty hold and the current system.
        snap.cargo = Array(repeating: 0, count: 10)
        #expect(HeatmapModel.values(mode: .holdProfit, intel: book, snapshot: snap).values.allSatisfy { $0.value == nil })
        snap.cargo[0] = 1
        snap.priceCargo[0] = 10
        let hold = HeatmapModel.values(mode: .holdProfit, intel: book, snapshot: snap)
        #expect(hold.values[snap.currentSystem].value == nil && hold.values[t].value == 67)
        // Last visited: days since, date unknown, never.
        book.systems[u] = SystemIntel(lastVisitDay: nil, visitCount: 1)
        snap.day += 4
        let last = HeatmapModel.values(mode: .lastVisited, intel: book, snapshot: snap)
        #expect(last.values[snap.currentSystem] == HeatmapValue(value: 4) && last.values[u] == HeatmapValue(value: nil, note: .dateUnknown))
        #expect(last.values[t] == HeatmapValue(value: nil))
    }

    @Test("INT-026 MAP-094 hop risk: pirate activity, plus police activity for criminals; .na counts 0")
    func hopRisk() {
        var s = freshState(.windows201, seed: 9)
        let clean = RouteSnapshot(s)
        s.commander.policeRecordScore = -6
        let criminal = RouteSnapshot(s)
        for (i, sys) in s.galaxy.systems.enumerated() {
            let pol = s.ruleset.tables.politics(sys.politics)
            let pirates = pol.activityPirates == .na ? 0 : pol.activityPirates.rawValue
            let police = pol.activityPolice == .na ? 0 : pol.activityPolice.rawValue
            #expect(clean.hopRisk[i] == pirates && criminal.hopRisk[i] == pirates + police)
        }
        #expect(RouteSnapshot.activityWeight(.na) == 0 && clean.risk(-1) == 0)
    }

    @Test("INT-027 MAP-069 lowestRisk: total risk ≤ fewestJumps and cheapest; hops are edges (100 seeds)", arguments: RulesetID.allCases)
    func lowestRisk(_ r: RulesetID) throws {
        for seed in 0..<100 {
            var s = freshState(r, seed: 5_000 + UInt64(seed))
            if seed % 3 == 0 { s.commander.policeRecordScore = -20 }
            let snap = RouteSnapshot(s)
            let from = s.commander.currentSystem
            let to = (from + 1 + seed * 7) % s.galaxy.systems.count
            guard let risky = RoutePlanner.plan(from: from, to: to, in: snap, objective: .lowestRisk) else { continue }
            #expect(risky.objective == .lowestRisk)
            for other in [RouteObjective.fewestJumps, .cheapest] {
                let o = try #require(RoutePlanner.plan(from: from, to: to, in: snap, objective: other))
                #expect(risky.totalRisk <= o.totalRisk)
            }
            for hop in risky.hops {
                #expect(RoutePlanner.edges(from: hop.from, in: snap).contains { $0.to == hop.to && $0.viaWormhole == hop.viaWormhole })
                #expect(hop.risk == snap.risk(hop.to))
            }
        }
        // Tie-breaking: two equal-risk routes keep the lower index (MAP-058).
        let tie = RouteSnapshot(points: [RoutePoint(x: 0, y: 0), RoutePoint(x: 5, y: 5), RoutePoint(x: 5, y: -5), RoutePoint(x: 10, y: 0)],
                                wormholes: [], distanceRule: .floor, fuelCapacity: 8, currentFuel: 8, fuelCostPerParsec: 1,
                                wormholeTax: 0, perWarpCosts: 0, hopRisk: [0, 2, 2, 1])
        #expect(RoutePlanner.plan(from: 0, to: 3, in: tie, objective: .lowestRisk)?.stops == [0, 1, 3])
        let safer = RouteSnapshot(points: tie.points, wormholes: [], distanceRule: .floor, fuelCapacity: 8, currentFuel: 8,
                                  fuelCostPerParsec: 1, wormholeTax: 0, perWarpCosts: 0, hopRisk: [0, 5, 2, 1])
        #expect(RoutePlanner.plan(from: 0, to: 3, in: safer, objective: .lowestRisk)?.stops == [0, 2, 3])
    }

    @Test("INT-028 sells filter: the newest observation shows buy and stock, else the public itemTraded rule (estimate)")
    func sellsFilter() {
        let (s, snap, book0) = docked()
        var book = book0
        let t = other(snap)
        book.observe(obs(day: 1, buy: 10, stock: 0), at: t)
        #expect(TradeIntel.sells(item: .ore, system: t, book: book, snapshot: snap) == nil)
        book.observe(obs(day: 2, buy: 10, stock: 3), at: t)
        #expect(TradeIntel.sells(item: .ore, system: t, book: book, snapshot: snap) == .observed)
        let u = other(snap, 5)
        let traded = Pricing.itemTraded(s.ruleset.tables.item(.robots), in: s.galaxy.systems[u], ruleset: s.ruleset)
        #expect(TradeIntel.sells(item: .robots, system: u, book: book, snapshot: snap) == (traded ? .estimate : nil))
        let here = s.buyPrices[0] > 0 && s.currentSystem.tradeItems[0] > 0
        #expect(TradeIntel.sells(item: .water, system: snap.currentSystem, book: book, snapshot: snap) == (here ? .observed : nil))
    }
}
