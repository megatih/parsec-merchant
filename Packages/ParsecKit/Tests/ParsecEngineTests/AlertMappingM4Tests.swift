// SPDX-License-Identifier: GPL-2.0-or-later
// Engine side of the {M4} alert mappings (docs/specs/ALR.md): each classic quest alert's trigger yields the mapped value.
import Testing
@testable import ParsecEngine

/// A docked engine with `event` at the current system, a Wasp with free slots and a free quarter, and plenty of cash.
private func eventEngine(_ event: SpecialEventType, record: Int = 10, _ adjust: (inout GameState) -> Void = { _ in }) -> GameEngine {
    makeEngine { s in
        var ship = freshShip(.wasp, s)
        ship.weapons = [.beamLaser]
        s.commander.ship = ship
        s.commander.cash = 600_000
        s.commander.policeRecordScore = record
        s.commander.reputationScore = 40
        s.galaxy.systems[s.commander.currentSystem].specialEvent = event
        adjust(&s)
    }
}

/// Performs the special event with every consent given.
private func accept(_ e: inout GameEngine) -> StepResult {
    e.perform(.specialEvent, acknowledging: Set(WarningID.allCases))
}

private func has(_ events: [GameEvent], _ test: (GameEvent) -> Bool) -> Bool { events.contains(where: test) }

@Suite("Alert mappings, engine side (ALR {M4}): special-event results and refusals")
struct AlertMappingM4SpecialTests {
    @Test("ALR-002 ALR-129 ALR-153 ALR-150 ALR-149 cargo and status results map to specialEventCompleted")
    func statusResults() {
        var japori = eventEngine(.japori)
        let bays = japori.state.freeCargoBays
        #expect(accept(&japori).events == [.specialEventCompleted(.japori)])                                  // AntidoteOnBoard
        #expect(japori.state.freeCargoBays == bays - 10)
        var reactor = eventEngine(.reactor, record: -10)
        let rBays = reactor.state.freeCargoBays
        #expect(accept(&reactor).events == [.specialEventCompleted(.reactor)])                                // ReactorOnBoard
        #expect(reactor.state.reactorOnBoard && reactor.state.freeCargoBays == rBays - 15)
        var moon = eventEngine(.moon)
        #expect(accept(&moon).events == [.specialEventCompleted(.moon)])                                      // SpecialMoonBought
        #expect(moon.state.quests.moon == QuestStatus.Moon.bought)
        var erase = eventEngine(.eraseRecord, record: -20)
        #expect(accept(&erase).events == [.specialEventCompleted(.eraseRecord)])                              // SpecialCleanRecord
        #expect(erase.state.commander.policeRecordScore == 0)
        var hull = eventEngine(.scarabUpgradeHull) { $0.quests.scarab = QuestStatus.Scarab.destroyed }
        let h = hull.state.commander.ship.hull
        #expect(accept(&hull).events == [.specialEventCompleted(.scarabUpgradeHull)])                         // ShipHullUpgraded
        #expect(hull.state.commander.ship.hull == h + 50 && hull.state.commander.ship.hullUpgraded)
    }

    @Test("ALR-083 ALR-084 ALR-086 ALR-087 ALR-089 quest rewards install their equipment with specialEventCompleted")
    func rewards() {
        func reward(_ ev: SpecialEventType, _ adjust: (inout GameState) -> Void = { _ in }) -> (StepResult, Ship) {
            var e = eventEngine(ev, adjust)
            return (accept(&e), e.state.commander.ship)
        }
        let (fuel, s1) = reward(.gemulonFuel) { $0.quests.gemulon = QuestStatus.Gemulon.fuel }
        #expect(fuel.events == [.specialEventCompleted(.gemulonFuel)] && s1.gadgets.contains(.fuelCompactor))   // EquipmentFuelCompactor
        let (bays, s2) = reward(.sculptureHiddenBays) { $0.quests.sculpture = QuestStatus.Sculpture.delivered }
        #expect(bays.events == [.specialEventCompleted(.sculptureHiddenBays)] && s2.gadgets.contains(.hiddenCargoBays))  // EquipmentHiddenCompartments
        let (shield, s3) = reward(.dragonflyShield)
        #expect(shield.events == [.specialEventCompleted(.dragonflyShield)] && s3.shields.map(\.type).contains(.lightning))  // EquipmentLightningShield
        let (laser, s4) = reward(.reactorLaser) { $0.quests.reactor = QuestStatus.Reactor.delivered }
        #expect(laser.events == [.specialEventCompleted(.reactorLaser)] && s4.weapons.contains(.morgansLaser))  // EquipmentMorgansLaser
        let (quantum, s5) = reward(.princessQuantum) { $0.quests.princess = QuestStatus.Princess.returned }
        #expect(quantum.events == [.specialEventCompleted(.princessQuantum)] && s5.weapons.contains(.quantumDisruptor))  // EquipmentQuantumDisruptor
    }

    @Test("ALR-162 ALR-163 ALR-164 ALR-171 ALR-175 passengers, canisters, skill and tribble results")
    func otherResults() {
        var jarek = eventEngine(.jarek)
        #expect(accept(&jarek).events == [.specialEventCompleted(.jarek)] && jarek.state.jarekOnBoard)        // SpecialPassengerOnBoard
        var wild = eventEngine(.wild, record: -10)
        #expect(accept(&wild).events == [.specialEventCompleted(.wild)] && wild.state.wildOnBoard)
        var princess = eventEngine(.princessQonos) { $0.quests.princess = QuestStatus.Princess.rescued }
        #expect(accept(&princess).events == [.specialEventCompleted(.princessQonos)] && princess.state.princessOnBoard)
        var cargo = eventEngine(.cargoForSale)
        let r = accept(&cargo)
        guard case let .sealedCanisters(item) = r.events.first else { Issue.record("no canisters"); return }   // SpecialSealedCanisters
        #expect(r.events == [.sealedCanisters(item), .specialEventCompleted(.cargoForSale)])
        #expect(cargo.state.commander.ship.cargo[item.rawValue] == 3)
        var skill = eventEngine(.skill)
        let before = skill.state.mercenaries[CrewID.commander].skills
        #expect(accept(&skill).events == [.specialEventCompleted(.skill)])                                    // SpecialSkillIncrease
        let after = skill.state.mercenaries[CrewID.commander].skills
        #expect(zip(before, after).filter { $0 != $1 }.map { $1 - $0 } == [1])   // exactly one skill, +1: derivable
        var buyer = eventEngine(.tribbleBuyer) { $0.commander.ship.tribbles = 10 }
        #expect(accept(&buyer).events == [.specialEventCompleted(.tribbleBuyer)])                             // TribblesGone
        var tribble = eventEngine(.tribble)
        #expect(accept(&tribble).events == [.specialEventCompleted(.tribble)])                                // TribblesOwn
    }

    @Test("ALR-152 ALR-154 ALR-185 ALR-186 ALR-188 special-event refusals and the reactor-with-Wild consent")
    func refusals() {
        var poor = eventEngine(.moon) { $0.commander.cash = 400_000 }
        #expect(poor.perform(.specialEvent).decision == .confirm(Confirmation(.acceptSpecialEvent, amounts: [500_000])))
        #expect(accept(&poor).rejection == .insufficientFunds)                                               // SpecialIF
        var full = eventEngine(.jarek) { s in s.commander.ship.crew = [CrewID.commander, 1, 2] }
        #expect(accept(&full).rejection == .noFreeQuarters)                                                  // SpecialNoQuarters
        var noLaser = eventEngine(.wild, record: -10) { $0.commander.ship.weapons = [.pulseLaser] }
        #expect(accept(&noLaser).rejection == .wildRequiresLaser)                                            // WildWontBoardLaser
        var reactorAboard = eventEngine(.wild, record: -10) { $0.quests.reactor = 3 }
        #expect(accept(&reactorAboard).rejection == .wildRefusesReactor)                                     // WildWontBoardReactor
        var leaves = eventEngine(.reactor, record: -10) { s in s.hireCrew(CrewID.wild); s.quests.wild = QuestStatus.Wild.started }
        let ask = leaves.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(ask.decision == .confirm(Confirmation(.wildLeavesForReactor)))                               // WildWontStayAboardReactor
        let done = leaves.perform(.specialEvent, acknowledging: [.acceptSpecialEvent, .wildLeavesForReactor])
        #expect(done.events == [.wildLeftShip, .specialEventCompleted(.reactor)])
    }

    @Test("ALR-183 ALR-187 departing with Wild and no beam laser asks wildLeavesWithoutLaser, then wildLeftShip")
    func wildDeparture() throws {
        var e = makeEngine { s in
            s.commander.ship = freshShip(.beetle, s)
            s.commander.ship.weapons = []
            s.hireCrew(CrewID.wild)
            s.quests.wild = QuestStatus.Wild.started
        }
        let t = try #require(plainTarget(e.state))
        _ = e.perform(.selectTarget(t))
        #expect(e.perform(.warp).decision == .confirm(Confirmation(.wildLeavesWithoutLaser)))                // WildWontStayAboardLaser
        let r = e.perform(.warp, acknowledging: [.wildLeavesWithoutLaser])
        #expect(r.events.first == .wildLeftShip)                                                              // WildLeavesShip
        // C# resets the status but leaves him in the crew, so the departure's IncDays counts it to 1 (kept quirk).
        #expect(e.state.quests.wild == QuestStatus.Wild.started)
    }
}

@Suite("Alert mappings, engine side (ALR {M4}): encounters")
struct AlertMappingM4EncounterTests {
    @Test("ALR-012 ALR-035 surrendering the artifact to the Mantis: consent, then artifactRelinquished")
    func mantis() {
        var e = m4EncounterEngine(.pirateAttack, opponent: .mantis) { s, _ in s.quests.artifact = QuestStatus.Artifact.onBoard }
        #expect(e.perform(.encounter(.surrender)).decision == .confirm(Confirmation(.surrenderArtifact)))     // EncounterAliensSurrender
        let r = e.perform(.encounter(.surrender), acknowledging: [.surrenderArtifact])
        #expect(r.events.first == .artifactRelinquished && e.state.quests.artifact == QuestStatus.Artifact.notStarted)  // ArtifactRelinquished
    }

    @Test("ALR-038 ALR-044 the Scorpion: noDisruptors without disruptor power; disabling emits opponentDisabled and rescues")
    func scorpion() throws {
        var bare = m4EncounterEngine(.scorpionAttack, opponent: .scorpion) { s, _ in s.commander.ship.weapons = [.militaryLaser] }
        #expect(bare.perform(.encounter(.attack)).rejection == .noDisruptors)                                // EncounterAttackNoDisruptors
        let base = m4EncounterEngine(.scorpionAttack, opponent: .scorpion) { s, opp in
            s.commander.ship = freshShip(.wasp, s)
            s.commander.ship.weapons = [.photonDisruptor, .militaryLaser]
            s.quests.princess = QuestStatus.Princess.flyQonos
            opp.hull = 2
            for i in opp.shields.indices { opp.shields[i].charge = 0 }
        }
        let (r, e) = try #require(m4Scan(base, { $0.perform(.encounter(.attack)) }, until: { r, _ in r.events.contains(.opponentDisabled(.scorpion)) }))
        #expect(r.events.contains(.opponentDisabled(.scorpion)))                                              // EncounterDisabledOpponent
        #expect(e.state.quests.princess == QuestStatus.Princess.rescued)                                      // the rescue part
    }

    @Test("ALR-058 ALR-059 ALR-125 pirates: refused with the Princess, take the sculpture, or find hidden compartments")
    func pirateSurrender() {
        var princess = m4EncounterEngine(.pirateAttack) { s, _ in s.commander.ship = freshShip(.beetle, s); s.hireCrew(CrewID.princess) }
        #expect(princess.perform(.encounter(.surrender)).rejection == .surrenderPrincess)                     // EncounterPiratesSurrenderPrincess
        var sculpture = m4EncounterEngine(.pirateAttack) { s, _ in s.quests.sculpture = 1 }
        #expect(sculpture.perform(.encounter(.surrender)).events.first == .sculptureTaken)                    // EncounterPiratesTakeSculpture
        var hidden = m4EncounterEngine(.pirateAttack) { s, _ in
            s.commander.ship = freshShip(.beetle, s)
            s.commander.ship.gadgets = [.hiddenCargoBays]
            s.hireCrew(CrewID.princess)
            s.quests.sculpture = 1
        }
        let r = hidden.perform(.encounter(.surrender))
        #expect(r.events.first == .preciousHidden && hidden.state.princessOnBoard && hidden.state.sculptureOnBoard)  // PreciousHidden
    }

    @Test("ALR-056 ALR-181 ALR-182 after looting: reactor and Wild (no room) are derived; Wild with room joins the pirates")
    func afterLooting() {
        func loot(opponent: ShipType, _ adjust: @escaping (inout GameState) -> Void) -> (StepResult, GameState) {
            var e = m4EncounterEngine(.pirateAttack, opponent: opponent) { s, _ in
                s.commander.ship = freshShip(.beetle, s)
                s.commander.ship.cargo[TradeItemType.water.rawValue] = 5
                adjust(&s)
            }
            return (e.perform(.encounter(.surrender)), e.state)
        }
        let (rr, rs) = loot(opponent: .gnat) { $0.quests.reactor = 3 }
        #expect(has(rr.events) { if case .looted = $0 { true } else { false } } && rs.reactorOnBoard)       // EncounterPiratesExamineReactor
        let (cr, cs) = loot(opponent: .gnat) { s in s.hireCrew(CrewID.wild); s.quests.wild = QuestStatus.Wild.started }
        #expect(!cr.events.contains(.wildJoinedPirates) && cs.wildOnBoard && cs.quests.wild == QuestStatus.Wild.started)  // WildChatsPirates
        let (gr, gs) = loot(opponent: .wasp) { s in s.hireCrew(CrewID.wild); s.quests.wild = QuestStatus.Wild.started }
        #expect(gr.events.contains(.wildJoinedPirates) && gs.quests.wild == QuestStatus.Wild.notStarted)      // WildGoesPirates
    }
}

@Suite("Alert mappings, engine side (ALR {M4}): arrival, day advance, arrest and escape pod")
struct AlertMappingM4ArrivalTests {
    func arriving(_ adjust: (inout GameState) -> Void) -> GameState {
        var s = makeEngine().state
        s.warpSystem = plainTarget(s) ?? 1
        adjust(&s)
        return s
    }

    @Test("ALR-130 ALR-131 ALR-132 ALR-133 ALR-128 reactor warnings at 2, 16, 18 and the meltdown at 20")
    func reactor() {
        for (status, expected) in [(2, GameEvent.reactorWarning(status: 2)), (16, .reactorWarning(status: 16)), (18, .reactorWarning(status: 18))] {
            var s = arriving { $0.quests.reactor = status }
            #expect(s.arrival().first == expected)                                                            // ReactorWarningFuel/FuelGone/Temp
        }
        var quiet = arriving { $0.quests.reactor = 5 }
        #expect(!has(quiet.arrival()) { if case .reactorWarning = $0 { true } else { false } })
        var melt = arriving { $0.quests.reactor = QuestStatus.Reactor.date }
        let events = melt.arrival()
        #expect(events.first == .reactorMeltdown && melt.phase == .gameOver(.killed))                         // ReactorMeltdown / ReactorDestroyed
    }

    @Test("ALR-034 ALR-151 ALR-165 Og egg, the experiment and the fabric rip")
    func arrivalAndDays() throws {
        var og = makeEngine { s in
            s.commander.ship = freshShip(.wasp, s)
            s.commander.currentSystem = SystemID.og
            s.commander.ship.cargo = Array(repeating: 1, count: 10)
        }.state
        #expect(og.arrivalEasterEgg() == [.easterEgg] && og.commander.ship.shields.map(\.type) == [.lightning])  // Egg
        var days = makeEngine { $0.quests.experiment = QuestStatus.Experiment.date }.state
        #expect(days.incDays(1).contains(.experimentPerformed))                                               // SpecialExperimentPerformed
        var rip = makeEngine { s in s.quests.experiment = QuestStatus.Experiment.performed; s.quests.fabricRipProbability = 25 }
        let t = try #require(plainTarget(rip.state))
        _ = rip.perform(.selectTarget(t))
        let r = rip.perform(.warp)
        let event = r.events.first { if case .fabricRip = $0 { true } else { false } }
        guard case let .fabricRip(dest)? = event else { Issue.record("no rip"); return }                      // SpecialTimespaceFabricRip
        #expect(rip.state.warpSystem == dest)
    }

    @Test("ALR-169 ALR-170 ALR-172 ALR-174 ALR-177 tribble arrival notices")
    func tribbles() throws {
        var all = arriving { s in s.commander.ship.tribbles = 10; s.quests.reactor = 5 }
        #expect(all.arrivalTribbles().first == .tribblesDied(.allFromReactor))                               // TribblesAllDied
        var half = arriving { s in s.commander.ship.tribbles = 30; s.quests.reactor = 5 }
        #expect(half.arrivalTribbles().first == .tribblesDied(.halfFromReactor))                             // TribblesHalfDied
        var narc = arriving { s in s.commander.ship.tribbles = 300; s.commander.ship.cargo[TradeItemType.narcotics.rawValue] = 1 }
        #expect(narc.arrivalTribbles().first == .tribblesDied(.narcotics(converted: 1)))                     // TribblesMostDied
        var food = arriving { s in s.commander.ship.tribbles = 5; s.commander.ship.cargo[TradeItemType.food.rawValue] = 2 }
        try #require(m4ForceDraws(&food, [(2, 0), (205, 0)]))
        // TribblesAteFood, TribblesInspector
        #expect(food.arrivalTribbles() == [.tribblesAteFood(eaten: 2), .tribbleInspectorWarning(count: 206), .tribblesChanged(from: 5, to: 206)])
    }

    @Test("ALR-179 tribbles only lower the trade-in shown in the ship quote; the purchase is not blocked")
    func tradeIn() {
        let base = makeEngine { s in s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech; s.commander.cash = 100_000 }
        var infested = base
        infested.state.commander.ship.tribbles = 1
        #expect(infested.state.shipQuote(.firefly).netPrice > base.state.shipQuote(.firefly).netPrice)
        #expect(infested.perform(.buyShip(.firefly, transfers: []), acknowledging: [.buyShip]).rejection == nil)
    }

    @Test("ALR-004 ALR-115 ALR-126 ALR-127 ALR-135 ALR-176 ALR-180 arrest losses are state changes beside arrested")
    func arrestLosses() {
        var s = makeEngine { s in
            s.commander.cash = 0
            s.commander.ship = freshShip(.beetle, s)
            s.hireCrew(CrewID.jarek)
            s.hireCrew(CrewID.wild)
            s.quests.jarek = 5
            s.quests.wild = 5
            s.quests.japori = QuestStatus.Japori.inTransit
            s.quests.reactor = 3
            s.quests.sculpture = 1
            s.commander.ship.tribbles = 50
        }.state
        let events = s.arrested()
        #expect(events.filter { if case .arrested = $0 { false } else { true } }.allSatisfy {
            if case .passengerConcerned = $0 { true } else if case .passengerImpatient = $0 { true } else { false }
        })
        #expect(events.contains { if case .arrested(_, _, true) = $0 { true } else { false } })
        #expect(s.quests.japori == QuestStatus.Japori.done)                                                  // AntidoteTaken
        #expect(s.quests.jarek <= 1)                                                                          // JarekTakenHome
        #expect(s.quests.reactor == QuestStatus.Reactor.notStarted)                                          // ReactorConfiscated
        #expect(s.quests.sculpture == QuestStatus.Sculpture.notStarted)                                      // SculptureConfiscated
        #expect(s.commander.ship.tribbles == 0)                                                              // TribblesRemoved
        #expect(s.quests.wild <= 1 && s.newsEvents.contains(.wildArrested))                                  // WildArrested
        var p = makeEngine { s in
            s.commander.cash = 100_000
            s.commander.ship = freshShip(.beetle, s)
            s.hireCrew(CrewID.princess)
            s.quests.princess = 6
        }.state
        _ = p.arrested()
        #expect(p.quests.princess <= 1)                                                                       // PrincessTakenHome
    }

    @Test("ALR-003 ALR-011 ALR-115 ALR-126 ALR-128 ALR-136 ALR-173 ALR-180 escape-pod losses are state changes beside escapePodUsed")
    func podLosses() {
        var s = makeEngine { s in
            s.commander.ship = freshShip(.wasp, s)
            s.commander.ship.escapePod = true
            s.hireCrew(CrewID.jarek)
            s.hireCrew(CrewID.princess)
            s.quests.jarek = 5
            s.quests.princess = 6
            s.quests.japori = QuestStatus.Japori.inTransit
            s.quests.artifact = QuestStatus.Artifact.onBoard
            s.quests.reactor = 3
            s.quests.sculpture = 1
            s.commander.ship.tribbles = 50
        }.state
        let events = s.escapeWithPod()
        #expect(events.first == .escapePodUsed(insurancePayout: 0))
        #expect(s.quests.japori == QuestStatus.Japori.notStarted)                                            // AntidoteDestroyed
        #expect(s.quests.artifact == QuestStatus.Artifact.done)                                              // ArtifactLost
        #expect(s.quests.jarek == 1 && !s.jarekOnBoard)                                                       // JarekTakenHome
        #expect(s.quests.princess == 1 && !s.princessOnBoard)                                                 // PrincessTakenHome
        #expect(s.quests.reactor == QuestStatus.Reactor.done)                                                 // ReactorDestroyed
        #expect(s.sculptureOnBoard)                                                                            // SculptureSaved
        #expect(s.commander.ship.tribbles == 0)                                                               // TribblesKilled
        var w = makeEngine { s in s.commander.ship = freshShip(.beetle, s); s.hireCrew(CrewID.wild); s.quests.wild = 5 }.state
        _ = w.escapeWithPod()
        #expect(w.quests.wild == 1 && !w.wildOnBoard && w.newsEvents.contains(.wildArrested))                // WildArrested
    }

    @Test("ALR-156 ALR-157 ALR-158 ALR-159 ALR-160 ALR-161 passenger concerned and impatient notices")
    func impatience() {
        let cases = [(CrewID.jarek, 5, 10), (CrewID.princess, 9, 13), (CrewID.wild, 5, 10)]
        for (id, concerned, impatient) in cases {
            var s = makeEngine { s in s.commander.ship = freshShip(.beetle, s); s.hireCrew(id) }.state
            func set(_ v: Int) {
                switch id {
                case CrewID.jarek: s.quests.jarek = v
                case CrewID.princess: s.quests.princess = v
                default: s.quests.wild = v
                }
            }
            set(concerned)
            #expect(s.incDays(1) == [.passengerConcerned(crewID: id)])
            set(impatient)
            #expect(s.incDays(1) == [.passengerImpatient(crewID: id)] && s.mercenaries[id].skills == [0, 0, 0, 0])
            set(concerned + 1)
            #expect(s.incDays(1).isEmpty)
        }
    }
}
