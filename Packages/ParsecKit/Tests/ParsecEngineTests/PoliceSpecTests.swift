// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecEngine

/// Shared set-up for the POL tests: an engine inside an encounter whose transit resumes with `clicks` left.
enum Pol {
    static let yes = Set(WarningID.allCases)

    static func engine(_ type: EncounterType, _ ruleset: RulesetID = .windows201, difficulty: Difficulty = .normal,
                       opponent: ShipType = .gnat, clicks: Int = 1, _ adjust: (inout GameState) -> Void = { _ in }) -> GameEngine {
        var e = makeEngine(ruleset, difficulty: difficulty) { s in
            s.commander.ship.weapons = [.pulseLaser]
            s.commander.cash = 5_000
            s.commander.debt = 0
            s.galaxy.systems[s.warpSystem].politics = .capitalist
        }
        e.state.encounterTransit = TransitState(destination: e.state.warpSystem, clicksRemaining: clicks, viaWormhole: false)
        let opp = Ship(type: opponent, spec: e.ruleset.tables.ship(opponent))
        e.state.phase = .encounter(EncounterState(type: type, opponent: opp, clicks: clicks))
        adjust(&e.state)
        return e
    }

    /// Sets C# `Commander.Worth` (ship list price + cash − debt) to `w` exactly.
    static func setWorth(_ s: inout GameState, _ w: Int) {
        let price = s.commander.ship.spec(s.ruleset).price
        if w >= price {
            s.commander.cash = w - price
            s.commander.debt = 0
        } else {
            s.commander.cash = 0
            s.commander.debt = price - w
        }
    }

    /// The current encounter; records an issue (and returns a placeholder) when the engine is not in one.
    static func encounter(_ e: GameEngine, sourceLocation: SourceLocation = #_sourceLocation) -> EncounterState {
        guard case let .encounter(enc) = e.state.phase else {
            Issue.record("not in an encounter: \(e.state.phase)", sourceLocation: sourceLocation)
            return EncounterState(type: .policeIgnore, opponent: e.state.commander.ship)
        }
        return enc
    }

    /// Runs C# `EncounterVerifyAttack` with every warning acknowledged and returns the record afterwards.
    static func recordAfterAttack(_ type: EncounterType, record: Int, opponent: ShipType = .gnat,
                                  _ adjust: (inout GameState) -> Void = { _ in }) -> (Int, EncounterType) {
        var e = engine(type, opponent: opponent) { s in
            s.commander.policeRecordScore = record
            adjust(&s)
        }
        var enc = encounter(e)
        _ = e.verifyAttack(&enc, yes)
        return (e.state.commander.policeRecordScore, enc.type)
    }
}

@Suite("POL §1-2: record and reputation scales, drift")
struct PoliceScaleSpecTests {
    @Test("POL-001 a new game starts Clean and Harmless; scores are unbounded")
    func newGame() {
        var e = makeEngine()
        #expect(e.state.commander.policeRecordScore == 0 && e.state.commander.reputationScore == 0)
        #expect(e.state.policeRecord == .clean && e.state.reputation == .harmless)
        e.state.commander.policeRecordScore = -1_000
        e.state.commander.reputationScore = 50_000
        _ = e.state.incDays(1)
        #expect(e.state.commander.policeRecordScore == -999)
        #expect(e.state.policeRecord == .psychopath && e.state.reputation == .elite)
        #expect(e.state.arrestTerm == 999)
    }

    @Test("POL-002 police-record level boundaries")
    func recordLevels() {
        let cases: [(Int, PoliceRecordType)] = [
            (-71, .psychopath), (-70, .villain), (-31, .villain), (-30, .criminal), (-11, .criminal), (-10, .crook),
            (-6, .crook), (-5, .dubious), (-1, .dubious), (0, .clean), (4, .clean), (5, .lawful), (9, .lawful),
            (10, .trusted), (24, .trusted), (25, .liked), (74, .liked), (75, .hero), (10_000, .hero),
        ]
        for (score, level) in cases { #expect(PoliceRecordType(score: score) == level, "score \(score)") }
    }

    @Test("POL-003 the lookup walks upward; everything below −70 is Psychopath; 10 levels")
    func recordWalk() {
        #expect(PoliceRecordType.allCases.count == 10)
        for score in [-80, -100, -101, -1_000, Int(Int32.min)] { #expect(PoliceRecordType(score: score) == .psychopath) }
    }

    @Test("POL-004 the level function takes the score explicitly and matches the commander lookup")
    func explicitScore() {
        var s = makeEngine().state
        for score in stride(from: -120, through: 120, by: 7) {
            s.commander.policeRecordScore = score
            #expect(s.policeRecord == PoliceRecordType(score: score))
        }
    }

    @Test("POL-005 reputation levels, negatives are Harmless")
    func reputationLevels() {
        let cases: [(Int, ReputationType)] = [
            (-50, .harmless), (9, .harmless), (10, .mostlyHarmless), (19, .mostlyHarmless), (20, .poor), (40, .average),
            (80, .aboveAverage), (150, .competent), (299, .competent), (300, .dangerous), (600, .deadly), (1_499, .deadly),
            (1_500, .elite),
        ]
        for (score, level) in cases { #expect(ReputationType(score: score) == level, "score \(score)") }
        #expect(ReputationType.minScores == [0, 10, 20, 40, 80, 150, 300, 600, 1_500])
    }

    @Test("POL-006 code constants −100 −70 −30 −10 −5 0 5 10 25 75 drive the rules")
    func constants() {
        #expect(PoliceRecordType.minScores == [-100, -70, -30, -10, -5, 0, 5, 10, 25, 75])
        // criminal (−30): attacking police asks only above it.
        var e = Pol.engine(.policeIgnore) { $0.commander.policeRecordScore = -30 }
        #expect(e.perform(.encounter(.attack)).decision != .confirm(Confirmation(.attackPolice, amounts: [-33])))
        e = Pol.engine(.policeIgnore) { $0.commander.policeRecordScore = -29 }
        #expect(e.perform(.encounter(.attack)).decision == .confirm(Confirmation(.attackPolice, amounts: [-33])))
        // psychopath (−100): surrender is refused at or below it.
        e = Pol.engine(.policeAttack) { $0.commander.policeRecordScore = -100 }
        #expect(e.perform(.encounter(.surrender)).rejection == .surrenderRefused)
        e = Pol.engine(.policeAttack) { $0.commander.policeRecordScore = -99 }
        #expect(e.perform(.encounter(.surrender)).decision == .confirm(Confirmation(.surrenderToPolice)))
        // villain (−70): attacking a famous captain; dubious (−5): arrest; clean (0): attacking a trader.
        #expect(Pol.recordAfterAttack(.captainAhab, record: 0).0 == -72)
        var s = makeEngine().state
        s.commander.policeRecordScore = 40
        _ = s.arrested()
        #expect(s.commander.policeRecordScore == -5)
        #expect(Pol.recordAfterAttack(.traderIgnore, record: -1).0 == -3)
        #expect(Pol.recordAfterAttack(.traderIgnore, record: 0).0 == -5)
    }

    @Test("POL-008 record score deltas per action")
    func deltas() {
        #expect(Pol.recordAfterAttack(.policeIgnore, record: -40).0 == -43)
        #expect(Pol.recordAfterAttack(.traderIgnore, record: -10).0 == -12)
        #expect(Pol.recordAfterAttack(.pirateAttack, record: 7).0 == 7)
        func won(_ type: EncounterType, _ opp: ShipType = .gnat) -> Int {
            var e = Pol.engine(type, opponent: opp) { $0.commander.policeRecordScore = 0 }
            var enc = Pol.encounter(e)
            _ = e.state.encounterWon(&enc)
            return e.state.commander.policeRecordScore
        }
        #expect(won(.policeAttack) == -6)
        #expect(won(.traderAttack) == -4)
        #expect(won(.pirateAttack) == 1)
        var e = Pol.engine(.policeInspect) { s in s.commander.ship.cargo[TradeItemType.firearms.rawValue] = 1 }
        _ = e.perform(.encounter(.flee), acknowledging: Pol.yes)
        #expect(e.state.commander.policeRecordScore == -6) // min(0 − 2, −6) on Normal
        e = Pol.engine(.policeInspect) { s in s.commander.ship.cargo[TradeItemType.narcotics.rawValue] = 2 }
        _ = e.perform(.encounter(.submit), acknowledging: Pol.yes)
        #expect(e.state.commander.policeRecordScore == -1)
        // Caught with Wild (escape pod) −4; famous captain kill is a reputation bonus, not a record change.
        var s = makeEngine().state
        s.commander.ship.crew.append(CrewID.wild)
        s.commander.policeRecordScore = 10
        _ = s.escapeWithPod()
        #expect(s.commander.policeRecordScore == 10 - 4 - 3 / 3) // −4, then IncDays(3) decays by 1
        e = Pol.engine(.famousCaptainAttack) { s in s.commander.reputationScore = 400; s.newsEvents = [.captAhabAttacked] }
        var enc = Pol.encounter(e)
        _ = e.state.encounterWon(&enc)
        #expect(e.state.commander.policeRecordScore == 0)
        #expect(e.state.commander.reputationScore == 400 + 100 + ShipType.gnat.rawValue / 2 + 1)
    }

    @Test("POL-009 criminal means rec < −5 for prices and rec < 0 for the loan limit")
    func criminalThresholds() {
        func prices(_ rec: Int) -> [Int] {
            var s = makeEngine().state
            s.commander.policeRecordScore = rec
            s.calculatePrices(for: s.commander.currentSystem)
            return s.sellPrices
        }
        #expect(prices(-5) == prices(0))
        let clean = prices(-5), criminal = prices(-6)
        #expect(zip(clean, criminal).allSatisfy { $0.1 == $0.0 * 90 / 100 })
        var s = makeEngine().state
        s.commander.policeRecordScore = 0
        let lawfulLoan = s.maxLoan
        s.commander.policeRecordScore = -1
        #expect(lawfulLoan >= 1_000 && s.maxLoan == 500)
    }

    @Test("POL-010 Windows IncDays drift: positive decays by n/3, below −5 improves by n/(D ≤ Normal ? 1 : D)")
    func drift() {
        func after(_ rec: Int, _ n: Int, _ d: Difficulty) -> Int {
            var s = makeEngine(difficulty: d).state
            s.commander.policeRecordScore = rec
            _ = s.incDays(n)
            return s.commander.policeRecordScore
        }
        #expect(after(30, 1, .normal) == 30)
        #expect(after(30, 3, .normal) == 29)
        #expect(after(2, 30, .normal) == 0)
        #expect(after(-3, 30, .normal) == -3)
        #expect(after(-20, 1, .normal) == -19)
        #expect(after(-20, 30, .normal) == -5)
        #expect(after(-20, 1, .hard) == -20)
        #expect(after(-20, 4, .impossible) == -19)
    }

    @Test("POL-012 Windows drift examples")
    func driftExamples() {
        var s = makeEngine(difficulty: .hard).state
        s.commander.policeRecordScore = 30
        _ = s.incDays(1)
        #expect(s.commander.policeRecordScore == 30)
        _ = s.incDays(3)
        #expect(s.commander.policeRecordScore == 29)
        s.commander.policeRecordScore = -20
        _ = s.incDays(1)
        #expect(s.commander.policeRecordScore == -20)
        _ = s.incDays(30)
        #expect(s.commander.policeRecordScore == -10)
    }
}

@Suite("POL §3: record and reputation changes by action")
struct PoliceRecordChangeSpecTests {
    @Test("POL-030 attacking police: confirmation above −30, then min(rec, −30) − 3 and policeAttack (not from policeFlee)")
    func attackPolice() {
        let illegal: (inout GameState) -> Void = { $0.commander.ship.cargo[TradeItemType.firearms.rawValue] = 1 }
        for type in [EncounterType.policeInspect, .policeIgnore, .policeFlee, .policeSurrender, .marieCelestePolice] {
            var e = Pol.engine(type) { s in illegal(&s); s.commander.policeRecordScore = 3 }
            let before = e.state
            #expect(e.perform(.encounter(.attack)).decision == .confirm(Confirmation(.attackPolice, amounts: [-33])), "\(type)")
            #expect(e.state == before)
            let (rec, newType) = Pol.recordAfterAttack(type, record: 3, illegal)
            #expect(rec == -33)
            #expect(newType == (type == .policeFlee ? .policeFlee : .policeAttack))
            #expect(Pol.recordAfterAttack(type, record: -50, illegal).0 == -53)
        }
        for type in [EncounterType.policeAttack, .policeDisabled] {
            #expect(Pol.recordAfterAttack(type, record: 3).0 == 3)
        }
    }

    @Test("POL-032 attacking a peaceful trader: −2 below 0, else confirm and −5; other trader types unchanged")
    func attackTrader() {
        for type in [EncounterType.traderIgnore, .traderBuy, .traderSell] {
            #expect(Pol.recordAfterAttack(type, record: -1).0 == -3)
            var e = Pol.engine(type)
            #expect(e.perform(.encounter(.attack)).decision == .confirm(Confirmation(.attackTrader, amounts: [-5])))
            #expect(Pol.recordAfterAttack(type, record: 20).0 == -5)
        }
        for type in [EncounterType.traderAttack, .traderSurrender] {
            #expect(Pol.recordAfterAttack(type, record: 20).0 == 20)
        }
    }

    @Test("POL-033 attacking a famous captain: always confirm, min(rec, −70) − 2, news, famousCaptainAttack")
    func attackCaptain() {
        var e = Pol.engine(.captainConrad) { $0.commander.policeRecordScore = -90 }
        #expect(e.perform(.encounter(.attack)).decision == .confirm(Confirmation(.attackCaptain)))
        var enc = Pol.encounter(e)
        _ = e.verifyAttack(&enc, Pol.yes)
        #expect(e.state.commander.policeRecordScore == -92)
        #expect(e.state.newsEvents.last == .captConradAttacked)
        #expect(enc.type == .famousCaptainAttack)
        #expect(Pol.recordAfterAttack(.captainHuie, record: 10).0 == -72)
        #expect(Pol.recordAfterAttack(.famousCaptainAttack, record: -72).0 == -72)
    }

    @Test("POL-035 fleeing an inspection: nothing-illegal confirmation, then min(rec − 2, −5 − (D ≥ Normal))")
    func fleeInspection() {
        var e = Pol.engine(.policeInspect)
        #expect(e.perform(.encounter(.flee)).decision == .confirm(Confirmation(.fleeInspection)))
        func fled(_ rec: Int, _ d: Difficulty) -> (Int, EncounterType) {
            var e = Pol.engine(.policeInspect, difficulty: d) { $0.commander.policeRecordScore = rec }
            var enc = Pol.encounter(e)
            _ = e.verifyFlee(&enc, Pol.yes)
            return (e.state.commander.policeRecordScore, enc.type)
        }
        #expect(fled(-4, .easy) == (-6, .policeAttack))
        #expect(fled(3, .easy) == (-5, .policeAttack))
        #expect(fled(0, .normal) == (-6, .policeAttack))
        #expect(fled(-10, .hard) == (-12, .policeAttack))
    }

    @Test("POL-036 fleeing post-Marie customs: confirmation, then min(rec − 3, −30) and policeAttack")
    func fleeCustoms() {
        var e = Pol.engine(.marieCelestePolice) { $0.commander.ship.cargo[TradeItemType.narcotics.rawValue] = 5 }
        #expect(e.perform(.encounter(.flee)).decision == .confirm(Confirmation(.fleeMariePolice)))
        for (rec, expected) in [(0, -30), (-40, -43)] {
            var e = Pol.engine(.marieCelestePolice) { $0.commander.policeRecordScore = rec }
            var enc = Pol.encounter(e)
            _ = e.verifyFlee(&enc, Pol.yes)
            #expect(e.state.commander.policeRecordScore == expected && enc.type == .policeAttack)
        }
    }

    @Test("POL-039 attacking pirates or monsters and fleeing attackers change no record")
    func noRecordChange() {
        let cases: [(EncounterType, ShipType)] = [
            (.pirateAttack, .gnat), (.pirateIgnore, .gnat), (.spaceMonsterIgnore, .spaceMonster), (.dragonflyIgnore, .dragonfly),
            (.scarabAttack, .scarab), (.scorpionIgnore, .scorpion),
        ]
        for (type, opp) in cases {
            let rec = Pol.recordAfterAttack(type, record: 4, opponent: opp) { s in
                s.commander.ship.weapons = [.pulseLaser, .photonDisruptor]
            }.0
            #expect(rec == 4, "\(type)")
        }
        for type in [EncounterType.policeAttack, .pirateAttack, .traderAttack] {
            var e = Pol.engine(type) { $0.commander.policeRecordScore = 4 }
            var enc = Pol.encounter(e)
            _ = e.verifyFlee(&enc, Pol.yes)
            #expect(e.state.commander.policeRecordScore == 4 && enc.cmdrFleeing)
        }
    }

    @Test("POL-040 +1 for destroying pirates, monster, Dragonfly, Scarab; plundering a disabled pirate; disabling specials")
    func lawfulKills() {
        func won(_ type: EncounterType, _ opp: ShipType) -> Int {
            var e = Pol.engine(type, opponent: opp) { $0.commander.policeRecordScore = 0 }
            var enc = Pol.encounter(e)
            _ = e.state.encounterWon(&enc)
            return e.state.commander.policeRecordScore
        }
        #expect(won(.pirateAttack, .gnat) == 1)
        #expect(won(.pirateFlee, .hornet) == 1)
        #expect(won(.spaceMonsterAttack, .spaceMonster) == 1)
        #expect(won(.dragonflyAttack, .dragonfly) == 1)
        #expect(won(.scarabAttack, .scarab) == 1)
        #expect(won(.pirateAttack, .mantis) == 0)
        var e = Pol.engine(.pirateDisabled) { s in
            if case var .encounter(enc) = s.phase { enc.opponentDisabled = true; s.phase = .encounter(enc) }
        }
        _ = e.perform(.encounter(.plunder))
        _ = e.perform(.plunderDone)
        #expect(e.state.commander.policeRecordScore == 1)
        for (type, opp) in [(EncounterType.dragonflyAttack, ShipType.dragonfly), (.scarabAttack, .scarab), (.scorpionAttack, .scorpion)] {
            var e = Pol.engine(type, opponent: opp)
            var enc = Pol.encounter(e)
            enc.opponentDisabled = true
            let (result, events) = e.state.executeRound(&enc)
            #expect(result == .normal && events.contains(.opponentDisabled(opp)))
            #expect(e.state.commander.policeRecordScore == 1, "\(opp)")
        }
    }

    @Test("POL-041 destroying police costs 6")
    func killPolice() {
        for type in [EncounterType.policeAttack, .policeFlee] {
            var e = Pol.engine(type) { $0.commander.policeRecordScore = -40 }
            var enc = Pol.encounter(e)
            _ = e.state.encounterWon(&enc)
            #expect(e.state.commander.policeRecordScore == -46 && e.state.commander.kills.police == 1)
        }
    }

    @Test("POL-042 destroying a trader costs 4; a famous captain costs nothing more")
    func killTrader() {
        for type in [EncounterType.traderAttack, .traderFlee, .traderSurrender] {
            var e = Pol.engine(type) { $0.commander.policeRecordScore = 2 }
            var enc = Pol.encounter(e)
            _ = e.state.encounterWon(&enc)
            #expect(e.state.commander.policeRecordScore == -2)
        }
        var e = Pol.engine(.famousCaptainAttack) { s in s.commander.policeRecordScore = -72; s.newsEvents = [.captHuieAttacked] }
        var enc = Pol.encounter(e)
        _ = e.state.encounterWon(&enc)
        #expect(e.state.commander.policeRecordScore == -72)
    }

    @Test("POL-043 plunder: traders −2, surrendered pirates −1, applied after plundering")
    func plunderRecord() {
        for (type, delta) in [(EncounterType.traderSurrender, -2), (.traderDisabled, -2), (.pirateSurrender, -1)] {
            var e = Pol.engine(type) { s in
                s.commander.policeRecordScore = 10
                if case var .encounter(enc) = s.phase { enc.opponent.cargo[0] = 3; s.phase = .encounter(enc) }
            }
            _ = e.perform(.encounter(.plunder))
            #expect(e.state.commander.policeRecordScore == 10)
            _ = e.perform(.plunderTake(.water, quantity: 1))
            #expect(e.state.commander.policeRecordScore == 10)
            _ = e.perform(.plunderDone)
            #expect(e.state.commander.policeRecordScore == 10 + delta, "\(type)")
        }
    }

    @Test("POL-044 trafficking: submitting with detectable goods −1, a clean inspection +1")
    func trafficking() {
        var e = Pol.engine(.policeInspect) { s in
            s.commander.policeRecordScore = 7
            s.commander.ship.cargo[TradeItemType.firearms.rawValue] = 2
        }
        _ = e.perform(.encounter(.submit), acknowledging: Pol.yes)
        #expect(e.state.commander.policeRecordScore == 6)
        e = Pol.engine(.policeInspect) { $0.commander.policeRecordScore = 7 }
        _ = e.perform(.encounter(.submit))
        #expect(e.state.commander.policeRecordScore == 8)
    }

    @Test("POL-045 littering penalties change the same police record field")
    func littering() {
        var caught = false
        for seed in 1...60 where !caught {
            var e = makeEngine(seed: UInt64(seed), difficulty: .impossible) { s in
                s.commander.ship.cargo[0] = 5
                s.commander.policeRecordScore = -9
                s.phase = .inTransit(TransitState(destination: 0, clicksRemaining: 10, viaWormhole: false))
            }
            let r = e.perform(.jettisonCargo(.water, quantity: 1))
            if r.events.contains(.caughtLittering(newRecord: -10)) {
                caught = true
                #expect(e.state.commander.policeRecordScore == -10)
            } else {
                #expect(e.state.commander.policeRecordScore == -9)
            }
        }
        #expect(caught)
    }

    @Test("POL-047 arrest assigns rec = −5 whatever the previous value")
    func arrestAssigns() {
        for rec in [60, 0, -5, -50] {
            var s = makeEngine().state
            s.commander.cash = 100_000
            s.commander.policeRecordScore = rec
            _ = s.arrested()
            #expect(s.commander.policeRecordScore == -5, "from \(rec)")
        }
    }

    @Test("POL-048 reputation: +type/2+1 per kill, disable and plunder; famous captain → max(300, rep + 100); never lowered")
    func reputation() {
        var e = Pol.engine(.pirateAttack, opponent: .hornet) { $0.commander.reputationScore = 7 }
        var enc = Pol.encounter(e)
        _ = e.state.encounterWon(&enc)
        #expect(e.state.commander.reputationScore == 7 + ShipType.hornet.rawValue / 2 + 1)
        for (start, expected) in [(100, 300), (299, 300), (300, 400), (1_000, 1_100)] {
            var e = Pol.engine(.famousCaptainAttack, opponent: .wasp) { s in s.commander.reputationScore = start; s.newsEvents = [.captAhabAttacked] }
            var enc = Pol.encounter(e)
            _ = e.state.encounterWon(&enc)
            #expect(e.state.commander.reputationScore == expected + ShipType.wasp.rawValue / 2 + 1)
        }
        e = Pol.engine(.scarabAttack, opponent: .scarab) { $0.commander.reputationScore = 0 }
        enc = Pol.encounter(e)
        enc.opponentDisabled = true
        _ = e.state.executeRound(&enc)
        #expect(e.state.commander.reputationScore == ShipType.scarab.rawValue / 2 + 1)
        e = Pol.engine(.traderSurrender, opponent: .beetle) { $0.commander.reputationScore = 50 }
        _ = e.perform(.encounter(.plunder))
        _ = e.perform(.plunderDone)
        #expect(e.state.commander.reputationScore == 50 + ShipType.beetle.rawValue / 2 + 1)
        // Arrest, police kills and plunder penalties never lower it.
        var s = makeEngine().state
        s.commander.reputationScore = 444
        s.commander.cash = 100_000
        _ = s.arrested()
        #expect(s.commander.reputationScore == 444)
        e = Pol.engine(.policeAttack) { $0.commander.reputationScore = 10 }
        enc = Pol.encounter(e)
        _ = e.state.encounterWon(&enc)
        #expect(e.state.commander.reputationScore == 10 + ShipType.gnat.rawValue / 2 + 1)
    }
}
