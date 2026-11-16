// SPDX-License-Identifier: GPL-2.0-or-later
// QST-TRIBBLES {M4}: buying, selling, the arrival update, value and loss (docs/specs/QST-TRIBBLES.md).
import Testing
@testable import ParsecEngine

/// Advances `s.rng` until its next draws give exactly `draws` (bound, value) in order. Returns false if none found.
func m4ForceDraws(_ s: inout GameState, _ draws: [(below: Int, value: Int)], limit: Int = 500_000) -> Bool {
    for _ in 0..<limit {
        var probe = s.rng
        if draws.allSatisfy({ probe.next(below: $0.below) == $0.value }) { return true }
        _ = s.rng.next(below: 1_000)
    }
    return false
}

/// A docked state at the system holding `event` (moved there), with cash and the given tribbles.
private func atEvent(_ event: SpecialEventType, tribbles: Int = 0, cash: Int = 1_000,
                     _ adjust: (inout GameState) -> Void = { _ in }) -> GameEngine {
    makeEngine { s in
        let sys = s.galaxy.systems.firstIndex { $0.specialEvent == event } ?? s.commander.currentSystem
        s.commander.currentSystem = sys
        s.galaxy.systems[sys].specialEvent = event
        s.commander.ship.tribbles = tribbles
        s.commander.cash = cash
        s.options.reserveMoney = false
        adjust(&s)
    }
}

/// A docked state ready for `arrivalTribbles()` with tribbles and cargo.
private func tribbleState(_ t: Int, food: Int = 0, foodCost: Int = 0, narc: Int = 0, narcCost: Int = 0,
                          reactor: Bool = false) -> GameState {
    var s = makeEngine().state
    let f = TradeItemType.food.rawValue, n = TradeItemType.narcotics.rawValue
    s.commander.ship = freshShip(.wasp, s)
    s.commander.ship.tribbles = t
    s.commander.ship.cargo[f] = food
    s.commander.priceCargo[f] = foodCost
    s.commander.ship.cargo[n] = narc
    s.commander.priceCargo[n] = narcCost
    if reactor { s.quests.reactor = 5 }
    s.tribbleMessage = true
    return s
}

private func isTribbleEvent(_ e: GameEvent) -> Bool {
    switch e {
    case .tribblesChanged, .tribblesDied, .tribblesAteFood, .tribbleInspectorWarning: true
    default: false
    }
}

@Suite("Quest spec: tribbles, buying, selling and the arrival update (QST-TRIBBLES §1–3)")
struct QuestTribblesSpecTests {
    @Test("QST-TRIBBLES-001 Tribble: always shown, price 1000 with consent, sets T = 1, charges 1000 and is removed")
    func buyTribble() {
        var e = atEvent(.tribble, tribbles: 7, cash: 1_500)
        #expect(e.state.specialEventAvailable == .tribble)
        let sys = e.state.commander.currentSystem
        #expect(e.perform(.specialEvent).decision == .confirm(Confirmation(.acceptSpecialEvent, amounts: [1_000])))
        let r = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(r.events == [.specialEventCompleted(.tribble)])
        #expect(e.state.commander.ship.tribbles == 1)   // an assignment: 7 → 1
        #expect(e.state.commander.cash == 500 && e.state.galaxy.systems[sys].specialEvent == nil)
        var poor = atEvent(.tribble, cash: 999)
        #expect(poor.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).rejection == .insufficientFunds)
        // cashToSpend counts: Reserve Money with wages to reserve refuses 1000 cash.
        var reserved = atEvent(.tribble, cash: 1_000) { s in
            s.commander.ship = freshShip(.beetle, s)
            s.commander.ship.crew[1] = 1
            s.options.reserveMoney = true
        }
        #expect(reserved.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).rejection == .insufficientFunds)
    }

    @Test("QST-TRIBBLES-003 TribbleBuyer: shown iff T > 0, price 0, pays T / 2, sets T = 0, only this buyer is removed")
    func sellTribbles() {
        var e = atEvent(.tribbleBuyer, tribbles: 0, cash: 0)
        #expect(e.state.specialEventAvailable == nil)
        e.state.commander.ship.tribbles = 5_001
        #expect(e.state.specialEventAvailable == .tribbleBuyer)
        let here = e.state.commander.currentSystem
        let others = e.state.galaxy.systems.indices.filter { $0 != here && e.state.galaxy.systems[$0].specialEvent == .tribbleBuyer }
        #expect(!others.isEmpty)
        #expect(e.perform(.specialEvent).decision == .confirm(Confirmation(.acceptSpecialEvent, amounts: [0])))
        #expect(e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).events == [.specialEventCompleted(.tribbleBuyer)])
        #expect(e.state.commander.cash == 2_500 && e.state.commander.ship.tribbles == 0)
        #expect(e.state.galaxy.systems[here].specialEvent == nil)
        #expect(others.allSatisfy { e.state.galaxy.systems[$0].specialEvent == .tribbleBuyer })
    }

    @Test("QST-TRIBBLES-004 the newspaper lists every reachable TribbleBuyer whether or not the player has tribbles")
    func newspaperBuyers() throws {
        var s = makeEngine().state
        let w = try #require(s.destinations.first)
        s.galaxy.systems[w].specialEvent = .tribbleBuyer
        #expect(s.commander.ship.tribbles == 0)
        #expect(s.newspaper.headlines.contains(.tribbleBuyer(system: w)))
        s.commander.ship.tribbles = 50
        #expect(s.newspaper.headlines.contains(.tribbleBuyer(system: w)))
        let unreachable = try #require(unreachableTarget(s))
        s.galaxy.systems[unreachable].specialEvent = .tribbleBuyer
        #expect(!s.newspaper.headlines.contains(.tribbleBuyer(system: unreachable)))
    }

    @Test("QST-TRIBBLES-005 one branch only (reactor, else narcotics, else food), after an arrest too; tribblesChanged last")
    func updateBranches() {
        let f = TradeItemType.food.rawValue, n = TradeItemType.narcotics.rawValue
        var reactor = tribbleState(40, food: 5, narc: 5, reactor: true)
        let rEvents = reactor.arrivalTribbles()
        #expect(rEvents == [.tribblesDied(.halfFromReactor), .tribblesChanged(from: 40, to: 20)])
        #expect(reactor.commander.ship.cargo[f] == 5 && reactor.commander.ship.cargo[n] == 5 && !reactor.tribbleMessage)
        var narc = tribbleState(40, food: 5, narc: 5)
        let nEvents = narc.arrivalTribbles()
        #expect(narc.commander.ship.cargo[f] == 5 && narc.commander.ship.cargo[n] < 5 && !narc.tribbleMessage)
        #expect(nEvents.last == .tribblesChanged(from: 40, to: narc.commander.ship.tribbles) && nEvents.count == 2)
        var none = tribbleState(0, food: 5)
        let rng = none.rng
        #expect(none.arrivalTribbles().isEmpty && none.rng == rng && none.tribbleMessage)
        // The arrival after an arrest runs the update.
        var e = makeEngine { s in armDepartureFreeze(&s); s.commander.ship.tribbles = 10; s.commander.cash = 50_000 }
        _ = e.perform(.warp)
        let events = e.finishEncounter(.arrested)
        let tribble = events.filter(isTribbleEvent)
        #expect(tribble.last == .tribblesChanged(from: 10, to: e.state.commander.ship.tribbles))
        #expect(e.state.commander.ship.tribbles > 10)
    }

    @Test("QST-TRIBBLES-006 QST-TRIBBLES-020 reactor branch: < 20 all die, else half; no RNG, no growth, no warning")
    func reactorBranch() {
        var few = tribbleState(19, reactor: true)
        let rng = few.rng
        #expect(few.arrivalTribbles() == [.tribblesDied(.allFromReactor), .tribblesChanged(from: 19, to: 0)])
        #expect(few.commander.ship.tribbles == 0 && few.rng == rng)
        var many = tribbleState(40, reactor: true)
        #expect(many.arrivalTribbles() == [.tribblesDied(.halfFromReactor), .tribblesChanged(from: 40, to: 20)])
        #expect(many.rng == rng)
        // Crossing no threshold downward: 200 000 is never reached, 100 halves to 50 with no inspector warning.
        var hundred = tribbleState(100, reactor: true)
        #expect(hundred.arrivalTribbles() == [.tribblesDied(.halfFromReactor), .tribblesChanged(from: 100, to: 50)])
    }

    @Test("QST-TRIBBLES-007 QST-TRIBBLES-021 narcotics branch: draw order rand(3) then rand(5); furs gain, one survives")
    func narcoticsBranch() throws {
        var s = tribbleState(500, narc: 2, narcCost: 300)
        try #require(m4ForceDraws(&s, [(3, 2), (5, 4)]))
        let fursBasis = s.commander.priceCargo[TradeItemType.furs.rawValue]
        let events = s.arrivalTribbles()
        #expect(events == [.tribblesDied(.narcotics(converted: 2)), .tribblesChanged(from: 500, to: 296)])
        #expect(s.commander.ship.cargo[TradeItemType.narcotics.rawValue] == 0)
        #expect(s.commander.priceCargo[TradeItemType.narcotics.rawValue] == 0)
        #expect(s.commander.ship.cargo[TradeItemType.furs.rawValue] == 2)
        #expect(s.commander.priceCargo[TradeItemType.furs.rawValue] == fursBasis)
        // Partial conversion scales the basis; at least one tribble survives.
        var p = tribbleState(50, narc: 4, narcCost: 400)
        try #require(m4ForceDraws(&p, [(3, 0), (5, 0)]))
        _ = p.arrivalTribbles()
        #expect(p.commander.ship.cargo[TradeItemType.narcotics.rawValue] == 3)
        #expect(p.commander.priceCargo[TradeItemType.narcotics.rawValue] == 300)
        #expect(p.commander.ship.tribbles == 1)   // 50 − min(98, 49)
    }

    @Test("QST-TRIBBLES-008 QST-TRIBBLES-009 QST-TRIBBLES-011 food branch: eating, growth and the worked example")
    func foodBranch() throws {
        var s = tribbleState(10, food: 4, foodCost: 400)
        try #require(m4ForceDraws(&s, [(4, 1), (310, 9)]))
        let events = s.arrivalTribbles()
        #expect(events == [.tribblesAteFood(eaten: 3), .tribbleInspectorWarning(count: 320), .tribblesChanged(from: 10, to: 320)])
        #expect(s.commander.ship.cargo[TradeItemType.food.rawValue] == 1)
        #expect(s.commander.priceCargo[TradeItemType.food.rawValue] == 100)
        // T = 1 with no food: the bound is 0, a draw is still consumed and T becomes 2.
        var one = tribbleState(1)
        var probe = one.rng
        _ = probe.next(below: 0)
        #expect(one.arrivalTribbles() == [.tribblesChanged(from: 1, to: 2)])
        #expect(one.rng == probe)
        // No food: the bound is T / 2.
        var half = tribbleState(30)
        try #require(m4ForceDraws(&half, [(15, 14)]))
        _ = half.arrivalTribbles()
        #expect(half.commander.ship.tribbles == 45)
    }

    @Test("QST-TRIBBLES-010 the inspector warning fires once when 100, 1000, 10000, 50000 or exactly 100000 is crossed")
    func inspectorWarning() throws {
        func warnings(_ t: Int, _ draw: Int) throws -> [GameEvent] {
            var s = tribbleState(t)
            try #require(m4ForceDraws(&s, [(t / 2, draw)]))
            return s.arrivalTribbles().filter { if case .tribbleInspectorWarning = $0 { true } else { false } }
        }
        #expect(try warnings(98, 0) == [])   // 98 → 99
        #expect(try warnings(98, 1) == [.tribbleInspectorWarning(count: 100)])
        #expect(try warnings(100, 10) == [])
        #expect(try warnings(990, 20) == [.tribbleInspectorWarning(count: 1_011)])
        #expect(try warnings(9_990, 100) == [.tribbleInspectorWarning(count: 10_091)])
        #expect(try warnings(49_000, 2_000) == [.tribbleInspectorWarning(count: 51_001)])
        #expect(try warnings(60_000, 10) == [])
        // Two thresholds (100 and 1000) in one step still give one warning: 98 eat 10 food → 1098, then + 1 + 0.
        var both = tribbleState(98, food: 10, foodCost: 100)
        try #require(m4ForceDraws(&both, [(10, 0), (549, 0)]))
        #expect(both.arrivalTribbles() == [.tribblesAteFood(eaten: 10), .tribbleInspectorWarning(count: 1_099),
                                           .tribblesChanged(from: 98, to: 1_099)])
    }

    @Test("QST-TRIBBLES-022 cap: growth is clamped to 100000 and warns only when it lands there")
    func cap() throws {
        var s = tribbleState(99_990)
        try #require(m4ForceDraws(&s, [(49_995, 100)]))
        #expect(s.arrivalTribbles() == [.tribbleInspectorWarning(count: 100_000), .tribblesChanged(from: 99_990, to: 100_000)])
        var low = tribbleState(99_990)
        try #require(m4ForceDraws(&low, [(49_995, 5)]))
        #expect(low.arrivalTribbles() == [.tribblesChanged(from: 99_990, to: 99_996)])
        // At the cap: no draw, no growth, no warning.
        var full = tribbleState(100_000)
        let rng = full.rng
        #expect(full.arrivalTribbles() == [.tribblesChanged(from: 100_000, to: 100_000)] && full.rng == rng)
    }
}

@Suite("Quest spec: tribbles, value, trade and loss (QST-TRIBBLES §4–5)")
struct QuestTribblesLossSpecTests {
    @Test("QST-TRIBBLES-013 tribbles quarter the hull in trade-in value, not the insurance value nor the Windows worth")
    func tradeInValue() {
        var s = makeEngine().state
        let price = s.commander.ship.spec(s.ruleset).price
        let clean = s.baseWorth(of: s.commander.ship, forInsurance: false)
        let insured = s.baseWorth(of: s.commander.ship, forInsurance: true)
        let worth = s.worth
        s.commander.ship.tribbles = 3
        #expect(s.baseWorth(of: s.commander.ship, forInsurance: false) == clean - price * 3 / 4 + price / 4)
        #expect(s.baseWorth(of: s.commander.ship, forInsurance: true) == insured)
        #expect(s.worth == worth)
    }

    @Test("QST-TRIBBLES-014 tribbles only lower the shipyard trade-in; nothing is blocked and tribbleMessage is never read")
    func shipyardAdvisory() {
        func engine(tribbles: Int, message: Bool) -> GameEngine {
            makeEngine { s in
                s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech
                s.commander.cash = 100_000
                s.commander.ship.tribbles = tribbles
                s.tribbleMessage = message
            }
        }
        let clean = engine(tribbles: 0, message: false), infested = engine(tribbles: 10, message: false)
        let price = clean.state.commander.ship.spec(clean.ruleset).price
        #expect(infested.state.shipQuote(.firefly).netPrice == clean.state.shipQuote(.firefly).netPrice + price / 2)
        var buy = infested
        #expect(buy.perform(.buyShip(.firefly, transfers: []), acknowledging: [.buyShip]).rejection == nil)
        var a = engine(tribbles: 10, message: true), b = engine(tribbles: 10, message: false)
        let ra = a.perform(.buyShip(.firefly, transfers: []), acknowledging: [.buyShip])
        let rb = b.perform(.buyShip(.firefly, transfers: []), acknowledging: [.buyShip])
        #expect(ra == rb && a.state.commander == b.state.commander)
    }

    @Test("QST-TRIBBLES-015 a new ship from the shipyard or the designer starts with no tribbles")
    func newShip() {
        var e = makeEngine { s in
            s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech
            s.galaxy.systems[s.commander.currentSystem].shipyard = .sienar
            s.commander.cash = 100_000
            s.commander.ship.tribbles = 500
        }
        var designer = e
        _ = e.perform(.buyShip(.firefly, transfers: []), acknowledging: [.buyShip])
        #expect(e.state.commander.ship.type == .firefly && e.state.commander.ship.tribbles == 0)
        let d = ShipDesign(name: "Clean", size: .tiny, cargoBays: 10, fuelTanks: 15, hull: 10, weaponSlots: 1, shieldSlots: 0,
                           gadgetSlots: 1, crewQuarters: 1)
        let r = designer.perform(.buildDesign(d, transfers: []), acknowledging: [.buyShip])
        #expect(r.rejection == nil && designer.state.commander.ship.type == .custom && designer.state.commander.ship.tribbles == 0)
    }

    @Test("QST-TRIBBLES-016 arrest: a fine paid in cash keeps the tribbles; a ship sold for the fine leaves T = 0")
    func arrest() {
        var paid = makeEngine { s in s.commander.cash = 100_000; s.commander.ship.tribbles = 77 }.state
        let events = paid.arrested()
        #expect(events.contains { if case .arrested(_, _, false) = $0 { true } else { false } })
        #expect(paid.commander.ship.tribbles == 77)
        var sold = makeEngine { s in s.commander.cash = 0; s.commander.ship.tribbles = 77 }.state
        let soldEvents = sold.arrested()
        #expect(soldEvents.contains { if case .arrested(_, _, true) = $0 { true } else { false } })
        #expect(sold.commander.ship.tribbles == 0)
        #expect(!soldEvents.contains(where: isTribbleEvent))   // derived by the app (ALR-176), no own event
    }

    @Test("QST-TRIBBLES-017 the escape pod's Flea has no tribbles; no separate event")
    func escapePod() {
        var s = makeEngine { s in s.commander.ship.tribbles = 300; s.commander.ship.escapePod = true }.state
        let events = s.escapeWithPod()
        #expect(s.commander.ship.type == .flea && s.commander.ship.tribbles == 0)
        #expect(!events.contains(where: isTribbleEvent))
    }

    @Test("QST-TRIBBLES-018 tribbles are not cargo: no bays, no effect on inspections or loot, none on opponents, IncDays keeps T")
    func notCargo() {
        let base = makeEngine().state
        var s = base
        s.commander.ship.tribbles = 10_000
        #expect(s.freeCargoBays == base.freeCargoBays && s.filledCargoBays == base.filledCargoBays)
        #expect(s.inspectionFine == base.inspectionFine && s.bribeAmount == base.bribeAmount)
        #expect(s.detectableIllegalCargoOrPassengers == base.detectableIllegalCargoOrPassengers)
        _ = s.incDays(5)
        #expect(s.commander.ship.tribbles == 10_000)
        var gen = s
        #expect(gen.generateOpponent(.pirate).tribbles == 0 && gen.generateOpponent(.trader).tribbles == 0)
        // Pirate surrender with tribbles and some cargo: cargo is looted, tribbles stay.
        var e = m4EncounterEngine(.pirateAttack, opponent: .wasp) { s, _ in
            s.commander.ship.tribbles = 10_000
            s.commander.ship.cargo[TradeItemType.water.rawValue] = 2
            s.commander.priceCargo[TradeItemType.water.rawValue] = 60
        }
        let r = e.perform(.encounter(.surrender))
        #expect(r.events.contains { if case .looted = $0 { true } else { false } })
        // The trip then arrives; the only change to T is the arrival update, which starts from the untouched 10 000.
        let changes = r.events.compactMap { ev -> (Int, Int)? in if case let .tribblesChanged(a, b) = ev { (a, b) } else { nil } }
        #expect(changes.count == 1 && changes.first?.0 == 10_000 && changes.first?.1 == e.state.commander.ship.tribbles)
    }

    @Test("QST-TRIBBLES-019 scenario: buy (and the 999 refusal), grow on real arrivals, sell to a buyer")
    func buyGrowSell() throws {
        var refused = atEvent(.tribble, cash: 999)
        #expect(refused.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).rejection == .insufficientFunds)
        var e = atEvent(.tribble, cash: 1_000)
        _ = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(e.state.commander.ship.tribbles == 1 && e.state.commander.cash == 0)
        var last = 1
        for _ in 0..<4 {
            e.state.commander.ship.fuel = e.state.commander.ship.fuelTanks(e.ruleset)
            let t = try #require(plainTarget(e.state))
            _ = e.perform(.selectTarget(t))
            let trip = completeTrip(&e)
            #expect(e.state.phase == .docked && e.state.commander.currentSystem == t)
            let changed = trip.events.compactMap { ev -> (Int, Int)? in if case let .tribblesChanged(a, b) = ev { (a, b) } else { nil } }
            #expect(changed.count == 1 && changed.first?.0 == last)
            last = e.state.commander.ship.tribbles
        }
        #expect(last > 1)
        // A buyer at the current system pays T / 2; the others stay but are hidden while T == 0.
        let here = e.state.commander.currentSystem
        e.state.galaxy.systems[here].specialEvent = .tribbleBuyer
        let other = try #require(e.state.galaxy.systems.indices.first { $0 != here && e.state.galaxy.systems[$0].specialEvent == .tribbleBuyer })
        let cash = e.state.commander.cash
        _ = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(e.state.commander.cash == cash + last / 2 && e.state.commander.ship.tribbles == 0)
        #expect(e.state.galaxy.systems[here].specialEvent == nil)
        var there = e
        there.state.commander.currentSystem = other
        #expect(there.state.galaxy.systems[other].specialEvent == .tribbleBuyer && there.state.specialEventAvailable == nil)
        // The 5001 → 2500 case of the bullet.
        var buyer = atEvent(.tribbleBuyer, tribbles: 5_001, cash: 0)
        _ = buyer.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(buyer.state.commander.cash == 2_500 && buyer.state.commander.ship.tribbles == 0)
    }

    @Test("QST-TRIBBLES-023 loss: a new ship and the escape pod leave T = 0; an arrest paid in cash keeps T")
    func losses() {
        var ship = makeEngine { s in
            s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech
            s.commander.cash = 100_000
            s.commander.ship.tribbles = 40
        }
        _ = ship.perform(.buyShip(.firefly, transfers: []), acknowledging: [.buyShip])
        #expect(ship.state.commander.ship.tribbles == 0)
        var pod = makeEngine { s in armDepartureFreeze(&s); s.commander.ship.tribbles = 40; s.commander.ship.escapePod = true }
        _ = pod.perform(.warp)
        _ = pod.finishEncounter(.escapePod)
        #expect(pod.state.commander.ship.type == .flea && pod.state.commander.ship.tribbles == 0)
        var jail = makeEngine { s in s.commander.cash = 100_000; s.commander.ship.tribbles = 40 }.state
        _ = jail.arrested()
        #expect(jail.commander.ship.tribbles == 40)
    }
}
