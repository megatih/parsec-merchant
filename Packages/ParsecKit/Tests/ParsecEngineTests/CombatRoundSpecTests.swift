// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecEngine

// docs/specs/CMB.md §6–§8: disabling, round outcome and the opponent's state update (Windows 2.01 rules).
@Suite("Combat spec: disabling, outcome, state update (CMB)")
struct CombatRoundSpecTests {
    typealias Kit = CombatKit

    // MARK: §6 Disabling

    @Test("CMB-038 disableable: every non-player ship except Bottle, Mantis and Space Monster")
    func disableableShips() {
        let s = Kit.state()
        for t in ShipType.allCases where t != .custom {
            let ship = Ship(type: t, spec: s.ruleset.tables.ship(t))
            #expect(s.disableable(ship) == ![.bottle, .mantis, .spaceMonster].contains(t), "\(t)")
        }
    }

    @Test("CMB-039 the disable check draws rand(100) after every player shot that reached the damage stage")
    func disableDrawAlways() {
        // Lasers only (disrupt == 0): a damaging hit on a disableable opponent still consumes the rand(100).
        var checked = 0
        for seed in UInt64(0)..<120 {
            var s = Kit.state(.normal, seed: seed)
            s.commander.ship = Kit.playerShip(s, .hornet, weapons: [.pulseLaser])
            var enc = EncounterState(type: .pirateAttack, opponent: Kit.opponent(&s, .wasp, skills: [5, 5, 5, 3]))
            var copy = s.rng
            guard copy.next(below: s.shipSkills[1] + 4) >= copy.next(below: 5 + s.skills(of: enc.opponent)[0] / 2) else { continue }
            let roll = copy.next(below: 15 * (100 + 2 * s.shipSkills[1]) / 100)
            if roll > 0 { _ = copy.next(below: 3) }
            _ = copy.next(below: 100)
            _ = s.executeAttack(commanderAttacks: true, fleeing: false, encounter: &enc)
            #expect(s.rng == copy && !enc.opponentDisabled)
            checked += 1
        }
        #expect(checked > 0)
    }

    @Test("CMB-040 disableOpponents defaults off; the disruptor share can still disable with the option off")
    func disruptorShareDisables() {
        #expect(GameOptions().disableOpponents == false)
        var disabled = false
        for seed in UInt64(0)..<400 where !disabled {
            var s = Kit.state(.normal, seed: seed)
            s.commander.ship = Kit.playerShip(s, .wasp, weapons: [.pulseLaser, .quantumDisruptor, .quantumDisruptor])
            var enc = EncounterState(type: .pirateAttack, opponent: Kit.opponent(&s, .gnat, skills: [5, 5, 5, 1]))
            _ = s.executeAttack(commanderAttacks: true, fleeing: false, encounter: &enc)
            disabled = enc.opponentDisabled && enc.opponent.hull > 0
        }
        #expect(disabled)
    }

    @Test("CMB-043 a disabled opponent stays disabled and never fires")
    func disabledStays() {
        for seed in UInt64(0)..<50 {
            var s = Kit.state(.normal, seed: seed)
            s.commander.ship = Kit.playerShip(s, .hornet, weapons: [.pulseLaser])
            var enc = EncounterState(type: .pirateDisabled, opponent: Kit.opponent(&s, .wasp, weapons: [.morgansLaser], skills: [5, 10, 5, 5]))
            enc.opponentDisabled = true
            let hull = s.commander.ship.hull
            for _ in 0..<3 {
                _ = s.executeRound(&enc)
                #expect(enc.opponentDisabled && s.commander.ship.hull == hull && enc.type == .pirateDisabled)
            }
        }
    }

    // MARK: §7–§8 Outcome and state update

    @Test("CMB-010 CMB-044 CMB-046 CMB-049 CMB-050 CMB-053 CMB-054 CMB-094 a full round matches the spec model, draw for draw")
    func roundModel() {
        var outcomes: [String: Int] = [:]
        for seed in UInt64(0)..<4_000 {
            let (s0, e0) = CombatModel.randomSituation(seed)
            var es = s0, ee = e0
            let model = CombatModel.round(s0, e0)
            let (result, events) = es.executeRound(&ee)
            #expect(result == model.result, "seed \(seed)")
            if model.won {
                #expect(ee.opponent.hull <= 0 && ee.opponent == model.enc.opponent && es.commander.ship == model.state.commander.ship)
                #expect(events.first == model.events.first)
            } else {
                #expect(es == model.state && ee == model.enc && events == model.events, "seed \(seed)")
            }
            outcomes["\(result)\(model.won ? "-won" : "")", default: 0] += 1
        }
        #expect(outcomes.count == 5, "\(outcomes)")
    }

    @Test("CMB-044 player destroyed: escape pod, mutual destruction or player destroyed")
    func playerDestroyed() {
        var seen: Set<String> = []
        for seed in UInt64(0)..<600 where seen.count < 3 {
            var s = Kit.state(.impossible, seed: seed)
            s.commander.ship = Kit.playerShip(s, .gnat, weapons: [.morgansLaser])
            s.commander.ship.hull = 1
            s.commander.ship.escapePod = seed % 3 == 0
            s.mercenaries[CrewID.commander].skills = [1, 10, 1, 1]
            var opp = Kit.opponent(&s, .gnat, weapons: [.morgansLaser], skills: [1, 10, 1, 1])
            opp.hull = 1
            var enc = EncounterState(type: .pirateAttack, opponent: opp)
            let (result, events) = s.executeRound(&enc)
            guard s.commander.ship.hull <= 0 else { continue }
            if s.commander.ship.escapePod {
                #expect(result == .escapePod)
                seen.insert("pod")
            } else {
                #expect(result == .killed)
                #expect(events.last == (enc.opponent.hull <= 0 ? .bothDestroyed : .playerDestroyed))
                seen.insert(enc.opponent.hull <= 0 ? "both" : "player")
            }
        }
        #expect(seen == ["pod", "both", "player"])
    }

    @Test("CMB-046 CMB-047 a disabled non-special opponent: update, continue, no escape or auto-repeat; shooting it to 0 wins nothing")
    func disabledOutcome() {
        var s = Kit.state()
        s.options.continuousAttack = true
        s.commander.ship = Kit.playerShip(s, .hornet, weapons: [.beamLaser], gadgets: [.targetingSystem])
        var enc = EncounterState(type: .pirateDisabled, opponent: Kit.opponent(&s, .wasp))
        enc.opponentDisabled = true
        enc.oppFleeing = true
        let kills = s.commander.kills, record = s.commander.policeRecordScore, cash = s.commander.cash
        var copy = s.rng
        _ = copy.next(below: 100)  // the update draw only: Targeting auto-hit, no escape checks
        let (result, events) = s.executeRound(&enc)
        #expect(result == .continue && s.rng == copy)
        #expect(enc.opponent.hull == 0 && enc.type == .pirateDisabled && !enc.oppFleeing)
        #expect(!enc.continueAttacking && !enc.continueFleeing)
        #expect(s.commander.kills == kills && s.commander.policeRecordScore == record && s.commander.cash == cash)
        #expect(events.last == .opponentDisabled(.wasp))
    }

    @Test("CMB-049 Beginner: a fleeing player always escapes and the round draws nothing")
    func beginnerEscape() {
        var s = Kit.state(.beginner)
        s.commander.ship = Kit.playerShip(s, .gnat)
        var enc = EncounterState(type: .pirateAttack, opponent: Kit.opponent(&s, .wasp, weapons: [.morgansLaser]))
        enc.cmdrFleeing = true
        let rng = s.rng
        let (result, events) = s.executeRound(&enc)
        #expect(result == .normal && s.rng == rng)
        #expect(events.last == .playerEscaped(wasHit: false))
    }

    @Test("CMB-052 an escape ends the encounter, leaves no auto-repeat and keeps a special ship's damage")
    func escapeEnds() {
        var found = false
        for seed in UInt64(0)..<300 where !found {
            var e = Kit.engine(.spaceMonsterAttack, difficulty: .easy, seed: seed) { s in s.specialShips.spaceMonster }
            e.state.commander.ship.weapons = [.morgansLaser, .morgansLaser, .morgansLaser]
            e.state.commander.ship.hull = 10_000
            e.state.mercenaries[CrewID.commander].skills = [10, 10, 5, 5]
            _ = e.perform(.encounter(.attack))
            guard let enc = Kit.encounter(e), enc.opponent.hull < 400 else { continue }
            #expect(e.state.specialShips.spaceMonster.hull == enc.opponent.hull, "damage persists on the shared ship")
            // Now flee until the player escapes.
            for _ in 0..<40 where Kit.encounter(e) != nil {
                let r = e.perform(.encounter(.flee))
                if r.events.contains(where: { if case .playerEscaped = $0 { true } else { false } }) { found = true }
                if Kit.encounter(e) != nil { #expect(!found) }
            }
            if found {
                #expect(e.state.specialShips.spaceMonster.hull < 500)
                #expect(e.state.encounterTransit == nil)
            }
        }
        #expect(found)
    }

    @Test("CMB-054 CMB-055 CMB-056 CMB-057 CMB-058 opponent state update table")
    func updateTable() {
        let types: [EncounterType] = [.pirateAttack, .pirateFlee, .pirateSurrender, .policeAttack, .policeFlee, .traderAttack,
                                      .traderFlee, .traderSurrender, .famousCaptainAttack, .dragonflyAttack, .scarabAttack,
                                      .spaceMonsterAttack, .policeSurrender, .marieCelestePolice, .pirateDisabled]
        let hulls = [100, 95, 89, 80, 66, 60, 49, 30]
        let base = Kit.state()
        var n = 0
        for type in types {
            for ship in [ShipType.wasp, .mantis] {
                for oppHull in hulls {
                    for myHull in hulls {
                        for disabled in [false, true] {
                            var s = base
                            s.rng = RNGState(kind: base.ruleset.rngKind, seed: UInt64(n))
                            n += 1
                            s.commander.ship.hull = myHull
                            var opp = Kit.opponent(&s, ship)
                            opp.hull = oppHull
                            var enc = EncounterState(type: type, opponent: opp)
                            enc.opponentDisabled = disabled
                            var ms = s, me = enc
                            CombatModel.update(&ms, &me, prevPlayer: 100, prevOpp: 100)
                            s.updateEncounterType(prevCmdrHull: 100, prevOppHull: 100, encounter: &enc)
                            #expect(enc.type == me.type && s.rng == ms.rng, "\(type) \(ship) \(oppHull) \(myHull) \(disabled)")
                        }
                    }
                }
            }
        }
        // The draw happens even when nothing can change.
        var s = Kit.state()
        var enc = EncounterState(type: .pirateAttack, opponent: Kit.opponent(&s, .gnat))
        var copy = s.rng
        _ = copy.next(below: 100)
        s.updateEncounterType(prevCmdrHull: s.commander.ship.hull, prevOppHull: enc.opponent.hull, encounter: &enc)
        #expect(s.rng == copy && enc.type == .pirateAttack)
    }

    @Test("CMB-061 a stance change after a round emits encounterChanged with the new type")
    func stanceChangeEvent() {
        var seen = false
        for seed in UInt64(0)..<3_000 {
            let (s0, e0) = CombatModel.randomSituation(seed)
            var s = s0, enc = e0
            let start = enc.type
            let (result, events) = s.executeRound(&enc)
            guard result == .continue, !enc.opponentDisabled else { continue }
            if enc.type != start {
                #expect(events.last == .encounterChanged(enc.type))
                seen = true
            } else {
                #expect(!events.contains { if case .encounterChanged = $0 { true } else { false } })
            }
        }
        #expect(seen)
    }
}
