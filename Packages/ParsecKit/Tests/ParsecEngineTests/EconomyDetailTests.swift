// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecEngine

/// A trader ship in an encounter, carrying `cargo` units of each item at index → count.
func traderEncounter(_ s: inout GameState, cargo: [TradeItemType: Int]) {
    var ship = Ship(type: .beetle, spec: s.ruleset.tables.ship(.beetle))
    for (item, q) in cargo.sorted(by: { $0.key.rawValue < $1.key.rawValue }) { ship.cargo[item.rawValue] = q }
    s.phase = .encounter(EncounterState(type: .traderSell, opponent: ship))
}

@Suite("Economy details (ECO)")
struct EconomyDetailTests {
    @Test("ECO-001 ECO-002 trade item table and illegality")
    func tradeTable() {
        let t = Ruleset.windows201.tables.tradeItems
        #expect(t.count == 10)
        #expect(t[0] == TradeItemSpec(type: .water, techProduction: .preAgricultural, techUsage: .preAgricultural, techTopProduction: .medieval,
                                      priceLowTech: 30, priceIncrease: 3, variance: 4, pressurePriceHike: .drought,
                                      resourceLowPrice: .sweetOceans, resourceHighPrice: .desert, minTradePrice: 30, maxTradePrice: 50, roundOff: 1))
        #expect(t[9].priceLowTech == 5_000 && t[9].priceIncrease == -150 && t[9].roundOff == 100)
        #expect(TradeItemType.allCases.filter(\.isIllegal) == [.firearms, .narcotics])
    }

    @Test("ECO-003 ECO-004 ECO-008 traded/used rules and zero standard price when unused")
    func tradedUsed() {
        let r = Ruleset.windows201
        var sys = StarSystem(id: 0, x: 0, y: 0, size: .medium, techLevel: .agricultural, politics: .pacifist, pressure: .none, specialResource: .nothing)
        let robots = r.tables.item(.robots), firearms = r.tables.item(.firearms), food = r.tables.item(.food)
        #expect(!Pricing.itemTraded(robots, in: sys, ruleset: r) && !Pricing.itemUsed(robots, in: sys, ruleset: r))
        #expect(Pricing.standardPrice(robots, in: sys, ruleset: r) == 0)
        #expect(Pricing.itemTraded(food, in: sys, ruleset: r))
        sys.techLevel = .renaissance
        #expect(!Pricing.itemUsed(firearms, in: sys, ruleset: r), "Pacifist forbids firearms")
        for item in r.tables.tradeItems { #expect(item.techUsage <= item.techProduction) }
    }

    @Test("ECO-005 ECO-009 ECO-010 standard price formula and hidden resource (Windows)")
    func standardPrice() {
        let r = Ruleset.windows201
        var sys = StarSystem(id: 0, x: 0, y: 0, size: .large, techLevel: .hiTech, politics: .corporate, pressure: .none, specialResource: .mineralRich)
        let ore = r.tables.item(.ore)
        // 350 + 7·20 = 490; Corporate wants Robots (no); traders Swarms 7 → ×86/100 = 421; size 3 → ×97/100 = 408
        #expect(Pricing.standardPrice(ore, in: sys, ruleset: r) == 408)
        sys.visited = true
        #expect(Pricing.standardPrice(ore, in: sys, ruleset: r) == 408 * 3 / 4)
        #expect(r.tables.item(.robots).priceLowTech + 7 * r.tables.item(.robots).priceIncrease == 3_950)
        for item in r.tables.tradeItems { #expect(item.priceLowTech + 7 * item.priceIncrease > 0) }
    }

    @Test("ECO-016 ECO-017 ECO-041 prices are recomputed for the arrival system after quantities")
    func arrivalOrder() {
        var a = makeEngine().state, b = a
        a.arrivalMarketUpdate(arrival: 5)
        b.updatePressuresAndQuantities(arrival: 5)
        b.calculatePrices(for: 5)
        #expect(a == b)
        #expect(a.buyPrices.count == 10 && a.sellPrices.count == 10)
    }

    @Test("ECO-021 ECO-022 hiring changes buy prices only; traded items have buy ≥ sell + 1, untraded buy 0")
    func buyRecalc() throws {
        for seed in 1...60 {
            var e = makeEngine(seed: UInt64(seed))
            let candidates = e.state.mercenariesForHire
            guard let merc = candidates.first(where: { e.state.mercenaries[$0].skills[2] > 5 && e.state.dailyRate(of: $0) > 0 }) else { continue }
            e.state.commander.ship.crew = [CrewID.commander, nil]
            let sell = e.state.sellPrices
            _ = e.perform(.hire(crewID: merc))
            #expect(e.state.sellPrices == sell)
            let sys = e.state.currentSystem
            for (i, item) in e.ruleset.tables.tradeItems.enumerated() {
                if Pricing.itemTraded(item, in: sys, ruleset: e.ruleset) {
                    #expect(e.state.buyPrices[i] >= e.state.sellPrices[i] + 1)
                } else {
                    #expect(e.state.buyPrices[i] == 0)
                }
            }
            return
        }
        Issue.record("no suitable seed")
    }

    @Test("ECO-023 RecalculateSellPrices multiplies sell by 100/90 and leaves buy")
    func recalcSell() {
        var s = makeEngine { s in setMarket(&s, buy: 100, sell: 90) }.state
        s.recalculateSellPrices()
        #expect(s.sellPrices.allSatisfy { $0 == 100 } && s.buyPrices.allSatisfy { $0 == 100 })
    }

    @Test("ECO-032 ECO-033 countdown start = difficulty + 3, set on departure")
    func countdown() {
        var s = makeEngine(difficulty: .hard).state
        #expect(s.countDownStart == 6)
        #expect(s.galaxy.systems.allSatisfy { $0.countDown == 0 })
        s.setDepartureCountdown()
        #expect(s.currentSystem.countDown == 6)
    }

    @Test("ECO-042 cash to spend subtracts current costs only with Reserve Money")
    func cashToSpend() {
        var s = makeEngine().state
        s.commander.debt = 5_000
        #expect(s.cashToSpend == s.commander.cash)
        s.options.reserveMoney = true
        #expect(s.cashToSpend == s.commander.cash - 500)
    }

    @Test("ECO-044 option defaults")
    func optionDefaults() {
        let o = GameOptions()
        #expect(!o.reserveMoney && o.leaveEmpty == 0 && o.alwaysIgnoreTraders && o.remindLoans && o.trackAutoOff)
    }

    @Test("ECO-050 ECO-079 sell preview: max = units held; dump mode when the market does not buy")
    func sellPreview() throws {
        let e = makeEngine { s in setMarket(&s, sell: 50); s.commander.ship.cargo[3] = 7; s.sellPrices[4] = 0; s.commander.ship.cargo[4] = 2 }
        #expect(try e.state.marketSellCheck(.ore, dump: false).get() == 7)
        #expect(e.state.marketSellCheck(.games, dump: false) == .failure(.marketNotInterested))
        #expect(try e.state.marketSellCheck(.games, dump: true).get() == 2)
        #expect(e.state.marketSellCheck(.water, dump: false) == .failure(.cargoNoneToSell))
    }

    @Test("ECO-055 jettison is only possible in space")
    func jettisonDocked() {
        var e = makeEngine { s in s.commander.ship.cargo[0] = 5 }
        #expect(e.perform(.jettisonCargo(.water, quantity: 1)).rejection == .notAllowedInPhase)
    }

    @Test("ECO-078 ECO-083 buy preview and perform agree; errors map to the classic alerts")
    func buyPreview() throws {
        var e = makeEngine { s in setMarket(&s, buy: 300); s.commander.cash = 1_000 }
        let maxQ = try e.state.marketBuyCheck(.ore).get()
        #expect(maxQ == 3)
        #expect(e.perform(.buyCargo(.ore, quantity: maxQ + 1)).rejection == .invalidQuantity)
        #expect(e.perform(.buyCargo(.ore, quantity: maxQ)).rejection == nil)
        #expect(e.state.marketBuyCheck(.ore) == .failure(.insufficientFunds))
    }

    @Test("ECO-076 invariants after random market commands")
    func invariants() {
        var e = makeEngine(seed: 77) { s in s.commander.cash = 20_000 }
        var rng = Xoshiro256StarStar(seed: 1)
        for _ in 0..<400 {
            let item = TradeItemType(rawValue: rng.next(below: 10)) ?? .water
            let q = 1 + rng.next(below: 5)
            switch rng.next(below: 3) {
            case 0: _ = e.perform(.buyCargo(item, quantity: q))
            case 1: _ = e.perform(.sellCargo(item, quantity: q))
            default: _ = e.perform(.dumpCargo(item, quantity: q))
            }
            let s = e.state
            #expect(s.commander.ship.cargo.allSatisfy { $0 >= 0 } && s.currentSystem.tradeItems.allSatisfy { $0 >= 0 })
            #expect(s.filledCargoBays <= s.commander.ship.cargoBays(s.ruleset))
            for i in 0..<10 where s.commander.ship.cargo[i] == 0 { #expect(s.commander.priceCargo[i] == 0) }
        }
    }

    @Test("ECO-060 ECO-061 tradeable items follow the criminal XOR rule; pick advances from GetRandom(10)")
    func tradeable() {
        var s = makeEngine { s in setMarket(&s) }.state
        var ship = Ship(type: .beetle, spec: s.ruleset.tables.ship(.beetle))
        ship.cargo[5] = 3; ship.cargo[2] = 4
        #expect(s.tradeableItems(in: ship, isTraderShip: true) == [.food])
        s.commander.policeRecordScore = -6
        #expect(s.tradeableItems(in: ship, isTraderShip: true) == [.firearms])
        #expect(s.pickTradeItem(in: ship, isTraderShip: true) == .firearms)
    }

    @Test("ECO-059 trade-in-orbit roll: TraderSell needs a free bay and trader goods, else TraderBuy")
    func orbitRoll() {
        var s = makeEngine { s in setMarket(&s) }.state
        s.chanceOfTradeInOrbit = 1_000
        var trader = Ship(type: .beetle, spec: s.ruleset.tables.ship(.beetle))
        trader.cargo[0] = 5
        #expect(s.tradeInOrbitRoll(trader: trader) == .traderSell)
        s.commander.ship.cargo[1] = s.commander.ship.cargoBays(s.ruleset)
        #expect(s.tradeInOrbitRoll(trader: trader) == .traderBuy)
        s.chanceOfTradeInOrbit = 0
        #expect(s.tradeInOrbitRoll(trader: trader) == nil)
    }

    @Test("ECO-063 ECO-064 ECO-074 in-orbit prices: ±adjustment, banker's rounding, clamped to trade limits")
    func orbitPrices() {
        var low = Xoshiro256StarStar(seed: 0)
        // Find draws to cover both branches deterministically by brute force over seeds.
        var seen = Set<Int>()
        for seed in 0..<200 {
            var r = DotNetRandom(seed: Int32(seed))
            let p = OrbitTrade.price(item: .ore, marketPrice: 400, direction: .traderSells, ruleset: .windows201, rng: &r)
            seen.insert(p)
            #expect(p == 360 || p == 420, "ore 400×0.9=360 or ×1.1=440→clamped 420; got \(p)")
        }
        #expect(seen == [360, 420])
        #expect(OrbitTrade.roundHalfEven(2.5) == 2 && OrbitTrade.roundHalfEven(3.5) == 4)
        _ = low.next(below: 1)
        var r2 = DotNetRandom(seed: 3)
        let buy = OrbitTrade.price(item: .water, marketPrice: 40, direction: .traderBuys, ruleset: .windows201, rng: &r2)
        #expect([36, 44].contains(buy))
    }

    @Test("ECO-065 ECO-068 ECO-071 ECO-073 ECO-081 orbit trade offer, Windows cash cap quirk, resolve and event")
    func orbitOffer() {
        var e = makeEngine { s in setMarket(&s, buy: 100, sell: 90); s.commander.cash = 1_000; traderEncounter(&s, cargo: [.food: 30]) }
        let open = e.startOrbitTrade(direction: .traderSells)
        guard case let .tradeInOrbit(offer) = open.decision else { Issue.record("no offer"); return }
        #expect(offer.item == .food && offer.unitsAvailable == 30)
        // Windows caps with the *system* buy price (100): min(15 bays, 30, 1000/100) = 10.
        #expect(offer.maxQuantity == 10)
        #expect(e.perform(.resolveTradeInOrbit(quantity: 11)).rejection == .invalidQuantity)
        let r = e.perform(.resolveTradeInOrbit(quantity: 2))
        #expect(r.events == [.orbitTradeCompleted(direction: .traderSells, item: .food, quantity: 2, total: 2 * offer.unitPrice)])
        guard case let .encounter(enc) = e.state.phase else { return }
        #expect(enc.opponent.cargo[2] == 28 && e.state.commander.ship.cargo[2] == 2)
        // Selling to a trader: max = min(held, trader free bays).
        var b = makeEngine { s in setMarket(&s, buy: 100, sell: 90); s.commander.ship.cargo[0] = 6; traderEncounter(&s, cargo: [.ore: 48]) }
        guard case let .tradeInOrbit(o2) = b.startOrbitTrade(direction: .traderBuys).decision else { Issue.record("no offer"); return }
        #expect(o2.item == .water && o2.maxQuantity == 2)
        #expect(b.perform(.resolveTradeInOrbit(quantity: 0)).events.isEmpty)
    }

    @Test("ECO-082 price breakdown explains the sell price from visible information")
    func breakdown() {
        let s = makeEngine().state
        for item in TradeItemType.allCases {
            let b = s.priceBreakdown(item)
            #expect(b.afterCriminal + b.fluctuation == s.sellPrices[item.rawValue])
            #expect(b.buyMarkup == s.buyPrices[item.rawValue] - s.sellPrices[item.rawValue])
        }
    }
}
