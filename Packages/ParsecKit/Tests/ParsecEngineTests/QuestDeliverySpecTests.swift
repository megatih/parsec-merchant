// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecEngine

private let gemulon = SystemID.gemulon
private let daled = SystemID.daled

/// Escape-pod ending of an encounter (the C# destroyed-with-pod path).
private func podOut(_ e: inout GameEngine) -> [GameEvent] {
    QSTKit.encounter(&e, .pirateAttack, opponent: .gnat)
    return e.finishEncounter(.escapePod)
}

/// Buys a Beetle at a Hi-Tech shipyard (a ship trade with no day advance).
private func tradeShip(_ e: inout GameEngine) {
    e.state.galaxy.systems[e.state.commander.currentSystem].techLevel = .hiTech
    e.state.commander.cash += 100_000
    let r = e.perform(.buyShip(.beetle, transfers: []), acknowledging: Set(WarningID.allCases))
    #expect(r.rejection == nil && e.state.commander.ship.type == .beetle)
}

// MARK: - Gemulon

@Suite("Quest: Gemulon invasion (QST-GEMULON {M4})")
struct QuestGemulonSpecTests {
    @Test("QST-GEMULON-001 Gemulon is always shown, message-only, free; handling sets status 1 and removes it")
    func start() {
        var e = QSTKit.engine(.gemulon) { s in s.commander.policeRecordScore = -100; s.commander.reputationScore = 0 }
        #expect(e.state.specialEventAvailable == .gemulon && e.state.specialEventSpec(.gemulon)?.price == 0)
        #expect(e.perform(.specialEvent).events == [.specialEventCompleted(.gemulon)])
        #expect(e.state.quests.gemulon == 1 && e.state.currentSystem.specialEvent == nil && e.state.commander.cash == 10_000)
    }

    @Test("QST-GEMULON-002 arriving at the unaccepted start adds the gemulon headline; an unaccepted quest never invades")
    func unaccepted() throws {
        var e = QSTKit.engine(nil)
        let start = try #require(QSTKit.system(holding: .gemulon, in: e.state))
        _ = try #require(QSTKit.arrive(&e, at: start))
        #expect(e.state.commander.currentSystem == start && e.state.newsEvents.contains(.gemulon))
        let techBefore = e.state.galaxy.systems[gemulon].techLevel
        let events = e.state.incDays(30)
        #expect(e.state.quests.gemulon == 0 && !events.contains(.gemulonInvaded))
        #expect(e.state.galaxy.systems[gemulon].techLevel == techBefore && e.state.galaxy.systems[gemulon].specialEvent == .gemulonRescued)
    }

    @Test("QST-GEMULON-004 IncDays(n) counts 0 < status < 8 up to min(status + n, 8); 0, 9, 10 never count; pod days count")
    func countdown() {
        for (from, n, to) in [(1, 1, 2), (1, 3, 4), (5, 5, 8), (7, 1, 8), (0, 5, 0), (9, 5, 9), (10, 5, 10)] {
            var s = QSTKit.engine(nil) { $0.quests.gemulon = from }.state
            _ = s.incDays(n)
            #expect(s.quests.gemulon == to, "\(from) + \(n)")
        }
        var pod = QSTKit.engine(nil) { $0.quests.gemulon = 2 }
        _ = podOut(&pod)
        #expect(pod.state.quests.gemulon == 5)                                    // escape pod: IncDays(3)
    }

    @Test("QST-GEMULON-005 reaching 8 invades Gemulon in the same IncDays: event, Pre-Agricultural Anarchy, gemulonInvaded")
    func invasion() {
        var e = QSTKit.engine(nil) { $0.quests.gemulon = 6 }
        e.state.galaxy.systems[gemulon].techLevel = .hiTech
        let events = e.state.incDays(2)
        let g = e.state.galaxy.systems[gemulon]
        #expect(events == [.gemulonInvaded] && e.state.quests.gemulon == 8)
        #expect(g.specialEvent == .gemulonInvaded && g.techLevel == .preAgricultural && g.politics == .anarchy)
        QSTKit.dock(&e, at: gemulon)
        #expect(e.state.shipsForSale.isEmpty)                                     // rules read the new tech level
        #expect(e.state.currentSystem.politics == .anarchy)
    }

    @Test("QST-GEMULON-006 while status is 8, every click towards Gemulon makes one rand(10) > 4 Mantis draw")
    func mantisRule() {
        var base = QSTKit.engine(nil) { $0.quests.gemulon = 8 }
        base.state.warpSystem = gemulon
        var mantis = 0, quiet = 0
        for _ in 0..<60 {
            var s = base.state
            var peek = s.rng
            let draw = peek.next(below: 10)
            let enc = s.determineRandomEncounter(clicks: 10)
            if draw > 4 {
                #expect(enc?.opponent.type == .mantis && enc?.type == .pirateAttack)
                mantis += 1
            } else {
                #expect(enc == nil && s.rng == peek)                               // exactly the one draw
                quiet += 1
            }
            _ = base.state.rng.next(below: 1_000)
        }
        #expect(mantis > 0 && quiet > 0)
    }

    @Test("QST-GEMULON-008 GemulonRescued is shown iff 0 < status < 8; message-only, price 0")
    func rescuedShown() {
        for status in 0...10 {
            #expect(QSTKit.shown(.gemulonRescued) { $0.quests.gemulon = status } == (status > 0 && status < 8), "\(status)")
        }
        #expect(QSTKit.engine(nil).state.specialEventSpec(.gemulonRescued).map { $0.messageOnly && $0.price == 0 } == true)
    }

    @Test("QST-GEMULON-009 QST-GEMULON-010 QST-GEMULON-011 QST-GEMULON-017 success: rescue, fuel offer, compactor")
    func success() throws {
        var e = QSTKit.engine(nil)
        let start = try #require(QSTKit.system(holding: .gemulon, in: e.state))
        QSTKit.dock(&e, at: start)
        _ = e.perform(.specialEvent)
        #expect(e.state.quests.gemulon == 1)
        for _ in 0..<2 { _ = try #require(QSTKit.hop(&e, avoiding: [gemulon])) }
        let techBefore = e.state.galaxy.systems[gemulon].techLevel, govBefore = e.state.galaxy.systems[gemulon].politics
        _ = try #require(QSTKit.arrive(&e, at: gemulon))
        #expect(e.state.quests.gemulon == 4 && e.state.commander.currentSystem == gemulon)
        #expect(e.state.newsEvents.contains(.gemulonRescued))                    // QST-GEMULON-014: rescued headline
        #expect(e.state.specialEventAvailable == .gemulonRescued)
        #expect(e.perform(.specialEvent).events == [.specialEventCompleted(.gemulonRescued)])
        #expect(e.state.quests.gemulon == 9 && e.state.currentSystem.specialEvent == .gemulonFuel)
        #expect(e.state.currentSystem.techLevel == techBefore && e.state.currentSystem.politics == govBefore)
        _ = e.state.incDays(10)
        #expect(e.state.quests.gemulon == 9)                                      // countdown stopped
        #expect(e.perform(.specialEvent).decision == .confirm(Confirmation(.acceptSpecialEvent, amounts: [0])))
        let fuel = e.state.commander.ship.fuel
        let r = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(r.events == [.specialEventCompleted(.gemulonFuel)])
        #expect(e.state.commander.ship.gadgets.filter { $0 == .fuelCompactor }.count == 1)
        #expect(e.state.quests.gemulon == 10 && e.state.currentSystem.specialEvent == nil)
        #expect(e.state.commander.ship.fuel == fuel)                             // tank not refilled
    }

    @Test("QST-GEMULON-018 slot refusal: noFreeSlot with all gadget slots full, state unchanged; after selling one it works")
    func slotRefusal() {
        var e = QSTKit.engine(.gemulonFuel) { s in
            s.quests.gemulon = 9
            s.commander.ship = Ship(type: .beetle, spec: s.ruleset.tables.ship(.beetle))
            s.commander.ship.crew[0] = CrewID.commander
            s.commander.ship.gadgets = Array(repeating: .navigatingSystem, count: s.commander.ship.spec(s.ruleset).gadgetSlots)
        }
        let before = e.state
        #expect(e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).rejection == .noFreeSlot)
        #expect(e.state == before)
        #expect(e.perform(.sellGadget(index: 0), acknowledging: Set(WarningID.allCases)).rejection == nil)
        #expect(e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).events == [.specialEventCompleted(.gemulonFuel)])
        #expect(e.state.quests.gemulon == 10 && e.state.commander.ship.gadgets.contains(.fuelCompactor))
    }

    @Test("QST-GEMULON-013 QST-GEMULON-015 QST-GEMULON-019 too late by travel: invasion, Mantis rule, GemulonInvaded only removes")
    func tooLateByTravel() throws {
        var e = QSTKit.engine(nil)
        let start = try #require(QSTKit.system(holding: .gemulon, in: e.state))
        QSTKit.dock(&e, at: start)
        _ = e.perform(.specialEvent)
        for trip in 1...7 {
            let events = try #require(QSTKit.hop(&e, avoiding: [gemulon]))
            #expect(events.contains(.gemulonInvaded) == (trip == 7), "trip \(trip)")
        }
        let g = e.state.galaxy.systems[gemulon]
        #expect(e.state.quests.gemulon == 8 && g.specialEvent == .gemulonInvaded)
        #expect(g.techLevel == .preAgricultural && g.politics == .anarchy)
        // QST-GEMULON-015: neither the start nor the rescue exists any more, so nothing can set the status again.
        #expect(QSTKit.system(holding: .gemulon, in: e.state) == nil && QSTKit.system(holding: .gemulonRescued, in: e.state) == nil)
        // The next trip to Gemulon uses the Mantis rule: one rand(10) per click and no band roll.
        var probe = e.state
        probe.warpSystem = gemulon
        var peek = probe.rng
        let draw = peek.next(below: 10)
        let enc = probe.determineRandomEncounter(clicks: 20)
        #expect((enc?.opponent.type == .mantis) == (draw > 4))
        QSTKit.dock(&e, at: gemulon)
        #expect(e.state.specialEventAvailable == .gemulonInvaded)
        #expect(e.state.specialEventSpec(.gemulonInvaded).map { $0.messageOnly && $0.price == 0 } == true)
        var expected = e.state
        expected.galaxy.systems[gemulon].specialEvent = nil
        #expect(e.perform(.specialEvent).events == [.specialEventCompleted(.gemulonInvaded)])
        #expect(e.state == expected)                                              // QST-GEMULON-013: removal only
    }

    @Test("QST-GEMULON-014 the gemulonInvaded arrival headline is unreachable; gemulonRescued only while 0 < status < 8")
    func arrivalHeadlines() {
        for status in [1, 7] {
            var s = QSTKit.engine(nil) { $0.quests.gemulon = status }.state
            s.commander.currentSystem = gemulon
            s.addArrivalNews()
            #expect(s.newsEvents == [.gemulonRescued])
        }
        // Reaching 8 (or 9) replaces GemulonRescued in the same step, so the ≥ 8 branch never sees it.
        var invaded = QSTKit.engine(nil) { $0.quests.gemulon = 7 }.state
        _ = invaded.incDays(1)
        invaded.commander.currentSystem = gemulon
        invaded.addArrivalNews()
        #expect(invaded.galaxy.systems[gemulon].specialEvent == .gemulonInvaded && !invaded.newsEvents.contains(.gemulonInvaded))
        var rescued = QSTKit.engine(nil) { $0.quests.gemulon = 3 }
        QSTKit.dock(&rescued, at: gemulon)
        _ = rescued.perform(.specialEvent)
        rescued.state.newsEvents = []
        rescued.state.addArrivalNews()
        #expect(rescued.state.quests.gemulon == 9 && rescued.state.newsEvents.isEmpty)
    }

    @Test("QST-GEMULON-016 arrest, escape pod, ship trades and encounters change the status only through their days")
    func otherInteractions() {
        var arrest = QSTKit.engine(nil) { $0.quests.gemulon = 9 }
        _ = QSTKit.arrest(&arrest, destination: 3)
        #expect(arrest.state.quests.gemulon == 9)
        var unstarted = QSTKit.engine(nil)
        _ = podOut(&unstarted)
        #expect(unstarted.state.quests.gemulon == 0)
        var trade = QSTKit.engine(nil) { $0.quests.gemulon = 2 }
        tradeShip(&trade)
        #expect(trade.state.quests.gemulon == 2)
        var fight = QSTKit.engine(nil) { $0.quests.gemulon = 3 }
        QSTKit.encounter(&fight, .pirateAttack, opponent: .gnat)
        _ = fight.finishEncounter(.normal)
        #expect(fight.state.quests.gemulon == 3)
    }

    @Test("QST-GEMULON-020 too late by jail: a 30-day term at status 2 invades during the jail days, before the arrival")
    func tooLateByJail() {
        var e = QSTKit.engine(nil) { $0.quests.gemulon = 2 }
        let r = QSTKit.arrest(&e, destination: 5)
        #expect(e.state.quests.gemulon == 8)
        let invaded = r.events.firstIndex(of: .gemulonInvaded), arrived = r.events.firstIndex(of: .arrived(system: 5))
        let arrested = r.events.firstIndex { if case .arrested(term: 30, _, _) = $0 { true } else { false } }
        #expect(arrested != nil && invaded != nil && arrived != nil)
        if let a = arrested, let i = invaded, let d = arrived { #expect(a < i && i < d) }
    }
}

// MARK: - Experiment

@Suite("Quest: the dangerous experiment (QST-EXPERIMENT {M4})")
struct QuestExperimentSpecTests {
    @Test("QST-EXPERIMENT-001 Experiment is shown iff record ≥ −5; message-only, free; sets 1; no start-system headline")
    func start() {
        #expect(!QSTKit.shown(.experiment) { $0.commander.policeRecordScore = -6 })
        var e = QSTKit.engine(.experiment) { $0.commander.policeRecordScore = -5 }
        #expect(e.state.specialEventAvailable == .experiment)
        #expect(e.state.specialEventSpec(.experiment).map { $0.messageOnly && $0.price == 0 } == true)
        e.state.addArrivalNews()
        #expect(e.state.newsEvents.isEmpty)
        #expect(e.perform(.specialEvent).events == [.specialEventCompleted(.experiment)])
        #expect(e.state.quests.experiment == 1 && e.state.currentSystem.specialEvent == nil)
    }

    @Test("QST-EXPERIMENT-003 IncDays counts 0 < status < 12 up to min(status + n, 12); the 11th day performs it")
    func countdown() {
        for (from, n, to) in [(1, 5, 6), (1, 10, 11), (11, 1, 12), (5, 30, 12), (0, 5, 0), (13, 5, 13)] {
            var s = QSTKit.engine(nil) { $0.quests.experiment = from }.state
            let events = s.incDays(n)
            #expect(s.quests.experiment == to, "\(from) + \(n)")
            #expect(events.contains(.experimentPerformed) == (to == 12 && from != 12), "\(from) + \(n) performed")
        }
    }

    @Test("QST-EXPERIMENT-004 reaching 12: probability 25 (not lowered in that call), ExperimentFailed, event and headline")
    func performed() {
        var s = QSTKit.engine(nil) { $0.quests.experiment = 10 }.state
        let events = s.incDays(2)
        #expect(events == [.experimentPerformed])
        #expect(s.quests.fabricRipProbability == 25 && s.galaxy.systems[daled].specialEvent == .experimentFailed)
        #expect(s.newsEvents.contains(.experimentPerformed))
    }

    @Test("QST-EXPERIMENT-005 afterwards IncDays(n) lowers the probability by n (may go negative); 25 always rips")
    func probability() {
        var s = QSTKit.engine(nil) { $0.quests.experiment = 12; $0.quests.fabricRipProbability = 2 }.state
        _ = s.incDays(5)
        #expect(s.quests.fabricRipProbability == -3)
        _ = s.incDays(1)
        #expect(s.quests.fabricRipProbability == -3)                               // stops once ≤ 0
        // Exactly 25 at the rip test (a jump has no day advance) rips on every RNG state.
        for k in 0..<10 {
            var e = QSTKit.engine(nil) { $0.quests.experiment = 12; $0.quests.fabricRipProbability = 25; $0.quests.canSuperWarp = true }
            for _ in 0..<k { _ = e.state.rng.next(below: 1_000) }
            e.state.warpSystem = 100
            let r = e.perform(.jump, acknowledging: [.useSingularity])
            #expect(r.events.contains { if case .fabricRip = $0 { true } else { false } }, "offset \(k)")
        }
    }

    @Test("QST-EXPERIMENT-006 ExperimentFailed: always shown, message-only, only removes itself; arrival headline")
    func failedEvent() {
        var e = QSTKit.engine(.experimentFailed) { $0.quests.experiment = 12; $0.quests.fabricRipProbability = 20 }
        #expect(e.state.specialEventAvailable == .experimentFailed)
        e.state.addArrivalNews()
        #expect(e.state.newsEvents == [.experimentFailed])
        var expected = e.state
        expected.galaxy.systems[expected.commander.currentSystem].specialEvent = nil
        #expect(e.perform(.specialEvent).events == [.specialEventCompleted(.experimentFailed)])
        #expect(e.state == expected)
    }

    @Test("QST-EXPERIMENT-007 ExperimentStopped is shown iff 0 < status < 12, message-only and free; arrival headline")
    func stoppedShown() {
        for status in 0...13 {
            #expect(QSTKit.shown(.experimentStopped) { $0.quests.experiment = status } == (status > 0 && status < 12), "\(status)")
            var s = QSTKit.engine(.experimentStopped) { $0.quests.experiment = status }.state
            s.addArrivalNews()
            #expect(s.newsEvents.contains(.experimentStopped) == (status > 0 && status < 12))
        }
        #expect(QSTKit.engine(nil).state.specialEventSpec(.experimentStopped).map { $0.messageOnly && $0.price == 0 } == true)
    }

    @Test("QST-EXPERIMENT-008 stopping sets 13 and the singularity; IncDays then changes neither status nor probability")
    func stopped() {
        var e = QSTKit.engine(.experimentStopped) { $0.quests.experiment = 4 }
        _ = e.perform(.specialEvent)
        #expect(e.state.quests.experiment == 13 && e.state.quests.canSuperWarp && e.state.currentSystem.specialEvent == nil)
        let events = e.state.incDays(40)
        #expect(e.state.quests.experiment == 13 && e.state.quests.fabricRipProbability == 0 && events.isEmpty)
    }

    @Test("QST-EXPERIMENT-009 the singularity is consumed by a jump; arrest, escape pod and ship trades keep it")
    func singularity() {
        var arrest = QSTKit.engine(nil) { $0.quests.canSuperWarp = true }
        _ = QSTKit.arrest(&arrest, destination: 4)
        #expect(arrest.state.quests.canSuperWarp)
        var pod = QSTKit.engine(nil) { $0.quests.canSuperWarp = true }
        _ = podOut(&pod)
        #expect(pod.state.quests.canSuperWarp)
        var trade = QSTKit.engine(nil) { $0.quests.canSuperWarp = true }
        tradeShip(&trade)
        #expect(trade.state.quests.canSuperWarp)
        // Only ExperimentStopped sets it among the 46 events.
        for ev in SpecialEventType.allCases {
            var e = questScenario(seed: 1, ev: ev.rawValue, v: 1)
            _ = e.perform(.specialEvent, acknowledging: Set(WarningID.allCases))
            #expect(e.state.quests.canSuperWarp == (ev == .experimentStopped), "\(ev)")
        }
    }

    @Test("QST-EXPERIMENT-010 stopped in time: 5 warps to Daled, stop it, then a jump reaches any target and clears it")
    func stoppedInTime() throws {
        var e = QSTKit.engine(nil)
        let start = try #require(QSTKit.system(holding: .experiment, in: e.state))
        QSTKit.dock(&e, at: start)
        #expect(e.perform(.specialEvent).events == [.specialEventCompleted(.experiment)])
        for _ in 0..<4 { _ = try #require(QSTKit.hop(&e, avoiding: [daled])) }
        _ = try #require(QSTKit.arrive(&e, at: daled))
        #expect(e.state.quests.experiment == 6 && e.state.specialEventAvailable == .experimentStopped)
        #expect(e.perform(.specialEvent).events == [.specialEventCompleted(.experimentStopped)])
        #expect(e.state.quests.experiment == 13 && e.state.quests.canSuperWarp && e.state.currentSystem.specialEvent == nil)
        let far = try #require(e.state.galaxy.systems.indices.max { QSTKit.distance(e.state, daled, $0) < QSTKit.distance(e.state, daled, $1) })
        #expect(QSTKit.distance(e.state, daled, far) > e.state.commander.ship.fuelTanks(e.ruleset))
        e.state.warpSystem = far
        #expect(e.perform(.jump).decision == .confirm(Confirmation(.useSingularity, amounts: [far])))
        let r = e.perform(.jump, acknowledging: [.useSingularity])
        #expect(r.events.contains(.departed(from: daled, to: far, viaWormhole: false)) && !e.state.quests.canSuperWarp)
    }

    @Test("QST-EXPERIMENT-011 performed: the 11th warp performs it and rips; the next departure lowers to 24 first")
    func performedByTravel() throws {
        var e = QSTKit.engine(nil)
        let start = try #require(QSTKit.system(holding: .experiment, in: e.state))
        QSTKit.dock(&e, at: start)
        _ = e.perform(.specialEvent)
        for trip in 1...10 {
            let events = try #require(QSTKit.hop(&e, avoiding: [daled]))
            #expect(!events.contains(.experimentPerformed), "trip \(trip)")
        }
        let eleventh = try #require(QSTKit.hop(&e, avoiding: [daled]))
        #expect(eleventh.contains(.experimentPerformed))
        #expect(eleventh.contains { if case .fabricRip = $0 { true } else { false } })
        #expect(e.state.quests.fabricRipProbability == 25 && e.state.galaxy.systems[daled].specialEvent == .experimentFailed)
        #expect(!e.state.newsEvents.contains(.experimentPerformed))                // lost at the departure news reset
        _ = try #require(QSTKit.hop(&e, avoiding: [daled]))
        #expect(e.state.quests.fabricRipProbability == 24)
        QSTKit.dock(&e, at: daled)
        #expect(e.state.specialEventAvailable == .experimentFailed)
        let quests = e.state.quests
        #expect(e.perform(.specialEvent).events == [.specialEventCompleted(.experimentFailed)])
        #expect(e.state.quests == quests && e.state.currentSystem.specialEvent == nil)
    }

    @Test("QST-EXPERIMENT-012 performed in jail: 25 without lowering, headline in the arrival paper, then 24 per test")
    func performedInJail() {
        var e = QSTKit.engine(nil) { $0.quests.experiment = 2 }
        let r = QSTKit.arrest(&e, destination: 6)
        #expect(r.events.contains(.experimentPerformed))
        #expect(e.state.quests.experiment == 12 && e.state.quests.fabricRipProbability == 25)
        #expect(e.state.phase == .docked && e.state.newsEvents.contains(.experimentPerformed))
        let target = QSTKit.nearest(to: e.state.commander.currentSystem, in: e.state)
        e.state.commander.ship.fuel = e.state.commander.ship.fuelTanks(e.ruleset)
        e.state.warpSystem = target
        var rips = 0
        var start = e
        for _ in 0..<100 {
            var c = start
            let w = c.perform(.warp)
            #expect(c.state.quests.fabricRipProbability == 24)
            if w.events.contains(where: { if case .fabricRip = $0 { true } else { false } }) { rips += 1 }
            _ = start.state.rng.next(below: 1_000)
        }
        #expect(rips > 0 && rips < 100)                                           // 24 in 100, not certain
    }

    @Test("QST-EXPERIMENT-013 not accepted: with record < −5 the start is not offered and Daled's stop never shows")
    func notAccepted() {
        var e = QSTKit.engine(.experiment) { $0.commander.policeRecordScore = -6 }
        #expect(e.perform(.specialEvent).rejection == .noSpecialEvent)
        QSTKit.dock(&e, at: daled)
        e.state.galaxy.systems[daled].specialEvent = .experimentStopped
        #expect(e.state.specialEventAvailable == nil)
        _ = e.state.incDays(30)
        #expect(e.state.quests.experiment == 0 && e.state.quests.fabricRipProbability == 0)
    }
}

// MARK: - Artifact

@Suite("Quest: the alien artifact (QST-ARTIFACT {M4})")
struct QuestArtifactSpecTests {
    /// A state on its way to a system whose band roll will match nothing, with the next two draws peeked.
    private static func bandMiss(_ artifact: Int) -> [(GameState, Int)] {
        var base = QSTKit.engine(nil) { $0.quests.artifact = artifact }.state
        base.warpSystem = QSTKit.nearest(to: base.commander.currentSystem, in: base, avoiding: [SystemID.kravat, gemulon])
        let gov = base.ruleset.tables.politics(base.galaxy.systems[base.warpSystem].politics)
        let mod = max(1, 3 - base.policeRecord.rawValue)
        let bands = gov.activityPirates.rawValue + gov.activityPolice.rawValue * mod + gov.activityTraders.rawValue
        var out: [(GameState, Int)] = []
        for _ in 0..<4_000 {
            var peek = base.rng
            let roll = peek.next(below: 44 - 2 * base.difficulty.rawValue)
            if roll >= bands { out.append((base, peek.next(below: 20))) }
            _ = base.rng.next(below: 1_000)
        }
        return out
    }

    @Test("QST-ARTIFACT-001 Artifact: shown iff record ≥ −5, a question [0], sets 1; uses no bay, quarter or slot")
    func pickUp() {
        #expect(!QSTKit.shown(.artifact) { $0.commander.policeRecordScore = -6 })
        var e = QSTKit.engine(.artifact)
        let bays = e.state.freeCargoBays, crew = e.state.commander.ship.crew, gadgets = e.state.commander.ship.freeGadgetSlots(e.ruleset)
        #expect(e.perform(.specialEvent).decision == .confirm(Confirmation(.acceptSpecialEvent, amounts: [0])))
        #expect(e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).events == [.specialEventCompleted(.artifact)])
        #expect(e.state.quests.artifact == 1 && e.state.currentSystem.specialEvent == nil)
        #expect(e.state.freeCargoBays == bays && e.state.commander.ship.crew == crew)
        #expect(e.state.commander.ship.freeGadgetSlots(e.ruleset) == gadgets)
    }

    @Test("QST-ARTIFACT-003 QST-ARTIFACT-013 with the artifact aboard and no band match, rand(20) = 3 is a Mantis, 4 is not")
    func mantisDraw() throws {
        let cases = Self.bandMiss(1)
        let three = try #require(cases.first { $0.1 == 3 })
        let four = try #require(cases.first { $0.1 == 4 })
        var s3 = three.0, s4 = four.0
        #expect(s3.determineRandomEncounter(clicks: 7)?.opponent.type == .mantis)
        #expect(s4.determineRandomEncounter(clicks: 7) == nil)
        for (state, draw) in cases.prefix(200) {
            var s = state
            #expect((s.determineRandomEncounter(clicks: 7)?.opponent.type == .mantis) == (draw <= 3))
        }
        // Without the artifact the same click draws nothing more.
        var none = three.0
        none.quests.artifact = 0
        var peek = none.rng
        _ = peek.next(below: 44 - 2 * none.difficulty.rawValue)
        #expect(none.determineRandomEncounter(clicks: 7) == nil && none.rng == peek)
        // The Kravat/Wild branch takes precedence: no Mantis there.
        var kravat = three.0
        kravat.warpSystem = SystemID.kravat
        kravat.commander.ship = Ship(type: .beetle, spec: kravat.ruleset.tables.ship(.beetle))
        kravat.commander.ship.crew[0] = CrewID.commander
        kravat.hireCrew(CrewID.wild)
        for _ in 0..<50 {
            var k = kravat
            #expect(k.determineRandomEncounter(clicks: 7)?.opponent.type != .mantis)
            _ = kravat.rng.next(below: 1_000)
        }
    }

    @Test("QST-ARTIFACT-005 QST-ARTIFACT-011 QST-ARTIFACT-014 surrender to the Mantis: confirmation, status 0, transit resumes")
    func surrender() {
        var e = QSTKit.engine(nil) { $0.quests.artifact = 1 }
        QSTKit.encounter(&e, .pirateAttack, opponent: .mantis, destination: 8)
        #expect(e.perform(.encounter(.surrender)).decision == .confirm(Confirmation(.surrenderArtifact)))
        let r = e.perform(.encounter(.surrender), acknowledging: [.surrenderArtifact])
        #expect(r.events.first == .artifactRelinquished && e.state.quests.artifact == 0)
        #expect(e.state.phase == .docked && r.events.last == .arrived(system: 8))  // the one-click trip completes
        e.state.galaxy.systems[8].specialEvent = .artifactDelivery
        #expect(e.state.specialEventAvailable == nil)                             // never offered again
        var without = QSTKit.engine(nil)
        QSTKit.encounter(&without, .pirateAttack, opponent: .mantis)
        #expect(without.perform(.encounter(.surrender), acknowledging: [.surrenderArtifact]).rejection == .surrenderRefused)
    }

    @Test("QST-ARTIFACT-006 destroying a Mantis leaves the artifact aboard")
    func destroyMantis() throws {
        var base = QSTKit.engine(nil) { s in
            s.quests.artifact = 1
            s.commander.ship = Ship(type: .hornet, spec: s.ruleset.tables.ship(.hornet))
            s.commander.ship.crew[0] = CrewID.commander
            s.commander.ship.weapons = [.militaryLaser, .militaryLaser, .militaryLaser]
            s.mercenaries[CrewID.commander].skills = [10, 10, 10, 10]
        }
        QSTKit.encounter(&base, .pirateAttack, opponent: .mantis)
        if case var .encounter(enc) = base.state.phase {
            enc.opponent.hull = 1
            enc.opponent.shields = []
            base.state.phase = .encounter(enc)
        }
        var found = false
        for _ in 0..<500 where !found {
            var e = base
            let r = e.perform(.encounter(.attack))
            if r.events.contains(.opponentDestroyed(.mantis)) {
                found = true
                #expect(e.state.quests.artifact == 1 && e.state.artifactOnBoard)
            }
            _ = base.state.rng.next(below: 1_000)
        }
        #expect(found)
    }

    @Test("QST-ARTIFACT-007 arrest and ship trades keep the artifact aboard")
    func arrestAndTrade() {
        var arrest = QSTKit.engine(nil) { $0.quests.artifact = 1 }
        _ = QSTKit.arrest(&arrest, destination: 2)
        #expect(arrest.state.artifactOnBoard)
        var trade = QSTKit.engine(nil) { $0.quests.artifact = 1 }
        tradeShip(&trade)
        #expect(trade.state.artifactOnBoard)
    }

    @Test("QST-ARTIFACT-008 QST-ARTIFACT-015 the escape pod sets status 2 (no separate event); no reward is ever paid")
    func pod() {
        var e = QSTKit.engine(nil) { $0.quests.artifact = 1; $0.commander.ship.escapePod = true }
        let events = podOut(&e)
        #expect(e.state.quests.artifact == 2)
        #expect(events.contains(.escapePodUsed(insurancePayout: 0)))
        e.state.galaxy.systems[e.state.commander.currentSystem].specialEvent = .artifactDelivery
        #expect(e.state.specialEventAvailable == nil)
        #expect(e.perform(.specialEvent).rejection == .noSpecialEvent)
    }

    @Test("QST-ARTIFACT-010 ArtifactDelivery: shown iff aboard, message-only, −20000; status 2; arrival headline")
    func delivery() {
        #expect(!QSTKit.shown(.artifactDelivery))
        var e = QSTKit.engine(.artifactDelivery) { $0.quests.artifact = 1 }
        e.state.addArrivalNews()
        #expect(e.state.newsEvents == [.artifactDelivery])
        #expect(e.state.specialEventSpec(.artifactDelivery).map { $0.messageOnly && $0.price == -20_000 } == true)
        #expect(e.perform(.specialEvent).events == [.specialEventCompleted(.artifactDelivery)])
        #expect(e.state.quests.artifact == 2 && e.state.commander.cash == 30_000 && e.state.currentSystem.specialEvent == nil)
    }

    @Test("QST-ARTIFACT-012 success: pick up with consent, travel to the delivery system, collect 20000")
    func success() throws {
        var e = QSTKit.engine(nil)
        let pickUp = try #require(QSTKit.system(holding: .artifact, in: e.state))
        let deliver = try #require(QSTKit.system(holding: .artifactDelivery, in: e.state))
        QSTKit.dock(&e, at: pickUp)
        #expect(e.perform(.specialEvent).decision == .confirm(Confirmation(.acceptSpecialEvent, amounts: [0])))
        _ = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(e.state.quests.artifact == 1)
        _ = try #require(QSTKit.arrive(&e, at: deliver))
        #expect(e.state.specialEventAvailable == .artifactDelivery)
        let cash = e.state.commander.cash
        #expect(e.perform(.specialEvent).events == [.specialEventCompleted(.artifactDelivery)])
        #expect(e.state.commander.cash == cash + 20_000 && e.state.quests.artifact == 2 && e.state.currentSystem.specialEvent == nil)
    }

    @Test("QST-ARTIFACT-016 record gate: at −6 not offered (noSpecialEvent); at −5 offered")
    func recordGate() {
        var e = QSTKit.engine(.artifact) { $0.commander.policeRecordScore = -6 }
        #expect(e.state.specialEventAvailable == nil)
        #expect(e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).rejection == .noSpecialEvent)
        e.state.commander.policeRecordScore = -5
        #expect(e.state.specialEventAvailable == .artifact)
    }
}
