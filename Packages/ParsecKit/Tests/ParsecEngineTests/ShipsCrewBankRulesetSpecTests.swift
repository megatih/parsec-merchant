// SPDX-License-Identifier: GPL-2.0-or-later
// M5 ruleset rows for ships, equipment, skills, crew and the bank (RUL-044…061, 116; SHP/CRW/BNK {M5}).
import Testing
@testable import ParsecEngine

/// An encounter-phase engine (transit resumes afterwards) for very-rare and pod scenarios.
private func encounterEngine(_ id: RulesetID, _ type: EncounterType, difficulty: Difficulty = .normal,
                             _ adjust: (inout GameState) -> Void = { _ in }) -> GameEngine {
    var e = makeEngine(id, difficulty: difficulty)
    e.state.encounterTransit = TransitState(destination: e.state.warpSystem, clicksRemaining: 1, viaWormhole: false)
    e.state.phase = .encounter(EncounterState(type: type, opponent: Ship(type: .gnat, spec: e.ruleset.tables.ship(.gnat)),
                                              clicks: 1))
    adjust(&e.state)
    return e
}

@Suite("Ships and equipment rulesets (RUL-047, 052…056, SHP {M5})")
struct ShipsRulesetSpecTests {
    @Test("RUL-047 SHP-017 fuel compactor: tanks + 3 in Modern and Windows; Palm tanks = 18 (Flea 20 → 18)")
    func compactor() {
        for id in allRulesets {
            let s = makeEngine(id).state
            var flea = freshShip(.flea, s)
            flea.gadgets = [.fuelCompactor]
            var gnat = freshShip(.gnat, s)
            gnat.gadgets = [.fuelCompactor]
            #expect(flea.fuelTanks(s.ruleset) == (id == .palm122 ? 18 : 23))
            #expect(gnat.fuelTanks(s.ruleset) == (id == .palm122 ? 18 : 17))
        }
    }

    @Test("RUL-056 SHP-029 SHP-030 trade-in fuel term: (tanks − fuel) × cost; Palm (base tanks − min(fuel, tanks)) × cost plus cargo basis")
    func tradeInFuelTerm() {
        for id in allRulesets {
            var s = makeEngine(id).state
            var gnat = freshShip(.gnat, s)
            gnat.gadgets = [.fuelCompactor]
            gnat.fuel = 18
            let spec = gnat.spec(s.ruleset)
            let equipment = 30_000 * 3 / 4
            let fuelTerm = id == .palm122 ? (14 - 18) * spec.fuelCost : (gnat.fuelTanks(s.ruleset) - 18) * spec.fuelCost
            #expect(s.baseWorth(of: gnat, forInsurance: true) == 10_000 * 3 / 4 - fuelTerm + equipment)
            s.commander.ship = gnat
            s.commander.priceCargo[4] = 321
            #expect(s.shipWorth(forInsurance: false) == s.baseWorth(of: gnat, forInsurance: false) + 321)
        }
    }

    @Test("SHP-019 Palm hull strength is spec + 50 while the Scarab upgrade is held; a ship trade drops it")
    func upgradedHull() {
        var e = makeEngine(.palm122) { s in
            s.commander.ship.hullUpgraded = true
            s.quests.scarab = QuestStatus.Scarab.done
            s.commander.cash = 100_000
            s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech
        }
        #expect(e.state.commander.ship.hullStrength(e.ruleset) == 150)
        _ = e.perform(.buyShip(.firefly, transfers: []), acknowledging: [.buyShip])
        #expect(e.state.commander.ship.hullStrength(e.ruleset) == 100 && e.state.quests.scarab == QuestStatus.Scarab.notStarted)
    }

    @Test("SHP-021 Palm equipment checks: owned gadget, not sold, in debt, ToSpend, slots")
    func equipmentOrder() {
        var e = makeEngine(.palm122) { s in
            s.commander.debt = 500
            s.commander.ship.gadgets = [.navigatingSystem]
            s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech
        }
        #expect(e.perform(.buyGadget(.navigatingSystem)).rejection == .equipmentAlreadyOwned)
        #expect(e.perform(.buyWeapon(.morgansLaser)).rejection == .notSoldHere)
        #expect(e.perform(.buyWeapon(.pulseLaser)).rejection == .inDebt)
        e.state.commander.debt = 0
        e.state.commander.cash = 100_000
        e.state.options.reserveMoney = true
        e.state.commander.debt = 0
        e.state.commander.ship.weapons = [.pulseLaser]
        #expect(e.perform(.buyWeapon(.beamLaser)).rejection == .noFreeSlot)
        e.state.commander.cash = 1_000
        #expect(e.perform(.buyShield(.energy)).rejection == .insufficientFunds)
    }

    @Test("SHP-026 Palm refuses to sell Extra bays when fewer than 5 bays are free")
    func extraBays() {
        var e = makeEngine(.palm122) { s in
            s.commander.ship.gadgets = [.extraCargoBays]
            s.commander.ship.cargo[0] = 16
        }
        #expect(e.perform(.sellGadget(index: 0)).rejection == .extraBaysInUse)
        e.state.commander.ship.cargo[0] = 15
        #expect(e.perform(.sellGadget(index: 0)).decision == .confirm(Confirmation(.sellEquipment, amounts: [2_500 * 3 / 4])))
    }

    @Test("RUL-052 SHP-035 Palm ship price = Price×(100−Trader)/100 − trade-in (0 → 1); Modern and Windows Price − trade-in")
    func shipDiscount() {
        for id in allRulesets {
            var s = makeEngine(id).state
            s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech
            let tradeIn = s.shipWorth(forInsurance: false)
            #expect(tradeIn == 9_000)
            #expect(s.shipQuote(.firefly).netPrice == (id == .palm122 ? 23_750 - 9_000 : 25_000 - 9_000))
            s.commander.priceCargo[0] = 23_750 - 9_000
            #expect(s.shipQuote(.firefly).netPrice == (id == .palm122 ? 1 : 25_000 - 23_750))
        }
    }

    @Test("SHP-037 Palm checks the reactor before the crew count; C# the crew count first")
    func shipTradeOrder() {
        for id in allRulesets {
            var e = makeEngine(id) { s in
                s.commander.ship = freshShip(.beetle, s)
                s.commander.ship.crew[1] = 1
                s.commander.ship.crew[2] = 2
                s.quests.reactor = 3
                s.commander.cash = 200_000
                s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech
            }
            let r = e.perform(.buyShip(.firefly, transfers: []), acknowledging: [.buyShip])
            #expect(r.rejection == (id == .palm122 ? .reactorOnBoard : .notEnoughQuarters))
        }
    }

    @Test("RUL-053 SHP-042 Palm transfers Lightning 30000, Compactor 20000, Morgan's 33333, without the item's own price in the test")
    func transfers() {
        func engine(_ id: RulesetID, cash: Int) -> GameEngine {
            makeEngine(id) { s in
                var ship = freshShip(.wasp, s)
                ship.weapons = [.morgansLaser]
                ship.shields = [ShieldInstance(type: .lightning, charge: 100)]
                ship.gadgets = [.fuelCompactor]
                s.commander.ship = ship
                s.commander.cash = cash
                s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech
            }
        }
        let palm = engine(.palm122, cash: 0).state.shipQuote(.termite)
        #expect(palm.candidates.map(\.item) == [.lightningShield, .fuelCompactor, .morgansLaser])
        #expect(palm.candidates.map(\.price) == [30_000, 20_000, 33_333])
        let windows = engine(.windows201, cash: 0).state.shipQuote(.termite)
        #expect(windows.candidates.map(\.item) == [.morgansLaser, .lightningShield, .fuelCompactor])
        #expect(windows.candidates.map(\.price) == [45_833, 41_250, 27_500])
        // Cash covers the net price exactly: Palm still offers the first item (its own price is not tested) and charges
        // it, then cannot offer the rest; Windows offers none.
        for id in [RulesetID.palm122, .windows201] {
            var e = engine(id, cash: 0)
            let net = e.state.shipQuote(.termite).netPrice
            e.state.commander.cash = net
            let r = e.perform(.buyShip(.termite, transfers: [.lightningShield, .fuelCompactor, .morgansLaser]),
                              acknowledging: [.buyShip])
            if id == .palm122 {
                #expect(r.events.contains(.cannotAffordAllTransfers) && !r.events.contains(.cannotAffordTransfer(.lightningShield)))
                #expect(r.events.contains(.cannotAffordTransfer(.fuelCompactor)) && r.events.contains(.cannotAffordTransfer(.morgansLaser)))
                #expect(e.state.commander.cash == -30_000 && e.state.commander.ship.has(.lightning))
            } else {
                #expect(r.events.contains(.cannotAffordTransfer(.morgansLaser)) && e.state.commander.cash == 0)
            }
        }
    }

    @Test("RUL-054 RUL-055 SHP-043 SHP-045 BNK-050 Palm keeps pod and insurance free, clears cargo, and the moved Lightning is uncharged")
    func palmTradeEffects() {
        for id in allRulesets {
            var e = makeEngine(id) { s in
                var ship = freshShip(.wasp, s)
                ship.shields = [ShieldInstance(type: .lightning, charge: 350)]
                ship.escapePod = true
                ship.cargo[0] = 5
                ship.tribbles = 10
                ship.crew[1] = 4
                s.commander.ship = ship
                s.commander.insurance = true
                s.commander.noClaim = 12
                s.commander.priceCargo[0] = 150
                s.commander.cash = 400_000
                s.quests.scarab = QuestStatus.Scarab.done
                s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech
            }
            let quote = e.state.shipQuote(.termite)
            #expect(quote.candidates.contains { $0.item == .escapePod } == (id != .palm122))
            _ = e.perform(.buyShip(.termite, transfers: [.lightningShield]), acknowledging: [.buyShip])
            let s = e.state
            #expect(s.commander.ship.type == .termite)
            #expect(s.commander.ship.shields.first?.charge == (id == .palm122 ? 0 : 350))
            #expect(s.commander.ship.escapePod == (id == .palm122))
            #expect(s.commander.insurance == (id == .palm122) && s.commander.noClaim == (id == .palm122 ? 12 : 0))
            #expect(s.commander.ship.cargo == Array(repeating: 0, count: 10) && s.commander.ship.tribbles == 0)
            #expect(s.commander.ship.crew[1] == 4 && s.quests.scarab == QuestStatus.Scarab.notStarted)
            if id == .palm122 { #expect(s.commander.priceCargo == Array(repeating: 0, count: 10)) }
        }
    }

    @Test("SHP-050 Palm offers the escape pod when ToSpend ≥ 2000; C# tests cash")
    func escapePodOffer() {
        for id in [RulesetID.windows201, .palm122] {
            let s = makeEngine(id) { s in
                s.commander.ship = freshShip(.beetle, s)
                s.commander.ship.crew[1] = 1
                s.options.reserveMoney = true
                s.commander.cash = 2_000 + s.dailyRate(of: 1) - 1
            }.state
            #expect(s.escapePodOffered == (id == .windows201))
        }
    }
}

@Suite("Skills and crew rulesets (RUL-048…051, 057…061, 105, 116; CRW {M5})")
struct CrewRulesetSpecTests {
    @Test("RUL-048 SHP-010 the cloaking device adds +3 pilot in Modern and Windows, +2 in Palm")
    func cloakBonus() {
        for id in allRulesets {
            let s = makeEngine(id) { $0.commander.ship.gadgets = [.cloakingDevice] }.state
            #expect(s.skill(.pilot) == 5 + (id == .palm122 ? 2 : 3))
        }
    }

    @Test("RUL-049 RUL-050 CRW-013 CRW-014 CRW-016 Palm: best crew + gadget bonus once per type, then AdaptDifficulty (Hard 0)")
    func palmSkillOrder() {
        func pilot(_ id: RulesetID, _ d: Difficulty, gadgets: [GadgetType]) -> Int {
            makeEngine(id, difficulty: d) { $0.commander.ship = freshShip(.wasp, $0); $0.commander.ship.gadgets = gadgets }
                .state.skill(.pilot)
        }
        #expect(pilot(.palm122, .hard, gadgets: [.navigatingSystem, .cloakingDevice]) == 5 + 3 + 2)
        #expect(pilot(.palm122, .impossible, gadgets: [.navigatingSystem, .cloakingDevice]) == 9)
        #expect(pilot(.windows201, .hard, gadgets: [.navigatingSystem, .cloakingDevice]) == 4 + 3 + 3)
        #expect(pilot(.modern, .hard, gadgets: [.navigatingSystem, .navigatingSystem]) == 4 + 6)
        #expect(pilot(.palm122, .hard, gadgets: [.navigatingSystem, .navigatingSystem]) == 5 + 3)
        #expect(Skills.adjustForDifficulty(5, .hard, hardAdjustment: 0) == 5 && Skills.adjustForDifficulty(5, .hard) == 4)
        #expect(pilot(.palm122, .easy, gadgets: []) == 6 && pilot(.palm122, .normal, gadgets: []) == 5)
        // Palm stops at the first vacant crew slot.
        let gap = makeEngine(.palm122) { s in
            s.commander.ship = freshShip(.wasp, s)
            s.commander.ship.crew[2] = 1
            s.mercenaries[1].skills = [10, 10, 10, 10]
        }.state
        #expect(gap.skill(.pilot) == 5)
    }

    @Test("RUL-057 CRW-021 Palm passengers (Jarek, Wild) contribute no skills; C# counts them as crew")
    func passengers() {
        for id in allRulesets {
            let s = makeEngine(id) { s in
                s.commander.ship = freshShip(.beetle, s)
                s.hireCrew(CrewID.wild)
                s.hireCrew(CrewID.jarek)
            }.state
            #expect(s.skill(.fighter) == (id == .palm122 ? 5 : s.mercenaries[CrewID.wild].skills[1]))
            #expect(s.dailyRate(of: CrewID.wild) == 0 && s.dailyRate(of: CrewID.jarek) == 0)
        }
    }

    @Test("CRW-005 Palm commander names hold at most 20 characters")
    func nameLength() {
        let long = String(repeating: "x", count: 21)
        #expect(CommanderRules.validate(NewGameConfig(commanderName: long, ruleset: .palm122, seed: 1)) == .commanderNameTooLong)
        #expect(CommanderRules.validate(NewGameConfig(commanderName: String(long.dropLast()), ruleset: .palm122, seed: 1)) == nil)
        #expect(CommanderRules.validate(NewGameConfig(commanderName: long, ruleset: .windows201, seed: 1)) == nil)
    }

    @Test("CRW-028 Palm offers only the lowest-index mercenary of the system")
    func oneForHire() {
        for id in [RulesetID.windows201, .palm122] {
            let s = makeEngine(id) { s in
                for m in 1..<s.mercenaries.count where s.mercenaries[m].systemID == s.commander.currentSystem {
                    s.mercenaries[m].systemID = nil
                }
                s.mercenaries[5].systemID = s.commander.currentSystem
                s.mercenaries[9].systemID = s.commander.currentSystem
            }.state
            #expect(s.mercenariesForHire == (id == .palm122 ? [5] : [5, 9]))
        }
    }

    @Test("RUL-059 CRW-031 Zeethibal's wage: 0 in Modern and Windows; (P+F+T+E)×3 in Palm")
    func zeethibal() {
        for id in allRulesets {
            let s = makeEngine(id) { $0.mercenaries[CrewID.zeethibal].skills = [10, 8, 5, 5] }.state
            #expect(s.dailyRate(of: CrewID.zeethibal) == (id == .palm122 ? 84 : 0))
        }
    }

    @Test("CRW-033 Palm sums wages over the mercenary slots, skipping vacancies; C# stops at the first vacancy")
    func mercenaryCost() {
        for id in [RulesetID.windows201, .palm122] {
            let s = makeEngine(id) { s in
                s.commander.ship = freshShip(.beetle, s)
                s.commander.ship.crew[2] = 3
            }.state
            #expect(s.mercenaryCosts == (id == .palm122 ? s.dailyRate(of: 3) : 0))
        }
    }

    @Test("CRW-036 Palm hire: a passenger takes a quarter; no free quarter → noFreeQuarters; no cash check")
    func palmHire() {
        var e = makeEngine(.palm122) { s in
            s.commander.ship = freshShip(.beetle, s)
            s.hireCrew(CrewID.jarek)
            s.commander.cash = 0
            for m in 1..<s.mercenaries.count where s.mercenaries[m].systemID == s.commander.currentSystem {
                s.mercenaries[m].systemID = nil
            }
            s.mercenaries[5].systemID = s.commander.currentSystem
            s.mercenaries[6].systemID = s.commander.currentSystem
        }
        #expect(e.perform(.hire(crewID: 5)).events == [.hired(crewID: 5)])
        #expect(e.perform(.hire(crewID: 6)).rejection == .noFreeQuarters)
    }

    @Test("RUL-060 CRW-040 a fired mercenary relocates within range in Modern and Windows; stays put in Palm")
    func fire() {
        for id in allRulesets {
            var e = makeEngine(id) { s in
                s.commander.ship = freshShip(.beetle, s)
                s.commander.ship.crew[1] = 7
                s.mercenaries[7].systemID = 3
            }
            let rng = e.state.rng
            _ = e.perform(.fire(crewID: 7), acknowledging: [.fireMercenary])
            #expect(!e.state.commander.ship.hasCrew(7))
            if id == .palm122 {
                #expect(e.state.mercenaries[7].systemID == 3 && e.state.rng == rng)
            } else if let to = e.state.mercenaries[7].systemID {
                #expect(GalaxyGenerator.distance(e.state.galaxy.systems[to], e.state.currentSystem, rule: e.ruleset.flags.distance) < 20)
                #expect(e.state.rng != rng)
            }
        }
    }

    @Test("CRW-048 on arrest Palm dismisses the mercenaries when any is aboard; C# only when two or more are")
    func arrestCrew() {
        for id in [RulesetID.windows201, .palm122] {
            var s = makeEngine(id) { s in
                s.commander.ship = freshShip(.beetle, s)
                s.commander.ship.crew[1] = 7
                s.commander.cash = 100_000
                s.commander.policeRecordScore = -40
            }.state
            _ = s.arrested()
            #expect(s.commander.ship.hasCrew(7) == (id == .windows201))
        }
    }

    @Test("RUL-116 CRW-051 RUL-116 Modern relocates mercenaries lost to arrest or the pod; Windows and Palm leave them")
    func lostMercenaries() {
        for id in allRulesets {
            var s = makeEngine(id) { s in
                s.commander.ship = freshShip(.beetle, s)
                s.commander.ship.crew[1] = 7
                s.commander.ship.crew[2] = 8
                s.mercenaries[7].systemID = 1
                s.mercenaries[8].systemID = 2
                s.commander.cash = 100_000
                s.commander.policeRecordScore = -40
                s.warpSystem = (s.commander.currentSystem + 1) % s.galaxy.systems.count
            }.state
            var pod = s
            _ = s.arrested()
            pod.createFlea()
            for result in [s, pod] {
                let moved = [7, 8].map { result.mercenaries[$0].systemID }
                if id == .modern {
                    for to in moved.compactMap({ $0 }) {
                        #expect(GalaxyGenerator.distance(result.galaxy.systems[to], result.galaxy.systems[result.warpSystem],
                                                         rule: result.ruleset.flags.distance) < 20)
                    }
                    #expect(result.rng != makeEngine(id).state.rng)
                } else {
                    #expect(moved == [1, 2])
                }
            }
        }
    }

    @Test("CRW-054 Palm increase re-draws rand(4) until the skill is below 10; all at 10 → no change, no draw")
    func palmIncrease() {
        var s = makeEngine(.palm122) { $0.mercenaries[CrewID.commander].skills = [10, 10, 10, 3] }.state
        var expectedRNG = s.rng
        while expectedRNG.next(below: 4) != 3 {}
        s.changeRandomSkill(1)
        #expect(s.mercenaries[CrewID.commander].skills == [10, 10, 10, 4] && s.rng == expectedRNG)
        s.mercenaries[CrewID.commander].skills = [10, 10, 10, 10]
        let rng = s.rng
        s.changeRandomSkill(1)
        #expect(s.mercenaries[CrewID.commander].skills == [10, 10, 10, 10] && s.rng == rng)
    }

    @Test("RUL-058 CRW-055 Palm decrease re-draws until the skill exceeds n; with none eligible every ruleset makes no change")
    func palmDecrease() {
        var s = makeEngine(.palm122) { $0.mercenaries[CrewID.commander].skills = [9, 3, 3, 3] }.state
        s.changeRandomSkill(-3)
        #expect(s.mercenaries[CrewID.commander].skills == [6, 3, 3, 3])
        for id in allRulesets {
            var t = makeEngine(id) { $0.mercenaries[CrewID.commander].skills = [2, 2, 2, 2] }.state
            #expect(!t.changeRandomSkill(-3) && t.mercenaries[CrewID.commander].skills == [2, 2, 2, 2])
        }
    }

    @Test("CRW-058 Palm strange tonic below Hard with every skill at 10 ends without a change")
    func palmTonic() {
        var e = encounterEngine(.palm122, .bottleOld, difficulty: .easy) { $0.mercenaries[CrewID.commander].skills = [10, 10, 10, 10] }
        let r = e.perform(.encounter(.drink), acknowledging: [.drinkTonic])
        #expect(r.events.contains(.tonicConsumed(good: false)))
        #expect(e.state.mercenaries[CrewID.commander].skills == [10, 10, 10, 10])
    }

    @Test("CRW-061 Palm recalculates buy prices after Huie's training; C# does not (CRW-060)")
    func huie() {
        for id in [RulesetID.windows201, .palm122] {
            var e = encounterEngine(id, .captainHuie) { s in
                s.commander.ship.weapons = [.militaryLaser]
                s.mercenaries[CrewID.commander].skills = [5, 5, 10, 0]
                s.buyPrices = Array(repeating: 1, count: 10)
                // No transit to resume, so no arrival recomputes the prices afterwards.
                s.encounterTransit = nil
            }
            _ = e.perform(.encounter(.meet), acknowledging: [.meetCaptain])
            #expect((e.state.buyPrices == Array(repeating: 1, count: 10)) == (id == .windows201))
        }
    }

    @Test("RUL-061 passengers warn at 5 and turn impatient in Modern and Windows; Palm has no impatience")
    func impatience() {
        for id in allRulesets {
            var s = makeEngine(id) { s in
                s.commander.ship = freshShip(.beetle, s)
                s.hireCrew(CrewID.jarek)
                s.quests.jarek = 5
            }.state
            let events = s.incDays(1)
            #expect(events.contains(.passengerConcerned(crewID: CrewID.jarek)) == (id != .palm122))
            #expect(s.quests.jarek == (id == .palm122 ? 5 : 6))
        }
    }
}

@Suite("Bank rulesets (RUL-044…046, BNK {M5})")
struct BankRulesetSpecTests {
    @Test("RUL-044 BNK-041 insurance: double precision in Modern and Windows; Palm integer with min(noClaim, 90)")
    func premium() {
        for id in allRulesets {
            for noClaim in [0, 10, 95] {
                var s = makeEngine(id).state
                s.commander.ship.hull = 39
                s.commander.insurance = true
                s.commander.noClaim = noClaim
                let w = s.baseWorth(of: s.commander.ship, forInsurance: true)
                let expected = id == .palm122
                    ? max(1, ((w * 5) / 2_000) * (100 - min(noClaim, 90)) / 100)
                    : max(1, Int(Double(w) * 0.0025 * Double(100 - noClaim) / 100.0))
                #expect(s.insuranceCosts == expected, "\(id) \(noClaim)")
            }
        }
    }

    @Test("RUL-045 BNK-044 BNK-045 no-claim: +days (clamped 90) in Modern and Windows; Palm +1 per warp, unclamped, (maximum) only at 90")
    func noClaim() {
        for id in allRulesets {
            var s = makeEngine(id) { s in s.commander.insurance = true; s.commander.noClaim = 89 }.state
            _ = s.incDays(3)
            #expect(s.commander.noClaim == (id == .palm122 ? 89 : 90))
            #expect(s.bankPreview.noClaimAtMaximum == (id != .palm122))
            if id == .palm122 {
                s.commander.noClaim = 90
                #expect(s.bankPreview.noClaimAtMaximum)
                s.commander.noClaim = 91
                #expect(!s.bankPreview.noClaimAtMaximum && s.bankPreview.noClaim == 90)
            }
        }
        // A normal Palm warp adds exactly one.
        var e = makeEngine(.palm122) { s in
            s.commander.insurance = true
            s.commander.ship.escapePod = true
            s.commander.noClaim = 90
            s.commander.cash = 50_000
            s.options.disableOpponents = true
            let here = s.currentSystem
            s.warpSystem = s.galaxy.systems.indices.first {
                $0 != s.commander.currentSystem
                    && GalaxyGenerator.distance(s.galaxy.systems[$0], here, rule: s.ruleset.flags.distance) <= 14
            } ?? 0
        }
        let r = e.perform(.warp)
        #expect(r.rejection == nil)
        #expect(e.state.commander.noClaim == 91)
    }

    @Test("RUL-046 buying insurance resets no-claim in Modern and Windows; Palm keeps it")
    func buyInsurance() {
        for id in allRulesets {
            var e = makeEngine(id) { s in s.commander.ship.escapePod = true; s.commander.noClaim = 30 }
            _ = e.perform(.buyInsurance)
            #expect(e.state.commander.insurance && e.state.commander.noClaim == (id == .palm122 ? 30 : 0))
        }
    }

    @Test("BNK-019 Palm's pay-back-everything repays min(debt, credits, 99999)")
    func repayAll() {
        for id in [RulesetID.windows201, .palm122] {
            let s = makeEngine(id) { s in s.commander.debt = 150_000; s.commander.cash = 120_000 }.state
            #expect(s.bankPreview.repayAllAmount == (id == .palm122 ? 99_999 : 120_000))
        }
    }

    @Test("BNK-021 Palm interest max(1, debt/10) with the credits > interest branch")
    func interest() {
        var s = makeEngine(.palm122).state
        s.commander.debt = 7; s.commander.cash = 5
        s.payInterest()
        #expect(s.commander.cash == 4 && s.commander.debt == 7)
        s.commander.debt = 12_345; s.commander.cash = 1_234
        s.payInterest()
        #expect(s.commander.cash == 0 && s.commander.debt == 12_345)
        s.commander.cash = 1_235
        s.payInterest()
        #expect(s.commander.cash == 1 && s.commander.debt == 12_345)
    }

    @Test("BNK-030 Palm market buying is blocked above 100000 debt; trade in orbit has no debt check")
    func debtBlocksMarket() {
        var e = makeEngine(.palm122) { s in setMarket(&s); s.commander.debt = 100_001; s.commander.cash = 5_000 }
        #expect(e.perform(.buyCargo(.water, quantity: 1)).rejection == .debtTooLargeToTrade)
        var trader = Ship(type: .beetle, spec: e.ruleset.tables.ship(.beetle))
        trader.cargo[2] = 10
        #expect((e.state.makeOrbitTradeOffer(direction: .traderSells, trader: trader)?.maxQuantity ?? 0) > 0)
    }

    @Test("BNK-048 Palm runs the arrival before the escape-pod payout; C# after")
    func podOrder() {
        // The `.arrived` event is always last (TRV-060), so the order is checked by composing the steps: the pod step's
        // state equals Arrival()-then-pod for Palm and pod-then-arrival for C#.
        for id in [RulesetID.windows201, .palm122] {
            var e = encounterEngine(id, .pirateAttack) { s in s.commander.ship.escapePod = true }
            var expected = e.state
            expected.phase = .docked
            expected.encounterTransit = nil
            if id == .palm122 {
                // The Palm pod sequence itself starts with Arrival() (POL-107), then System Information.
                _ = expected.palmEscapeWithPod()
                expected.palmSystemInformation()
            } else {
                _ = expected.escapeWithPod()
                _ = expected.arrival()
            }
            let events = e.finishEncounter(.escapePod)
            #expect(events.contains { if case .escapePodUsed = $0 { true } else { false } })
            #expect(events.last == .arrived(system: e.state.commander.currentSystem))
            #expect(e.state.commander == expected.commander && e.state.galaxy == expected.galaxy, "\(id)")
        }
    }

    @Test("BNK-058 Palm asks about Wild before the money checks; accepting drops Wild even if a check then fails")
    func wildFirst() {
        for id in [RulesetID.windows201, .palm122] {
            var e = makeEngine(id) { s in
                s.commander.ship = freshShip(.beetle, s)
                s.hireCrew(CrewID.wild)
                s.quests.wild = QuestStatus.Wild.started
                s.commander.debt = 200_000
                let here = s.currentSystem
                s.warpSystem = s.galaxy.systems.indices.first {
                    $0 != s.commander.currentSystem
                        && GalaxyGenerator.distance(s.galaxy.systems[$0], here, rule: s.ruleset.flags.distance) <= 14
                } ?? 0
            }
            let r = e.perform(.warp)
            if id == .palm122 {
                #expect(r.decision == .confirm(Confirmation(.wildLeavesWithoutLaser)))
                let r2 = e.perform(.warp, acknowledging: [.wildLeavesWithoutLaser])
                #expect(r2.events == [.wildLeftShip, .departureBlocked(.debtTooLargeToTravel)])
                #expect(e.state.quests.wild == QuestStatus.Wild.notStarted)
            } else {
                #expect(r.rejection == .debtTooLargeToTravel)
            }
        }
    }
}
