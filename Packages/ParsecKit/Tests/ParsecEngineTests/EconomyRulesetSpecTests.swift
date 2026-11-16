// SPDX-License-Identifier: GPL-2.0-or-later
// M5 economy ruleset rows: markets, trade in orbit, worth and the MOD fixes in this area (RUL-032…043, 101, 105…108,
// 113, 115, 117…119; ECO {M5}). Palm behaviour is tested as rules (formula, order, ranges), not ROM-exact numbers.
import Testing
@testable import ParsecEngine

/// The first RNG state reached from `start` whose next `next(below: n)` draw equals `value`.
func rngState(_ start: RNGState, nextBelow n: Int, is value: Int) -> RNGState {
    var s = start
    while true {
        var probe = s
        if probe.next(below: n) == value { return s }
        _ = s.next(below: n)
    }
}

/// A docked state whose every system has an expired countdown except `system`, which drifts on the next update.
private func driftState(_ id: RulesetID, seed: UInt64 = 7) -> (GameState, Int) {
    var s = makeEngine(id, seed: seed).state
    for i in s.galaxy.systems.indices { s.galaxy.systems[i].countDown = 0 }
    return (s, s.commander.currentSystem)
}

/// Runs `steps` drift steps of `system` (countdown 4 → 3, so drift) with `arrival` as the warp system; returns every
/// per-item delta from a stock of 50 and the stocks after the last step.
private func drift(_ s: inout GameState, system k: Int, arrival: Int, steps: Int) -> (deltas: [[Int]], last: [Int]) {
    var deltas: [[Int]] = []
    var last: [Int] = []
    for _ in 0..<steps {
        s.galaxy.systems[k].countDown = 4
        s.galaxy.systems[k].tradeItems = Array(repeating: 50, count: 10)
        s.updatePressuresAndQuantities(arrival: arrival)
        last = s.galaxy.systems[k].tradeItems
        deltas.append(last.map { $0 - 50 })
    }
    return (deltas, last)
}

@Suite("Economy rulesets: markets (RUL-032…036, ECO {M5})")
struct EconomyRulesetMarketTests {
    @Test("RUL-032 ECO-027 Palm quantities scale by the size of system #itemIndex; Modern and Windows by the own size")
    func quantitySizeSource() {
        let base = makeEngine(.windows201).state
        var huge = base.currentSystem
        huge.specialResource = .nothing
        huge.pressure = .none
        huge.size = .huge
        var tiny = huge
        tiny.size = .tiny
        let allTiny = Array(repeating: SystemSize.tiny, count: base.galaxy.systems.count)
        var r1 = base.rng, r2 = base.rng, r3 = base.rng, r4 = base.rng
        let palm = Pricing.initialQuantities(for: huge, difficulty: .normal, ruleset: .palm122, systemSizes: allTiny, rng: &r1)
        let windowsTiny = Pricing.initialQuantities(for: tiny, difficulty: .normal, ruleset: .windows201, rng: &r2)
        #expect(palm == windowsTiny)
        let modern = Pricing.initialQuantities(for: huge, difficulty: .normal, ruleset: .modern, systemSizes: allTiny, rng: &r3)
        let windowsHuge = Pricing.initialQuantities(for: huge, difficulty: .normal, ruleset: .windows201, rng: &r4)
        #expect(modern == windowsHuge && modern != palm)
    }

    @Test("RUL-033 ECO-039 Palm drift is rand(5) − rand(5) (triangular −4…4); Modern and Windows uniform −4…4")
    func driftDistribution() {
        func stats(_ id: RulesetID) -> (zero: Double, extreme: Double, inRange: Bool) {
            var (s, k) = driftState(id)
            s.galaxy.systems[k].techLevel = .hiTech
            s.galaxy.systems[k].politics = .anarchy
            let traded = s.ruleset.tables.tradeItems.indices.filter {
                Pricing.itemTraded(s.ruleset.tables.tradeItems[$0], in: s.galaxy.systems[k], ruleset: s.ruleset)
            }
            let all = drift(&s, system: k, arrival: k, steps: 400).deltas.flatMap { d in traded.map { d[$0] } }
            let n = Double(all.count)
            return (Double(all.filter { $0 == 0 }.count) / n, Double(all.filter { abs($0) == 4 }.count) / n,
                    all.allSatisfy { (-4...4).contains($0) })
        }
        let palm = stats(.palm122), windows = stats(.windows201), modern = stats(.modern)
        #expect(palm.inRange && windows.inRange && modern.inRange)
        // Triangular: P(0) = 5/25, P(±4) = 2/25; uniform: P(0) = 1/9, P(±4) = 2/9.
        #expect(palm.zero > 0.16 && palm.extreme < 0.12)
        #expect(windows.zero < 0.15 && windows.extreme > 0.17)
        #expect(modern.zero < 0.15 && modern.extreme > 0.17)
    }

    @Test("RUL-034 RUL-107 ECO-038 ECO-039 untradeable items: Palm zeroes them; Modern tests the own system; Windows the warp system")
    func untradeableDrift() {
        func run(_ id: RulesetID) -> [Int] {
            var (s, k) = driftState(id)
            s.galaxy.systems[k].techLevel = .agricultural
            // The warp system can trade robots; system k cannot.
            let arrival = (k + 1) % s.galaxy.systems.count
            s.galaxy.systems[arrival].techLevel = .hiTech
            return drift(&s, system: k, arrival: arrival, steps: 30).deltas.map { $0[TradeItemType.robots.rawValue] }
        }
        #expect(run(.palm122).allSatisfy { $0 == -50 })
        #expect(run(.modern).allSatisfy { $0 == 0 })
        let windows = run(.windows201)
        #expect(windows.contains { $0 != 0 } && windows.allSatisfy { (-4...4).contains($0) })
    }

    @Test("RUL-035 ECO-040 Palm shuffles every status before any quantity draw; Modern and Windows interleave per system")
    func shuffleOrder() {
        func pressures(_ id: RulesetID, countdowns: Bool) -> [SystemPressure] {
            var s = makeEngine(id, seed: 11).state
            for i in s.galaxy.systems.indices { s.galaxy.systems[i].countDown = countdowns ? 3 : 0 }
            s.updatePressuresAndQuantities(arrival: s.commander.currentSystem)
            return s.galaxy.systems.map(\.pressure)
        }
        // With statuses first, the quantity draws cannot move later status draws.
        #expect(pressures(.palm122, countdowns: true) == pressures(.palm122, countdowns: false))
        #expect(pressures(.windows201, countdowns: true) != pressures(.windows201, countdowns: false))
        #expect(pressures(.modern, countdowns: true) != pressures(.modern, countdowns: false))
    }

    @Test("RUL-036 ECO-013 Palm variance is rand(V) − rand(V) (never ±V); Modern and Windows uniform in [−v, v]")
    func priceVariance() {
        func deviations(_ id: RulesetID) -> [Int] {
            var s = makeEngine(id).state
            var sys = s.currentSystem
            sys.techLevel = .hiTech
            sys.politics = .anarchy
            sys.pressure = .none
            let water = s.ruleset.tables.item(.water)
            let base = Pricing.standardPrice(water, in: sys, ruleset: s.ruleset)
            return (0..<600).map { _ in
                Pricing.sellPrices(in: sys, criminal: false, ruleset: s.ruleset, rng: &s.rng)[0] - base
            }
        }
        let palm = deviations(.palm122)
        #expect(palm.allSatisfy { (-3...3).contains($0) } && palm.contains(3) && palm.contains(-3))
        for id in [RulesetID.windows201, .modern] {
            let d = deviations(id)
            #expect(d.allSatisfy { (-4...4).contains($0) } && d.contains(4) && d.contains(-4))
        }
    }

    @Test("RUL-106 ECO-006 ECO-007 resources change unvisited markets in Modern and Palm; Modern still shows Unknown")
    func resourceUnvisited() {
        for id in [RulesetID.windows201, .modern, .palm122] {
            var s = makeEngine(id).state
            let k = s.commander.currentSystem
            s.galaxy.systems[k].visited = false
            s.galaxy.systems[k].specialResource = .sweetOceans
            s.galaxy.systems[k].pressure = .none
            let sys = s.galaxy.systems[k]
            var noResource = sys
            noResource.specialResource = .nothing
            let water = s.ruleset.tables.item(.water)
            let price = Pricing.standardPrice(water, in: sys, ruleset: s.ruleset)
            let plain = Pricing.standardPrice(water, in: noResource, ruleset: s.ruleset)
            #expect((price == plain * 3 / 4) == (id != .windows201))
            // The player-facing view never leaks the hidden resource.
            #expect(sys.knownResource == .nothing)
            #expect(s.priceBreakdown(.water).afterResource == s.priceBreakdown(.water).afterSize)
        }
    }

    @Test("ECO-075 Modern keeps Windows' exact integer price and quantity arithmetic")
    func modernIntegerArithmetic() {
        let w = makeEngine(.windows201).state
        let m = makeEngine(.modern).state
        let sys = w.currentSystem
        var r1 = w.rng, r2 = w.rng
        #expect(Pricing.sellPrices(in: sys, criminal: true, ruleset: .modern, rng: &r1)
            == Pricing.sellPrices(in: sys, criminal: true, ruleset: .windows201, rng: &r2))
        var q1 = w.rng, q2 = w.rng
        #expect(Pricing.initialQuantities(for: sys, difficulty: .hard, ruleset: .modern, rng: &q1)
            == Pricing.initialQuantities(for: sys, difficulty: .hard, ruleset: .windows201, rng: &q2))
        let sell = [37, 251, 101, 359, 0, 999, 640, 777, 2_555, 4_321]
        #expect(Pricing.buyPrices(sell: sell, in: sys, criminal: true, traderSkill: 7, ruleset: .modern)
            == Pricing.buyPrices(sell: sell, in: sys, criminal: true, traderSkill: 7, ruleset: .windows201))
        #expect(m.payInterestResult(debt: 12_345) == w.payInterestResult(debt: 12_345))
    }
}

private extension GameState {
    func payInterestResult(debt: Int) -> Int {
        var s = self
        s.commander.debt = debt
        s.commander.cash = 0
        s.payInterest()
        return s.commander.debt
    }
}

@Suite("Economy rulesets: money to spend, dumping, haggling (ECO {M5})")
struct EconomyRulesetMoneyTests {
    @Test("ECO-043 BNK-055 Palm ToSpend = max(0, cash − mercenaries − insurance), ignoring interest and wormhole tax")
    func toSpend() {
        for id in [RulesetID.windows201, .palm122] {
            var s = makeEngine(id).state
            s.options.reserveMoney = true
            s.commander.cash = 500
            s.commander.debt = 10_000
            #expect(s.cashToSpend == (id == .palm122 ? 500 : 500 - 1_000))
            s.commander.debt = 0
            s.commander.ship = freshShip(.beetle, s)
            s.commander.ship.crew[1] = 1
            let wage = s.dailyRate(of: 1)
            s.commander.cash = wage - 1
            #expect(s.cashToSpend == (id == .palm122 ? 0 : -1))
            s.commander.cash = 1_000
            #expect(s.cashToSpend == 1_000 - wage)
        }
    }

    @Test("RUL-043 ECO-054 dock-dump cap: cashToSpend/(5(D+1)) in Modern and Windows; Palm toSpend/5×(D+1)")
    func dumpCap() {
        for (id, expected) in [(RulesetID.windows201, 1_000 / 15), (.modern, 1_000 / 15), (.palm122, 1_000 / 5 * 3)] {
            let s = makeEngine(id) { s in
                setMarket(&s)
                s.sellPrices[0] = 0
                s.commander.ship = freshShip(.termite, s)
                s.commander.ship.cargo[0] = 700
                s.commander.cash = 1_000
            }.state
            #expect((try? s.marketSellCheck(.water, dump: true).get()) == expected)
        }
    }

    @Test("ECO-058 Palm asks before jettisoning a whole holding and shows its cost basis; Modern and Windows do not")
    func jettisonAll() {
        for id in [RulesetID.windows201, .modern, .palm122] {
            var e = makeEngine(id) { s in
                s.commander.ship.cargo[2] = 4
                s.commander.priceCargo[2] = 440
                s.commander.policeRecordScore = -10
                s.phase = .inTransit(TransitState(destination: s.warpSystem, clicksRemaining: 5, viaWormhole: false))
            }
            var partial = e
            #expect(partial.perform(.jettisonCargo(.food, quantity: 3)).decision == nil)
            let r = e.perform(.jettisonCargo(.food, quantity: 4))
            if id == .palm122 {
                #expect(r.decision == .confirm(Confirmation(.jettisonAll, amounts: [440])))
                #expect(e.state.commander.ship.cargo[2] == 4)
                #expect(e.perform(.jettisonCargo(.food, quantity: 4), acknowledging: [.jettisonAll]).events.first
                    == .jettisonedCargo(item: .food, quantity: 4))
            } else {
                #expect(r.events.first == .jettisonedCargo(item: .food, quantity: 4))
            }
        }
    }

    @Test("RUL-051 ECO-020 Palm adds Jarek's +1 trader before the difficulty adjustment (Impossible, skill 1: Palm 1, C# 2)")
    func haggleOrder() {
        for (id, expected) in [(RulesetID.windows201, 2), (.modern, 2), (.palm122, 1)] {
            let s = makeEngine(id, difficulty: .impossible) { s in
                s.mercenaries[CrewID.commander].skills = [1, 1, 1, 1]
                s.quests.jarek = QuestStatus.Jarek.done
            }.state
            #expect(s.skill(.trader) == expected)
        }
    }
}

@Suite("Economy rulesets: trade in orbit (RUL-038…042, RUL-108, ECO {M5})")
struct EconomyRulesetOrbitTests {
    /// A docked state with a known market and a trader carrying `cargo`.
    static func orbit(_ id: RulesetID, _ adjust: (inout GameState) -> Void = { _ in }) -> (GameState, Ship) {
        var s = makeEngine(id) { s in setMarket(&s, buy: 100, sell: 90) }.state
        adjust(&s)
        var trader = Ship(type: .beetle, spec: s.ruleset.tables.ship(.beetle))
        trader.cargo = [0, 0, 20, 0, 0, 0, 0, 0, 0, 0]
        return (s, trader)
    }

    @Test("RUL-038 RUL-039 ECO-066 Palm: inclusive thresholds, truncation, trader sells /r×r, trader buys (/r+1)×r")
    func palmPricing() {
        let start = rngState(makeEngine().state.rng, nextBelow: 100, is: 45)
        func price(_ id: RulesetID, _ direction: OrbitTradeDirection) -> Int {
            var rng = start
            return OrbitTrade.price(item: .narcotics, marketPrice: 2_550, direction: direction, ruleset: .named(id), rng: &rng)
        }
        // Draw 45 is favourable only with Palm's `<= 45`: trader sells ×1.1, trader buys ×0.8.
        #expect(price(.palm122, .traderSells) == Int(2_550.0 * 1.1) / 50 * 50)
        #expect(price(.palm122, .traderBuys) == (Int(2_550.0 * 0.8) / 50 + 1) * 50)
        #expect(price(.windows201, .traderSells) == Int((2_550.0 * 0.8 / 50).rounded(.toNearestOrEven)) * 50)
        #expect(price(.windows201, .traderBuys) == Int((2_550.0 * 1.1 / 50).rounded(.toNearestOrEven)) * 50)
        #expect(price(.modern, .traderBuys) == price(.windows201, .traderBuys))
        // Clamp to the item's trade range in every ruleset.
        var rng = start
        #expect(OrbitTrade.price(item: .narcotics, marketPrice: 9_000, direction: .traderBuys, ruleset: .palm122, rng: &rng) == 3_000)
    }

    @Test("RUL-041 ECO-067 Palm writes the in-orbit price into the market arrays; Modern and Windows keep it local")
    func priceScope() {
        for id in [RulesetID.windows201, .modern, .palm122] {
            var (s, trader) = Self.orbit(id)
            guard let offer = s.makeOrbitTradeOffer(direction: .traderSells, trader: trader) else {
                Issue.record("no offer"); continue
            }
            #expect(s.buyPrices[offer.item.rawValue] == (id == .palm122 ? offer.unitPrice : 100))
            s.commander.ship.cargo[0] = 5
            trader.cargo = Array(repeating: 0, count: 10)
            let sell = s.makeOrbitTradeOffer(direction: .traderBuys, trader: trader)
            #expect(s.sellPrices[0] == (id == .palm122 ? sell?.unitPrice : 90))
        }
    }

    @Test("RUL-108 ECO-069 ECO-070 buy cap: Modern and Palm cash / in-orbit price; Windows cash / system price")
    func buyCap() {
        for id in [RulesetID.windows201, .modern, .palm122] {
            var (s, trader) = Self.orbit(id) { $0.commander.cash = 1_000 }
            let free = s.freeCargoBays
            guard let offer = s.makeOrbitTradeOffer(direction: .traderSells, trader: trader) else {
                Issue.record("no offer"); continue
            }
            let capPrice = id == .windows201 ? 100 : offer.unitPrice
            #expect(offer.maxQuantity == min(free, 20, 1_000 / capPrice))
            var buyer = s
            if buyer.resolveOrbitTrade(offer, quantity: offer.maxQuantity, trader: &trader) != nil, id != .windows201 {
                #expect(buyer.commander.cash >= 0)
            }
        }
    }

    @Test("RUL-040 ECO-072 sell cap: Modern and Windows the trader's free bays; Palm its type's bays, overwriting its cargo")
    func sellCap() {
        for id in [RulesetID.windows201, .modern, .palm122] {
            var (s, trader) = Self.orbit(id) { s in
                s.commander.ship = freshShip(.termite, s)
                s.commander.ship.cargo[0] = 60
            }
            trader.cargo = [0, 0, 45, 0, 0, 0, 0, 0, 0, 0]
            guard let offer = s.makeOrbitTradeOffer(direction: .traderBuys, trader: trader) else {
                Issue.record("no offer"); continue
            }
            #expect(offer.maxQuantity == (id == .palm122 ? 50 : 5))
            _ = s.resolveOrbitTrade(offer, quantity: 3, trader: &trader)
            #expect(trader.cargo[0] == (id == .palm122 ? 3 : 0) && s.commander.ship.cargo[0] == 57)
        }
    }

    @Test("ECO-062 Palm picks with up to 10 rand(10) tries, then scans from 0; C# advances from one draw")
    func itemPick() {
        let base = Self.orbit(.palm122).0
        var trader = Ship(type: .beetle, spec: base.ruleset.tables.ship(.beetle))
        trader.cargo = [0, 0, 5, 0, 0, 0, 0, 7, 0, 0]
        // A state whose next ten draws hit neither 2 nor 7: Palm falls back to the scan (item 2).
        var probe = base.rng
        var start = base.rng
        while true {
            var p = probe
            if (0..<10).allSatisfy({ _ in ![2, 7].contains(p.next(below: 10)) }) { start = probe; break }
            _ = probe.next(below: 10)
        }
        var palm = base
        palm.rng = start
        #expect(palm.pickTradeItem(in: trader, isTraderShip: true) == .food)
        var after = start
        for _ in 0..<10 { _ = after.next(below: 10) }
        #expect(palm.rng == after)
        // C#: one draw, then advance cyclically to the next qualifying index.
        var windows = Self.orbit(.windows201).0
        windows.rng = start
        var first = start
        let d = first.next(below: 10)
        let expected: TradeItemType = (3...7).contains(d) ? .machines : .food
        #expect(windows.pickTradeItem(in: trader, isTraderShip: true) == expected && windows.rng == first)
    }

    @Test("RUL-042 a cloaked player still gets trade offers in Palm; never in Modern and Windows")
    func cloakedTrade() {
        func offers(_ id: RulesetID) -> Int {
            var s = makeEngine(id, difficulty: .beginner) { s in
                setMarket(&s)
                s.chanceOfTradeInOrbit = 1_000
                s.commander.ship.gadgets = [.cloakingDevice]
                s.mercenaries[CrewID.commander].skills = [1, 1, 8, 10]
            }.state
            var count = 0
            for _ in 0..<60 {
                let enc = s.determineTrader(clicks: 5)
                guard s.commanderCloaked else { continue }
                if let t = enc?.type, t == .traderSell || t == .traderBuy { count += 1 }
            }
            return count
        }
        #expect(offers(.palm122) > 0)
        #expect(offers(.windows201) == 0 && offers(.modern) == 0)
    }
}

@Suite("Economy rulesets: MOD fixes and worth (RUL-101, 105, 113, 115, 117…119, BNK/SHP worth)")
struct EconomyRulesetModTests {
    @Test("RUL-101 MOD-001 buying a ship or getting the Flea resets the cargo cost basis in Modern and Palm; Windows keeps it")
    func costBasisReset() {
        for id in [RulesetID.windows201, .modern, .palm122] {
            var e = makeEngine(id) { s in
                s.commander.cash = 200_000
                s.commander.priceCargo[3] = 700
                s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech
            }
            let kept = id == .windows201 ? 700 : 0
            _ = e.perform(.buyShip(.firefly, transfers: []), acknowledging: [.buyShip])
            #expect(e.state.commander.ship.type == .firefly && e.state.commander.priceCargo[3] == kept)
            var s = makeEngine(id).state
            s.commander.priceCargo[3] = 700
            s.createFlea()
            #expect(s.commander.priceCargo[3] == kept)
        }
    }

    @Test("RUL-105 CRW-053 MOD-005 random increases reach 10 in Modern and Palm, stop at 9 in Windows")
    func skillCap() {
        for id in [RulesetID.windows201, .modern, .palm122] {
            var s = makeEngine(id) { $0.mercenaries[CrewID.commander].skills = [9, 9, 9, 9] }.state
            s.changeRandomSkill(1)
            let skills = s.mercenaries[CrewID.commander].skills
            #expect(skills == [9, 9, 9, 9] ? id == .windows201 : (id != .windows201 && skills.max() == 10))
        }
    }

    @Test("RUL-113 MOD-013 Modern places the 5 shipyards on 5 distinct systems; Windows may stack them")
    func distinctShipyards() {
        for seed in UInt64(1)...25 {
            let s = makeEngine(.modern, seed: seed).state
            #expect(s.galaxy.systems.filter { $0.shipyard != nil }.count == 5, "seed \(seed)")
        }
        #expect(Ruleset.modern.flags.distinctShipyards && !Ruleset.windows201.flags.distinctShipyards)
        let stacked = (UInt64(1)...300).contains { makeEngine(.windows201, seed: $0).state.galaxy.systems.filter { $0.shipyard != nil }.count < 5 }
        #expect(stacked)
    }

    @Test("RUL-115 RUL-037 ECO-024 Wild's delivery: Modern ×100/90 only if criminal; Windows always; Palm never and record = max(record, 0)")
    func wildDelivery() {
        for id in [RulesetID.windows201, .modern, .palm122] {
            for record in [20, -10] {
                var e = makeEngine(id) { s in
                    var ship = freshShip(.wasp, s)
                    ship.weapons = [.beamLaser]
                    s.commander.ship = ship
                    s.commander.policeRecordScore = record
                    s.quests.wild = QuestStatus.Wild.started
                    s.hireCrew(CrewID.wild)
                    s.galaxy.systems[s.commander.currentSystem].specialEvent = .wildGetsOut
                    setMarket(&s, buy: 300, sell: 270)
                }
                let r = e.perform(.specialEvent, acknowledging: Set(WarningID.allCases))
                #expect(r.events.contains(.specialEventCompleted(.wildGetsOut)), "\(id) \(record)")
                let recalculated = id == .windows201 || (id == .modern && record < -5)
                #expect(e.state.sellPrices[0] == (recalculated ? 300 : 270), "\(id) \(record)")
                #expect(e.state.commander.policeRecordScore == (id == .palm122 ? max(record, 0) : 0))
            }
        }
    }

    @Test("RUL-115 ECO-024 Erase Record recalculates sell prices in every ruleset (it needs a criminal record)")
    func eraseRecord() {
        for id in [RulesetID.windows201, .modern, .palm122] {
            var e = makeEngine(id) { s in
                s.commander.cash = 50_000
                s.commander.policeRecordScore = -20
                s.galaxy.systems[s.commander.currentSystem].specialEvent = .eraseRecord
                setMarket(&s, buy: 300, sell: 270)
            }
            _ = e.perform(.specialEvent, acknowledging: Set(WarningID.allCases))
            #expect(e.state.commander.policeRecordScore == 0 && e.state.sellPrices[0] == 300)
        }
    }

    @Test("RUL-117 SHP-002 SHP-056 BNK-053 MOD-017 Modern uses Palm's fuel/repair columns; the wormhole tax follows the fuel cost")
    func fuelRepairColumns() {
        let fuel = [1, 2, 3, 5, 7, 10, 15, 15, 20, 20, 1, 1, 1, 1, 1]
        let repair = [1, 1, 1, 1, 1, 1, 2, 3, 4, 5, 1, 1, 1, 1, 1]
        let modern = makeEngine(.modern).state, windows = makeEngine(.windows201).state
        for (i, type) in ShipType.allCases.prefix(15).enumerated() {
            let m = Ship(type: type, spec: modern.ruleset.tables.ship(type)).spec(modern.ruleset)
            let w = Ship(type: type, spec: windows.ruleset.tables.ship(type)).spec(windows.ruleset)
            #expect(m.fuelCost == fuel[i] && m.repairCost == repair[i], "\(type)")
            #expect(w.fuelCost == repair[i] && w.repairCost == fuel[i], "\(type)")
        }
        let scorpion = Ship(type: .scorpion, spec: modern.ruleset.tables.ship(.scorpion)).spec(modern.ruleset)
        #expect(scorpion.fuelCost == 1 && scorpion.repairCost == 1)
        #expect(!Ruleset.palm122.flags.economy.swapFuelAndRepairColumns)
        func tax(_ s: GameState) -> Int {
            var s = s
            guard let w = s.galaxy.systems.indices.first(where: { s.galaxy.wormholeExists(from: s.commander.currentSystem, to: $0) })
            else { return -1 }
            s.warpSystem = w
            return s.wormholeCosts
        }
        func onWormhole(_ s: GameState) -> GameState {
            var s = s
            s.commander.currentSystem = s.galaxy.wormholes[0]
            return s
        }
        #expect(tax(onWormhole(modern)) == 50 && tax(onWormhole(windows)) == 25)
        var e = makeEngine(.modern) { $0.commander.ship.fuel = 10 }
        let cash = e.state.commander.cash
        _ = e.perform(.buyFuel(credits: 2))
        #expect(e.state.commander.ship.fuel == 11 && e.state.commander.cash == cash - 2)
    }

    @Test("RUL-118 BNK-036 BNK-037 MOD-018 debt warning and reminder: Windows exclusive; Modern both; Palm both on the normal path only")
    func debtNotices() {
        func notices(_ id: RulesetID, normal: Bool) -> [GameEvent] {
            var s = makeEngine(id) { s in
                s.commander.debt = 80_000
                s.commander.days = 10
                s.options.remindLoans = true
            }.state
            // The normal arrival vs the arrival after an arrest (no pod), TRV-062.
            return (normal ? s.arrival() : s.arrivalAfterArrestOrPod(pod: false)).filter {
                if case .debtWarning = $0 { return true }
                if case .debtReminder = $0 { return true }
                return false
            }
        }
        let both: [GameEvent] = [.debtWarning(debt: 80_000), .debtReminder(debt: 80_000)]
        #expect(notices(.windows201, normal: true) == [.debtWarning(debt: 80_000)])
        #expect(notices(.windows201, normal: false) == [.debtWarning(debt: 80_000)])
        #expect(notices(.modern, normal: true) == both && notices(.modern, normal: false) == both)
        #expect(notices(.palm122, normal: true) == both && notices(.palm122, normal: false).isEmpty)
    }

    @Test("RUL-119 BNK-005 BNK-006 BNK-009 SHP-032 MOD-019 worth: trade-in value + cost basis in Modern and Palm; list price in Windows")
    func worth() {
        for id in [RulesetID.windows201, .modern, .palm122] {
            var s = makeEngine(id).state
            let tradeIn = 10_000 * 3 / 4 + 2_000 * 3 / 4
            #expect(s.worth == (id == .windows201 ? 11_000 : tradeIn + 1_000))
            s.commander.priceCargo[1] = 900
            s.commander.debt = 300
            s.quests.moon = QuestStatus.Moon.bought
            let ship = id == .windows201 ? 10_000 : s.baseWorth(of: s.commander.ship, forInsurance: false) + 900
            #expect(s.worth == ship + 1_000 - 300 + 500_000)
            // Consumers read the same value (max loan).
            #expect(s.maxLoan == min(25_000, max(1_000, s.worth / 5_000 * 500)))
        }
    }
}
