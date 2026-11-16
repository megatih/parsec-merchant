// SPDX-License-Identifier: GPL-2.0-or-later
// SAV §12 and SCORE-037/038: the versioned HighScores.json file, quarantine, unknown tables and once-only recording.
import Foundation
import Testing
@testable import ParsecEngine
@testable import ParsecPersistence

private func entry(_ name: String, score: Int, _ ruleset: RulesetID = .modern) -> HighScoreEntry {
    HighScoreEntry(name: name, endType: .retired, score: score, days: 10, worth: 1_000, difficulty: .normal, rulesetID: ruleset)
}

private func rawFile(_ store: HighScoreStore) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as? [String: Any])
}

@Suite("SAV high-score storage (SAV §12)")
struct HighScoreStoreSpecTests {
    @Test("SAV-049 HighScores.json is {format, schemaVersion 1, tables by ruleset id}, sorted keys, atomic; missing = empty")
    func fileShape() throws {
        let root = makeTempRoot()
        defer { cleanUp(root) }
        let store = HighScoreStore(root: root)
        #expect(try store.load().isEmpty && store.table(for: .palm122).entries.isEmpty)
        let modern = HighScoreTable().inserting(entry("A", score: 50)).0
        let palm = HighScoreTable().inserting(entry("P", score: 7, .palm122)).0
        try store.save([.modern: modern, .palm122: palm])
        let raw = try rawFile(store)
        #expect(raw["format"] as? String == "parsec-merchant-highscores" && raw["schemaVersion"] as? Int == 1)
        let tables = try #require(raw["tables"] as? [String: Any])
        #expect(Set(tables.keys) == ["modern", "palm122"])
        #expect(try store.load() == [.modern: modern, .palm122: palm])
        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        let keys = ["format", "recordedGames", "schemaVersion", "tables"].compactMap { text.range(of: "\"\($0)\"")?.lowerBound }
        #expect(keys.count == 4 && keys == keys.sorted())
        #expect(!fileNames(root).contains { $0.contains("tmp") })
    }

    @Test("SAV-050 unreadable files are quarantined (empty tables); future versions stay and refuse writes; unknown tables survive")
    func robustness() throws {
        let root = makeTempRoot()
        defer { cleanUp(root) }
        let store = HighScoreStore(root: root)
        let bad: [Data] = [Data("not json".utf8), Data(#"{"format":"other","schemaVersion":1,"tables":{}}"#.utf8),
                           Data(#"{"format":"parsec-merchant-highscores","schemaVersion":1,"tables":{"modern":42}}"#.utf8)]
        for (i, data) in bad.enumerated() {
            try data.write(to: store.fileURL)
            #expect(try store.load().isEmpty)
            #expect(!FileOps.exists(store.fileURL))
            #expect(fileNames(store.corruptDirectory).count == i + 1)
        }
        #expect(fileNames(store.corruptDirectory) == ["1-HighScores.json", "2-HighScores.json", "HighScores.json"])
        // A future version: left in place, reads as empty, writes throw.
        let future = Data(#"{"format":"parsec-merchant-highscores","schemaVersion":9,"tables":{}}"#.utf8)
        try future.write(to: store.fileURL)
        #expect(try store.load().isEmpty)
        #expect(throws: SaveError.unsupportedFutureVersion(9)) { try store.clear(.modern) }
        #expect(throws: SaveError.unsupportedFutureVersion(9)) { try store.record(newState(), end: .retired, gameID: "x") }
        #expect(try Data(contentsOf: store.fileURL) == future)
        // Tables under ruleset ids this build doesn't know are kept verbatim on rewrite.
        let alien = #"{"format":"parsec-merchant-highscores","schemaVersion":1,"tables":{"amiga":{"weird":[1,2,3]}}}"#
        try Data(alien.utf8).write(to: store.fileURL)
        try store.save([.modern: HighScoreTable().inserting(entry("A", score: 1)).0])
        let tables = try #require(try rawFile(store)["tables"] as? [String: Any])
        #expect((tables["amiga"] as? [String: Any])?["weird"] as? [Int] == [1, 2, 3])
        #expect(try tables["modern"] != nil && store.load().count == 1)
    }
}

@Suite("SCORE high-score recording and clearing (SCORE-037/038)")
struct HighScoreRecordingSpecTests {
    @Test("SCORE-037 an ended game's entry is recorded exactly once, even when the game is reopened")
    func recordOnce() throws {
        let root = makeTempRoot()
        defer { cleanUp(root) }
        let store = HighScoreStore(root: root)
        var engine = GameEngine(state: dayState(20))
        engine.state.commander.cash = 50_000
        engine.perform(.retire, acknowledging: [.retire])
        let outcome = try store.record(engine.state, end: .retired, gameID: "game-1")
        #expect(outcome == .entered(rank: 1))
        #expect(try store.record(engine.state, end: .retired, gameID: "game-1") == nil)
        #expect(try store.table(for: .modern).entries.count == 1)
        // A different game with the same state is a separate entry.
        #expect(try store.record(engine.state, end: .retired, gameID: "game-2") == .entered(rank: 2))
        // Missed and excluded games are recorded too, so reopening them never inserts later.
        var cheat = engine.state
        cheat.cheatsUsed = true
        #expect(try store.record(cheat, end: .retired, gameID: "game-3") == .excludedForCheats)
        try store.clear(.modern)
        #expect(try store.record(cheat, end: .retired, gameID: "game-3") == nil)
        #expect(try store.table(for: .modern).entries.isEmpty)
    }

    @Test("SCORE-038 tables start empty; clearing one ruleset's table leaves the others")
    func clearTable() throws {
        let root = makeTempRoot()
        defer { cleanUp(root) }
        let store = HighScoreStore(root: root)
        for id in RulesetID.allCases { #expect(try store.table(for: id) == HighScoreTable()) }
        #expect(HighScoreTable().entries.isEmpty && HighScoreTable.capacity == 10)
        try store.save([.modern: HighScoreTable().inserting(entry("M", score: 5)).0,
                        .windows201: HighScoreTable().inserting(entry("W", score: 6, .windows201)).0])
        try store.clear(.modern)
        #expect(try store.table(for: .modern).entries.isEmpty)
        #expect(try store.table(for: .windows201).entries.map(\.name) == ["W"])
    }
}
