// SPDX-License-Identifier: GPL-2.0-or-later
// QST-PRINCESS and QST-SCULPTURE {M4} (docs/specs/QST-PRINCESS.md, docs/specs/QST-SCULPTURE.md).
import Testing
@testable import ParsecEngine

/// Moves the docked ship next to `target` (the closest system within full-tank range), refuels and warps there, letting
/// `onEncounter` handle each encounter (default: end it normally). Returns every event of the trip.
@discardableResult
func m4Fly(_ e: inout GameEngine, to target: Int, ack: Set<WarningID> = [],
           onEncounter: (inout GameEngine, EncounterState) -> [GameEvent] = { e, _ in e.finishEncounter(.normal) }) -> [GameEvent] {
    let s = e.state
    let tanks = s.commander.ship.fuelTanks(s.ruleset)
    let rule = s.ruleset.flags.distance
    let near = s.galaxy.systems.indices
        .filter { $0 != target && !s.galaxy.wormholeExists(from: $0, to: target) }
        .map { ($0, GalaxyGenerator.distance(s.galaxy.systems[$0], s.galaxy.systems[target], rule: rule)) }
        .filter { $0.1 <= tanks }
        .min { $0.1 < $1.1 }
    guard let from = near?.0 else { return [] }
    e.state.commander.currentSystem = from
    e.state.commander.ship.fuel = tanks
    _ = e.perform(.selectTarget(target))
    var events = e.perform(.warp, acknowledging: ack).events
    var guardCount = 0
    while case let .encounter(enc) = e.state.phase, guardCount < 500 {
        let before = e.state
        events += onEncounter(&e, enc)
        if e.state == before { events += e.finishEncounter(.normal) }
        guardCount += 1
    }
    return events
}

/// A Wasp with photon disruptors and a free quarter and weapon slot; the Scorpion is weakened so it can be disabled.
private func princessShip(_ s: inout GameState) {
    var ship = freshShip(.wasp, s)
    ship.weapons = [.photonDisruptor, .militaryLaser]
    ship.shields = [ShieldInstance(type: .reflective, charge: s.ruleset.tables.shield(.reflective).power)]
    s.commander.ship = ship
    s.commander.cash = 50_000
    s.commander.policeRecordScore = 5
    s.commander.reputationScore = 40
    s.specialShips.scorpion.hull = 2
    for i in s.specialShips.scorpion.shields.indices { s.specialShips.scorpion.shields[i].charge = 0 }
}

/// Attacks the Scorpion until the encounter is over.
private func fightScorpion(_ e: inout GameEngine, _ enc: EncounterState) -> [GameEvent] {
    guard enc.opponent.type == .scorpion else { return e.finishEncounter(.normal) }
    var events: [GameEvent] = []
    var rounds = 0
    while case let .encounter(now) = e.state.phase, now.opponent.type == .scorpion, rounds < 200 {
        events += e.perform(.encounter(.attack)).events
        rounds += 1
    }
    return events
}

private func dock(_ e: inout GameEngine, at system: Int) {
    e.state.commander.currentSystem = system
    e.state.phase = .docked
}

// MARK: - Princess

@Suite("Quest spec: the Princess (QST-PRINCESS)")
struct QuestPrincessSpecTests {
    @Test("QST-PRINCESS-001 Princess at Galvon: rec ≥ 5 and rep ≥ 40, message-only, status 1, replaced by PrincessReturned; news")
    func start() {
        var e = makeEngine { s in s.commander.currentSystem = SystemID.galvon; s.commander.policeRecordScore = 5; s.commander.reputationScore = 40 }
        #expect(e.state.currentSystem.specialEvent == .princess && e.state.specialEventAvailable == .princess)
        var low = e
        low.state.commander.reputationScore = 39
        #expect(low.state.specialEventAvailable == nil)
        let r = e.perform(.specialEvent)
        #expect(r.decision == nil && r.events == [.specialEventCompleted(.princess)])
        #expect(e.state.quests.princess == 1 && e.state.galaxy.systems[SystemID.galvon].specialEvent == .princessReturned)
        #expect(e.state.specialEventAvailable == nil)
        var news = makeEngine().state
        news.warpSystem = SystemID.galvon
        _ = news.arrival()
        #expect(news.newsEvents.contains(.princess))
    }

    @Test("QST-PRINCESS-002 Centauri (1…3) and Inthara (2…3): message-only, +1 and removed; arrival headlines")
    func search() {
        var e = makeEngine { s in s.commander.currentSystem = SystemID.inthara; s.quests.princess = 1 }
        #expect(e.state.specialEventAvailable == nil)
        dock(&e, at: SystemID.centauri)
        #expect(e.state.specialEventAvailable == .princessCentauri)
        #expect(e.perform(.specialEvent).events == [.specialEventCompleted(.princessCentauri)])
        #expect(e.state.quests.princess == 2 && e.state.galaxy.systems[SystemID.centauri].specialEvent == nil)
        dock(&e, at: SystemID.inthara)
        #expect(e.perform(.specialEvent).events == [.specialEventCompleted(.princessInthara)])
        #expect(e.state.quests.princess == 3 && e.state.galaxy.systems[SystemID.inthara].specialEvent == nil)
        for (status, system, headline) in [(1, SystemID.centauri, NewsEvent.princessCentauri), (2, SystemID.inthara, .princessInthara)] {
            var s = makeEngine { $0.quests.princess = status }.state
            s.warpSystem = system
            _ = s.arrival()
            #expect(s.newsEvents.contains(headline))
        }
    }

    @Test("QST-PRINCESS-003 status 3: the persistent Scorpion meets every trip to Qonos at click 1; Qonos headlines")
    func scorpionEncounter() {
        var s = makeEngine { $0.quests.princess = QuestStatus.Princess.flyQonos }.state
        s.warpSystem = SystemID.qonos
        s.specialShips.scorpion.hull = 123
        let enc = s.determineFixedEncounter(clicks: 1)
        #expect(enc?.type == .scorpionAttack && enc?.opponent == s.specialShips.scorpion && enc?.opponent.hull == 123)
        #expect(enc?.opponent.weapons == [.militaryLaser, .militaryLaser] && enc?.opponent.shields.map(\.type) == [.reflective, .reflective])
        #expect(s.determineFixedEncounter(clicks: 2) == nil)
        for (status, headline) in [(3, NewsEvent.princessQonos), (4, .princessRescued)] {
            var a = makeEngine { $0.quests.princess = status }.state
            a.warpSystem = SystemID.qonos
            _ = a.arrival()
            #expect(a.newsEvents.contains(headline))
        }
    }

    @Test("QST-PRINCESS-004 Scorpion: disruptors needed, never destroyed, disabling rescues (+kill, rec +1, rep +9); fleeing keeps 3")
    func scorpionFight() throws {
        let base = m4EncounterEngine(.scorpionAttack, opponent: .scorpion) { s, opp in
            princessShip(&s)
            s.quests.princess = QuestStatus.Princess.flyQonos
            opp = s.specialShips.scorpion
        }
        var noDisruptor = base
        noDisruptor.state.commander.ship.weapons = [.militaryLaser]
        #expect(noDisruptor.perform(.encounter(.attack)).rejection == .noDisruptors)
        let (r, e) = try #require(m4Scan(base, { $0.perform(.encounter(.attack)) }, until: { r, _ in
            r.events.contains(.opponentDisabled(.scorpion))
        }))
        #expect(!r.events.contains(.opponentDestroyed(.scorpion)))
        #expect(e.state.quests.princess == QuestStatus.Princess.rescued)
        #expect(e.state.commander.kills.pirates == base.state.commander.kills.pirates + 1)
        #expect(e.state.commander.policeRecordScore == base.state.commander.policeRecordScore + 1)
        #expect(e.state.commander.reputationScore == base.state.commander.reputationScore + 9)
        #expect(e.state.specialShips.scorpion.hull >= 1)
        var fled = base
        _ = fled.finishEncounter(.normal)
        #expect(fled.state.quests.princess == QuestStatus.Princess.flyQonos)
    }

    @Test("QST-PRINCESS-005 PrincessQonos: status 4 and not aboard, consent, noFreeQuarters, hired, removed, buy prices follow Trader")
    func takeAboard() {
        var e = makeEngine { s in
            s.commander.currentSystem = SystemID.qonos
            s.quests.princess = QuestStatus.Princess.rescued
            s.mercenaries[CrewID.commander].skills[SkillType.trader.rawValue] = 1
            s.commander.ship = freshShip(.beetle, s)
            s.commander.ship.crew[1] = 1
            s.commander.ship.crew[2] = 2
        }
        #expect(e.state.specialEventAvailable == .princessQonos)
        #expect(e.perform(.specialEvent).decision == .confirm(Confirmation(.acceptSpecialEvent, amounts: [0])))
        let full = e.state
        #expect(e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).rejection == .noFreeQuarters && e.state == full)
        e.state.commander.ship.crew[2] = nil
        let traderBefore = e.state.skill(.trader)
        let r = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(r.events == [.specialEventCompleted(.princessQonos)])
        #expect(e.state.commander.ship.crew[2] == CrewID.princess && e.state.quests.princess == QuestStatus.Princess.rescued)
        #expect(e.state.galaxy.systems[SystemID.qonos].specialEvent == nil && e.state.specialEventAvailable == nil)
        #expect(e.state.skill(.trader) != traderBefore)
        var ref = e.state
        ref.recalculateBuyPricesHere()
        #expect(e.state.buyPrices == ref.buyPrices && e.state.buyPrices != full.buyPrices)
    }

    @Test("QST-PRINCESS-006 aboard: no wage, cannot be fired, adds skills, needs a quarter in a new ship, not illegal")
    func specialCrew() {
        var e = makeEngine { s in
            s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech
            s.commander.cash = 100_000
            s.commander.ship = freshShip(.beetle, s)
            s.hireCrew(CrewID.princess)
            s.quests.princess = QuestStatus.Princess.rescued
        }
        #expect(e.state.dailyRate(of: CrewID.princess) == 0 && e.state.mercenaryCosts == 0)
        #expect(e.perform(.fire(crewID: CrewID.princess), acknowledging: [.fireMercenary]).rejection == .cannotFireSpecialPassenger)
        #expect(e.state.skill(.engineer) >= e.state.mercenaries[CrewID.princess].skills[SkillType.engineer.rawValue])
        #expect(e.perform(.buyShip(.flea, transfers: []), acknowledging: [.buyShip]).rejection == .passengersNeedQuarters)
        #expect(!e.state.illegalSpecialCargo && !e.state.detectableIllegalCargoOrPassengers)
    }

    @Test("QST-PRINCESS-007 impatience: concerned at 9, impatient at 13 (skills 0), +1 per IncDays call whatever n")
    func impatience() {
        var s = makeEngine { s in s.commander.ship = freshShip(.beetle, s); s.hireCrew(CrewID.princess) }.state
        s.quests.princess = 8
        #expect(!s.incDays(30).contains(.passengerConcerned(crewID: CrewID.princess)))
        #expect(s.quests.princess == 9)
        #expect(s.incDays(1).contains(.passengerConcerned(crewID: CrewID.princess)) && s.quests.princess == 10)
        s.quests.princess = 13
        #expect(s.incDays(1).contains(.passengerImpatient(crewID: CrewID.princess)))
        #expect(s.mercenaries[CrewID.princess].skills == [0, 0, 0, 0] && s.quests.princess == 14)
        let quiet = s.incDays(1)
        #expect(s.quests.princess == 14 && !quiet.contains(.passengerImpatient(crewID: CrewID.princess)))
        #expect(s.princessOnBoard)
    }

    @Test("QST-PRINCESS-008 surrendering to pirates with her aboard: refused without hidden bays, hidden with them")
    func surrender() {
        func engine(hidden: Bool) -> GameEngine {
            m4EncounterEngine(.pirateAttack, opponent: .wasp) { s, _ in
                s.commander.ship = freshShip(.beetle, s)
                s.hireCrew(CrewID.princess)
                s.quests.princess = QuestStatus.Princess.rescued
                if hidden { s.commander.ship.gadgets = [.hiddenCargoBays] }
                s.commander.ship.cargo[TradeItemType.water.rawValue] = 10
            }
        }
        var refused = engine(hidden: false)
        let before = refused.state
        #expect(refused.perform(.encounter(.surrender)).rejection == .surrenderPrincess && refused.state == before)
        var hidden = engine(hidden: true)
        let r = hidden.perform(.encounter(.surrender))
        #expect(r.events.first == .preciousHidden && hidden.state.princessOnBoard)
    }

    @Test("QST-PRINCESS-009 QST-PRINCESS-010 arrest: ≥ 2 mercenaries → she leaves, status kept; else status 0, aboard, counting to 3")
    func arrest() {
        var many = makeEngine { s in
            s.commander.cash = 100_000
            s.commander.ship = freshShip(.wasp, s)
            s.commander.ship.crew = [CrewID.commander, 1, 2, nil]   // four quarters, as a designed ship can have
            s.hireCrew(CrewID.princess)
            s.quests.princess = 6
        }.state
        _ = many.arrested()
        #expect(!many.princessOnBoard && many.quests.princess == 6)
        var few = makeEngine { s in
            s.commander.cash = 100_000
            s.commander.ship = freshShip(.beetle, s)
            s.hireCrew(CrewID.princess)
            s.quests.princess = 6
        }.state
        let events = few.arrested()
        #expect(events.contains { if case .arrested(_, _, false) = $0 { true } else { false } })
        #expect(few.princessOnBoard && few.quests.princess == 1)   // 0, then the jail IncDays adds one
        // She is still accepted by PrincessReturned at Galvon (kept quirk).
        few.galaxy.systems[SystemID.galvon].specialEvent = .princessReturned
        few.commander.currentSystem = SystemID.galvon
        #expect(few.specialEventAvailable == .princessReturned)
        // QST-PRINCESS-010: the status counts on; at 3 the Scorpion returns, and disabling it sets 4 again.
        _ = few.incDays(1)
        _ = few.incDays(1)
        #expect(few.quests.princess == 3)
        few.warpSystem = SystemID.qonos
        #expect(few.determineFixedEncounter(clicks: 1)?.opponent.type == .scorpion)
        few.defeatSpecialShip(.scorpion)
        #expect(few.quests.princess == QuestStatus.Princess.rescued)
    }

    @Test("QST-PRINCESS-011 the escape pod: status 0, then 1 in the pod's IncDays, and she is gone with the old ship")
    func escapePod() {
        var s = makeEngine { s in
            s.commander.ship = freshShip(.beetle, s)
            s.hireCrew(CrewID.princess)
            s.quests.princess = 7
            s.commander.ship.escapePod = true
        }.state
        _ = s.escapeWithPod()
        #expect(s.quests.princess == 1 && !s.princessOnBoard && s.commander.ship.type == .flea)
        s.commander.currentSystem = SystemID.galvon
        s.galaxy.systems[SystemID.galvon].specialEvent = .princessReturned
        #expect(s.specialEventAvailable == nil)
        s.commander.currentSystem = SystemID.qonos
        #expect(s.specialEventAvailable == nil)
    }

    @Test("QST-PRINCESS-012 PrincessReturned: she leaves (slots shift up), status 15, event becomes PrincessQuantum; impatient too")
    func returned() {
        for status in [QuestStatus.Princess.rescued, QuestStatus.Princess.impatient] {
            var e = makeEngine { s in
                s.commander.currentSystem = SystemID.galvon
                s.galaxy.systems[SystemID.galvon].specialEvent = .princessReturned
                s.commander.ship = freshShip(.beetle, s)
                s.commander.ship.crew[1] = CrewID.princess
                s.commander.ship.crew[2] = 3
                s.quests.princess = status
                s.recalculateBuyPricesHere()
            }
            #expect(e.state.specialEventAvailable == .princessReturned)
            let r = e.perform(.specialEvent)
            #expect(r.decision == nil && r.events == [.specialEventCompleted(.princessReturned)])
            #expect(e.state.commander.ship.crew == [CrewID.commander, 3, nil])
            #expect(e.state.quests.princess == QuestStatus.Princess.returned)
            #expect(e.state.galaxy.systems[SystemID.galvon].specialEvent == .princessQuantum)
            var ref = e.state
            ref.recalculateBuyPricesHere()
            #expect(e.state.buyPrices == ref.buyPrices)
        }
    }

    @Test("QST-PRINCESS-013 PrincessQuantum: consent, noFreeSlot keeps the event; else a Quantum Disruptor, status 16, removed")
    func quantum() {
        var e = makeEngine { s in
            s.commander.currentSystem = SystemID.galvon
            s.galaxy.systems[SystemID.galvon].specialEvent = .princessQuantum
            s.quests.princess = QuestStatus.Princess.returned
            s.commander.ship.weapons = [.pulseLaser]   // the Gnat's only weapon slot is full
        }
        #expect(e.perform(.specialEvent).decision == .confirm(Confirmation(.acceptSpecialEvent, amounts: [0])))
        let full = e.state
        #expect(e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).rejection == .noFreeSlot && e.state == full)
        e.state.commander.ship.weapons = []
        #expect(e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).events == [.specialEventCompleted(.princessQuantum)])
        #expect(e.state.commander.ship.weapons == [.quantumDisruptor] && e.state.quests.princess == QuestStatus.Princess.done)
        #expect(e.state.galaxy.systems[SystemID.galvon].specialEvent == nil)
    }

    @Test("QST-PRINCESS-014 the princessReturned headline is unreachable: handling PrincessReturned replaces the event")
    func unreachableHeadline() {
        var e = makeEngine { s in
            s.commander.currentSystem = SystemID.galvon
            s.galaxy.systems[SystemID.galvon].specialEvent = .princessReturned
            s.commander.ship = freshShip(.beetle, s)
            s.hireCrew(CrewID.princess)
            s.quests.princess = QuestStatus.Princess.rescued
        }
        _ = e.perform(.specialEvent)
        #expect(e.state.quests.princess == QuestStatus.Princess.returned)
        var s = e.state
        s.warpSystem = SystemID.galvon
        _ = s.arrival()
        #expect(!s.newsEvents.contains(.princessReturned))
        // Before handling (status 4 with the event in place) the headline does not fire either.
        var early = makeEngine { $0.quests.princess = QuestStatus.Princess.rescued; $0.galaxy.systems[SystemID.galvon].specialEvent = .princessReturned }.state
        early.warpSystem = SystemID.galvon
        _ = early.arrival()
        #expect(!early.newsEvents.contains(.princessReturned))
    }

    @Test("QST-PRINCESS-016 scenario: Galvon, Centauri, Inthara, the Scorpion, Qonos, back to Galvon, the Quantum Disruptor")
    func success() throws {
        var e = makeEngine { princessShip(&$0) }
        dock(&e, at: SystemID.galvon)
        _ = e.perform(.specialEvent)
        #expect(e.state.quests.princess == 1 && e.state.galaxy.systems[SystemID.galvon].specialEvent == .princessReturned)
        m4Fly(&e, to: SystemID.centauri)
        _ = e.perform(.specialEvent)
        #expect(e.state.quests.princess == 2)
        m4Fly(&e, to: SystemID.inthara)
        _ = e.perform(.specialEvent)
        #expect(e.state.quests.princess == 3)
        var met = false
        let trip = m4Fly(&e, to: SystemID.qonos) { e, enc in
            if enc.opponent.type == .scorpion { met = enc.clicks == 1 }
            return fightScorpion(&e, enc)
        }
        #expect(met && trip.contains(.opponentDisabled(.scorpion)), "\(trip)")
        #expect(e.state.quests.princess == QuestStatus.Princess.rescued && e.state.commander.currentSystem == SystemID.qonos)
        _ = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(e.state.princessOnBoard && e.state.quests.princess == QuestStatus.Princess.rescued)
        m4Fly(&e, to: SystemID.galvon)
        #expect(e.state.quests.princess > QuestStatus.Princess.rescued)   // one per day aboard
        _ = e.perform(.specialEvent)
        #expect(!e.state.princessOnBoard && e.state.quests.princess == QuestStatus.Princess.returned)
        #expect(e.state.galaxy.systems[SystemID.galvon].specialEvent == .princessQuantum)
        _ = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(e.state.commander.ship.weapons.contains(.quantumDisruptor) && e.state.quests.princess == QuestStatus.Princess.done)
    }

    @Test("QST-PRINCESS-017 gates: rec 4 hides the start; Inthara at 1 and Qonos at 3 offer nothing; no disruptors → noDisruptors")
    func gates() {
        var e = makeEngine { s in s.commander.currentSystem = SystemID.galvon; s.commander.policeRecordScore = 4; s.commander.reputationScore = 40 }
        #expect(e.state.specialEventAvailable == nil && e.perform(.specialEvent).rejection == .noSpecialEvent)
        dock(&e, at: SystemID.inthara)
        e.state.quests.princess = 1
        #expect(e.state.specialEventAvailable == nil)
        dock(&e, at: SystemID.qonos)
        e.state.quests.princess = 3
        #expect(e.state.specialEventAvailable == nil)
        var fight = m4EncounterEngine(.scorpionAttack, opponent: .scorpion) { s, _ in s.commander.ship.weapons = [.militaryLaser] }
        #expect(fight.perform(.encounter(.attack)).rejection == .noDisruptors)
    }

    @Test("QST-PRINCESS-018 no quarters at Qonos: noFreeQuarters with nothing changed; after firing a mercenary it works")
    func noQuarters() {
        var e = makeEngine { s in
            s.commander.currentSystem = SystemID.qonos
            s.quests.princess = QuestStatus.Princess.rescued
            s.commander.ship = freshShip(.beetle, s)
            s.commander.ship.crew[1] = 1
            s.commander.ship.crew[2] = 2
        }
        let before = e.state
        #expect(e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).rejection == .noFreeQuarters && e.state == before)
        _ = e.perform(.fire(crewID: 2), acknowledging: [.fireMercenary])
        #expect(e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).rejection == nil && e.state.princessOnBoard)
    }

    @Test("QST-PRINCESS-019 scenario: boarding at 4, warps raise the status; concerned at 9, impatient at 13, returned at 14")
    func impatienceScenario() {
        var e = makeEngine { s in
            princessShip(&s)
            s.commander.currentSystem = SystemID.qonos
            s.quests.princess = QuestStatus.Princess.rescued
        }
        _ = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        var concernedAt: Int?, impatientAt: Int?
        for warp in 1...11 {
            let found = e.state.quests.princess
            let target = warp.isMultiple(of: 2) ? SystemID.centauri : SystemID.inthara
            let events = m4Fly(&e, to: target)
            if events.contains(.passengerConcerned(crewID: CrewID.princess)) { concernedAt = found }
            if events.contains(.passengerImpatient(crewID: CrewID.princess)) { impatientAt = found }
        }
        #expect(concernedAt == 9 && impatientAt == 13)
        #expect(e.state.quests.princess == QuestStatus.Princess.impatient)
        #expect(e.state.mercenaries[CrewID.princess].skills == [0, 0, 0, 0])
        m4Fly(&e, to: SystemID.galvon)
        e.state.galaxy.systems[SystemID.galvon].specialEvent = .princessReturned
        _ = e.perform(.specialEvent)
        #expect(e.state.quests.princess == QuestStatus.Princess.returned && !e.state.princessOnBoard)
    }

    @Test("QST-PRINCESS-020 failures: pirate surrender refused, pod loses her at 1, arrest with mercenaries sticks, else stays at 1")
    func failures() {
        var pirates = m4EncounterEngine(.pirateAttack) { s, _ in
            s.commander.ship = freshShip(.beetle, s)
            s.hireCrew(CrewID.princess)
            s.quests.princess = QuestStatus.Princess.rescued
        }
        #expect(pirates.perform(.encounter(.surrender)).rejection == .surrenderPrincess)
        var pod = makeEngine { s in
            armDepartureFreeze(&s)
            s.commander.ship = freshShip(.beetle, s)
            s.commander.ship.fuel = 20
            s.hireCrew(CrewID.princess)
            s.quests.princess = QuestStatus.Princess.rescued
            s.commander.ship.escapePod = true
        }
        _ = pod.perform(.warp)
        _ = pod.finishEncounter(.escapePod)
        #expect(pod.state.quests.princess == 1 && !pod.state.princessOnBoard)
        // Arrest through a police surrender, with two mercenaries: she leaves, status kept.
        var stuck = m4EncounterEngine(.policeAttack) { s, _ in
            s.commander.cash = 100_000
            s.commander.ship = freshShip(.wasp, s)
            s.commander.ship.crew = [CrewID.commander, 1, 2, nil]   // four quarters, as a designed ship can have
            s.hireCrew(CrewID.princess)
            s.quests.princess = 5
        }
        _ = stuck.perform(.encounter(.surrender), acknowledging: [.surrenderToPolice])
        #expect(!stuck.state.princessOnBoard && stuck.state.quests.princess == 5)
        var kept = m4EncounterEngine(.policeAttack) { s, _ in
            s.commander.cash = 100_000
            s.commander.ship = freshShip(.beetle, s)
            s.hireCrew(CrewID.princess)
            s.quests.princess = 5
        }
        _ = kept.perform(.encounter(.surrender), acknowledging: [.surrenderToPolice])
        #expect(kept.state.princessOnBoard && kept.state.quests.princess == 1)
    }
}

// MARK: - Sculpture

@Suite("Quest spec: the stolen sculpture (QST-SCULPTURE)")
struct QuestSculptureSpecTests {
    /// Docked at the Sculpture start with a dubious record and good reputation.
    func atStart(_ adjust: (inout GameState) -> Void = { _ in }) -> GameEngine {
        makeEngine { s in
            let sys = s.galaxy.systems.firstIndex { $0.specialEvent == .sculpture } ?? 1
            s.commander.currentSystem = sys
            s.commander.policeRecordScore = -10
            s.commander.reputationScore = 40
            adjust(&s)
        }
    }

    @Test("QST-SCULPTURE-001 shown iff status 0, rec < −5, rep ≥ 40; price −2000, refused only below cashToSpend −2000")
    func offer() {
        var e = atStart()
        #expect(e.state.specialEventAvailable == .sculpture)
        #expect(e.perform(.specialEvent).decision == .confirm(Confirmation(.acceptSpecialEvent, amounts: [-2_000])))
        var poor = atStart { s in
            s.commander.cash = 0
            s.commander.ship = freshShip(.beetle, s)
            s.commander.ship.crew[1] = 1
            s.options.reserveMoney = true
        }
        let costs = poor.state.currentCosts
        poor.state.commander.cash = costs - 2_001
        #expect(poor.state.cashToSpend == -2_001)
        #expect(poor.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).rejection == .insufficientFunds)
        poor.state.commander.cash = costs - 2_000
        #expect(poor.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).rejection == nil)
    }

    @Test("QST-SCULPTURE-002 accepting: status 1, +2000 cash, removed, no bay used; sculptureStolen news while in place")
    func accept() {
        var e = atStart { $0.commander.cash = 100 }
        let sys = e.state.commander.currentSystem
        let bays = e.state.freeCargoBays
        var news = e.state
        news.warpSystem = sys
        _ = news.arrival()
        #expect(news.newsEvents.contains(.sculptureStolen))
        #expect(e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).events == [.specialEventCompleted(.sculpture)])
        #expect(e.state.quests.sculpture == 1 && e.state.commander.cash == 2_100)
        #expect(e.state.galaxy.systems[sys].specialEvent == nil && e.state.freeCargoBays == bays && e.state.sculptureOnBoard)
    }

    @Test("QST-SCULPTURE-003 every Endor arrival with SculptureDelivered in place adds sculptureTracked, whatever the status")
    func tracked() {
        for status in [0, 1, 3] {
            var s = makeEngine { $0.quests.sculpture = status }.state
            #expect(s.galaxy.systems[SystemID.endor].specialEvent == .sculptureDelivered)
            s.warpSystem = SystemID.endor
            _ = s.arrival()
            #expect(s.newsEvents.contains(.sculptureTracked))
        }
    }

    @Test("QST-SCULPTURE-004 illegal special cargo: submit arrests, bribe ×2 (Normal), Marie Celeste yield needs surrenderToPolice")
    func illegal() {
        let clean = makeEngine().state
        var s = clean
        s.quests.sculpture = 1
        #expect(s.illegalSpecialCargo && s.detectableIllegalCargoOrPassengers)
        if let plain = clean.bribeAmount, let doubled = s.bribeAmount { #expect(doubled == min(10_000, max(100, plain * 2))) }
        var inspect = m4EncounterEngine(.policeInspect) { s, _ in s.quests.sculpture = 1; s.commander.cash = 50_000 }
        #expect(inspect.perform(.encounter(.submit)).decision == .confirm(Confirmation(.submitInspection)))
        let r = inspect.perform(.encounter(.submit), acknowledging: [.submitInspection])
        #expect(r.events.contains { if case .arrested = $0 { true } else { false } })
        var marie = m4EncounterEngine(.marieCelestePolice) { s, _ in s.quests.sculpture = 1 }
        #expect(marie.perform(.encounter(.yield)).decision == .confirm(Confirmation(.surrenderToPolice)))
    }

    @Test("QST-SCULPTURE-005 QST-SCULPTURE-016 pirates: hidden bays keep it (preciousHidden), else status 0 with sculptureTaken first")
    func pirates() {
        func engine(hidden: Bool) -> GameEngine {
            m4EncounterEngine(.pirateAttack, opponent: .wasp) { s, _ in
                s.commander.ship = freshShip(.beetle, s)
                s.quests.sculpture = 1
                s.commander.cash = 9_000
                if hidden { s.commander.ship.gadgets = [.hiddenCargoBays] }
                s.commander.ship.cargo[TradeItemType.water.rawValue] = 10
            }
        }
        var kept = engine(hidden: true)
        #expect(kept.perform(.encounter(.surrender)).events.first == .preciousHidden && kept.state.quests.sculpture == 1)
        var taken = engine(hidden: false)
        let r = taken.perform(.encounter(.surrender))
        #expect(r.events.first == .sculptureTaken && r.events.dropFirst().first.map { if case .looted = $0 { true } else { false } } == true)
        #expect(taken.state.quests.sculpture == 0 && taken.state.commander.cash == 9_000)   // the 2000 already paid is kept
        taken.state.commander.currentSystem = SystemID.endor
        taken.state.phase = .docked
        #expect(taken.state.specialEventAvailable == nil)
    }

    @Test("QST-SCULPTURE-006 arrest: hidden bays removed, sculpture status 0, no separate event")
    func arrest() {
        var s = makeEngine { s in
            s.commander.ship = freshShip(.beetle, s)
            s.commander.ship.gadgets = [.hiddenCargoBays]
            s.quests.sculpture = 1
            s.commander.cash = 100_000
        }.state
        let events = s.arrested()
        #expect(s.quests.sculpture == 0 && !s.commander.ship.has(.hiddenCargoBays))
        #expect(events.contains { if case .arrested = $0 { true } else { false } } && !events.contains(.sculptureTaken))
    }

    @Test("QST-SCULPTURE-007 the escape pod and a ship trade keep the sculpture")
    func podAndTrade() {
        var pod = makeEngine { s in s.quests.sculpture = 1; s.commander.ship.escapePod = true }.state
        _ = pod.escapeWithPod()
        #expect(pod.quests.sculpture == 1 && pod.sculptureOnBoard)
        var trade = makeEngine { s in
            s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech
            s.commander.cash = 100_000
            s.quests.sculpture = 1
        }
        _ = trade.perform(.buyShip(.firefly, transfers: []), acknowledging: [.buyShip])
        #expect(trade.state.commander.ship.type == .firefly && trade.state.sculptureOnBoard)
    }

    @Test("QST-SCULPTURE-008 Wild boarding with the sculpture aboard changes no sculpture state (the app adds ALR-184)")
    func wildAdmires() {
        var e = makeEngine { s in
            s.commander.ship = freshShip(.wasp, s)
            s.commander.ship.weapons = [.beamLaser]
            s.commander.policeRecordScore = -10
            s.quests.sculpture = 1
            let sys = s.galaxy.systems.firstIndex { $0.specialEvent == .wild } ?? 1
            s.commander.currentSystem = sys
        }
        let r = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(r.events == [.specialEventCompleted(.wild)] && e.state.wildOnBoard)
        #expect(e.state.quests.sculpture == 1 && e.state.sculptureOnBoard)
    }

    @Test("QST-SCULPTURE-009 once lost the job is gone: the start was removed and the delivery needs status 1")
    func lostForGood() {
        var e = atStart()
        let sys = e.state.commander.currentSystem
        _ = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        e.state.quests.sculpture = 0
        #expect(e.state.galaxy.systems[sys].specialEvent == nil && e.state.specialEventAvailable == nil)
        dock(&e, at: SystemID.endor)
        #expect(e.state.specialEventAvailable == nil)
    }

    @Test("QST-SCULPTURE-010 SculptureDelivered: status 1 only, message-only, status 2, replaced by SculptureHiddenBays")
    func delivered() {
        var e = makeEngine { $0.commander.currentSystem = SystemID.endor }
        #expect(e.state.specialEventAvailable == nil)
        e.state.quests.sculpture = 1
        let r = e.perform(.specialEvent)
        #expect(r.decision == nil && r.events == [.specialEventCompleted(.sculptureDelivered)])
        #expect(e.state.quests.sculpture == 2 && e.state.galaxy.systems[SystemID.endor].specialEvent == .sculptureHiddenBays)
    }

    @Test("QST-SCULPTURE-011 QST-SCULPTURE-012 hidden bays: status 3 first; no slot → committed refusal, event kept; later install")
    func hiddenBays() {
        var e = makeEngine { s in
            s.commander.currentSystem = SystemID.endor
            s.galaxy.systems[SystemID.endor].specialEvent = .sculptureHiddenBays
            s.quests.sculpture = 2
            s.commander.ship.gadgets = [.navigatingSystem]   // the Gnat's only gadget slot
        }
        #expect(e.perform(.specialEvent).decision == .confirm(Confirmation(.acceptSpecialEvent, amounts: [0])))
        let refusal = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(refusal.rejection == nil && refusal.events == [.specialEventRefused(.sculptureHiddenBays, reason: .noFreeSlot)])
        #expect(e.state.quests.sculpture == 3 && e.state.galaxy.systems[SystemID.endor].specialEvent == .sculptureHiddenBays)
        #expect(e.state.specialEventAvailable == .sculptureHiddenBays)
        let bays = e.state.commander.ship.cargoBays(e.ruleset)
        e.state.commander.ship.gadgets = []
        #expect(e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).events == [.specialEventCompleted(.sculptureHiddenBays)])
        #expect(e.state.commander.ship.gadgets == [.hiddenCargoBays] && e.state.galaxy.systems[SystemID.endor].specialEvent == nil)
        #expect(e.state.commander.ship.cargoBays(e.ruleset) == bays + 5)
    }

    @Test("QST-SCULPTURE-013 scenario: accept, fly to Endor, delivery, hidden bays installed")
    func success() {
        var e = atStart { s in s.commander.ship.gadgets = []; s.commander.cash = 0 }
        _ = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(e.state.commander.cash == 2_000 && e.state.quests.sculpture == 1)
        // Encounters on the way are passed by (never submitted to), so the sculpture arrives.
        m4Fly(&e, to: SystemID.endor)
        #expect(e.state.commander.currentSystem == SystemID.endor && e.state.quests.sculpture == 1)
        _ = e.perform(.specialEvent)
        #expect(e.state.quests.sculpture == 2 && e.state.galaxy.systems[SystemID.endor].specialEvent == .sculptureHiddenBays)
        _ = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(e.state.commander.ship.has(.hiddenCargoBays) && e.state.quests.sculpture == 3)
        #expect(e.state.galaxy.systems[SystemID.endor].specialEvent == nil)
    }

    @Test("QST-SCULPTURE-014 gates: rec −5 or rep 39 hide the start")
    func gates() {
        #expect(atStart { $0.commander.policeRecordScore = -5 }.state.specialEventAvailable == nil)
        #expect(atStart { $0.commander.reputationScore = 39 }.state.specialEventAvailable == nil)
        #expect(atStart { $0.commander.policeRecordScore = -6 }.state.specialEventAvailable == .sculpture)
    }

    @Test("QST-SCULPTURE-015 slot refusal at Endor commits status 3; after selling a gadget the next acceptance installs")
    func slotRefusal() {
        var e = makeEngine { s in
            s.commander.currentSystem = SystemID.endor
            s.galaxy.systems[SystemID.endor].specialEvent = .sculptureHiddenBays
            s.quests.sculpture = 2
            s.galaxy.systems[SystemID.endor].techLevel = .hiTech
            s.commander.ship.gadgets = [.autoRepairSystem]
        }
        let r = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(r.events == [.specialEventRefused(.sculptureHiddenBays, reason: .noFreeSlot)] && e.state.quests.sculpture == 3)
        #expect(e.perform(.sellGadget(index: 0), acknowledging: [.sellEquipment]).rejection == nil)
        _ = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(e.state.commander.ship.gadgets == [.hiddenCargoBays])
    }

    @Test("QST-SCULPTURE-017 police: an arrest loses it; the escape pod keeps status 1 and the delivery works from the Flea")
    func police() {
        var arrest = m4EncounterEngine(.policeAttack) { s, _ in s.quests.sculpture = 1; s.commander.cash = 100_000 }
        _ = arrest.perform(.encounter(.surrender), acknowledging: [.surrenderToPolice])
        #expect(arrest.state.quests.sculpture == 0)
        var pod = makeEngine { s in armDepartureFreeze(&s); s.quests.sculpture = 1; s.commander.ship.escapePod = true }
        _ = pod.perform(.warp)
        _ = pod.finishEncounter(.escapePod)
        #expect(pod.state.commander.ship.type == .flea && pod.state.quests.sculpture == 1)
        dock(&pod, at: SystemID.endor)
        #expect(pod.state.specialEventAvailable == .sculptureDelivered)
        _ = pod.perform(.specialEvent)
        #expect(pod.state.quests.sculpture == 2)
    }
}
