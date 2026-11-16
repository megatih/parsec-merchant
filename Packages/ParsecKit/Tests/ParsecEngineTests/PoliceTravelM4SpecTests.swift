// SPDX-License-Identifier: GPL-2.0-or-later
// POL and TRV bullets tagged {M4}: quest effects of the arrest, the escape pod, the arrival pipeline and IncDays.
import Testing
@testable import ParsecEngine

/// A docked state with a Beetle (three quarters) crewed by the commander and `crew`.
private func crewed(_ crew: [Int], cash: Int = 100_000, _ adjust: (inout GameState) -> Void = { _ in }) -> GameState {
    var s = makeEngine().state
    s.commander.ship = freshShip(.beetle, s)
    s.commander.ship.crew = [CrewID.commander] + crew.map { Optional($0) } + Array(repeating: nil, count: max(0, 2 - crew.count))
    s.commander.cash = cash
    adjust(&s)
    return s
}

@Suite("Police spec: quest effects (POL {M4})")
struct PoliceQuestSpecTests {
    @Test("POL-046 the escape pod with Wild aboard costs 4 record points; an arrest with Wild sets −5 without the −4")
    func wildRecord() {
        var pod = crewed([CrewID.wild]) { s in s.quests.wild = 3; s.commander.policeRecordScore = -10; s.commander.ship.escapePod = true }
        _ = pod.escapeWithPod()
        var noWild = crewed([]) { s in s.commander.policeRecordScore = -10; s.commander.ship.escapePod = true }
        _ = noWild.escapeWithPod()
        // −10 − 4 = −14, then the pod's IncDays(3) drifts a criminal record up by 3 on Normal.
        #expect(pod.commander.policeRecordScore == -11 && noWild.commander.policeRecordScore == -7)
        var arrest = crewed([CrewID.wild]) { s in s.quests.wild = 3; s.commander.policeRecordScore = -40 }
        _ = arrest.arrested()
        #expect(arrest.commander.policeRecordScore == -5)
    }

    @Test("POL-076 Mantis surrender: refused without the artifact; with it, consent, status 0, artifactRelinquished, encounter over")
    func mantis() {
        var without = m4EncounterEngine(.pirateAttack, opponent: .mantis)
        #expect(without.perform(.encounter(.surrender)).rejection == .surrenderRefused)
        var with = m4EncounterEngine(.pirateAttack, opponent: .mantis) { s, _ in s.quests.artifact = QuestStatus.Artifact.onBoard }
        let before = with.state
        #expect(with.perform(.encounter(.surrender)).decision == .confirm(Confirmation(.surrenderArtifact)) && with.state == before)
        let r = with.perform(.encounter(.surrender), acknowledging: [.surrenderArtifact])
        #expect(r.events.first == .artifactRelinquished && with.state.quests.artifact == QuestStatus.Artifact.notStarted)
        if case .encounter = with.state.phase { Issue.record("the encounter must end") }
    }

    @Test("POL-077 surrender to pirates with the Princess aboard and no hidden bays → surrenderPrincess")
    func princess() {
        var e = m4EncounterEngine(.pirateAttack) { s, _ in s.commander.ship = freshShip(.beetle, s); s.hireCrew(CrewID.princess) }
        let before = e.state
        #expect(e.perform(.encounter(.surrender)).rejection == .surrenderPrincess && e.state == before)
        e.state.commander.ship.gadgets = [.hiddenCargoBays]
        #expect(e.perform(.encounter(.surrender)).rejection == nil)
    }

    @Test("POL-084 Wild after looting: pirate quarters > 1 → status 0 and wildJoinedPirates, still in the crew; else nothing")
    func wildAndPirates() {
        func loot(_ opponent: ShipType) -> (StepResult, GameState) {
            var e = m4EncounterEngine(.pirateAttack, opponent: opponent) { s, _ in
                s.commander.ship = freshShip(.beetle, s)
                s.hireCrew(CrewID.wild)
                s.quests.wild = 3
                s.commander.ship.cargo[TradeItemType.ore.rawValue] = 4
            }
            return (e.perform(.encounter(.surrender)), e.state)
        }
        #expect(Ruleset.windows201.tables.ship(.wasp).crewQuarters > 1 && Ruleset.windows201.tables.ship(.gnat).crewQuarters == 1)
        let (joined, js) = loot(.wasp)
        #expect(joined.events.contains(.wildJoinedPirates) && js.quests.wild == QuestStatus.Wild.notStarted)
        #expect(js.wildOnBoard)   // port quirk: not removed from the crew
        let (stayed, ss) = loot(.gnat)
        #expect(!stayed.events.contains(.wildJoinedPirates) && ss.quests.wild == 3 && ss.wildOnBoard)
    }

    @Test("POL-095 arrest order quirk: ≥ 2 mercenaries → Jarek/Princess leave with status kept; else they stay, status 0 → 1")
    func arrestQuirk() {
        var many = makeEngine().state
        many.commander.ship = freshShip(.wasp, many)
        many.commander.ship.crew = [CrewID.commander, 1, 2, nil]   // four quarters, as a designed ship can have
        many.hireCrew(CrewID.jarek)
        many.commander.cash = 100_000
        many.quests.jarek = 4
        _ = many.arrested()
        #expect(!many.jarekOnBoard && many.quests.jarek == 4)
        var few = crewed([CrewID.jarek, CrewID.princess]) { s in s.quests.jarek = 4; s.quests.princess = 6 }
        _ = few.arrested()
        #expect(few.jarekOnBoard && few.princessOnBoard && few.quests.jarek == 1 && few.quests.princess == 1)
        // Ship sold for the fine: the Flea has no passengers, so their statuses stay 0.
        var sold = crewed([CrewID.jarek, CrewID.princess], cash: 0) { s in s.quests.jarek = 4; s.quests.princess = 6 }
        let events = sold.arrested()
        #expect(events.contains { if case .arrested(_, _, true) = $0 { true } else { false } })
        #expect(!sold.jarekOnBoard && sold.quests.jarek == 0 && sold.quests.princess == 0)
    }

    @Test("POL-105 escape pod order quirk: IncDays(3) runs before CreateFlea, so each passenger status ends at 1")
    func podQuirk() {
        var s = crewed([CrewID.jarek, CrewID.wild]) { s in s.quests.jarek = 4; s.quests.wild = 6; s.commander.ship.escapePod = true }
        let days = s.commander.days
        _ = s.escapeWithPod()
        #expect(s.commander.days == days + 3)
        #expect(s.quests.jarek == 1 && s.quests.wild == 1 && !s.jarekOnBoard && !s.wildOnBoard)
        var p = crewed([CrewID.princess]) { s in s.quests.princess = 8; s.commander.ship.escapePod = true }
        _ = p.escapeWithPod()
        #expect(p.quests.princess == 1 && !p.princessOnBoard)
    }
}

@Suite("Travel spec: quest steps of the arrival and IncDays (TRV {M4})")
struct TravelQuestSpecTests {
    func arriving(_ adjust: (inout GameState) -> Void) -> GameState {
        var s = makeEngine().state
        s.warpSystem = plainTarget(s) ?? 1
        adjust(&s)
        return s
    }

    @Test("TRV-052 reactor check: 20 → meltdown and status 0, then the pod (pipeline continues) or game over; 2/16/18 warn")
    func reactorCheck() {
        var dead = arriving { $0.quests.reactor = QuestStatus.Reactor.date }
        let events = dead.arrival()
        #expect(events == [.reactorMeltdown, .gameEnded(.killed, score: dead.score(for: .killed))])
        #expect(dead.quests.reactor == 0 && dead.commander.currentSystem == dead.warpSystem)
        var pod = arriving { s in s.quests.reactor = QuestStatus.Reactor.date; s.commander.ship.escapePod = true }
        let podEvents = pod.arrival()
        #expect(podEvents.first == .reactorMeltdown && podEvents.last == .arrived(system: pod.warpSystem))
        #expect(podEvents.contains { if case .escapePodUsed = $0 { true } else { false } } && pod.phase == .docked)
        for status in [2, 16, 18] {
            var s = arriving { $0.quests.reactor = status }
            #expect(s.arrival().first == .reactorWarning(status: status))
        }
        for status in [1, 3, 15, 17, 19] {
            var s = arriving { $0.quests.reactor = status }
            #expect(!s.arrival().contains { if case .reactorWarning = $0 { true } else { false } })
        }
    }

    @Test("TRV-053 the Windows tribble update runs after the reactor check and before the debt check")
    func tribblePosition() {
        var s = arriving { s in
            s.quests.reactor = 2
            s.commander.ship.tribbles = 40
            s.commander.debt = 80_000
        }
        let events = s.arrival()
        let reactor = events.firstIndex(of: .reactorWarning(status: 2))
        let tribbles = events.firstIndex(of: .tribblesDied(.halfFromReactor))
        let changed = events.firstIndex(of: .tribblesChanged(from: 40, to: 20))
        let debt = events.firstIndex(of: .debtWarning(debt: 80_000))
        #expect(reactor == 0 && tribbles == 1 && changed == 2 && debt == 3)
    }

    @Test("TRV-058 Og egg: only at Og, one unit of every good and a free shield slot; cargo and basis cleared")
    func easterEgg() {
        func og(_ adjust: (inout GameState) -> Void = { _ in }) -> GameState {
            var s = makeEngine().state
            s.commander.ship = freshShip(.wasp, s)
            s.commander.currentSystem = SystemID.og
            s.commander.ship.cargo = Array(repeating: 1, count: 10)
            s.commander.priceCargo = Array(repeating: 50, count: 10)
            adjust(&s)
            return s
        }
        var hit = og()
        #expect(hit.arrivalEasterEgg() == [.easterEgg])
        #expect(hit.commander.ship.shields == [ShieldInstance(type: .lightning, charge: hit.ruleset.tables.shield(.lightning).power)])
        #expect(hit.commander.ship.cargo == Array(repeating: 0, count: 10) && hit.commander.priceCargo == Array(repeating: 0, count: 10))
        let two = og { $0.commander.ship.cargo[3] = 2 }
        let full = og { s in s.commander.ship.shields = [ShieldInstance(type: .energy, charge: 1), ShieldInstance(type: .energy, charge: 1)] }
        let elsewhere = og { $0.commander.currentSystem = SystemID.acamar }
        for s in [two, full, elsewhere] {
            var copy = s
            #expect(copy.arrivalEasterEgg().isEmpty && copy == s)
        }
    }

    @Test("TRV-075 Gemulon counter: +n capped at 8; reaching 8 invades (event, Pre-Agricultural, Anarchy)")
    func gemulon() {
        var s = makeEngine { $0.quests.gemulon = 3 }.state
        #expect(s.incDays(2).isEmpty && s.quests.gemulon == 5)
        let events = s.incDays(30)
        #expect(events == [.gemulonInvaded] && s.quests.gemulon == QuestStatus.Gemulon.tooLate)
        let g = s.galaxy.systems[SystemID.gemulon]
        #expect(g.techLevel == .preAgricultural && g.politics == .anarchy && g.specialEvent == .gemulonInvaded)
        #expect(s.incDays(1).isEmpty && s.quests.gemulon == QuestStatus.Gemulon.tooLate)
        var idle = makeEngine().state
        _ = idle.incDays(5)
        #expect(idle.quests.gemulon == 0)
    }

    @Test("TRV-077 reactor counter: while aboard, +n capped at 20")
    func reactorCounter() {
        var s = makeEngine { $0.quests.reactor = 3 }.state
        _ = s.incDays(4)
        #expect(s.quests.reactor == 7)
        _ = s.incDays(30)
        #expect(s.quests.reactor == QuestStatus.Reactor.date)
        var delivered = makeEngine { $0.quests.reactor = QuestStatus.Reactor.delivered }.state
        _ = delivered.incDays(3)
        #expect(delivered.quests.reactor == QuestStatus.Reactor.delivered)
    }

    @Test("TRV-078 experiment counter: +n capped at 12; at 12 rip chance 25, Daled fails, event and news; then −n per call")
    func experiment() {
        var s = makeEngine { $0.quests.experiment = 5 }.state
        #expect(s.incDays(3).isEmpty && s.quests.experiment == 8)
        let events = s.incDays(10)
        #expect(events == [.experimentPerformed] && s.quests.experiment == QuestStatus.Experiment.performed)
        #expect(s.quests.fabricRipProbability == 25 && s.galaxy.systems[SystemID.daled].specialEvent == .experimentFailed)
        #expect(s.newsEvents.contains(.experimentPerformed))
        _ = s.incDays(1)
        #expect(s.quests.fabricRipProbability == 24)
        _ = s.incDays(30)
        #expect(s.quests.fabricRipProbability == -6)   // may go negative
        _ = s.incDays(1)
        #expect(s.quests.fabricRipProbability == -6)   // no longer > 0
    }

    @Test("TRV-079 Jarek and Wild impatience: concerned at 5, impatient at 10 (skills 0), +1 per call up to 11")
    func jarekWild() {
        for id in [CrewID.jarek, CrewID.wild] {
            var s = crewed([id])
            func status() -> Int { id == CrewID.jarek ? s.quests.jarek : s.quests.wild }
            func set(_ v: Int) { if id == CrewID.jarek { s.quests.jarek = v } else { s.quests.wild = v } }
            set(4)
            #expect(s.incDays(30).isEmpty && status() == 5)
            #expect(s.incDays(1) == [.passengerConcerned(crewID: id)] && status() == 6)
            set(10)
            #expect(s.incDays(1) == [.passengerImpatient(crewID: id)] && status() == 11)
            #expect(s.mercenaries[id].skills == [0, 0, 0, 0])
            #expect(s.incDays(1).isEmpty && status() == 11)
        }
    }

    @Test("TRV-080 Princess impatience: concerned at 9, impatient at 13 (skills 0), +1 per call up to 14")
    func princess() {
        var s = crewed([CrewID.princess]) { $0.quests.princess = 9 }
        #expect(s.incDays(5) == [.passengerConcerned(crewID: CrewID.princess)] && s.quests.princess == 10)
        s.quests.princess = 13
        #expect(s.incDays(1) == [.passengerImpatient(crewID: CrewID.princess)] && s.quests.princess == 14)
        #expect(s.mercenaries[CrewID.princess].skills == [0, 0, 0, 0])
        #expect(s.incDays(1).isEmpty && s.quests.princess == 14)
        // Not aboard: no counting.
        var away = makeEngine { $0.quests.princess = 9 }.state
        #expect(away.incDays(1).isEmpty && away.quests.princess == 9)
    }
}
