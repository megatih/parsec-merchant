// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import ParsecInsights
import Testing
@testable import ParsecMerchant

/// INT §7–§9 (Market, galaxy chart, system intel, settings and readout) and MAP-047/096/097 in the app.
@MainActor
struct IntelAppTests {
    /// A docked Quick Start game with one item bought, so the hold is non-empty.
    static func tradingSession(seed: UInt64 = 11) throws -> GameSession {
        let s = try TestSessions.playing(seed: seed)
        let state = try #require(s.state)
        let item = try #require(state.marketRows.first { $0.maxBuy > 0 }?.item)
        s.send(.buyCargo(item, quantity: 1))
        s.send(.selectNextTarget(forward: true))
        return s
    }

    static func inputs(_ s: GameSession) throws -> MarketIntelModel.Inputs {
        MarketIntelModel.Inputs.make(state: try #require(s.state), journal: s.journal)
    }

    @Test("INT-029 MarketIntelModel holds per row the quote, profit per bay, history, advice and explanation from INT only")
    func marketModel() async throws {
        let s = try Self.tradingSession()
        let state = try #require(s.state)
        let inputs = try Self.inputs(s)
        let m = MarketIntelModel.make(book: inputs.book, snapshot: inputs.snapshot, target: inputs.target, breakdowns: inputs.breakdowns)
        #expect(m.rows.map(\.item) == TradeItemType.allCases && m.target == state.warpSystem)
        for row in m.rows {
            #expect(row.targetQuote == TradeIntel.quote(item: row.item, system: m.target, book: inputs.book, snapshot: inputs.snapshot))
            #expect(row.profitPerBay == TradeIntel.profitPerBay(item: row.item, target: m.target, book: inputs.book,
                                                                snapshot: inputs.snapshot))
            #expect(row.explanation == PriceExplanation.make(state.priceBreakdown(row.item)))
        }
        #expect(m.bestBuys == TradeIntel.bestBuys(for: m.target, book: inputs.book, snapshot: inputs.snapshot))
        #expect(m.holdAtTarget == TradeIntel.holdValue(at: m.target, book: inputs.book, snapshot: inputs.snapshot))
        // Built off the main actor, it is the same value.
        #expect(await MarketIntelModel.build(inputs) == m)
        // The current system as target has no target quotes or buys.
        let here = MarketIntelModel.make(book: inputs.book, snapshot: inputs.snapshot, target: inputs.snapshot.currentSystem)
        #expect(here.targetIsHere && here.rows.allSatisfy { $0.targetQuote == nil } && here.bestBuys.isEmpty && here.holdAtTarget == nil)
    }

    @Test("INT-030 the Target cell: sell quote, age or est., dimming for old data, Δ with sign and the source help tag")
    func targetCellTexts() {
        let base = PriceQuote(item: .robots, system: 3, sell: 4000, buy: nil, stock: nil, source: .estimate, age: nil,
                              staleness: .estimate, pressureHint: nil)
        #expect(IntelText.age(base) == "est.")
        var observed = base
        observed.source = .observed(day: 5)
        observed.age = 3
        observed.staleness = .fresh
        #expect(IntelText.age(observed) == "3 d ago" && IntelText.help(observed) == "Seen on day 5.")
        observed.age = 0
        #expect(IntelText.age(observed) == "today")
        observed.staleness = .old
        observed.pressureHint = PressureHint(pressure: .war, day: 9, source: .news)
        #expect(IntelText.help(observed).contains("News on day 9: war"))
        #expect(IntelText.signed(412) == "+412" && IntelText.signed(-12) == "−12" && IntelText.arrow(5) == "▲" && IntelText.arrow(-5) == "▼")
        #expect(TradeItemType.allCases.map(BridgeID.Cargo.target) == TradeItemType.allCases.map { "bridge.cargo.target.\($0)" })
    }

    @Test("INT-031 the History sparkline series and its accessibility value; fewer than 2 observations say No history")
    func history() throws {
        #expect(IntelText.historyValue([10]) == "No history")
        #expect(IntelText.historyValue([10, 12, 9]) == "Sell price over 3 visits: from 10 to 9 credits")
        let s = try TestSessions.playing()
        let inputs = try Self.inputs(s)
        let m = MarketIntelModel.make(book: inputs.book, snapshot: inputs.snapshot, target: inputs.target)
        // The start observation is the only one so far: one point per item that is bought here.
        let st = try #require(s.state)
        for row in m.rows { #expect(row.history.count == (st.sellPrices[row.item.rawValue] > 0 ? 1 : 0)) }
        #expect(AXID.MarketIntel.history(.water) == "market.row.water.history")
    }

    @Test("INT-032 Why this price?: steps from the breakdown, neutral steps collapsed behind Show all")
    func whyPanel() throws {
        let s = try TestSessions.playing()
        let st = try #require(s.state)
        let item = try #require(TradeItemType.allCases.first { st.sellPrices[$0.rawValue] > 0 })
        let e = PriceExplanation.make(st.priceBreakdown(item))
        let collapsed = PriceExplanationRows.visible(e, showAll: false)
        #expect(collapsed.first?.factor == .base && collapsed.allSatisfy { $0.factor == .base || !$0.isNeutral })
        #expect(PriceExplanationRows.visible(e, showAll: true) == e.steps)
        #expect(PriceFactor.allCases.allSatisfy { !IntelText.factor($0).isEmpty })
        #expect(IntelText.factor(.fluctuation) == "Market fluctuation")
        #expect(AXID.MarketIntel.why == "market.why" && AXID.MarketIntel.whyShowAll == "market.why.showAll")
    }

    @Test("INT-033 the recommendations strip texts, est. labels, destination enablement and identifiers")
    func strip() throws {
        let r = TradeRecommendation(item: .robots, profitPerBay: 412, units: 12, projectedProfit: 4944, quoteSource: .estimate,
                                    staleness: .estimate)
        #expect(IntelText.buyRecommendation(r, target: "Rhymus") == "Best buy here for Rhymus: Robots +412/bay (12 bays, +4,944) est.")
        let d = DestinationRecommendation(system: 3, profit: 1200, distance: 7, usesEstimates: false)
        #expect(IntelText.destinationRecommendation(d, system: "Rhymus") == "Best destinations for your hold: Rhymus +1,200")
        let s = try Self.tradingSession()
        let st = try #require(s.state)
        let dest = try #require(st.destinations.first)
        #expect(RecommendationRules.canSelectTarget(dest, state: st, inputLocked: false))
        #expect(!RecommendationRules.canSelectTarget(dest, state: st, inputLocked: true))
        #expect(BridgeID.Cargo.good(.water) == "bridge.cargo.good.water", "the best buy is the star in the Good cell")

    }

    @Test("INT-034 the footer projection: Hold at <target>, est. and unsellable items")
    func footer() {
        let h = HoldValue(revenue: 500, costBasis: 300, profit: 200, unsellable: [.firearms, .narcotics], usesEstimates: true)
        #expect(IntelText.holdProjection(h, target: "Rhymus") == "Hold at Rhymus: +200 est. · 2 items not bought there")
        #expect(BridgeID.Cargo.hold == "bridge.cargo.summary.hold")
    }

    @Test("INT-035 the Held cell's sell advice")
    func sellAdvice() {
        let a = SellAdvice(item: .robots, herePerUnit: 12, bestSystem: 3, bestSell: 90, bestPerUnit: 40, bestSource: .observed(day: 2),
                           bestAge: 3)
        #expect(IntelText.sellAdvice(a, systemName: { _ in "Rhymus" }, today: 5) == "Sell here: +12/unit · Best known: Rhymus +40/unit (3 d ago)")
    }

    @Test("INT-036 MAP-047 the hover card's intel rows: up to 3 quotes with age or estimate, then the hold's best profit")
    func hoverRows() throws {
        let s = try Self.tradingSession()
        let inputs = try #require(s.intelInputs())
        let target = try #require(s.state?.destinations.first)
        let rows = HoverIntel.rows(system: target, book: inputs.book, snapshot: inputs.snapshot) { "\($0)" }
        #expect(rows.count >= 2 && rows.count <= 4)
        #expect(rows.last?.hasPrefix("Best profit for your hold: ") == true)
        #expect(rows.dropLast().allSatisfy { $0.contains("(estimate)") })  // never visited: estimates only
        let here = HoverIntel.rows(system: inputs.snapshot.currentSystem, book: inputs.book, snapshot: inputs.snapshot) { "\($0)" }
        #expect(!here.contains { $0.hasPrefix("Best profit") })
    }

    @Test("INT-037 UI-PG-060 the System Intel model behind the Selected System panel (quotes, resource, hint, last visit)")
    func systemIntel() throws {
        let s = try TestSessions.playing()
        let inputs = try #require(s.intelInputs())
        let cur = inputs.snapshot.currentSystem
        let here = SystemIntelModel.make(system: cur, book: inputs.book, snapshot: inputs.snapshot)
        #expect(here.rows.count == TradeItemType.allCases.count && here.rows.allSatisfy { $0.quote.source == .live })
        if case .day = here.lastVisit {} else { Issue.record("the start system has a visit day") }
        let unvisited = try #require(inputs.snapshot.systems.indices.first { !inputs.snapshot.systems[$0].visited })
        let far = SystemIntelModel.make(system: unvisited, book: inputs.book, snapshot: inputs.snapshot)
        #expect(far.lastVisit == .never && far.knownResource == nil)
        // UI-PG-060: the Selected System panel of the Galactic Chart shows these rows (the Find Prices sheet is gone).
        #expect(AXID.SystemIntel.row(.ore) == "systemIntel.row.ore" && AXID.all.contains(AXID.SystemIntel.row(.water)))
    }

    @Test("INT-038 Show trade recommendations defaults on and affects only the strip")
    func recommendationsSetting() throws {
        let defaults = try #require(UserDefaults(suiteName: "pm-intel-\(UUID().uuidString)"))
        #expect(AppSettings(defaults: defaults).showRecommendations)
        defaults.set(false, forKey: AppSettingsKey.showRecommendations)
        #expect(!AppSettings(defaults: defaults).showRecommendations)
        #expect(AXID.IntelSettings.recommendations == "settings.intel.recommendations")
    }

    @Test("INT-039 the tactical readout gains only Met before: N times, won M, from the journal's encounter records")
    func metBefore() throws {
        #expect(TacticalText.metBefore(nil) == nil && TacticalText.metBefore(MetBefore(met: 0, won: 0)) == nil)
        #expect(TacticalText.metBefore(MetBefore(met: 3, won: 1)) == "Met before: 3 times, won 1")
        let s = try TestSessions.playing()
        var j = try #require(s.journal)
        let kills = try #require(s.state?.commander.kills)
        for (i, outcome) in [EncounterOutcomeKind.destroyed(.gnat), .escaped].enumerated() {
            let r = EncounterRecord(type: .pirateAttack, opponent: .gnat, rounds: 2, outcome: outcome, bounty: 0, minHullPercent: 80,
                                    killsAfter: kills)
            j.entries.append(LogEntry(id: j.nextEntryID + i, day: 1, system: 0, worth: 0, kind: .encounter(r)))
        }
        #expect(MetBefore.make(opponent: .gnat, journal: j) == MetBefore(met: 2, won: 1))
        #expect(MetBefore.make(opponent: .wasp, journal: j) == MetBefore(met: 0, won: 0))
    }

    @Test("INT-040 the Market's standard-price helper equals TradeIntel's estimate for every system and item")
    func onePrice() throws {
        let s = try TestSessions.playing()
        var st = try #require(s.state)
        let snapshot = IntelSnapshot(st)
        for target in st.destinations {
            st.warpSystem = target
            for row in st.marketRows {
                let q = TargetQuote.make(state: st, item: row.item, buyPrice: row.buyPrice)
                let est = TradeIntel.estimate(item: row.item, system: target, snapshot: snapshot)
                #expect((q?.price ?? 0) == est)
            }
        }
    }

    @Test("INT-028 MAP-072 the sells filter: observed systems or the public rule (estimate), combined with the other filters")
    func sellsFilter() throws {
        let s = try TestSessions.playing()
        let inputs = try #require(s.intelInputs())
        let snap = try #require(s.mapSnapshot)
        let sells = SystemSearch.sells(.water, book: inputs.book, snapshot: inputs.snapshot)
        #expect(sells.count == snap.systems.count)
        let all = SystemSearch.results(query: "", filters: [], snapshot: snap, sells: sells)
        #expect(Set(all) == Set(sells.indices.filter { sells[$0] != nil }))
        #expect(SystemSearch.dimmed(filters: [], snapshot: snap, sells: sells) == Set(sells.indices.filter { sells[$0] == nil }))
        #expect(SystemSearch.results(query: "", filters: [], snapshot: snap, sells: nil).isEmpty)
        #expect(s.sellsMatches(nil) == nil && s.sellsMatches(.water) == sells)
        #expect(AXID.Map(.galaxy).searchFilterSells == "galaxy.search.filter.sells")
    }

    // MARK: Heatmap (MAP-096 / MAP-097)

    @Test("MAP-096 heatmap choices map to modes; tints normalize the scale; the legend has numbers and the estimate note")
    func heatmapHUD() throws {
        #expect(MapHeatmapChoice.allCases.map { $0.mode(item: .robots) }
            == [.none, .price(.robots), .holdProfit, .police, .pirates, .techLevel, .lastVisited])
        let r = HeatmapResult(values: [HeatmapValue(value: 10), HeatmapValue(value: nil), HeatmapValue(value: 30, note: .estimate)],
                              scale: HeatmapScale(min: 10, max: 30))
        #expect(HeatmapTint.strengths(r) == [0, nil, 1])
        #expect(HeatmapTint.legend(r) == ["Low 10 · High 30", "Dashed: estimate"])
        #expect(HeatmapTint.legend(HeatmapResult(values: [HeatmapValue(value: nil)], scale: HeatmapScale(min: 0, max: 0))) == ["No data"])
        #expect(MapLayer.m10.contains(.heatmap) && MapLayer.m10.count == MapLayer.allCases.count)
        #expect(AXID.Map(.galaxy).heatmap == "galaxy.heatmap" && AXID.Map(.galaxyWindow).heatmapCommodity == "galaxyWindow.heatmap.commodity")
        let s = try TestSessions.playing()
        #expect(s.heatmap(.none) == nil)
        let tech = try #require(s.heatmap(.techLevel))
        #expect(tech.values.count == s.state?.galaxy.systems.count)
    }

    @Test("MAP-097 the map's heatmap comes from intel only: hidden prices and resources never change it")
    func heatmapFairness() throws {
        let s = try Self.tradingSession()
        let modes: [HeatmapMode] = [.price(.water), .price(.robots), .holdProfit, .police, .pirates, .techLevel, .lastVisited]
        let before = modes.map { s.heatmap($0) }
        try TestSessions.edit(s) { st in
            for i in st.galaxy.systems.indices where i != st.commander.currentSystem {
                st.galaxy.systems[i].tradeItems = st.galaxy.systems[i].tradeItems.map { $0 + 7 }
                st.galaxy.systems[i].countDown += 1
                if !st.galaxy.systems[i].visited { st.galaxy.systems[i].specialResource = .mineralRich }
            }
        }
        // `edit` installs a fresh journal for the edited state; restore the intel by rebuilding from the same start.
        #expect(modes.map { s.heatmap($0)?.values.map(\.value) } == before.map { $0?.values.map(\.value) })
    }
}
