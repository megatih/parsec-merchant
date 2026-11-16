// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Testing
@testable import ParsecEngine

// docs/specs/CMB.md §9–§15: continuous attack, winning, bounty, scooping, plunder, determinism and the engine API
// (Windows 2.01 rules).
@Suite("Combat spec: auto-repeat, victory, bounty, scoop, plunder, API (CMB)")
struct CombatOutcomeSpecTests {
    typealias Kit = CombatKit

    static func isEscape(_ e: GameEvent) -> Bool { if case .playerEscaped = e { true } else { false } }

    // MARK: §9 Continuous attack

    @Test("CMB-062 continuousAttack and continuousAttackFleeing default to false")
    func continuousDefaults() {
        let o = GameOptions()
        #expect(!o.continuousAttack && !o.continuousAttackFleeing)
    }

    @Test("CMB-064 CMB-065 continuation: attacks on non-fleeing opponents and flights continue; fleeing targets need the option")
    func continuation() {
        var checked = 0
        for seed in UInt64(0)..<1_500 {
            var m = Mix(x: seed)
            var s = CombatModel.bases[2]
            s.rng = RNGState(kind: s.ruleset.rngKind, seed: seed)
            s.options.continuousAttack = true
            s.options.continuousAttackFleeing = m.flip()
            s.commander.ship = Kit.playerShip(s, .wasp, weapons: [.militaryLaser, .militaryLaser, .beamLaser])
            s.commander.ship.hull = 10_000
            var opp = Kit.opponent(&s, .hornet, weapons: [.pulseLaser], skills: [3, 3, 3, 1])
            opp.hull = 150
            let starts: [EncounterType] = [.pirateAttack, .pirateFlee, .pirateSurrender, .traderAttack, .traderFlee]
            var enc = EncounterState(type: starts[m.next(starts.count)], opponent: opp)
            enc.cmdrFleeing = m.flip(3)
            let start = enc.type
            let (result, _) = s.executeRound(&enc)
            guard result == .continue, !enc.opponentDisabled else { continue }
            let fleeingNow = CombatModel.opponentFleeing.contains(enc.type)
            let newlySurrendered = enc.type != start && (enc.type == .pirateSurrender || enc.type == .traderSurrender)
            if enc.cmdrFleeing {
                #expect(enc.continueFleeing && !enc.continueAttacking)
            } else {
                let expected = !fleeingNow || (s.options.continuousAttackFleeing && !newlySurrendered)
                #expect(enc.continueAttacking == expected, "seed \(seed) \(start)->\(enc.type)")
                #expect(!enc.continueFleeing)
            }
            checked += 1
        }
        #expect(checked > 500)
    }

    @Test("CMB-066 the auto-repeat tick needs a continue flag, clears both and runs a round without re-verification")
    func autoRepeat() {
        var e = Kit.engine(.traderAttack) { s in Kit.opponent(&s, .gnat, weapons: [.pulseLaser]) }
        #expect(e.perform(.encounter(.autoRepeat)).rejection == .encounterActionUnavailable)
        for seed in UInt64(0)..<40 {
            for type in [EncounterType.traderAttack, .policeFlee] {
                var a = Kit.engine(type, seed: seed) { s in Kit.opponent(&s, .gnat, weapons: [.pulseLaser]) }
                guard var enc = Kit.encounter(a) else { continue }
                enc.continueAttacking = true
                enc.continueFleeing = true
                a.state.phase = .encounter(enc)
                var cleared = enc
                cleared.continueAttacking = false
                cleared.continueFleeing = false
                var s = a.state
                let (result, events) = s.executeRound(&cleared)
                let record = a.state.commander.policeRecordScore
                let r = a.perform(.encounter(.autoRepeat))
                #expect(r.rejection == nil && r.decision == nil, "no confirmation, no trader re-roll, no police record change")
                #expect(Array(r.events.prefix(events.count)) == events)
                if result == .continue {
                    #expect(a.state.rng == s.rng && Kit.encounter(a) == cleared)
                    #expect(a.state.commander.policeRecordScore == record)
                }
            }
        }
    }

    @Test("CMB-068 stop clears both flags; every other command clears them before acting; a refused command keeps them")
    func interrupt() {
        var e = Kit.engine(.pirateAttack) { s in Kit.opponent(&s, .wasp, weapons: [.pulseLaser]) }
        #expect(e.perform(.encounter(.stop)).rejection == .encounterActionUnavailable)
        guard var enc = Kit.encounter(e) else { Issue.record("no encounter"); return }
        enc.continueAttacking = true
        enc.continueFleeing = true
        e.state.phase = .encounter(enc)
        var stopped = e
        #expect(stopped.perform(.encounter(.stop)).rejection == nil)
        #expect(Kit.encounter(stopped).map { !$0.continueAttacking && !$0.continueFleeing } == true)
        // A refused command (no weapons) leaves the flags alone.
        var refused = e
        refused.state.commander.ship.weapons = []
        guard case var .encounter(re) = refused.state.phase else { return }
        re.continueAttacking = true
        refused.state.phase = .encounter(re)
        #expect(refused.perform(.encounter(.attack)).rejection == .noWeapons)
        #expect(Kit.encounter(refused)?.continueAttacking == true)
        // Flee with the continuous options off: the flags are gone after the round.
        var fled = e
        let r = fled.perform(.encounter(.flee))
        #expect(r.rejection == nil)
        if let after = Kit.encounter(fled) { #expect(!after.continueAttacking && !after.continueFleeing) }
    }

    // MARK: §10 Winning

    struct WinCase {
        var type: EncounterType
        var ship: ShipType
        var kills: Kills
        var record: Int
        var bounty: Bool
    }

    @Test("CMB-070 CMB-077 EncounterWon effects by type, and reputation += shipType/2 + 1")
    func encounterWonEffects() {
        let cases: [WinCase] = [
            WinCase(type: .famousCaptainAttack, ship: .wasp, kills: Kills(pirates: 0, police: 0, traders: 1), record: 0, bounty: false),
            WinCase(type: .dragonflyAttack, ship: .dragonfly, kills: Kills(pirates: 1, police: 0, traders: 0), record: 1, bounty: false),
            WinCase(type: .scarabAttack, ship: .scarab, kills: Kills(pirates: 1, police: 0, traders: 0), record: 1, bounty: false),
            WinCase(type: .pirateAttack, ship: .gnat, kills: Kills(pirates: 1, police: 0, traders: 0), record: 1, bounty: true),
            WinCase(type: .pirateFlee, ship: .wasp, kills: Kills(pirates: 1, police: 0, traders: 0), record: 1, bounty: true),
            WinCase(type: .pirateSurrender, ship: .mantis, kills: Kills(pirates: 1, police: 0, traders: 0), record: 0, bounty: false),
            WinCase(type: .policeAttack, ship: .hornet, kills: Kills(pirates: 0, police: 1, traders: 0), record: -6, bounty: false),
            WinCase(type: .policeFlee, ship: .hornet, kills: Kills(pirates: 0, police: 1, traders: 0), record: -6, bounty: false),
            WinCase(type: .spaceMonsterAttack, ship: .spaceMonster, kills: Kills(pirates: 1, police: 0, traders: 0), record: 1, bounty: false),
            WinCase(type: .traderAttack, ship: .gnat, kills: Kills(pirates: 0, police: 0, traders: 1), record: -4, bounty: false),
            WinCase(type: .traderSurrender, ship: .termite, kills: Kills(pirates: 0, police: 0, traders: 1), record: -4, bounty: false),
        ]
        for c in cases {
            var s = Kit.state(.easy)
            s.commander.reputationScore = 500
            s.newsEvents = [.captAhabAttacked]
            var opp = Kit.opponent(&s, c.ship)
            opp.hull = 0
            var enc = EncounterState(type: c.type, opponent: opp)
            let cash = s.commander.cash
            let bounty = s.bounty(of: opp)
            let events = s.encounterWon(&enc)
            #expect(s.commander.kills == c.kills, "\(c.type)")
            #expect(s.commander.policeRecordScore == c.record, "\(c.type)")
            #expect(s.commander.cash == cash + (c.bounty ? bounty : 0), "\(c.type)")
            let fame = c.type == .famousCaptainAttack ? 100 : 0
            #expect(s.commander.reputationScore == 500 + fame + c.ship.rawValue / 2 + 1, "\(c.type)")
            #expect(events.first == .opponentDestroyed(c.ship))
            switch c.type {
            case .famousCaptainAttack: #expect(s.newsEvents == [.captAhabDestroyed])
            case .dragonflyAttack: #expect(s.quests.dragonfly == QuestStatus.Dragonfly.destroyed)
            case .scarabAttack: #expect(s.quests.scarab == QuestStatus.Scarab.destroyed)
            case .spaceMonsterAttack: #expect(s.quests.spaceMonster == QuestStatus.SpaceMonster.destroyed)
            default: break
            }
        }
        // CMB-077 examples: Gnat +1, Wasp +5, Mantis +7, Scarab +7, Scorpion (disabled) +9.
        #expect([ShipType.gnat, .wasp, .mantis, .scarab, .scorpion].map { $0.rawValue / 2 + 1 } == [1, 5, 7, 7, 9])
        var s = Kit.state()
        s.commander.ship = Kit.playerShip(s, .wasp, weapons: [.pulseLaser], gadgets: [.targetingSystem])
        s.commander.ship.hull = 10_000
        var enc = EncounterState(type: .scorpionAttack, opponent: Kit.opponent(&s, .scorpion))
        enc.opponentDisabled = true
        let rep = s.commander.reputationScore
        let (result, _) = s.executeRound(&enc)
        #expect(result == .normal && s.commander.reputationScore == rep + 9)
    }

    @Test("CMB-071 a destroyed pirate pays the bounty only with record >= -5")
    func bountyCrediting() {
        for record in [-5, -6] {
            var s = Kit.state(.easy)
            s.commander.policeRecordScore = record
            var opp = Kit.opponent(&s, .wasp, weapons: [.pulseLaser])
            opp.hull = 0
            var enc = EncounterState(type: .pirateAttack, opponent: opp)
            let cash = s.commander.cash, b = s.bounty(of: opp)
            let events = s.encounterWon(&enc)
            if record == -5 {
                #expect(s.commander.cash == cash + b && events == [.opponentDestroyed(.wasp), .bountyPaid(b)])
            } else {
                #expect(s.commander.cash == cash && events == [.opponentDestroyed(.wasp)])
            }
        }
    }

    @Test("CMB-073 famous-captain kill: reputation below 300 becomes 300, else +100 (before the per-kill gain)")
    func famousReputation() {
        for (before, after) in [(100, 300), (299, 300), (300, 400), (650, 750)] {
            var s = Kit.state()
            s.commander.reputationScore = before
            var opp = Kit.opponent(&s, .wasp)
            opp.hull = 0
            var enc = EncounterState(type: .famousCaptainAttack, opponent: opp)
            _ = s.encounterWon(&enc)
            #expect(s.commander.reputationScore == after + ShipType.wasp.rawValue / 2 + 1)
        }
    }

    @Test("CMB-074 winning ends the encounter without auto-repeat; a scoop decision is raised in the same step")
    func winningEnds() {
        var won = 0
        for seed in UInt64(0)..<300 where won < 4 {
            var e = Kit.engine(.pirateAttack, difficulty: .easy, seed: seed) { s in
                var o = Kit.opponent(&s, .gnat, skills: [1, 1, 1, 1])
                o.hull = 1
                if seed % 2 == 0 { o.cargo[TradeItemType.ore.rawValue] = 3 }
                return o
            }
            e.state.options.continuousAttack = true
            guard var enc = Kit.encounter(e) else { continue }
            enc.continueAttacking = true
            e.state.phase = .encounter(enc)
            let r = e.perform(.encounter(.attack))
            guard r.events.contains(.opponentDestroyed(.gnat)) else { continue }
            won += 1
            if seed % 2 == 0 {
                #expect(r.decision == .scoop(.ore))
                #expect(Kit.encounter(e).map { !$0.continueAttacking && !$0.continueFleeing } == true)
                _ = e.perform(.resolveScoop(accept: false))
            }
            #expect(Kit.encounter(e) == nil)
        }
        #expect(won == 4)
    }

    @Test("CMB-078 kill counters only increase (wins add; arrest and escape pod keep them)")
    func killCounters() {
        var s = Kit.state()
        s.commander.kills = Kills(pirates: 3, police: 2, traders: 1)
        var opp = Kit.opponent(&s, .gnat)
        opp.hull = 0
        var enc = EncounterState(type: .pirateAttack, opponent: opp)
        _ = s.encounterWon(&enc)
        #expect(s.commander.kills == Kills(pirates: 4, police: 2, traders: 1))
        var arrested = s
        _ = arrested.arrested()
        #expect(arrested.commander.kills == s.commander.kills)
        var pod = s
        pod.commander.ship.escapePod = true
        _ = pod.escapeWithPod()
        #expect(pod.commander.kills == s.commander.kills)
    }

    // MARK: §11 Bounty

    @Test("CMB-079 CMB-080 bounty: (list price + discounted local equipment prices) * (2P+E+3F)/60, /200, /25*25, 25…2500")
    func bountyFormula() {
        for tech in [TechLevel.hiTech, .agricultural] {
            var s = Kit.state()
            s.galaxy.systems[s.commander.currentSystem].techLevel = tech
            s.mercenaries[CrewID.commander].skills = [5, 5, 8, 5]
            s.commander.ship = Kit.playerShip(s, .gnat)
            var opp = Kit.opponent(&s, .hornet, weapons: [.pulseLaser, .morgansLaser], shields: [ShieldInstance(type: .energy, charge: 0)],
                                   skills: [6, 7, 2, 4])
            opp.gadgets = [.autoRepairSystem]
            let t = s.skill(.trader)
            let local = tech == .hiTech
            // Morgan's laser has no buyable tech level, so it never counts; gadgets are not counted.
            let equipment = local ? 2_000 * (100 - t) / 100 + 5_000 * (100 - t) / 100 : 0
            let sk = s.skills(of: opp)
            let price = (100_000 + equipment) * (2 * sk[0] + sk[3] + 3 * sk[1]) / 60
            #expect(s.bounty(of: opp) == max(25, min(2_500, price / 200 / 25 * 25)), "\(tech)")
        }
    }

    @Test("CMB-082 bounty examples: 500, 250, floor 25, cap 2500")
    func bountyExamples() {
        var s = Kit.state()
        func bounty(_ type: ShipType, _ skills: [Int], gadgets: [GadgetType] = []) -> Int {
            var o = Kit.opponent(&s, type, skills: skills)
            o.gadgets = gadgets
            return s.bounty(of: o)
        }
        #expect(bounty(.hornet, [10, 10, 1, 10]) == 500)
        #expect(bounty(.hornet, [5, 5, 1, 5]) == 250)
        #expect(bounty(.flea, [1, 1, 1, 1]) == 25)
        #expect(bounty(.scorpion, [10, 10, 1, 10], gadgets: [.targetingSystem]) == 2_500)
    }

    // MARK: §12 Scooping

    @Test("CMB-083 CMB-084 scoop chance by difficulty and a canister drawn in proportion to the victim's units")
    func scoopRoll() {
        var triggered = Array(repeating: 0, count: 5)
        for seed in UInt64(0)..<600 {
            for d in Difficulty.allCases {
                var s = CombatModel.bases[d.rawValue]
                s.rng = RNGState(kind: s.ruleset.rngKind, seed: seed)
                var m = Mix(x: seed)
                var victim = Ship(type: .hornet, spec: s.ruleset.tables.ship(.hornet))
                victim.cargo = (0..<10).map { _ in m.flip(3) ? m.next(6) : 0 }
                var copy = s.rng
                let lucky = d < .normal || copy.next(below: d.rawValue) == 0
                var expected: TradeItemType?
                let filled = victim.cargo.reduce(0, +)
                if lucky, filled > 0 {
                    let index = copy.next(below: filled)
                    var acc = 0
                    expected = TradeItemType.allCases.first { acc += victim.cargo[$0.rawValue]; return acc > index }
                    triggered[d.rawValue] += 1
                }
                s.scoopRoll(victim)
                #expect(s.pendingScoop == expected && s.rng == copy)
            }
        }
        // 100 % below Normal (whenever there is cargo); roughly 1/2, 1/3, 1/4 above.
        #expect(triggered[0] == triggered[1] && triggered[2] > triggered[3] && triggered[3] > triggered[4])
    }

    func scoopEngine(full: Bool) -> GameEngine {
        var e = Kit.engine(.pirateAttack) { s in Kit.opponent(&s, .gnat) }
        e.state.pendingScoop = .robots
        e.state.pendingEncounterResult = .normal
        e.state.commander.priceCargo = Array(repeating: 0, count: 10)
        if full { e.state.commander.ship.cargo[TradeItemType.water.rawValue] = e.state.commander.ship.cargoBays(e.ruleset) }
        return e
    }

    @Test("CMB-086 a triggered scoop is PendingDecision.scoop; declining leaves it; picking up adds one unit at cost basis 0")
    func scoopDecision() {
        var e = scoopEngine(full: false)
        #expect(e.perform(.encounter(.attack)).rejection == .pendingDecisionFirst)
        var declined = e
        let d = declined.perform(.resolveScoop(accept: false))
        #expect(!d.events.contains(.scooped(.robots)) && declined.state.commander.ship.cargo[9] == 0)
        #expect(Kit.encounter(declined) == nil && declined.state.pendingScoop == nil)
        let r = e.perform(.resolveScoop(accept: true))
        #expect(r.events.first == .scooped(.robots))
        #expect(e.state.commander.ship.cargo[9] == 1 && e.state.commander.priceCargo[9] == 0)
    }

    @Test("CMB-087 with a full hold the player may jettison first; otherwise accepting leaves the canister (scoopNoRoom)")
    func scoopNoRoom() {
        var e = scoopEngine(full: true)
        var left = e
        let r = left.perform(.resolveScoop(accept: true))
        #expect(r.events.first == .scoopNoRoom && left.state.commander.ship.cargo[9] == 0)
        var declined = e
        let d = declined.perform(.resolveScoop(accept: false))
        #expect(!d.events.contains(.scoopNoRoom) && !d.events.contains(.scooped(.robots)))
        // Jettison inside the open decision (ECO-055), then pick up.
        #expect(e.perform(.jettisonCargo(.water, quantity: 1), acknowledging: Kit.yes).rejection == nil)
        #expect(e.state.pendingScoop == .robots)
        let p = e.perform(.resolveScoop(accept: true))
        #expect(p.events.first == .scooped(.robots) && e.state.commander.ship.cargo[9] == 1)
    }

    // MARK: §13 Plunder

    @Test("CMB-089 plunder: offered types, capped transfers, noEmptyBays, cost basis 0, no debt block, jettison inside, plunderDone ends")
    func plunderFlow() {
        let offered = Set(EncounterType.allCases.filter { $0.actions.contains(.plunder) })
        #expect(offered == [.pirateDisabled, .pirateSurrender, .traderDisabled, .traderSurrender])
        var e = Kit.engine(.pirateSurrender) { s in
            var o = Kit.opponent(&s, .gnat)
            o.cargo[TradeItemType.water.rawValue] = 5
            o.cargo[TradeItemType.narcotics.rawValue] = 3
            return o
        }
        e.state.commander.debt = 1_000_000
        e.state.commander.priceCargo = Array(repeating: 0, count: 10)
        let free = e.state.freeCargoBays
        let r = e.perform(.encounter(.plunder))
        #expect(r.decision == .plunder([5, 0, 0, 0, 0, 0, 0, 0, 3, 0]))
        #expect(e.perform(.plunderTake(.water, quantity: 6)).rejection == .invalidQuantity)
        #expect(e.perform(.plunderTake(.furs, quantity: 1)).rejection == .cargoNoneAvailable)
        let t = e.perform(.plunderTake(.water, quantity: 3))
        #expect(t.decision == .plunder([2, 0, 0, 0, 0, 0, 0, 0, 3, 0]))
        #expect(e.state.commander.ship.cargo[0] == 3 && e.state.commander.priceCargo[0] == 0)
        #expect(e.perform(.jettisonCargo(.water, quantity: 1), acknowledging: Kit.yes).rejection == nil)
        // Fill the hold: no bay left.
        e.state.commander.ship.cargo[TradeItemType.ore.rawValue] = e.state.freeCargoBays
        #expect(e.state.freeCargoBays == 0 && free > 0)
        #expect(e.perform(.plunderTake(.narcotics, quantity: 1)).rejection == .noEmptyBays)
        #expect(e.perform(.plunderDone).rejection == nil)
        #expect(Kit.encounter(e) == nil && e.state.pendingPlunder == nil)
    }

    @Test("CMB-091 plunder effects applied when the decision closes, by type")
    func plunderEffects() {
        struct Case { var type: EncounterType; var disabled: Bool; var record: Int; var recordAfter: Int; var kills: Kills; var bounty: Bool }
        let cases = [
            Case(type: .traderSurrender, disabled: false, record: 0, recordAfter: -2, kills: Kills(), bounty: false),
            Case(type: .traderDisabled, disabled: true, record: 0, recordAfter: -2, kills: Kills(pirates: 0, police: 0, traders: 1), bounty: false),
            Case(type: .pirateDisabled, disabled: true, record: -5, recordAfter: -4, kills: Kills(pirates: 1, police: 0, traders: 0), bounty: true),
            Case(type: .pirateDisabled, disabled: true, record: -6, recordAfter: -5, kills: Kills(pirates: 1, police: 0, traders: 0), bounty: false),
            Case(type: .pirateSurrender, disabled: false, record: 0, recordAfter: -1, kills: Kills(), bounty: false),
        ]
        for c in cases {
            var e = Kit.engine(c.type) { s in Kit.opponent(&s, .wasp, weapons: [.beamLaser]) }
            guard var enc = Kit.encounter(e) else { continue }
            enc.opponentDisabled = c.disabled
            e.state.phase = .encounter(enc)
            e.state.commander.policeRecordScore = c.record
            e.state.commander.kills = Kills()
            let rep = e.state.commander.reputationScore, cash = e.state.commander.cash
            let b = e.state.bounty(of: enc.opponent)
            _ = e.perform(.encounter(.plunder))
            #expect(e.state.commander.policeRecordScore == c.record, "nothing happens before the decision closes")
            let r = e.perform(.plunderDone)
            #expect(e.state.commander.policeRecordScore == c.recordAfter, "\(c.type) \(c.record)")
            #expect(e.state.commander.kills == c.kills)
            #expect(e.state.commander.reputationScore == rep + ShipType.wasp.rawValue / 2 + 1)
            if c.bounty {
                #expect(r.events.first == .bountyPaid(b) && e.state.commander.cash == cash + b)
            } else {
                #expect(!r.events.contains(.bountyPaid(b)) && e.state.commander.cash == cash)
            }
        }
    }

    @Test("CMB-093 boarding the Marie Celeste: same plunder decision, no record or reputation change; more narcotics -> justLootedMarie")
    func marieCeleste() {
        for take in [TradeItemType?.none, .water, .narcotics] {
            var e = Kit.engine(.marieCeleste) { s in
                var o = Kit.opponent(&s, .gnat)
                o.cargo[TradeItemType.water.rawValue] = 4
                o.cargo[TradeItemType.narcotics.rawValue] = 4
                return o
            }
            e.state.commander.ship.cargo[TradeItemType.narcotics.rawValue] = 2
            let record = e.state.commander.policeRecordScore, rep = e.state.commander.reputationScore
            #expect(e.perform(.encounter(.board)).decision == .confirm(Confirmation(.boardMarieCeleste)))
            #expect(e.perform(.encounter(.board), acknowledging: Kit.yes).decision == .plunder([4, 0, 0, 0, 0, 0, 0, 0, 4, 0]))
            if let take { _ = e.perform(.plunderTake(take, quantity: 1)) }
            _ = e.perform(.plunderDone)
            #expect(e.state.quests.justLootedMarie == (take == .narcotics), "\(String(describing: take))")
            #expect(e.state.commander.policeRecordScore == record && e.state.commander.reputationScore == rep)
            #expect(Kit.encounter(e) == nil)
        }
    }

    // MARK: §14–§15 Determinism and engine API

    @Test("CMB-096 same state, command and RNG give the same result, events and state")
    func determinism() {
        for seed in UInt64(0)..<30 {
            for action in [EncounterAction.attack, .flee] {
                var a = Kit.engine(.pirateAttack, seed: seed) { s in Kit.opponent(&s, .wasp, weapons: [.beamLaser]) }
                a.state.options.continuousAttack = true
                var b = a
                for _ in 0..<5 where Kit.encounter(a) != nil {
                    let repeating = Kit.encounter(a).map { $0.continueAttacking || $0.continueFleeing } ?? false
                    let cmd: Command = .encounter(repeating ? .autoRepeat : action)
                    let ra = a.perform(cmd), rb = b.perform(cmd)
                    #expect(ra == rb && a.state == b.state)
                }
            }
        }
    }

    @Test("CMB-097 every round emits combatRound first (after playerAttacked/playerFled), then outcome events")
    func roundEvents() {
        for seed in UInt64(0)..<40 {
            for action in [EncounterAction.attack, .flee] {
                var e = Kit.engine(.pirateAttack, seed: seed) { s in Kit.opponent(&s, .wasp, weapons: [.beamLaser]) }
                let r = e.perform(.encounter(action))
                #expect(r.events.first == (action == .attack ? .playerAttacked : .playerFled))
                guard r.events.count > 1, case let .combatRound(round, _, _, playerHull, opponentHull) = r.events[1] else {
                    Issue.record("no combatRound event")
                    continue
                }
                #expect(round == 1)
                if let enc = Kit.encounter(e) {
                    #expect(playerHull == e.state.commander.ship.hull && opponentHull == enc.opponent.hull)
                }
            }
        }
    }

    @Test("CMB-098 encounterPreview is pure and lists each action's rejection or confirmation plus hull/shield percentages")
    func preview() throws {
        var e = Kit.engine(.policeInspect) { s in
            var o = Kit.opponent(&s, .wasp, shields: [ShieldInstance(type: .energy, charge: 25)])
            o.hull = 50
            return o
        }
        e.state.commander.ship.hull = 75
        e.state.commander.ship.shields = [ShieldInstance(type: .energy, charge: 50)]
        let before = e.state
        let p = try #require(e.encounterPreview)
        #expect(e.state == before)
        #expect(p.actions.map(\.action) == [.attack, .flee, .submit, .bribe])
        #expect(p.actions[0].confirmation == Confirmation(.submitWithNothingIllegal))
        #expect(p.actions[1].confirmation == Confirmation(.fleeInspection))
        #expect(p.actions[2].rejection == nil && p.actions[2].confirmation == nil)
        #expect(p.playerHullPercent == 50 && p.playerShieldPercent == 50)
        #expect(p.opponentHullPercent == 25 && p.opponentShieldPercent == 25)
        e.state.commander.ship.weapons = []
        let q = try #require(e.encounterPreview)
        #expect(q.actions[0].rejection == .noWeapons && !q.actions[0].enabled)
    }

    @Test("CMB-099 combat CommandError cases and typed combat events")
    func combatErrors() throws {
        var e = Kit.engine(.scorpionAttack) { s in Kit.opponent(&s, .scorpion) }
        #expect(e.perform(.encounter(.attack)).rejection == .noDisruptors)
        e.state.commander.ship.weapons = []
        #expect(e.perform(.encounter(.attack)).rejection == .noWeapons)
        var m = Kit.engine(.pirateAttack) { s in Kit.opponent(&s, .mantis) }
        m.state.commander.ship.weapons = [.photonDisruptor]
        #expect(m.perform(.encounter(.attack)).rejection == .noLasers)
        #expect(m.perform(.encounter(.submit)).rejection == .encounterActionUnavailable)
        m.state.pendingPlunder = PlunderOffer(victimCargo: Array(repeating: 0, count: 10), marieCeleste: false)
        #expect(m.perform(.encounter(.flee)).rejection == .pendingDecisionFirst)
        // The combat events are typed values (no strings) and round-trip through Codable.
        let events: [GameEvent] = [.combatRound(round: 1, playerHit: true, opponentHit: false, playerHull: 3, opponentHull: 4),
                                   .opponentDisabled(.gnat), .encounterChanged(.pirateFlee), .playerEscaped(wasHit: true),
                                   .opponentEscaped, .opponentDestroyed(.gnat), .bountyPaid(250), .bothDestroyed, .playerDestroyed,
                                   .scooped(.ore), .scoopNoRoom]
        let decoded = try JSONDecoder().decode([GameEvent].self, from: JSONEncoder().encode(events))
        #expect(decoded == events)
    }
}
