// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecEngine

/// Shared helpers for the QST spec tests (QST-INDEX and the delivery / one-off chains).
enum QSTKit {
    /// A docked Windows 2.01 game (Gnat, record 0, reputation 0, cash 10 000) with `event` at the current system.
    static func engine(_ event: SpecialEventType?, seed: UInt64 = 42, difficulty: Difficulty = .normal,
                       _ adjust: (inout GameState) -> Void = { _ in }) -> GameEngine {
        makeEngine(seed: seed, difficulty: difficulty) { s in
            s.commander.policeRecordScore = 0
            s.commander.reputationScore = 0
            s.commander.cash = 10_000
            s.galaxy.systems[s.commander.currentSystem].specialEvent = event
            adjust(&s)
        }
    }

    /// Whether `event` is offered at the current system after `adjust`.
    static func shown(_ event: SpecialEventType, _ adjust: (inout GameState) -> Void = { _ in }) -> Bool {
        engine(event, adjust).state.specialEventAvailable == event
    }

    /// Moves the commander to `system`, docked (scenario setup, not a trip).
    static func dock(_ e: inout GameEngine, at system: Int) {
        e.state.commander.currentSystem = system
        e.state.warpSystem = system
        e.state.phase = .docked
    }

    /// The generated system holding `event`.
    static func system(holding event: SpecialEventType, in s: GameState) -> Int? {
        s.galaxy.systems.firstIndex { $0.specialEvent == event }
    }

    static func distance(_ s: GameState, _ a: Int, _ b: Int) -> Int {
        GalaxyGenerator.distance(s.galaxy.systems[a], s.galaxy.systems[b], rule: s.ruleset.flags.distance)
    }

    /// The system closest to `target` other than `target` and `avoiding`.
    static func nearest(to target: Int, in s: GameState, avoiding: Set<Int> = []) -> Int {
        s.galaxy.systems.indices.filter { $0 != target && !avoiding.contains($0) }
            .min { distance(s, $0, target) < distance(s, $1, target) } ?? target
    }

    /// Warps (with a full tank) to `target` on the first RNG offset whose trip docks somewhere (a fabric rip may
    /// redirect it) with no encounter other than ones the player simply ignores. Returns the trip's events, or nil.
    static func quietWarp(_ e: inout GameEngine, to target: Int) -> [GameEvent]? {
        e.state.commander.ship.fuel = e.state.commander.ship.fuelTanks(e.ruleset)
        e.state.warpSystem = target
        var start = e
        for _ in 0..<3_000 {
            var c = start
            let r = c.perform(.warp)
            var events = r.events
            while case let .encounter(enc) = c.state.phase, enc.type.actions.contains(.ignore), events.count < 400 {
                events += c.perform(.encounter(.ignore)).events
            }
            if r.rejection == nil, c.state.phase == .docked {
                e = c
                return events
            }
            _ = start.state.rng.next(below: 1_000)
        }
        return nil
    }

    /// One quiet one-day warp from the current system to its nearest neighbour outside `avoiding`.
    static func hop(_ e: inout GameEngine, avoiding: Set<Int>) -> [GameEvent]? {
        let target = nearest(to: e.state.commander.currentSystem, in: e.state, avoiding: avoiding)
        return quietWarp(&e, to: target)
    }

    /// Docks next to `target` (outside `avoiding`) and makes one quiet warp to it.
    static func arrive(_ e: inout GameEngine, at target: Int, avoiding: Set<Int> = []) -> [GameEvent]? {
        dock(&e, at: nearest(to: target, in: e.state, avoiding: avoiding))
        return quietWarp(&e, to: target)
    }

    /// Puts the commander into an encounter of `type` with a fresh `opponent` on a one-click trip to `destination`.
    static func encounter(_ e: inout GameEngine, _ type: EncounterType, opponent: ShipType, destination: Int? = nil) {
        var opp = Ship(type: opponent, spec: e.ruleset.tables.ship(opponent))
        opp.crew[0] = CrewID.opponent
        let dest = destination ?? e.state.commander.currentSystem
        e.state.warpSystem = dest
        e.state.lastOpponent = opp
        e.state.encounterTransit = TransitState(destination: dest, clicksRemaining: 1, viaWormhole: false, hadEncounter: true)
        e.state.phase = .encounter(EncounterState(type: type, opponent: opp, clicks: 1))
    }

    /// Surrenders to a police ship on the way to `destination` (record −10 gives a 30-day term). Returns the step.
    static func arrest(_ e: inout GameEngine, destination: Int) -> StepResult {
        e.state.commander.policeRecordScore = -10
        encounter(&e, .policeAttack, opponent: .gnat, destination: destination)
        return e.perform(.encounter(.surrender), acknowledging: [.surrenderToPolice])
    }

    /// QST-018 invariants for one state.
    static func invariantViolations(_ s: GameState) -> [String] {
        let q = s.quests
        var v: [String] = []
        let ranges: [(String, Int, ClosedRange<Int>)] = [
            ("artifact", q.artifact, 0...2), ("dragonfly", q.dragonfly, 0...6), ("experiment", q.experiment, 0...13),
            ("gemulon", q.gemulon, 0...10), ("japori", q.japori, 0...2), ("jarek", q.jarek, 0...12), ("moon", q.moon, 0...2),
            ("princess", q.princess, 0...16), ("reactor", q.reactor, 0...22), ("scarab", q.scarab, 0...3),
            ("sculpture", q.sculpture, 0...3), ("spaceMonster", q.spaceMonster, 0...3), ("wild", q.wild, 0...12),
        ]
        for (name, value, range) in ranges where !range.contains(value) { v.append("\(name) = \(value)") }
        if (q.artifact == QuestStatus.Artifact.onBoard) != s.artifactOnBoard { v.append("artifact aboard") }
        let unique: [SpecialEventType] = [.gemulonRescued, .gemulonFuel, .experimentStopped, .princessReturned, .princessQuantum]
        for ev in unique where s.galaxy.systems.filter({ $0.specialEvent == ev }).count > 1 { v.append("two \(ev)") }
        return v
    }
}

/// QST-INDEX: shared special-event rules (availability, the `.specialEvent` flow, API, invariants).
@Suite("Quest index: shared special-event rules (QST {M4})")
struct QuestIndexSpecTests {
    static let allSetups: [(SpecialEventType, Int)] = SpecialEventType.allCases.flatMap { ev in (0..<4).map { (ev, $0) } }

    // MARK: Availability

    @Test("QST-001 specialEventAvailable: nil unless docked with an event whose condition holds; a pure query")
    func availabilityQuery() {
        let e = QSTKit.engine(.lottery)
        let before = e.state
        #expect(e.state.specialEventAvailable == .lottery)
        #expect(e.state == before)                                                  // no state change, no RNG
        #expect(QSTKit.engine(nil).state.specialEventAvailable == nil)              // no event
        #expect(QSTKit.engine(.artifactDelivery).state.specialEventAvailable == nil) // condition false
        var transit = QSTKit.engine(.lottery)
        transit.state.phase = .inTransit(TransitState(destination: 1, clicksRemaining: 5, viaWormhole: false))
        #expect(transit.state.specialEventAvailable == nil)                        // not docked
        var over = QSTKit.engine(.lottery)
        over.state.phase = .gameOver(.retired)
        #expect(over.state.specialEventAvailable == nil)
    }

    @Test("QST-002 Shown-when: Dubious −5, Lawful 5, Average 40; free bays count antidote and reactor; aboard from status/crew")
    func shownWhenConstants() {
        #expect(QSTKit.shown(.artifact) { $0.commander.policeRecordScore = -5 })
        #expect(!QSTKit.shown(.artifact) { $0.commander.policeRecordScore = -6 })
        #expect(QSTKit.shown(.eraseRecord) { $0.commander.policeRecordScore = -6 })
        #expect(!QSTKit.shown(.eraseRecord) { $0.commander.policeRecordScore = -5 })
        #expect(QSTKit.shown(.princess) { $0.commander.policeRecordScore = 5; $0.commander.reputationScore = 40 })
        #expect(!QSTKit.shown(.princess) { $0.commander.policeRecordScore = 4; $0.commander.reputationScore = 40 })
        #expect(!QSTKit.shown(.princess) { $0.commander.policeRecordScore = 5; $0.commander.reputationScore = 39 })
        #expect(QSTKit.shown(.scarab) { $0.commander.reputationScore = 40 })
        #expect(!QSTKit.shown(.scarab) { $0.commander.reputationScore = 39 })
        // Gnat: 15 bays. The antidote takes 10, the reactor 5 + 10 − (status − 1) / 2.
        #expect(!QSTKit.shown(.cargoForSale) { $0.quests.japori = 1; $0.commander.ship.cargo[0] = 3 })
        #expect(QSTKit.shown(.cargoForSale) { $0.quests.japori = 1; $0.commander.ship.cargo[0] = 2 })
        #expect(!QSTKit.shown(.cargoForSale) { $0.quests.reactor = 1 })
        #expect(QSTKit.shown(.artifactDelivery) { $0.quests.artifact = 1 })
        #expect(!QSTKit.shown(.artifactDelivery) { $0.quests.artifact = 2 })
        #expect(QSTKit.shown(.reactorDelivered) { $0.quests.reactor = 20 })
        #expect(!QSTKit.shown(.reactorDelivered) { $0.quests.reactor = 21 })
        #expect(QSTKit.shown(.sculptureDelivered) { $0.quests.sculpture = 1 })
        #expect(!QSTKit.shown(.jarekGetsOut) { $0.quests.jarek = 1 })              // status alone is not "aboard"
        let beetle: (inout GameState) -> Void = { s in
            s.commander.ship = Ship(type: .beetle, spec: s.ruleset.tables.ship(.beetle))
            s.commander.ship.crew[0] = CrewID.commander
        }
        #expect(QSTKit.shown(.jarekGetsOut) { beetle(&$0); $0.hireCrew(CrewID.jarek) })   // crew slot, any status
        #expect(QSTKit.shown(.wildGetsOut) { beetle(&$0); $0.hireCrew(CrewID.wild) })
        #expect(QSTKit.shown(.princessReturned) { beetle(&$0); $0.hireCrew(CrewID.princess) })
    }

    @Test("QST-003 Moon threshold: Worth > MoonCost × .8 in double equals the integer test worth > 500000 × 4 / 5")
    func moonThreshold() {
        #expect(QuestStatus.moonCost * 4 / 5 == 400_000)
        for delta in -2...2 {
            let target = 400_000 + delta
            let e = QSTKit.engine(.moon) { s in s.commander.cash = target - s.commander.ship.spec(s.ruleset).price }
            #expect(e.state.worth == target)
            #expect((e.state.specialEventAvailable == .moon) == (Double(target) > Double(QuestStatus.moonCost) * 0.8))
        }
    }

    // MARK: The specialEvent flow

    @Test("QST-005 specialEvent with nothing available is noSpecialEvent and changes nothing")
    func noSpecialEvent() {
        let cases: [GameEngine] = [
            QSTKit.engine(nil),
            QSTKit.engine(.eraseRecord),                                          // record 0: condition false
            { var e = QSTKit.engine(.lottery)
              e.state.phase = .inTransit(TransitState(destination: 3, clicksRemaining: 4, viaWormhole: false))
              return e }(),
        ]
        for var e in cases {
            let before = e.state
            #expect(e.perform(.specialEvent, acknowledging: Set(WarningID.allCases)).rejection == .noSpecialEvent)
            #expect(e.state == before)
        }
    }

    @Test("QST-006 question events need acceptSpecialEvent (amounts [price]); message-only events are handled at once")
    func consent() {
        var q = QSTKit.engine(.skill)
        let before = q.state
        #expect(q.perform(.specialEvent).decision == .confirm(Confirmation(.acceptSpecialEvent, amounts: [3_000])))
        #expect(q.state == before)                                                // declining = not resending
        #expect(q.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).events.last == .specialEventCompleted(.skill))
        var m = QSTKit.engine(.lottery)
        let r = m.perform(.specialEvent)
        #expect(r.decision == nil && r.events == [.specialEventCompleted(.lottery)])
    }

    @Test("QST-007 price check after consent: cashToSpend < price is insufficientFunds, also for negative prices")
    func priceCheck() {
        var e = QSTKit.engine(.eraseRecord) { s in s.commander.policeRecordScore = -10; s.commander.cash = 4_999 }
        let before = e.state
        #expect(e.perform(.specialEvent).decision != nil)                          // consent first
        #expect(e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).rejection == .insufficientFunds)
        #expect(e.state == before)
        // Reserve money: interest 30 000 on a 300 000 debt puts cashToSpend at −30 000 < −20 000.
        var art = QSTKit.engine(.artifactDelivery) { s in
            s.quests.artifact = 1
            s.commander.cash = 0
            s.commander.debt = 300_000
            s.options.reserveMoney = true
        }
        #expect(art.state.cashToSpend == -30_000)
        #expect(art.perform(.specialEvent).rejection == .insufficientFunds)
        art.state.commander.debt = 200_000                                         // cashToSpend −20 000: not below
        #expect(art.perform(.specialEvent).events == [.specialEventCompleted(.artifactDelivery)])
        #expect(art.state.commander.cash == 20_000)
    }

    @Test("QST-008 order: effect, then cash −= price, then removal; chain events precede specialEventCompleted")
    func handlingOrder() throws {
        var art = QSTKit.engine(.artifactDelivery) { $0.quests.artifact = 1 }
        _ = art.perform(.specialEvent)
        #expect(art.state.commander.cash == 30_000 && art.state.currentSystem.specialEvent == nil)
        var cargo = QSTKit.engine(.cargoForSale)
        let r = cargo.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(r.events.count == 2 && r.events.last == .specialEventCompleted(.cargoForSale))
        if case .sealedCanisters = r.events.first {} else { Issue.record("canisters event first") }
        // Reactor with Wild aboard: the effect's own event comes first.
        var reactor = questScenario(seed: 1, ev: SpecialEventType.reactor.rawValue, v: 3)
        let rr = reactor.perform(.specialEvent, acknowledging: [.acceptSpecialEvent, .wildLeavesForReactor])
        #expect(rr.events == [.wildLeftShip, .specialEventCompleted(.reactor)])
        // Moon: the status is set before the price is charged, so worth does not move.
        var moon = QSTKit.engine(.moon) { $0.commander.cash = 600_000 }
        let worth = moon.state.worth
        _ = moon.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(moon.state.worth == worth && moon.state.commander.cash == 100_000)
    }

    @Test("QST-009 every replacement pair costs 0 on both sides, so charging the handled event's price is identical")
    func replacementPrices() {
        let pairs: [(SpecialEventType, SpecialEventType, (inout GameState) -> Void)] = [
            (.dragonflyDestroyed, .dragonflyShield, { $0.quests.dragonfly = 5 }),
            (.gemulonRescued, .gemulonFuel, { $0.quests.gemulon = 3 }),
            (.princess, .princessReturned, { $0.commander.policeRecordScore = 5; $0.commander.reputationScore = 40 }),
            (.reactorDelivered, .reactorLaser, { $0.quests.reactor = 5 }),
            (.scarabDestroyed, .scarabUpgradeHull, { $0.quests.scarab = 2 }),
            (.sculptureDelivered, .sculptureHiddenBays, { $0.quests.sculpture = 1 }),
        ]
        for (first, second, adjust) in pairs {
            var e = QSTKit.engine(first, adjust)
            #expect(e.state.specialEventSpec(first)?.price == 0 && e.state.specialEventSpec(second)?.price == 0)
            _ = e.perform(.specialEvent)
            #expect(e.state.currentSystem.specialEvent == second && e.state.commander.cash == 10_000, "\(first)")
        }
        var returned = questScenario(seed: 1, ev: SpecialEventType.princessReturned.rawValue, v: 1)
        let cash = returned.state.commander.cash
        #expect(returned.state.specialEventSpec(.princessQuantum)?.price == 0)
        _ = returned.perform(.specialEvent)
        #expect(returned.state.currentSystem.specialEvent == .princessQuantum && returned.state.commander.cash == cash)
    }

    @Test("QST-010 in-handler refusals are rejections that change nothing; SculptureHiddenBays commits its status")
    func refusals() {
        func refused(_ ev: SpecialEventType, _ error: CommandError, _ adjust: (inout GameState) -> Void) {
            var e = QSTKit.engine(ev, adjust)
            let before = e.state
            #expect(e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).rejection == error, "\(ev)")
            #expect(e.state == before, "\(ev) unchanged")
        }
        let fullGadgets: (inout GameState) -> Void = { s in
            s.commander.ship.gadgets = Array(repeating: .navigatingSystem, count: s.commander.ship.spec(s.ruleset).gadgetSlots)
        }
        let fullWeapons: (inout GameState) -> Void = { s in
            s.commander.ship.weapons = Array(repeating: .pulseLaser, count: s.commander.ship.spec(s.ruleset).weaponSlots)
        }
        refused(.gemulonFuel, .noFreeSlot, fullGadgets)
        refused(.dragonflyShield, .noFreeSlot) { s in
            s.commander.ship.shields = Array(repeating: ShieldInstance(type: .energy, charge: 0),
                                             count: s.commander.ship.spec(s.ruleset).shieldSlots)
        }
        refused(.reactorLaser, .noFreeSlot, fullWeapons)
        refused(.princessQuantum, .noFreeSlot, fullWeapons)
        refused(.jarek, .noFreeQuarters) { _ in }                                    // a Gnat has no spare quarters
        refused(.princessQonos, .noFreeQuarters) { $0.quests.princess = 4 }
        refused(.reactor, .noEmptyBays) { s in
            s.commander.policeRecordScore = -10; s.commander.reputationScore = 40; s.commander.ship.cargo[0] = 1
        }
        refused(.wild, .noFreeQuarters) { $0.commander.policeRecordScore = -10 }
        var hidden = QSTKit.engine(.sculptureHiddenBays) { s in fullGadgets(&s); s.quests.sculpture = 2 }
        let r = hidden.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(r.rejection == nil && r.events == [.specialEventRefused(.sculptureHiddenBays, reason: .noFreeSlot)])
        #expect(hidden.state.quests.sculpture == QuestStatus.Sculpture.done)
        #expect(hidden.state.currentSystem.specialEvent == .sculptureHiddenBays)
    }

    @Test("QST-012 one command handles one event; a replacement is offered at once and needs its own command")
    func oneEventPerCommand() {
        var e = QSTKit.engine(.gemulonRescued) { $0.quests.gemulon = 2 }
        #expect(e.perform(.specialEvent).events == [.specialEventCompleted(.gemulonRescued)])
        #expect(e.state.specialEventAvailable == .gemulonFuel)
        #expect(e.perform(.specialEvent).decision == .confirm(Confirmation(.acceptSpecialEvent, amounts: [0])))
        #expect(e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).events == [.specialEventCompleted(.gemulonFuel)])
        var d = QSTKit.engine(.dragonflyDestroyed) { $0.quests.dragonfly = 5 }
        #expect(d.perform(.specialEvent).events == [.specialEventCompleted(.dragonflyDestroyed)])
        #expect(d.state.specialEventAvailable == .dragonflyShield && d.state.quests.dragonfly == 5)
    }

    @Test("QST-013 no special event advances the day or touches the market beyond the chain rules")
    func noDayNoMarket() {
        for (ev, v) in Self.allSetups {
            var e = questScenario(seed: 3, ev: ev.rawValue, v: v)
            guard e.state.specialEventAvailable != nil else { continue }
            let before = e.state
            _ = e.perform(.specialEvent, acknowledging: Set(WarningID.allCases))
            let s = e.state
            #expect(s.commander.days == before.commander.days, "\(ev) v\(v) day")
            #expect(s.currentSystem.tradeItems == before.currentSystem.tradeItems, "\(ev) v\(v) stock")
            if ev == .eraseRecord || ev == .wildGetsOut {
                #expect(s.sellPrices == before.sellPrices.map { $0 * 100 / 90 }, "\(ev) v\(v) sell ×100/90")
            } else {
                #expect(s.sellPrices == before.sellPrices, "\(ev) v\(v) sell")
            }
            if s.skill(.trader) == before.skill(.trader) {
                #expect(s.buyPrices == before.buyPrices, "\(ev) v\(v) buy")
            } else {
                var expected = s
                expected.recalculateBuyPricesHere()
                #expect(s.buyPrices == expected.buyPrices, "\(ev) v\(v) buy recalculated")
            }
        }
    }

    @Test("QST-014 only CargoForSale (1 draw), Skill (1 draw if eligible) and JaporiDelivery (2 draws) use the RNG")
    func rngDraws() throws {
        for (ev, v) in Self.allSetups {
            var e = questScenario(seed: 5, ev: ev.rawValue, v: v)
            guard e.state.specialEventAvailable != nil else { continue }
            var expected = e.state.rng
            let r = e.perform(.specialEvent, acknowledging: Set(WarningID.allCases))
            guard r.rejection == nil else { continue }
            let draws = switch ev {
            case .cargoForSale, .skill: 1
            case .japoriDelivery: 2
            default: 0
            }
            for _ in 0..<draws { _ = expected.next(below: 10) }
            #expect(e.state.rng == expected, "\(ev) v\(v) draws \(draws)")
        }
        var maxed = QSTKit.engine(.skill) { $0.mercenaries[CrewID.commander].skills = [9, 9, 9, 9] }
        let rng = maxed.state.rng
        _ = maxed.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(maxed.state.rng == rng)                                            // no eligible skill: no draw
    }

    @Test("QST-015 MoonRetirement ends the game in the handler: no price, event kept, gameOver(.boughtMoon)")
    func moonEnding() {
        var e = QSTKit.engine(.moonRetirement) { $0.quests.moon = 1 }
        let cash = e.state.commander.cash
        let r = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(r.events == [.specialEventCompleted(.moonRetirement), .gameEnded(.boughtMoon, score: e.state.score(for: .boughtMoon))])
        #expect(e.state.phase == .gameOver(.boughtMoon) && e.state.commander.cash == cash)
        #expect(e.state.currentSystem.specialEvent == .moonRetirement)
    }

    // MARK: API

    @Test("QST-016 shared API: acceptSpecialEvent, noSpecialEvent, refusal errors; specialEventRefused only for HiddenBays")
    func sharedAPI() {
        var refusedTypes: Set<SpecialEventType> = []
        var errors: Set<CommandError> = []
        for (ev, v) in Self.allSetups {
            for seed: Int32 in [1, 2] {
                var e = questScenario(seed: seed, ev: ev.rawValue, v: v)
                let shown = e.state.specialEventAvailable != nil
                let r = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent, .wildLeavesForReactor])
                if !shown { #expect(r.rejection == .noSpecialEvent) }
                if let error = r.rejection { errors.insert(error) }
                for case let .specialEventRefused(t, reason) in r.events {
                    refusedTypes.insert(t)
                    #expect(reason == .noFreeSlot)
                }
                if r.rejection == nil, case .gameOver = e.state.phase {
                    #expect(r.events.last == .gameEnded(.boughtMoon, score: e.state.score(for: .boughtMoon)))
                } else if r.rejection == nil, r.decision == nil {
                    #expect(r.events.last == .specialEventCompleted(ev) || refusedTypes.contains(ev), "\(ev) completed")
                }
            }
        }
        #expect(refusedTypes.isSubset(of: [.sculptureHiddenBays]))
        #expect(errors.isSubset(of: [.noSpecialEvent, .insufficientFunds, .noFreeSlot, .noFreeQuarters, .noEmptyBays,
                                     .wildRequiresLaser, .wildRefusesReactor]))
        var japori = QSTKit.engine(.japori) { $0.commander.ship.cargo[0] = 6 }       // 9 free bays < 10
        #expect(japori.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).rejection == .noEmptyBays)
        var hidden = QSTKit.engine(.sculptureHiddenBays) { s in
            s.commander.ship.gadgets = Array(repeating: .navigatingSystem, count: s.commander.ship.spec(s.ruleset).gadgetSlots)
        }
        #expect(hidden.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).events
                == [.specialEventRefused(.sculptureHiddenBays, reason: .noFreeSlot)])
    }

    @Test("QST-017 the 46 events: one table row each; 26 message-only (OK) and 20 questions (Accept/Decline) as in §2")
    func eventTable() {
        let table = Ruleset.windows201.tables.specialEvents
        #expect(table.map(\.type) == SpecialEventType.allCases)
        #expect(table.filter(\.messageOnly).count == 26 && table.filter { !$0.messageOnly }.count == 20)
        let questions: Set<SpecialEventType> = [.artifact, .cargoForSale, .dragonflyShield, .eraseRecord, .gemulonFuel, .japori,
                                                .jarek, .moon, .moonRetirement, .reactor, .reactorLaser, .scarabUpgradeHull,
                                                .skill, .tribble, .tribbleBuyer, .wild, .sculpture, .sculptureHiddenBays,
                                                .princessQonos, .princessQuantum]
        #expect(Set(table.filter { !$0.messageOnly }.map(\.type)) == questions)
        let prices: [SpecialEventType: Int] = [.artifactDelivery: -20_000, .cargoForSale: 1_000, .eraseRecord: 5_000,
                                               .lottery: -1_000, .moon: 500_000, .skill: 3_000, .spaceMonsterKilled: -15_000,
                                               .tribble: 1_000, .sculpture: -2_000]
        for row in table { #expect(row.price == prices[row.type] ?? 0, "\(row.type) price") }
    }

    // MARK: Invariants

    @Test("QST-018 invariants hold after every special event and along random play; the moon status never decreases")
    func invariants() throws {
        for (ev, v) in Self.allSetups {
            var e = questScenario(seed: 7, ev: ev.rawValue, v: v)
            let moon = e.state.quests.moon
            _ = e.perform(.specialEvent, acknowledging: Set(WarningID.allCases))
            #expect(QSTKit.invariantViolations(e.state).isEmpty, "\(ev) v\(v) \(QSTKit.invariantViolations(e.state))")
            #expect(e.state.quests.moon >= moon)
        }
        for seed: UInt64 in [11, 12] {
            var e = QSTKit.engine(nil, seed: seed) { $0.commander.cash = 100_000 }
            var mix = Mix(x: seed)
            for _ in 0..<12 {
                let dest = e.state.destinations.filter { $0 != e.state.commander.currentSystem }
                guard !dest.isEmpty else { break }
                let moon = e.state.quests.moon
                _ = try #require(QSTKit.quietWarp(&e, to: dest[mix.next(dest.count)]))
                _ = e.perform(.specialEvent, acknowledging: Set(WarningID.allCases))
                #expect(QSTKit.invariantViolations(e.state).isEmpty, "\(QSTKit.invariantViolations(e.state))")
                #expect(e.state.quests.moon >= moon)
                if case .gameOver = e.state.phase { break }
            }
        }
    }

    @Test("QST-019 every shown event is handleable: completed, a documented rejection or the Reactor/Wild consent")
    func handleable() {
        let documented: Set<CommandError> = [.insufficientFunds, .noFreeSlot, .noFreeQuarters, .noEmptyBays,
                                             .wildRequiresLaser, .wildRefusesReactor]
        for (ev, v) in Self.allSetups {
            for seed: Int32 in [1, 2] {
                var e = questScenario(seed: seed, ev: ev.rawValue, v: v)
                guard e.state.specialEventAvailable == ev else { continue }
                let r = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
                if let error = r.rejection {
                    #expect(documented.contains(error), "\(ev) v\(v) \(error)")
                } else if case let .confirm(c) = r.decision {
                    #expect(c.warning == .wildLeavesForReactor && ev == .reactor, "\(ev) v\(v)")
                } else {
                    #expect(r.events.contains(.specialEventCompleted(ev)) || r.events.contains { if case .specialEventRefused = $0 { true } else { false } },
                            "\(ev) v\(v)")
                }
            }
        }
    }
}
