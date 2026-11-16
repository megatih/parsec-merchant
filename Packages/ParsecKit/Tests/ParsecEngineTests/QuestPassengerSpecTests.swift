// SPDX-License-Identifier: GPL-2.0-or-later
// QST-JAREK (docs/specs/QST-JAREK.md) and the M4 CRW quest bullets (CRW-042, CRW-063…067). Shared quest-trip helpers
// for the Jarek, Wild and reactor suites live in `QuestTrip`.
import Testing
@testable import ParsecEngine

/// Builders for the passenger and reactor quest scenarios: a docked engine with an offer, and real warps.
enum QuestTrip {
    static let yes = Set(WarningID.allCases)
    /// Quest destinations a filler hop must not land on by accident.
    static let questSystems: Set<Int> = [SystemID.devidia, SystemID.kravat, SystemID.nix]

    /// A docked Normal game with cash, no debt, reputation 40 and `event` offered at the current system.
    static func engine(_ event: SpecialEventType? = nil, difficulty: Difficulty = .normal,
                       _ adjust: (inout GameState) -> Void = { _ in }) -> GameEngine {
        var e = makeEngine(difficulty: difficulty) { s in
            s.commander.cash = 200_000
            s.commander.debt = 0
            s.commander.reputationScore = 40
        }
        if let event { e.state.galaxy.systems[e.state.commander.currentSystem].specialEvent = event }
        adjust(&e.state)
        return e
    }

    /// A fresh ship of `type` with the commander aboard and the given weapons.
    static func ship(_ type: ShipType, _ s: GameState, weapons: [WeaponType] = []) -> Ship {
        var ship = freshShip(type, s)
        ship.weapons = weapons
        return ship
    }

    /// One normal warp (refuelled first) to a reachable non-quest system; every encounter ends normally.
    static func hop(_ e: inout GameEngine, ack: Set<WarningID> = [], sourceLocation: SourceLocation = #_sourceLocation) -> [GameEvent] {
        e.state.commander.ship.fuel = e.state.commander.ship.fuelTanks(e.ruleset)
        let s = e.state
        guard let d = s.destinations.first(where: {
            !questSystems.contains($0) && !s.galaxy.wormholeExists(from: s.commander.currentSystem, to: $0)
        }) else {
            Issue.record("no destination", sourceLocation: sourceLocation)
            return []
        }
        e.state.warpSystem = d
        return completeTrip(&e, .warp, ack: ack).events
    }

    /// Places the commander on a neighbour of `target` and makes one normal warp there (one departure, one IncDays).
    static func travel(_ e: inout GameEngine, to target: Int, ack: Set<WarningID> = [],
                       sourceLocation: SourceLocation = #_sourceLocation) -> [GameEvent] {
        let s = e.state
        let tanks = s.commander.ship.fuelTanks(e.ruleset)
        guard let n = s.galaxy.systems.indices.first(where: {
            $0 != target && !questSystems.contains($0) && !s.galaxy.wormholeExists(from: $0, to: target)
                && GalaxyGenerator.distance(s.galaxy.systems[$0], s.galaxy.systems[target], rule: e.ruleset.flags.distance) <= tanks
        }) else {
            Issue.record("no neighbour of \(target)", sourceLocation: sourceLocation)
            return []
        }
        e.state.commander.currentSystem = n
        e.state.commander.ship.fuel = tanks
        e.state.warpSystem = target
        return completeTrip(&e, .warp, ack: ack).events
    }

    /// Runs `incDays(1)` `calls` times and returns the events of each call.
    static func dayCalls(_ s: inout GameState, _ calls: Int) -> [[GameEvent]] {
        (0..<calls).map { _ in s.incDays(1) }
    }

    static func isArrest(_ e: GameEvent) -> Bool { if case .arrested = e { true } else { false } }
    static func isPod(_ e: GameEvent) -> Bool { if case .escapePodUsed = e { true } else { false } }
    static func isNotice(_ e: GameEvent) -> Bool {
        switch e {
        case .passengerConcerned, .passengerImpatient: true
        default: false
        }
    }
}

private let jarek = CrewID.jarek

// MARK: QST-JAREK §1-3

@Suite("QST-JAREK: statuses, button, boarding")
struct QuestJarekBoardingSpecTests {
    @Test("QST-JAREK-001 statuses 0/1/11/12; a new game starts at 0")
    func statuses() {
        #expect([QuestStatus.Jarek.notStarted, QuestStatus.Jarek.started, QuestStatus.Jarek.impatient, QuestStatus.Jarek.done]
            == [0, 1, 11, 12])
        for seed in UInt64(0)..<5 { #expect(makeEngine(seed: seed).state.quests.jarek == 0) }
    }

    @Test("QST-JAREK-002 jarek on one random system (needs consent [0]), jarekGetsOut fixed at Devidia (message-only)")
    func eventsAndRows() throws {
        let rows = makeEngine().state
        let start = try #require(rows.specialEventSpec(.jarek)), out = try #require(rows.specialEventSpec(.jarekGetsOut))
        #expect(start.price == 0 && start.occurrence == 1 && !start.messageOnly)
        #expect(out.price == 0 && out.occurrence == 0 && out.messageOnly)
        var placed = 0
        for seed in UInt64(0)..<20 {
            let s = makeEngine(seed: seed).state
            #expect(s.galaxy.systems[SystemID.devidia].specialEvent == .jarekGetsOut)
            let count = s.galaxy.systems.filter { $0.specialEvent == .jarek }.count
            #expect(count <= 1)
            placed += count
        }
        #expect(placed > 0)
        var e = QuestTrip.engine(.jarek) { $0.commander.ship = QuestTrip.ship(.wasp, $0) }
        let before = e.state
        #expect(e.perform(.specialEvent).decision == .confirm(Confirmation(.acceptSpecialEvent, amounts: [0])))
        #expect(e.state == before)
        var g = QuestTrip.engine(.jarekGetsOut) { $0.commander.ship = QuestTrip.ship(.wasp, $0); $0.hireCrew(jarek) }
        #expect(g.perform(.specialEvent).events.last == .specialEventCompleted(.jarekGetsOut))
    }

    @Test("QST-JAREK-003 jarekOnBoard is crew member 33 in the crew array, whatever the status")
    func onBoard() {
        var s = QuestTrip.engine { $0.commander.ship = QuestTrip.ship(.wasp, $0) }.state
        s.quests.jarek = 5
        #expect(!s.jarekOnBoard)
        s.hireCrew(jarek)
        s.quests.jarek = 0
        #expect(s.jarekOnBoard)
        s.quests.jarek = QuestStatus.Jarek.done
        #expect(s.jarekOnBoard)
    }

    @Test("QST-JAREK-004 jarek needs record ≥ −5; jarekGetsOut needs Jarek aboard")
    func button() {
        for (record, shown) in [(-5, true), (-6, false), (10, true)] {
            let s = QuestTrip.engine(.jarek) { $0.commander.policeRecordScore = record }.state
            #expect((s.specialEventAvailable == .jarek) == shown, "record \(record)")
        }
        var s = QuestTrip.engine(.jarekGetsOut) { $0.commander.ship = QuestTrip.ship(.wasp, $0) }.state
        #expect(s.specialEventAvailable == nil)
        s.hireCrew(jarek)
        #expect(s.specialEventAvailable == .jarekGetsOut)
    }

    @Test("QST-JAREK-006 boarding: noFreeQuarters keeps the offer; else first free slot, status 1, removed, prices follow")
    func boarding() {
        var e = QuestTrip.engine(.jarek) { $0.commander.ship = QuestTrip.ship(.gnat, $0) }
        let before = e.state
        #expect(e.perform(.specialEvent, acknowledging: QuestTrip.yes).rejection == .noFreeQuarters)
        #expect(e.state == before && e.state.specialEventAvailable == .jarek)
        e = QuestTrip.engine(.jarek) { s in
            s.commander.ship = QuestTrip.ship(.wasp, s)
            s.mercenaries[CrewID.commander].skills = [5, 5, 5, 5]
            setMarket(&s, buy: 2_000, sell: 1_000)
        }
        let r = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(r.events == [.specialEventCompleted(.jarek)])
        #expect(e.state.commander.ship.crew == [CrewID.commander, jarek, nil])
        #expect(e.state.quests.jarek == QuestStatus.Jarek.started && e.state.currentSystem.specialEvent == nil)
        #expect(e.state.skill(.trader) == 10)
        var ref = e.state
        ref.recalculateBuyPricesHere()
        #expect(e.state.buyPrices == ref.buyPrices && e.state.buyPrices != Array(repeating: 2_000, count: 10))
    }

    @Test("QST-JAREK-007 aboard: crew skills 3/2/10/4, wage 0, a quarter, cannot be fired, needs quarters on a trade, moves along")
    func aboard() {
        var e = QuestTrip.engine { s in
            s.commander.ship = QuestTrip.ship(.bumblebee, s)
            s.mercenaries[CrewID.commander].skills = [1, 1, 1, 1]
            s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech
            s.hireCrew(jarek)
        }
        #expect(e.state.mercenaries[jarek].skills == [3, 2, 10, 4])
        #expect(e.state.shipSkills == [3, 2, 10, 4])
        #expect(e.state.dailyRate(of: jarek) == 0 && e.state.mercenaryCosts == 0)
        #expect(e.state.commander.ship.freeQuarters == 0)
        #expect(e.perform(.fire(crewID: jarek), acknowledging: QuestTrip.yes).rejection == .cannotFireSpecialPassenger)
        #expect(e.perform(.buyShip(.firefly, transfers: []), acknowledging: QuestTrip.yes).rejection == .passengersNeedQuarters)
        #expect(e.perform(.buyShip(.hornet, transfers: []), acknowledging: QuestTrip.yes).rejection == nil)
        #expect(e.state.commander.ship.type == .hornet && e.state.commander.ship.crew == [CrewID.commander, jarek])
    }
}

// MARK: QST-JAREK §4 Impatience

@Suite("QST-JAREK: impatience")
struct QuestJarekImpatienceSpecTests {
    @Test("QST-JAREK-009 QST-JAREK-020 per IncDays call: concerned at 5, impatient (skills 0) at 10, then stays 11")
    func impatience() {
        var s = QuestTrip.engine { $0.commander.ship = QuestTrip.ship(.wasp, $0) }.state
        s.hireCrew(jarek)
        s.quests.jarek = QuestStatus.Jarek.started
        let calls = QuestTrip.dayCalls(&s, 12)
        for (i, events) in calls.enumerated() {
            let notices = events.filter(QuestTrip.isNotice)
            switch i + 1 {
            case 5: #expect(notices == [.passengerConcerned(crewID: jarek)])
            case 10: #expect(notices == [.passengerImpatient(crewID: jarek)])
            default: #expect(notices.isEmpty, "call \(i + 1)")
            }
        }
        #expect(s.quests.jarek == QuestStatus.Jarek.impatient && s.mercenaries[jarek].skills == [0, 0, 0, 0])
        // QST-JAREK-020: the call that finds 10 is the impatient one and leaves 11; a long IncDays still counts once.
        var t = QuestTrip.engine { $0.commander.ship = QuestTrip.ship(.wasp, $0) }.state
        t.hireCrew(jarek)
        t.quests.jarek = 9
        #expect(t.incDays(30).filter(QuestTrip.isNotice).isEmpty && t.quests.jarek == 10)
        #expect(t.mercenaries[jarek].skills == [3, 2, 10, 4])
        #expect(t.incDays(3).filter(QuestTrip.isNotice) == [.passengerImpatient(crewID: jarek)] && t.quests.jarek == 11)
        // No notice and no counting without Jarek aboard.
        var u = QuestTrip.engine().state
        u.quests.jarek = 5
        #expect(u.incDays(1).filter(QuestTrip.isNotice).isEmpty && u.quests.jarek == 5)
    }

    @Test("QST-JAREK-010 impatience never fails the quest; zeroed skills stay; no buy-price recalculation on the drop")
    func neverFails() {
        var e = QuestTrip.engine(.jarekGetsOut) { s in
            s.commander.ship = QuestTrip.ship(.wasp, s)
            s.mercenaries[CrewID.commander].skills = [5, 5, 5, 5]
            setMarket(&s)
            s.hireCrew(jarek)
            s.quests.jarek = 10
        }
        let prices = e.state.buyPrices
        _ = e.state.incDays(1)
        #expect(e.state.skill(.trader) == 5 && e.state.buyPrices == prices)
        #expect(e.state.specialEventAvailable == .jarekGetsOut)
        _ = e.perform(.specialEvent)
        #expect(e.state.quests.jarek == QuestStatus.Jarek.done && e.state.mercenaries[jarek].skills == [0, 0, 0, 0])
    }
}

// MARK: QST-JAREK §5 Delivery

@Suite("QST-JAREK: delivery and the haggling computer")
struct QuestJarekDeliverySpecTests {
    @Test("QST-JAREK-012 jarekGetsOut: status 12, Fire shifts later crew up, removed; prices only if the Trader changes")
    func delivery() {
        func deliver(commanderTrader: Int) -> GameEngine {
            var e = QuestTrip.engine(.jarekGetsOut) { s in
                s.commander.ship = QuestTrip.ship(.wasp, s)
                s.mercenaries[CrewID.commander].skills = [1, 1, commanderTrader, 1]
                s.mercenaries[1].skills = [1, 1, 1, 1]
                s.hireCrew(jarek)
                s.hireCrew(1)
                s.quests.jarek = 4
                setMarket(&s, buy: 7, sell: 90)
            }
            let rng = e.state.rng, home = e.state.mercenaries[jarek].systemID
            #expect(e.perform(.specialEvent).events == [.specialEventCompleted(.jarekGetsOut)])
            #expect(e.state.commander.ship.crew == [CrewID.commander, 1, nil])
            #expect(e.state.quests.jarek == QuestStatus.Jarek.done && e.state.currentSystem.specialEvent == nil)
            #expect(e.state.rng == rng && e.state.mercenaries[jarek].systemID == home)
            return e
        }
        // Trader 10 with Jarek and bonus = 11; 9 + 1 = 10 without him: recalculated.
        let changed = deliver(commanderTrader: 9)
        var ref = changed.state
        ref.recalculateBuyPricesHere()
        #expect(changed.state.buyPrices == ref.buyPrices && changed.state.buyPrices != Array(repeating: 7, count: 10))
        // Commander Trader 10: 11 before and after his removal, so the (stale) prices are kept.
        #expect(deliver(commanderTrader: 10).state.buyPrices == Array(repeating: 7, count: 10))
    }

    @Test("QST-JAREK-013 from status 12 the effective Trader is the adjusted best + 1: 1000 buys at 1050, not 1060")
    func haggling() throws {
        var s = QuestTrip.engine { s in s.mercenaries[CrewID.commander].skills = [5, 5, 7, 5] }.state
        #expect(s.skill(.trader) == 7)
        let sell = Array(repeating: 1_000, count: 10)
        let without = Pricing.buyPrices(sell: sell, in: s.currentSystem, criminal: false, traderSkill: s.skill(.trader), ruleset: s.ruleset)
        s.quests.jarek = QuestStatus.Jarek.done
        #expect(s.skill(.trader) == 8 && s.shipSkills[SkillType.trader.rawValue] == 7)
        let with = Pricing.buyPrices(sell: sell, in: s.currentSystem, criminal: false, traderSkill: s.skill(.trader), ruleset: s.ruleset)
        let traded = try #require(without.firstIndex { $0 > 0 })
        #expect(without[traded] == 1_060 && with[traded] == 1_050)
        // Difficulty-adjusted first: Hard lowers 7 to 6, then the bonus gives 7.
        var hard = QuestTrip.engine(difficulty: .hard) { s in s.mercenaries[CrewID.commander].skills = [5, 5, 7, 5] }.state
        hard.quests.jarek = QuestStatus.Jarek.done
        #expect(hard.skill(.trader) == 7)
    }

    @Test("QST-JAREK-014 the bonus is permanent: it survives arrest, ship trades, the escape pod and a ship sold on arrest")
    func permanent() {
        var e = Pol.engine(.policeAttack) { s in
            s.quests.jarek = QuestStatus.Jarek.done
            s.mercenaries[CrewID.commander].skills = [5, 5, 5, 5]
            s.commander.cash = 0 // the fine sells the ship
        }
        let r = e.perform(.encounter(.surrender), acknowledging: QuestTrip.yes)
        #expect(r.events.contains(.arrested(term: 30, fine: 500, shipSold: true)))
        #expect(e.state.commander.ship.type == .flea && e.state.quests.jarek == QuestStatus.Jarek.done && e.state.skill(.trader) == 6)
        var pod = Pol.engine(.pirateAttack) { s in
            s.quests.jarek = QuestStatus.Jarek.done
            s.commander.ship.escapePod = true
            s.mercenaries[CrewID.commander].skills = [5, 5, 5, 5]
        }
        _ = pod.finishEncounter(.escapePod)
        #expect(pod.state.commander.ship.type == .flea && pod.state.quests.jarek == QuestStatus.Jarek.done && pod.state.skill(.trader) == 6)
        var trade = QuestTrip.engine { s in
            s.quests.jarek = QuestStatus.Jarek.done
            s.mercenaries[CrewID.commander].skills = [5, 5, 5, 5]
            s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech
        }
        #expect(trade.perform(.buyShip(.hornet, transfers: []), acknowledging: QuestTrip.yes).rejection == nil)
        #expect(trade.state.quests.jarek == QuestStatus.Jarek.done && trade.state.skill(.trader) == 6)
    }
}

// MARK: QST-JAREK §6-8 Failures, news, scenarios

@Suite("QST-JAREK: failures, news and scenarios")
struct QuestJarekScenarioSpecTests {
    @Test("QST-JAREK-016 arrest: alone he stays with status 0 → 1 and can still be delivered; with ≥ 2 mercenaries he leaves, status kept")
    func arrest() {
        var e = Pol.engine(.policeAttack) { s in
            s.commander.ship = QuestTrip.ship(.wasp, s)
            s.commander.cash = 50_000
            s.hireCrew(jarek)
            s.quests.jarek = 4
        }
        let r = e.perform(.encounter(.surrender), acknowledging: QuestTrip.yes)
        #expect(r.events.contains(where: QuestTrip.isArrest))
        #expect(e.state.jarekOnBoard && e.state.quests.jarek == 1)
        e.state.galaxy.systems[e.state.commander.currentSystem].specialEvent = .jarekGetsOut
        _ = e.perform(.specialEvent)
        #expect(e.state.quests.jarek == QuestStatus.Jarek.done)
        // Two ordinary mercenaries: the crew is cleared in the mercenary step, before the Jarek step.
        var m = Pol.engine(.policeAttack) { s in
            var spec = s.ruleset.tables.ship(.wasp)
            spec.crewQuarters = 4
            var ship = Ship(type: .custom, spec: spec)
            ship.customSpec = spec
            ship.crew[0] = CrewID.commander
            s.commander.ship = ship
            s.commander.cash = 50_000
            s.hireCrew(jarek)
            s.hireCrew(1)
            s.hireCrew(2)
            s.quests.jarek = 4
        }
        _ = m.perform(.encounter(.surrender), acknowledging: QuestTrip.yes)
        #expect(m.state.commander.ship.crew == [CrewID.commander, nil, nil, nil] && m.state.quests.jarek == 4)
        m.state.galaxy.systems[m.state.commander.currentSystem].specialEvent = .jarekGetsOut
        #expect(m.state.specialEventAvailable == nil)
    }

    @Test("QST-JAREK-017 escape pod: status 0, the pod's IncDays(3) makes it 1, the Flea leaves him behind; quest lost")
    func pod() {
        var e = Pol.engine(.pirateAttack) { s in
            s.commander.ship = QuestTrip.ship(.wasp, s)
            s.commander.ship.escapePod = true
            s.hireCrew(jarek)
            s.quests.jarek = 6
        }
        let events = e.finishEncounter(.escapePod)
        #expect(events.contains(where: QuestTrip.isPod))
        #expect(e.state.quests.jarek == 1 && !e.state.jarekOnBoard && e.state.commander.ship.type == .flea)
        e.state.galaxy.systems[e.state.commander.currentSystem].specialEvent = .jarekGetsOut
        #expect(e.state.specialEventAvailable == nil)
    }

    @Test("QST-JAREK-019 arriving at Devidia with Jarek aboard adds the jarekGetsOut headline")
    func news() {
        var e = QuestTrip.engine { s in s.commander.ship = QuestTrip.ship(.wasp, s); s.hireCrew(jarek); s.quests.jarek = 1 }
        _ = QuestTrip.travel(&e, to: SystemID.devidia)
        #expect(e.state.commander.currentSystem == SystemID.devidia && e.state.newsEvents.contains(.jarekGetsOut))
        var none = QuestTrip.engine { s in s.commander.ship = QuestTrip.ship(.wasp, s) }
        _ = QuestTrip.travel(&none, to: SystemID.devidia)
        #expect(none.state.commander.currentSystem == SystemID.devidia && !none.state.newsEvents.contains(.jarekGetsOut))
    }

    @Test("QST-JAREK-021 scenario: board, 10 warps (concerned 5, impatient 10), deliver at Devidia, Trader 6 even after a ship trade")
    func happyPath() {
        var e = QuestTrip.engine(.jarek) { s in
            s.commander.ship = QuestTrip.ship(.bumblebee, s)
            s.commander.policeRecordScore = 0
            s.mercenaries[CrewID.commander].skills = [5, 5, 5, 5]
            setMarket(&s)
        }
        let prices = e.state.buyPrices
        _ = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(e.state.jarekOnBoard && e.state.quests.jarek == 1 && e.state.skill(.trader) == 10 && e.state.buyPrices != prices)
        for warp in 1...10 {
            let notices = QuestTrip.hop(&e).filter(QuestTrip.isNotice)
            switch warp {
            case 5: #expect(notices == [.passengerConcerned(crewID: jarek)])
            case 10: #expect(notices == [.passengerImpatient(crewID: jarek)])
            default: #expect(notices.isEmpty, "warp \(warp)")
            }
        }
        #expect(e.state.mercenaries[jarek].skills == [0, 0, 0, 0] && e.state.quests.jarek == QuestStatus.Jarek.impatient)
        _ = QuestTrip.travel(&e, to: SystemID.devidia)
        #expect(e.state.newsEvents.contains(.jarekGetsOut) && e.state.specialEventAvailable == .jarekGetsOut)
        _ = e.perform(.specialEvent)
        #expect(e.state.quests.jarek == QuestStatus.Jarek.done && !e.state.jarekOnBoard && e.state.skill(.trader) == 6)
        e.state.galaxy.systems[e.state.commander.currentSystem].techLevel = .hiTech
        #expect(e.perform(.buyShip(.hornet, transfers: []), acknowledging: QuestTrip.yes).rejection == nil)
        #expect(e.state.skill(.trader) == 6)
    }

    @Test("QST-JAREK-022 scenario failures: no quarter, record −6, arrest alone, arrest with two mercenaries, pod")
    func failures() {
        // (a) No free quarter.
        var a = QuestTrip.engine(.jarek) { $0.commander.ship = QuestTrip.ship(.gnat, $0) }
        let before = a.state
        #expect(a.perform(.specialEvent, acknowledging: QuestTrip.yes).rejection == .noFreeQuarters && a.state == before)
        // (b) Record −6 hides the start.
        #expect(QuestTrip.engine(.jarek) { $0.commander.policeRecordScore = -6 }.state.specialEventAvailable == nil)
        // (c) Arrested alone: status 0 then 1 after the jail days; still aboard; delivery at Devidia gives 12.
        var c = Pol.engine(.policeAttack) { s in
            s.commander.ship = QuestTrip.ship(.wasp, s)
            s.commander.cash = 50_000
            s.hireCrew(jarek)
            s.quests.jarek = 3
        }
        #expect(c.perform(.encounter(.surrender), acknowledging: QuestTrip.yes).events.contains(where: QuestTrip.isArrest))
        #expect(c.state.quests.jarek == 1 && c.state.jarekOnBoard)
        _ = QuestTrip.travel(&c, to: SystemID.devidia)
        _ = c.perform(.specialEvent)
        #expect(c.state.quests.jarek == QuestStatus.Jarek.done && !c.state.jarekOnBoard)
        // (d) Two mercenaries in a 4-quarter custom ship: everyone leaves, status unchanged, no button at Devidia.
        var d = Pol.engine(.policeAttack) { s in
            var spec = s.ruleset.tables.ship(.wasp)
            spec.crewQuarters = 4
            var ship = Ship(type: .custom, spec: spec)
            ship.customSpec = spec
            ship.crew[0] = CrewID.commander
            s.commander.ship = ship
            s.commander.cash = 50_000
            s.hireCrew(jarek)
            s.hireCrew(1)
            s.hireCrew(2)
            s.quests.jarek = 3
        }
        _ = d.perform(.encounter(.surrender), acknowledging: QuestTrip.yes)
        #expect(d.state.quests.jarek == 3 && !d.state.jarekOnBoard)
        _ = QuestTrip.travel(&d, to: SystemID.devidia)
        #expect(d.state.commander.currentSystem == SystemID.devidia && d.state.specialEventAvailable == nil)
        // (e) Pod: final status 1, Jarek not in the Flea's crew.
        var p = Pol.engine(.pirateAttack) { s in
            s.commander.ship = QuestTrip.ship(.wasp, s)
            s.commander.ship.escapePod = true
            s.hireCrew(jarek)
            s.quests.jarek = 3
        }
        #expect(p.finishEncounter(.escapePod).contains(where: QuestTrip.isPod))
        #expect(p.state.quests.jarek == 1 && p.state.commander.ship.crew == [CrewID.commander])
    }
}

// MARK: CRW quest bullets

@Suite("CRW: special crew and quest skill rewards")
struct QuestCrewSpecTests {
    @Test("CRW-042 Wild, Jarek and the Princess board with Hire (first free slot, noFreeQuarters) and leave with Fire, no relocation")
    func specialCrew() {
        let cases: [(SpecialEventType, SpecialEventType, Int, (inout GameState) -> Void)] = [
            (.jarek, .jarekGetsOut, jarek, { _ in }),
            (.wild, .wildGetsOut, CrewID.wild, { $0.commander.policeRecordScore = -10 }),
            (.princessQonos, .princessReturned, CrewID.princess, { $0.quests.princess = QuestStatus.Princess.rescued }),
        ]
        for (board, leave, id, adjust) in cases {
            var full = QuestTrip.engine(board) { s in s.commander.ship = QuestTrip.ship(.gnat, s, weapons: [.beamLaser]); adjust(&s) }
            #expect(full.perform(.specialEvent, acknowledging: QuestTrip.yes).rejection == .noFreeQuarters, "\(board)")
            var e = QuestTrip.engine(board) { s in
                s.commander.ship = QuestTrip.ship(.wasp, s, weapons: [.beamLaser])
                s.mercenaries[1].skills = [1, 1, 1, 1]
                s.hireCrew(1)
                adjust(&s)
            }
            _ = e.perform(.specialEvent, acknowledging: QuestTrip.yes)
            #expect(e.state.commander.ship.crew == [CrewID.commander, 1, id], "\(board)")
            e.state.galaxy.systems[e.state.commander.currentSystem].specialEvent = leave
            let rng = e.state.rng, home = e.state.mercenaries[id].systemID
            _ = e.perform(.specialEvent, acknowledging: QuestTrip.yes)
            #expect(e.state.commander.ship.crew == [CrewID.commander, 1, nil], "\(leave)")
            #expect(e.state.mercenaries[id].systemID == home, "\(leave) does not relocate")
            if leave != .wildGetsOut { #expect(e.state.rng == rng, "\(leave) draws nothing") }
        }
    }

    @Test("CRW-063 the Japori delivery calls IncreaseRandomSkill twice")
    func japori() {
        for seed in UInt64(0)..<10 {
            var e = QuestTrip.engine(.japoriDelivery) { s in s.quests.japori = QuestStatus.Japori.inTransit }
            e.state.rng = makeEngine(seed: seed).state.rng
            var ref = e.state
            ref.changeRandomSkill(1)
            ref.changeRandomSkill(1)
            let total = e.state.mercenaries[CrewID.commander].skills.reduce(0, +)
            _ = e.perform(.specialEvent)
            #expect(e.state.mercenaries[CrewID.commander].skills == ref.mercenaries[CrewID.commander].skills && e.state.rng == ref.rng)
            #expect(e.state.mercenaries[CrewID.commander].skills.reduce(0, +) == total + 2)
        }
    }

    @Test("CRW-064 the Skill event costs 3000 and calls IncreaseRandomSkill once")
    func skillEvent() throws {
        #expect(try #require(makeEngine().state.specialEventSpec(.skill)).price == 3_000)
        var e = QuestTrip.engine(.skill)
        var ref = e.state
        ref.changeRandomSkill(1)
        let total = e.state.mercenaries[CrewID.commander].skills.reduce(0, +), cash = e.state.commander.cash
        _ = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(e.state.mercenaries[CrewID.commander].skills == ref.mercenaries[CrewID.commander].skills && e.state.rng == ref.rng)
        #expect(e.state.mercenaries[CrewID.commander].skills.reduce(0, +) == total + 1 && e.state.commander.cash == cash - 3_000)
    }

    /// Delivers Wild at Kravat with the given commander skills and returns Zeethibal's skills and system.
    func zeethibal(_ skills: [Int]) -> ([Int], Int?) {
        var e = QuestTrip.engine(.wildGetsOut) { s in
            s.commander.ship = QuestTrip.ship(.wasp, s, weapons: [.beamLaser])
            s.mercenaries[CrewID.commander].skills = skills
            s.hireCrew(CrewID.wild)
            s.quests.wild = 3
        }
        _ = e.perform(.specialEvent)
        return (e.state.mercenaries[CrewID.zeethibal].skills, e.state.mercenaries[CrewID.zeethibal].systemID)
    }

    @Test("CRW-065 Zeethibal at Kravat: 10 in the lowest raw skill, 8 in the second lowest, 5 elsewhere; ties P, F, T, E")
    func zeethibalRule() {
        var mix = Mix(x: 65)
        for _ in 0..<200 {
            let skills = (0..<4).map { _ in 1 + mix.next(10) }
            let order = (0..<4).sorted { (skills[$0], $0) < (skills[$1], $1) }
            var want = [5, 5, 5, 5]
            want[order[0]] = 10
            want[order[1]] = 8
            let (got, system) = zeethibal(skills)
            #expect(got == want && system == SystemID.kravat, "\(skills)")
        }
        #expect(zeethibal([5, 5, 5, 5]).0 == [10, 8, 5, 5])
        #expect(zeethibal([9, 3, 3, 3]).0 == [5, 10, 8, 5])
    }

    @Test("CRW-066 commander P4 F4 T6 E6 gives Zeethibal P10 F8 T5 E5")
    func zeethibalExample() {
        #expect(zeethibal([4, 4, 6, 6]).0 == [10, 8, 5, 5])
    }

    @Test("CRW-067 Zeethibal is hired through the personnel flow, has wage 0, and relocates within distance < 20 when fired")
    func zeethibalHire() {
        var e = QuestTrip.engine { s in
            s.commander.ship = QuestTrip.ship(.wasp, s)
            s.mercenaries[CrewID.zeethibal].systemID = s.commander.currentSystem
        }
        #expect(e.state.mercenariesForHire.contains(CrewID.zeethibal))
        #expect(e.perform(.hire(crewID: CrewID.zeethibal)).events == [.hired(crewID: CrewID.zeethibal)])
        #expect(e.state.dailyRate(of: CrewID.zeethibal) == 0 && e.state.mercenaryCosts == 0)
        let here = e.state.currentSystem
        _ = e.perform(.fire(crewID: CrewID.zeethibal), acknowledging: [.fireMercenary])
        #expect(!e.state.commander.ship.hasCrew(CrewID.zeethibal))
        let moved = e.state.mercenaries[CrewID.zeethibal].systemID ?? -1
        #expect(e.state.galaxy.systems.indices.contains(moved))
        if e.state.galaxy.systems.indices.contains(moved) {
            #expect(GalaxyGenerator.distance(e.state.galaxy.systems[moved], here, rule: e.ruleset.flags.distance) < 20)
        }
    }
}
