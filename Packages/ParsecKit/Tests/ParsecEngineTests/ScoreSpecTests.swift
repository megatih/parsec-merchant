// SPDX-License-Identifier: GPL-2.0-or-later
// SCORE {M4}: endings, the Retire command and the Windows 2.01 score formula (docs/specs/SCORE.md).
import Testing
@testable import ParsecEngine

/// An engine in an encounter of `type` against a fresh `opponent`, with a one-click transit to resume afterwards.
func m4EncounterEngine(_ type: EncounterType, opponent: ShipType = .gnat, difficulty: Difficulty = .normal,
                       _ adjust: (inout GameState, inout Ship) -> Void = { _, _ in }) -> GameEngine {
    makeEngine(difficulty: difficulty) { s in
        var opp = Ship(type: opponent, spec: s.ruleset.tables.ship(opponent))
        opp.crew[0] = CrewID.opponent
        adjust(&s, &opp)
        s.lastOpponent = opp
        s.encounterTransit = TransitState(destination: s.warpSystem, clicksRemaining: 1, viaWormhole: false, hadEncounter: true)
        s.phase = .encounter(EncounterState(type: type, opponent: opp, clicks: 1))
    }
}

/// Runs `body` on copies of `base` whose RNG is advanced by 0, 1, 2… draws and returns the first accepted outcome.
func m4Scan(_ base: GameEngine, limit: Int = 3_000, _ body: (inout GameEngine) -> StepResult,
            until accept: (StepResult, GameEngine) -> Bool) -> (StepResult, GameEngine)? {
    var start = base
    for _ in 0..<limit {
        var e = start
        let r = body(&e)
        if accept(r, e) { return (r, e) }
        _ = start.state.rng.next(below: 1_000)
    }
    return nil
}

/// A docked Windows 2.01 state with the given difficulty, day and worth (Gnat list price + cash − debt).
private func scored(_ d: Difficulty, days: Int = 1, worth: Int) -> GameState {
    var s = makeEngine(difficulty: d).state
    s.commander.days = days
    let price = s.commander.ship.spec(s.ruleset).price
    if worth >= price {
        s.commander.cash = worth - price
        s.commander.debt = 0
    } else {
        s.commander.cash = 0
        s.commander.debt = price - worth
    }
    #expect(s.worth == worth)
    return s
}

/// One worked example of SCORE-027.
private struct ScoreExample {
    var end: GameEndType
    var d: Difficulty
    var days: Int
    var worth: Int
    var score: Int
}

/// A game that has just ended by retiring.
private func endedGame() -> GameEngine {
    var e = makeEngine()
    _ = e.perform(.retire, acknowledging: [.retire])
    return e
}

@Suite("Score spec: endings (SCORE §1–2)")
struct ScoreEndingSpecTests {
    @Test("SCORE-001 GameEndType has killed 0, retired 1, boughtMoon 2 and the Modern boughtMoonGirl 3")
    func endTypes() {
        #expect(GameEndType.allCases.map(\.rawValue) == [0, 1, 2, 3])
        #expect(GameEndType.killed.rawValue == 0 && GameEndType.retired.rawValue == 1)
        #expect(GameEndType.boughtMoon.rawValue == 2 && GameEndType.boughtMoonGirl.rawValue == 3)
        // C# NA = -1 is "the phase is not .gameOver": a fresh game is docked.
        #expect(makeEngine().state.phase == .docked)
    }

    @Test("SCORE-002 SCORE-012 an ending is only the phase; the step commits and its last event is gameEnded(type, score:)")
    func endingIsPhase() {
        var e = makeEngine { $0.commander.cash = 5_000 }
        let r = e.perform(.retire, acknowledging: [.retire])
        #expect(r.decision == nil && r.rejection == nil)
        #expect(e.state.phase == .gameOver(.retired))
        #expect(r.events.last == .gameEnded(.retired, score: e.state.score(for: .retired)))
        // Moon claim: the special-event completion comes first, then gameEnded on the committed state.
        var m = makeEngine { s in
            s.commander.currentSystem = SystemID.utopia
            s.quests.moon = QuestStatus.Moon.bought
        }
        let mr = m.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(mr.events == [.specialEventCompleted(.moonRetirement), .gameEnded(.boughtMoon, score: m.state.score(for: .boughtMoon))])
        #expect(m.state.phase == .gameOver(.boughtMoon))
    }

    @Test("SCORE-003 killed in combat: both destroyed without a pod ends the game with no victory effects; a pod continues")
    func killedInCombat() throws {
        let base = m4EncounterEngine(.pirateAttack) { s, opp in
            s.commander.ship.hull = 1
            s.commander.ship.weapons = [.militaryLaser, .militaryLaser]
            opp.weapons = [.militaryLaser, .militaryLaser]
            opp.hull = 1
        }
        let (r, e) = try #require(m4Scan(base, { $0.perform(.encounter(.attack)) }, until: { r, _ in r.events.contains(.bothDestroyed) }))
        #expect(e.state.phase == .gameOver(.killed))
        #expect(r.events.last == .gameEnded(.killed, score: e.state.score(for: .killed)))
        #expect(!r.events.contains { if case .bountyPaid = $0 { true } else { false } })
        #expect(!r.events.contains { if case .opponentDestroyed = $0 { true } else { false } })
        #expect(e.state.commander.kills == base.state.commander.kills)
        #expect(e.state.commander.policeRecordScore == base.state.commander.policeRecordScore)
        #expect(e.state.commander.reputationScore == base.state.commander.reputationScore)
        // Same fight with an escape pod: the pod fires and the game goes on.
        var podded = base
        podded.state.commander.ship.escapePod = true
        let (pr, pe) = try #require(m4Scan(podded, { $0.perform(.encounter(.attack)) }, until: { r, _ in
            r.events.contains { if case .escapePodUsed = $0 { true } else { false } }
        }))
        #expect(!pr.events.contains { if case .gameEnded = $0 { true } else { false } })
        if case .gameOver = pe.state.phase { Issue.record("pod must not end the game") }
    }

    @Test("SCORE-005 reactor meltdown: status reset, killed without a pod (no arrival), play continues with one")
    func meltdown() {
        var s = makeEngine().state
        s.warpSystem = plainTarget(s) ?? 1
        s.quests.reactor = QuestStatus.Reactor.date
        var pod = s
        let events = s.arrival()
        #expect(events == [.reactorMeltdown, .gameEnded(.killed, score: s.score(for: .killed))])
        #expect(s.quests.reactor == QuestStatus.Reactor.notStarted && s.phase == .gameOver(.killed))
        pod.commander.ship.escapePod = true
        let podEvents = pod.arrival()
        #expect(podEvents.first == .reactorMeltdown && podEvents.last == .arrived(system: pod.warpSystem))
        #expect(!podEvents.contains { if case .gameEnded = $0 { true } else { false } })
        #expect(pod.phase == .docked && pod.quests.reactor == QuestStatus.Reactor.notStarted)
    }

    @Test("SCORE-006 retiring costs nothing and changes nothing else")
    func retireChangesNothing() {
        let base = makeEngine { s in s.commander.cash = 3_000; s.commander.debt = 700; s.quests.japori = QuestStatus.Japori.inTransit }
        var e = base
        _ = e.perform(.retire, acknowledging: [.retire])
        var expected = base.state
        expected.phase = .gameOver(.retired)
        #expect(e.state == expected)
    }

    @Test("SCORE-007 SCORE-023 claiming the moon: status done, boughtMoon, score with the 500 000 moon value and days bonus")
    func claimMoon() {
        var e = makeEngine { s in
            s.commander.currentSystem = SystemID.utopia
            s.quests.moon = QuestStatus.Moon.bought
            s.commander.days = 150
            s.commander.cash = 100_000 - s.commander.ship.spec(s.ruleset).price
        }
        #expect(e.state.specialEventAvailable == .moonRetirement)
        let cash = e.state.commander.cash
        let r = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(e.state.quests.moon == QuestStatus.Moon.done && e.state.phase == .gameOver(.boughtMoon))
        #expect(e.state.commander.cash == cash)
        // worth 100 000 + 500 000 moon = 600 000, day 150 on Normal: worked example 6 → 900.
        #expect(e.state.worth == 600_000)
        #expect(r.events.last == .gameEnded(.boughtMoon, score: 900))
    }

    @Test("SCORE-009 MoonRetirement needs acceptSpecialEvent with amounts [0]; reserved costs above cash refuse it")
    func moonConsent() {
        let base = makeEngine { s in
            s.commander.currentSystem = SystemID.utopia
            s.quests.moon = QuestStatus.Moon.bought
        }
        var e = base
        #expect(e.perform(.specialEvent).decision == .confirm(Confirmation(.acceptSpecialEvent, amounts: [0])))
        #expect(e.state == base.state)
        // Reserve Money with a paid mercenary and no cash: cashToSpend < 0 → insufficientFunds, nothing changes.
        var poor = makeEngine { s in
            s.commander.currentSystem = SystemID.utopia
            s.quests.moon = QuestStatus.Moon.bought
            s.commander.ship = freshShip(.beetle, s)
            s.commander.ship.crew[1] = 1
            s.commander.cash = 0
            s.options.reserveMoney = true
        }
        #expect(poor.state.cashToSpend < 0)
        let before = poor.state
        #expect(poor.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).rejection == .insufficientFunds)
        #expect(poor.state == before)
    }

    @Test("SCORE-011 arrest with the ship sold, the pod, huge debt, Gemulon, the experiment and tribbles all continue play")
    func noOtherEndings() {
        func notOver(_ s: GameState) -> Bool { if case .gameOver = s.phase { false } else { true } }
        var arrest = makeEngine { s in s.commander.cash = 0; s.commander.debt = 0 }.state
        _ = arrest.arrested()
        #expect(arrest.commander.ship.type == .flea && notOver(arrest))
        var pod = makeEngine { s in armDepartureFreeze(&s) }
        _ = pod.perform(.warp)
        _ = pod.finishEncounter(.escapePod)
        #expect(notOver(pod.state))
        var days = makeEngine { s in
            s.commander.debt = 1_000_000
            s.quests.gemulon = 7
            s.quests.experiment = 11
            s.commander.ship.tribbles = 99_999
        }.state
        let events = days.incDays(1)
        #expect(events.contains(.gemulonInvaded) && events.contains(.experimentPerformed))
        #expect(notOver(days))
        days.warpSystem = plainTarget(days) ?? 1
        _ = days.arrival()
        #expect(days.commander.ship.tribbles == 100_000 && notOver(days))
    }

    @Test("SCORE-013 after the end every command is rejected with .gameOver and the state is unchanged")
    func commandsAfterEnd() {
        var e = endedGame()
        let ended = e.state
        let commands: [Command] = [.setOptions(e.state.options), .track(1), .retire, .specialEvent, .warp, .jump,
                                   .buyCargo(.water, quantity: 1), .buyFuel(credits: 10), .encounter(.attack),
                                   .readNewspaper, .selectTarget(1), .borrow(100)]
        for c in commands {
            #expect(e.perform(c, acknowledging: Set(WarningID.allCases)).rejection == .gameOver, "\(c)")
            #expect(e.state == ended)
        }
    }

    @Test("SCORE-014 read-only queries keep working on a game-over state")
    func queriesAfterEnd() {
        let base = makeEngine { $0.commander.cash = 12_345 }
        let e = endedGame()
        var ended = base
        _ = ended.perform(.retire, acknowledging: [.retire])
        #expect(ended.state.worth == base.state.worth)
        #expect(ended.state.score(for: .retired) == base.state.score(for: .retired))
        #expect(ended.state.commander == base.state.commander && ended.state.quests == base.state.quests)
        #expect(e.state.score(for: .killed) == makeEngine().state.score(for: .killed))
    }
}

@Suite("Score spec: Retire command and score formula (SCORE §3–7)")
struct ScoreFormulaSpecTests {
    @Test("SCORE-016 retire is accepted only when docked: transit and encounter → notAllowedInPhase, game over → gameOver")
    func retirePhases() {
        var enc = m4EncounterEngine(.pirateAttack)
        let encState = enc.state
        #expect(enc.perform(.retire, acknowledging: [.retire]).rejection == .notAllowedInPhase)
        #expect(enc.perform(.retire).rejection == .notAllowedInPhase && enc.state == encState)
        var transit = makeEngine { s in
            s.phase = .inTransit(TransitState(destination: s.warpSystem, clicksRemaining: 3, viaWormhole: false))
        }
        #expect(transit.perform(.retire, acknowledging: [.retire]).rejection == .notAllowedInPhase)
        var over = endedGame()
        #expect(over.perform(.retire, acknowledging: [.retire]).rejection == .gameOver)
    }

    @Test("SCORE-017 two-phase consent with the score preview; allowed in debt and with passengers, quests and cargo")
    func retireConsent() {
        let base = makeEngine { s in
            s.commander.debt = 20_000
            s.commander.ship = freshShip(.beetle, s)
            s.hireCrew(CrewID.princess)
            s.quests.princess = QuestStatus.Princess.rescued
            s.quests.sculpture = QuestStatus.Sculpture.inTransit
            s.commander.ship.cargo[TradeItemType.firearms.rawValue] = 3
        }
        var e = base
        let preview = base.state.score(for: .retired)
        #expect(e.perform(.retire).decision == .confirm(Confirmation(.retire, amounts: [preview])))
        #expect(e.state == base.state)
        let r = e.perform(.retire, acknowledging: [.retire])
        #expect(r.events == [.gameEnded(.retired, score: preview)])
        #expect(e.state.phase == .gameOver(.retired))
    }

    @Test("SCORE-018 SCORE-027 the C# score formula on the worked examples")
    func workedExamples() {
        let cases: [ScoreExample] = [
            ScoreExample(end: .killed, d: .normal, days: 1, worth: 11_000, score: 11),
            ScoreExample(end: .retired, d: .normal, days: 1, worth: 11_000, score: 12),
            ScoreExample(end: .retired, d: .easy, days: 1, worth: 250_000, score: 190),
            ScoreExample(end: .retired, d: .hard, days: 1, worth: 3_000_000, score: 1_824),
            ScoreExample(end: .killed, d: .normal, days: 1, worth: 999_999, score: 1_079),
            ScoreExample(end: .killed, d: .normal, days: 1, worth: 1_000_009, score: 1_080),
            ScoreExample(end: .boughtMoon, d: .normal, days: 150, worth: 600_000, score: 900),
            ScoreExample(end: .boughtMoon, d: .normal, days: 300, worth: 560_000, score: 672),
            ScoreExample(end: .boughtMoon, d: .normal, days: 301, worth: 560_000, score: 672),
            ScoreExample(end: .boughtMoon, d: .beginner, days: 250, worth: 800_000, score: 320),
            ScoreExample(end: .boughtMoon, d: .impossible, days: 100, worth: 2_000_000, score: 3_000),
            ScoreExample(end: .killed, d: .normal, days: 1, worth: -5_000, score: -5),
            ScoreExample(end: .retired, d: .impossible, days: 1, worth: 50_000_000, score: -5_969)
        ]
        for c in cases {
            #expect(scored(c.d, days: c.days, worth: c.worth).score(for: c.end) == c.score, "\(c)")
        }
        // Modern's moon-girl ending uses the moon row (mod 100 and the days bonus).
        let s = scored(.normal, days: 150, worth: 600_000)
        #expect(s.score(for: .boughtMoonGirl) == s.score(for: .boughtMoon))
    }

    @Test("SCORE-019 the Int32 product wraps like C#; negative worth gives a negative score")
    func wrapping() {
        // Impossible, retired: (D+1)×mod = 475; W' = 4 521 019 is the first value whose product exceeds Int32.max.
        let below = scored(.impossible, worth: 1_000_000 + (4_521_018 - 1_000_000) * 10)
        let above = scored(.impossible, worth: 36_210_190)
        #expect(below.score(for: .retired) == 475 * 4_521_018 / 250_000)
        #expect(above.score(for: .retired) == Int(Int32(truncatingIfNeeded: 475 * 4_521_019)) / 250_000)
        #expect(above.score(for: .retired) < 0)
        #expect(scored(.normal, worth: -100_000).score(for: .retired) == 3 * 95 * -100_000 / 250_000)
    }

    @Test("SCORE-021 the score uses the Windows worth: list price + cash − debt + moon, not hull, equipment or cargo")
    func windowsWorth() {
        var s = scored(.normal, worth: 50_000)
        let score = s.score(for: .retired)
        s.commander.ship.hull = 1
        s.commander.ship.weapons.append(.militaryLaser)
        s.commander.ship.cargo[TradeItemType.robots.rawValue] = 5
        s.commander.priceCargo[TradeItemType.robots.rawValue] = 25_000
        #expect(s.worth == 50_000 && s.score(for: .retired) == score)
        s.quests.moon = QuestStatus.Moon.bought
        #expect(s.worth == 550_000)
        #expect(s.score(for: .retired) == 3 * 95 * 550_000 / 250_000)
    }

    @Test("SCORE-023 days, worth and difficulty come from the state at the end; the moon bonus stops at day (D+1)×100")
    func endStateInputs() {
        #expect(scored(.normal, days: 299, worth: 560_000).score(for: .boughtMoon) == 3 * 100 * (1_000 + 560_000) / 250_000)
        #expect(scored(.normal, days: 300, worth: 560_000).score(for: .boughtMoon) == 672)
        #expect(scored(.normal, days: 450, worth: 560_000).score(for: .boughtMoon) == 672)
        // The retire score is read after the step: an identical state gives the same number as the event.
        var e = makeEngine { $0.commander.days = 77 }
        let r = e.perform(.retire, acknowledging: [.retire])
        #expect(r.events.last == .gameEnded(.retired, score: e.state.score(for: .retired)))
    }

    @Test("SCORE-024 score(for:) is already in tenths of a percent; its digits split with truncating / and % like C#")
    func tenths() {
        func parts(_ t: Int) -> (Int, Int) { (t / 10, t % 10) }
        let t = scored(.hard, worth: 3_000_000).score(for: .retired)
        #expect(t == 1_824 && parts(t) == (182, 4))
        #expect(parts(scored(.impossible, worth: 50_000_000).score(for: .retired)) == (-596, -9))
        #expect(parts(scored(.normal, worth: -5_000).score(for: .killed)) == (0, -5))
    }

    @Test("SCORE-026 score(for:) is a pure query in every phase: no RNG, no state change")
    func pureQuery() {
        let states = [makeEngine().state, m4EncounterEngine(.pirateAttack).state, endedGame().state,
                      makeEngine { s in s.phase = .inTransit(TransitState(destination: 1, clicksRemaining: 2, viaWormhole: false)) }.state]
        for s in states {
            let copy = s
            for end in GameEndType.allCases { _ = s.score(for: end) }
            #expect(s == copy && s.rng == copy.rng)
            #expect(s.score(for: .retired) == copy.score(for: .retired))
        }
    }

    @Test("SCORE-040 scenario: retire flow, encounter refusal, both destroyed, meltdown, moon claim and its refusal")
    func scenario() throws {
        // (a) docked Normal retire.
        var e = makeEngine { s in s.commander.days = 1; s.commander.cash = 1_000 }
        let before = e.state
        let ask = e.perform(.retire)
        #expect(ask.decision == .confirm(Confirmation(.retire, amounts: [12])) && e.state == before)  // worth 11 000 → 12
        let done = e.perform(.retire, acknowledging: [.retire])
        #expect(e.state.phase == .gameOver(.retired) && done.events.last == .gameEnded(.retired, score: 12))
        #expect(e.perform(.buyFuel(credits: 1)).rejection == .gameOver)
        // (b) retire during an encounter.
        var enc = m4EncounterEngine(.traderIgnore)
        #expect(enc.perform(.retire, acknowledging: [.retire]).rejection == .notAllowedInPhase)
        // (c) both destroyed, no pod; with a pod no game over.
        let fight = m4EncounterEngine(.pirateAttack) { s, opp in
            s.commander.ship.hull = 1
            s.commander.ship.weapons = [.militaryLaser, .militaryLaser]
            opp.weapons = [.militaryLaser, .militaryLaser]
            opp.hull = 1
        }
        let (both, after) = try #require(m4Scan(fight, { $0.perform(.encounter(.attack)) }, until: { r, _ in r.events.contains(.bothDestroyed) }))
        #expect(after.state.phase == .gameOver(.killed) && !both.events.contains { if case .bountyPaid = $0 { true } else { false } })
        #expect(after.state.commander.kills == fight.state.commander.kills)
        var podFight = fight
        podFight.state.commander.ship.escapePod = true
        let (_, podAfter) = try #require(m4Scan(podFight, { $0.perform(.encounter(.attack)) }, until: { r, _ in
            r.events.contains { if case .escapePodUsed = $0 { true } else { false } }
        }))
        #expect(podAfter.state.phase == .docked)
        // (d) meltdown without a pod.
        var melt = makeEngine().state
        melt.warpSystem = plainTarget(melt) ?? 1
        melt.quests.reactor = QuestStatus.Reactor.date
        let meltEvents = melt.arrival()
        #expect(meltEvents.first == .reactorMeltdown && melt.phase == .gameOver(.killed))
        #expect(!meltEvents.contains { if case .arrived = $0 { true } else { false } })
        // (e) moon claim, and its refusal under Reserve Money.
        var moon = makeEngine { s in
            s.commander.currentSystem = SystemID.utopia
            s.quests.moon = QuestStatus.Moon.bought
            s.commander.days = 150
            s.commander.cash = 100_000 - s.commander.ship.spec(s.ruleset).price
        }
        var refused = moon
        let r = moon.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(moon.state.quests.moon == QuestStatus.Moon.done && moon.state.phase == .gameOver(.boughtMoon))
        #expect(r.events.last == .gameEnded(.boughtMoon, score: 900))
        refused.state.commander.ship = freshShip(.beetle, refused.state)
        refused.state.commander.ship.crew[1] = 1
        refused.state.commander.cash = 0
        refused.state.options.reserveMoney = true
        let snapshot = refused.state
        #expect(refused.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).rejection == .insufficientFunds)
        #expect(refused.state == snapshot)
    }
}
