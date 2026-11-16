// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Testing
@testable import ParsecEngine

// MARK: Helpers

/// The first reachable destination that is not the far end of a wormhole.
func plainTarget(_ s: GameState) -> Int? {
    s.destinations.first { !s.galaxy.wormholeExists(from: s.commander.currentSystem, to: $0) }
}

/// A system the ship cannot reach with its fuel (and not through a wormhole).
func unreachableTarget(_ s: GameState) -> Int? {
    s.galaxy.systems.indices.first { $0 != s.commander.currentSystem && !s.destinationOK($0) }
}

/// Puts the commander at the first wormhole, targeting its far end, and arms the Scarab trap (ENC: a Scarab
/// encounter at click 20 after a wormhole jump) at `trap` (default: the target), so the trip stops right after the
/// departure with the transit state observable.
func armDepartureFreeze(_ s: inout GameState, trap: Int? = nil) {
    s.commander.currentSystem = s.galaxy.wormholes[0]
    s.warpSystem = s.galaxy.wormholes[1]
    s.galaxy.systems[trap ?? s.warpSystem].specialEvent = .scarabDestroyed
    s.quests.scarab = QuestStatus.Scarab.hunting
}

/// Performs `command` and ends every encounter normally until the trip is over.
func completeTrip(_ e: inout GameEngine, _ command: Command = .warp,
                  ack: Set<WarningID> = []) -> (result: StepResult, events: [GameEvent], encounters: [EncounterState]) {
    let first = e.perform(command, acknowledging: ack)
    var events = first.events
    var seen: [EncounterState] = []
    while case let .encounter(enc) = e.state.phase {
        seen.append(enc)
        events += e.finishEncounter(.normal)
    }
    return (first, events, seen)
}

/// A ship of `type` with the commander aboard.
func freshShip(_ type: ShipType, _ s: GameState) -> Ship {
    var ship = Ship(type: type, spec: s.ruleset.tables.ship(type))
    ship.crew[0] = CrewID.commander
    return ship
}

// MARK: §1 Reachability and targets

@Suite("Travel spec: reachability and targets (TRV §1)")
struct TravelTargetSpecTests {
    @Test("TRV-001 destOk: not the current system, and within fuel range or through a wormhole")
    func destOk() throws {
        var s = makeEngine().state
        let cur = s.commander.currentSystem
        #expect(!s.destinationOK(cur))
        for i in s.galaxy.systems.indices where i != cur {
            let d = GalaxyGenerator.distance(s.galaxy.systems[cur], s.galaxy.systems[i], rule: s.ruleset.flags.distance)
            #expect(s.destinationOK(i) == (d <= s.commander.ship.fuel || s.galaxy.wormholeExists(from: cur, to: i)))
        }
        s.commander.currentSystem = s.galaxy.wormholes[0]
        s.commander.ship.fuel = 0
        #expect(s.destinationOK(s.galaxy.wormholes[1]))
        #expect(s.destinations == [s.galaxy.wormholes[1]])
    }

    @Test("TRV-003 selectTarget accepts any system index, sets the target and clears the wormhole flag only")
    func selectTarget() throws {
        var e = makeEngine { $0.targetWormhole = true }
        let far = try #require(unreachableTarget(e.state))
        var expected = e.state
        expected.warpSystem = far
        expected.targetWormhole = false
        let r = e.perform(.selectTarget(far))
        #expect(r.rejection == nil && r.events.isEmpty)
        #expect(e.state == expected)
        let before = e.state
        #expect(e.perform(.selectTarget(e.state.galaxy.systems.count)).rejection == .invalidArgument)
        #expect(e.perform(.selectTarget(-1)).rejection == .invalidArgument)
        #expect(e.state == before)
    }

    @Test("TRV-004 selectWormhole targets the next wormhole in the ring from any wormhole system")
    func selectWormhole() throws {
        var e = makeEngine { s in
            s.commander.currentSystem = s.galaxy.wormholes[0]
            s.commander.ship.fuel = 0
        }
        let ring = e.state.galaxy.wormholes
        // Any wormhole may be chosen, not only the current one; the result is then out of range here.
        #expect(e.perform(.selectWormhole(ring[2])).rejection == nil)
        #expect(e.state.warpSystem == ring[3] && e.state.targetWormhole)
        #expect(!e.state.destinationOK(e.state.warpSystem))
        // The ring wraps.
        #expect(e.perform(.selectWormhole(ring[ring.count - 1])).rejection == nil)
        #expect(e.state.warpSystem == ring[0])
        // The current wormhole is always in range.
        #expect(e.perform(.selectWormhole(ring[0])).rejection == nil)
        #expect(e.state.warpSystem == ring[1] && e.state.destinationOK(ring[1]))
        let notWormhole = try #require(e.state.galaxy.systems.indices.first { !ring.contains($0) })
        let before = e.state
        #expect(e.perform(.selectWormhole(notWormhole)).rejection == .invalidArgument)
        #expect(e.state == before)
    }

    @Test("TRV-006 destinations lists every reachable system in ascending index order")
    func destinations() {
        let s = makeEngine().state
        let d = s.destinations
        #expect(!d.isEmpty)
        #expect(d == d.sorted())
        #expect(d == s.galaxy.systems.indices.filter { s.destinationOK($0) })
        #expect(!d.contains(s.commander.currentSystem))
    }

    @Test("TRV-007 selectNextTarget cycles through the destinations, wrapping, and selects wormholes as wormholes")
    func selectNext() throws {
        // Empty list: nothing changes.
        var empty = makeEngine { s in s.commander.ship.fuel = 0; s.galaxy.wormholes = [] }
        let before = empty.state
        let r = empty.perform(.selectNextTarget(forward: true))
        #expect(r.rejection == nil && r.events.isEmpty && empty.state == before)

        var e = makeEngine { s in s.commander.currentSystem = s.galaxy.wormholes[0] }
        let dest = e.state.destinations
        try #require(dest.count >= 3)
        let cur = e.state.commander.currentSystem
        func check(_ index: Int) {
            #expect(e.state.warpSystem == dest[index])
            #expect(e.state.targetWormhole == e.state.galaxy.wormholeExists(from: cur, to: dest[index]))
        }
        // The current target (the current system) is not in the list: forward picks the first, backward the last.
        e.state.warpSystem = cur
        _ = e.perform(.selectNextTarget(forward: true))
        check(0)
        _ = e.perform(.selectNextTarget(forward: true))
        check(1)
        _ = e.perform(.selectNextTarget(forward: false))
        check(0)
        _ = e.perform(.selectNextTarget(forward: false))
        check(dest.count - 1)
        _ = e.perform(.selectNextTarget(forward: true))
        check(0)
        e.state.warpSystem = cur
        _ = e.perform(.selectNextTarget(forward: false))
        check(dest.count - 1)
        // The wormhole destination is reached through selectWormhole(cur).
        let w = try #require(dest.firstIndex(of: e.state.galaxy.wormholes[1]))
        e.state.warpSystem = dest[(w + dest.count - 1) % dest.count]
        _ = e.perform(.selectNextTarget(forward: true))
        #expect(e.state.warpSystem == e.state.galaxy.wormholes[1] && e.state.targetWormhole)
    }

    @Test("TRV-009 track sets or clears the tracked system without affecting travel")
    func track() throws {
        var e = makeEngine()
        let far = try #require(unreachableTarget(e.state))
        let dest = e.state.destinations
        let warp = e.state.warpSystem
        #expect(e.perform(.track(far)).rejection == nil)
        #expect(e.state.trackedSystem == far)
        #expect(e.state.destinations == dest && e.state.warpSystem == warp)
        #expect(e.perform(.track(nil)).rejection == nil)
        #expect(e.state.trackedSystem == nil)
        #expect(e.perform(.track(e.state.galaxy.systems.count)).rejection == .invalidArgument)
    }

    @Test("TRV-010 after an arrival the target is the arrival system and is not a valid destination")
    func targetAfterArrival() throws {
        var e = makeEngine()
        let t = try #require(plainTarget(e.state))
        _ = e.perform(.selectTarget(t))
        _ = completeTrip(&e)
        #expect(e.state.commander.currentSystem == t)
        #expect(e.state.warpSystem == t)
        #expect(!e.state.destinationOK(e.state.warpSystem))
        #expect(e.perform(.warp).rejection == .destinationOutOfRange)
    }
}

// MARK: §2 Warp command and preconditions

@Suite("Travel spec: warp preconditions (TRV §2)")
struct TravelWarpCheckSpecTests {
    @Test("TRV-011 warp needs the docked phase and an in-range target; a rejection changes nothing")
    func warpPhaseAndRange() throws {
        var e = makeEngine()
        let opp = freshShip(.gnat, e.state)
        var enc = e
        enc.state.phase = .encounter(EncounterState(type: .policeIgnore, opponent: opp))
        #expect(enc.perform(.warp).rejection == .notAllowedInPhase)
        // The target is the current system after a new game.
        let before = e.state
        #expect(e.state.warpSystem == e.state.commander.currentSystem)
        #expect(e.perform(.warp).rejection == .destinationOutOfRange)
        let far = try #require(unreachableTarget(e.state))
        e.state.warpSystem = far
        let withFar = e.state
        #expect(e.perform(.warp).rejection == .destinationOutOfRange)
        #expect(e.state == withFar)
        #expect(before.commander == withFar.commander)
    }

    @Test("TRV-012 departure checks: debt, mercenaries, insurance, wormhole tax, then the Wild consent; no interest check")
    func checkOrder() throws {
        func engine(_ adjust: (inout GameState) -> Void) -> GameEngine {
            makeEngine { s in
                s.commander.ship = freshShip(.beetle, s)
                s.commander.ship.crew[1] = 1
                s.commander.insurance = true
                s.commander.currentSystem = s.galaxy.wormholes[0]
                s.warpSystem = s.galaxy.wormholes[1]
                adjust(&s)
            }
        }
        let base = engine { _ in }.state
        let merc = base.mercenaryCosts, ins = base.insuranceCosts, tax = base.wormholeCosts
        try #require(merc > 0 && ins > 0 && tax > 0)
        var e = engine { s in s.commander.debt = 100_001; s.commander.cash = 0; s.commander.ship.crew[2] = CrewID.wild }
        #expect(e.perform(.warp).rejection == .debtTooLargeToTravel)
        e = engine { s in s.commander.cash = merc - 1; s.commander.ship.crew[2] = CrewID.wild }
        #expect(e.perform(.warp).rejection == .cannotPayMercenaries)
        e = engine { s in s.commander.cash = merc + ins - 1; s.commander.ship.crew[2] = CrewID.wild }
        #expect(e.perform(.warp).rejection == .cannotPayInsurance)
        e = engine { s in s.commander.cash = merc + ins + tax - 1; s.commander.ship.crew[2] = CrewID.wild }
        #expect(e.perform(.warp).rejection == .cannotPayWormholeTax)
        // All paid: the Wild consent is last.
        e = engine { s in s.commander.cash = merc + ins + tax; s.commander.ship.crew[2] = CrewID.wild }
        #expect(e.perform(.warp).decision == .confirm(Confirmation(.wildLeavesWithoutLaser)))
        // Debt of exactly 100 000 passes and interest is never checked: the warp proceeds with no cash for interest.
        e = engine { s in s.commander.debt = 100_000; s.commander.cash = merc + ins + tax }
        let r = e.perform(.warp)
        #expect(r.rejection == nil)
        #expect(r.events.contains { if case .departed = $0 { true } else { false } })
    }

    @Test("TRV-014 Wild consent: without a beam laser or better the warp asks first; acknowledging lets Wild leave")
    func wildConsent() throws {
        var e = makeEngine { s in
            s.commander.ship = freshShip(.beetle, s)
            s.commander.ship.weapons = []
            s.commander.ship.crew[1] = CrewID.wild
            s.quests.wild = QuestStatus.Wild.started
        }
        let t = try #require(plainTarget(e.state))
        _ = e.perform(.selectTarget(t))
        let before = e.state
        let ask = e.perform(.warp)
        #expect(ask.decision == .confirm(Confirmation(.wildLeavesWithoutLaser)) && ask.events.isEmpty)
        #expect(e.state == before)
        let go = e.perform(.warp, acknowledging: [.wildLeavesWithoutLaser])
        #expect(go.rejection == nil)
        #expect(go.events.first == .wildLeftShip)
        #expect(go.events.contains(.departed(from: before.commander.currentSystem, to: t, viaWormhole: false)))
        // Status 0 is set before the departure; a jump (no IncDays impatience step) leaves it observable.
        var j = makeEngine { s in
            s.commander.ship = freshShip(.beetle, s)
            s.commander.ship.weapons = []
            s.commander.ship.crew[1] = CrewID.wild
            s.quests.wild = QuestStatus.Wild.started
            s.quests.canSuperWarp = true
            s.warpSystem = t
        }
        _ = j.perform(.jump, acknowledging: [.useSingularity, .wildLeavesWithoutLaser])
        #expect(j.state.quests.wild == QuestStatus.Wild.notStarted)
        // Windows `HasWeapon(BeamLaser, exact: false)`: a disruptor (a higher weapon type) satisfies Wild; a pulse laser does not.
        var armed = makeEngine { s in
            s.commander.ship = freshShip(.beetle, s)
            s.commander.ship.crew[1] = CrewID.wild
            s.commander.ship.weapons = []
        }
        armed.state.warpSystem = t
        armed.state.commander.ship.weapons = [.photonDisruptor]
        #expect(!armed.state.wildWillLeave)
        armed.state.commander.ship.weapons = [.beamLaser]
        #expect(!armed.state.wildWillLeave)
        armed.state.commander.ship.weapons = [.pulseLaser]
        #expect(armed.state.wildWillLeave)
    }

    @Test("TRV-016 wormhole tax is 25 times the ship's fuel cost per parsec, only through a wormhole")
    func wormholeTax() throws {
        var s = makeEngine().state
        s.commander.currentSystem = s.galaxy.wormholes[0]
        s.warpSystem = s.galaxy.wormholes[1]
        for type in [ShipType.gnat, .hornet, .grasshopper, .wasp] {
            s.commander.ship = freshShip(type, s)
            #expect(s.wormholeCosts == 25 * s.ruleset.tables.ship(type).fuelCost)
        }
        s.commander.ship = freshShip(.gnat, s)
        #expect(s.wormholeCosts == 25)
        s.commander.ship = freshShip(.wasp, s)
        #expect(s.wormholeCosts == 125)
        s.warpSystem = try #require(plainTarget(s))
        #expect(s.wormholeCosts == 0)
    }

    @Test("TRV-017 the warp preview reports the same error the warp returns, and the Wild consent separately")
    func previewMatchesWarp() throws {
        let cases: [(inout GameState) -> Void] = [
            { _ in },
            { s in s.commander.debt = 100_001 },
            { s in s.commander.ship = freshShip(.beetle, s); s.commander.ship.crew[1] = 1; s.commander.cash = 0 },
            { s in s.commander.insurance = true; s.commander.cash = 0 },
            { s in s.commander.currentSystem = s.galaxy.wormholes[0]; s.commander.cash = 10 },
            { s in s.commander.ship.fuel = 0; s.galaxy.wormholes = [] },
            { s in s.commander.ship.crew.append(CrewID.wild); s.commander.ship.weapons = [] },
        ]
        for adjust in cases {
            var e = makeEngine(.windows201, adjust)
            let target = e.state.galaxy.wormholeExists(from: e.state.commander.currentSystem, to: nil)
                ? e.state.galaxy.wormholes[1] : (plainTarget(e.state) ?? unreachableTarget(e.state) ?? 0)
            _ = e.perform(.selectTarget(target))
            let before = e.state
            let p = e.state.warpTargetPreview(target)
            #expect(e.state == before)
            let r = e.perform(.warp)
            #expect(r.rejection == p.blocking)
            if p.blocking == nil {
                #expect(p.wildWillLeave == (r.decision == .confirm(Confirmation(.wildLeavesWithoutLaser))))
            }
        }
    }
}

// MARK: §3 Singularity jump

@Suite("Travel spec: singularity jump (TRV §3)")
struct TravelJumpSpecTests {
    @Test("TRV-018 jump needs the singularity and the docked phase but no range or fuel")
    func jumpRequirements() throws {
        var e = makeEngine { s in s.commander.ship.fuel = 0 }
        let far = try #require(unreachableTarget(e.state))
        _ = e.perform(.selectTarget(far))
        #expect(e.perform(.jump, acknowledging: [.useSingularity]).rejection == .noSingularity)
        e.state.quests.canSuperWarp = true
        var enc = e
        enc.state.phase = .encounter(EncounterState(type: .policeIgnore, opponent: freshShip(.gnat, e.state)))
        #expect(enc.perform(.jump, acknowledging: [.useSingularity]).rejection == .notAllowedInPhase)
        let trip = completeTrip(&e, .jump, ack: [.useSingularity])
        #expect(trip.result.rejection == nil)
        #expect(trip.events.contains { if case .departed(_, far, _) = $0 { true } else { false } })
        #expect(e.state.commander.ship.fuel == 0)
        #expect(!e.state.quests.canSuperWarp)
    }

    @Test("TRV-019 a jump to the current system is rejected with singularityTargetIsCurrentSystem")
    func jumpToCurrent() {
        var e = makeEngine { $0.quests.canSuperWarp = true }
        #expect(e.state.warpSystem == e.state.commander.currentSystem)
        let before = e.state
        #expect(e.perform(.jump, acknowledging: [.useSingularity]).rejection == .singularityTargetIsCurrentSystem)
        #expect(e.state == before)
    }

    @Test("TRV-021 jump consent; the singularity is consumed before the departure checks")
    func jumpConsent() throws {
        var e = makeEngine { s in s.quests.canSuperWarp = true; s.commander.debt = 100_001 }
        let t = try #require(plainTarget(e.state))
        _ = e.perform(.selectTarget(t))
        let before = e.state
        let ask = e.perform(.jump)
        #expect(ask.decision == .confirm(Confirmation(.useSingularity, amounts: [t])) && ask.events.isEmpty)
        #expect(e.state == before)
        let lost = e.perform(.jump, acknowledging: [.useSingularity])
        #expect(lost.rejection == nil)
        #expect(lost.events == [.singularityLost, .departureBlocked(.debtTooLargeToTravel)])
        #expect(!e.state.quests.canSuperWarp)
        #expect(e.state.phase == .docked && e.state.commander.currentSystem == before.commander.currentSystem)
        // The preview warns before consent.
        #expect(before.jumpPreview.blocking == .debtTooLargeToTravel && before.jumpPreview.available)
    }

    @Test("TRV-022 declining the Wild consent during a jump keeps the singularity")
    func jumpWildDecline() throws {
        var e = makeEngine { s in
            s.quests.canSuperWarp = true
            s.commander.ship.crew.append(CrewID.wild)
            s.commander.ship.weapons = []
        }
        let t = try #require(plainTarget(e.state))
        _ = e.perform(.selectTarget(t))
        let before = e.state
        let r = e.perform(.jump, acknowledging: [.useSingularity])
        #expect(r.decision == .confirm(Confirmation(.wildLeavesWithoutLaser)))
        #expect(e.state == before && e.state.quests.canSuperWarp)
        let go = e.perform(.jump, acknowledging: [.useSingularity, .wildLeavesWithoutLaser])
        #expect(go.events.first == .wildLeftShip && !e.state.quests.canSuperWarp)
    }

    @Test("TRV-023 a singularity departure charges nothing, uses no fuel or day, and its news is cleared")
    func singularityDeparture() throws {
        var e = makeEngine { s in
            armDepartureFreeze(&s)
            s.quests.canSuperWarp = true
            s.commander.ship = freshShip(.beetle, s)
            s.commander.ship.crew[1] = 1
            s.commander.insurance = true
            s.commander.debt = 5_000
            s.commander.ship.fuel = 3
        }
        let before = e.state
        let r = e.perform(.jump, acknowledging: [.useSingularity])
        #expect(r.rejection == nil)
        let s = e.state
        #expect(s.commander.cash == before.commander.cash && s.commander.debt == before.commander.debt)
        #expect(s.commander.ship.fuel == 3 && s.commander.days == before.commander.days)
        #expect(s.commander.noClaim == before.commander.noClaim)
        #expect(s.arrivedViaWormhole)
        #expect(s.newsEvents.isEmpty)
        #expect(s.galaxy.systems[before.commander.currentSystem].countDown == s.countDownStart)
        #expect(r.events.contains(.departed(from: before.commander.currentSystem, to: before.warpSystem, viaWormhole: true)))
        // The 20-click transit runs as for a normal warp (frozen here at click 20 by the Scarab).
        #expect(s.transitPreview?.clicksRemaining == 20)
    }
}

// MARK: §4 Departure

@Suite("Travel spec: departure (TRV §4)")
struct TravelDepartureSpecTests {
    @Test("TRV-026 TRV-027 departure: costs from the pre-departure state, fuel, interest, day, countdown, news, prices")
    func departureOrder() throws {
        var e = makeEngine { s in
            armDepartureFreeze(&s)
            s.commander.ship = freshShip(.beetle, s)
            s.commander.ship.crew[1] = 1
            s.commander.insurance = true
            s.commander.noClaim = 0
            s.commander.debt = 1_000
            s.commander.cash = 5_000
            s.newsEvents = [.gemulon]
        }
        let b = e.state
        let premium = b.insurancePremium(noClaim: 0)
        #expect(b.insuranceCosts == premium)
        let charges = b.mercenaryCosts + premium + b.wormholeCosts
        let interest = b.interestCosts
        let r = e.perform(.warp)
        let s = e.state
        #expect(s.commander.cash == b.commander.cash - charges - interest)
        #expect(s.commander.noClaim == 1)
        #expect(s.commander.days == b.commander.days + 1)
        #expect(s.commander.ship.fuel == b.commander.ship.fuel)
        #expect(s.galaxy.systems[b.commander.currentSystem].countDown == b.countDownStart)
        #expect(s.newsEvents.isEmpty)
        #expect(r.events.first == .departed(from: b.commander.currentSystem, to: b.warpSystem, viaWormhole: true))
        // Fuel: a normal warp deducts the distance.
        var f = makeEngine()
        let t = try #require(plainTarget(f.state))
        _ = f.perform(.selectTarget(t))
        let fuel = f.state.commander.ship.fuel
        let dist = f.state.warpTargetPreview(t).distance
        _ = completeTrip(&f)
        #expect(f.state.commander.ship.fuel == fuel - dist && f.state.commander.ship.fuel >= 0)
    }

    @Test("TRV-028 departed follows the day advance and precedes the rip; the charges equal dailyCosts")
    func departedEvent() throws {
        var e = makeEngine { s in
            armDepartureFreeze(&s)
            s.commander.debt = 2_000
            s.commander.cash = 5_000
            s.quests.experiment = QuestStatus.Experiment.date
        }
        let b = e.state
        let costs = b.dailyCosts(to: b.warpSystem)
        let r = e.perform(.warp)
        let dep = try #require(r.events.firstIndex { if case .departed = $0 { true } else { false } })
        let exp = try #require(r.events.firstIndex(of: .experimentPerformed))
        let rip = try #require(r.events.firstIndex { if case .fabricRip = $0 { true } else { false } })
        #expect(exp < dep && dep < rip)
        #expect(costs.interest == 200 && costs.wormholeTax == 25)
        #expect(e.state.commander.cash == b.commander.cash - costs.total)
    }

    @Test("TRV-029 the departure's own experimentPerformed news is cleared by the news reset")
    func experimentNewsCleared() throws {
        var e = makeEngine { $0.quests.experiment = QuestStatus.Experiment.date }
        let t = try #require(plainTarget(e.state))
        _ = e.perform(.selectTarget(t))
        let trip = completeTrip(&e)
        #expect(trip.events.contains(.experimentPerformed))
        #expect(!e.state.newsEvents.contains(.experimentPerformed))
        // During jail days (IncDays outside a departure) it survives.
        var s = makeEngine { $0.quests.experiment = QuestStatus.Experiment.date }.state
        _ = s.incDays(30)
        #expect(s.newsEvents == [.experimentPerformed])
    }

    @Test("TRV-030 departure prices for the target use the police record after the day advance")
    func departurePrices() throws {
        var e = makeEngine { s in armDepartureFreeze(&s); s.commander.policeRecordScore = -6 }
        var after = e.state
        _ = after.incDays(1)
        #expect(after.commander.policeRecordScore == -5)
        after.calculatePrices(for: after.warpSystem)
        var preDecay = e.state
        preDecay.calculatePrices(for: preDecay.warpSystem)
        try #require(after.buyPrices != preDecay.buyPrices || after.sellPrices != preDecay.sellPrices)
        _ = e.perform(.warp)
        guard case .encounter = e.state.phase else { Issue.record("trip not frozen at departure"); return }
        #expect(e.state.buyPrices == after.buyPrices && e.state.sellPrices == after.sellPrices)
    }
}

// MARK: §5 Fabric rip

@Suite("Travel spec: fabric rip (TRV §5)")
struct TravelRipSpecTests {
    @Test("TRV-036 rip test: probability 25 needs no draw; otherwise rand(100) < p; then destination = rand(N)")
    func ripTest() throws {
        func jumpEngine(seed: UInt64, p: Int, experiment: Int = QuestStatus.Experiment.performed) -> GameEngine {
            makeEngine(seed: seed) { s in
                s.quests.canSuperWarp = true
                s.quests.experiment = experiment
                s.quests.fabricRipProbability = p
                s.warpSystem = plainTarget(s) ?? 0
                s.targetWormhole = true
            }
        }
        var sawRip = false, sawNoRip = false
        for seed in UInt64(1)...60 {
            var e = jumpEngine(seed: seed, p: 10)
            #expect(e.state.galaxy.systems.count == 128)
            var ref = e.state
            ref.calculatePrices(for: ref.warpSystem)
            let rips = ref.rng.next(below: 100) < 10
            let dest = rips ? ref.rng.next(below: 128) : nil
            let r = e.perform(.jump, acknowledging: [.useSingularity])
            let event = r.events.first { if case .fabricRip = $0 { true } else { false } }
            #expect(event == dest.map { .fabricRip(newDestination: $0) })
            if rips { sawRip = true } else { sawNoRip = true }
        }
        #expect(sawRip && sawNoRip)
        // Probability exactly 25: no test draw.
        var e = jumpEngine(seed: 7, p: 25)
        var ref = e.state
        ref.calculatePrices(for: ref.warpSystem)
        let dest = ref.rng.next(below: 128)
        let r = e.perform(.jump, acknowledging: [.useSingularity])
        #expect(r.events.contains(.fabricRip(newDestination: dest)))
        // No rip without the performed experiment or with a non-positive probability.
        for (p, x) in [(25, QuestStatus.Experiment.date), (0, QuestStatus.Experiment.performed), (-3, QuestStatus.Experiment.performed)] {
            var n = jumpEngine(seed: 7, p: p, experiment: x)
            let events = n.perform(.jump, acknowledging: [.useSingularity]).events
            #expect(!events.contains { if case .fabricRip = $0 { true } else { false } })
        }
    }

    @Test("TRV-038 a rip changes only the destination: nothing refunded, departure prices and wormhole flag kept")
    func ripChangesOnlyDestination() throws {
        var e = makeEngine(seed: 11) { s in
            armDepartureFreeze(&s)
            s.quests.experiment = QuestStatus.Experiment.performed
            s.quests.fabricRipProbability = 26  // 25 after the departure's IncDays(1): always rips, no test draw
        }
        var ref = e.state
        ref.payInterest()
        _ = ref.incDays(1)
        ref.setDepartureCountdown()
        ref.calculatePrices(for: ref.warpSystem)
        let x = ref.rng.next(below: 128)
        // Trap the rip destination so the trip stops at click 20 with the transit observable.
        e.state.galaxy.systems[x].specialEvent = .scarabDestroyed
        let b = e.state
        let r = e.perform(.warp)
        #expect(r.events.contains(.fabricRip(newDestination: x)))
        let t = try #require(e.state.transitPreview)
        #expect(t.destination == x && e.state.warpSystem == x && !e.state.targetWormhole)
        #expect(t.viaWormhole && e.state.arrivedViaWormhole)
        #expect(e.state.commander.cash == b.commander.cash - b.wormholeCosts)
        #expect(e.state.commander.ship.fuel == b.commander.ship.fuel)
        #expect(e.state.buyPrices == ref.buyPrices && e.state.sellPrices == ref.sellPrices)
    }

    @Test("TRV-039 the trip whose departure completes the experiment always rips; later IncDays(n) lowers p by n")
    func ripAfterExperiment() throws {
        for seed in UInt64(1)...5 {
            var e = makeEngine(seed: seed) { $0.quests.experiment = QuestStatus.Experiment.date }
            let t = try #require(plainTarget(e.state))
            _ = e.perform(.selectTarget(t))
            let r = e.perform(.warp)
            #expect(r.events.contains { if case .fabricRip = $0 { true } else { false } })
        }
        var s = makeEngine().state
        s.quests.experiment = QuestStatus.Experiment.performed
        s.quests.fabricRipProbability = 25
        _ = s.incDays(3)
        #expect(s.quests.fabricRipProbability == 22)
        s.quests.fabricRipProbability = 1
        _ = s.incDays(3)
        #expect(s.quests.fabricRipProbability == -2)
        _ = s.incDays(3)
        #expect(s.quests.fabricRipProbability == -2)
    }
}

// MARK: §6 Transit state machine

@Suite("Travel spec: transit (TRV §6)")
struct TravelTransitSpecTests {
    @Test("TRV-040 a departure enters a 20-click transit within the same step")
    func transitStart() throws {
        var e = makeEngine { armDepartureFreeze(&$0) }
        let dest = e.state.warpSystem
        let r = e.perform(.warp)
        guard case let .encounter(enc) = e.state.phase else { Issue.record("expected the Scarab at click 20"); return }
        #expect(enc.clicks == 20)
        #expect(e.state.transitPreview == TransitState(destination: dest, clicksRemaining: 20, viaWormhole: true, hadEncounter: true))
        #expect(r.events.last == .encounterStarted(type: .scarabAttack, opponent: .scarab, clicks: 20, playerCloaked: false))
    }

    @Test("TRV-041 click loop: encounters stop the step at their click; the loop ends with an arrival in the same step")
    func clickLoop() throws {
        var found = false
        for seed in UInt64(1)...40 {
            var e = makeEngine(seed: seed)
            let t = try #require(plainTarget(e.state))
            _ = e.perform(.selectTarget(t))
            let first = e.perform(.warp)
            guard case let .encounter(enc) = e.state.phase else { continue }
            found = true
            #expect(first.events.last == .encounterStarted(type: enc.type, opponent: enc.opponent.type, clicks: enc.clicks,
                                                            playerCloaked: false))
            #expect(e.state.encounterTransit?.clicksRemaining == enc.clicks && e.state.encounterTransit?.hadEncounter == true)
            var clicks = [enc.clicks]
            var events: [GameEvent] = []
            while case .encounter = e.state.phase {
                events = e.finishEncounter(.normal)
                if case let .encounter(next) = e.state.phase { clicks.append(next.clicks) }
            }
            #expect(clicks == clicks.sorted(by: >) && Set(clicks).count == clicks.count)
            #expect(e.state.phase == .docked && events.last == .arrived(system: t))
            break
        }
        #expect(found)
    }

    @Test("TRV-042 ending an encounter resumes the transit; a saved encounter reloads to the same future")
    func resumable() throws {
        var e = makeEngine { armDepartureFreeze(&$0) }
        _ = e.perform(.warp)
        let data = try JSONEncoder().encode(e.state)
        var loaded = GameEngine(state: try JSONDecoder().decode(GameState.self, from: data))
        #expect(loaded.state == e.state)
        var a = e, b = loaded
        let ea = a.finishEncounter(.normal), eb = b.finishEncounter(.normal)
        #expect(ea == eb && a.state == b.state)
        // The next click is 19 (or later: an arrival or another encounter below 20).
        if case let .encounter(next) = a.state.phase { #expect(next.clicks < 20) } else { #expect(a.state.phase == .docked) }
        loaded = b
        #expect(loaded.state == a.state)
    }

    @Test("TRV-043 arrest and escape pod end the clicks and arrive at once; death ends the game with no arrival")
    func encounterEndings() throws {
        var frozen = makeEngine { armDepartureFreeze(&$0) }
        _ = frozen.perform(.warp)
        let dest = frozen.state.warpSystem
        // Arrest: exactly the arrival pipeline, no further click.
        var e = frozen
        var ref = frozen.state
        ref.phase = .docked
        ref.encounterTransit = nil
        let refEvents = ref.arrival()
        #expect(e.finishEncounter(.arrested) == refEvents)
        #expect(e.state == ref && e.state.commander.currentSystem == dest)
        // Escape pod: the pod sequence, then the arrival.
        e = frozen
        ref = frozen.state
        ref.phase = .docked
        ref.encounterTransit = nil
        var podEvents = ref.escapeWithPod()
        podEvents += ref.arrival()
        #expect(e.finishEncounter(.escapePod) == podEvents)
        #expect(e.state == ref && e.state.commander.ship.type == .flea)
        // Killed.
        e = frozen
        #expect(e.finishEncounter(.killed).isEmpty)
        #expect(e.state.phase == .gameOver(.killed))
        #expect(e.state.commander.currentSystem == frozen.state.commander.currentSystem)
    }

    @Test("TRV-045 uneventfulTrip is emitted only after a trip without encounters, before the arrival events")
    func uneventful() throws {
        var sawQuiet = false, sawEventful = false
        for seed in UInt64(1)...80 where !(sawQuiet && sawEventful) {
            var e = makeEngine(seed: seed)
            let t = try #require(plainTarget(e.state))
            _ = e.perform(.selectTarget(t))
            let trip = completeTrip(&e)
            #expect(trip.events.last == .arrived(system: t))
            if trip.encounters.isEmpty {
                sawQuiet = true
                let dep = try #require(trip.events.firstIndex { if case .departed = $0 { true } else { false } })
                #expect(trip.events[dep + 1] == .uneventfulTrip)
                #expect(trip.events.filter { $0 == .uneventfulTrip }.count == 1)
            } else {
                sawEventful = true
                #expect(!trip.events.contains(.uneventfulTrip))
            }
        }
        #expect(sawQuiet && sawEventful)
    }

    @Test("TRV-046 transit flags are reset at departure; docked commands are rejected in an encounter")
    func transitFlagsAndPhase() throws {
        var e = makeEngine { s in
            armDepartureFreeze(&s)
            s.raided = true
            s.inspected = true
            s.litterWarning = true
            setMarket(&s)
        }
        _ = e.perform(.warp)
        guard case .encounter = e.state.phase else { Issue.record("not frozen"); return }
        #expect(!e.state.raided && !e.state.inspected && !e.state.litterWarning)
        let before = e.state
        for c: Command in [.warp, .jump, .readNewspaper, .buyFuel(credits: 10), .repairHull(credits: 10), .buyCargo(.water, quantity: 1),
                           .selectTarget(0), .selectWormhole(e.state.galaxy.wormholes[0]), .selectNextTarget(forward: true)] {
            #expect(e.perform(c, acknowledging: [.useSingularity]).rejection == .notAllowedInPhase, "\(c)")
        }
        #expect(e.state == before)
    }
}

// MARK: §7 Per-click repairs

@Suite("Travel spec: per-click repairs (TRV §7)")
struct TravelClickRepairSpecTests {
    @Test("TRV-047 TRV-049 each click repairs rand(Engineer): hull first, the rest doubled into shields in slot order")
    func clickRepairs() throws {
        var s = makeEngine().state
        s.commander.ship = freshShip(.hornet, s)
        s.mercenaries[CrewID.commander].skills = [5, 5, 5, 6]
        let eng = s.shipSkills[3]
        try #require(eng >= 6)
        let power = s.ruleset.tables.shield(.energy).power
        let strength = s.commander.ship.hullStrength(s.ruleset)
        for trial in 0..<60 {
            var t = s
            t.commander.ship.hull = strength - trial % 4
            t.commander.ship.shields = [ShieldInstance(type: .energy, charge: power - trial % 7),
                                        ShieldInstance(type: .energy, charge: power - trial % 3)]
            var peek = t.rng
            var r = peek.next(below: eng)
            let used = min(r, strength - t.commander.ship.hull)
            var expected = t.commander.ship
            expected.hull += used
            r -= used
            if r > 0 {
                r *= 2
                for i in expected.shields.indices where r > 0 {
                    let add = min(r, power - expected.shields[i].charge)
                    expected.shields[i].charge += add
                    r -= add
                }
            }
            t.performClickRepairs()
            #expect(t.commander.ship == expected)
            #expect(t.rng == peek)  // a draw on every click, even at full hull and shields
            s.rng = t.rng
        }
        // The example: Engineer 6, draw 5, hull 2 below maximum, one shield 10 below power → hull +2, shield +6.
        s.mercenaries[CrewID.commander].skills = [5, 5, 5, 6]
        try #require(s.shipSkills[3] == 6)
        var guardCount = 0
        while true {
            var peek = s.rng
            if peek.next(below: 6) == 5 { break }
            _ = s.rng.next(below: 2)
            guardCount += 1
            try #require(guardCount < 10_000)
        }
        s.commander.ship.hull = strength - 2
        s.commander.ship.shields = [ShieldInstance(type: .energy, charge: power - 10)]
        s.performClickRepairs()
        #expect(s.commander.ship.hull == strength && s.commander.ship.shields[0].charge == power - 4)
    }
}

// MARK: §10 API and §11 previews

@Suite("Travel spec: API and previews (TRV §10, §11)")
struct TravelAPISpecTests {
    @Test("TRV-081 travel commands are Codable; the select commands are accepted only while docked")
    func commands() throws {
        let all: [Command] = [.warp, .jump, .selectTarget(3), .selectWormhole(4), .selectNextTarget(forward: false), .track(nil), .track(7)]
        for c in all {
            #expect(try JSONDecoder().decode(Command.self, from: JSONEncoder().encode(c)) == c)
        }
        var e = makeEngine()
        e.state.phase = .encounter(EncounterState(type: .policeIgnore, opponent: freshShip(.gnat, e.state)))
        for c: Command in [.selectTarget(3), .selectWormhole(e.state.galaxy.wormholes[0]), .selectNextTarget(forward: true)] {
            #expect(e.perform(c).rejection == .notAllowedInPhase)
        }
        // Tracking is a chart setting, accepted in any phase.
        #expect(e.perform(.track(5)).rejection == nil && e.state.trackedSystem == 5)
        var over = makeEngine()
        over.state.phase = .gameOver(.killed)
        #expect(over.perform(.selectTarget(1)).rejection == .gameOver)
    }

    @Test("TRV-082 travel events: departed, encounterStarted, arrival events, singularityLost and departureBlocked")
    func events() throws {
        var e = makeEngine { armDepartureFreeze(&$0) }
        let from = e.state.commander.currentSystem, to = e.state.warpSystem
        let r = e.perform(.warp)
        #expect(r.events == [.departed(from: from, to: to, viaWormhole: true),
                             .encounterStarted(type: .scarabAttack, opponent: .scarab, clicks: 20, playerCloaked: false)])
        var rest: [GameEvent] = []
        while case .encounter = e.state.phase { rest = e.finishEncounter(.normal) }
        #expect(rest.last == .arrived(system: to))
        var j = makeEngine { s in s.quests.canSuperWarp = true; s.commander.debt = 200_000; s.warpSystem = plainTarget(s) ?? 1 }
        #expect(j.perform(.jump, acknowledging: [.useSingularity]).events == [.singularityLost, .departureBlocked(.debtTooLargeToTravel)])
        // Events round-trip through Codable for the replay log.
        for ev: GameEvent in [.singularityLost, .departureBlocked(.cannotPayInsurance), .fabricRip(newDestination: 3), .uneventfulTrip] {
            #expect(try JSONDecoder().decode(GameEvent.self, from: JSONEncoder().encode(ev)) == ev)
        }
    }

    @Test("TRV-083 travel errors and warnings are reachable through perform")
    func errors() throws {
        var e = makeEngine()
        #expect(e.perform(.warp).rejection == .destinationOutOfRange)
        #expect(e.perform(.jump).rejection == .noSingularity)
        e.state.quests.canSuperWarp = true
        #expect(e.perform(.jump).rejection == .singularityTargetIsCurrentSystem)
        let t = try #require(plainTarget(e.state))
        _ = e.perform(.selectTarget(t))
        #expect(e.perform(.jump).decision == .confirm(Confirmation(.useSingularity, amounts: [t])))
        var d = e
        d.state.commander.debt = 100_001
        #expect(d.perform(.warp).rejection == .debtTooLargeToTravel)
        var w = e
        w.state.commander.ship.crew.append(CrewID.wild)
        w.state.commander.ship.weapons = []
        #expect(w.perform(.warp).decision == .confirm(Confirmation(.wildLeavesWithoutLaser)))
    }

    @Test("TRV-084 NEWS-028 whole Windows trips match the C# harness draw for draw, including the newspaper")
    func harnessTrips() throws {
        let runs = TravelHarnessTests.runs
        try #require(!runs.isEmpty)
        let strings = try #require(TravelHarnessTests.strings)
        for run in runs {
            var e = GameEngine(config: NewGameConfig(commanderName: "Harness", difficulty: Difficulty(rawValue: run.difficulty) ?? .normal,
                                                     ruleset: .windows201, seed: UInt64(UInt32(bitPattern: run.seed))))
            e.state.options.alwaysIgnoreTraders = false
            for (w, expected) in run.warps.prefix(4).enumerated() {
                e.state.commander.ship.fuel = e.state.commander.ship.fuelTanks(e.ruleset)
                e.state.commander.cash = max(e.state.commander.cash, 20_000)
                if w % 5 == 4 { e.state.commander.policeRecordScore = -12 }
                e.state.commander.ship.hull = max(1, e.state.commander.ship.hull - (w % 3) * 7)
                let dest = e.state.destinations
                _ = e.perform(.selectTarget(dest[(w * 7) % dest.count]))
                _ = completeTrip(&e)
                let s = e.state
                #expect(s.buyPrices == expected.buy && s.sellPrices == expected.sell)
                #expect(s.currentSystem.tradeItems == expected.stock && s.commander.ship.hull == expected.hull)
                let (head, text) = strings.render(s.newspaper, commander: "Harness", shipType: s.commander.ship.type)
                #expect(head == expected.paperHead && text == expected.paperText)
            }
        }
    }

    @Test("TRV-086 the warp-target preview: distance, wormhole, range, fuel after, costs, blocking error, Wild")
    func warpPreview() throws {
        var s = makeEngine { s in s.commander.currentSystem = s.galaxy.wormholes[0] }.state
        let cur = s.commander.currentSystem
        let t = try #require(plainTarget(s))
        let p = s.warpTargetPreview(t)
        let dist = GalaxyGenerator.distance(s.galaxy.systems[cur], s.galaxy.systems[t], rule: s.ruleset.flags.distance)
        #expect(p.target == t && p.distance == dist && !p.viaWormhole && p.inRange)
        #expect(p.fuelAfter == s.commander.ship.fuel - dist && p.costs == s.dailyCosts(to: t) && p.blocking == nil && !p.wildWillLeave)
        let w = s.warpTargetPreview(s.galaxy.wormholes[1])
        #expect(w.viaWormhole && w.inRange && w.fuelAfter == s.commander.ship.fuel && w.costs.wormholeTax == 25)
        let far = try #require(unreachableTarget(s))
        #expect(s.warpTargetPreview(far).blocking == .destinationOutOfRange && !s.warpTargetPreview(far).inRange)
        s.commander.cash = 10
        #expect(s.warpTargetPreview(s.galaxy.wormholes[1]).blocking == .cannotPayWormholeTax)
        #expect(s.warpTargetPreview(t).blocking == nil)
        s.commander.ship.crew.append(CrewID.wild)
        s.commander.ship.weapons = []
        #expect(s.warpTargetPreview(t).wildWillLeave)
    }

    @Test("TRV-087 the jump preview: availability, destination and the check the jump would fail after consent")
    func jumpPreview() throws {
        var s = makeEngine().state
        #expect(s.jumpPreview.rejection == .noSingularity && !s.jumpPreview.available)
        s.quests.canSuperWarp = true
        #expect(s.jumpPreview.rejection == .singularityTargetIsCurrentSystem)
        s.warpSystem = try #require(unreachableTarget(s))
        #expect(s.jumpPreview == JumpPreview(destination: s.warpSystem, rejection: nil, blocking: nil, wildWillLeave: false))
        s.commander.insurance = true
        s.commander.cash = 0
        #expect(s.jumpPreview.blocking == .cannotPayInsurance && s.jumpPreview.available)
    }

    @Test("TRV-088 the transit preview shows the trip in progress and nil when docked; it draws nothing")
    func transitPreview() throws {
        var e = makeEngine { armDepartureFreeze(&$0) }
        #expect(e.state.transitPreview == nil)
        let dest = e.state.warpSystem
        _ = e.perform(.warp)
        let rng = e.state.rng
        #expect(e.state.transitPreview == TransitState(destination: dest, clicksRemaining: 20, viaWormhole: true, hadEncounter: true))
        #expect(e.state.rng == rng)
        var s = e.state
        let t = TransitState(destination: 4, clicksRemaining: 7, viaWormhole: false)
        s.phase = .inTransit(t)
        #expect(s.transitPreview == t)
    }
}
