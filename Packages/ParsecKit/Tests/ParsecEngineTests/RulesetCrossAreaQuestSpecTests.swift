// SPDX-License-Identifier: GPL-2.0-or-later
// Cross-area quest {M5} bullets (QST-*, CMB-041, SHP-058, TRV-044): quest ships, the artifact Mantis, Gemulon, the
// reactor, tribbles and the moon per ruleset (docs/specs/QST-*.md, RUL.md).
import Testing
@testable import ParsecEngine

/// A Palm state whose warp system is `system`, with the lowest-activity government so the encounter bands often fail.
private func quietWarp(_ r: RulesetID, to system: Int, _ adjust: (inout GameState) -> Void = { _ in }) -> GameState {
    RS.state(r) { s in
        s.warpSystem = system
        let t = s.ruleset.tables
        func band(_ p: PoliticalSystemType) -> Int {
            let g = t.politics(p)
            return g.activityPirates.rawValue + g.activityPolice.rawValue * 2 + g.activityTraders.rawValue
        }
        s.galaxy.systems[system].politics = PoliticalSystemType.allCases.min { band($0) < band($1) } ?? .anarchy
        adjust(&s)
    }
}

/// True when no attack of a strong Palm ship ever disables `opponent` (Palm has no disruptors: CMB-041, RUL-015).
private func palmNeverDisables(_ opponent: (GameState) -> Ship, weapons: [WeaponType]) -> Bool {
    var damaged = false
    for k in 0..<60 {
        var s = RS.advanced(RS.state(.palm122) { s in
            s.commander.ship = CombatKit.playerShip(s, .wasp, weapons: weapons)
            s.mercenaries[CrewID.commander].skills = [10, 10, 10, 10]
            s.options.disableOpponents = true
        }, k)
        var e = EncounterState(type: .pirateAttack, opponent: opponent(s))
        e.opponent.shields = []
        let before = e.opponent.hull
        _ = s.executeAttack(commanderAttacks: true, fleeing: false, encounter: &e)
        if e.opponentDisabled { return false }
        if e.opponent.hull < before { damaged = true }
    }
    return damaged
}

@Suite("Cross-area rulesets: Palm quest ships (CMB-041, QST-DRAGONFLY-014, QST-SCARAB-016, QST-MONSTER-012)")
struct PalmQuestShipSpecTests {
    @Test("CMB-041 Palm has no disruptors, no disable draw and no …Disabled state; Windows can disable")
    func palmNoDisable() {
        #expect(!Ruleset.palm122.content.hasDisruptors && Ruleset.palm122.tables.weapons.allSatisfy { !$0.disabling })
        #expect(palmNeverDisables({ s in var c = s; return CombatKit.opponent(&c, .gnat) }, weapons: [.morgansLaser, .militaryLaser]))
        // Rounds never turn a Palm encounter into a disabled type.
        let disabled: Set<EncounterType> = [.pirateDisabled, .policeDisabled, .traderDisabled, .famousCaptDisabled]
        for k in 0..<40 {
            var s = RS.advanced(RS.state(.palm122) { s in
                s.commander.ship = CombatKit.playerShip(s, .wasp, weapons: [.morgansLaser, .morgansLaser])
                s.options.disableOpponents = true
            }, k)
            var e = EncounterState(type: .pirateAttack, opponent: RS.gnatOpponent(&s))
            _ = s.executeRound(&e)
            #expect(!disabled.contains(e.type) && !e.opponentDisabled)
        }
        // The Windows disable path exists (Photon disruptor against an unshielded ship).
        var disabledOnce = false
        for k in 0..<60 where !disabledOnce {
            var s = RS.advanced(RS.state(.windows201) { s in
                s.commander.ship = CombatKit.playerShip(s, .wasp, weapons: [.photonDisruptor, .photonDisruptor])
                s.mercenaries[CrewID.commander].skills = [10, 10, 10, 10]
                s.options.disableOpponents = true
            }, k)
            var e = EncounterState(type: .pirateAttack, opponent: RS.gnatOpponent(&s))
            _ = s.executeAttack(commanderAttacks: true, fleeing: false, encounter: &e)
            disabledOnce = e.opponentDisabled
        }
        #expect(disabledOnce)
    }

    @Test("QST-DRAGONFLY-014 Palm: every meeting starts with an undamaged Dragonfly and reset skills; destroying it sets 5; no disabling")
    func palmDragonfly() {
        var s = RS.state(.palm122) { s in
            s.warpSystem = SystemID.zalkon
            s.quests.dragonfly = QuestStatus.Dragonfly.flyZalkon
        }
        let fresh = GalaxyGenerator.createShips(ruleset: .palm122).dragonfly
        var damaged = fresh
        damaged.hull = 3
        damaged.shields = []
        s.persistSpecialShip(damaged)
        let enc = s.determineFixedEncounter(clicks: 1)
        #expect(enc?.type == .dragonflyAttack && enc?.opponent == fresh)
        let d = s.difficulty.rawValue
        #expect(s.mercenaries[CrewID.dragonfly].skills == [4 + d, 6 + d, 1, 6 + d])
        var won = EncounterState(type: .dragonflyAttack, opponent: fresh)
        _ = s.encounterWon(&won)
        #expect(s.quests.dragonfly == QuestStatus.Dragonfly.destroyed && s.quests.dragonfly == 5)
        #expect(palmNeverDisables({ $0.specialShips.dragonfly }, weapons: [.morgansLaser, .morgansLaser]))
    }

    @Test("QST-SCARAB-016 Palm: the Scarab starts every meeting undamaged; only Pulse and Morgan's hurt it; no disabling")
    func palmScarab() {
        var s = RS.state(.palm122) { s in
            s.warpSystem = 3
            s.arrivedViaWormhole = true
            s.galaxy.systems[3].specialEvent = .scarabDestroyed
            s.quests.scarab = QuestStatus.Scarab.hunting
        }
        let fresh = GalaxyGenerator.createShips(ruleset: .palm122).scarab
        var damaged = fresh
        damaged.hull = 9
        s.persistSpecialShip(damaged)
        let enc = s.determineFixedEncounter(clicks: 20)
        #expect(enc?.type == .scarabAttack && enc?.opponent == fresh)
        #expect(Ruleset.palm122.flags.encounter.scarabVulnerableWeapons == [.pulseLaser, .morgansLaser])
        func hurts(_ weapons: [WeaponType]) -> Bool {
            (0..<60).contains { k in
                var c = RS.advanced(RS.state(.palm122) { s in
                    s.commander.ship = CombatKit.playerShip(s, .wasp, weapons: weapons)
                    s.mercenaries[CrewID.commander].skills = [10, 10, 10, 10]
                }, k)
                var e = EncounterState(type: .scarabAttack, opponent: c.specialShips.scarab)
                _ = c.executeAttack(commanderAttacks: true, fleeing: false, encounter: &e)
                return e.opponent.hull < c.specialShips.scarab.hull
            }
        }
        #expect(!hurts([.beamLaser, .militaryLaser]) && hurts([.pulseLaser]) && hurts([.morgansLaser]))
        #expect(palmNeverDisables({ $0.specialShips.scarab }, weapons: [.morgansLaser, .pulseLaser]))
    }

    @Test("QST-MONSTER-012 Palm monster: hull loaded from MonsterHull, written back only on escape, ×105/100 per warp (singularity too), killed → 2")
    func palmMonster() {
        var s = RS.state(.palm122) { s in
            s.warpSystem = SystemID.acamar
            s.quests.spaceMonster = QuestStatus.SpaceMonster.atAcamar
            s.specialShips.spaceMonster.hull = 321
        }
        #expect(s.determineFixedEncounter(clicks: 1)?.opponent.hull == 321)
        var hit = s.specialShips.spaceMonster
        hit.hull = 100
        s.persistSpecialShip(hit)
        #expect(s.specialShips.spaceMonster.hull == 321)
        s.persistSpecialShip(hit, playerEscaped: true)
        #expect(s.specialShips.spaceMonster.hull == 100)
        for (viaSingularity, hull, healed) in [(true, 200, 210), (false, 200, 210), (true, 490, 500)] {
            var w = makeEngine(.palm122).state
            w.warpSystem = plainTarget(w) ?? 1
            w.specialShips.spaceMonster.hull = hull
            _ = w.depart(viaSingularity: viaSingularity)
            #expect(w.specialShips.spaceMonster.hull == healed, "singularity \(viaSingularity)")
        }
        var won = EncounterState(type: .spaceMonsterAttack, opponent: s.specialShips.spaceMonster)
        _ = s.encounterWon(&won)
        #expect(s.quests.spaceMonster == QuestStatus.SpaceMonster.destroyed && s.quests.spaceMonster == 2)
    }

    @Test("QST-SCARAB-012 hardened hull: Windows halves for every defender, Modern only for the player, Palm never (it raises the cap)")
    func hardeningScope() {
        func loss(_ r: RulesetID, hardened: Bool, playerDefends: Bool, k: Int) -> Int {
            var s = RS.advanced(RS.state(r) { s in
                s.commander.ship = CombatKit.playerShip(s, .wasp, weapons: [.pulseLaser])
                s.mercenaries[CrewID.commander].skills = [5, 5, 5, 1]
                if hardened {
                    s.quests.scarab = QuestStatus.Scarab.done
                    s.commander.ship.hullUpgraded = true
                    s.commander.ship.hull = s.commander.ship.hullStrength(s.ruleset)
                }
            }, k)
            var opp = CombatKit.opponent(&s, .wasp, weapons: [.pulseLaser], skills: [5, 5, 5, 1])
            opp.hull = opp.hullStrength(s.ruleset)
            var e = EncounterState(type: .pirateAttack, opponent: opp)
            let before = playerDefends ? s.commander.ship.hull : e.opponent.hull
            _ = s.executeAttack(commanderAttacks: !playerDefends, fleeing: false, encounter: &e)
            return before - (playerDefends ? s.commander.ship.hull : e.opponent.hull)
        }
        for r in allRulesets {
            var compared = 0
            for k in 0..<40 {
                let plain = loss(r, hardened: false, playerDefends: true, k: k)
                guard plain > 0 else { continue }
                compared += 1
                #expect(loss(r, hardened: true, playerDefends: true, k: k) == (r == .palm122 ? plain : plain / 2), "\(r)")
                let oppPlain = loss(r, hardened: false, playerDefends: false, k: k)
                let oppHard = loss(r, hardened: true, playerDefends: false, k: k)
                #expect(oppHard == (r == .windows201 ? oppPlain / 2 : oppPlain), "\(r)")
            }
            #expect(compared > 0)
        }
        #expect(!Ruleset.palm122.flags.encounter.hardenedHullHalvesDamage && Ruleset.palm122.flags.encounter.hullDamageCapUsesBaseHull)
        #expect(Ruleset.modern.flags.hardenedHullProtectsPlayerOnly && !Ruleset.windows201.flags.hardenedHullProtectsPlayerOnly)
    }
}

@Suite("Cross-area rulesets: artifact Mantis and Gemulon (QST-ARTIFACT-004, QST-GEMULON-007)")
struct MantisGemulonSpecTests {
    /// Replays the Palm band roll (and the Kravat roll when `kravat`) and checks the Mantis draw that follows.
    private func checkMantis(_ base: GameState, kravat: Bool) -> (mantis: Bool, none: Bool) {
        var seen = (mantis: false, none: false)
        for k in 0..<400 {
            var s = RS.advanced(base, k)
            var r = s.rng
            let g = s.ruleset.tables.politics(s.galaxy.systems[s.warpSystem].politics)
            let band = g.activityPirates.rawValue + g.activityPolice.rawValue * max(1, 3 - s.policeRecord.rawValue)
                + g.activityTraders.rawValue
            guard r.next(below: 44 - 2 * s.difficulty.rawValue) >= band else { continue }
            if kravat, r.next(below: 100) < 100 / max(2, min(4, 5 - s.difficulty.rawValue)) { continue }
            let mantis = r.next(below: 20) <= 3
            let enc = s.determineRandomEncounter(clicks: 5)
            if mantis {
                #expect(enc?.type == .pirateAttack && enc?.opponent.type == .mantis)
                seen.mantis = true
            } else {
                #expect(enc == nil)
                seen.none = true
            }
        }
        return seen
    }

    @Test("QST-ARTIFACT-004 Palm makes the artifact Mantis draw whenever no band flag is set, also after a failed Kravat roll")
    func artifactMantis() {
        let plain = quietWarp(.palm122, to: 3) { $0.quests.artifact = QuestStatus.Artifact.onBoard }
        let a = checkMantis(plain, kravat: false)
        #expect(a.mantis && a.none)
        let kravat = quietWarp(.palm122, to: SystemID.kravat) { s in
            s.quests.artifact = QuestStatus.Artifact.onBoard
            boardWild(&s)
        }
        let b = checkMantis(kravat, kravat: true)
        #expect(b.mantis && b.none)
        #expect(Ruleset.palm122.flags.encounter.artifactMantisWhenNoBand && !Ruleset.windows201.flags.encounter.artifactMantisWhenNoBand)
    }

    @Test("QST-GEMULON-007 Palm counts the invasion without a cap, invades at ≥ 8 and its Mantis rule tests > 7; a rescue resets to 0")
    func palmGemulon() {
        var s = RS.state(.palm122) { $0.quests.gemulon = 6 }
        _ = s.incDays(3)
        #expect(s.quests.gemulon == 9 && s.galaxy.systems[SystemID.gemulon].specialEvent == .gemulonInvaded)
        s.warpSystem = SystemID.gemulon
        var outcomes = Set<Bool>()
        for k in 0..<20 {
            var c = RS.advanced(s, k)
            var r = c.rng
            let mantis = r.next(below: 10) > 4
            let enc = c.determineRandomEncounter(clicks: 5)
            if mantis {
                #expect(enc?.type == .pirateAttack && enc?.opponent.type == .mantis)
            } else {
                #expect(enc == nil && c.rng == r) // the single rand(10) draw, no band roll
            }
            outcomes.insert(mantis)
        }
        #expect(outcomes == [true, false])
        // Windows: status 9 follows a rescue, so a Gemulon trip rolls the normal bands (never the Mantis draw).
        let w = RS.state(.windows201) { s in
            s.quests.gemulon = QuestStatus.Gemulon.fuel
            s.warpSystem = SystemID.gemulon
        }
        for k in 0..<20 {
            var c = RS.advanced(w, k)
            #expect(c.determineRandomEncounter(clicks: 5)?.opponent.type != .mantis)
        }
        // The Palm rescue stores 0 and the compactor leaves it, so `> 7` can only mean the invasion.
        for (id, rescued, done) in [(RulesetID.palm122, 0, 0), (.windows201, 9, 10)] {
            var e = questEngine(id, .gemulonRescued) { $0.quests.gemulon = 3 }
            _ = e.perform(.specialEvent)
            #expect(e.state.quests.gemulon == rescued)
            _ = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
            #expect(e.state.quests.gemulon == done && e.state.commander.ship.gadgets.contains(.fuelCompactor))
        }
    }
}

@Suite("Cross-area rulesets: Palm passengers' quest rules (QST-JAREK-011/015, QST-WILD-021)")
struct PassengerQuestRulesSpecTests {
    @Test("QST-JAREK-011 QST-WILD-021 Palm has no Jarek or Wild impatience; C# warns at 5 and turns impatient at 11")
    func noImpatience() {
        for id in [RulesetID.palm122, .windows201] {
            var s = makeEngine(id) { s in
                s.commander.ship = freshShip(.beetle, s)
                s.hireCrew(CrewID.jarek)
                s.hireCrew(CrewID.wild)
                s.quests.jarek = QuestStatus.Jarek.started
                s.quests.wild = QuestStatus.Wild.started
            }.state
            var events: [GameEvent] = []
            for _ in 0..<12 { events += s.incDays(1) }
            let palm = id == .palm122
            #expect(events.contains(.passengerConcerned(crewID: CrewID.jarek)) == !palm)
            #expect(events.contains(.passengerImpatient(crewID: CrewID.wild)) == !palm)
            #expect(s.quests.jarek == (palm ? 1 : QuestStatus.Jarek.impatient) && s.quests.wild == (palm ? 1 : QuestStatus.Wild.impatient))
            #expect(s.jarekOnBoard && s.wildOnBoard)
        }
    }

    @Test("QST-WILD-021 the Palm Kravat engineer boost reads the player's Wild (a passenger known only by status)")
    func kravatBoost() {
        for wild in [true, false] {
            for seed in UInt64(0)..<20 {
                var p = RS.state(.palm122, .impossible, seed: seed) { s in
                    s.warpSystem = SystemID.kravat
                    if wild { boardWild(&s) }
                }
                #expect(p.wildOnBoard == wild && !p.commander.ship.hasCrew(CrewID.wild))
                let v = RS.peek(p, [10, 10, 10, 10, 10])
                var ship = Ship(type: .wasp, spec: p.ruleset.tables.ship(.wasp))
                p.generateOpponentCrew(&ship)
                let engineer = p.mercenaries[CrewID.opponent].skills[3]
                #expect(engineer == (wild && v[4] < 5 ? 10 : 1 + v[3]))
            }
        }
    }

    @Test("QST-JAREK-015 Palm delivery: status done, buy prices always recalculated with the +1 added before the difficulty adjustment")
    func palmDelivery() {
        for (difficulty, skill, expected) in [(Difficulty.normal, 5, 6), (.impossible, 1, 1)] {
            var e = questEngine(.palm122, .jarekGetsOut, difficulty: difficulty) { s in
                s.mercenaries[CrewID.commander].skills = [skill, skill, skill, skill]
                s.hireCrew(CrewID.jarek)
                setMarket(&s, buy: 1, sell: 90)
            }
            #expect(e.perform(.specialEvent, acknowledging: QuestTrip.yes).rejection == nil)
            let s = e.state
            #expect(s.quests.jarek == QuestStatus.Jarek.done && !s.jarekOnBoard && s.skill(.trader) == expected)
            let recalculated = Pricing.buyPrices(sell: s.sellPrices, in: s.currentSystem, criminal: s.commander.policeRecordScore < -5,
                                                 traderSkill: s.skill(.trader), ruleset: s.ruleset)
            #expect(s.buyPrices == recalculated && s.buyPrices != Array(repeating: 1, count: 10))
        }
    }
}

@Suite("Cross-area rulesets: moon, skill increase and Scarab status (QST-MOON-002/013, QST-ONEOFF-010, QST-SCARAB-015)")
struct MoonSkillScarabSpecTests {
    @Test("QST-MOON-002 Modern offers the moon on trade-in worth: list-price worth above 400000 is not enough")
    func modernMoonWorth() {
        for id in [RulesetID.modern, .windows201] {
            for extra in [0, 1] {
                let s = questEngine(id, .moon) { s in
                    s.commander.debt = 0
                    s.commander.cash = 0
                    s.commander.cash = 400_000 - s.shipWorth(forInsurance: false) + extra
                }.state
                #expect(s.commander.ship.spec(s.ruleset).price + s.commander.cash > 400_000) // list-price worth above
                let offered = id == .windows201 || extra == 1
                #expect((s.specialEventAvailable == .moon) == offered, "\(id) +\(extra)")
            }
        }
    }

    @Test("QST-MOON-013 Palm retirement ends the game with status MOON and the Palm score formula")
    func palmMoonEnd() {
        var e = makeEngine(.palm122) { s in
            s.commander.currentSystem = SystemID.utopia
            s.galaxy.systems[SystemID.utopia].specialEvent = .moonRetirement
            s.quests.moon = QuestStatus.Moon.bought
        }
        let r = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(e.state.phase == .gameOver(.boughtMoon))
        #expect(r.events.last == .gameEnded(.boughtMoon, score: e.state.score(for: .boughtMoon)))
        #expect(e.ruleset.flags.travel.scoreFormula == .palm && e.state.quests.moon > QuestStatus.Moon.notStarted)
    }

    @Test("QST-ONEOFF-010 increases reach 10 in Modern and Palm; Palm redraws rand(4) until a skill below 10, none when all are 10")
    func skillIncrease() {
        var p = makeEngine(.palm122) { $0.mercenaries[CrewID.commander].skills = [10, 10, 9, 10] }.state
        var r = p.rng
        var d = r.next(below: 4)
        while d != 2 { d = r.next(below: 4) }
        let raised = p.changeRandomSkill(1)
        #expect(raised)
        #expect(p.mercenaries[CrewID.commander].skills == [10, 10, 10, 10] && p.rng == r)
        let rng = p.rng
        let again = p.changeRandomSkill(1)
        #expect(!again && p.rng == rng && p.mercenaries[CrewID.commander].skills == [10, 10, 10, 10])
        for (id, reaches) in [(RulesetID.modern, true), (.windows201, false)] {
            var s = makeEngine(id) { $0.mercenaries[CrewID.commander].skills = [9, 10, 10, 10] }.state
            _ = s.changeRandomSkill(1)
            #expect((s.mercenaries[CrewID.commander].skills[0] == 10) == reaches)
        }
        #expect(Ruleset.modern.flags.randomSkillIncreaseReachesTen && Ruleset.palm122.flags.randomSkillIncreaseReachesTen)
    }

    @Test("QST-SCARAB-015 Palm resets Scarab status 3 → 0 with the escape pod and with a ship purchase; C# pods keep it")
    func palmScarabReset() {
        for id in allRulesets {
            var s = makeEngine(id) { s in
                s.quests.scarab = QuestStatus.Scarab.done
                s.commander.ship.escapePod = true
                s.warpSystem = plainTarget(s) ?? 1
            }.state
            _ = s.escapeWithPod()
            #expect(s.quests.scarab == (id == .palm122 ? QuestStatus.Scarab.notStarted : QuestStatus.Scarab.done))
        }
        var e = questEngine(.palm122) { s in
            s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech
            s.quests.scarab = QuestStatus.Scarab.done
        }
        #expect(e.perform(.buyShip(.firefly, transfers: []), acknowledging: QuestTrip.yes).rejection == nil)
        #expect(e.state.commander.ship.type == .firefly && e.state.quests.scarab == QuestStatus.Scarab.notStarted)
    }
}

@Suite("Cross-area rulesets: reactor and tribbles on Palm arrival (QST-REACTOR-014/019, QST-TRIBBLES-012)")
struct ReactorTribbleArrivalSpecTests {
    private static func arriving(_ id: RulesetID, _ adjust: (inout GameState) -> Void = { _ in }) -> GameState {
        var s = makeEngine(id).state
        s.warpSystem = plainTarget(s) ?? 1
        adjust(&s)
        return s
    }

    @Test("QST-REACTOR-014 Palm runs Arrival() first, then the warnings at 2, 16, 18 and the meltdown at 20; the pod adds only its Arrival()")
    func palmReactorArrival() {
        for status in [2, 3, 16, 17, 18] {
            var s = Self.arriving(.palm122) { $0.quests.reactor = status }
            var replica = s
            replica.arrivalMarket()
            let events = s.arrival()
            #expect(events.contains(.reactorWarning(status: status)) == [2, 16, 18].contains(status), "status \(status)")
            #expect(s.galaxy.systems.map(\.pressure) == replica.galaxy.systems.map(\.pressure))
        }
        var dead = Self.arriving(.palm122) { $0.quests.reactor = QuestStatus.Reactor.date }
        var replica = dead
        replica.arrivalMarket()
        let de = dead.arrival()
        #expect(de.contains(.reactorMeltdown) && dead.phase == .gameOver(.killed))
        #expect(dead.commander.currentSystem == dead.warpSystem && dead.rng == replica.rng)
        var pod = Self.arriving(.palm122) { s in
            s.quests.reactor = QuestStatus.Reactor.date
            s.commander.ship.escapePod = true
        }
        var twice = pod
        twice.arrivalMarket()
        twice.arrivalMarket()
        let pe = pod.arrival()
        #expect(pe.first == .reactorMeltdown && pod.rng == twice.rng && pod.commander.ship.type == .flea)
    }

    @Test("QST-REACTOR-019 Palm: the pod sets the reactor to 0 (C# 22); submitting with it and no Wild confiscates it; real damage factor")
    func palmReactorLoss() {
        for id in [RulesetID.palm122, .windows201] {
            var s = Self.arriving(id) { s in
                s.quests.reactor = 5
                s.commander.ship.escapePod = true
            }
            _ = s.escapeWithPod()
            #expect(s.quests.reactor == (id == .palm122 ? QuestStatus.Reactor.notStarted : QuestStatus.Reactor.done))
        }
        var p = Pol.engine(.policeInspect, .palm122) { s in
            s.quests.reactor = 1
            s.commander.policeRecordScore = 0
        }
        let r = p.perform(.encounter(.submit))
        #expect(r.events.contains(.reactorConfiscated) && p.state.quests.reactor == 0)
        #expect(!r.events.contains { if case .arrested = $0 { true } else { false } })
        #expect(Ruleset.palm122.flags.reactorDamageRealFactor && Ruleset.palm122.flags.encounter.reactorConfiscatedOnSubmit)
    }

    @Test("QST-TRIBBLES-012 Palm tribbles: cost bases scale with what is left; growth uses T/2 except after food; clamp; skipped after arrest")
    func palmTribbles() {
        let narc = TradeItemType.narcotics.rawValue, food = TradeItemType.food.rawValue
        // Narcotics: T = 1 + rand(3), i = min(1 + rand(3), narc) converted, basis × (narc − i)/narc, then T += 1 + rand(max(1, T/2)).
        var n = Self.arriving(.palm122) { s in
            s.commander.ship.tribbles = 500
            s.commander.ship.cargo[narc] = 2
            s.commander.priceCargo[narc] = 999
        }
        var rn = n.rng
        var t = 1 + rn.next(below: 3)
        let dead = min(1 + rn.next(below: 3), 2)
        t += 1 + rn.next(below: max(1, t / 2))
        _ = n.arrivalTribbles()
        #expect(n.commander.ship.tribbles == t && n.rng == rn)
        #expect(n.commander.ship.cargo[narc] == 2 - dead && n.commander.priceCargo[narc] == 999 * (2 - dead) / 2)
        // Food: T += 100 + rand(food × 100), food = rand(food), basis × new/old, then T += 1 + rand(T).
        var f = Self.arriving(.palm122) { s in
            s.commander.ship.tribbles = 10
            s.commander.ship.cargo[food] = 4
            s.commander.priceCargo[food] = 400
        }
        var rf = f.rng
        var tf = 10 + 100 + rf.next(below: 400)
        let left = rf.next(below: 4)
        tf += 1 + rf.next(below: tf)
        _ = f.arrivalTribbles()
        #expect(f.commander.ship.tribbles == tf && f.commander.priceCargo[food] == 400 * left / 4)
        // No branch: growth by 1 + rand(T/2), clamped to 100000; at 100000 no growth draw.
        var g = Self.arriving(.palm122) { $0.commander.ship.tribbles = 99_000 }
        var rg = g.rng
        let grown = min(100_000, 99_000 + 1 + rg.next(below: 49_500))
        let ge = g.arrivalTribbles()
        #expect(g.commander.ship.tribbles == grown && g.rng == rg)
        #expect(ge.contains(.tribbleInspectorWarning(count: grown)) == false) // 99 000 → ≤ 100 000 crosses no tested threshold
        var full = Self.arriving(.palm122) { $0.commander.ship.tribbles = 100_000 }
        let rfull = full.rng
        _ = full.arrivalTribbles()
        #expect(full.commander.ship.tribbles == 100_000 && full.rng == rfull)
        // The inspector warns only when 100, 1000, 10000 or 50000 is crossed.
        var w = Self.arriving(.palm122) { $0.commander.ship.tribbles = 40_000 }
        let we = w.arrivalTribbles()
        #expect(we.contains(.tribbleInspectorWarning(count: w.commander.ship.tribbles)) == (w.commander.ship.tribbles >= 50_000))
        // After a Palm arrest only Arrival() runs: the tribbles do not change.
        var jail = Self.arriving(.palm122) { $0.commander.ship.tribbles = 50 }
        _ = jail.arrivalAfterArrestOrPod(pod: false)
        #expect(jail.commander.ship.tribbles == 50)
    }
}

@Suite("Cross-area rulesets: Palm auto-buy and post-Marie customs (SHP-058, TRV-044)")
struct AutoBuyCustomsSpecTests {
    @Test("SHP-058 Palm arrival auto-fuel and auto-repair buy what the cash allows; Windows buys all or nothing")
    func partialAutoBuy() {
        for id in [RulesetID.palm122, .windows201] {
            var s = makeEngine(id) { s in
                s.warpSystem = plainTarget(s) ?? 1
                s.options.autoFuel = true
                s.commander.ship.fuel = s.commander.ship.fuelTanks(s.ruleset) - 5
                s.commander.cash = 2 * s.commander.ship.spec(s.ruleset).fuelCost
            }.state
            let tanks = s.commander.ship.fuelTanks(s.ruleset)
            #expect(s.arrivalRepairs() == [.autoFuelFailed])
            #expect(s.commander.ship.fuel == (id == .palm122 ? tanks - 3 : tanks - 5))
            var rep = makeEngine(id) { s in
                s.warpSystem = plainTarget(s) ?? 1
                s.options.autoRepair = true
                s.mercenaries[CrewID.commander].skills = [1, 1, 1, 1]
                s.commander.ship.hull = 10
                s.commander.cash = 3 * s.commander.ship.spec(s.ruleset).repairCost
            }.state
            let cash = rep.commander.cash
            _ = rep.arrivalRepairs()
            #expect((rep.commander.cash < cash) == (id == .palm122)) // Palm buys partial repairs
        }
        #expect(Ruleset.palm122.flags.travel.arrivalAutoBuyPartial && !Ruleset.modern.flags.travel.arrivalAutoBuyPartial)
    }

    @Test("TRV-044 Palm post-Marie customs: after the loop (click 1 again, flag cleared); finishing it arrives with no further click")
    func postMarie() {
        var e = GameEngine(state: RS.state(.palm122) { s in
            s.quests.justLootedMarie = true
            s.phase = .inTransit(TransitState(destination: s.warpSystem, clicksRemaining: 3, viaWormhole: false))
            s.galaxy.systems[s.warpSystem].politics = .anarchy
        })
        // Inside the loop no customs encounter appears at click 1 (Windows would show it there).
        var inLoop = e.state
        #expect(inLoop.determineFixedEncounter(clicks: 1) == nil && inLoop.quests.justLootedMarie)
        var events = e.continueTransit()
        while case .encounter = e.state.phase, Pol.encounter(e).type != .marieCelestePolice {
            events += e.finishEncounter(.normal)
        }
        guard case let .encounter(enc) = e.state.phase else { Issue.record("no customs encounter: \(events)"); return }
        #expect(enc.type == .marieCelestePolice && enc.clicks == 1 && !e.state.quests.justLootedMarie)
        #expect(e.state.encounterTransit?.clicksRemaining == 1)
        let r = e.perform(.encounter(.yield))
        #expect(e.state.phase == .docked && r.events.contains(.arrived(system: e.state.warpSystem)))
        #expect(!r.events.contains(.uneventfulTrip) && !r.events.contains { if case .encounterStarted = $0 { true } else { false } })
    }
}
