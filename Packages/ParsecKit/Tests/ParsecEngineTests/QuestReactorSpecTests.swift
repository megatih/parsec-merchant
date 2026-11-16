// SPDX-License-Identifier: GPL-2.0-or-later
// QST-REACTOR (docs/specs/QST-REACTOR.md): statuses, pickup, effects while aboard, countdown, meltdown, laser, losses.
import Testing
@testable import ParsecEngine

private let yes = QuestTrip.yes

/// A docked game with record −10, reputation 40 and a 30-bay Grasshopper (two weapon slots, one Beam laser).
private func reactorEngine(_ event: SpecialEventType? = nil, status: Int = 0, _ adjust: (inout GameState) -> Void = { _ in }) -> GameEngine {
    QuestTrip.engine(event) { s in
        s.commander.policeRecordScore = -10
        s.commander.ship = QuestTrip.ship(.grasshopper, s, weapons: [.beamLaser])
        s.quests.reactor = status
        adjust(&s)
    }
}

/// Reactor warning statuses among `events`.
private func warnings(_ events: [GameEvent]) -> [Int] {
    events.compactMap { if case let .reactorWarning(status) = $0 { status } else { nil } }
}

// MARK: §1-3 Statuses, button, pickup

@Suite("QST-REACTOR: statuses, button, pickup")
struct QuestReactorPickupSpecTests {
    @Test("QST-REACTOR-001 statuses 0/1/20/21/22; aboard means 0 < reactor < 21; a new game starts at 0")
    func statuses() {
        let r = QuestStatus.Reactor.self
        #expect([r.notStarted, r.fuelOK, r.date, r.delivered, r.done] == [0, 1, 20, 21, 22])
        var s = makeEngine().state
        #expect(s.quests.reactor == 0)
        for status in 0...22 {
            s.quests.reactor = status
            #expect(s.reactorOnBoard == (status > 0 && status < 21), "\(status)")
        }
    }

    @Test("QST-REACTOR-002 reactor ≥ 70 parsecs from Nix, reactorDelivered at Nix, reactorLaser never placed; table rows")
    func placementAndRows() throws {
        for seed in UInt64(0)..<10 {
            let s = makeEngine(seed: seed).state
            #expect(s.galaxy.systems[SystemID.nix].specialEvent == .reactorDelivered)
            let placed = s.galaxy.systems.indices.filter { s.galaxy.systems[$0].specialEvent == .reactor }
            #expect(placed.count == 1)
            for i in placed {
                #expect(GalaxyGenerator.distance(s.galaxy.systems[SystemID.nix], s.galaxy.systems[i], rule: s.ruleset.flags.distance) >= 70)
            }
            #expect(!s.galaxy.systems.contains { $0.specialEvent == .reactorLaser })
        }
        let s = makeEngine().state
        for (type, messageOnly) in [(SpecialEventType.reactor, false), (.reactorDelivered, true), (.reactorLaser, false)] {
            let row = try #require(s.specialEventSpec(type))
            #expect(row.price == 0 && row.occurrence == 0 && row.messageOnly == messageOnly, "\(type)")
        }
        for type in [SpecialEventType.reactor, .reactorLaser] {
            var e = reactorEngine(type, status: type == .reactorLaser ? 21 : 0)
            #expect(e.perform(.specialEvent).decision == .confirm(Confirmation(.acceptSpecialEvent, amounts: [0])), "\(type)")
        }
    }

    @Test("QST-REACTOR-003 reactor needs status 0, record < −5, reputation ≥ 40; delivered needs it aboard; laser always shows")
    func button() {
        let cases: [(Int, Int, Int, Bool)] = [(0, -6, 40, true), (0, -5, 40, false), (0, -10, 39, false), (21, -10, 40, false)]
        for (status, record, reputation, shown) in cases {
            let s = reactorEngine(.reactor, status: status) { s in
                s.commander.policeRecordScore = record
                s.commander.reputationScore = reputation
            }.state
            #expect((s.specialEventAvailable == .reactor) == shown, "\(status) \(record) \(reputation)")
        }
        #expect(reactorEngine(.reactorDelivered).state.specialEventAvailable == nil)
        #expect(reactorEngine(.reactorDelivered, status: 19).state.specialEventAvailable == .reactorDelivered)
        #expect(reactorEngine(.reactorLaser) { s in s.commander.policeRecordScore = 50; s.commander.reputationScore = 0 }
            .state.specialEventAvailable == .reactorLaser)
    }

    @Test("QST-REACTOR-005 fewer than 15 free bays: noEmptyBays and the offer stays")
    func bays() {
        var e = reactorEngine(.reactor) { $0.commander.ship.cargo[0] = 16 }
        let before = e.state
        #expect(e.state.freeCargoBays == 14)
        #expect(e.perform(.specialEvent, acknowledging: yes).rejection == .noEmptyBays && e.state == before)
        var ok = reactorEngine(.reactor) { $0.commander.ship.cargo[0] = 15 }
        #expect(ok.perform(.specialEvent, acknowledging: yes).rejection == nil && ok.state.reactorOnBoard)
    }

    @Test("QST-REACTOR-006 with Wild aboard: wildLeavesForReactor needed (decline keeps all); with it Wild's status 0, he stays")
    func wildConsent() {
        var e = reactorEngine(.reactor) { s in s.hireCrew(CrewID.wild); s.quests.wild = 5 }
        let before = e.state
        #expect(e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).decision == .confirm(Confirmation(.wildLeavesForReactor)))
        #expect(e.state == before && e.state.specialEventAvailable == .reactor)
        _ = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent, .wildLeavesForReactor])
        #expect(e.state.quests.wild == 0 && e.state.wildOnBoard && e.state.quests.reactor == 1)
    }

    @Test("QST-REACTOR-007 success: status 1, removed; events [wildLeftShip]? then specialEventCompleted(.reactor)")
    func success() {
        var e = reactorEngine(.reactor)
        #expect(e.perform(.specialEvent, acknowledging: yes).events == [.specialEventCompleted(.reactor)])
        #expect(e.state.quests.reactor == QuestStatus.Reactor.fuelOK && e.state.currentSystem.specialEvent == nil)
        var w = reactorEngine(.reactor) { s in s.hireCrew(CrewID.wild); s.quests.wild = 2 }
        #expect(w.perform(.specialEvent, acknowledging: yes).events == [.wildLeftShip, .specialEventCompleted(.reactor)])
    }
}

// MARK: §4 While aboard

@Suite("QST-REACTOR: while aboard")
struct QuestReactorAboardSpecTests {
    @Test("QST-REACTOR-008 bays 5 + 10 − (status − 1)/2; not a trade item (cannot be sold, dumped or stolen)")
    func bayFormula() {
        var s = reactorEngine().state
        let bays = s.commander.ship.cargoBays(s.ruleset)
        #expect(bays == 30)
        let expected = [15, 15, 14, 14, 13, 13, 12, 12, 11, 11, 10, 10, 9, 9, 8, 8, 7, 7, 6]
        for status in 1...19 {
            s.quests.reactor = status
            #expect(s.freeCargoBays == bays - expected[status - 1], "\(status)")
        }
        s.quests.reactor = 1
        #expect(s.freeCargoBays == 15)
        s.quests.reactor = 5
        #expect(s.freeCargoBays == 17 && s.commander.ship.cargo.allSatisfy { $0 == 0 })
        var e = reactorEngine(status: 5) { setMarket(&$0) }
        for item in TradeItemType.allCases {
            #expect(e.perform(.sellCargo(item, quantity: 1)).rejection != nil)
            #expect(e.perform(.dumpCargo(item, quantity: 1), acknowledging: yes).rejection != nil)
        }
        // Pirates find no cargo: blackmail, and the reactor stays.
        var raid = Pol.engine(.pirateAttack) { s in s.commander.ship = QuestTrip.ship(.grasshopper, s); s.quests.reactor = 5 }
        let events = raid.perform(.encounter(.surrender)).events
        #expect(events.contains { if case .blackmailed = $0 { true } else { false } } && raid.state.quests.reactor == 5)
    }

    @Test("QST-REACTOR-009 damage factor, tribbles, illegal special cargo, trade block, raid has no reactor event, Wild refuses")
    func effects() {
        // (a) Hard: the opponent's damage to the player is doubled (same draws, larger hull loss).
        var bigger = 0
        for seed in UInt64(0)..<200 {
            var plain = CombatKit.state(.hard, seed: seed)
            plain.commander.ship = CombatKit.playerShip(plain, .wasp)
            var enc = EncounterState(type: .pirateAttack, opponent: CombatKit.opponent(&plain, .wasp, weapons: [.beamLaser], skills: [5, 10, 5, 5]))
            var loaded = plain, enc2 = enc
            loaded.quests.reactor = 5
            _ = plain.executeAttack(commanderAttacks: false, fleeing: false, encounter: &enc)
            _ = loaded.executeAttack(commanderAttacks: false, fleeing: false, encounter: &enc2)
            #expect(loaded.commander.ship.hull <= plain.commander.ship.hull)
            if loaded.commander.ship.hull < plain.commander.ship.hull { bigger += 1 }
        }
        #expect(bigger > 0)
        // (b) Tribbles: all die below 20, else they halve.
        // QST-TRIBBLES: the death notice precedes the count change.
        for (count, left, death) in [(19, 0, TribbleDeath.allFromReactor), (20, 10, .halfFromReactor), (101, 50, .halfFromReactor)] {
            var s = reactorEngine(status: 3) { $0.commander.ship.tribbles = count }.state
            #expect(s.arrivalTribbles() == [.tribblesDied(death), .tribblesChanged(from: count, to: left)])
        }
        // (c) Illegal special cargo: submit, surrender and yield arrest; the bribe is multiplied.
        let s = reactorEngine(status: 3).state
        var clean = s
        clean.quests.reactor = 0
        #expect(s.illegalSpecialCargo && !clean.illegalSpecialCargo && (s.bribeAmount ?? 0) > (clean.bribeAmount ?? 0))
        for (type, action) in [(EncounterType.policeInspect, EncounterAction.submit), (.policeAttack, .surrender), (.marieCelestePolice, .yield)] {
            var p = Pol.engine(type) { s in s.commander.cash = 50_000; s.quests.reactor = 3 }
            #expect(p.perform(.encounter(action), acknowledging: yes).events.contains(where: QuestTrip.isArrest), "\(action)")
        }
        // (d) Ship trades are refused.
        var trade = reactorEngine(status: 3) { $0.galaxy.systems[$0.commander.currentSystem].techLevel = .hiTech }
        #expect(trade.perform(.buyShip(.hornet, transfers: []), acknowledging: yes).rejection == .reactorOnBoard)
        // (e) A pirate raid emits only the loot step: the app shows the reactor notice from the state.
        var raid = Pol.engine(.pirateAttack) { s in s.commander.ship.cargo[0] = 1; s.quests.reactor = 3 }
        let events = raid.perform(.encounter(.surrender)).events
        #expect(events.first == .looted(units: 1) && raid.state.reactorOnBoard)
        // (f) Wild refuses to board.
        var w = reactorEngine(.wild, status: 3)
        #expect(w.perform(.specialEvent, acknowledging: yes).rejection == .wildRefusesReactor)
    }

    @Test("QST-REACTOR-010 each IncDays(n) adds n up to 20; a singularity jump adds no day")
    func countdown() {
        var s = reactorEngine(status: 1).state
        _ = s.incDays(1)
        #expect(s.quests.reactor == 2)
        _ = s.incDays(5)
        #expect(s.quests.reactor == 7)
        _ = s.incDays(30)
        #expect(s.quests.reactor == 20)
        var off = reactorEngine(status: 21).state
        _ = off.incDays(3)
        #expect(off.quests.reactor == 21)
        var jump = reactorEngine(status: 4) { s in
            s.quests.canSuperWarp = true
            s.warpSystem = s.galaxy.systems.indices.first { $0 != s.commander.currentSystem && !QuestTrip.questSystems.contains($0) } ?? 1
        }
        let days = jump.state.commander.days
        let trip = completeTrip(&jump, .jump, ack: yes)
        #expect(trip.result.rejection == nil && jump.state.commander.days == days && jump.state.quests.reactor == 4)
        // k normal departures after loading reach 1 + k.
        var e = reactorEngine(status: 1)
        for k in 1...3 { _ = QuestTrip.hop(&e); #expect(e.state.quests.reactor == 1 + k) }
    }
}

// MARK: §5-7 Arrival, laser, losses

@Suite("QST-REACTOR: arrival, laser, losses")
struct QuestReactorArrivalSpecTests {
    @Test("QST-REACTOR-011 reactorDelivered at 1…19: status 21, event becomes reactorLaser, bays freed")
    func delivered() {
        for status in [1, 7, 19] {
            var e = reactorEngine(.reactorDelivered, status: status)
            let free = e.state.freeCargoBays
            #expect(e.perform(.specialEvent).events == [.specialEventCompleted(.reactorDelivered)])
            #expect(e.state.quests.reactor == 21 && e.state.currentSystem.specialEvent == .reactorLaser)
            #expect(e.state.freeCargoBays == free + 5 + 10 - (status - 1) / 2 && !e.state.reactorOnBoard)
        }
        // An arrival at 20 melts down first, so the delivery is no longer offered.
        var e = reactorEngine(status: 20) { $0.commander.ship.escapePod = true }
        _ = QuestTrip.travel(&e, to: SystemID.nix)
        #expect(e.state.commander.currentSystem == SystemID.nix && e.state.quests.reactor == 0 && e.state.specialEventAvailable == nil)
    }

    @Test("QST-REACTOR-012 the first arrival step warns at 2, 16 and 18 with that status, and nowhere else")
    func arrivalWarnings() {
        for status in 1...19 {
            var s = reactorEngine(status: status).state
            s.warpSystem = plainTarget(s) ?? 1
            let events = s.arrival()
            let want = [2, 16, 18].contains(status) ? [status] : []
            #expect(warnings(events) == want, "\(status)")
            if !want.isEmpty { #expect(events.first == .reactorWarning(status: status)) }
        }
    }

    @Test("QST-REACTOR-013 QST-REACTOR-021 meltdown at 20: pod → status 0 (not 22), pipeline continues; no pod → killed, stop")
    func meltdown() {
        var pod = reactorEngine(status: 20) { $0.commander.ship.escapePod = true }.state
        pod.warpSystem = plainTarget(pod) ?? 1
        let podEvents = pod.arrival()
        #expect(podEvents.first == .reactorMeltdown && podEvents.contains(where: QuestTrip.isPod))
        #expect(podEvents.last == .arrived(system: pod.warpSystem))
        #expect(pod.quests.reactor == 0 && pod.commander.ship.type == .flea && pod.phase == .docked)
        var dead = reactorEngine(status: 20).state
        dead.warpSystem = plainTarget(dead) ?? 1
        let deadEvents = dead.arrival()
        #expect(deadEvents == [.reactorMeltdown, .gameEnded(.killed, score: dead.score(for: .killed))])
        #expect(dead.phase == .gameOver(.killed))
        // QST-REACTOR-021: the meltdown is tested only on arrival; reaching 20 in IncDays does nothing else.
        var counting = reactorEngine(status: 19).state
        #expect(counting.incDays(4).isEmpty && counting.quests.reactor == 20 && counting.reactorOnBoard)
    }

    @Test("QST-REACTOR-015 reactorLaser: noFreeSlot keeps the offer; else Morgan's laser (85), status 22, removed")
    func laser() {
        #expect(makeEngine().ruleset.tables.weapon(.morgansLaser).power == 85)
        var full = reactorEngine(.reactorLaser, status: 21) { $0.commander.ship.weapons = [.pulseLaser, .pulseLaser] }
        let before = full.state
        #expect(full.perform(.specialEvent, acknowledging: yes).rejection == .noFreeSlot && full.state == before)
        #expect(full.state.specialEventAvailable == .reactorLaser)
        var e = reactorEngine(.reactorLaser, status: 21)
        #expect(e.perform(.specialEvent, acknowledging: yes).events == [.specialEventCompleted(.reactorLaser)])
        #expect(e.state.commander.ship.weapons == [.beamLaser, .morgansLaser] && e.state.quests.reactor == 22)
        #expect(e.state.currentSystem.specialEvent == nil)
    }

    @Test("QST-REACTOR-017 arrest confiscates the reactor (status 0); no delivery at Nix afterwards")
    func arrest() {
        var e = Pol.engine(.policeInspect) { s in s.commander.cash = 50_000; s.quests.reactor = 6 }
        #expect(e.perform(.encounter(.submit), acknowledging: yes).events.contains(where: QuestTrip.isArrest))
        #expect(e.state.quests.reactor == 0 && !e.state.reactorOnBoard)
        _ = QuestTrip.travel(&e, to: SystemID.nix)
        #expect(e.state.commander.currentSystem == SystemID.nix && e.state.specialEventAvailable == nil)
    }

    @Test("QST-REACTOR-018 escape pod with the reactor aboard: status 22, no laser, no delivery at Nix")
    func pod() {
        var e = Pol.engine(.pirateAttack) { s in s.commander.ship.escapePod = true; s.quests.reactor = 6 }
        #expect(e.finishEncounter(.escapePod).contains(where: QuestTrip.isPod))
        #expect(e.state.quests.reactor == 22 && !e.state.commander.ship.weapons.contains(.morgansLaser))
        _ = QuestTrip.travel(&e, to: SystemID.nix)
        #expect(e.state.specialEventAvailable == nil)
    }

    @Test("QST-REACTOR-020 the chain adds no news headline")
    func noNews() {
        #expect(!NewsEvent.allCases.contains { "\($0)".lowercased().contains("reactor") })
        var with = reactorEngine(status: 3)
        var without = reactorEngine()
        _ = QuestTrip.travel(&with, to: SystemID.nix)
        _ = QuestTrip.travel(&without, to: SystemID.nix)
        #expect(with.state.newsEvents == without.state.newsEvents)
        _ = with.perform(.specialEvent)
        #expect(with.state.newsEvents == without.state.newsEvents)
    }
}

// MARK: §9 Scenarios

@Suite("QST-REACTOR: scenarios")
struct QuestReactorScenarioSpecTests {
    @Test("QST-REACTOR-022 scenario: accept (5 free bays), warning on arrival 1, deliver at Nix on arrival 6, install the laser")
    func happyPath() {
        var e = reactorEngine(.reactor) { s in s.commander.ship = QuestTrip.ship(.bumblebee, s); s.commander.ship.cargo[0] = 5 }
        #expect(e.state.freeCargoBays == 20)
        _ = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(e.state.quests.reactor == 1 && e.state.freeCargoBays == 5)
        for arrival in 1...5 {
            let w = warnings(QuestTrip.hop(&e))
            #expect(w == (arrival == 1 ? [2] : []), "arrival \(arrival)")
        }
        _ = QuestTrip.travel(&e, to: SystemID.nix)
        #expect(e.state.quests.reactor == 7 && e.state.freeCargoBays == 25 - 5 - 12)
        _ = e.perform(.specialEvent)
        #expect(e.state.quests.reactor == 21 && e.state.freeCargoBays == 20 && e.state.currentSystem.specialEvent == .reactorLaser)
        _ = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(e.state.commander.ship.weapons == [.morgansLaser] && e.state.quests.reactor == 22 && e.state.currentSystem.specialEvent == nil)
    }

    /// Loads the reactor and makes 19 normal warps; returns the events of each arrival.
    func nineteenWarps(pod: Bool) -> (GameEngine, [[GameEvent]]) {
        var e = reactorEngine(.reactor) { $0.commander.ship.escapePod = pod }
        _ = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        var arrivals: [[GameEvent]] = []
        for _ in 1...19 { arrivals.append(QuestTrip.hop(&e)) }
        return (e, arrivals)
    }

    @Test("QST-REACTOR-023 scenario meltdown: warnings on arrivals 1, 15, 17; arrival 19 kills, or the pod saves and the arrival completes")
    func meltdownScenario() {
        for pod in [false, true] {
            let (e, arrivals) = nineteenWarps(pod: pod)
            for (i, events) in arrivals.dropLast().enumerated() {
                let want: [Int] = [1: [2], 15: [16], 17: [18]][i + 1] ?? []
                #expect(warnings(events) == want, "pod \(pod) arrival \(i + 1)")
            }
            let last = arrivals.last ?? []
            let melt = last.firstIndex(of: .reactorMeltdown) ?? last.count
            #expect(melt < last.count, "pod \(pod)")
            let after = Array(last.suffix(from: min(melt, last.count)))
            if pod {
                #expect(after.contains(where: QuestTrip.isPod) && after.last == .arrived(system: e.state.commander.currentSystem))
                #expect(e.state.quests.reactor == 0 && e.state.commander.ship.type == .flea && e.state.phase == .docked)
            } else {
                #expect(after == [.reactorMeltdown, .gameEnded(.killed, score: e.state.score(for: .killed))])
                #expect(e.state.phase == .gameOver(.killed))
            }
        }
    }

    @Test("QST-REACTOR-024 scenario refusals: 14 bays, Wild consent, laser with full slots, record −5 / reputation 39 hidden")
    func refusals() {
        var a = reactorEngine(.reactor) { $0.commander.ship.cargo[0] = 16 }
        let before = a.state
        #expect(a.perform(.specialEvent, acknowledging: yes).rejection == .noEmptyBays && a.state == before)
        var b = reactorEngine(.reactor) { s in s.hireCrew(CrewID.wild); s.quests.wild = 1 }
        let beforeB = b.state
        #expect(b.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).decision == .confirm(Confirmation(.wildLeavesForReactor)))
        #expect(b.state == beforeB)
        let r = b.perform(.specialEvent, acknowledging: [.acceptSpecialEvent, .wildLeavesForReactor])
        #expect(r.events == [.wildLeftShip, .specialEventCompleted(.reactor)])
        #expect(b.state.quests.wild == 0 && b.state.wildOnBoard && b.state.quests.reactor == 1)
        var c = reactorEngine(.reactorLaser, status: 21) { $0.commander.ship.weapons = [.beamLaser, .beamLaser] }
        #expect(c.perform(.specialEvent, acknowledging: yes).rejection == .noFreeSlot)
        #expect(c.state.quests.reactor == 21 && c.state.specialEventAvailable == .reactorLaser)
        #expect(reactorEngine(.reactor) { $0.commander.policeRecordScore = -5 }.state.specialEventAvailable == nil)
        #expect(reactorEngine(.reactor) { $0.commander.reputationScore = 39 }.state.specialEventAvailable == nil)
    }

    @Test("QST-REACTOR-025 scenario losses: arrest (status 0), pod (status 22), no button at Nix; buying a ship → reactorOnBoard")
    func losses() {
        var a = Pol.engine(.policeAttack) { s in s.commander.cash = 50_000; s.quests.reactor = 9 }
        #expect(a.perform(.encounter(.surrender), acknowledging: yes).events.contains(where: QuestTrip.isArrest))
        #expect(a.state.quests.reactor == 0)
        _ = QuestTrip.travel(&a, to: SystemID.nix)
        #expect(a.state.specialEventAvailable == nil)
        var b = Pol.engine(.pirateAttack) { s in s.commander.ship.escapePod = true; s.quests.reactor = 9 }
        _ = b.finishEncounter(.escapePod)
        #expect(b.state.quests.reactor == 22)
        _ = QuestTrip.travel(&b, to: SystemID.nix)
        #expect(b.state.specialEventAvailable == nil)
        var c = reactorEngine(status: 9) { $0.galaxy.systems[$0.commander.currentSystem].techLevel = .hiTech }
        let before = c.state
        #expect(c.perform(.buyShip(.wasp, transfers: []), acknowledging: yes).rejection == .reactorOnBoard && c.state == before)
    }
}
