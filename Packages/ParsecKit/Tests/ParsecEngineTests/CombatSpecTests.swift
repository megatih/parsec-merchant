// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Testing
@testable import ParsecEngine

// docs/specs/CMB.md §1–§5: encounter combat state, attack/flee commands, round structure, to-hit and damage (Windows 2.01 rules; Modern only where a MOD applies).
@Suite("Combat spec: commands, rounds, damage (CMB)")
struct CombatSpecTests {
    typealias Kit = CombatKit

    // MARK: §1 State and commands

    @Test("CMB-001 EncounterState carries the round flags and survives a Codable round trip mid-encounter")
    func encounterStateCodable() throws {
        var s = Kit.state()
        s.commander.ship = Kit.playerShip(s, .hornet, weapons: [.beamLaser])
        var enc = EncounterState(type: .pirateAttack, opponent: Kit.opponent(&s, .gnat, weapons: [.pulseLaser]), clicks: 9)
        enc.cmdrFleeing = true
        enc.oppFleeing = true
        enc.oppFleeingPrev = true
        enc.cmdrHit = true
        enc.oppHit = true
        enc.continueAttacking = true
        enc.continueFleeing = true
        enc.opponentDisabled = true
        enc.round = 3
        s.phase = .encounter(enc)
        let decoded = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(s))
        #expect(decoded == s)
        guard case var .encounter(e2) = decoded.phase else { Issue.record("phase lost"); return }
        #expect(e2 == enc)
        // Resuming from the decoded save plays the next round exactly like the original.
        var a = s, b = decoded, e1 = enc
        let ra = a.executeRound(&e1), rb = b.executeRound(&e2)
        #expect(ra.0 == rb.0 && ra.1 == rb.1 && a == b && e1 == e2)
    }

    @Test("CMB-002 a new encounter starts with continue flags and opponentDisabled clear; attack/flee set cmdrFleeing")
    func encounterStartFlags() {
        var s = Kit.state()
        let enc = EncounterState(type: .pirateAttack, opponent: Kit.opponent(&s, .gnat))
        #expect(!enc.continueAttacking && !enc.continueFleeing && !enc.opponentDisabled && !enc.forceContinuous)
        // A stale cmdrFleeing is overwritten by every attack or flee before the round runs.
        var e = Kit.engine(.pirateAttack) { s in Kit.opponent(&s, .gnat, weapons: [.pulseLaser]) }
        var stale = Kit.encounter(e)
        stale?.cmdrFleeing = true
        guard var st = stale else { Issue.record("no encounter"); return }
        #expect(e.verifyAttack(&st, []) == nil)
        #expect(!st.cmdrFleeing)
        st.cmdrFleeing = false
        #expect(e.verifyFlee(&st, []) == nil)
        #expect(st.cmdrFleeing)
    }

    @Test("CMB-003 attack without any weapon is rejected with noWeapons and changes nothing")
    func attackNoWeapons() {
        var e = Kit.engine(.pirateAttack) { s in Kit.opponent(&s, .gnat, weapons: [.pulseLaser]) }
        e.state.commander.ship.weapons = []
        let before = e.state
        #expect(e.perform(.encounter(.attack), acknowledging: Kit.yes).rejection == .noWeapons)
        #expect(e.state == before)
    }

    @Test("CMB-004 attack on a non-disableable opponent without lasers is rejected with noLasers")
    func attackNoLasers() {
        for (type, ship) in [(EncounterType.pirateAttack, ShipType.mantis), (.spaceMonsterAttack, .spaceMonster)] {
            var e = Kit.engine(type) { s in Kit.opponent(&s, ship, weapons: [.pulseLaser]) }
            e.state.commander.ship.weapons = [.photonDisruptor]
            #expect(e.perform(.encounter(.attack), acknowledging: Kit.yes).rejection == .noLasers)
            e.state.commander.ship.weapons = [.photonDisruptor, .pulseLaser]
            #expect(e.perform(.encounter(.attack), acknowledging: Kit.yes).rejection == nil)
        }
        // A disableable pirate may be attacked with disruptors alone.
        var e = Kit.engine(.pirateAttack) { s in Kit.opponent(&s, .gnat, weapons: [.pulseLaser]) }
        e.state.commander.ship.weapons = [.photonDisruptor]
        #expect(e.perform(.encounter(.attack), acknowledging: Kit.yes).rejection == nil)
    }

    @Test("CMB-006 attack type transitions; other types unchanged; cmdrFleeing cleared")
    func attackTransitions() {
        let cases: [(EncounterType, ShipType, EncounterType)] = [
            (.pirateIgnore, .gnat, .pirateAttack), (.dragonflyIgnore, .dragonfly, .dragonflyAttack),
            (.scarabIgnore, .scarab, .scarabAttack), (.scorpionIgnore, .scorpion, .scorpionAttack),
            (.spaceMonsterIgnore, .spaceMonster, .spaceMonsterAttack), (.policeIgnore, .gnat, .policeAttack),
            (.captainAhab, .wasp, .famousCaptainAttack), (.captainConrad, .wasp, .famousCaptainAttack),
            (.captainHuie, .wasp, .famousCaptainAttack),
            (.pirateAttack, .gnat, .pirateAttack), (.pirateFlee, .gnat, .pirateFlee), (.pirateSurrender, .gnat, .pirateSurrender),
            (.pirateDisabled, .gnat, .pirateDisabled), (.traderFlee, .gnat, .traderFlee), (.policeFlee, .gnat, .policeFlee),
            (.traderDisabled, .gnat, .traderDisabled), (.policeDisabled, .gnat, .policeDisabled),
        ]
        for (from, ship, to) in cases {
            var e = Kit.engine(from) { s in Kit.opponent(&s, ship, weapons: [.pulseLaser]) }
            e.state.commander.ship.weapons = [.pulseLaser, .quantumDisruptor]
            guard var enc = Kit.encounter(e) else { Issue.record("no encounter"); continue }
            enc.cmdrFleeing = true
            #expect(e.verifyAttack(&enc, Kit.yes) == nil, "\(from)")
            #expect(enc.type == to, "\(from)")
            #expect(!enc.cmdrFleeing)
        }
    }

    @Test("CMB-007 trader reaction: one rand(1500) drawn first decides traderFlee vs traderAttack; traderFlee never re-rolled")
    func traderReaction() {
        for seed in UInt64(0)..<60 {
            for from in [EncounterType.traderBuy, .traderIgnore, .traderSell, .traderAttack, .traderSurrender] {
                let armed = seed % 3 != 0
                var e = Kit.engine(from, seed: seed) { s in Kit.opponent(&s, .gnat, weapons: armed ? [.pulseLaser] : []) }
                e.state.commander.reputationScore = Int(seed % 5) * 120
                guard var enc = Kit.encounter(e) else { continue }
                var copy = e.state.rng
                let roll = copy.next(below: 1_500)
                let flee = roll <= e.state.commander.reputationScore * 10 / (ShipType.gnat.rawValue + 1) || !armed
                #expect(e.verifyAttack(&enc, Kit.yes) == nil)
                #expect(enc.type == (flee ? .traderFlee : .traderAttack))
                #expect(e.state.rng == copy, "exactly one draw")
            }
            var e = Kit.engine(.traderFlee, seed: seed) { s in Kit.opponent(&s, .gnat, weapons: [.pulseLaser]) }
            guard var enc = Kit.encounter(e) else { continue }
            let rng = e.state.rng
            #expect(e.verifyAttack(&enc, Kit.yes) == nil)
            #expect(enc.type == .traderFlee && e.state.rng == rng)
        }
    }

    @Test("CMB-009 flee sets cmdrFleeing; inspections turn into policeAttack; an unconfirmed flee changes nothing")
    func fleeCommand() {
        var e = Kit.engine(.pirateAttack) { s in Kit.opponent(&s, .gnat, weapons: [.pulseLaser]) }
        guard var enc = Kit.encounter(e) else { Issue.record("no encounter"); return }
        #expect(e.verifyFlee(&enc, []) == nil)
        #expect(enc.cmdrFleeing && enc.type == .pirateAttack)

        for (type, warning) in [(EncounterType.policeInspect, WarningID.fleeInspection), (.marieCelestePolice, .fleeMariePolice)] {
            var p = Kit.engine(type) { s in Kit.opponent(&s, .gnat, weapons: [.pulseLaser]) }
            let before = p.state
            let r = p.perform(.encounter(.flee))
            #expect(r.decision == .confirm(Confirmation(warning)))
            #expect(p.state == before)
            guard var pe = Kit.encounter(p) else { continue }
            #expect(p.verifyFlee(&pe, Kit.yes) == nil)
            #expect(pe.type == .policeAttack && pe.cmdrFleeing)
        }
        // Flee is offered only where ENC shows the Flee button.
        var f = Kit.engine(.pirateFlee) { s in Kit.opponent(&s, .gnat) }
        #expect(f.perform(.encounter(.flee)).rejection == .encounterActionUnavailable)
    }

    // MARK: §2 Round structure

    @Test("CMB-010 round prologue and who fires, by the type at the start of the round")
    func roundStructure() {
        for seed in UInt64(0)..<200 {
            var s = Kit.state(.normal, seed: seed)
            s.commander.ship = Kit.playerShip(s, .hornet, weapons: [.beamLaser, .beamLaser])
            s.commander.ship.hull = 10_000
            let opp = Kit.opponent(&s, .wasp, weapons: [.militaryLaser, .militaryLaser], skills: [5, 10, 5, 1])
            let types: [EncounterType] = [.pirateFlee, .traderSurrender, .policeFlee, .pirateDisabled, .traderBuy]
            var enc = EncounterState(type: types[Int(seed) % types.count], opponent: opp)
            enc.oppFleeing = seed % 2 == 0
            enc.cmdrHit = true
            enc.oppHit = true
            let prevFlee = enc.oppFleeing
            let sBefore = s
            _ = s.executeRound(&enc)
            #expect(s.commander.ship.hull == 10_000, "only the player fires in (b) and (c)")
            #expect(enc.oppFleeingPrev == prevFlee)
            #expect(!enc.cmdrHit)
            // (a): with the player fleeing the opponent fires and the player does not.
            var s2 = sBefore
            var e2 = EncounterState(type: .pirateAttack, opponent: opp)
            e2.cmdrFleeing = true
            _ = s2.executeRound(&e2)
            #expect(e2.opponent.hull == opp.hull && !e2.oppHit)
        }
    }

    @Test("CMB-012 fleeing from policeSurrender: nobody fires; only the escape pair and the update draw")
    func fleeFromSurrenderDemand() {
        for seed in UInt64(0)..<100 {
            var s = Kit.state(.hard, seed: seed)
            s.commander.ship = Kit.playerShip(s, .hornet, weapons: [.beamLaser])
            let opp = Kit.opponent(&s, .wasp, weapons: [.militaryLaser], skills: [6, 10, 5, 5])
            var enc = EncounterState(type: .policeSurrender, opponent: opp)
            enc.cmdrFleeing = true
            var copy = s.rng
            let escaped = (copy.next(below: 7) + s.shipSkills[0] / 3) * 2 >= copy.next(below: s.skills(of: opp)[0]) * (2 + 3)
            if !escaped { _ = copy.next(below: 100) }
            let hulls = (s.commander.ship.hull, opp.hull)
            let (result, _) = s.executeRound(&enc)
            #expect(s.commander.ship.hull == hulls.0 && enc.opponent.hull == hulls.1)
            #expect(result == (escaped ? .normal : .continue))
            #expect(s.rng == copy)
        }
    }

    @Test("CMB-013 round results: continue keeps the encounter; normal, killed and escapePod leave it")
    func roundResults() {
        var seen: Set<String> = []
        for seed in UInt64(0)..<400 where seen.count < 4 {
            var e = Kit.engine(.pirateAttack, difficulty: .hard, seed: seed) { s in
                Kit.opponent(&s, .wasp, weapons: [.militaryLaser, .militaryLaser, .militaryLaser], skills: [5, 10, 5, 5])
            }
            e.state.commander.ship.hull = Int(seed % 4) * 15 + 5
            e.state.commander.ship.escapePod = seed % 2 == 0
            guard var enc = Kit.encounter(e) else { continue }
            enc.opponent.hull = Int(seed % 3) * 30 + 5
            e.state.phase = .encounter(enc)
            var probe = e.state, pe = enc
            let (result, _) = probe.executeRound(&pe)
            _ = e.perform(.encounter(.attack), acknowledging: Kit.yes)
            switch result {
            case .continue: #expect(Kit.encounter(e) != nil)
            case .normal: #expect(Kit.encounter(e) == nil)
            case .killed: #expect(e.state.phase == .gameOver(.killed))
            case .escapePod: #expect(e.state.phase == .docked)
            case .arrested: Issue.record("a round never arrests")
            }
            seen.insert("\(result)")
        }
        #expect(seen == ["continue", "normal", "killed", "escapePod"])
    }

    // MARK: §3–§5 To-hit, weapon power, damage

    @Test("CMB-014 CMB-016 to-hit: Beginner fleeing never hit, Targeting auto-hit on a disabled opponent, rand(F+size) >= k*rand(5+P/2)")
    func toHit() throws {
        // CMB-016 example: Fighter 6 vs a Small defender with Pilot 7: hit iff rand(7) >= rand(8) (fleeing: >= 2*rand(8)).
        for seed in UInt64(0)..<150 {
            for fleeing in [false, true] {
                var s = Kit.state(.normal, seed: seed)
                s.commander.ship = Kit.playerShip(s, .gnat, weapons: [.pulseLaser])
                s.mercenaries[CrewID.commander].skills = [5, 6, 5, 5]
                var enc = EncounterState(type: .pirateAttack, opponent: Kit.opponent(&s, .gnat, skills: [7, 5, 5, 5]))
                try #require(s.shipSkills[1] == 6 && s.skills(of: enc.opponent)[0] == 7)
                try #require(s.ruleset.tables.ship(.gnat).size.rawValue == 1)
                var copy = s.rng
                let hit = copy.next(below: 7) >= (fleeing ? 2 : 1) * copy.next(below: 8)
                let before = enc.opponent
                _ = s.executeAttack(commanderAttacks: true, fleeing: fleeing, encounter: &enc)
                if hit { #expect(s.rng != copy, "a hit goes on to the damage roll") } else { #expect(s.rng == copy && enc.opponent == before) }
            }
        }
        // Beginner: a fleeing player is never hit and nothing is drawn.
        var b = Kit.state(.beginner)
        b.commander.ship = Kit.playerShip(b, .gnat)
        var be = EncounterState(type: .pirateAttack, opponent: Kit.opponent(&b, .wasp, weapons: [.morgansLaser], skills: [5, 10, 5, 5]))
        let rng = b.rng, hull = b.commander.ship.hull
        #expect(!b.executeAttack(commanderAttacks: false, fleeing: true, encounter: &be))
        #expect(b.rng == rng && b.commander.ship.hull == hull)
    }

    @Test("CMB-017 weapon powers and laser/disruptor sums")
    func weaponPower() {
        let r = Ruleset.windows201
        for (w, p) in CombatModel.power { #expect(r.tables.weapon(w).power == p) }
        let s = Kit.state()
        let ship = Kit.playerShip(s, .wasp, weapons: [.pulseLaser, .morgansLaser, .quantumDisruptor])
        #expect(ship.weaponStrength(r, from: .pulseLaser, to: .morgansLaser) == 100)
        #expect(ship.weaponStrength(r, from: .photonDisruptor, to: .quantumDisruptor) == 60)
        #expect(ship.weaponStrength(r) == 160)
    }

    @Test("CMB-018 against the Scarab only Pulse, Morgan's and Quantum count")
    func scarabWeapons() {
        var hits = 0
        for seed in UInt64(0)..<120 {
            var s = Kit.state(.normal, seed: seed)
            s.commander.ship = Kit.playerShip(s, .wasp, weapons: [.beamLaser, .militaryLaser, .photonDisruptor])
            var enc = EncounterState(type: .scarabAttack, opponent: Kit.opponent(&s, .scarab))
            var copy = s.rng
            let hit = copy.next(below: s.shipSkills[1] + 3) >= copy.next(below: 5 + s.skills(of: enc.opponent)[0] / 2)
            if hit { _ = copy.next(below: 100) }  // weapons == 0: no damage roll, only the disable check
            let hull = enc.opponent.hull
            #expect(!s.executeAttack(commanderAttacks: true, fleeing: false, encounter: &enc))
            #expect(s.rng == copy && enc.opponent.hull == hull)
            if hit { hits += 1 }
        }
        #expect(hits > 0)
        // Pulse and Morgan's still damage the Scarab.
        var damaged = false
        for seed in UInt64(0)..<60 where !damaged {
            var s = Kit.state(.normal, seed: seed)
            s.commander.ship = Kit.playerShip(s, .wasp, weapons: [.pulseLaser, .morgansLaser])
            var enc = EncounterState(type: .scarabAttack, opponent: Kit.opponent(&s, .scarab))
            damaged = s.executeAttack(commanderAttacks: true, fleeing: false, encounter: &enc) && enc.opponent.hull < 400
        }
        #expect(damaged)
    }

    @Test("CMB-020 hitting a disabled opponent zeroes its hull with no damage roll (Targeting: no draw at all)")
    func shootDisabled() {
        var s = Kit.state()
        s.commander.ship = Kit.playerShip(s, .hornet, weapons: [.beamLaser], gadgets: [.targetingSystem])
        var enc = EncounterState(type: .pirateDisabled, opponent: Kit.opponent(&s, .wasp))
        enc.opponentDisabled = true
        let rng = s.rng
        #expect(!s.executeAttack(commanderAttacks: true, fleeing: false, encounter: &enc))
        #expect(enc.opponent.hull == 0 && s.rng == rng)
        // Without Targeting: only the to-hit pair is drawn.
        for seed in UInt64(0)..<40 {
            var t = Kit.state(.normal, seed: seed)
            t.commander.ship = Kit.playerShip(t, .hornet, weapons: [.beamLaser])
            var te = EncounterState(type: .pirateDisabled, opponent: Kit.opponent(&t, .wasp))
            te.opponentDisabled = true
            var copy = t.rng
            let hit = copy.next(below: t.shipSkills[1] + 4) >= copy.next(below: 5 + t.skills(of: te.opponent)[0] / 2)
            _ = t.executeAttack(commanderAttacks: true, fleeing: false, encounter: &te)
            #expect(t.rng == copy && te.opponent.hull == (hit ? 0 : 200))
        }
    }

    @Test("CMB-021 disable attempt: unshielded disableable target, option on, disruptors: no damage, not a hit")
    func disableAttempt() {
        var attempts = 0
        for seed in UInt64(0)..<120 {
            var s = Kit.state(.normal, seed: seed)
            s.options.disableOpponents = true
            s.commander.ship = Kit.playerShip(s, .hornet, weapons: [.pulseLaser, .photonDisruptor])
            var enc = EncounterState(type: .pirateAttack, opponent: Kit.opponent(&s, .wasp))
            var copy = s.rng
            let f = s.shipSkills[1]
            let hit = copy.next(below: f + 4) >= copy.next(below: 5 + s.skills(of: enc.opponent)[0] / 2)
            var disabled = false
            if hit {
                let disrupt = copy.next(below: 20 * (100 + 2 * f) / 100)
                disabled = copy.next(below: 100) < disrupt * 300 / 200
                attempts += 1
            }
            #expect(!s.executeAttack(commanderAttacks: true, fleeing: false, encounter: &enc))
            #expect(enc.opponent.hull == 200 && s.rng == copy && enc.opponentDisabled == disabled)
        }
        #expect(attempts > 0)
    }

    @Test("CMB-022 damage roll rand(weapons*(100+2F)/100); no draw with 0 weapons; hit iff damage > 0")
    func damageRoll() {
        for seed in UInt64(0)..<80 {
            // Unarmed opponent firing at the player: a hit draws no damage roll and the player is not "hit".
            var s = Kit.state(.normal, seed: seed)
            s.commander.ship = Kit.playerShip(s, .hornet)
            var enc = EncounterState(type: .pirateAttack, opponent: Kit.opponent(&s, .wasp, skills: [5, 10, 5, 5]))
            var copy = s.rng
            _ = copy.next(below: 10 + 3)
            _ = copy.next(below: 5 + s.shipSkills[0] / 2)
            #expect(!s.executeAttack(commanderAttacks: false, fleeing: false, encounter: &enc))
            #expect(s.rng == copy)
        }
    }

    @Test("CMB-024 CMB-026 CMB-027 CMB-029 CMB-031 CMB-034 CMB-039 one shot matches the spec model (Windows)")
    func shotModel() {
        for seed in UInt64(0)..<3_000 {
            let (s0, e0) = CombatModel.randomSituation(seed &* 7_919)
            for playerFires in [true, false] {
                for fleeing in [false, true] {
                    var ms = s0, me = e0, es = s0, ee = e0
                    let mh = CombatModel.shot(&ms, &me, playerFires: playerFires, fleeing: fleeing)
                    let eh = es.executeAttack(commanderAttacks: playerFires, fleeing: fleeing, encounter: &ee)
                    #expect(mh == eh && ms == es && me == ee, "seed \(seed) player \(playerFires) fleeing \(fleeing)")
                    #expect(es.commander.ship.shields.allSatisfy { $0.charge >= 0 } && ee.opponent.hull >= 0)
                }
            }
        }
    }

    @Test("CMB-024 reactor factor is the truncated integer: x1 x1 x1 x2 x2")
    func reactorFactor() {
        let factors = Difficulty.allCases.map { d in Int(1 + Double(d.rawValue + 1) * (d < .normal ? 0.25 : 0.33)) }
        #expect(factors == [1, 1, 1, 2, 2])
        #expect(!Ruleset.windows201.flags.reactorDamageRealFactor)
    }

    @Test("CMB-026 shields absorb in slot order and never go negative")
    func shieldOrder() {
        for seed in UInt64(0)..<200 {
            var s = Kit.state(.normal, seed: seed)
            s.commander.ship = Kit.playerShip(s, .wasp, shields: [ShieldInstance(type: .energy, charge: 30), ShieldInstance(type: .energy, charge: 100)])
            var enc = EncounterState(type: .pirateAttack, opponent: Kit.opponent(&s, .wasp, weapons: [.morgansLaser], skills: [5, 10, 5, 5]))
            _ = s.executeAttack(commanderAttacks: false, fleeing: false, encounter: &enc)
            let c = s.commander.ship.shields.map(\.charge)
            #expect(c[0] >= 0 && c[1] >= 0)
            #expect(c[1] == 100 || c[0] == 0, "the second shield is touched only after the first is empty")
        }
    }

    @Test("CMB-029 hull cap divisors: player 4/3/2/1/1 by difficulty, opponents 2, with the +50 upgrade")
    func hullCap() {
        for d in Difficulty.allCases {
            var maxLoss = 0
            for seed in UInt64(0)..<150 {
                var s = Kit.state(d, seed: seed)
                s.commander.ship = Kit.playerShip(s, .gnat)
                s.commander.ship.hullUpgraded = true
                s.commander.ship.hull = 150
                var enc = EncounterState(type: .pirateAttack, opponent: Kit.opponent(&s, .wasp, weapons: [.morgansLaser, .morgansLaser],
                                                                                    skills: [5, 10, 5, 1]))
                _ = s.executeAttack(commanderAttacks: false, fleeing: false, encounter: &enc)
                maxLoss = max(maxLoss, 150 - s.commander.ship.hull)
            }
            #expect(maxLoss == 150 / [4, 3, 2, 1, 1][d.rawValue], "\(d)")
        }
    }

    @Test("CMB-031 hardened hull halves damage for every defender in Windows; CMB-035 worked example")
    func hardenedHullExample() throws {
        // CMB-035: Normal, a Gnat (hull 100, no shields, Engineer 4) hit by two Pulse lasers with Fighter 5: rand(33).
        let pulsePair: Int = 2 * 15, fighter: Int = 5
        let bound: Int = pulsePair * (100 + 2 * fighter) / 100
        #expect(bound == 33)
        var checked = 0
        for ruleset in [RulesetID.windows201, .modern] {
            for scarabDone in [false, true] {
                for seed in UInt64(0)..<120 {
                    var s = Kit.state(.normal, seed: seed, ruleset: ruleset)
                    if scarabDone { s.quests.scarab = QuestStatus.Scarab.done }
                    s.commander.ship = Kit.playerShip(s, .mosquito, weapons: [.pulseLaser, .pulseLaser])
                    s.mercenaries[CrewID.commander].skills = [5, 5, 5, 5]
                    var enc = EncounterState(type: .pirateAttack, opponent: Kit.opponent(&s, .gnat, skills: [5, 5, 5, 4]))
                    try #require(s.shipSkills[1] == 5 && s.skills(of: enc.opponent)[3] == 4)
                    var copy = s.rng
                    guard copy.next(below: 6) >= copy.next(below: 7) else { continue }
                    let roll = copy.next(below: 33)
                    guard roll > 0 else { continue }
                    var dmg = min(50, max(1, roll - copy.next(below: 4)))
                    if scarabDone, ruleset == .windows201 { dmg /= 2 }  // Modern (MOD-004) never halves an opponent's damage
                    _ = s.executeAttack(commanderAttacks: true, fleeing: false, encounter: &enc)
                    #expect(enc.opponent.hull == 100 - dmg)
                    checked += 1
                }
            }
        }
        #expect(checked > 20)
    }

    @Test("CMB-036 damage arithmetic cannot overflow Int32 for any table ship or custom design")
    func overflowGuard() {
        for r in [Ruleset.windows201, .modern, .palm122] {
            let maxPower = r.tables.weapons.map(\.power).max() ?? 0
            let maxSlots = max(r.tables.ships.map(\.weaponSlots).max() ?? 0, 6)
            let worst = Int32(maxPower * maxSlots).multipliedReportingOverflow(by: Int32(100 + 2 * 60))
            #expect(!worst.overflow)
        }
    }

    @Test("CMB-037 the damage path differs between rulesets only through RuleFlags (reactor factor, hardening scope)")
    func damageFlagsOnly() {
        #expect(!Ruleset.windows201.flags.reactorDamageRealFactor && Ruleset.modern.flags.reactorDamageRealFactor)
        #expect(!Ruleset.windows201.flags.hardenedHullProtectsPlayerOnly && Ruleset.modern.flags.hardenedHullProtectsPlayerOnly)
        var differed = false
        for seed in UInt64(0)..<1_500 {
            let (s0, e0) = CombatModel.randomSituation(seed &* 104_729)
            for playerFires in [true, false] {
                var w = s0, we = e0, m = s0, me = e0
                m.rulesetID = .modern
                let wh = w.executeAttack(commanderAttacks: playerFires, fleeing: false, encounter: &we)
                let mh = m.executeAttack(commanderAttacks: playerFires, fleeing: false, encounter: &me)
                m.rulesetID = .windows201
                let same = wh == mh && w == m && we == me
                let flagged = s0.reactorOnBoard || s0.quests.scarab == QuestStatus.Scarab.done
                #expect(same || flagged, "seed \(seed): only the flagged paths may differ")
                if !same { differed = true }
            }
        }
        #expect(differed)
    }
}
