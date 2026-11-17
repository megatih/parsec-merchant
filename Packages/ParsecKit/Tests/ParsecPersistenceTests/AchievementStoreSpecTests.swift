// SPDX-License-Identifier: GPL-2.0-or-later
// ACH §3 (ACH-011…015): the app-wide Achievements.json store.
import Foundation
import Testing
import ParsecEngine
import ParsecInsights
@testable import ParsecPersistence

private let fixedClock: @Sendable () -> Date = { Date(timeIntervalSince1970: 1_800_000_000) }

private func raw(_ store: AchievementStore) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as? [String: Any])
}

@Suite("ACH achievement store")
struct AchievementStoreSpecTests {
    @Test("ACH-011 Achievements.json: format, schemaVersion 1, records sorted by id, ISO 8601 UTC, sorted keys, atomic")
    func fileShape() throws {
        let root = makeTempRoot()
        defer { cleanUp(root) }
        var store = AchievementStore(root: root, clock: fixedClock)
        #expect(try store.records().isEmpty)
        try store.unlock([AchievementID.wormhole.rawValue, AchievementID.firstProfit.rawValue], gameID: "g1", rulesetID: "modern", day: 12)
        let object = try raw(store)
        #expect(object["format"] as? String == "parsec-merchant-achievements" && object["schemaVersion"] as? Int == 1)
        let records = try store.records()
        #expect(records.map(\.id) == ["firstProfit", "wormhole"])
        #expect(records[0] == AchievementRecord(id: "firstProfit", unlockedAt: "2027-01-15T08:00:00Z", gameID: "g1", rulesetID: "modern",
                                                day: 12))
        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        let keys = ["format", "schemaVersion", "unlocked"].compactMap { text.range(of: "\"\($0)\"")?.lowerBound }
        #expect(keys.count == 3 && keys == keys.sorted())
        #expect(!fileNames(root).contains { $0.contains("tmp") })
        // Unknown ids (from a newer app) are kept and rewritten unchanged.
        try store.unlock(["futureAchievement"], gameID: "g2", rulesetID: "palm122", day: 1)
        try store.unlock(["bigScore"], gameID: "g2", rulesetID: "palm122", day: 2)
        #expect(try store.records().map(\.id) == ["bigScore", "firstProfit", "futureAchievement", "wormhole"])
    }

    @Test("ACH-012 unlock adds only new ids and returns them; first unlock wins; records and isUnlocked read it")
    func unlockIdempotent() throws {
        let root = makeTempRoot()
        defer { cleanUp(root) }
        var store = AchievementStore(root: root, clock: fixedClock)
        #expect(try store.unlock(["hero", "hero"], gameID: "a", rulesetID: "modern", day: 3) == ["hero"])
        var later = AchievementStore(root: root) { Date(timeIntervalSince1970: 1_900_000_000) }
        #expect(try later.unlock(["hero", "villain"], gameID: "b", rulesetID: "modern", day: 9) == ["villain"])
        let hero = try #require(try later.records().first { $0.id == "hero" })
        #expect(hero.gameID == "a" && hero.day == 3 && hero.unlockedAt == "2027-01-15T08:00:00Z")
        #expect(try later.isUnlocked("villain") && !later.isUnlocked("moon"))
        #expect(try later.unlock([], gameID: "c", rulesetID: "modern", day: 1).isEmpty)
    }

    @Test("ACH-013 unreadable files are quarantined (empty store); a future schema stays in place and is never written")
    func robustness() throws {
        let root = makeTempRoot()
        defer { cleanUp(root) }
        var store = AchievementStore(root: root, clock: fixedClock)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.fileURL)
        #expect(try store.records().isEmpty)
        #expect(fileNames(root.appendingPathComponent("Corrupt")) == ["Achievements.json"])
        try Data(#"{"format":"parsec-merchant-achievements","schemaVersion":1,"unlocked":"x"}"#.utf8).write(to: store.fileURL)
        #expect(try store.records().isEmpty)
        let future = Data(#"{"format":"parsec-merchant-achievements","schemaVersion":7,"unlocked":[]}"#.utf8)
        try future.write(to: store.fileURL)
        #expect(try store.unlock(["moon"], gameID: "g", rulesetID: "modern", day: 1) == ["moon"])
        #expect(!store.isPersisting && store.sessionOnly.map(\.id) == ["moon"])
        #expect(try Data(contentsOf: store.fileURL) == future)
        #expect(try store.records().map(\.id) == ["moon"] && store.isUnlocked("moon"))
        #expect(try store.unlock(["moon"], gameID: "g", rulesetID: "modern", day: 2).isEmpty)
        try store.reset()
        #expect(try Data(contentsOf: store.fileURL) == future && store.sessionOnly.isEmpty)
    }

    @Test("ACH-014 reset writes an empty list")
    func reset() throws {
        let root = makeTempRoot()
        defer { cleanUp(root) }
        var store = AchievementStore(root: root, clock: fixedClock)
        try store.unlock(["moon", "hero"], gameID: "g", rulesetID: "modern", day: 1)
        try store.reset()
        #expect(try store.records().isEmpty && (raw(store)["unlocked"] as? [Any])?.isEmpty == true)
        #expect(try store.unlock(["moon"], gameID: "g", rulesetID: "modern", day: 2) == ["moon"])
    }

    @Test("ACH-015 app-wide unlocks live in the store, per-game unlock events in the journal; a reset clears only the store")
    func storeVersusJournal() throws {
        let root = makeTempRoot()
        defer { cleanUp(root) }
        var store = AchievementStore(root: root, clock: fixedClock)
        let state = newState(.modern)
        var journal = GameJournal.start(state: state)
        var s = state
        s.commander.ship.cargo[0] = 1
        s.commander.priceCargo[0] = 1
        var engine = GameEngine(state: s)
        let result = engine.perform(.sellCargo(.water, quantity: 1))
        let out = JournalRecorder.record(JournalStep(command: .sellCargo(.water, quantity: 1), before: s, result: result,
                                                     after: engine.state), into: &journal)
        let added = try store.unlock(out.unlocked.map(\.rawValue), gameID: "g", rulesetID: s.rulesetID.rawValue, day: s.commander.days)
        #expect(added == ["firstProfit"])
        try store.reset()
        #expect(try store.records().isEmpty && journal.entries.contains { $0.kind == .achievementUnlocked(.firstProfit) })
    }
}
