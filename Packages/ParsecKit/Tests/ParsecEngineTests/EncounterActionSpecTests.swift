// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecEngine

extension EncSpec {
    static let yes = Set(WarningID.allCases)

    static func opponent(_ type: ShipType, weapons: [WeaponType] = [.pulseLaser], cargo: [Int]? = nil) -> (GameState) -> Ship {
        { s in
            var o = ship(s, type)
            o.weapons = Array(weapons.prefix(o.spec(s.ruleset).weaponSlots))
            if !o.crew.isEmpty { o.crew[0] = CrewID.opponent }
            if let cargo { o.cargo = cargo }
            return o
        }
    }

    static func cargo(_ pairs: [(TradeItemType, Int)]) -> [Int] {
        var c = Array(repeating: 0, count: 10)
        for (item, q) in pairs { c[item.rawValue] = q }
        return c
    }

    /// Runs `verifyAttack` on the current encounter; returns the stop result (if any) and the updated encounter.
    static func verify(_ e: inout GameEngine, _ ack: Set<WarningID>) -> (StepResult?, EncounterState?) {
        guard var enc = current(e) else { return (nil, nil) }
        let r = e.verifyAttack(&enc, ack)
        return (r, enc)
    }
}

// MARK: - §6.2 Attack

@Suite("ENC §6.2: attack")
struct EncounterAttackTests {
    @Test("ENC-140 attack validation order: no weapons, no lasers vs a non-disableable ship, no disruptors vs the Scorpion")
    func validation() {
        func attempt(_ type: EncounterType, _ weapons: [WeaponType], _ opp: ShipType) -> CommandError? {
            var e = EncSpec.encounter(type, with: { s in s.commander.ship.weapons = weapons }, opponent: EncSpec.opponent(opp))
            let before = e.state
            let r = e.perform(.encounter(.attack), acknowledging: EncSpec.yes)
            if r.rejection != nil { #expect(e.state == before, "\(type) rejection changed state") }
            return r.rejection
        }
        #expect(attempt(.pirateAttack, [], .gnat) == .noWeapons)
        #expect(attempt(.scorpionAttack, [], .scorpion) == .noWeapons)
        #expect(attempt(.pirateAttack, [.photonDisruptor], .mantis) == .noLasers)
        #expect(attempt(.spaceMonsterAttack, [.photonDisruptor], .spaceMonster) == .noLasers)
        #expect(attempt(.pirateAttack, [.photonDisruptor], .gnat) == nil, "disruptors suffice against a disableable ship")
        #expect(attempt(.scorpionAttack, [.militaryLaser], .scorpion) == .noDisruptors)
        #expect(attempt(.scorpionAttack, [.militaryLaser, .photonDisruptor], .scorpion) == nil)
        var b = EncSpec.encounter(.pirateAttack, with: { s in s.commander.ship.weapons = [.photonDisruptor] }, opponent: EncSpec.opponent(.bottle))
        #expect(EncSpec.verify(&b, EncSpec.yes).0?.rejection == .noLasers, "a bottle is not disableable")
    }

    @Test("ENC-141 attacking from an …Ignore quest or pirate type switches to the matching …Attack (raw − 1) without confirmation")
    func ignoreToAttack() {
        let rows: [(EncounterType, EncounterType, ShipType)] = [
            (.dragonflyIgnore, .dragonflyAttack, .dragonfly), (.pirateIgnore, .pirateAttack, .gnat), (.scarabIgnore, .scarabAttack, .scarab),
            (.scorpionIgnore, .scorpionAttack, .scorpion), (.spaceMonsterIgnore, .spaceMonsterAttack, .spaceMonster),
        ]
        for (ignore, attack, opp) in rows {
            var e = EncSpec.encounter(ignore, with: { s in s.commander.ship.weapons = [.militaryLaser, .photonDisruptor] }, opponent: EncSpec.opponent(opp))
            let (stop, enc) = EncSpec.verify(&e, [])
            #expect(stop == nil && enc?.type == attack && attack.rawValue == ignore.rawValue - 1, "\(ignore)")
        }
    }

    @Test("ENC-142 attacking police: nothing-illegal confirmation first at an inspection, then attackPolice if rec > −30; type → policeAttack but policeFlee")
    func attackPolice() {
        var e = EncSpec.encounter(.policeInspect)
        let before = e.state
        #expect(e.perform(.encounter(.attack)).decision == .confirm(Confirmation(.submitWithNothingIllegal)))
        #expect(e.perform(.encounter(.attack), acknowledging: [.submitWithNothingIllegal]).decision == .confirm(Confirmation(.attackPolice, amounts: [-33])))
        #expect(e.state == before)
        let rows: [(EncounterType, Int, EncounterType, Int)] = [
            (.policeInspect, 0, .policeAttack, -33), (.marieCelestePolice, 10, .policeAttack, -33), (.policeIgnore, -10, .policeAttack, -33),
            (.policeSurrender, -29, .policeAttack, -33), (.policeFlee, 0, .policeFlee, -33), (.policeIgnore, -30, .policeAttack, -33),
            (.policeIgnore, -50, .policeAttack, -53),
        ]
        for (type, rec, next, after) in rows {
            var p = EncSpec.encounter(type) { s in s.commander.policeRecordScore = rec }
            let (stop, enc) = EncSpec.verify(&p, EncSpec.yes)
            #expect(stop == nil && enc?.type == next && p.state.commander.policeRecordScore == after, "\(type) rec \(rec)")
        }
        // rec ≤ −30: no attackPolice confirmation; illegal cargo: no nothing-illegal confirmation.
        var crook = EncSpec.encounter(.policeInspect) { s in
            s.commander.policeRecordScore = -40
            s.commander.ship.cargo[TradeItemType.narcotics.rawValue] = 2
        }
        #expect(EncSpec.verify(&crook, []).0 == nil && crook.state.commander.policeRecordScore == -43)
        for type in [EncounterType.policeAttack, .policeDisabled] {
            var p = EncSpec.encounter(type)
            let (stop, enc) = EncSpec.verify(&p, [])
            #expect(stop == nil && enc?.type == type && p.state.commander.policeRecordScore == 0, "\(type): no verification step")
        }
    }

    @Test("ENC-143 attacking a trader: −2 when rec < 0, else confirm attackTrader and rec = −5; then an always-made rand(1500) flee roll")
    func attackTrader() {
        func run(_ type: EncounterType, rec: Int, rep: Int, armed: Bool = true, ack: Set<WarningID> = EncSpec.yes)
            -> (StepResult?, EncounterType?, Int, Bool) {
            var e = EncSpec.encounter(type, with: { s in
                s.commander.policeRecordScore = rec
                s.commander.reputationScore = rep
            }, opponent: EncSpec.opponent(.gnat, weapons: armed ? [.pulseLaser] : []))
            var r = e.state.rng
            let draw = r.next(below: 1_500)
            let (stop, enc) = EncSpec.verify(&e, ack)
            if stop != nil { return (stop, enc?.type, e.state.commander.policeRecordScore, true) }
            let flee = draw <= rep * 10 / (ShipType.gnat.rawValue + 1) || !armed
            #expect(e.state.rng == r, "\(type): the flee roll is always made")
            return (nil, enc?.type, e.state.commander.policeRecordScore, enc?.type == (flee ? .traderFlee : .traderAttack))
        }
        #expect(run(.traderIgnore, rec: -1, rep: 0, ack: []) == (nil, .traderAttack, -3, true))
        let ask = run(.traderBuy, rec: 0, rep: 0, ack: [])
        #expect(ask.0?.decision == .confirm(Confirmation(.attackTrader, amounts: [-5])) && ask.2 == 0)
        #expect(run(.traderBuy, rec: 0, rep: 0) == (nil, .traderAttack, -5, true))
        #expect(run(.traderSell, rec: 7, rep: 100_000) == (nil, .traderFlee, -5, true))
        #expect(run(.traderAttack, rec: 0, rep: 0, ack: []) == (nil, .traderAttack, 0, true))
        #expect(run(.traderSurrender, rec: 3, rep: 100_000, ack: []) == (nil, .traderFlee, 3, true))
        #expect(run(.traderAttack, rec: 0, rep: 0, armed: false, ack: []) == (nil, .traderFlee, 0, true), "an unarmed trader flees")
    }

    @Test("ENC-144 attacking a famous captain: confirm attackCaptain, rec = min(rec, −70) − 2, an 'attacked' news event, type famousCaptainAttack")
    func attackCaptain() {
        let news: [EncounterType: NewsEvent] = [.captainAhab: .captAhabAttacked, .captainConrad: .captConradAttacked, .captainHuie: .captHuieAttacked]
        for (type, event) in news {
            for (rec, after) in [(10, -72), (-80, -82)] {
                var e = EncSpec.encounter(type, with: { s in s.commander.policeRecordScore = rec }, opponent: EncSpec.opponent(.wasp))
                let before = e.state
                #expect(EncSpec.verify(&e, []).0?.decision == .confirm(Confirmation(.attackCaptain)))
                #expect(e.state == before)
                let (stop, enc) = EncSpec.verify(&e, [.attackCaptain])
                #expect(stop == nil && enc?.type == .famousCaptainAttack)
                #expect(e.state.commander.policeRecordScore == after && e.state.newsEvents.last == event)
            }
        }
    }

    @Test("ENC-145 attacking from any other type keeps the type; then commanderFleeing = false and one combat round runs")
    func otherTypes() throws {
        let rows: [(EncounterType, ShipType)] = [
            (.pirateAttack, .gnat), (.pirateFlee, .gnat), (.pirateSurrender, .gnat), (.pirateDisabled, .gnat), (.policeAttack, .gnat),
            (.policeDisabled, .gnat), (.traderFlee, .gnat), (.traderDisabled, .gnat), (.famousCaptainAttack, .wasp),
            (.famousCaptDisabled, .wasp), (.dragonflyAttack, .dragonfly), (.scarabAttack, .scarab), (.scorpionAttack, .scorpion),
            (.spaceMonsterAttack, .spaceMonster),
        ]
        for (type, opp) in rows {
            var e = EncSpec.encounter(type, with: { s in s.commander.ship.weapons = [.militaryLaser, .photonDisruptor] }, opponent: EncSpec.opponent(opp))
            let before = e.state
            let (stop, enc) = EncSpec.verify(&e, [])
            #expect(stop == nil && enc?.type == type, "\(type)")
            #expect(e.state.rng == before.rng && e.state.commander.policeRecordScore == before.commander.policeRecordScore)
        }
        var e = EncSpec.encounter(.pirateAttack) { s in s.commander.ship.shields = [ShieldInstance(type: .reflective, charge: 200)] }
        var enc = try #require(EncSpec.current(e))
        enc.cmdrFleeing = true
        e.state.phase = .encounter(enc)
        let r = e.perform(.encounter(.attack))
        #expect(r.events.first == .playerAttacked)
        #expect(r.events.contains { if case .combatRound(round: 1, _, _, _, _) = $0 { true } else { false } })
        if let after = EncSpec.current(e) { #expect(!after.cmdrFleeing && after.round == 1) }
    }

    @Test("ENC-146 every manual Attack re-runs verification (police penalty again, a fresh trader flee roll); auto-repeat does not")
    func reverification() throws {
        var p = EncSpec.encounter(.policeFlee) { s in s.commander.policeRecordScore = -40 }
        #expect(EncSpec.verify(&p, []).0 == nil && p.state.commander.policeRecordScore == -43)
        #expect(EncSpec.verify(&p, []).0 == nil && p.state.commander.policeRecordScore == -46)
        var t = EncSpec.encounter(.traderAttack)
        let start = t.state
        _ = EncSpec.verify(&t, [])
        _ = EncSpec.verify(&t, [])
        #expect(t.state.rng == EncSpec.after(start, [1_500, 1_500]))
        for type in [EncounterType.policeFlee, .traderAttack, .traderSurrender] {
            var a = EncSpec.encounter(type) { s in s.commander.policeRecordScore = -40 }
            var enc = try #require(EncSpec.current(a))
            enc.continueAttacking = true
            a.state.phase = .encounter(enc)
            var model = a
            enc.continueAttacking = false
            _ = model.runRound(&enc, events: [])
            _ = a.perform(.encounter(.autoRepeat))
            #expect(a.state == model.state, "\(type): the auto-repeat tick is a bare round")
        }
    }
}

// MARK: - §6.3–6.4 Flee, surrender, submit, yield, bribe

@Suite("ENC §6.3–6.4: flee, surrender, submit, yield, bribe")
struct EncounterPoliceActionTests {
    @Test("ENC-150 flee: confirmations (inspection with nothing illegal, customs always), police record and type changes, then a fleeing round")
    func flee() throws {
        var i = EncSpec.encounter(.policeInspect)
        #expect(i.perform(.encounter(.flee)).decision == .confirm(Confirmation(.fleeInspection)))
        var c = EncSpec.encounter(.marieCelestePolice) { s in s.commander.ship.cargo[TradeItemType.narcotics.rawValue] = 3 }
        #expect(c.perform(.encounter(.flee)).decision == .confirm(Confirmation(.fleeMariePolice)))
        let rows: [(EncounterType, Difficulty, Int, Int)] = [
            (.policeInspect, .normal, 0, -6), (.policeInspect, .normal, -10, -12), (.policeInspect, .easy, 0, -5),
            (.policeInspect, .easy, 3, -5), (.policeInspect, .impossible, 0, -6), (.marieCelestePolice, .normal, 0, -30),
            (.marieCelestePolice, .normal, -40, -43),
        ]
        for (type, diff, rec, after) in rows {
            var e = EncSpec.encounter(type, diff) { s in s.commander.policeRecordScore = rec }
            var enc = try #require(EncSpec.current(e))
            #expect(e.verifyFlee(&enc, EncSpec.yes) == nil)
            #expect(enc.type == .policeAttack && enc.cmdrFleeing && e.state.commander.policeRecordScore == after, "\(type) \(diff) \(rec)")
        }
        var narc = EncSpec.encounter(.policeInspect) { s in s.commander.ship.cargo[TradeItemType.narcotics.rawValue] = 3 }
        #expect(!GameEngine.isConfirmationRequest(narc.perform(.encounter(.flee))), "illegal goods: no nothing-illegal confirmation")
        var pir = EncSpec.encounter(.pirateAttack)
        var penc = try #require(EncSpec.current(pir))
        #expect(pir.verifyFlee(&penc, []) == nil && penc.type == .pirateAttack && penc.cmdrFleeing)
        var run = EncSpec.encounter(.pirateAttack)
        let r = run.perform(.encounter(.flee))
        #expect(r.events.first == .playerFled && r.events.contains { if case .combatRound = $0 { true } else { false } })
    }

    @Test("ENC-152 surrender dispatch: Mantis (artifact), police (arrest unless rec ≤ −100), else the pirate raid (refused with the Princess aboard)")
    func surrender() {
        var m = EncSpec.encounter(.pirateAttack, opponent: EncSpec.opponent(.mantis))
        #expect(m.perform(.encounter(.surrender), acknowledging: EncSpec.yes).rejection == .surrenderRefused)
        var ma = EncSpec.encounter(.pirateAttack, with: { s in s.quests.artifact = QuestStatus.Artifact.onBoard }, opponent: EncSpec.opponent(.mantis))
        #expect(ma.perform(.encounter(.surrender)).decision == .confirm(Confirmation(.surrenderArtifact)))
        let mr = ma.perform(.encounter(.surrender), acknowledging: [.surrenderArtifact])
        #expect(mr.events.contains(.artifactRelinquished) && ma.state.quests.artifact == 0 && EncSpec.endedNormally(ma, mr))
        for type in [EncounterType.policeAttack, .policeSurrender] {
            var hard = EncSpec.encounter(type) { s in s.commander.policeRecordScore = -100 }
            #expect(hard.perform(.encounter(.surrender), acknowledging: EncSpec.yes).rejection == .surrenderRefused)
            var p = EncSpec.encounter(type) { s in s.commander.policeRecordScore = -99 }
            #expect(p.perform(.encounter(.surrender)).decision == .confirm(Confirmation(.surrenderToPolice)))
            let pr = p.perform(.encounter(.surrender), acknowledging: [.surrenderToPolice])
            #expect(pr.events.contains { if case .arrested = $0 { true } else { false } } && p.state.phase == .docked)
        }
        var pr = EncSpec.encounter(.pirateAttack) { s in s.commander.ship.crew[1] = CrewID.princess }
        #expect(pr.perform(.encounter(.surrender), acknowledging: EncSpec.yes).rejection == .surrenderPrincess)
        var hidden = EncSpec.encounter(.pirateAttack) { s in
            s.commander.ship.crew[1] = CrewID.princess
            s.commander.ship.gadgets = [.hiddenCargoBays]
        }
        #expect(hidden.perform(.encounter(.surrender)).rejection == nil, "hidden bays shelter the Princess")
        var raid = EncSpec.encounter(.pirateAttack) { s in s.commander.ship.cargo[TradeItemType.ore.rawValue] = 4 }
        let rr = raid.perform(.encounter(.surrender))   // no confirmation for a pirate surrender
        #expect(rr.events.contains(.looted(units: 4)) && raid.state.raided && EncSpec.endedNormally(raid, rr))
    }

    @Test("ENC-153 surrendering to the Scarab is a pirate raid; the stolen cargo stays in the Scarab's hold")
    func scarabRaid() {
        var e = EncSpec.encounter(.scarabAttack, with: { s in
            s.commander.ship.cargo = EncSpec.cargo([(.water, 3), (.ore, 2)])
        }, opponent: { s in s.specialShips.scarab })
        let r = e.perform(.encounter(.surrender))
        #expect(r.events.contains(.looted(units: 5)) && e.state.raided)
        #expect(e.state.specialShips.scarab.cargo == EncSpec.cargo([(.water, 3), (.ore, 2)]))
        #expect(e.state.commander.ship.cargo.allSatisfy { $0 == 0 })
    }

    @Test("ENC-154 raided stays set until the next departure; inspected suppresses further inspections (no inspection draw)")
    func tripFlags() {
        var e = EncSpec.encounter(.pirateAttack) { s in s.commander.ship.cargo[0] = 2 }
        _ = e.perform(.encounter(.surrender))
        #expect(e.state.raided && e.state.phase == .docked)
        e.state.commander.ship.fuel = e.state.commander.ship.fuelTanks(e.ruleset)
        e.state.commander.cash = 50_000
        if let target = e.state.destinations.first {
            _ = e.perform(.selectTarget(target))
            let r = e.perform(.warp)
            #expect(r.events.contains { if case .departed = $0 { true } else { false } })
            #expect(!e.state.raided && !e.state.inspected)
        } else {
            Issue.record("no destination in range")
        }
        for rec in [0, 2, 5, 20] {
            var s = EncSpec.engine { s in s.inspected = true; s.commander.policeRecordScore = rec }.state
            var g = s
            _ = g.generateOpponent(.police)
            let enc = s.determinePolice(clicks: 3)
            #expect(s.rng == g.rng && enc?.type != .policeInspect, "rec \(rec): no inspection roll once inspected")
        }
    }

    @Test("ENC-155 submit: confirm submitInspection when illegal goods/passengers are detectable; arrest with Wild/reactor/sculpture; clean → +1")
    func submit() {
        var clean = EncSpec.encounter(.policeInspect)
        let cr = clean.perform(.encounter(.submit))
        #expect(cr.events.contains(.inspectionClean) && clean.state.commander.policeRecordScore == 1 && EncSpec.endedNormally(clean, cr))
        var narc = EncSpec.encounter(.policeInspect) { s in s.commander.ship.cargo[TradeItemType.narcotics.rawValue] = 4 }
        #expect(narc.perform(.encounter(.submit)).decision == .confirm(Confirmation(.submitInspection)))
        let nr = narc.perform(.encounter(.submit), acknowledging: [.submitInspection])
        #expect(nr.events.contains { if case .fined = $0 { true } else { false } } && narc.state.commander.ship.cargo[8] == 0)
        #expect(EncSpec.endedNormally(narc, nr))
        for special in 0..<3 {
            var w = EncSpec.encounter(.policeInspect) { s in
                switch special {
                case 0: s.commander.ship.crew[1] = CrewID.wild
                case 1: s.quests.reactor = QuestStatus.Reactor.fuelOK
                default: s.quests.sculpture = QuestStatus.Sculpture.inTransit
                }
            }
            #expect(w.perform(.encounter(.submit)).decision == .confirm(Confirmation(.submitInspection)))
            let wr = w.perform(.encounter(.submit), acknowledging: [.submitInspection])
            #expect(wr.events.contains { if case .arrested = $0 { true } else { false } } && w.state.phase == .docked, "special \(special)")
        }
    }

    @Test("ENC-156 yield to customs: illegal special cargo → confirm surrenderToPolice, arrest; else confirm submitInspection, rec = min(rec, −5), goods gone")
    func yieldCustoms() {
        var w = EncSpec.encounter(.marieCelestePolice) { s in s.commander.ship.crew[1] = CrewID.wild }
        #expect(w.perform(.encounter(.yield)).decision == .confirm(Confirmation(.surrenderToPolice)))
        let wr = w.perform(.encounter(.yield), acknowledging: [.surrenderToPolice])
        #expect(wr.events.contains { if case .arrested = $0 { true } else { false } } && w.state.phase == .docked)
        for (rec, after) in [(10, -5), (-20, -20)] {
            var y = EncSpec.encounter(.marieCelestePolice) { s in
                s.commander.policeRecordScore = rec
                s.commander.ship.cargo = EncSpec.cargo([(.narcotics, 5), (.firearms, 1), (.food, 2)])
            }
            #expect(y.perform(.encounter(.yield)).decision == .confirm(Confirmation(.submitInspection)))
            let yr = y.perform(.encounter(.yield), acknowledging: [.submitInspection])
            #expect(yr.events.contains(.yielded) && y.state.commander.policeRecordScore == after)
            #expect(y.state.commander.ship.cargo == EncSpec.cargo([(.food, 2)]) && EncSpec.endedNormally(y, yr))
        }
    }

    @Test("ENC-157 bribe order: customs refuse, bribe level 0 impossible, nothing-illegal confirmation, bribe confirmation, cash check, pay")
    func bribe() throws {
        var c = EncSpec.encounter(.marieCelestePolice)
        #expect(c.perform(.encounter(.bribe), acknowledging: EncSpec.yes).rejection == .bribeNotAccepted)
        var z = EncSpec.encounter(.policeInspect) { s in s.galaxy.systems[s.warpSystem].politics = .cybernetic }
        #expect(z.perform(.encounter(.bribe), acknowledging: EncSpec.yes).rejection == .bribeNotPossible)
        var e = EncSpec.encounter(.policeInspect) { s in s.commander.cash = 50_000 }
        let amount = try #require(e.state.bribeAmount)
        #expect(e.perform(.encounter(.bribe)).decision == .confirm(Confirmation(.submitWithNothingIllegal)))
        #expect(e.perform(.encounter(.bribe), acknowledging: [.submitWithNothingIllegal]).decision == .confirm(Confirmation(.bribe, amounts: [amount])))
        var poor = EncSpec.encounter(.policeInspect) { s in s.commander.cash = 0 }
        let before = poor.state
        #expect(poor.perform(.encounter(.bribe), acknowledging: EncSpec.yes).rejection == .insufficientFunds)
        #expect(poor.state == before && EncSpec.current(poor) != nil, "the encounter continues")
        let r = e.perform(.encounter(.bribe), acknowledging: [.submitWithNothingIllegal, .bribe])
        #expect(r.events.contains(.bribed(amount)) && e.state.commander.cash == 50_000 - amount && EncSpec.endedNormally(e, r))
        var illegal = EncSpec.encounter(.policeInspect) { s in s.commander.cash = 50_000; s.commander.ship.cargo[5] = 1 }
        let illegalAmount = try #require(illegal.state.bribeAmount)
        #expect(illegal.perform(.encounter(.bribe)).decision == .confirm(Confirmation(.bribe, amounts: [illegalAmount])))
    }
}

// MARK: - §6.5 Plunder, trade, ignore, board, drink, meet

@Suite("ENC §6.5: plunder, trade, ignore, board, drink, meet")
struct EncounterOtherActionTests {
    @Test("ENC-158 plunder opens a plunder decision over the opponent's cargo without confirmation; finishing it ends the encounter Normal")
    func plunder() {
        let hold = EncSpec.cargo([(.water, 3), (.games, 2)])
        for type in [EncounterType.pirateDisabled, .pirateSurrender, .traderDisabled, .traderSurrender] {
            var e = EncSpec.encounter(type, opponent: EncSpec.opponent(.gnat, cargo: hold))
            let r = e.perform(.encounter(.plunder))
            #expect(r.decision == .plunder(hold) && r.rejection == nil, "\(type)")
            let t = e.perform(.plunderTake(.water, quantity: 2))
            #expect(t.events == [.plundered(item: .water, quantity: 2)])
            let d = e.perform(.plunderDone)
            #expect(EncSpec.endedNormally(e, d) && e.state.commander.ship.cargo[0] == 2, "\(type)")
        }
    }

    @Test("ENC-159 trade opens the trade-in-orbit decision (item and price rolled then); any resolution, including 0, ends Normal")
    func trade() throws {
        for (type, qty) in [(EncounterType.traderSell, 0), (.traderSell, 1), (.traderBuy, 0), (.traderBuy, 2)] {
            var e = EncSpec.encounter(type, with: { s in
                setMarket(&s)
                s.commander.cash = 10_000
                if type == .traderBuy { s.commander.ship.cargo[0] = 5 }
            }, opponent: EncSpec.opponent(.gnat, cargo: EncSpec.cargo([(.water, 5)])))
            let before = e.state.rng
            let r = e.perform(.encounter(.trade))
            guard case let .tradeInOrbit(offer) = r.decision else { Issue.record("\(type): no trade decision"); continue }
            #expect(offer.direction == (type == .traderBuy ? .traderBuys : .traderSells) && e.state.rng != before)
            let done = e.perform(.resolveTradeInOrbit(quantity: qty))
            #expect(done.rejection == nil && EncSpec.endedNormally(e, done), "\(type) quantity \(qty)")
        }
    }

    @Test("ENC-160 ignore ends the encounter Normal with no draw and no change except clearing the continue flags")
    func ignore() throws {
        for type in [EncounterType.pirateIgnore, .policeFlee, .traderBuy, .captainAhab, .bottleGood] {
            var e = EncSpec.encounter(type)
            var enc = try #require(EncSpec.current(e))
            enc.continueAttacking = true
            e.state.phase = .encounter(enc)
            var model = e
            enc.continueAttacking = false
            model.state.phase = .encounter(enc)
            let expected = model.finishEncounter(.normal)
            let r = e.perform(.encounter(.ignore))
            #expect(r.events == expected && e.state == model.state, "\(type)")
        }
    }

    @Test("ENC-161 board the Marie Celeste: confirm, plunder her cargo; justLootedMarie only if the commander's narcotics increased")
    func board() {
        let marie = EncSpec.opponent(.gnat, cargo: EncSpec.cargo([(.narcotics, 5)]))
        var e = EncSpec.encounter(.marieCeleste, opponent: marie)
        let before = e.state
        #expect(e.perform(.encounter(.board)).decision == .confirm(Confirmation(.boardMarieCeleste)))
        #expect(e.state == before, "declining leaves the encounter open")
        #expect(e.perform(.encounter(.board), acknowledging: [.boardMarieCeleste]).decision == .plunder(EncSpec.cargo([(.narcotics, 5)])))
        _ = e.perform(.plunderTake(.narcotics, quantity: 2))
        let d = e.perform(.plunderDone)
        #expect(e.state.quests.justLootedMarie && EncSpec.endedNormally(e, d))
        // Narcotics already aboard and none taken: no customs police (C# compares with the count before boarding).
        var held = EncSpec.encounter(.marieCeleste, with: { s in s.commander.ship.cargo[8] = 3 }, opponent: marie)
        _ = held.perform(.encounter(.board), acknowledging: [.boardMarieCeleste])
        let hd = held.perform(.plunderDone)
        #expect(!held.state.quests.justLootedMarie && EncSpec.endedNormally(held, hd))
    }

    @Test("ENC-162 drink: confirm drinkTonic, apply the tonic, emit tonicConsumed, end Normal; declining leaves the encounter open")
    func drink() {
        for type in [EncounterType.bottleGood, .bottleOld] {
            var e = EncSpec.encounter(type, opponent: EncSpec.opponent(.bottle))
            let before = e.state
            #expect(e.perform(.encounter(.drink)).decision == .confirm(Confirmation(.drinkTonic)))
            #expect(e.state == before)
            let r = e.perform(.encounter(.drink), acknowledging: [.drinkTonic])
            #expect(r.events.contains(.tonicConsumed(good: type == .bottleGood)) && EncSpec.endedNormally(e, r))
            #expect(e.state.mercenaries[CrewID.commander].skills != before.mercenaries[CrewID.commander].skills)
        }
    }

    @Test("ENC-163 meet: confirm meetCaptain; trade the first reflective shield (Ahab) or military laser (Conrad, Huie) for min(10, skill + 2|1)")
    func meet() {
        let trained: [EncounterType: SkillType] = [.captainAhab: .pilot, .captainConrad: .engineer, .captainHuie: .trader]
        let rows: [(EncounterType, Difficulty, Int, Int)] = [
            (.captainAhab, .normal, 5, 7), (.captainAhab, .hard, 5, 6), (.captainConrad, .normal, 9, 10), (.captainHuie, .impossible, 4, 5),
        ]
        for (type, diff, from, to) in rows {
            let skill = trained[type] ?? .pilot
            var e = EncSpec.encounter(type, diff, with: { s in
                s.commander.ship.shields = [ShieldInstance(type: .energy, charge: 1), ShieldInstance(type: .reflective, charge: 2)]
                s.commander.ship.weapons = [.pulseLaser, .militaryLaser]
                s.mercenaries[CrewID.commander].skills[skill.rawValue] = from
            }, opponent: EncSpec.opponent(.wasp))
            let before = e.state
            #expect(e.perform(.encounter(.meet)).decision == .confirm(Confirmation(.meetCaptain)))
            #expect(e.state == before)
            let r = e.perform(.encounter(.meet), acknowledging: [.meetCaptain])
            #expect(r.events.contains(.captainTraining(skill: skill)) && EncSpec.endedNormally(e, r))
            #expect(e.state.mercenaries[CrewID.commander].skills[skill.rawValue] == to, "\(type) \(diff)")
            if type == .captainAhab {
                #expect(e.state.commander.ship.shields.map(\.type) == [.energy])
            } else {
                #expect(e.state.commander.ship.weapons == [.pulseLaser])
            }
        }
        var two = EncSpec.encounter(.captainConrad) { s in s.commander.ship.weapons = [.militaryLaser, .beamLaser] }
        _ = two.perform(.encounter(.meet), acknowledging: [.meetCaptain])
        #expect(two.state.commander.ship.weapons == [.beamLaser], "the first military laser goes")
    }

    @Test("ENC-164 after a round, Continue keeps the encounter (encounterChanged when the type changed); Normal/Killed/EscapePod end it")
    func afterRound() {
        var changed = false, unchanged = false, ended = false
        for seed in UInt64(1)...600 where !(changed && unchanged && ended) {
            var e = EncSpec.engine(seed: seed) { s in s.commander.ship.shields = [ShieldInstance(type: .reflective, charge: 200)] }
            var opp = EncSpec.gnat(e.state)
            opp.hull = seed % 4 == 0 ? 3 : 100
            EncSpec.enter(&e, .pirateAttack, opponent: opp)
            let r = e.perform(.encounter(.attack))
            if e.state.pendingScoop != nil { _ = e.perform(.resolveScoop(accept: false)) }
            if let enc = EncSpec.current(e) {
                let didChange = enc.type != .pirateAttack
                #expect(r.events.contains(.encounterChanged(enc.type)) == didChange, "seed \(seed)")
                changed = changed || didChange
                unchanged = unchanged || !didChange
            } else {
                ended = true
                #expect(e.state.phase == .docked || e.state.phase == .gameOver(.killed))
            }
        }
        #expect(changed && unchanged && ended)
    }
}
