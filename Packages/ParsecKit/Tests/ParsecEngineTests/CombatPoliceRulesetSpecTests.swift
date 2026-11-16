// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecEngine

private let firearms = TradeItemType.firearms.rawValue
private let narcotics = TradeItemType.narcotics.rawValue

/// Spec model of one opponent shot at the unshielded player (CMB §3–§5), parameterised by the ruleset switches under test.
private func expectedPlayerHull(_ s: GameState, _ opp: Ship, skill: SkillType, realFactor: Bool, capHull: Int, halve: Bool) -> Int {
    var r = s.rng
    let a = s.skills(of: opp), d = s.shipSkills
    let size = s.commander.ship.spec(s.ruleset).size.rawValue
    guard r.next(below: a[1] + size) >= r.next(below: 5 + d[0] / 2) else { return s.commander.ship.hull }
    var damage = r.next(below: opp.weaponStrength(s.ruleset) * (100 + 2 * a[skill.rawValue]) / 100)
    guard damage > 0 else { return s.commander.ship.hull }
    if s.reactorOnBoard {
        let dd = s.difficulty.rawValue
        let f = 1 + Double(dd + 1) * (s.difficulty < .normal ? 0.25 : 0.33)
        damage = realFactor ? Int(Double(damage) * f) : damage * Int(f)
    }
    damage = max(1, damage - r.next(below: d[3]))
    damage = min(damage, capHull / max(1, 4 - s.difficulty.rawValue))
    if halve { damage /= 2 }
    return max(0, s.commander.ship.hull - damage)
}

private func combatState(_ r: RulesetID, _ d: Difficulty = .normal, k: Int = 0) -> GameState {
    RS.advanced(RS.state(r, d) { s in
        s.commander.ship = CombatKit.playerShip(s, .wasp, weapons: [.pulseLaser])
        s.mercenaries[CrewID.commander].skills = [3, 3, 3, 3]
    }, k)
}

@Suite("RUL §2 / CMB: combat by ruleset")
struct CombatRulesetTests {
    @Test("RUL-090 CMB-023 CMB-028 damage uses the attacker's Fighter (Windows, Modern) or Engineer (Palm); then −rand(E_def), ≥ 1")
    func damageSkill() {
        for (r, skill) in [(RulesetID.windows201, SkillType.fighter), (.modern, .fighter), (.palm122, .engineer)] {
            var hits = 0
            for k in 0..<60 {
                var s = combatState(r, k: k)
                let opp = CombatKit.opponent(&s, .wasp, weapons: [.militaryLaser], skills: [5, 2, 5, 10])
                var e = EncounterState(type: .pirateAttack, opponent: opp)
                let expected = expectedPlayerHull(s, opp, skill: skill, realFactor: false,
                                                  capHull: s.commander.ship.hullStrength(s.ruleset), halve: false)
                _ = s.executeAttack(commanderAttacks: false, fleeing: false, encounter: &e)
                #expect(s.commander.ship.hull == expected)
                if expected < s.commander.ship.hullStrength(s.ruleset) { hits += 1 }
            }
            #expect(hits > 0)
        }
    }

    @Test("RUL-114 CMB-025 reactor factor: real factor before truncation (Modern, Palm) vs integer factor (Windows)")
    func reactorFactor() {
        for (r, real) in [(RulesetID.windows201, false), (.modern, true), (.palm122, true)] {
            for d in Difficulty.allCases {
                for k in 0..<12 {
                    var s = RS.advanced(RS.state(r, d) { s in
                        s.commander.ship = CombatKit.playerShip(s, .wasp, weapons: [.pulseLaser])
                        s.quests.reactor = 5
                    }, k)
                    let opp = CombatKit.opponent(&s, .wasp, weapons: [.militaryLaser], skills: [5, 8, 5, 8])
                    var e = EncounterState(type: .pirateAttack, opponent: opp)
                    let skill = s.ruleset.flags.encounter.damageSkill
                    let expected = expectedPlayerHull(s, opp, skill: skill, realFactor: real,
                                                      capHull: s.commander.ship.hullStrength(s.ruleset), halve: false)
                    _ = s.executeAttack(commanderAttacks: false, fleeing: false, encounter: &e)
                    #expect(s.commander.ship.hull == expected)
                }
            }
        }
        // Spec examples: damage 100 → 125, 150, 199, 232, 265 with the real factor.
        let got = Difficulty.allCases.map { d in Int(100 * (1 + Double(d.rawValue + 1) * (d < .normal ? 0.25 : 0.33))) }
        #expect(got == [125, 150, 199, 232, 265])
    }

    @Test("RUL-104 CMB-030 CMB-032 CMB-033 hardened hull: halves for all (Windows), player only (Modern), never in Palm; Palm caps with the base hull")
    func hardenedHull() {
        for r in [RulesetID.windows201, .modern, .palm122] {
            for k in 0..<30 {
                var s = combatState(r, k: k)
                s.quests.scarab = QuestStatus.Scarab.done
                s.commander.ship.hullUpgraded = true
                let opp = CombatKit.opponent(&s, .wasp, weapons: [.morgansLaser, .morgansLaser, .morgansLaser], skills: [5, 10, 5, 10])
                var e = EncounterState(type: .pirateAttack, opponent: opp)
                let rules = s.ruleset.flags.encounter
                let expected = expectedPlayerHull(s, opp, skill: rules.damageSkill, realFactor: false,
                                                  capHull: s.commander.ship.hullStrength(s.ruleset), // upgraded hull for the hardened player
                                                  halve: r != .palm122)
                _ = s.executeAttack(commanderAttacks: false, fleeing: false, encounter: &e)
                #expect(s.commander.ship.hull == expected)
            }
            // The opponent as defender: halved only in Windows.
            var s = combatState(r)
            s.quests.scarab = QuestStatus.Scarab.done
            s.commander.ship.weapons = [.morgansLaser, .morgansLaser, .morgansLaser]
            s.mercenaries[CrewID.commander].skills = [10, 10, 10, 10]
            var damaged = false
            for k in 0..<40 where !damaged {
                var c = RS.advanced(s, k)
                var opp = CombatKit.opponent(&c, .wasp, skills: [1, 1, 1, 1])
                opp.hull = opp.hullStrength(c.ruleset)
                var e = EncounterState(type: .pirateAttack, opponent: opp)
                _ = c.executeAttack(commanderAttacks: true, fleeing: false, encounter: &e)
                let loss = opp.hull - e.opponent.hull
                if loss > 0 {
                    damaged = true
                    let cap = c.ruleset.tables.ship(.wasp).hullStrength / 2
                    #expect(r == .windows201 ? loss <= cap / 2 : loss <= cap)
                    if r != .windows201 { #expect(loss > cap / 2) } // huge damage hits the unhalved cap
                }
            }
            #expect(damaged)
        }
    }

    @Test("RUL-091 CMB-019 Scarab: Pulse, Morgan's and Quantum hurt it (Windows, Modern); only Pulse and Morgan's in Palm")
    func scarabWeapons() {
        #expect(Ruleset.palm122.tables.weapon(.pulseLaser).power == 15 && Ruleset.palm122.tables.weapon(.beamLaser).power == 25)
        #expect(Ruleset.palm122.tables.weapon(.militaryLaser).power == 35 && Ruleset.palm122.tables.weapon(.morgansLaser).power == 85)
        for r in [RulesetID.windows201, .palm122] {
            var dealt = false
            for k in 0..<60 {
                var s = combatState(r, k: k)
                s.options.disableOpponents = false
                // Palm has no disruptors at all (RUL-015), so its ship carries only the two lasers that never hurt the Scarab.
                s.commander.ship.weapons = r == .palm122 ? [.beamLaser, .militaryLaser] : [.quantumDisruptor, .beamLaser, .militaryLaser]
                s.mercenaries[CrewID.commander].skills = [10, 10, 10, 10]
                var e = EncounterState(type: .scarabAttack, opponent: s.specialShips.scarab)
                e.opponent.shields = []
                // A damage roll above 0 counts as a hit (the Quantum share then goes to disruption, CMB-027).
                if s.executeAttack(commanderAttacks: true, fleeing: false, encounter: &e) { dealt = true }
            }
            #expect(dealt == (r == .windows201), "\(r)")
        }
    }

    @Test("RUL-092 CMB-011 shooting a surrendering ship uses the fleeing modifier (Windows) or the normal one (Palm)")
    func surrenderingTarget() {
        for r in [RulesetID.windows201, .palm122] {
            var checked = false
            for k in 0..<200 where !checked {
                let s = combatState(r, k: k)
                var t = s
                let opp = CombatKit.opponent(&t, .wasp, skills: [1, 1, 1, 1])
                var asFlee = t, asNormal = t
                var e1 = EncounterState(type: .pirateSurrender, opponent: opp), e2 = e1
                _ = asFlee.executeAttack(commanderAttacks: true, fleeing: true, encounter: &e1)
                _ = asNormal.executeAttack(commanderAttacks: true, fleeing: false, encounter: &e2)
                guard e1.opponent.hull != e2.opponent.hull else { continue }
                checked = true
                var round = t
                var e = EncounterState(type: .pirateSurrender, opponent: opp)
                _ = round.executeRound(&e)
                #expect(e.opponent.hull == (r == .palm122 ? e2 : e1).opponent.hull)
            }
            #expect(checked)
        }
    }

    @Test("CMB-015 Palm: a fleeing player on Beginner is never shot at (no draws); no targeting auto-hit without disabling")
    func beginnerFlee() {
        var s = combatState(.palm122, .beginner)
        let opp = CombatKit.opponent(&s, .wasp, weapons: [.militaryLaser])
        var e = EncounterState(type: .pirateAttack, opponent: opp)
        let s0 = s.rng
        #expect(!s.executeAttack(commanderAttacks: false, fleeing: true, encounter: &e))
        #expect(s.rng == s0 && !e.opponentDisabled)
    }

    @Test("CMB-051 CMB-059 CMB-095 Palm: no opponent escape check while the player flees; no stance draw without hull damage")
    func palmDrawCounts() {
        var checked = 0
        for k in 0..<60 {
            for r in [RulesetID.windows201, .palm122] {
                var s = combatState(r, k: k)
                let opp = CombatKit.opponent(&s, .gnat, skills: [10, 5, 5, 5])
                var e = EncounterState(type: .pirateFlee, opponent: opp)
                e.cmdrFleeing = true
                let s0 = s.rng
                let (res, _) = s.executeRound(&e)
                guard res == .continue else { continue }
                let n = RS.draws(s0, s.rng)
                // Player escape pair only (Palm) vs escape pair + opponent escape pair + the stance draw (Windows).
                #expect(n == (r == .palm122 ? 2 : 5))
                checked += 1
            }
        }
        #expect(checked > 2)
    }

    @Test("CMB-059 CMB-060 Palm stance update: draws rand(10) only where needed; famous captains never change")
    func palmStance() {
        for k in 0..<40 {
            var s = combatState(.palm122, k: k)
            let opp = CombatKit.opponent(&s, .gnat)
            var e = EncounterState(type: .pirateAttack, opponent: opp)
            e.opponent.hull = 10 // dropped below 2/3 of 100; the player is undamaged → flee, then rand(10) > 8 → surrender
            let surrender = RS.peek(s, [10])[0] > 8
            let s0 = s.rng
            s.updateEncounterType(prevCmdrHull: s.commander.ship.hull, prevOppHull: 100, encounter: &e)
            #expect(e.type == (surrender ? .pirateSurrender : .pirateFlee) && RS.draws(s0, s.rng) == 1)
            var t = EncounterState(type: .traderAttack, opponent: opp)
            t.opponent.hull = 95 // between 9/10 and 1: no change, no draw
            let t0 = s.rng
            s.updateEncounterType(prevCmdrHull: s.commander.ship.hull, prevOppHull: 100, encounter: &t)
            #expect(t.type == .traderAttack && s.rng == t0)
            var f = EncounterState(type: .famousCaptainAttack, opponent: opp)
            f.opponent.hull = 1
            s.updateEncounterType(prevCmdrHull: s.commander.ship.hull, prevOppHull: 100, encounter: &f)
            #expect(f.type == .famousCaptainAttack && s.rng == t0)
        }
    }

    @Test("CMB-048 Palm outcomes: both destroyed → pod if owned else bothDestroyed; opponent destroyed → won")
    func palmOutcomes() {
        var foundBoth = false
        for k in 0..<400 where !foundBoth {
            var s = combatState(.palm122, .hard, k: k)
            s.commander.ship.hull = 1
            s.commander.ship.weapons = [.morgansLaser, .morgansLaser, .morgansLaser]
            s.mercenaries[CrewID.commander].skills = [10, 10, 10, 10]
            var opp = CombatKit.opponent(&s, .gnat, weapons: [.militaryLaser], skills: [5, 10, 5, 5])
            opp.hull = 1
            var e = EncounterState(type: .pirateAttack, opponent: opp)
            var pod = s
            pod.commander.ship.escapePod = true
            var e2 = e
            let (res, events) = s.executeRound(&e)
            if res == .killed, e.opponent.hull <= 0 {
                foundBoth = true
                #expect(events.contains(.bothDestroyed))
                #expect(pod.executeRound(&e2).0 == .escapePod)
            } else if res == .normal {
                #expect(events.first == .opponentDestroyed(.gnat))
            }
        }
        #expect(foundBoth)
    }

    @Test("CMB-063 CMB-069 ENC-189 Palm continuation: attacking a fleeing ship continues regardless of the fleeing option")
    func palmContinuation() {
        for r in [RulesetID.windows201, .palm122] {
            var checked = false
            for k in 0..<60 where !checked {
                var s = combatState(r, k: k)
                s.options.continuousAttack = true
                s.options.continuousAttackFleeing = false
                var opp = CombatKit.opponent(&s, .wasp, skills: [1, 1, 1, 1])
                opp.hull = opp.hullStrength(s.ruleset)
                var e = EncounterState(type: .pirateFlee, opponent: opp)
                let (res, _) = s.executeRound(&e)
                guard res == .continue, e.type == .pirateFlee else { continue }
                checked = true
                #expect(e.continueAttacking == (r == .palm122))
            }
            #expect(checked)
        }
        // A change to a surrender type clears AutoAttack in Palm; a change to a flee type keeps it.
        var kinds: Set<EncounterType> = []
        for k in 0..<200 {
            var s = combatState(.palm122, k: k)
            s.options.continuousAttack = true
            s.commander.ship.weapons = [.morgansLaser, .morgansLaser]
            s.mercenaries[CrewID.commander].skills = [10, 10, 10, 10]
            let opp = CombatKit.opponent(&s, .bumblebee, skills: [1, 1, 1, 1])
            var e = EncounterState(type: .traderAttack, opponent: opp)
            let (res, _) = s.executeRound(&e)
            guard res == .continue, e.type != .traderAttack else { continue }
            #expect(e.continueAttacking == (e.type == .traderFlee) && !e.continueFleeing)
            kinds.insert(e.type)
        }
        #expect(kinds == [.traderFlee, .traderSurrender])
    }

    @Test("CMB-067 ENC-147 POL-031 Palm auto-repeat re-runs the attack checks: each round against police costs −3")
    func palmAutoRepeat() {
        for r in [RulesetID.windows201, .palm122] {
            var e = Pol.engine(.policeAttack, r, opponent: .wasp) { s in
                s.options.continuousAttack = true
                s.commander.policeRecordScore = -40
                s.commander.ship = CombatKit.playerShip(s, .wasp, weapons: [.pulseLaser])
                s.mercenaries[CrewID.commander].skills = [1, 1, 1, 1]
            }
            _ = e.perform(.encounter(.attack), acknowledging: Pol.yes)
            let after1 = e.state.commander.policeRecordScore
            #expect(after1 == (r == .palm122 ? -43 : -40))
            guard let enc = CombatKit.encounter(e), enc.continueAttacking else { Issue.record("no continuation \(r)"); continue }
            _ = e.perform(.encounter(.autoRepeat), acknowledging: Pol.yes)
            #expect(e.state.commander.policeRecordScore == (r == .palm122 ? -46 : -40))
        }
    }

    @Test("RUL-093 RUL-095 CMB-072 CMB-075 CMB-076 won effects: Palm always credits the pirate bounty (event only at ≥ −5); captains add no kill")
    func wonEffects() {
        for r in [RulesetID.windows201, .palm122] {
            var s = combatState(r)
            s.commander.policeRecordScore = -20
            let cash = s.commander.cash
            var opp = CombatKit.opponent(&s, .gnat)
            opp.cargo = Array(repeating: 0, count: 10)
            var e = EncounterState(type: .pirateAttack, opponent: opp)
            let b = s.bounty(of: opp)
            let events = s.encounterWon(&e)
            #expect(s.commander.cash == cash + (r == .palm122 ? b : 0))
            #expect(!events.contains(.bountyPaid(b)))
            #expect(s.commander.kills.pirates == 1 && s.commander.policeRecordScore == -19)
            #expect(s.commander.reputationScore == 1 + ShipType.gnat.rawValue / 2)
            var t = combatState(r)
            var f = EncounterState(type: .famousCaptainAttack, opponent: t.generateOpponent(.famousCaptain))
            _ = t.encounterWon(&f)
            #expect(t.commander.kills.traders == (r == .palm122 ? 0 : 1))
            var p = combatState(r)
            var pol = EncounterState(type: .policeAttack, opponent: opp)
            _ = p.encounterWon(&pol)
            #expect(p.commander.kills.police == 1 && p.commander.policeRecordScore == -6)
        }
        var s = combatState(.palm122)
        s.commander.policeRecordScore = 0
        let opp = CombatKit.opponent(&s, .gnat)
        var e = EncounterState(type: .pirateAttack, opponent: opp)
        let b = s.bounty(of: opp)
        #expect(s.encounterWon(&e).contains(.bountyPaid(b)))
    }

    @Test("RUL-094 CMB-081 bounty equipment at the discounted local price, 0 above tech level (Windows) vs base price (Palm)")
    func bountyPrices() {
        for r in [RulesetID.windows201, .palm122] {
            var s = combatState(r)
            s.galaxy.systems[s.commander.currentSystem].techLevel = .preAgricultural
            let opp = CombatKit.opponent(&s, .gnat, weapons: [.militaryLaser], shields: [ShieldInstance(type: .reflective, charge: 1)],
                                         skills: [6, 6, 6, 6])
            let t = s.ruleset.tables
            let equip = r == .palm122 ? t.weapon(.militaryLaser).price + t.shield(.reflective).price : 0
            let sk = s.skills(of: opp)
            let price = (t.ship(.gnat).price + equip) * (2 * sk[0] + sk[3] + 3 * sk[1]) / 60
            #expect(s.bounty(of: opp) == max(25, min(2_500, price / 200 / 25 * 25)))
        }
    }

    @Test("RUL-097 CMB-085 scoop: victim's cargo on rand(D) == 0 (Windows) vs rand(D) == 1 and a cheap random item (Palm)")
    func scoop() {
        for k in 0..<40 {
            var w = combatState(.windows201, k: k)
            let empty = Ship(type: .gnat, spec: w.ruleset.tables.ship(.gnat))
            w.scoopRoll(empty)
            #expect(w.pendingScoop == nil)
            var p = combatState(.palm122, k: k)
            let v = RS.peek(p, [2, 10, 10])
            p.scoopRoll(empty)
            if v[0] == 1 {
                #expect(p.pendingScoop?.rawValue == (v[1] >= 5 ? v[2] : v[1]))
            } else {
                #expect(p.pendingScoop == nil)
            }
        }
        var easy = combatState(.palm122, .easy)
        let v = RS.peek(easy, [10, 10])
        easy.scoopRoll(Ship(type: .gnat, spec: easy.ruleset.tables.ship(.gnat)))
        #expect(easy.pendingScoop?.rawValue == (v[0] >= 5 ? v[1] : v[0]))
    }

    @Test("CMB-088 Palm scoop with a full hold: scoopNoRoom; with room the unit is added")
    func scoopRoom() {
        var e = Pol.engine(.pirateAttack, .palm122)
        e.state.pendingScoop = .water
        e.state.commander.ship.cargo[0] = e.state.commander.ship.cargoBays(e.ruleset)
        #expect(e.perform(.resolveScoop(accept: true)).events == [.scoopNoRoom])
        e.state.pendingScoop = .water
        e.state.commander.ship.cargo[0] = 0
        #expect(e.perform(.resolveScoop(accept: true)).events.first == .scooped(.water))
        #expect(e.state.commander.ship.cargo[0] == 1)
    }

    @Test("RUL-096 CMB-090 CMB-092 plunder: Palm offers it at surrender, applies −2/−1 on pressing Plunder, no reputation or kills")
    func plunder() {
        for (type, delta) in [(EncounterType.traderSurrender, -2), (.pirateSurrender, -1)] {
            #expect(type.actions.contains(.plunder))
            var p = Pol.engine(type, .palm122) { $0.commander.policeRecordScore = 0 }
            if case var .encounter(enc) = p.state.phase {
                enc.opponent.cargo[0] = 3
                p.state.phase = .encounter(enc)
            }
            let r = p.perform(.encounter(.plunder))
            #expect(r.decision == .plunder([3, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
            #expect(p.state.commander.policeRecordScore == delta)
            _ = p.perform(.plunderTake(.water, quantity: 2))
            #expect(p.state.commander.ship.cargo[0] == 2 && p.state.commander.priceCargo[0] == 0)
            let rep = p.state.commander.reputationScore
            _ = p.perform(.plunderDone)
            #expect(p.state.commander.policeRecordScore == delta && p.state.commander.reputationScore == rep)
            var w = Pol.engine(type, .windows201) { $0.commander.policeRecordScore = 0 }
            _ = w.perform(.encounter(.plunder))
            #expect(w.state.commander.policeRecordScore == 0)
            _ = w.perform(.plunderDone)
            #expect(w.state.commander.policeRecordScore == delta && w.state.commander.reputationScore > 0)
        }
    }

    @Test("CMB-008 CMB-095 ENC-147 Palm trader re-roll: unarmed → flee without a draw (Windows draws first)")
    func traderReroll() {
        for r in [RulesetID.windows201, .palm122] {
            var e = Pol.engine(.traderAttack, r) { s in
                if case var .encounter(enc) = s.phase {
                    enc.opponent.weapons = []
                    s.phase = .encounter(enc)
                }
            }
            var enc = Pol.encounter(e)
            let r0 = e.state.rng
            #expect(e.verifyAttack(&enc, Pol.yes) == nil)
            #expect(enc.type == .traderFlee)
            #expect(RS.draws(r0, e.state.rng) == (r == .palm122 ? 0 : 1))
        }
    }
}

@Suite("RUL §2 / POL: police by ruleset")
struct PoliceRulesetTests {
    @Test("RUL-131 ENC-147 POL-031 attacking police: confirm above criminal, record = min(rec, criminal) − 3; Palm on every police type")
    func attackPolice() {
        for (r, criminal) in [(RulesetID.windows201, -30), (.palm122, -10)] {
            var e = Pol.engine(.policeIgnore, r) { $0.commander.policeRecordScore = criminal + 1 }
            #expect(e.perform(.encounter(.attack)).decision == .confirm(Confirmation(.attackPolice, amounts: [criminal - 3])))
            var enc = Pol.encounter(e)
            #expect(e.verifyAttack(&enc, Pol.yes) == nil && e.state.commander.policeRecordScore == criminal - 3 && enc.type == .policeAttack)
            var a = Pol.engine(.policeAttack, r) { $0.commander.policeRecordScore = -50 }
            var ae = Pol.encounter(a)
            _ = a.verifyAttack(&ae, Pol.yes)
            #expect(a.state.commander.policeRecordScore == (r == .palm122 ? -53 : -50))
        }
    }

    @Test("RUL-132 POL-034 attacking a captain: min(rec, −70) − 2 (Windows) or min(rec, −30) − 2 (Palm), Palm again on every round")
    func attackCaptain() {
        for (r, villain) in [(RulesetID.windows201, -70), (.palm122, -30)] {
            var e = Pol.engine(.captainAhab, r) { $0.commander.policeRecordScore = 0 }
            var enc = Pol.encounter(e)
            #expect(e.verifyAttack(&enc, []) == .needsConfirmation(Confirmation(.attackCaptain)))
            #expect(e.verifyAttack(&enc, Pol.yes) == nil)
            #expect(e.state.commander.policeRecordScore == villain - 2 && enc.type == .famousCaptainAttack)
            let news = e.state.newsEvents.count
            var again = enc
            #expect(e.verifyAttack(&again, []) == nil) // no second confirmation
            #expect(e.state.commander.policeRecordScore == (r == .palm122 ? villain - 4 : villain - 2))
            #expect(e.state.newsEvents.count == news)
        }
    }

    @Test("RUL-133 police refuse surrender at rec ≤ −100 (Windows) or ≤ −70 (Palm)")
    func surrenderRefusal() {
        for (r, psycho) in [(RulesetID.windows201, -100), (.palm122, -70)] {
            var e = Pol.engine(.policeAttack, r) { $0.commander.policeRecordScore = psycho }
            #expect(e.perform(.encounter(.surrender), acknowledging: Pol.yes).rejection == .surrenderRefused)
            e = Pol.engine(.policeAttack, r) { $0.commander.policeRecordScore = psycho + 1 }
            #expect(e.perform(.encounter(.surrender)).decision == .confirm(Confirmation(.surrenderToPolice)))
        }
    }

    @Test("RUL-134 RUL-135 ENC-151 POL-037 POL-038 flee penalties and the Palm flee nothing-illegal test")
    func fleePenalties() {
        func recAfterFlee(_ r: RulesetID, _ type: EncounterType, _ rec: Int, _ d: Difficulty) -> Int {
            var e = Pol.engine(type, r, difficulty: d) { s in
                s.commander.policeRecordScore = rec
                s.commander.ship.cargo[firearms] = 1
            }
            var enc = Pol.encounter(e)
            _ = e.verifyFlee(&enc, Pol.yes)
            #expect(enc.type == .policeAttack)
            return e.state.commander.policeRecordScore
        }
        #expect(recAfterFlee(.palm122, .policeInspect, -4, .easy) == -5)
        #expect(recAfterFlee(.windows201, .policeInspect, -4, .easy) == -6)
        #expect(recAfterFlee(.palm122, .policeInspect, 0, .normal) == -6)
        #expect(recAfterFlee(.palm122, .policeInspect, -8, .normal) == -10)
        #expect(recAfterFlee(.palm122, .marieCelestePolice, -5, .normal) == -10)
        #expect(recAfterFlee(.palm122, .marieCelestePolice, -15, .normal) == -18)
        #expect(recAfterFlee(.windows201, .marieCelestePolice, -5, .normal) == -30)
        // ENC-151: Palm counts Wild and the reactor, never the sculpture; C# counts the sculpture as special cargo.
        for (r, asks) in [(RulesetID.windows201, false), (.palm122, true)] {
            var e = Pol.engine(.policeInspect, r) { $0.quests.sculpture = QuestStatus.Sculpture.inTransit }
            #expect((e.perform(.encounter(.flee)).decision == .confirm(Confirmation(.fleeInspection))) == asks)
        }
        var p = Pol.engine(.policeInspect, .palm122) { $0.quests.reactor = 5 }
        #expect(p.perform(.encounter(.flee)).decision != .confirm(Confirmation(.fleeInspection)))
    }

    @Test("POL-052 POL-054 Palm: illegal = Firearms/Narcotics; the nothing-illegal test differs per action")
    func nothingIllegal() {
        var s = RS.state(.palm122) { $0.quests.reactor = 21 }
        #expect(!s.reactorOnBoard && !s.carriesIllegalGoods)
        s.quests.reactor = 1
        #expect(s.reactorOnBoard)
        s.commander.ship.cargo[narcotics] = 1
        #expect(s.carriesIllegalGoods && !s.nothingIllegal(for: .attack))
        s.commander.ship.cargo[narcotics] = 0
        #expect(s.nothingIllegal(for: .attack) && s.nothingIllegal(for: .bribe) && !s.nothingIllegal(for: .flee))
        s.quests.reactor = 0
        s.commander.ship.crew = [CrewID.commander, CrewID.wild]
        #expect(s.nothingIllegal(for: .attack) && !s.nothingIllegal(for: .bribe) && !s.nothingIllegal(for: .flee))
        // Windows uses one test for all three actions.
        var w = RS.state(.windows201) { $0.commander.ship.crew = [CrewID.commander, CrewID.wild] }
        #expect(!w.nothingIllegal(for: .attack) && !w.nothingIllegal(for: .bribe))
        w.commander.ship.crew = [CrewID.commander]
        #expect(w.nothingIllegal(for: .attack))
        // Palm attack at an inspection with Wild aboard but no goods still asks.
        var e = Pol.engine(.policeInspect, .palm122) { s in
            s.commander.ship.crew = [CrewID.commander, CrewID.wild]
            s.commander.policeRecordScore = -20
        }
        #expect(e.perform(.encounter(.attack)).decision == .confirm(Confirmation(.submitWithNothingIllegal)))
    }

    @Test("RUL-139 POL-060 POL-062 Palm submit: the reactor is confiscated without arrest; status 1 skips the warning; Wild arrests")
    func submitReactor() {
        var w = Pol.engine(.policeInspect, .windows201) { $0.quests.reactor = 1 }
        #expect(w.perform(.encounter(.submit)).decision == .confirm(Confirmation(.submitInspection)))
        let wr = w.perform(.encounter(.submit), acknowledging: Pol.yes)
        #expect(wr.events.contains { if case .arrested = $0 { true } else { false } })
        var p = Pol.engine(.policeInspect, .palm122) { s in
            s.quests.reactor = 1
            s.commander.policeRecordScore = 0
        }
        let pr = p.perform(.encounter(.submit))
        #expect(pr.decision == nil && pr.events.prefix(2) == [.inspectionClean, .reactorConfiscated])
        #expect(p.state.quests.reactor == 0 && p.state.commander.policeRecordScore == 1)
        #expect(!pr.events.contains { if case .arrested = $0 { true } else { false } })
        var p5 = Pol.engine(.policeInspect, .palm122) { $0.quests.reactor = 5 }
        #expect(p5.perform(.encounter(.submit)).decision == .confirm(Confirmation(.submitInspection)))
        var pw = Pol.engine(.policeInspect, .palm122) { $0.commander.ship.crew = [CrewID.commander, CrewID.wild] }
        let pwr = pw.perform(.encounter(.submit), acknowledging: Pol.yes)
        #expect(!pwr.events.contains(.inspectionClean))
        #expect(pwr.events.contains { if case .arrested = $0 { true } else { false } })
    }

    @Test("POL-061 Palm inspection fine: integer quotient rounded up to 50 (W = 10001 Normal → 250; C# 300)")
    func inspectionFine() {
        var p = RS.state(.palm122)
        Pol.setWorth(&p, 10_001)
        #expect(p.inspectionFine == 250)
        var w = RS.state(.windows201)
        Pol.setWorth(&w, 10_001)
        #expect(w.inspectionFine == 300)
        var e = Pol.engine(.policeInspect, .palm122) { s in
            Pol.setWorth(&s, 50_000)
            s.commander.ship.cargo[firearms] = 2
            s.commander.priceCargo[firearms] = 400
        }
        // The fine is computed after the goods are removed (C# EncounterVerifySubmit: RemoveIllegalGoods, then Worth).
        var afterRemoval = e.state
        afterRemoval.removeIllegalGoods()
        let fine = afterRemoval.inspectionFine
        let r = e.perform(.encounter(.submit), acknowledging: Pol.yes)
        #expect(r.events.first == .fined(fine))
        #expect(e.state.commander.ship.cargo[firearms] == 0 && e.state.commander.priceCargo[firearms] == 0) // submit clears the basis
    }

    @Test("RUL-140 POL-067 bribe: real ceiling × k incl. sculpture (Windows) vs integer % rounding, × k only with Wild or reactor (Palm)")
    func bribe() {
        let level1 = PoliticalSystemType.allCases.first { Ruleset.windows201.tables.politics($0).bribeLevel == 1 } ?? .anarchy
        let level0 = PoliticalSystemType.allCases.first { Ruleset.windows201.tables.politics($0).bribeLevel == 0 } ?? .anarchy
        func amount(_ r: RulesetID, _ w: Int, _ d: Difficulty = .normal, _ adjust: (inout GameState) -> Void = { _ in }) -> Int? {
            var s = RS.state(r, d) { $0.galaxy.systems[$0.warpSystem].politics = level1 }
            adjust(&s)
            Pol.setWorth(&s, w)
            return s.bribeAmount
        }
        #expect(amount(.palm122, 11_000) == 600 && amount(.palm122, 10_001) == 500 && amount(.windows201, 10_001) == 600)
        #expect(amount(.palm122, 30_000, .hard) { $0.quests.reactor = 5 } == 6_000)
        #expect(amount(.palm122, 11_000) { $0.quests.sculpture = QuestStatus.Sculpture.inTransit } == 600)
        #expect(amount(.windows201, 11_000) { $0.quests.sculpture = QuestStatus.Sculpture.inTransit } == 1_200)
        // Palm checks the bribe level before the customs refusal.
        for (r, err) in [(RulesetID.windows201, CommandError.bribeNotAccepted), (.palm122, .bribeNotPossible)] {
            var e = Pol.engine(.marieCelestePolice, r) { $0.galaxy.systems[$0.warpSystem].politics = level0 }
            #expect(e.perform(.encounter(.bribe), acknowledging: Pol.yes).rejection == err)
        }
    }

    @Test("RUL-138 POL-073 Palm yield: no confirmation, record ≤ −5, goods removed but their cost basis kept")
    func yield() {
        var p = Pol.engine(.marieCelestePolice, .palm122) { s in
            s.commander.policeRecordScore = 3
            s.commander.ship.cargo[narcotics] = 4
            s.commander.priceCargo[narcotics] = 800
        }
        let r = p.perform(.encounter(.yield))
        #expect(r.decision == nil && r.events.first == .yielded)
        #expect(p.state.commander.policeRecordScore == -5 && p.state.commander.ship.cargo[narcotics] == 0)
        #expect(p.state.commander.priceCargo[narcotics] == 800)
        var w = Pol.engine(.marieCelestePolice, .windows201) { s in
            s.commander.ship.cargo[narcotics] = 4
            s.commander.priceCargo[narcotics] = 800
        }
        #expect(w.perform(.encounter(.yield)).decision == .confirm(Confirmation(.submitInspection)))
        _ = w.perform(.encounter(.yield), acknowledging: Pol.yes)
        #expect(w.state.commander.priceCargo[narcotics] == 0)
    }

    @Test("POL-074 POL-110 Palm Yield arrest ends the trip after the arrest's own short Arrival (one arrival, no arrival tail)")
    func yieldArrest() {
        var p = Pol.engine(.marieCelestePolice, .palm122, clicks: 5) { s in
            s.commander.ship.crew = [CrewID.commander, CrewID.wild]
            s.commander.debt = 80_000
            s.commander.cash = 100
        }
        #expect(p.perform(.encounter(.yield)).decision == .confirm(Confirmation(.surrenderToPolice)))
        let r = p.perform(.encounter(.yield), acknowledging: Pol.yes)
        #expect(p.state.phase == .docked && p.state.commander.currentSystem == p.state.warpSystem)
        #expect(r.events.filter { if case .arrived = $0 { true } else { false } }.count == 1)
        #expect(!r.events.contains { if case .debtWarning = $0 { true } else { false } })
        // Windows runs the normal arrival after jail (debt warning included).
        var w = Pol.engine(.policeAttack, .windows201) { s in
            s.commander.debt = 80_000
            s.commander.cash = 100
            s.commander.policeRecordScore = -20
        }
        let wr = w.perform(.encounter(.surrender), acknowledging: Pol.yes)
        #expect(wr.events.contains { if case .debtWarning = $0 { true } else { false } })
    }

    @Test("RUL-102 RUL-136 POL-090 POL-091 arrest fine: Palm two-step division and the negative-fine bug; Modern floors at 500")
    func arrestFine() {
        for r in [RulesetID.windows201, .palm122, .modern] {
            var s = RS.state(r)
            Pol.setWorth(&s, 10_000)
            s.commander.policeRecordScore = -10
            #expect(s.arrestFine == 1_500 && s.arrestTerm == 30)
            s.commander.policeRecordScore = 10
            #expect(s.arrestFine == (r == .modern ? 500 : -500))
            s.commander.ship.crew = [CrewID.commander, CrewID.wild]
            #expect(s.arrestFine == (r == .modern ? 525 : -525))
        }
        // Two-step truncation equals the single division for every sign (C and C# both truncate toward zero).
        for x in [-150_001, -49_999, -100, 0, 99, 49_999, 50_000, 123_456_789] { #expect((x / 100) / 500 == x / 50_000) }
    }

    @Test("RUL-137 POL-098 POL-099 Palm arrest order: Arrival, IncDays, then fine or sale (refunding kept basis), rec −5, debt, interest")
    func palmArrest() {
        var e = Pol.engine(.policeAttack, .palm122) { s in
            s.commander.policeRecordScore = -40
            s.commander.cash = 10
            s.commander.debt = 0
            s.commander.ship.cargo[narcotics] = 3
            s.commander.priceCargo[narcotics] = 900
            s.commander.insurance = true
            s.commander.ship.crew = [CrewID.commander, 5]
            s.quests.scarab = QuestStatus.Scarab.done
            s.commander.ship.hullUpgraded = true
        }
        let fine = e.state.arrestFine
        let sale = e.state.shipWorth(forInsurance: true) // includes the narcotics basis, kept by Palm
        let days = e.state.commander.days
        let r = e.perform(.encounter(.surrender), acknowledging: Pol.yes)
        #expect(r.events.first == .arrested(term: 40, fine: fine, shipSold: true))
        #expect(e.state.commander.cash == max(0, 10 + sale - fine))
        #expect(e.state.commander.ship.type == .flea && e.state.commander.ship.hullUpgraded) // Scarab status kept
        #expect(e.state.commander.policeRecordScore == -5 && e.state.commander.days == days + 40)
        #expect(!e.state.commander.insurance && e.state.commander.ship.crew.dropFirst().allSatisfy { $0 == nil })
        #expect(e.state.commander.currentSystem == e.state.warpSystem)
        // The debt is paid down after the fine, then interest runs `term` times on what is left.
        var d = Pol.engine(.policeAttack, .palm122) { s in
            s.commander.policeRecordScore = -30
            s.commander.cash = 100_000
            s.commander.debt = 200_000
        }
        let fine2 = d.state.arrestFine
        _ = d.perform(.encounter(.surrender), acknowledging: Pol.yes)
        var expectDebt = 200_000 - (100_000 - fine2)
        for _ in 0..<30 { expectDebt += max(1, Int(Double(expectDebt) * 0.1)) }
        #expect(d.state.commander.cash == 0 && d.state.commander.debt == expectDebt)
    }

    @Test("RUL-099 POL-107 POL-110 escape pod: Palm resets the Scarab upgrade, loses reactor and artifact, one short arrival")
    func escapePod() {
        for r in [RulesetID.windows201, .modern, .palm122] {
            var e = Pol.engine(.pirateAttack, r) { s in
                s.quests.scarab = QuestStatus.Scarab.done
                s.quests.reactor = 5
                s.quests.artifact = QuestStatus.Artifact.onBoard
                s.commander.ship.tribbles = 50
                s.commander.ship.escapePod = true
            }
            let days = e.state.commander.days
            let events = e.finish(.escapePod).events
            let palm = r == .palm122
            #expect(e.state.quests.scarab == (palm ? QuestStatus.Scarab.notStarted : QuestStatus.Scarab.done))
            #expect(e.state.quests.reactor == (palm ? QuestStatus.Reactor.notStarted : QuestStatus.Reactor.done))
            #expect(e.state.quests.artifact == (palm ? QuestStatus.Artifact.notStarted : QuestStatus.Artifact.done))
            #expect(e.state.commander.ship.type == .flea && e.state.commander.ship.tribbles == 0)
            #expect(e.state.commander.days == days + 3 && e.state.commander.currentSystem == e.state.warpSystem)
            #expect(events.filter { if case .arrived = $0 { true } else { false } }.count == 1)
        }
    }

    @Test("RUL-098 POL-083 POL-085 Palm raid: all cargo if it fits, else random units at P·(c−1)/c; nothing to the pirate; Wild leaves with room")
    func palmRaid() {
        var all = Pol.engine(.pirateAttack, .palm122) { s in
            s.commander.ship.cargo[0] = 3
            s.commander.ship.cargo[4] = 2
            s.commander.priceCargo[0] = 30
        }
        let r = all.perform(.encounter(.surrender))
        #expect(r.events.first == .looted(units: 5))
        #expect(all.state.commander.ship.cargo.allSatisfy { $0 == 0 } && all.state.commander.priceCargo[0] == 0)
        var some = Pol.engine(.pirateAttack, .palm122) { s in
            s.commander.ship.cargo[0] = 3
            s.commander.priceCargo[0] = 10
            if case var .encounter(enc) = s.phase {
                enc.opponent.cargo[1] = enc.opponent.cargoBays(s.ruleset) - 1 // one free bay
                s.phase = .encounter(enc)
            }
        }
        _ = some.perform(.encounter(.surrender))
        #expect(some.state.commander.ship.cargo[0] == 2 && some.state.commander.priceCargo[0] == 6) // C# would give 7
        // Wild: leaves when the pirate ship type has more than one crew quarter.
        for (opp, leaves) in [(ShipType.gnat, false), (.wasp, true)] {
            var e = Pol.engine(.pirateAttack, .palm122, opponent: opp) { $0.commander.ship.crew = [CrewID.commander, CrewID.wild] }
            let crewQuarters = e.ruleset.tables.ship(opp).crewQuarters
            let res = e.perform(.encounter(.surrender))
            #expect(res.events.contains(.wildJoinedPirates) == (leaves && crewQuarters > 1))
            #expect(e.state.wildOnBoard == !(leaves && crewQuarters > 1))
        }
        // Windows keeps stolen goods on the pirate (taken highest index first).
        var w = Pol.engine(.pirateAttack, .windows201) { $0.commander.ship.cargo[9] = 2 }
        _ = w.perform(.encounter(.surrender))
        #expect(w.state.commander.ship.cargo[9] == 0)
    }

    @Test("POL-081 RUL-112 Modern: hidden bays beyond the cargo protect everything, so the pirates blackmail instead of aborting")
    func modernClamp() {
        var e = Pol.engine(.pirateAttack, .modern) { s in
            s.commander.ship.gadgets = [.hiddenCargoBays]
            s.commander.ship.cargo[0] = 2
        }
        let r = e.perform(.encounter(.surrender))
        #expect(r.events.contains { if case .blackmailed = $0 { true } else { false } })
        #expect(e.state.commander.ship.cargo[0] == 2 && e.state.phase != Pol.engine(.pirateAttack).state.phase)
    }

    @Test("RUL-103 POL-011 RUL-103 record decay: in IncDays (Windows) vs once per warp, never in IncDays (Modern, Palm)")
    func decay() {
        for r in [RulesetID.windows201, .modern, .palm122] {
            var s = RS.state(r) { $0.commander.policeRecordScore = 30 }
            _ = s.incDays(30)
            #expect(s.commander.policeRecordScore == (r == .windows201 ? 20 : 30))
        }
        var m = RS.state(.modern) { $0.commander.policeRecordScore = 30 }
        m.commander.days = 9
        m.perWarpRecordDecay()
        #expect(m.commander.policeRecordScore == 29)
        m.commander.days = 10
        m.perWarpRecordDecay()
        #expect(m.commander.policeRecordScore == 29)
        var h = RS.state(.palm122, .hard) { $0.commander.policeRecordScore = -20 }
        h.commander.days = 10
        h.perWarpRecordDecay()
        #expect(h.commander.policeRecordScore == -20)
        h.commander.days = 12
        h.perWarpRecordDecay()
        #expect(h.commander.policeRecordScore == -19)
        var n = RS.state(.palm122) { $0.commander.policeRecordScore = -20 }
        n.commander.days = 7
        n.perWarpRecordDecay()
        #expect(n.commander.policeRecordScore == -19)
        // Windows has no per-warp step at all (the warp only calls it when the flag says so).
        #expect(Ruleset.windows201.flags.travel.policeRecordDecay != .perWarp)
        // A real Modern warp landing on a day divisible by 3 applies it once.
        var e = makeEngine(.modern) { s in
            s.commander.policeRecordScore = 30
            s.commander.days = 8
            s.commander.ship.fuel = s.commander.ship.fuelTanks(s.ruleset)
        }
        guard let target = e.state.destinations.first(where: { !e.state.galaxy.wormholeExists(from: e.state.commander.currentSystem, to: $0) })
        else { Issue.record("no destination"); return }
        _ = e.perform(.selectTarget(target))
        _ = e.perform(.warp, acknowledging: Pol.yes)
        #expect(e.state.commander.days == 9 && e.state.commander.policeRecordScore == 29)
    }
}
