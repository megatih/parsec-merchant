// SPDX-License-Identifier: GPL-2.0-or-later
// Cross-area {M5} bullets (CRW, QST passengers, POL, BNK, SHP, GAL, SCORE, RUL) that combine several rule groups:
// the Palm passenger model, ship and equipment tables, arrest and pod variants, scoring and integer arithmetic.
import Testing
@testable import ParsecEngine

/// Puts Wild aboard as each ruleset models him: crew slot 1 (C#) or status only (Palm passenger, CRW-044).
func boardWild(_ s: inout GameState) {
    s.commander.ship.crew = [CrewID.commander, s.ruleset.flags.economy.passengersAsCrew ? CrewID.wild : nil]
    s.quests.wild = QuestStatus.Wild.started
}

/// Leaves exactly the mercenaries `ids` for hire in the current system.
private func onlyForHire(_ s: inout GameState, _ ids: [Int]) {
    for m in 1..<s.mercenaries.count where s.mercenaries[m].systemID == s.commander.currentSystem {
        s.mercenaries[m].systemID = nil
    }
    for id in ids { s.mercenaries[id].systemID = s.commander.currentSystem }
}

// MARK: Palm passengers

@Suite("Cross-area rulesets: Palm passengers (CRW-044/045, QST-JAREK-008/018, QST-WILD-009/015)")
struct PassengerModelSpecTests {
    @Test("CRW-044 QST-JAREK-008 Palm Jarek holds no crew slot and no skills, takes a quarter, and needs the last slot free")
    func palmJarek() {
        for id in [RulesetID.palm122, .windows201] {
            var e = questEngine(id, .jarek) { s in
                s.commander.ship = QuestTrip.ship(.bumblebee, s) // 2 quarters
                s.mercenaries[CrewID.commander].skills = [3, 3, 3, 3]
                onlyForHire(&s, [5])
            }
            let trader = e.state.skill(.trader)
            #expect(e.perform(.specialEvent, acknowledging: QuestTrip.yes).rejection == nil)
            #expect(e.state.jarekOnBoard && e.state.quests.jarek == QuestStatus.Jarek.started)
            if id == .palm122 {
                #expect(e.state.commander.ship.crew == [CrewID.commander, nil] && e.state.passengersOutsideCrew == 1)
                #expect(e.state.skill(.trader) == trader)
            } else {
                #expect(e.state.commander.ship.crew == [CrewID.commander, CrewID.jarek])
                #expect(e.state.skill(.trader) > trader) // Jarek's trader 10 counts in C#
            }
            // One quarter is left: the commander's. Palm refuses through AvailableQuarters, C# through the full array.
            #expect(e.perform(.hire(crewID: 5)).rejection == .noFreeQuarters)
        }
        // With a mercenary in the last slot (Crew[CrewQuarters − 1] ≥ 0) Jarek is refused and nothing changes.
        var full = questEngine(.palm122, .jarek) { s in
            s.commander.ship = QuestTrip.ship(.bumblebee, s)
            s.commander.ship.crew[1] = 5
        }
        #expect(full.perform(.specialEvent, acknowledging: QuestTrip.yes).rejection == .noFreeQuarters)
        #expect(full.state.quests.jarek == QuestStatus.Jarek.notStarted && !full.state.jarekOnBoard)
        // A Palm ship trade with a passenger aboard needs at least 2 quarters (SHP-037).
        var trade = questEngine(.palm122) { s in
            s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech
            s.hireCrew(CrewID.jarek)
        }
        #expect(trade.perform(.buyShip(.firefly, transfers: []), acknowledging: QuestTrip.yes).rejection == .passengersNeedQuarters)
    }

    @Test("CRW-045 Palm quirk: Wild boards a 2-quarter ship while Jarek is aboard (3 people, 2 quarters); C# refuses")
    func threeInTwo() {
        func engine(_ id: RulesetID) -> GameEngine {
            questEngine(id, .wild) { s in
                s.commander.ship = QuestTrip.ship(.bumblebee, s, weapons: [.beamLaser])
                s.commander.policeRecordScore = -10
                s.hireCrew(CrewID.jarek)
                s.quests.jarek = QuestStatus.Jarek.started
            }
        }
        var p = engine(.palm122)
        #expect(p.state.specialEventAvailable == .wild)
        #expect(p.perform(.specialEvent, acknowledging: QuestTrip.yes).rejection == nil)
        let ship = p.state.commander.ship
        let quarters = ship.spec(p.ruleset).crewQuarters
        #expect(p.state.jarekOnBoard && p.state.wildOnBoard && ship.crew == [CrewID.commander, nil])
        #expect(ship.crewCount + p.state.passengersOutsideCrew == 3 && quarters == 2)
        // The crew array (what the fuzz invariant checks) still fits the quarters.
        #expect(ship.crewCount <= quarters)
        var w = engine(.windows201)
        #expect(w.perform(.specialEvent, acknowledging: QuestTrip.yes).rejection == .noFreeQuarters)
        #expect(!w.state.wildOnBoard)
    }

    @Test("QST-WILD-009 Palm Wild is a passenger: status 1, no crew slot or skills, one fewer available quarter")
    func palmWild() {
        for id in [RulesetID.palm122, .windows201] {
            var e = questEngine(id, .wild) { s in
                s.commander.ship = QuestTrip.ship(.beetle, s, weapons: [.beamLaser]) // 3 quarters
                s.commander.policeRecordScore = -10
                s.mercenaries[CrewID.commander].skills = [3, 3, 3, 3]
                onlyForHire(&s, [5, 6])
            }
            let fighter = e.state.skill(.fighter)
            #expect(e.perform(.specialEvent, acknowledging: QuestTrip.yes).rejection == nil)
            #expect(e.state.quests.wild == QuestStatus.Wild.started && e.state.wildOnBoard)
            let palm = id == .palm122
            #expect(e.state.commander.ship.hasCrew(CrewID.wild) == !palm)
            #expect((e.state.skill(.fighter) == fighter) == palm)
            // Three quarters, Wild takes one: one mercenary can be hired, the second cannot.
            #expect(e.perform(.hire(crewID: 5)).rejection == nil)
            #expect(e.perform(.hire(crewID: 6)).rejection == .noFreeQuarters)
        }
    }

    @Test("QST-JAREK-018 Palm arrest and pod set Jarek 1 → 0 and he always leaves; C# keeps him with fewer than 2 mercenaries")
    func jarekLeaves() {
        func state(_ id: RulesetID) -> GameState {
            makeEngine(id) { s in
                s.commander.ship = freshShip(.beetle, s)
                s.hireCrew(CrewID.jarek)
                s.quests.jarek = QuestStatus.Jarek.started
                s.commander.cash = 100_000
                s.commander.policeRecordScore = -40
                s.commander.ship.escapePod = true
                s.warpSystem = plainTarget(s) ?? 1
            }.state
        }
        var palm = state(.palm122), palmPod = state(.palm122)
        _ = palm.arrested()
        _ = palmPod.escapeWithPod()
        for s in [palm, palmPod] {
            #expect(s.quests.jarek == QuestStatus.Jarek.notStarted && !s.jarekOnBoard)
        }
        // C# arrest (POL-095): with no mercenary aboard Jarek stays in the crew, and IncDays(term) moves his status to 1.
        var win = state(.windows201)
        _ = win.arrested()
        #expect(win.commander.ship.hasCrew(CrewID.jarek) && win.quests.jarek == 1)
    }

    @Test("QST-WILD-015 Palm Wild leaving is real: status 0 removes the passenger (warp without a laser, raid)")
    func wildLeaves() {
        var e = questEngine(.palm122) { s in
            s.commander.ship = QuestTrip.ship(.bumblebee, s)
            s.hireCrew(CrewID.wild)
        }
        #expect(e.state.wildWillLeave)
        let events = QuestTrip.hop(&e, ack: QuestTrip.yes)
        #expect(events.contains(.wildLeftShip))
        #expect(e.state.quests.wild == QuestStatus.Wild.notStarted && !e.state.wildOnBoard)
        #expect(!e.state.commander.ship.hasCrew(CrewID.wild))
        // A pirate raid by a ship with more than one quarter takes him (POL-085): he is gone, not just status 0.
        var raid = Pol.engine(.pirateAttack, .palm122, opponent: .wasp) { boardWild(&$0) }
        let r = raid.perform(.encounter(.surrender))
        #expect(r.events.contains(.wildJoinedPirates) && !raid.state.wildOnBoard)
        #expect(raid.state.quests.wild == QuestStatus.Wild.notStarted)
    }
}

// MARK: Crew roster, ships and equipment

@Suite("Cross-area rulesets: Palm roster, ship and equipment tables (CRW-026, SHP-003/006/008)")
struct PalmTablesSpecTests {
    @Test("CRW-026 Palm roster: ids 1…31 draw systems (distinct, never Kravat); Zeethibal (30) and the scratch slot (31) are never for hire")
    func palmRoster() {
        #expect(Ruleset.palm122.content.randomMercenaryIDs == Array(1...31))
        #expect(CrewID.zeethibal == 30 && CrewID.opponent == 31 && GameNames.crew[CrewID.zeethibal] == "Zeethibal")
        #expect(Ruleset.palm122.content.unplacedMercenaryIDs == [CrewID.zeethibal, CrewID.opponent])
        for seed in UInt64(1)...5 {
            var s = makeEngine(.palm122, seed: seed).state
            let systems = (1...29).compactMap { s.mercenaries[$0].systemID }
            #expect(systems.count == 29 && Set(systems).count == 29 && !systems.contains(SystemID.kravat), "seed \(seed)")
            #expect(s.mercenaries[CrewID.zeethibal].systemID == nil && s.mercenaries[CrewID.opponent].systemID == nil)
            for sys in s.galaxy.systems.indices {
                s.commander.currentSystem = sys
                #expect(s.mercenariesForHire.allSatisfy { (1...29).contains($0) })
            }
        }
    }

    @Test("SHP-003 Palm ships: rows 0…14 from Shiptype[] with CostOfFuel/RepairCosts unswapped; rows 15–16 unreachable placeholders")
    func palmShips() {
        let p = Ruleset.palm122.tables.ships
        #expect(p.count == 17 && p.enumerated().allSatisfy { $0.element.type.rawValue == $0.offset })
        // Global.c Shiptype[]: Gnat fuel 2 / repair 1, Wasp fuel 20 / repair 5, Termite hull 200, price 225000.
        #expect(p[ShipType.gnat.rawValue].fuelCost == 2 && p[ShipType.gnat.rawValue].repairCost == 1)
        #expect(p[ShipType.wasp.rawValue].fuelCost == 20 && p[ShipType.wasp.rawValue].repairCost == 5)
        #expect(p[ShipType.termite.rawValue].hullStrength == 200 && p[ShipType.termite.rawValue].price == 225_000)
        // The columns are read as stored (no RUL-117 swap in Palm).
        let s = makeEngine(.palm122).state
        let gnat = Ship(type: .gnat, spec: s.ruleset.tables.ship(.gnat)).spec(s.ruleset)
        #expect(!Ruleset.palm122.flags.economy.swapFuelAndRepairColumns && gnat.fuelCost == 2 && gnat.repairCost == 1)
        for t in [ShipType.custom, .scorpion] {
            #expect(p[t.rawValue].occurrence == 0 && p[t.rawValue].minTechLevel == .unavailable)
        }
        #expect(!Ruleset.palm122.content.hasShipyards && !Ruleset.palm122.content.hasPrincessQuest)
    }

    @Test("SHP-006 Palm equipment: 4 weapons (no disruptors), 3 shields, 6 gadgets (no hidden bays) with the Global.c values")
    func palmEquipment() {
        let t = Ruleset.palm122.tables
        #expect(t.weapons.map(\.type) == [.pulseLaser, .beamLaser, .militaryLaser, .morgansLaser])
        #expect(t.weapons.map(\.power) == [15, 25, 35, 85] && t.weapons.map(\.price) == [2_000, 12_500, 35_000, 50_000])
        #expect(t.weapons.map(\.minTechLevel) == [.industrial, .postIndustrial, .hiTech, .unavailable])
        #expect(t.shields.map(\.type) == [.energy, .reflective, .lightning] && t.shields.map(\.price) == [5_000, 20_000, 45_000])
        #expect(t.shields.map(\.power) == [100, 200, 350])
        #expect(t.gadgets.map(\.type) == [.extraCargoBays, .autoRepairSystem, .navigatingSystem, .targetingSystem,
                                          .cloakingDevice, .fuelCompactor])
        #expect(t.gadgets.map(\.price) == [2_500, 7_500, 15_000, 25_000, 100_000, 30_000])
        #expect(t.gadgets.map(\.minTechLevel) == [.earlyIndustrial, .industrial, .postIndustrial, .postIndustrial, .hiTech, .unavailable])
    }

    @Test("SHP-008 Palm sells weapons 0…2, shields 0…1 and gadgets 0…4; Morgan's laser, Lightning and the compactor are never sold")
    func palmSold() {
        var e = makeEngine(.palm122) { s in
            s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech
            s.commander.cash = 1_000_000
            s.commander.ship = QuestTrip.ship(.wasp, s)
        }
        let s = e.state
        #expect([WeaponType.pulseLaser, .beamLaser, .militaryLaser].allSatisfy { s.equipmentBuyPrice(weapon: $0) > 0 })
        #expect(s.equipmentBuyPrice(weapon: .morgansLaser) == 0)
        #expect(s.equipmentBuyPrice(shield: .energy) > 0 && s.equipmentBuyPrice(shield: .reflective) > 0)
        #expect(s.equipmentBuyPrice(shield: .lightning) == 0)
        let sold: [GadgetType] = [.extraCargoBays, .autoRepairSystem, .navigatingSystem, .targetingSystem, .cloakingDevice]
        #expect(sold.allSatisfy { s.equipmentBuyPrice(gadget: $0) > 0 } && s.equipmentBuyPrice(gadget: .fuelCompactor) == 0)
        #expect(e.perform(.buyWeapon(.morgansLaser), acknowledging: [.buyEquipment]).rejection == .notSoldHere)
        #expect(e.perform(.buyShield(.lightning), acknowledging: [.buyEquipment]).rejection == .notSoldHere)
        #expect(e.perform(.buyGadget(.fuelCompactor), acknowledging: [.buyEquipment]).rejection == .notSoldHere)
        #expect(e.perform(.buyWeapon(.militaryLaser), acknowledging: [.buyEquipment]).rejection == nil)
    }
}

// MARK: Galaxy

@Suite("Cross-area rulesets: Palm galaxy markets (GAL-027, GAL-067)")
struct PalmGalaxyMarketSpecTests {
    @Test("GAL-027 Palm starting quantity of item i uses system #i's size; a system not yet generated counts as size 0")
    func notYetGenerated() {
        let base = makeEngine(.palm122).state
        var sys = base.currentSystem
        sys.specialResource = .nothing
        sys.pressure = .none
        sys.size = .huge
        sys.techLevel = .hiTech
        let generated = [SystemSize](repeating: .huge, count: 3) // only systems 0…2 exist yet
        var r1 = base.rng, r2 = base.rng, r3 = base.rng
        let partial = Pricing.initialQuantities(for: sys, difficulty: .normal, ruleset: .palm122, systemSizes: generated, rng: &r1)
        let zeroTail = Pricing.initialQuantities(for: sys, difficulty: .normal, ruleset: .palm122,
                                                 systemSizes: generated + Array(repeating: .tiny, count: 7), rng: &r2)
        let allHuge = Pricing.initialQuantities(for: sys, difficulty: .normal, ruleset: .palm122,
                                                systemSizes: Array(repeating: .huge, count: 10), rng: &r3)
        #expect(SystemSize.tiny.rawValue == 0)
        #expect(partial == zeroTail && r1 == r2)
        #expect(Array(partial.prefix(3)) == Array(allHuge.prefix(3)) && partial != allHuge)
    }

    @Test("GAL-067 Palm arrival: ShuffleStatus over all systems first (r(100) < 15: busy → 0, calm → 1 + r(7)), then the quantity pass")
    func shuffleStatusFirst() {
        var s = makeEngine(.palm122, seed: 11).state
        for i in s.galaxy.systems.indices { s.galaxy.systems[i].countDown = 0 } // the quantity pass draws nothing
        var rng = s.rng
        var expected = s.galaxy.systems.map(\.pressure)
        for i in expected.indices where rng.next(below: 100) < 15 {
            expected[i] = expected[i] == .none ? SystemPressure(rawValue: 1 + rng.next(below: 7)) ?? .none : .none
        }
        s.updatePressuresAndQuantities(arrival: s.commander.currentSystem)
        #expect(s.galaxy.systems.map(\.pressure) == expected && s.rng == rng)
        // With every market counting down, the statuses are the same: no quantity draw comes between two status draws.
        var busy = makeEngine(.palm122, seed: 11).state
        for i in busy.galaxy.systems.indices { busy.galaxy.systems[i].countDown = 3 }
        busy.updatePressuresAndQuantities(arrival: busy.commander.currentSystem)
        #expect(busy.galaxy.systems.map(\.pressure) == expected && busy.rng != rng)
    }
}

// MARK: Arrest, pod and bank

@Suite("Cross-area rulesets: arrest and escape pod (BNK-026, POL-100, POL-108)")
struct ArrestPodCrossSpecTests {
    @Test("BNK-026 Palm jail: Arrival() and IncDays(term) first, then the fine, record −5, debt paid from cash, PayInterest term times")
    func palmJailBank() {
        var s = makeEngine(.palm122) { s in
            s.commander.policeRecordScore = -30
            s.commander.cash = 100_000
            s.commander.debt = 99_000
            s.warpSystem = plainTarget(s) ?? 1
        }.state
        let fine = s.arrestFine, term = s.arrestTerm, days = s.commander.days
        #expect(term == 30 && fine > 0 && fine < 100_000)
        _ = s.arrested()
        var debt = 99_000 - (100_000 - fine)
        for _ in 0..<term { debt += max(1, Int(Double(debt) * 0.1)) } // cash is 0, so every interest adds to the debt
        #expect(s.commander.currentSystem == s.warpSystem && s.commander.days == days + term)
        #expect(s.commander.policeRecordScore == -5 && s.commander.cash == 0 && s.commander.debt == debt)
    }

    @Test("POL-100 Modern: mercenaries lost to an arrest relocate like fired ones, from the destination; Windows leaves them")
    func arrestRelocates() {
        for id in [RulesetID.modern, .windows201] {
            var s = makeEngine(id) { s in
                s.commander.ship = freshShip(.beetle, s)
                s.commander.ship.crew[1] = 7
                s.commander.ship.crew[2] = 8
                s.mercenaries[7].systemID = 1
                s.mercenaries[8].systemID = 2
                s.commander.cash = 100_000
                s.commander.policeRecordScore = -40
                s.warpSystem = (s.commander.currentSystem + 60) % s.galaxy.systems.count
            }.state
            var reference = s
            reference.relocateMercenary(7, near: reference.warpSystem)
            reference.relocateMercenary(8, near: reference.warpSystem)
            _ = s.arrested()
            #expect(!s.commander.ship.hasCrew(7) && !s.commander.ship.hasCrew(8))
            if id == .modern {
                #expect(s.mercenaries[7].systemID == reference.mercenaries[7].systemID)
                #expect(s.mercenaries[8].systemID == reference.mercenaries[8].systemID)
            } else {
                #expect(s.mercenaries[7].systemID == 1 && s.mercenaries[8].systemID == 2)
            }
        }
    }

    @Test("POL-108 Modern escape pod: every cost basis reset with the Flea (RUL-101) and lost mercenaries relocate (RUL-116)")
    func podModern() {
        for id in [RulesetID.modern, .windows201] {
            var s = makeEngine(id) { s in
                s.commander.ship = freshShip(.beetle, s)
                s.commander.ship.crew[1] = 7
                s.mercenaries[7].systemID = 1
                s.commander.ship.cargo[2] = 4
                s.commander.priceCargo[2] = 400
                s.commander.ship.escapePod = true
                s.warpSystem = (s.commander.currentSystem + 60) % s.galaxy.systems.count
            }.state
            _ = s.escapeWithPod()
            #expect(s.commander.ship.type == .flea && !s.commander.ship.hasCrew(7))
            if id == .modern {
                #expect(s.commander.priceCargo.allSatisfy { $0 == 0 })
                let to = s.mercenaries[7].systemID ?? -1
                #expect(s.galaxy.systems.indices.contains(to))
                if s.galaxy.systems.indices.contains(to) {
                    #expect(GalaxyGenerator.distance(s.galaxy.systems[to], s.galaxy.systems[s.warpSystem], rule: s.ruleset.flags.distance) < 20)
                }
            } else {
                #expect(s.commander.priceCargo[2] == 400 && s.mercenaries[7].systemID == 1)
            }
        }
    }
}

// MARK: Score and arithmetic

@Suite("Cross-area rulesets: score, newspaper strings and integer arithmetic (SCORE-010/022, RUL-018, RUL-121)")
struct ScoreArithmeticCrossSpecTests {
    @Test("SCORE-010 Palm ToSpend is never negative, so the moon claim is never refused for funds; Windows refuses below 0")
    func palmMoonClaim() {
        for id in [RulesetID.palm122, .windows201] {
            var e = makeEngine(id) { s in
                s.commander.currentSystem = SystemID.utopia
                s.galaxy.systems[SystemID.utopia].specialEvent = .moonRetirement
                s.quests.moon = QuestStatus.Moon.bought
                s.commander.ship = freshShip(.beetle, s)
                s.commander.ship.crew[1] = 1
                s.commander.cash = 0
                s.commander.debt = 0
                s.options.reserveMoney = true
            }
            let r = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
            if id == .palm122 {
                #expect(e.state.cashToSpend >= 0 && r.rejection == nil && e.state.phase == .gameOver(.boughtMoon))
            } else {
                #expect(r.rejection == .insufficientFunds && e.state.phase == .docked)
            }
        }
    }

    @Test("SCORE-022 Modern and Palm score with the trade-in worth (repairs, cost basis, moon); a killed hull counts at 0")
    func tradeInWorthScore() {
        for id in allRulesets {
            let s = makeEngine(id) { s in
                s.commander.cash = 50_000
                s.commander.debt = 1_000
            }.state
            var damaged = s
            damaged.commander.ship.hull = 0
            var cargo = s
            cargo.commander.ship.cargo[0] = 2
            cargo.commander.priceCargo[0] = 1_000
            if id == .windows201 {
                #expect(damaged.worth == s.worth && cargo.worth == s.worth)
                continue
            }
            #expect(s.worth == s.shipWorth(forInsurance: false) + 50_000 - 1_000)
            #expect(damaged.worth < s.worth && cargo.worth == s.worth + 1_000)
            // The killed score reads the final, wrecked ship: it equals the score of any state with the same worth.
            var same = s
            same.commander.cash -= s.worth - damaged.worth
            #expect(same.worth == damaged.worth && same.score(for: .killed) == damaged.score(for: .killed))
            #expect(damaged.score(for: .killed) <= s.score(for: .killed))
            var moon = s
            moon.quests.moon = QuestStatus.Moon.bought
            #expect(moon.worth == s.worth + QuestStatus.moonCost)
        }
    }

    @Test("RUL-018 every ruleset composes papers from the shared tables: 3 mastheads and 4 canned stories per government")
    func newspaperTables() {
        #expect(NewsTables.mastheadsPerGovernment == 3 && NewsTables.cannedPerGovernment == 4)
        for id in allRulesets {
            for seed in UInt64(1)...6 {
                var s = makeEngine(id, seed: seed).state
                s.commander.days = Int(seed) * 7
                let paper = s.newspaper
                #expect(paper.government == s.currentSystem.politics)
                #expect((0..<NewsTables.mastheadsPerGovernment).contains(paper.mastheadIndex))
                for case let .canned(government, index) in paper.headlines {
                    #expect(government == paper.government && (0..<NewsTables.cannedPerGovernment).contains(index))
                }
            }
        }
        // Palm prints its fixed event headlines in its own order; C# in insertion order (NEWS-041).
        #expect(Ruleset.palm122.flags.travel.newsEventOrdering == .palmFixed)
        #expect(Ruleset.modern.flags.travel.newsEventOrdering == .insertion && Ruleset.windows201.flags.travel.newsEventOrdering == .insertion)
    }

    @Test("RUL-121 integer money arithmetic truncates as the source in every ruleset (interest, ×100/90, Wild's ×1.05 fine)")
    func integerArithmetic() {
        for id in allRulesets {
            let s = makeEngine(id).state
            for (debt, interest) in [(5, 1), (19, 1), (25, 2), (1_239, 123)] {
                var t = s
                t.commander.debt = debt
                t.commander.cash = 10_000
                t.payInterest()
                #expect(10_000 - t.commander.cash == interest, "\(id) debt \(debt)")
            }
            var r = s
            r.sellPrices = [91, 100, 7, 0, 899, 1_000, 50, 45, 3_001, 10]
            r.recalculateSellPrices()
            #expect(r.sellPrices == [101, 111, 7, 0, 998, 1_111, 55, 50, 3_334, 11])
            var f = s
            f.commander.policeRecordScore = -30
            let base = f.arrestFine
            boardWild(&f)
            #expect(base % 500 == 0 && f.arrestFine == Int(Double(base) * 1.05))
        }
    }
}
