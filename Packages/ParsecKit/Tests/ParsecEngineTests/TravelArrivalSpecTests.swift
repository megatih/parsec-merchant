// SPDX-License-Identifier: GPL-2.0-or-later
// TRV §8 and §9 (split from TravelSpecTests.swift for the file-length lint); helpers live there.
import Foundation
import Testing
@testable import ParsecEngine

// MARK: §8 Arrival pipeline

@Suite("Travel spec: arrival (TRV §8)")
struct TravelArrivalSpecTests {
    /// A docked state about to arrive at a plain target (the arrival is invoked directly).
    func arriving(_ adjust: (inout GameState) -> Void = { _ in }) -> GameState {
        var s = makeEngine().state
        s.warpSystem = plainTarget(s) ?? 1
        adjust(&s)
        return s
    }

    @Test("TRV-050 Windows arrival order: system, reactor, tribbles, debt, repairs, market, prices, news, arrived")
    func arrivalOrder() throws {
        var s = arriving { s in
            s.trackedSystem = s.warpSystem
            s.paidForNewspaper = true
            s.quests.reactor = QuestStatus.Reactor.fuelOK + 1
            s.commander.ship.tribbles = 10
            s.commander.debt = 80_000
            s.options.autoFuel = true
            s.commander.ship.fuel = 0
            s.commander.cash = 0
            s.galaxy.systems[s.warpSystem].specialEvent = .gemulon
        }
        let d = s.warpSystem
        var ref = s
        ref.commander.currentSystem = d
        ref.galaxy.systems[d].visited = true
        ref.updatePressuresAndQuantities(arrival: d)
        ref.calculatePrices(for: d)
        let events = s.arrival()
        #expect(events == [.reactorWarning(status: 2), .tribblesChanged(from: 10, to: 0), .debtWarning(debt: 80_000),
                           .autoFuelFailed, .arrived(system: d)])
        #expect(s.commander.currentSystem == d && s.galaxy.systems[d].visited && !s.paidForNewspaper && s.trackedSystem == nil)
        #expect(s.newsEvents == [.gemulon])
        #expect(s.buyPrices == ref.buyPrices && s.sellPrices == ref.sellPrices && s.rng == ref.rng)
        // Tracking stays on when the option is off.
        var keep = arriving { s in s.trackedSystem = s.warpSystem; s.options.trackAutoOff = false }
        _ = keep.arrival()
        #expect(keep.trackedSystem == keep.commander.currentSystem)
    }

    @Test("TRV-051 the full pipeline also runs after an escape pod, with the pod days already counted")
    func pipelineAfterPod() throws {
        var e = makeEngine { s in armDepartureFreeze(&s); s.commander.debt = 80_000; s.commander.cash = 20_000 }
        _ = e.perform(.warp)
        let days = e.state.commander.days
        let events = e.finishEncounter(.escapePod)
        #expect(e.state.commander.days == days + 3)
        #expect(events.contains { if case .escapePodUsed = $0 { true } else { false } })
        #expect(events.contains { if case .debtWarning = $0 { true } else { false } })
        #expect(events.last == .arrived(system: e.state.warpSystem))
        #expect(e.state.galaxy.systems[e.state.commander.currentSystem].visited)
    }

    @Test("TRV-054 Windows debt check: warning at 75 000 or more, else the every-5-days reminder")
    func debtCheck() {
        func events(_ debt: Int, days: Int, remind: Bool = true) -> [GameEvent] {
            var s = arriving { s in s.commander.debt = debt; s.commander.days = days; s.options.remindLoans = remind }
            return s.arrival().filter { $0 == .debtWarning(debt: debt) || $0 == .debtReminder(debt: debt) }
        }
        #expect(events(75_000, days: 10) == [.debtWarning(debt: 75_000)])
        #expect(events(74_999, days: 10) == [.debtReminder(debt: 74_999)])
        #expect(events(1_000, days: 11).isEmpty)
        #expect(events(1_000, days: 10, remind: false).isEmpty)
        #expect(events(0, days: 10).isEmpty)
    }

    @Test("TRV-055 arrival repairs: rand(Engineer) hull points only when damaged, then shields fully charged")
    func arrivalRepairs() throws {
        var s = arriving { s in
            s.commander.ship = freshShip(.hornet, s)
            s.commander.ship.shields = [ShieldInstance(type: .energy, charge: 3)]
        }
        let rngBefore = s.rng
        _ = s.arrivalRepairs()
        #expect(s.rng == rngBefore)
        #expect(s.commander.ship.shields[0].charge == s.ruleset.tables.shield(.energy).power)
        let strength = s.commander.ship.hullStrength(s.ruleset)
        s.commander.ship.hull = strength - 1
        var peek = s.rng
        let draw = peek.next(below: s.shipSkills[3])
        _ = s.arrivalRepairs()
        #expect(s.commander.ship.hull == strength - 1 + min(1, draw) && s.rng == peek)
    }

    @Test("TRV-056 TRV-057 TRV-065 auto-fuel and auto-repair are all-or-nothing from cash; failures emit fuel then repair")
    func autoBuy() throws {
        let fuelCost = makeEngine().state.commander.ship.spec(makeEngine().ruleset).fuelCost
        #expect(fuelCost == 1)
        // TRV-065: a Gnat 5 parsecs short at 1 cr/parsec with cash 4 buys nothing.
        var s = arriving { s in s.options.autoFuel = true; s.commander.ship.fuel -= 5; s.commander.cash = 4 }
        #expect(s.arrivalRepairs() == [.autoFuelFailed])
        #expect(s.commander.ship.fuel == s.commander.ship.fuelTanks(s.ruleset) - 5 && s.commander.cash == 4)
        s = arriving { s in s.options.autoFuel = true; s.commander.ship.fuel -= 5; s.commander.cash = 5 }
        #expect(s.arrivalRepairs().isEmpty)
        #expect(s.commander.ship.fuel == s.commander.ship.fuelTanks(s.ruleset) && s.commander.cash == 0)
        // Repairs (after the random arrival repair, which is below the damage here).
        s = arriving { s in s.options.autoRepair = true; s.commander.ship.hull -= 50; s.commander.cash = 0 }
        #expect(s.arrivalRepairs() == [.autoRepairFailed])
        #expect(s.commander.ship.hull < s.commander.ship.hullStrength(s.ruleset))
        s = arriving { s in s.options.autoRepair = true; s.commander.ship.hull -= 50; s.commander.cash = 10_000 }
        #expect(s.arrivalRepairs().isEmpty && s.commander.ship.hull == s.commander.ship.hullStrength(s.ruleset))
        // Both fail: both events, fuel first.
        s = arriving { s in
            s.options.autoFuel = true
            s.options.autoRepair = true
            s.commander.ship.fuel = 0
            s.commander.ship.hull -= 50
            s.commander.cash = 3
        }
        #expect(s.arrivalRepairs() == [.autoFuelFailed, .autoRepairFailed])
    }

    @Test("TRV-059 the Og egg draws nothing and touches nothing prices depend on, so its position is immaterial")
    func eggPosition() throws {
        let s = arriving { s in
            s.commander.currentSystem = SystemID.og
            s.commander.ship = freshShip(.hornet, s)
            s.commander.ship.cargo = Array(repeating: 1, count: 10)
        }
        try #require(s.commander.ship.freeShieldSlots(s.ruleset) > 0)
        var a = s, b = s
        let rng = a.rng
        #expect(a.arrivalEasterEgg() == [.easterEgg])
        #expect(a.rng == rng)
        a.calculatePrices(for: SystemID.og)
        b.calculatePrices(for: SystemID.og)
        _ = b.arrivalEasterEgg()
        #expect(a == b)
    }

    @Test("TRV-068 a completed trip ends with .arrived and no decision; a game-ending arrival leaves the game over")
    func tripCompletion() throws {
        var e = makeEngine()
        let t = try #require(plainTarget(e.state))
        _ = e.perform(.selectTarget(t))
        let first = e.perform(.warp)
        if case .docked = e.state.phase {
            #expect(first.decision == nil && first.events.last == .arrived(system: t))
        } else {
            var last: [GameEvent] = []
            while case .encounter = e.state.phase { last = e.finishEncounter(.normal) }
            #expect(last.last == .arrived(system: t))
        }
        #expect(e.state.phase == .docked)
        // A reactor meltdown without an escape pod ends the game inside the pipeline.
        var s = arriving { $0.quests.reactor = QuestStatus.Reactor.date }
        let events = s.arrival()
        #expect(events == [.reactorMeltdown, .gameEnded(.killed, score: s.score(for: .killed))])  // SCORE-012
        #expect(s.phase == .gameOver(.killed))
    }
}

// MARK: §9 Day advance

@Suite("Travel spec: IncDays (TRV §9)")
struct TravelIncDaysSpecTests {
    @Test("TRV-069 IncDays: 1 per normal departure, the jail term on arrest, 3 for the pod, none for a jump")
    func incDaysCallers() throws {
        var e = makeEngine { armDepartureFreeze(&$0) }
        let d0 = e.state.commander.days
        _ = e.perform(.warp)
        #expect(e.state.commander.days == d0 + 1)
        var pod = e
        _ = pod.finishEncounter(.escapePod)
        #expect(pod.state.commander.days == d0 + 4)
        var jail = makeEngine().state
        jail.commander.policeRecordScore = -40
        let events = jail.arrested()
        #expect(events.contains { if case .arrested(term: 40, _, _) = $0 { true } else { false } })
        #expect(jail.commander.days == 40)
        var j = makeEngine { s in armDepartureFreeze(&s); s.quests.canSuperWarp = true }
        _ = j.perform(.jump, acknowledging: [.useSingularity])
        #expect(j.state.commander.days == 0)
    }

    @Test("TRV-070 Windows IncDays order: days, no-claim, decay, monster, Gemulon, reactor, experiment, passengers")
    func incDaysOrder() {
        var s = makeEngine().state
        s.commander.ship = freshShip(.beetle, s)
        s.commander.ship.crew[1] = CrewID.jarek
        s.quests.jarek = 4
        s.commander.insurance = true
        s.commander.noClaim = 5
        s.commander.policeRecordScore = -10
        s.specialShips.spaceMonster.hull = 100
        s.quests.gemulon = QuestStatus.Gemulon.date
        s.quests.reactor = 5
        s.quests.experiment = QuestStatus.Experiment.date
        let events = s.incDays(1)
        #expect(events == [.gemulonInvaded, .experimentPerformed])
        #expect(s.commander.days == 1 && s.commander.noClaim == 6 && s.commander.policeRecordScore == -9)
        #expect(s.specialShips.spaceMonster.hull == 105)
        #expect(s.quests.gemulon == QuestStatus.Gemulon.tooLate && s.galaxy.systems[SystemID.gemulon].specialEvent == .gemulonInvaded)
        #expect(s.quests.reactor == 6)
        #expect(s.quests.experiment == QuestStatus.Experiment.performed && s.quests.fabricRipProbability == 25)
        #expect(s.galaxy.systems[SystemID.daled].specialEvent == .experimentFailed && s.newsEvents == [.experimentPerformed])
        #expect(s.quests.jarek == 5)
        // The no-claim counter is stored clamped.
        s.commander.noClaim = 90
        _ = s.incDays(5)
        #expect(s.commander.noClaim == 90)
    }

    @Test("TRV-071 TRV-072 Windows record decay inside IncDays and its examples")
    func decay() {
        func decayed(_ record: Int, n: Int, _ d: Difficulty = .normal) -> Int {
            var s = makeEngine(.windows201, difficulty: d).state
            s.commander.policeRecordScore = record
            _ = s.incDays(n)
            return s.commander.policeRecordScore
        }
        #expect(decayed(10, n: 1) == 10)
        #expect(decayed(-10, n: 1) == -9)
        #expect(decayed(-10, n: 1, .hard) == -10)
        #expect(decayed(10, n: 3) == 9)
        #expect(decayed(-10, n: 3, .impossible) == -10)
        #expect(decayed(20, n: 30) == 10)
        #expect(decayed(1, n: 30) == 0)
        #expect(decayed(-6, n: 30) == -5)
        #expect(decayed(-5, n: 30) == -5)
        #expect(decayed(-20, n: 30, .hard) == -10)
    }

    @Test("TRV-073 Space Monster heal: hull × 1.05^n truncated, capped at its hull strength")
    func monsterHeal() throws {
        func healed(_ hull: Int, n: Int) -> Int {
            var s = makeEngine().state
            s.specialShips.spaceMonster.hull = hull
            _ = s.incDays(n)
            return s.specialShips.spaceMonster.hull
        }
        try #require(makeEngine().state.specialShips.spaceMonster.hullStrength(makeEngine().ruleset) == 500)
        #expect(healed(100, n: 1) == 105)
        #expect(healed(19, n: 1) == 19)
        #expect(healed(200, n: 3) == 231)
        #expect(healed(490, n: 1) == 500)
        #expect(healed(500, n: 1) == 500)
    }
}
