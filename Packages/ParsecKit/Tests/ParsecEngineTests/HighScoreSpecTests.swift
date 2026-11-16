// SPDX-License-Identifier: GPL-2.0-or-later
// SCORE §6 {M6}: the high-score table (entries, ranking, capacity, eligibility), and the engine side of the
// game-end alerts ALR-096…104 (docs/specs/SCORE.md, ALR.md).
import Testing
@testable import ParsecEngine

private func hs(_ name: String, score: Int, worth: Int = 1_000, days: Int = 10,
                _ ruleset: RulesetID = .modern) -> HighScoreEntry {
    HighScoreEntry(name: name, endType: .retired, score: score, days: days, worth: worth, difficulty: .normal, rulesetID: ruleset)
}

/// Inserts every entry in order into a table of `capacity`, returning the table and the outcomes.
private func run(_ entries: [HighScoreEntry], capacity: Int = HighScoreTable.capacity) -> (HighScoreTable, [HighScoreOutcome]) {
    var table = HighScoreTable(capacity: capacity)
    var outcomes: [HighScoreOutcome] = []
    for e in entries {
        let (t, o) = table.inserting(e)
        table = t
        outcomes.append(o)
    }
    return (table, outcomes)
}

@Suite("High-score table (SCORE §6)")
struct HighScoreSpecTests {
    @Test("SCORE-029 an entry stores name, end, native score, days, worth, difficulty, ruleset, Ironman and reloaded")
    func entryFields() {
        for ruleset in RulesetID.allCases {
            var s = makeEngine(ruleset, difficulty: .hard) { s in
                s.commander.days = 123
                s.commander.cash = 40_000
            }.state
            s.ironman = true
            s.reloadCount = 2
            let e = s.highScoreEntry(for: .killed)
            #expect(e.name == "Test" && e.endType == .killed && e.days == 123 && e.worth == s.worth)
            #expect(e.score == s.score(for: .killed) && e.difficulty == .hard && e.rulesetID == ruleset)
            #expect(e.ironman && e.reloaded)
            s.ironman = false
            s.reloadCount = 0
            let plain = s.highScoreEntry(for: .retired)
            #expect(!plain.ironman && !plain.reloaded && plain.score == s.score(for: .retired))
        }
    }

    @Test("SCORE-030 tables are per ruleset: native score units differ, the ranking rule is the same everywhere")
    func perRuleset() {
        let make = { (id: RulesetID) in
            makeEngine(id) { s in s.commander.cash = 200_000; s.commander.days = 50 }.state
        }
        let windows = make(.windows201), palm = make(.palm122)
        // Palm's native score is about 5× the C# tenths for the same game, so the units are not comparable.
        #expect(palm.highScoreEntry(for: .retired).score != windows.highScoreEntry(for: .retired).score)
        // Separate tables: each holds only its ruleset's entries, ranked by the same rule.
        let modernTable = run([hs("A", score: 5), hs("B", score: 9)]).0
        let palmTable = run([hs("C", score: 5, .palm122), hs("D", score: 9, .palm122)]).0
        #expect(modernTable.entries.map(\.name) == ["B", "A"] && palmTable.entries.map(\.name) == ["D", "C"])
        #expect(modernTable.entries.allSatisfy { $0.rulesetID == .modern } && palmTable.entries.allSatisfy { $0.rulesetID == .palm122 })
    }

    @Test("SCORE-031 a ranks above b by score, then worth, then more days; full ties compare equal")
    func ordering() {
        #expect(hs("a", score: 11).ranksAbove(hs("b", score: 10, worth: 9_999_999, days: 999)))
        #expect(!hs("a", score: 10).ranksAbove(hs("b", score: 11)))
        #expect(hs("a", score: 10, worth: 2).ranksAbove(hs("b", score: 10, worth: 1, days: 999)))
        #expect(hs("a", score: 10, worth: 2, days: 9).ranksAbove(hs("b", score: 10, worth: 2, days: 5)))
        #expect(!hs("a", score: 10, worth: 2, days: 5).ranksAbove(hs("b", score: 10, worth: 2, days: 9)))
        let x = hs("x", score: 10, worth: 2, days: 5), y = hs("y", score: 10, worth: 2, days: 5)
        #expect(!x.ranksAbove(y) && !y.ranksAbove(x))
    }

    @Test("SCORE-032 top 10; enter iff a free slot or strictly above the lowest; the first 3 match a 3-slot table")
    func capacity() {
        #expect(HighScoreTable.capacity == 10 && HighScoreTable().capacity == 10)
        let full = run((1...10).map { hs("e\($0)", score: $0 * 10) }).0
        #expect(full.entries.count == 10 && full.entries.last?.score == 10)
        // Equal to the lowest: not entered.
        let (same, sameOutcome) = full.inserting(hs("tie", score: 10))
        #expect(sameOutcome == .missed && same == full)
        // Strictly above the lowest: enters, the lowest drops out.
        let (beat, beatOutcome) = full.inserting(hs("beat", score: 15))
        #expect(beatOutcome == .entered(rank: 10) && beat.entries.count == 10)
        #expect(!beat.entries.contains { $0.name == "e1" } && beat.entries.last?.name == "beat")
        // A long sequence: the 10-slot table's top 3 equals the classic 3-slot table.
        var seq: [HighScoreEntry] = []
        var x = 7
        for i in 0..<60 {
            x = (x * 37 + 11) % 101
            seq.append(hs("g\(i)", score: x, worth: (x * 13) % 7, days: i % 4))
        }
        let ten = run(seq).0, three = run(seq, capacity: 3).0
        #expect(three.entries.count == 3 && Array(ten.entries.prefix(3)) == three.entries)
    }

    @Test("SCORE-033 among equal entries the newer one goes below the older ones")
    func equalPlacement() {
        let (t, outcomes) = run([hs("old", score: 5), hs("mid", score: 5), hs("new", score: 5), hs("top", score: 6)])
        #expect(t.entries.map(\.name) == ["top", "old", "mid", "new"])
        #expect(outcomes == [.entered(rank: 1), .entered(rank: 2), .entered(rank: 3), .entered(rank: 1)])
    }

    @Test("SCORE-034 ALR-099 ALR-100 a cheated game never enters: excludedForCheats when it would qualify, missed otherwise")
    func cheats() {
        for ruleset in RulesetID.allCases {
            var s = makeEngine(ruleset) { $0.commander.cash = 100_000 }.state
            s.cheatsUsed = true
            #expect(s.highScoreExclusion == .excludedForCheats)
            let entry = s.highScoreEntry(for: .retired)
            let (t, o) = HighScoreTable().inserting(entry, eligible: s.highScoreExclusion)
            #expect(o == .excludedForCheats && t.entries.isEmpty)  // ALR-099
            // A full table it can't beat: the qualification test runs first → missed (ALR-100).
            let full = run((1...10).map { hs("e\($0)", score: entry.score + $0, ruleset) }).0
            let (t2, o2) = full.inserting(entry, eligible: s.highScoreExclusion)
            #expect(o2 == .missed && t2 == full)
            s.cheatsUsed = false
            #expect(s.highScoreExclusion == nil)
            #expect(full.inserting(entry, eligible: s.highScoreExclusion).1 == .missed)
        }
    }

    @Test("SCORE-035 Palm excludes a reloaded game (excludedForReload); Modern and Windows store it with the ↺ marker")
    func reloadBlock() {
        for ruleset in RulesetID.allCases {
            var s = makeEngine(ruleset) { $0.commander.cash = 100_000 }.state
            s.reloadCount = 1
            let (t, o) = HighScoreTable().inserting(s.highScoreEntry(for: .retired), eligible: s.highScoreExclusion)
            if ruleset == .palm122 {
                #expect(o == .excludedForReload && t.entries.isEmpty)
            } else {
                #expect(o == .entered(rank: 1) && t.entries.first?.reloaded == true)
            }
        }
    }

    @Test("SCORE-036 ALR-098 inserting is pure and returns the 1-based rank; the receiver is unchanged")
    func pureInsert() {
        let base = run([hs("a", score: 30), hs("b", score: 10)]).0
        let copy = base
        let (t, o) = base.inserting(hs("c", score: 20))
        #expect(o == .entered(rank: 2) && t.entries.map(\.name) == ["a", "c", "b"])  // ALR-098 carries the rank
        #expect(base == copy)
        #expect(base.inserting(hs("c", score: 20)) == (t, o))
        // The Ironman and reloaded markers ride along with the entered entry (ALR-098).
        var marked = hs("m", score: 99)
        marked.ironman = true
        marked.reloaded = true
        let (mt, mo) = base.inserting(marked)
        #expect(mo == .entered(rank: 1) && mt.entries[0].ironman && mt.entries[0].reloaded)
    }

    @Test("SCORE-041 scenario: ranks, equal placement, strict full-table rule, cheat and Palm reload exclusions, 3-slot match")
    func scenario() {
        let seq = [hs("s500", score: 500), hs("s300a", score: 300, worth: 10), hs("s300b", score: 300, worth: 20, days: 1),
                   hs("s300c", score: 300, worth: 20, days: 5), hs("s300d", score: 300, worth: 20, days: 9), hs("s100", score: 100)]
        let (t, outcomes) = run(seq)
        #expect(outcomes == [.entered(rank: 1), .entered(rank: 2), .entered(rank: 2), .entered(rank: 2), .entered(rank: 2),
                             .entered(rank: 6)])
        #expect(t.entries.map(\.name) == ["s500", "s300d", "s300c", "s300b", "s300a", "s100"])
        // Equal entry (s300c twin) goes below its equal.
        let (twin, twinOutcome) = t.inserting(hs("twin", score: 300, worth: 20, days: 5))
        #expect(twinOutcome == .entered(rank: 4) && twin.entries[2].name == "s300c" && twin.entries[3].name == "twin")
        // Full table: equal to the lowest misses, above it enters.
        let full = run(seq + (1...4).map { hs("f\($0)", score: 50) }).0
        #expect(full.entries.count == 10 && full.inserting(hs("low", score: 50)).1 == .missed)
        #expect(full.inserting(hs("ok", score: 51)).1 == .entered(rank: 7))
        // Cheated qualifying game.
        #expect(full.inserting(hs("cheat", score: 400), eligible: .excludedForCheats) == (full, .excludedForCheats))
        // Palm game with reloadCount > 0.
        var palm = makeEngine(.palm122) { $0.commander.cash = 900_000 }.state
        palm.reloadCount = 1
        let (pt, po) = HighScoreTable().inserting(palm.highScoreEntry(for: .retired), eligible: palm.highScoreExclusion)
        #expect(po == .excludedForReload && pt.entries.isEmpty)
        // First 3 of the 10-slot run equal a 3-slot run of the same sequence.
        #expect(Array(t.entries.prefix(3)) == run(seq, capacity: 3).0.entries)
    }
}

@Suite("Game-end alerts, engine side (ALR-096…104)")
struct GameEndAlertSpecTests {
    @Test("ALR-096 ALR-097 claiming the moon ends with boughtMoon; Modern after the Princess quest with boughtMoonGirl")
    func moonEndings() {
        for (ruleset, girl) in [(RulesetID.windows201, false), (.palm122, false), (.modern, true)] {
            var e = makeEngine(ruleset) { s in
                s.commander.currentSystem = SystemID.utopia
                s.galaxy.systems[SystemID.utopia].specialEvent = .moonRetirement
                s.quests.moon = QuestStatus.Moon.bought
                s.quests.princess = QuestStatus.Princess.done
            }
            let r = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
            let end: GameEndType = girl ? .boughtMoonGirl : .boughtMoon
            #expect(e.state.phase == .gameOver(end), "\(ruleset)")
            #expect(r.events.last == .gameEnded(end, score: e.state.score(for: end)))
        }
        // Modern without the Princess quest done: the plain moon ending.
        var plain = makeEngine(.modern) { s in
            s.commander.currentSystem = SystemID.utopia
            s.galaxy.systems[SystemID.utopia].specialEvent = .moonRetirement
            s.quests.moon = QuestStatus.Moon.bought
        }
        _ = plain.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(plain.state.phase == .gameOver(.boughtMoon))
    }

    @Test("ALR-101 destroyed without a pod (reactor meltdown) ends with killed and gameEnded(.killed)")
    func killed() {
        var s = makeEngine().state
        s.warpSystem = plainTarget(s) ?? 1
        s.quests.reactor = QuestStatus.Reactor.date
        let events = s.arrival()
        #expect(s.phase == .gameOver(.killed))
        #expect(events.last == .gameEnded(.killed, score: s.score(for: .killed)))
    }

    @Test("ALR-102 ALR-103 ALR-104 retire asks WarningID.retire with the score preview, then ends with the score in tenths")
    func retire() {
        for ruleset in RulesetID.allCases {
            var e = makeEngine(ruleset) { s in s.commander.cash = 80_000; s.commander.days = 30 }
            let before = e.state
            let preview = before.score(for: .retired)
            #expect(e.perform(.retire).decision == .confirm(Confirmation(.retire, amounts: [preview])))  // ALR-104
            #expect(e.state == before)
            let r = e.perform(.retire, acknowledging: [.retire])
            #expect(e.state.phase == .gameOver(.retired))                                                  // ALR-102
            #expect(r.events.last == .gameEnded(.retired, score: preview))                                  // ALR-103
            // The displayed tenths of a percent come from the same score (C#: score itself; Palm: score / 5).
            let tenths = e.state.scoreTenths(for: .retired)
            #expect(tenths == (ruleset == .palm122 ? preview / 5 : preview))
        }
        // Retire is docked only.
        var enc = m4EncounterEngine(.pirateAttack)
        #expect(enc.perform(.retire).rejection == .notAllowedInPhase)
    }
}
