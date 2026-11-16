// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Testing
@testable import ParsecEngine

@Suite("ENC §7: engine API")
struct EncounterAPITests {
    @Test("ENC-180 Command.encounter takes the classic actions plus autoRepeat and resolve; wrong phase and open decisions are rejected")
    func command() {
        #expect(EncounterAction.allCases == [.attack, .flee, .surrender, .bribe, .submit, .yield, .ignore, .plunder, .trade, .board, .drink,
                                             .meet, .stop, .autoRepeat, .resolve])
        var docked = EncSpec.engine()
        for action in EncounterAction.allCases {
            #expect(docked.perform(.encounter(action)).rejection == .notAllowedInPhase)
        }
        var p = EncSpec.encounter(.pirateSurrender, opponent: EncSpec.opponent(.gnat, cargo: EncSpec.cargo([(.water, 2)])))
        _ = p.perform(.encounter(.plunder))
        #expect(p.perform(.encounter(.attack)).rejection == .pendingDecisionFirst)
    }

    @Test("ENC-181 a missing consent returns .confirm with no state (or RNG) change; several consents are asked in source order")
    func twoPhase() {
        var t = EncSpec.encounter(.traderBuy)
        let before = t.state
        let r = t.perform(.encounter(.attack))
        #expect(r.decision == .confirm(ParsecEngine.Confirmation(.attackTrader, amounts: [-5])) && r.events.isEmpty && t.state == before)
        var e = EncSpec.encounter(.policeInspect)
        #expect(e.perform(.encounter(.attack)).decision == .confirm(ParsecEngine.Confirmation(.submitWithNothingIllegal)))
        #expect(e.perform(.encounter(.attack), acknowledging: [.attackPolice]).decision == .confirm(ParsecEngine.Confirmation(.submitWithNothingIllegal)))
        let second = e.perform(.encounter(.attack), acknowledging: [.submitWithNothingIllegal])
        #expect(second.decision == .confirm(ParsecEngine.Confirmation(.attackPolice, amounts: [-33])))
        let done = e.perform(.encounter(.attack), acknowledging: [.submitWithNothingIllegal, .attackPolice])
        #expect(done.events.first == .playerAttacked && e.state.commander.policeRecordScore == -33)
    }

    @Test("ENC-182 encounter commands raise exactly the §7 WarningIDs with the listed amounts; no takeMarieCargo or nothingIllegal")
    func warnings() throws {
        func ask(_ type: EncounterType, _ action: EncounterAction, with adjust: (inout GameState) -> Void = { _ in },
                 opponent: ((GameState) -> Ship)? = nil, ack: Set<WarningID> = []) -> ParsecEngine.Confirmation? {
            var e = EncSpec.encounter(type, with: adjust, opponent: opponent)
            if case let .confirm(c) = e.perform(.encounter(action), acknowledging: ack).decision { return c }
            return nil
        }
        let wild: (inout GameState) -> Void = { s in s.commander.ship.crew[1] = CrewID.wild }
        let narc: (inout GameState) -> Void = { s in s.commander.ship.cargo[8] = 2 }
        #expect(ask(.policeIgnore, .attack) == ParsecEngine.Confirmation(.attackPolice, amounts: [-33]))
        #expect(ask(.traderIgnore, .attack) == ParsecEngine.Confirmation(.attackTrader, amounts: [-5]))
        #expect(ask(.captainHuie, .attack, opponent: EncSpec.opponent(.wasp)) == ParsecEngine.Confirmation(.attackCaptain))
        #expect(ask(.policeInspect, .attack) == ParsecEngine.Confirmation(.submitWithNothingIllegal))
        #expect(ask(.policeInspect, .bribe) == ParsecEngine.Confirmation(.submitWithNothingIllegal))
        #expect(ask(.policeInspect, .flee) == ParsecEngine.Confirmation(.fleeInspection))
        #expect(ask(.marieCelestePolice, .flee) == ParsecEngine.Confirmation(.fleeMariePolice))
        #expect(ask(.policeAttack, .surrender) == ParsecEngine.Confirmation(.surrenderToPolice))
        #expect(ask(.marieCelestePolice, .yield, with: wild) == ParsecEngine.Confirmation(.surrenderToPolice))
        let bribe = try #require(EncSpec.encounter(.policeInspect, with: narc).state.bribeAmount)
        #expect(ask(.policeInspect, .bribe, with: narc) == ParsecEngine.Confirmation(.bribe, amounts: [bribe]))
        #expect(ask(.policeInspect, .submit, with: narc) == ParsecEngine.Confirmation(.submitInspection))
        #expect(ask(.marieCelestePolice, .yield) == ParsecEngine.Confirmation(.submitInspection))
        let artifact = ask(.pirateAttack, .surrender, with: { s in s.quests.artifact = 1 }, opponent: EncSpec.opponent(.mantis))
        #expect(artifact == ParsecEngine.Confirmation(.surrenderArtifact))
        #expect(ask(.bottleOld, .drink) == ParsecEngine.Confirmation(.drinkTonic))
        #expect(ask(.marieCeleste, .board) == ParsecEngine.Confirmation(.boardMarieCeleste))
        #expect(ask(.captainConrad, .meet) == ParsecEngine.Confirmation(.meetCaptain))
        // Actions with no consent at all.
        #expect(ask(.pirateAttack, .surrender) == nil && ask(.pirateIgnore, .ignore) == nil && ask(.policeInspect, .submit) == nil)
        let names = Set(WarningID.allCases.map(\.rawValue))
        #expect(!names.contains("takeMarieCargo") && !names.contains("nothingIllegal"))
    }

    @Test("ENC-183 encounter CommandErrors, each leaving state and RNG unchanged")
    func errors() {
        func reject(_ type: EncounterType, _ action: EncounterAction, with adjust: (inout GameState) -> Void = { _ in },
                    opponent: ((GameState) -> Ship)? = nil) -> CommandError? {
            var e = EncSpec.encounter(type, with: adjust, opponent: opponent)
            let before = e.state
            let r = e.perform(.encounter(action), acknowledging: EncSpec.yes)
            #expect(e.state == before, "\(type) \(action)")
            return r.rejection
        }
        #expect(reject(.bottleGood, .attack) == .encounterActionUnavailable)
        #expect(reject(.pirateAttack, .attack) { s in s.commander.ship.weapons = [] } == .noWeapons)
        #expect(reject(.pirateAttack, .attack, with: { s in s.commander.ship.weapons = [.photonDisruptor] }, opponent: EncSpec.opponent(.mantis)) == .noLasers)
        #expect(reject(.scorpionAttack, .attack, opponent: EncSpec.opponent(.scorpion)) == .noDisruptors)
        #expect(reject(.marieCelestePolice, .bribe) == .bribeNotAccepted)
        #expect(reject(.policeInspect, .bribe) { s in s.galaxy.systems[s.warpSystem].politics = .military } == .bribeNotPossible)
        #expect(reject(.policeInspect, .bribe) { s in s.commander.cash = 0 } == .insufficientFunds)
        #expect(reject(.policeAttack, .surrender) { s in s.commander.policeRecordScore = -150 } == .surrenderRefused)
        #expect(reject(.pirateAttack, .surrender) { s in s.commander.ship.crew[2] = CrewID.princess } == .surrenderPrincess)
    }

    @Test("ENC-184 events: one encounterStarted per shown encounter, encounterChanged on type changes, outcome events in the same StepResult")
    func events() throws {
        var e = EncSpec.engine { s in s.options.alwaysIgnoreTraders = false }
        func starts(_ evs: [GameEvent]) -> Int { evs.filter { if case .encounterStarted = $0 { true } else { false } }.count }
        var shown = 0
        for w in 0..<25 {
            e.state.commander.ship.fuel = e.state.commander.ship.fuelTanks(e.ruleset)
            e.state.commander.cash = max(e.state.commander.cash, 20_000)
            let dest = e.state.destinations
            try #require(!dest.isEmpty)
            _ = e.perform(.selectTarget(dest[(w * 7) % dest.count]))
            var evs = e.perform(.warp).events
            while true {
                let inEncounter = EncSpec.current(e) != nil
                #expect(starts(evs) == (inEncounter ? 1 : 0))
                guard let enc = EncSpec.current(e) else { break }
                shown += 1
                if case let .encounterStarted(type, opp, clicks, _) = evs.last {
                    #expect(type == enc.type && opp == enc.opponent.type && clicks == enc.clicks)
                }
                evs = e.finishEncounter(.normal)
            }
        }
        #expect(shown > 3)
        var b = EncSpec.encounter(.policeInspect) { s in s.commander.cash = 50_000 }
        let amount = try #require(b.state.bribeAmount)
        let r = b.perform(.encounter(.bribe), acknowledging: EncSpec.yes)
        #expect(r.events.first == .bribed(amount) && r.events.contains(.arrived(system: b.state.warpSystem)))
    }

    @Test("ENC-185 EncounterState and the trip flags are Codable state; a save made mid-encounter resumes identically")
    func codable() throws {
        var e = EncSpec.encounter(.pirateAttack) { s in s.raided = true; s.inspected = true; s.litterWarning = true }
        var enc = try #require(EncSpec.current(e))
        enc.round = 3
        enc.cmdrHit = true
        enc.oppHit = true
        enc.oppFleeingPrev = true
        enc.opponentDisabled = false
        enc.forceContinuous = true
        e.state.phase = .encounter(enc)
        let data = try JSONEncoder().encode(e.state)
        let decoded = try JSONDecoder().decode(GameState.self, from: data)
        #expect(decoded == e.state)
        var f = GameEngine(state: decoded)
        let r1 = e.perform(.encounter(.attack))
        let r2 = f.perform(.encounter(.attack))
        #expect(r1 == r2 && e.state == f.state)
    }

    @Test("ENC-186 the encounter preview is pure: type, badge, ships' hull/shield %, per-action availability, default, stop/auto-repeat")
    func preview() throws {
        var e = EncSpec.encounter(.policeIgnore) { s in
            s.commander.ship.hull = 75
            s.commander.ship.shields = [ShieldInstance(type: .energy, charge: 25)]
        }
        let before = e.state
        let p = try #require(e.encounterPreview)
        #expect(e.state == before, "preview changes nothing, RNG included")
        #expect(p.type == .policeIgnore && p.badge == .police && p.opponentType == .gnat)
        #expect(p.playerHullPercent == 50 && p.playerShieldPercent == 25 && p.opponentHullPercent == 100 && p.opponentShieldPercent == 0)
        #expect(p.actions.map(\.action) == [.attack, .ignore])
        #expect(p.actions[0].confirmation == ParsecEngine.Confirmation(.attackPolice, amounts: [-33]) && p.actions[0].enabled)
        #expect(p.actions[1].enabled && p.actions[1].confirmation == nil)
        #expect(p.defaultAction == .ignore && !p.canStop && !p.canAutoRepeat)
        e.state.commander.ship.weapons = []
        let unarmed = try #require(e.encounterPreview)
        #expect(unarmed.actions[0].rejection == .noWeapons && !unarmed.actions[0].enabled)
        var b = EncSpec.encounter(.marieCelestePolice)
        let bp = try #require(b.encounterPreview)
        #expect(bp.actions.first { $0.action == .bribe }?.rejection == .bribeNotAccepted)
        // No RNG state or opponent crew skills are exposed.
        let labels = Mirror(reflecting: bp).children.compactMap(\.label)
        #expect(!labels.contains { $0.lowercased().contains("rng") || $0.lowercased().contains("skill") })
        #expect(b.perform(.encounter(.ignore)).rejection == .encounterActionUnavailable, "customs cannot be ignored")
        #expect(EncSpec.engine().encounterPreview == nil)
    }

    @Test("ENC-187 auto-repeat: flags set after a continuing round per the continuous options; autoRepeat needs a flag and runs a bare round")
    func autoRepeat() throws {
        var idle = EncSpec.encounter(.pirateAttack)
        #expect(idle.perform(.encounter(.autoRepeat)).rejection == .encounterActionUnavailable)
        var checked = 0
        for seed in UInt64(1)...200 {
            for (cont, contFleeing, flee) in [(true, false, false), (true, true, false), (false, true, false), (true, false, true)] {
                var e = EncSpec.engine(seed: seed) { s in
                    s.options.continuousAttack = cont
                    s.options.continuousAttackFleeing = contFleeing
                    s.commander.ship.shields = [ShieldInstance(type: .reflective, charge: 200)]
                }
                EncSpec.enter(&e, .pirateAttack)
                _ = e.perform(.encounter(flee ? .flee : .attack))
                guard let enc = EncSpec.current(e), e.state.pendingScoop == nil else { continue }
                checked += 1
                let expected = cont && (enc.cmdrFleeing || !enc.oppFleeing
                    || (contFleeing && (enc.type == .pirateAttack || (enc.type != .pirateSurrender && enc.type != .traderSurrender))))
                #expect(enc.continueFleeing == (expected && flee) && enc.continueAttacking == (expected && !flee), "seed \(seed)")
                if enc.continueAttacking || enc.continueFleeing {
                    var model = e
                    var bare = enc
                    bare.continueAttacking = false
                    bare.continueFleeing = false
                    _ = model.runRound(&bare, events: [])
                    _ = e.perform(.encounter(.autoRepeat))
                    #expect(e.state == model.state, "seed \(seed): autoRepeat clears the flags and runs one round with the current cmdrFleeing")
                }
            }
        }
        #expect(checked > 100)
        // Any other action clears both flags first.
        var f = EncSpec.encounter(.pirateAttack)
        var enc = try #require(EncSpec.current(f))
        enc.continueAttacking = true
        f.state.phase = .encounter(enc)
        _ = f.perform(.encounter(.flee))
        if let after = EncSpec.current(f) { #expect(!after.continueAttacking && !after.continueFleeing) }
    }

    @Test("ENC-190 resolve = attack with forceContinuous: same state and RNG as Attack then autoRepeat with both options on")
    func resolve() {
        var compared = 0
        for seed in UInt64(1)...60 {
            let setup: (inout GameState) -> Void = { s in s.commander.ship.shields = [ShieldInstance(type: .reflective, charge: 200)] }
            var a = EncSpec.engine(seed: seed, setup)
            a.state.options.continuousAttack = true
            a.state.options.continuousAttackFleeing = true
            EncSpec.enter(&a, .pirateAttack)
            var b = EncSpec.engine(seed: seed, setup)
            EncSpec.enter(&b, .pirateAttack)
            _ = a.perform(.encounter(.attack))
            let rb = b.perform(.encounter(.resolve))
            #expect(rb.events.first == .playerAttacked)
            for _ in 0..<2 {
                if let x = EncSpec.current(a), x.continueAttacking { _ = a.perform(.encounter(.autoRepeat)) }
                if let y = EncSpec.current(b), y.continueAttacking { _ = b.perform(.encounter(.autoRepeat)) }
            }
            if var y = EncSpec.current(b) {
                #expect(y.forceContinuous)
                y.forceContinuous = false
                b.state.phase = .encounter(y)
            }
            b.state.options = a.state.options
            #expect(a.state == b.state, "seed \(seed)")
            compared += 1
        }
        #expect(compared == 60)
    }

    @Test("ENC-191 an open plunder, trade or scoop decision only accepts its resolving command; resolving returns to or ends the encounter")
    func pendingDecisions() throws {
        let hold = EncSpec.cargo([(.water, 4)])
        var p = EncSpec.encounter(.traderSurrender, opponent: EncSpec.opponent(.gnat, cargo: hold))
        _ = p.perform(.encounter(.plunder))
        #expect(p.perform(.encounter(.ignore)).rejection == .pendingDecisionFirst)
        #expect(p.perform(.resolveScoop(accept: true)).rejection != nil)
        #expect(p.perform(.resolveTradeInOrbit(quantity: 0)).rejection != nil)
        #expect(p.perform(.buyCargo(.water, quantity: 1)).rejection != nil)
        let pd = p.perform(.plunderDone)
        #expect(EncSpec.endedNormally(p, pd))

        var t = EncSpec.encounter(.traderSell, with: { s in setMarket(&s); s.commander.cash = 10_000 }, opponent: EncSpec.opponent(.gnat, cargo: hold))
        _ = t.perform(.encounter(.trade))
        #expect(t.perform(.encounter(.attack)).rejection == .pendingDecisionFirst)
        #expect(t.perform(.plunderDone).rejection != nil && t.perform(.resolveScoop(accept: false)).rejection != nil)
        let td = t.perform(.resolveTradeInOrbit(quantity: 0))
        #expect(EncSpec.endedNormally(t, td))

        var s = EncSpec.encounter(.pirateAttack)
        s.state.pendingScoop = .ore
        s.state.pendingEncounterResult = .normal
        #expect(s.perform(.encounter(.attack)).rejection == .pendingDecisionFirst)
        #expect(s.perform(.plunderTake(.ore, quantity: 1)).rejection != nil && s.perform(.plunderDone).rejection != nil)
        let done = s.perform(.resolveScoop(accept: true))
        #expect(done.events.contains(.scooped(.ore)) && EncSpec.endedNormally(s, done))
    }

    @Test("ENC-192 fuzz invariants: non-empty action set, live opponent, disabled ⇒ disabled type or quest ship, no pirates after a raid")
    func invariants() {
        var encounters = 0, raids = 0
        for game in 0..<40 {
            var e = GameEngine(config: NewGameConfig(commanderName: "Fuzz", difficulty: Difficulty(rawValue: game % 5) ?? .normal,
                                                     ruleset: .windows201, seed: UInt64(game + 11)))
            e.state.options.alwaysIgnoreTraders = false
            var r = Xoshiro256StarStar(seed: UInt64(game) &* 31 &+ 7)
            var raided = false
            for step in 0..<400 {
                if case .gameOver = e.state.phase { break }
                let res = e.perform(Self.pick(e.state, &r), acknowledging: EncSpec.yes)
                for ev in res.events {
                    switch ev {
                    case .departed: raided = false
                    case .looted, .blackmailed:
                        raided = true
                        raids += 1
                    case let .encounterStarted(type, opp, _, _):
                        encounters += 1
                        let pirate = [EncounterType.pirateAttack, .pirateIgnore, .pirateFlee].contains(type)
                        #expect(!(raided && pirate && opp != .mantis), "game \(game) step \(step): pirate after a raid")
                    default: break
                    }
                }
                guard let enc = EncSpec.current(e) else { continue }
                #expect(!enc.type.actions.isEmpty)
                #expect(enc.opponent.hull > 0 || e.state.pendingScoop != nil, "game \(game) step \(step): destroyed opponent")
                let disabledTypes: [EncounterType] = [.pirateDisabled, .policeDisabled, .traderDisabled, .famousCaptDisabled]
                #expect(!enc.opponentDisabled || disabledTypes.contains(enc.type) || [.dragonfly, .scarab, .scorpion].contains(enc.opponent.type))
            }
        }
        #expect(encounters > 100 && raids > 3)
    }

    /// Fuzz command choice (own RNG): surrender is favoured so that raids happen.
    static func pick(_ s: GameState, _ r: inout Xoshiro256StarStar) -> Command {
        if s.pendingScoop != nil { return .resolveScoop(accept: true) }
        if s.pendingPlunder != nil { return r.next(below: 2) == 0 ? .plunderDone : .plunderTake(.water, quantity: 1) }
        if s.pendingOrbitTrade != nil { return .resolveTradeInOrbit(quantity: 0) }
        if case let .encounter(enc) = s.phase {
            if enc.type.actions.contains(.surrender), r.next(below: 2) == 0 { return .encounter(.surrender) }
            var actions = enc.type.actions + [.resolve]
            if enc.continueAttacking || enc.continueFleeing { actions += [.autoRepeat, .stop] }
            return .encounter(actions[r.next(below: actions.count)])
        }
        switch r.next(below: 6) {
        case 0: return .buyFuel(credits: 500)
        case 1: return .buyCargo(TradeItemType(rawValue: r.next(below: 10)) ?? .water, quantity: 3)
        case 2:
            let dests = s.destinations
            return dests.isEmpty ? .buyFuel(credits: 500) : .selectTarget(dests[r.next(below: dests.count)])
        default: return .warp
        }
    }
}
