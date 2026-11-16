// SPDX-License-Identifier: GPL-2.0-or-later
// QST-WILD (docs/specs/QST-WILD.md): statuses, boarding, impatience, the "leave" quirks, arrest/pod, delivery, scenarios.
import Testing
@testable import ParsecEngine

private let wild = CrewID.wild
private let yes = QuestTrip.yes

private func isPolice(_ t: EncounterType) -> Bool {
    [.policeAttack, .policeIgnore, .policeFlee, .policeSurrender, .policeDisabled, .policeInspect].contains(t)
}

/// A docked game with record −10 and a Wasp (3 quarters) armed with `weapons`, Wild optionally aboard.
private func wildEngine(_ event: SpecialEventType? = nil, weapons: [WeaponType] = [.beamLaser], aboard: Bool = false,
                        status: Int = 1, _ adjust: (inout GameState) -> Void = { _ in }) -> GameEngine {
    QuestTrip.engine(event) { s in
        s.commander.policeRecordScore = -10
        s.commander.ship = QuestTrip.ship(.wasp, s, weapons: weapons)
        if aboard {
            s.hireCrew(wild)
            s.quests.wild = status
        }
        adjust(&s)
    }
}

// MARK: §1-3 Statuses, button, boarding

@Suite("QST-WILD: statuses, button, boarding")
struct QuestWildBoardingSpecTests {
    @Test("QST-WILD-001 statuses 0/1/11/12; a new game starts at 0")
    func statuses() {
        #expect([QuestStatus.Wild.notStarted, QuestStatus.Wild.started, QuestStatus.Wild.impatient, QuestStatus.Wild.done] == [0, 1, 11, 12])
        for seed in UInt64(0)..<5 { #expect(makeEngine(seed: seed).state.quests.wild == 0) }
    }

    @Test("QST-WILD-002 wild on one random system (consent [0]); wildGetsOut fixed at Kravat, message-only")
    func eventsAndRows() throws {
        let s0 = makeEngine().state
        let start = try #require(s0.specialEventSpec(.wild)), out = try #require(s0.specialEventSpec(.wildGetsOut))
        #expect(start.price == 0 && start.occurrence == 1 && !start.messageOnly)
        #expect(out.price == 0 && out.occurrence == 0 && out.messageOnly)
        var placed = 0
        for seed in UInt64(0)..<20 {
            let s = makeEngine(seed: seed).state
            #expect(s.galaxy.systems[SystemID.kravat].specialEvent == .wildGetsOut)
            let count = s.galaxy.systems.filter { $0.specialEvent == .wild }.count
            #expect(count <= 1)
            placed += count
        }
        #expect(placed > 0)
        var e = wildEngine(.wild)
        let before = e.state
        #expect(e.perform(.specialEvent).decision == .confirm(Confirmation(.acceptSpecialEvent, amounts: [0])) && e.state == before)
        var g = wildEngine(.wildGetsOut, aboard: true)
        #expect(g.perform(.specialEvent).events == [.specialEventCompleted(.wildGetsOut)])
    }

    @Test("QST-WILD-003 wildOnBoard is crew member 32 in the crew array, whatever the status")
    func onBoard() {
        var s = wildEngine().state
        s.quests.wild = 5
        #expect(!s.wildOnBoard && !s.illegalSpecialCargo)
        s.hireCrew(wild)
        s.quests.wild = 0
        #expect(s.wildOnBoard && s.illegalSpecialCargo)
    }

    @Test("QST-WILD-004 wild needs record < −5; wildGetsOut needs Wild aboard")
    func button() {
        for (record, shown) in [(-6, true), (-5, false), (0, false)] {
            #expect((wildEngine(.wild) { $0.commander.policeRecordScore = record }.state.specialEventAvailable == .wild) == shown)
        }
        #expect(wildEngine(.wildGetsOut).state.specialEventAvailable == nil)
        #expect(wildEngine(.wildGetsOut, aboard: true, status: 0).state.specialEventAvailable == .wildGetsOut)
    }

    @Test("QST-WILD-006 refusal order: quarters, then a Beam laser or better, then the reactor; state unchanged")
    func refusals() {
        func attempt(_ e: inout GameEngine) -> CommandError? {
            let before = e.state
            let r = e.perform(.specialEvent, acknowledging: yes)
            if r.rejection != nil { #expect(e.state == before) }
            return r.rejection
        }
        var full = wildEngine(.wild, weapons: []) { s in s.commander.ship = QuestTrip.ship(.gnat, s) }
        #expect(attempt(&full) == .noFreeQuarters)
        var pulse = wildEngine(.wild, weapons: [.pulseLaser]) { $0.quests.reactor = 1 }
        #expect(attempt(&pulse) == .wildRequiresLaser)
        var reactor = wildEngine(.wild) { $0.quests.reactor = 1 }
        #expect(attempt(&reactor) == .wildRefusesReactor)
        for weapon in [WeaponType.beamLaser, .militaryLaser, .morgansLaser, .photonDisruptor, .quantumDisruptor] {
            var ok = wildEngine(.wild, weapons: [weapon])
            #expect(attempt(&ok) == nil && ok.state.wildOnBoard, "\(weapon)")
        }
    }

    @Test("QST-WILD-008 boarding: first free slot, prices follow the Trader, status 1, removed; no extra event with the sculpture")
    func boarding() {
        var e = wildEngine(.wild) { s in
            s.mercenaries[CrewID.commander].skills = [1, 1, 1, 1]
            s.quests.sculpture = QuestStatus.Sculpture.inTransit
            setMarket(&s, buy: 7, sell: 90)
        }
        #expect(e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).events == [.specialEventCompleted(.wild)])
        #expect(e.state.commander.ship.crew == [CrewID.commander, wild, nil])
        #expect(e.state.quests.wild == QuestStatus.Wild.started && e.state.currentSystem.specialEvent == nil)
        var ref = e.state
        ref.recalculateBuyPricesHere()
        #expect(e.state.skill(.trader) == 2 && e.state.buyPrices == ref.buyPrices && e.state.buyPrices != Array(repeating: 7, count: 10))
    }
}

// MARK: §4 While aboard

@Suite("QST-WILD: while aboard")
struct QuestWildAboardSpecTests {
    @Test("QST-WILD-010 crew 7/10/2/5, wage 0, cannot be fired, quarters on a trade; police effects")
    func crewAndPolice() {
        var e = wildEngine(aboard: true) { s in
            s.mercenaries[CrewID.commander].skills = [1, 1, 1, 1]
            s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech
        }
        #expect(e.state.shipSkills == [7, 10, 2, 5] && e.state.dailyRate(of: wild) == 0 && e.state.mercenaryCosts == 0)
        #expect(e.perform(.fire(crewID: wild), acknowledging: yes).rejection == .cannotFireSpecialPassenger)
        #expect(e.perform(.buyShip(.firefly, transfers: []), acknowledging: yes).rejection == .passengersNeedQuarters)
        #expect(e.perform(.buyShip(.hornet, transfers: []), acknowledging: yes).rejection == nil)
        #expect(e.state.commander.ship.crew == [CrewID.commander, wild])
        // Fine × 1.05 and the doubled bribe (Normal).
        var without = e.state
        without.commander.ship.crew = [CrewID.commander, nil]
        #expect(e.state.arrestFine == Int(Double(without.arrestFine) * 1.05))
        var bribeState = Pol.engine(.policeInspect).state
        let plainBribe = bribeState.bribeAmount ?? 0
        bribeState.commander.ship.crew = [CrewID.commander, wild]
        let withBribe = bribeState.bribeAmount ?? 0
        #expect(plainBribe > 0 && plainBribe < 5_000 && withBribe == plainBribe * 2, "\(plainBribe) \(withBribe)")
        // Submitting, surrendering and yielding (customs police) all lead to arrest.
        for (type, action) in [(EncounterType.policeInspect, EncounterAction.submit), (.policeAttack, .surrender), (.marieCelestePolice, .yield)] {
            var p = Pol.engine(type) { s in s.commander.ship = QuestTrip.ship(.wasp, s, weapons: [.beamLaser]); s.hireCrew(wild) }
            #expect(p.perform(.encounter(action), acknowledging: yes).events.contains(where: QuestTrip.isArrest), "\(action)")
        }
        // Police ship tries 5 (bigger police ships on average) and the extra Kravat police roll.
        var bigger = 0, plain = 0, kravatWith = 0, kravatWithout = 0
        for seed in UInt64(0)..<300 {
            var a = wildEngine(aboard: true) { $0.commander.policeRecordScore = 0 }.state
            a.rng = makeEngine(seed: seed).state.rng
            var b = a
            b.commander.ship.crew = [CrewID.commander, nil, nil]
            bigger += a.generateOpponent(.police).type.rawValue
            plain += b.generateOpponent(.police).type.rawValue
            a.rng = makeEngine(seed: seed).state.rng
            b.rng = a.rng
            a.warpSystem = SystemID.kravat
            b.warpSystem = SystemID.kravat
            if let enc = a.determineRandomEncounter(clicks: 5), isPolice(enc.type) { kravatWith += 1 }
            if let enc = b.determineRandomEncounter(clicks: 5), isPolice(enc.type) { kravatWithout += 1 }
        }
        #expect(bigger > plain && kravatWith > kravatWithout)
    }

    @Test("QST-WILD-011 per IncDays call: concerned at 5, impatient (skills 0) at 10, then 11; never fails the quest")
    func impatience() {
        var s = wildEngine(aboard: true).state
        let calls = QuestTrip.dayCalls(&s, 12)
        for (i, events) in calls.enumerated() {
            let notices = events.filter(QuestTrip.isNotice)
            switch i + 1 {
            case 5: #expect(notices == [.passengerConcerned(crewID: wild)])
            case 10: #expect(notices == [.passengerImpatient(crewID: wild)])
            default: #expect(notices.isEmpty, "call \(i + 1)")
            }
        }
        #expect(s.quests.wild == QuestStatus.Wild.impatient && s.mercenaries[wild].skills == [0, 0, 0, 0])
        s.galaxy.systems[s.commander.currentSystem].specialEvent = .wildGetsOut
        var e = GameEngine(state: s)
        _ = e.perform(.specialEvent)
        #expect(e.state.quests.wild == QuestStatus.Wild.done && e.state.mercenaries[wild].skills == [0, 0, 0, 0])
    }
}

// MARK: §5-8 Leaving, arrest, pod, delivery, news

@Suite("QST-WILD: leaving, arrest, pod, delivery")
struct QuestWildLeavingSpecTests {
    @Test("QST-WILD-012 QST-WILD-023 warp without a laser: consent, status 0 → 1, but Wild stays aboard and can be delivered")
    func leaveQuirk() {
        var e = wildEngine(weapons: [.pulseLaser], aboard: true, status: 7)
        e.state.commander.ship.fuel = e.state.commander.ship.fuelTanks(e.ruleset)
        e.state.warpSystem = e.state.destinations.first { $0 != SystemID.kravat } ?? 1
        let before = e.state
        #expect(e.perform(.warp).decision == .confirm(Confirmation(.wildLeavesWithoutLaser)) && e.state == before)
        let trip = completeTrip(&e, .warp, ack: [.wildLeavesWithoutLaser])
        #expect(trip.result.events.first == .wildLeftShip)
        #expect(e.state.wildOnBoard && e.state.quests.wild == 1 && e.state.shipSkills[1] == 10)
        _ = QuestTrip.travel(&e, to: SystemID.kravat, ack: [.wildLeavesWithoutLaser])
        _ = e.perform(.specialEvent)
        #expect(e.state.quests.wild == QuestStatus.Wild.done && !e.state.wildOnBoard)
    }

    @Test("QST-WILD-013 pirate raid: a ship with > 1 quarter takes his status (wildJoinedPirates); else no event; he stays aboard")
    func pirates() {
        for (opponent, joins) in [(ShipType.wasp, true), (.gnat, false)] {
            var e = Pol.engine(.pirateAttack, opponent: opponent) { s in
                s.commander.ship = QuestTrip.ship(.wasp, s, weapons: [.beamLaser])
                s.hireCrew(wild)
                s.quests.wild = 4
                s.commander.ship.cargo[0] = 2
            }
            let events = e.perform(.encounter(.surrender)).events
            #expect(events.contains(.wildJoinedPirates) == joins, "\(opponent)")
            #expect(e.state.wildOnBoard && e.state.quests.wild == (joins ? 0 : 4), "\(opponent)")
        }
    }

    @Test("QST-WILD-014 accepting the reactor with Wild aboard needs wildLeavesForReactor; status 0, he stays in the crew")
    func reactorConsent() {
        var e = wildEngine(.reactor, aboard: true, status: 3)
        let before = e.state
        #expect(e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).decision == .confirm(Confirmation(.wildLeavesForReactor)))
        #expect(e.state == before)
        let r = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent, .wildLeavesForReactor])
        #expect(r.events == [.wildLeftShip, .specialEventCompleted(.reactor)])
        #expect(e.state.quests.wild == 0 && e.state.wildOnBoard && e.state.reactorOnBoard)
    }

    @Test("QST-WILD-016 arrest: status 0, news, record −5 (no −4); he stays unless the crew is cleared or the ship sold")
    func arrest() {
        var e = Pol.engine(.policeInspect) { s in
            s.commander.ship = QuestTrip.ship(.wasp, s, weapons: [.beamLaser])
            s.commander.policeRecordScore = -10
            s.commander.cash = 50_000
            s.hireCrew(wild)
            s.quests.wild = 6
        }
        #expect(e.perform(.encounter(.submit), acknowledging: yes).events.contains(where: QuestTrip.isArrest))
        #expect(e.state.newsEvents.contains(.wildArrested) && e.state.commander.policeRecordScore == -5)
        #expect(e.state.wildOnBoard && e.state.quests.wild == 1)
        var mercs = Pol.engine(.policeInspect) { s in
            s.commander.ship = QuestTrip.ship(.wasp, s, weapons: [.beamLaser])
            s.commander.cash = 50_000
            s.hireCrew(wild)
            s.hireCrew(1)
            s.quests.wild = 6
        }
        // Wild + one mercenary: only one non-special crew member, so nobody is cleared.
        _ = mercs.perform(.encounter(.submit), acknowledging: yes)
        #expect(mercs.state.wildOnBoard && mercs.state.quests.wild == 1)
        var sold = Pol.engine(.policeInspect) { s in
            s.commander.ship = QuestTrip.ship(.wasp, s, weapons: [.beamLaser])
            s.commander.policeRecordScore = -10
            s.commander.cash = 0
            s.hireCrew(wild)
            s.quests.wild = 6
        }
        _ = sold.perform(.encounter(.submit), acknowledging: yes)
        #expect(!sold.state.wildOnBoard && sold.state.commander.ship.type == .flea && sold.state.quests.wild == 0)
    }

    @Test("QST-WILD-017 escape pod: record −4, news, status 0 → 1 by IncDays(3), the Flea leaves him behind")
    func pod() {
        var e = Pol.engine(.pirateAttack) { s in
            s.commander.ship = QuestTrip.ship(.wasp, s, weapons: [.beamLaser])
            s.commander.ship.escapePod = true
            s.commander.policeRecordScore = 3
            s.hireCrew(wild)
            s.quests.wild = 8
        }
        #expect(e.finishEncounter(.escapePod).contains(where: QuestTrip.isPod))
        // −4 then the pod's IncDays(3) decays a positive record by 3 / 3 = 1: 3 − 4 = −1 stays (no decay for −5 < rec ≤ 0).
        #expect(e.state.commander.policeRecordScore == -1 && e.state.newsEvents.contains(.wildArrested))
        #expect(e.state.quests.wild == 1 && !e.state.wildOnBoard && e.state.commander.ship.type == .flea)
    }

    @Test("QST-WILD-018 delivery order: Zeethibal, status 12, record 0, Wild fired (prices on Trader change), sell × 100/90, removed")
    func delivery() {
        var e = wildEngine(.wildGetsOut, aboard: true, status: 4) { s in
            s.commander.policeRecordScore = 80
            s.mercenaries[CrewID.commander].skills = [1, 1, 1, 1]
            setMarket(&s, buy: 7, sell: 95)
        }
        let sell = e.state.sellPrices
        #expect(e.perform(.specialEvent).events == [.specialEventCompleted(.wildGetsOut)])
        let s = e.state
        #expect(s.mercenaries[CrewID.zeethibal].systemID == SystemID.kravat && s.mercenaries[CrewID.zeethibal].skills == [10, 8, 5, 5])
        #expect(s.quests.wild == QuestStatus.Wild.done && s.commander.policeRecordScore == 0 && !s.wildOnBoard)
        #expect(s.sellPrices == sell.map { $0 * 100 / 90 } && s.currentSystem.specialEvent == nil)
        // Wild's removal drops the Trader 2 → 1, so buy prices follow the old sell prices with the new (clean) record.
        #expect(s.buyPrices == Pricing.buyPrices(sell: sell, in: s.currentSystem, criminal: false, traderSkill: 1, ruleset: s.ruleset))
        // No Trader change: buy prices are not recalculated.
        var same = wildEngine(.wildGetsOut, aboard: true) { s in
            s.mercenaries[CrewID.commander].skills = [5, 5, 5, 5]
            setMarket(&s, buy: 7, sell: 95)
        }
        _ = same.perform(.specialEvent)
        #expect(same.state.buyPrices == Array(repeating: 7, count: 10) && same.state.sellPrices == Array(repeating: 105, count: 10))
    }

    @Test("QST-WILD-022 arriving at Kravat with Wild aboard adds wildGetsOut, even at status 0")
    func news() {
        var e = wildEngine(aboard: true, status: 0)
        _ = QuestTrip.travel(&e, to: SystemID.kravat)
        #expect(e.state.commander.currentSystem == SystemID.kravat && e.state.newsEvents.contains(.wildGetsOut))
        var none = wildEngine()
        _ = QuestTrip.travel(&none, to: SystemID.kravat)
        #expect(!none.state.newsEvents.contains(.wildGetsOut))
    }
}

// MARK: §9 Scenarios

@Suite("QST-WILD: scenarios")
struct QuestWildScenarioSpecTests {
    @Test("QST-WILD-024 scenario: board, 5 warps (concerned on 5), deliver at Kravat: Zeethibal, status 12, record 0, sell × 100/90")
    func happyPath() {
        var e = wildEngine(.wild) { s in s.mercenaries[CrewID.commander].skills = [6, 4, 7, 3] }
        _ = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(e.state.wildOnBoard && e.state.quests.wild == 1)
        for warp in 1...5 {
            let notices = QuestTrip.hop(&e).filter(QuestTrip.isNotice)
            #expect(notices == (warp == 5 ? [.passengerConcerned(crewID: wild)] : []), "warp \(warp)")
        }
        _ = QuestTrip.travel(&e, to: SystemID.kravat)
        #expect(e.state.newsEvents.contains(.wildGetsOut) && e.state.specialEventAvailable == .wildGetsOut)
        let sell = e.state.sellPrices
        _ = e.perform(.specialEvent)
        #expect(e.state.mercenaries[CrewID.zeethibal].skills == [5, 8, 5, 10] && e.state.mercenaries[CrewID.zeethibal].systemID == SystemID.kravat)
        #expect(e.state.quests.wild == QuestStatus.Wild.done && e.state.commander.policeRecordScore == 0 && !e.state.wildOnBoard)
        #expect(e.state.sellPrices == sell.map { $0 * 100 / 90 })
    }

    @Test("QST-WILD-025 scenario refusals: record −5 hidden, Pulse only, no quarter first, reactor; Photon disruptor qualifies")
    func refusals() {
        #expect(wildEngine(.wild) { $0.commander.policeRecordScore = -5 }.state.specialEventAvailable == nil)
        let cases: [(CommandError, GameEngine)] = [
            (.wildRequiresLaser, wildEngine(.wild, weapons: [.pulseLaser])),
            (.noFreeQuarters, wildEngine(.wild, weapons: []) { s in s.commander.ship = QuestTrip.ship(.gnat, s) }),
            (.wildRefusesReactor, wildEngine(.wild) { $0.quests.reactor = 3 }),
        ]
        for (error, engine) in cases {
            var e = engine
            let before = e.state
            #expect(e.perform(.specialEvent, acknowledging: yes).rejection == error && e.state == before, "\(error)")
        }
        var photon = wildEngine(.wild, weapons: [.photonDisruptor])
        #expect(photon.perform(.specialEvent, acknowledging: yes).rejection == nil && photon.state.wildOnBoard)
    }

    @Test("QST-WILD-026 scenario leave quirk: status 7, sell the laser, warp needs consent, Wild stays at status 1, delivered at Kravat")
    func leaveQuirk() {
        var e = wildEngine(aboard: true, status: 7) { s in s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech }
        #expect(e.perform(.sellWeapon(index: 0), acknowledging: yes).rejection == nil && e.state.commander.ship.weapons.isEmpty)
        e.state.commander.ship.fuel = e.state.commander.ship.fuelTanks(e.ruleset)
        e.state.warpSystem = e.state.destinations.first { $0 != SystemID.kravat } ?? 1
        #expect(e.perform(.warp).decision == .confirm(Confirmation(.wildLeavesWithoutLaser)))
        let trip = completeTrip(&e, .warp, ack: [.wildLeavesWithoutLaser])
        #expect(trip.events.contains(.wildLeftShip) && e.state.wildOnBoard && e.state.quests.wild == 1)
        _ = QuestTrip.travel(&e, to: SystemID.kravat, ack: [.wildLeavesWithoutLaser])
        #expect(e.state.specialEventAvailable == .wildGetsOut)
        _ = e.perform(.specialEvent)
        #expect(e.state.quests.wild == QuestStatus.Wild.done && e.state.commander.policeRecordScore == 0)
    }

    @Test("QST-WILD-027 scenario: submit with Wild → arrest, news, record −5, status 1 aboard; pod → −4, Flea without Wild, status 1")
    func arrestAndPod() {
        var a = Pol.engine(.policeInspect) { s in
            s.commander.ship = QuestTrip.ship(.wasp, s, weapons: [.beamLaser])
            s.commander.policeRecordScore = -20
            s.commander.cash = 500_000 // pays the fine, so the ship is not sold
            s.hireCrew(wild)
            s.quests.wild = 5
        }
        let events = a.perform(.encounter(.submit), acknowledging: yes).events
        #expect(events.contains(where: QuestTrip.isArrest) && a.state.newsEvents.contains(.wildArrested))
        #expect(a.state.commander.policeRecordScore == -5 && a.state.quests.wild == 1 && a.state.wildOnBoard)
        var p = Pol.engine(.pirateAttack) { s in
            s.commander.ship = QuestTrip.ship(.wasp, s, weapons: [.beamLaser])
            s.commander.ship.escapePod = true
            s.commander.policeRecordScore = -30
            s.hireCrew(wild)
            s.quests.wild = 5
        }
        _ = p.finishEncounter(.escapePod)
        // −30 − 4 = −34, then IncDays(3) on Normal moves a criminal record up by 3.
        #expect(p.state.commander.policeRecordScore == -31 && p.state.newsEvents.contains(.wildArrested))
        #expect(p.state.commander.ship.crew == [CrewID.commander] && p.state.quests.wild == 1)
    }
}
