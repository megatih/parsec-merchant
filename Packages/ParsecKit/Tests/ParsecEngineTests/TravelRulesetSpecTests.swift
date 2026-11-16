// SPDX-License-Identifier: GPL-2.0-or-later
// TRV {M5} and RUL-062…069, 118, 151: the Palm and Modern travel variants (docs/specs/TRV.md, RUL.md).
import Testing
@testable import ParsecEngine

// MARK: Helpers

/// A Firefly with one Energy shield drained to `charge`.
private func shieldedShip(_ s: GameState, charge: Int = 1) -> Ship {
    var ship = freshShip(.firefly, s)
    ship.shields = [ShieldInstance(type: .energy, charge: charge)]
    return ship
}

private func shieldsFull(_ s: GameState) -> Bool {
    s.commander.ship.shields.allSatisfy { $0.charge == s.ruleset.tables.shield($0.type).power }
}

/// Wild aboard with no weapon at all, so `wildWillLeave` holds in every ruleset.
private func wildAboardUnarmed(_ s: inout GameState) {
    s.commander.ship = freshShip(.bumblebee, s)
    s.commander.ship.weapons = []
    s.hireCrew(CrewID.wild)
    s.quests.wild = QuestStatus.Wild.started
}

/// A system that is neither the current one nor a wormhole end reachable from it.
private func otherSystem(_ s: GameState, excluding: Set<Int> = []) -> Int {
    let cur = s.commander.currentSystem
    return s.galaxy.systems.indices.first {
        $0 != cur && !excluding.contains($0) && !s.galaxy.wormholeExists(from: cur, to: $0)
    } ?? 1
}

// MARK: §1 Reachability and targets

@Suite("Travel rulesets: reachability and targets (TRV {M5})")
struct TravelRulesetTargetTests {
    @Test("TRV-002 Palm reachability is wormhole or 0 < distance ≤ fuel: the destOk predicate with Palm distance")
    func palmReachability() {
        for fuel in [0, 5, 14] {
            var s = makeEngine(.palm122).state
            s.commander.ship.fuel = fuel
            let cur = s.commander.currentSystem
            for i in s.galaxy.systems.indices {
                let d = GalaxyGenerator.distance(s.galaxy.systems[cur], s.galaxy.systems[i], rule: s.ruleset.flags.distance)
                let palm = s.galaxy.wormholeExists(from: cur, to: i) || (d > 0 && d <= fuel)
                #expect(s.destinationOK(i) == palm)
            }
        }
    }

    @Test("TRV-005 Palm selects a wormhole only at the current system; elsewhere wormholeNotAtCurrentSystem, unchanged")
    func palmWormholeScope() {
        var e = makeEngine(.palm122)
        let holes = e.state.galaxy.wormholes
        e.state.commander.currentSystem = holes[0]
        let before = e.state
        #expect(e.perform(.selectWormhole(holes[1])).rejection == .wormholeNotAtCurrentSystem)
        #expect(e.state == before)
        #expect(e.perform(.selectWormhole(holes[0])).rejection == nil)
        #expect(e.state.warpSystem == holes[1])
        // Windows 2.01 targets the far end of any wormhole.
        var w = makeEngine()
        w.state.commander.currentSystem = w.state.galaxy.wormholes[0]
        #expect(w.perform(.selectWormhole(w.state.galaxy.wormholes[1])).rejection == nil)
        #expect(w.state.warpSystem == w.state.galaxy.wormholes[2])
    }

    @Test("TRV-008 Palm selectNextTarget scans indices from the old target with wrap-around; none reachable → unchanged")
    func palmNextTarget() {
        var e = makeEngine(.palm122)
        let s0 = e.state
        let n = s0.galaxy.systems.count
        // Start from an out-of-range target so Palm and Windows differ.
        let start = unreachableTarget(s0) ?? 0
        func scan(_ forward: Bool) -> Int {
            var i = start
            repeat { i = (i + (forward ? 1 : -1) + n) % n } while !s0.destinationOK(i) && i != start
            return i
        }
        for forward in [true, false] {
            e.state = s0
            e.state.warpSystem = start
            #expect(e.perform(.selectNextTarget(forward: forward)).rejection == nil)
            #expect(e.state.warpSystem == scan(forward))
        }
        // Nothing reachable: no fuel and not at a wormhole.
        e.state = s0
        e.state.commander.ship.fuel = 0
        if !s0.galaxy.wormholes.contains(s0.commander.currentSystem) {
            e.state.warpSystem = start
            let before = e.state
            _ = e.perform(.selectNextTarget(forward: true))
            #expect(e.state == before)
        }
    }
}

// MARK: §2 Departure checks and the jump

@Suite("Travel rulesets: departure checks and singularity (TRV {M5}, RUL-067, RUL-068)")
struct TravelRulesetDepartureTests {
    @Test("TRV-013 RUL-067 Palm asks for Wild's consent before the debt and fee checks; Windows checks the debt first")
    func checkOrder() throws {
        func setup(_ s: inout GameState) {
            wildAboardUnarmed(&s)
            s.warpSystem = plainTarget(s) ?? 1
            s.commander.debt = 100_001
        }
        var palm = makeEngine(.palm122, setup)
        let pr = palm.perform(.warp)
        #expect(pr.decision == .confirm(Confirmation(.wildLeavesWithoutLaser)))
        var win = makeEngine(.windows201, setup)
        #expect(win.perform(.warp).rejection == .debtTooLargeToTravel)
        // Palm's remaining checks keep the source order: wages, then insurance, then the wormhole tax.
        var fees = makeEngine(.palm122) { s in
            s.commander.currentSystem = s.galaxy.wormholes[0]
            s.warpSystem = s.galaxy.wormholes[1]
            s.commander.cash = 0
        }
        #expect(fees.perform(.warp).rejection == .cannotPayWormholeTax)
        fees.state.commander.ship.escapePod = true
        fees.state.commander.insurance = true
        #expect(fees.perform(.warp).rejection == .cannotPayInsurance)
    }

    @Test("TRV-015 Palm: accepting Wild's departure commits it even when the debt check then fails")
    func wildRemovedThenBlocked() {
        var e = makeEngine(.palm122) { s in
            wildAboardUnarmed(&s)
            s.warpSystem = plainTarget(s) ?? 1
            s.commander.debt = 100_001
        }
        let cur = e.state.commander.currentSystem
        let r = e.perform(.warp, acknowledging: [.wildLeavesWithoutLaser])
        #expect(r.rejection == nil)
        #expect(r.events == [.wildLeftShip, .departureBlocked(.debtTooLargeToTravel)])
        #expect(e.state.quests.wild == QuestStatus.Wild.notStarted)
        #expect(e.state.phase == .docked && e.state.commander.currentSystem == cur)
    }

    @Test("TRV-020 Palm jumps to the tracked system: none → singularityNoTarget, current → rejected, else warp target := tracked")
    func palmJumpTarget() {
        var e = makeEngine(.palm122) { $0.quests.canSuperWarp = true }
        let cur = e.state.commander.currentSystem
        let t = otherSystem(e.state)
        let y = otherSystem(e.state, excluding: [t])
        e.state.warpSystem = y
        e.state.trackedSystem = nil
        #expect(e.perform(.jump).rejection == .singularityNoTarget)
        e.state.trackedSystem = cur
        #expect(e.perform(.jump).rejection == .singularityTargetIsCurrentSystem)
        e.state.trackedSystem = t
        #expect(e.state.jumpPreview.destination == t)
        #expect(e.perform(.jump).decision == .confirm(Confirmation(.useSingularity, amounts: [t])))
        // Freeze the trip right after departure: Palm jumps count as wormhole arrivals (Scarab trap at click 20).
        e.state.galaxy.systems[t].specialEvent = .scarabDestroyed
        e.state.quests.scarab = QuestStatus.Scarab.hunting
        let r = e.perform(.jump, acknowledging: [.useSingularity])
        #expect(r.events.contains(.departed(from: cur, to: t, viaWormhole: true)))
        #expect(e.state.warpSystem == t && !e.state.quests.canSuperWarp)
        // Windows 2.01 jumps to the warp target.
        var w = makeEngine { $0.quests.canSuperWarp = true }
        w.state.warpSystem = y
        w.state.trackedSystem = t
        #expect(w.state.jumpPreview.destination == y)
    }

    @Test("TRV-024 RUL-068 Palm singularity: no fees, interest, day or no-claim; recharge, heal, decay (old day), wormhole flag, news")
    func palmSingularity() {
        var s = makeEngine(.palm122).state
        s.commander.ship = shieldedShip(s)
        s.warpSystem = otherSystem(s)
        s.commander.cash = 1_000
        s.commander.debt = 1_000
        s.commander.ship.escapePod = true
        s.commander.insurance = true
        s.commander.noClaim = 5
        s.commander.days = 3
        s.commander.policeRecordScore = 10
        s.specialShips.spaceMonster.hull = 100
        s.newsEvents = [.caughtLittering]
        let before = s
        let events = s.depart(viaSingularity: true)
        #expect(s.commander.cash == before.commander.cash && s.commander.debt == before.commander.debt)
        #expect(s.commander.days == 3 && s.commander.noClaim == 5)
        #expect(s.commander.ship.fuel == before.commander.ship.fuel)
        #expect(shieldsFull(s))
        #expect(s.specialShips.spaceMonster.hull == 105)
        #expect(s.commander.policeRecordScore == 9)
        #expect(s.arrivedViaWormhole)
        #expect(s.newsEvents == [.experimentArrival])
        #expect(events.last == .departed(from: before.commander.currentSystem, to: before.warpSystem, viaWormhole: true))
        // Windows 2.01: none of the Palm side effects, and the headline is cleared four lines later.
        var w = makeEngine().state
        w.commander.ship = shieldedShip(w)
        w.warpSystem = otherSystem(w)
        w.commander.days = 3
        w.commander.policeRecordScore = 10
        w.specialShips.spaceMonster.hull = 100
        _ = w.depart(viaSingularity: true)
        #expect(!w.arrivedViaWormhole && !shieldsFull(w))
        #expect(w.specialShips.spaceMonster.hull == 100 && w.commander.policeRecordScore == 10)
        #expect(w.newsEvents.isEmpty)
    }

    @Test("TRV-025 Modern singularity: Windows behaviour plus the MOD-003 decay on the unchanged day; no heal, no recharge")
    func modernSingularity() {
        var s = makeEngine(.modern).state
        s.commander.ship = shieldedShip(s)
        s.warpSystem = otherSystem(s)
        s.commander.days = 3
        s.commander.policeRecordScore = 10
        s.specialShips.spaceMonster.hull = 100
        let cash = s.commander.cash
        _ = s.depart(viaSingularity: true)
        #expect(s.commander.policeRecordScore == 9)
        #expect(s.commander.days == 3 && s.commander.cash == cash)
        #expect(s.specialShips.spaceMonster.hull == 100)
        #expect(!shieldsFull(s) && !s.arrivedViaWormhole)
        #expect(s.newsEvents.isEmpty)
    }
}

// MARK: §4 Departure pipeline

@Suite("Travel rulesets: departure pipeline (TRV {M5}, RUL-062, RUL-063, RUL-069)")
struct TravelRulesetPipelineTests {
    private static func departing(_ id: RulesetID) -> GameEngine {
        makeEngine(id) { s in
            armDepartureFreeze(&s)
            s.commander.ship = shieldedShip(s)
            s.commander.cash = 100_000
            s.commander.debt = 1_000
            s.commander.ship.escapePod = true
            s.commander.insurance = true
            s.commander.noClaim = 5
            s.commander.days = 2
            s.commander.policeRecordScore = 10
            s.specialShips.spaceMonster.hull = 100
            s.newsEvents = [.caughtLittering]
        }
    }

    @Test("TRV-031 RUL-063 Palm departure: fees, shield recharge, wormhole, news reset, interest, day, no-claim, heal, decay")
    func palmDeparture() throws {
        var e = Self.departing(.palm122)
        let b = e.state
        let r = e.perform(.warp)
        guard case let .encounter(enc) = e.state.phase else { Issue.record("expected the click-20 trap"); return }
        #expect(enc.clicks == 20)
        let s = e.state
        let fees = b.mercenaryCosts + b.insuranceCosts + b.wormholeCosts
        #expect(s.commander.cash == b.commander.cash - fees - b.interestCosts)
        #expect(shieldsFull(s))
        #expect(s.arrivedViaWormhole && s.commander.ship.fuel == b.commander.ship.fuel)
        #expect(s.newsEvents.isEmpty)
        #expect(s.commander.days == 3 && s.commander.noClaim == 6)
        #expect(s.specialShips.spaceMonster.hull == 105)
        #expect(s.commander.policeRecordScore == 9)
        #expect(r.events.contains(.departed(from: b.commander.currentSystem, to: b.warpSystem, viaWormhole: true)))
        // Windows 2.01: no departure recharge, IncDays decay (10 − 1/3 = 10), no-claim through IncDays.
        var w = Self.departing(.windows201)
        _ = w.perform(.warp)
        #expect(!shieldsFull(w.state))
        #expect(w.state.commander.policeRecordScore == 10 && w.state.commander.noClaim == 6)
    }

    @Test("RUL-069 every ruleset makes the first of its 20 encounter checks at click 20")
    func twentyChecks() {
        for id in RulesetID.allCases {
            #expect(Ruleset.named(id).flags.travel.transitClicks == 20)
            var e = Self.departing(id)
            let r = e.perform(.warp)
            #expect(r.events.contains { if case let .encounterStarted(_, _, clicks, _) = $0 { clicks == 20 } else { false } })
        }
    }

    @Test("TRV-032 RUL-062 Palm heals the Space Monster ×105/100 per warp (19 stays 19, cap 500); Windows compounds per day")
    func monsterRegeneration() {
        for (hull, healed) in [(100, 105), (19, 19), (490, 500)] {
            var s = makeEngine(.palm122).state
            s.warpSystem = plainTarget(s) ?? 1
            s.specialShips.spaceMonster.hull = hull
            _ = s.depart(viaSingularity: false)
            #expect(s.specialShips.spaceMonster.hull == healed)
        }
        var palm = makeEngine(.palm122).state
        palm.specialShips.spaceMonster.hull = 200
        _ = palm.incDays(3)
        #expect(palm.specialShips.spaceMonster.hull == 200)
        var win = makeEngine().state
        win.specialShips.spaceMonster.hull = 200
        _ = win.incDays(3)
        #expect(win.specialShips.spaceMonster.hull == 231)
    }

    @Test("TRV-033 MOD-003 per-warp decay in Modern and Palm runs after the day advance; Modern IncDays no longer decays")
    func perWarpDecayTiming() {
        for id in [RulesetID.modern, .palm122] {
            var s = makeEngine(id).state
            s.warpSystem = plainTarget(s) ?? 1
            s.commander.days = 2
            s.commander.policeRecordScore = 10
            _ = s.depart(viaSingularity: false)
            #expect(s.commander.days == 3 && s.commander.policeRecordScore == 9)
            var jail = makeEngine(id).state
            jail.commander.policeRecordScore = 20
            _ = jail.incDays(30)
            #expect(jail.commander.policeRecordScore == 20)
        }
        var win = makeEngine().state
        win.commander.policeRecordScore = 20
        _ = win.incDays(30)
        #expect(win.commander.policeRecordScore == 10)
    }

    @Test("TRV-034 per-warp decay examples (Normal, Hard, Impossible)")
    func decayExamples() {
        let cases: [(Difficulty, Int, Int, Int)] = [
            (.normal, 9, 10, 9), (.normal, 9, -10, -9), (.normal, 10, 10, 10), (.hard, 10, -10, -10), (.hard, 12, -10, -9),
            (.impossible, 12, 3, 2), (.impossible, 12, -8, -7)
        ]
        for (d, days, record, expected) in cases {
            var s = makeEngine(.modern, difficulty: d).state
            s.commander.days = days
            s.commander.policeRecordScore = record
            s.perWarpRecordDecay()
            #expect(s.commander.policeRecordScore == expected, "D \(d) days \(days) record \(record)")
        }
    }

    @Test("TRV-035 Palm clears the news before the day advance, so EXPERIMENTPERFORMED reaches the arrival paper")
    func newsResetOrder() {
        for (id, survives) in [(RulesetID.palm122, true), (.windows201, false)] {
            var s = makeEngine(id).state
            s.warpSystem = plainTarget(s) ?? 1
            s.quests.experiment = QuestStatus.Experiment.date
            let events = s.depart(viaSingularity: false)
            #expect(events.contains(.experimentPerformed))
            #expect(s.newsEvents.contains(.experimentPerformed) == survives)
        }
    }

    @Test("TRV-037 Palm draws the rip percentage even at probability 25, then rand(systems); Windows skips that draw")
    func fabricRipDraws() throws {
        for (id, drawFirst) in [(RulesetID.palm122, true), (.windows201, false)] {
            var base = makeEngine(id).state
            base.warpSystem = plainTarget(base) ?? 1
            base.quests.experiment = QuestStatus.Experiment.performed
            // No rip: the RNG after the departure's price draws.
            var calm = base
            calm.quests.fabricRipProbability = 0
            _ = calm.depart(viaSingularity: false)
            var rng = calm.rng
            if drawFirst { _ = rng.next(below: 100) }
            let expected = rng.next(below: base.galaxy.systems.count)
            // IncDays lowers 26 to 25 before the test.
            var ripped = base
            ripped.quests.fabricRipProbability = 26
            let events = ripped.depart(viaSingularity: false)
            #expect(events.contains(.fabricRip(newDestination: expected)))
            #expect(ripped.warpSystem == expected && ripped.rng == rng)
        }
    }

    @Test("TRV-048 RUL-064 Palm per-click repair is rand(Engineer) >> 1; Windows rand(Engineer)")
    func clickRepair() {
        for (id, halved) in [(RulesetID.palm122, true), (.windows201, false)] {
            var s = makeEngine(id).state
            let strength = s.commander.ship.hullStrength(s.ruleset)
            s.commander.ship.hull = strength - 60
            var rng = s.rng
            let roll = rng.next(below: s.shipSkills[3])
            s.performClickRepairs()
            #expect(s.commander.ship.hull == strength - 60 + (halved ? roll >> 1 : roll))
        }
    }
}

// MARK: §7 Arrival

@Suite("Travel rulesets: arrival pipeline (TRV {M5}, RUL-065, RUL-066, RUL-118, RUL-151)")
struct TravelRulesetArrivalTests {
    private static func arriving(_ id: RulesetID, _ adjust: (inout GameState) -> Void = { _ in }) -> GameState {
        var s = makeEngine(id).state
        s.warpSystem = plainTarget(s) ?? 1
        adjust(&s)
        return s
    }

    @Test("TRV-060 RUL-066 Palm arrival order: debt notices, market, reactor, tribbles, repair, egg, news; Windows reactor first")
    func arrivalOrder() throws {
        func setup(_ s: inout GameState) {
            s.commander.debt = 80_000
            s.commander.days = 10
            s.quests.reactor = 2
            s.commander.ship.tribbles = 40
            s.galaxy.systems[s.warpSystem].specialEvent = .dragonfly
        }
        var palm = Self.arriving(.palm122, setup)
        let x = palm.warpSystem
        let pe = palm.arrival()
        let grown = palm.commander.ship.tribbles
        #expect((21...30).contains(grown))
        #expect(pe == [.debtWarning(debt: 80_000), .debtReminder(debt: 80_000), .reactorWarning(status: 2),
                       .tribblesDied(.halfFromReactor), .tribblesChanged(from: 40, to: grown), .arrived(system: x)])
        #expect(palm.commander.currentSystem == x && palm.galaxy.systems[x].visited)
        #expect(palm.newsEvents == [.dragonfly])
        var win = Self.arriving(.windows201, setup)
        let we = win.arrival()
        #expect(we == [.reactorWarning(status: 2), .tribblesDied(.halfFromReactor), .tribblesChanged(from: 40, to: 20),
                       .debtWarning(debt: 80_000), .arrived(system: win.warpSystem)])
    }

    @Test("TRV-061 Palm meltdown: with a pod Arrival() runs twice and the pipeline stops; without one the game ends")
    func palmMeltdown() {
        var s = Self.arriving(.palm122) {
            $0.quests.reactor = QuestStatus.Reactor.date
            $0.commander.ship.escapePod = true
            $0.commander.ship.tribbles = 50
        }
        var replica = s
        replica.arrivalMarket()
        replica.arrivalMarket()
        let events = s.arrival()
        #expect(events.first == .reactorMeltdown)
        #expect(events.contains { if case .escapePodUsed = $0 { true } else { false } })
        #expect(events.last == .arrived(system: s.commander.currentSystem))
        #expect(!events.contains { if case .tribblesChanged = $0 { true } else { false } })
        #expect(s.rng == replica.rng)
        #expect(s.commander.ship.type == .flea && s.quests.reactor == QuestStatus.Reactor.notStarted)
        var dead = Self.arriving(.palm122) { $0.quests.reactor = QuestStatus.Reactor.date }
        let de = dead.arrival()
        #expect(de == [.reactorMeltdown, .gameEnded(.killed, score: dead.score(for: .killed))])
        #expect(dead.phase == .gameOver(.killed))
    }

    @Test("TRV-062 after a Palm arrest only Arrival() runs: no debt, reactor, tribble or repair steps; Windows runs everything")
    func afterArrest() {
        func encounterState(_ id: RulesetID) -> GameEngine {
            var e = makeEngine(id) { s in
                s.warpSystem = plainTarget(s) ?? 1
                s.commander.debt = 80_000
                s.quests.reactor = 2
                s.commander.ship.tribbles = 40
                s.commander.ship.hull -= 30
                s.encounterTransit = TransitState(destination: s.warpSystem, clicksRemaining: 3, viaWormhole: false, hadEncounter: true)
            }
            let opp = freshShip(.gnat, e.state)
            e.state.phase = .encounter(EncounterState(type: .policeInspect, opponent: opp, clicks: 3))
            return e
        }
        var palm = encounterState(.palm122)
        let hull = palm.state.commander.ship.hull
        // The arrest sequence runs first (Palm's short Arrival is part of it, RUL-137), then the arrival step.
        let jail = palm.state.arrested()
        let pe = palm.finishEncounter(.arrested)
        #expect(jail.contains { if case .arrested = $0 { true } else { false } })
        #expect(pe == [.arrived(system: palm.state.warpSystem)])
        #expect(palm.state.commander.ship.tribbles == 40 && palm.state.commander.ship.hull == hull)
        #expect(palm.state.commander.currentSystem == palm.state.warpSystem && palm.state.phase == .docked)
        var win = encounterState(.windows201)
        let we = win.finishEncounter(.arrested)
        #expect(we.contains(.debtWarning(debt: 80_000)) && we.contains(.reactorWarning(status: 2)))
    }

    @Test("TRV-063 RUL-063 Palm arrival repair always draws rand(Engineer) and does not recharge shields")
    func palmArrivalRepair() {
        for (id, palm) in [(RulesetID.palm122, true), (.windows201, false)] {
            var s = Self.arriving(id) { $0.commander.ship = shieldedShip($0) }
            let before = s.rng
            _ = s.arrivalRepairs()
            var expected = before
            if palm { _ = expected.next(below: s.shipSkills[3]) }
            #expect(s.rng == expected)
            #expect(s.commander.ship.hull == s.commander.ship.hullStrength(s.ruleset))
            #expect(shieldsFull(s) == !palm)
        }
    }

    @Test("TRV-064 RUL-065 Palm auto-buy is partial; a fuel shortfall with auto-repair on reports both and skips repairs")
    func palmAutoBuy() {
        var s = Self.arriving(.palm122) { s in
            s.options.autoFuel = true
            s.commander.ship.fuel = s.commander.ship.fuelTanks(s.ruleset) - 5
            s.commander.cash = 2 * s.commander.ship.spec(s.ruleset).fuelCost
        }
        let tanks = s.commander.ship.fuelTanks(s.ruleset)
        #expect(s.arrivalRepairs() == [.autoFuelFailed])
        #expect(s.commander.ship.fuel == tanks - 3 && s.commander.cash == 0)
        var both = Self.arriving(.palm122) { s in
            s.options.autoFuel = true
            s.options.autoRepair = true
            s.commander.ship.fuel = 0
            s.commander.ship.hull = 10
            s.commander.cash = 0
        }
        #expect(both.arrivalRepairs() == [.autoFuelFailed, .autoRepairFailed])
        // Partial repair: three points' worth of cash buys three points after the engineer's draw.
        var rep = Self.arriving(.palm122) { s in
            s.options.autoRepair = true
            s.commander.ship.hull = 10
            s.commander.cash = 3 * s.commander.ship.spec(s.ruleset).repairCost
        }
        var rng = rep.rng
        let drawn = rng.next(below: rep.shipSkills[3])
        #expect(rep.arrivalRepairs() == [.autoRepairFailed])
        #expect(rep.commander.ship.hull == 10 + drawn + 3 && rep.commander.cash == 0)
        // Windows 2.01: all or nothing.
        var win = Self.arriving(.windows201) { s in
            s.options.autoRepair = true
            s.commander.ship.hull = 10
            s.commander.cash = 3 * s.commander.ship.spec(s.ruleset).repairCost
        }
        let cash = win.commander.cash
        #expect(win.arrivalRepairs() == [.autoRepairFailed])
        #expect(win.commander.cash == cash)
    }

    @Test("TRV-066 Palm Og egg: the message without a free slot installs nothing; with a slot the Lightning shield")
    func palmEgg() {
        func og(_ id: RulesetID, slot: Bool) -> GameState {
            var s = makeEngine(id).state
            s.commander.currentSystem = SystemID.og
            s.commander.ship = freshShip(slot ? .firefly : .gnat, s)
            s.commander.ship.cargo = Array(repeating: 1, count: 10)
            return s
        }
        var none = og(.palm122, slot: false)
        #expect(none.arrivalEasterEgg() == [.easterEggNoShieldSlot])
        #expect(none.commander.ship.cargo == Array(repeating: 1, count: 10) && none.commander.ship.shields.isEmpty)
        var slot = og(.palm122, slot: true)
        #expect(slot.arrivalEasterEgg() == [.easterEgg])
        #expect(slot.commander.ship.shields.map(\.type) == [.lightning] && slot.commander.ship.cargo.allSatisfy { $0 == 0 })
        var win = og(.windows201, slot: false)
        #expect(win.arrivalEasterEgg().isEmpty)
    }

    @Test("TRV-067 Palm marks the system visited and adds its news flag at the end of the arrival step")
    func palmVisitedAndNews() {
        var s = Self.arriving(.palm122) { s in
            s.galaxy.systems[s.warpSystem].visited = false
            s.galaxy.systems[s.warpSystem].specialEvent = .scarab
        }
        let x = s.warpSystem
        let events = s.arrival()
        #expect(events.last == .arrived(system: x))
        #expect(s.galaxy.systems[x].visited && s.newsEvents == [.scarab])
    }

    @Test("RUL-118 MOD-018 debt warning and reminder both fire in Modern and Palm; Windows reports only the warning")
    func debtNotices() {
        for (id, both) in [(RulesetID.modern, true), (.palm122, true), (.windows201, false)] {
            var s = makeEngine(id).state
            s.commander.debt = 75_000
            s.commander.days = 15
            let expected: [GameEvent] = both ? [.debtWarning(debt: 75_000), .debtReminder(debt: 75_000)] : [.debtWarning(debt: 75_000)]
            #expect(s.debtNotices() == expected)
            s.commander.debt = 500
            #expect(s.debtNotices() == [.debtReminder(debt: 500)])
        }
    }

    @Test("RUL-151 tribbles: Palm reactor halves (< 10 → 0) then grows, narcotics reset to 1…3, food 100+rand(food×100); C# differs")
    func tribbleAlgorithm() throws {
        // Reactor branch.
        var r1 = Self.arriving(.palm122) { $0.quests.reactor = 5; $0.commander.ship.tribbles = 15 }
        #expect(r1.arrivalTribbles().first == .tribblesDied(.allFromReactor))
        #expect(r1.commander.ship.tribbles == 0)
        var r2 = Self.arriving(.palm122) { $0.quests.reactor = 5; $0.commander.ship.tribbles = 40 }
        _ = r2.arrivalTribbles()
        #expect((21...30).contains(r2.commander.ship.tribbles))
        var wr = Self.arriving(.windows201) { $0.quests.reactor = 5; $0.commander.ship.tribbles = 15 }
        _ = wr.arrivalTribbles()
        #expect(wr.commander.ship.tribbles == 0)
        // Narcotics branch: the count resets to 1 + rand(3), then grows by 1.
        var n = Self.arriving(.palm122) { s in
            s.commander.ship.tribbles = 5_000
            s.commander.ship.cargo[TradeItemType.narcotics.rawValue] = 2
        }
        let ne = n.arrivalTribbles()
        #expect((2...4).contains(n.commander.ship.tribbles))
        let converted = 2 - n.commander.ship.cargo[TradeItemType.narcotics.rawValue]
        #expect(ne.first == .tribblesDied(.narcotics(converted: converted)))
        #expect(n.commander.ship.cargo[TradeItemType.furs.rawValue] == converted)
        // Food branch, replayed draw by draw.
        var f = Self.arriving(.palm122) { s in
            s.commander.ship.tribbles = 100
            s.commander.ship.cargo[TradeItemType.food.rawValue] = 5
        }
        var rng = f.rng
        var t = 100 + 100 + rng.next(below: 500)
        let left = rng.next(below: 5)
        t += 1 + rng.next(below: t)
        let fe = f.arrivalTribbles()
        #expect(f.commander.ship.tribbles == t && f.commander.ship.cargo[TradeItemType.food.rawValue] == left)
        #expect(fe.first == .tribblesAteFood(eaten: 5 - left))
        #expect(f.rng == rng)
    }
}

// MARK: §9 Day advance

@Suite("Travel rulesets: IncDays (TRV {M5})")
struct TravelRulesetDayTests {
    @Test("TRV-074 Palm IncDays only moves days and quest counters: no no-claim, decay, heal or passenger impatience")
    func palmIncDays() {
        var s = makeEngine(.palm122).state
        s.commander.ship.escapePod = true
        s.commander.insurance = true
        s.commander.noClaim = 5
        s.commander.policeRecordScore = -10
        s.specialShips.spaceMonster.hull = 100
        s.hireCrew(CrewID.jarek)
        s.quests.jarek = 5
        s.quests.reactor = 3
        let events = s.incDays(3)
        #expect(events.isEmpty)
        #expect(s.commander.days == makeEngine(.palm122).state.commander.days + 3)
        #expect(s.commander.noClaim == 5 && s.commander.policeRecordScore == -10)
        #expect(s.specialShips.spaceMonster.hull == 100 && s.quests.jarek == 5)
        #expect(s.quests.reactor == 6)
    }

    @Test("TRV-076 Palm Gemulon counter is uncapped (7 + 30 → 37) and invades at ≥ 8; Windows stops at 8")
    func palmGemulon() {
        var s = makeEngine(.palm122).state
        s.quests.gemulon = 7
        let events = s.incDays(30)
        #expect(s.quests.gemulon == 37 && events.contains(.gemulonInvaded))
        #expect(s.galaxy.systems[SystemID.gemulon].specialEvent == .gemulonInvaded)
        var w = makeEngine().state
        w.quests.gemulon = 7
        _ = w.incDays(30)
        #expect(w.quests.gemulon == QuestStatus.Gemulon.tooLate)
    }
}
