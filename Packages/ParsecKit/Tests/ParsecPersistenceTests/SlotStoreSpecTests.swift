// SPDX-License-Identifier: GPL-2.0-or-later
// SAV §4–7: store layout, atomic writes, backups, listing, quarantine, recovery, delete, import/export, generations.
import Foundation
import Testing
@testable import ParsecEngine
@testable import ParsecPersistence

/// A state on day `day` (a cheap way to tell versions apart).
func dayState(_ day: Int, _ ruleset: RulesetID = .modern, ironman: Bool = false) -> GameState {
    var s = newState(ruleset, ironman: ironman)
    s.commander.days = day
    return s
}

func setModified(_ url: URL, _ seconds: TimeInterval) throws {
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: seconds)], ofItemAtPath: url.path)
}

@Suite("SAV store layout and writes (SAV §4)")
struct SlotStoreLayoutSpecTests {
    @Test("SAV-017 SAV-019 layout: slot-<uuid>.parsecsave, .bakN, autosave.parsecsave, Corrupt/, HighScores.json")
    func layout() throws {
        let root = makeTempRoot()
        defer { cleanUp(root) }
        let store = SlotStore(root: root, appVersion: "t")
        #expect(fileNames(root).isEmpty)  // nothing is created before the first write
        let id = SlotStore.newSlotID()
        #expect(id == id.lowercased() && UUID(uuidString: id) != nil && id != SlotStore.autosaveID)
        #expect(SlotStore.newSlotID() != id)
        try store.save(dayState(1), slot: id, gameID: "g")
        try store.save(dayState(2), slot: id, gameID: "g")
        try store.autosave(dayState(3), gameID: "g")
        #expect(fileNames(store.savesDirectory) == ["autosave.parsecsave", "slot-\(id).parsecsave", "slot-\(id).parsecsave.bak1"])
        #expect(store.url(forSlot: SlotStore.autosaveID).lastPathComponent == "autosave.parsecsave")
        #expect(store.corruptDirectory == root.appendingPathComponent("Corrupt", isDirectory: true))
        #expect(HighScoreStore(root: root).fileURL == root.appendingPathComponent("HighScores.json"))
        try Data("junk".utf8).write(to: store.url(forSlot: SlotStore.newSlotID()))
        _ = try store.list()
        #expect(fileNames(root) == ["Corrupt", "Saves"])
    }

    @Test("SAV-018 ALR-092 writes are atomic: no temp files remain, and a failed write keeps the old bytes and throws")
    func atomicWrites() throws {
        let root = makeTempRoot()
        defer { cleanUp(root) }
        let store = SlotStore(root: root, appVersion: "t")
        let id = SlotStore.newSlotID()
        for d in 1...5 { try store.save(dayState(d), slot: id, gameID: "g") }
        try store.autosave(dayState(9), gameID: "g")
        try HighScoreStore(root: root).clear(.modern)
        #expect(!fileNames(store.savesDirectory).contains { $0.contains("tmp") })
        #expect(!fileNames(root).contains { $0.contains("tmp") })
        // A read-only Saves/ makes the write fail (the app shows SystemAlert.saveFailed): the old file is intact.
        let before = try Data(contentsOf: store.url(forSlot: SlotStore.autosaveID))
        let fm = FileManager.default
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: store.savesDirectory.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: store.savesDirectory.path) }
        #expect(throws: (any Error).self) { try store.autosave(dayState(10), gameID: "g") }
        #expect(try Data(contentsOf: store.url(forSlot: SlotStore.autosaveID)) == before)
        #expect(!fileNames(store.savesDirectory).contains { $0.contains("tmp") })
    }

    @Test("SAV-020 manual saves rotate .bak1…3 (bak1 = previous version); a new slot and the autosave have none")
    func rotation() throws {
        let root = makeTempRoot()
        defer { cleanUp(root) }
        let store = SlotStore(root: root, appVersion: "t")
        let id = SlotStore.newSlotID()
        for k in 1...6 {
            try store.save(dayState(k), slot: id, gameID: "g")
            let backups = (1...3).filter { FileOps.exists(store.backupURL(forSlot: id, index: $0)) }
            #expect(backups == (k > 1 ? Array(1...min(k - 1, 3)) : []), "after \(k) saves")
            #expect(try store.load(slot: id).state.commander.days == k)
            for i in backups {
                let old = try SaveCodec.decode(Data(contentsOf: store.backupURL(forSlot: id, index: i)))
                #expect(old.state.commander.days == k - i)
            }
        }
        for d in 1...3 { try store.autosave(dayState(d), gameID: "g") }
        #expect(!fileNames(store.savesDirectory).contains { $0.hasPrefix("autosave.parsecsave.bak") })
    }

    @Test("SAV-021 an Ironman save creates no backups and deletes existing ones")
    func ironmanBackups() throws {
        let root = makeTempRoot()
        defer { cleanUp(root) }
        let store = SlotStore(root: root, appVersion: "t")
        let id = SlotStore.newSlotID()
        for d in 1...4 { try store.save(dayState(d), slot: id, gameID: id) }
        #expect(fileNames(store.savesDirectory).count == 4)
        for d in 5...7 { try store.save(dayState(d, ironman: true), slot: id, gameID: id) }
        #expect(fileNames(store.savesDirectory) == ["slot-\(id).parsecsave"])
        #expect(try store.load(slot: id).state.commander.days == 7)
    }
}

@Suite("SAV listing, loading, quarantine and recovery (SAV §5)")
struct SlotStoreReadSpecTests {
    @Test("SAV-022 list: main files only, newest first, ties by id; other names ignored and left alone")
    func listing() throws {
        let root = makeTempRoot()
        defer { cleanUp(root) }
        let store = SlotStore(root: root, appVersion: "t")
        #expect(try store.list().isEmpty)  // no Saves/ yet
        let a = "00000000-0000-4000-8000-00000000000a", b = "00000000-0000-4000-8000-00000000000b"
        let c = "00000000-0000-4000-8000-00000000000c"
        try store.save(dayState(1), slot: a, gameID: "ga")
        try store.save(dayState(2), slot: a, gameID: "ga")  // creates a.bak1
        try store.save(dayState(3, .palm122), slot: b, gameID: "gb")
        try store.save(dayState(4), slot: c, gameID: "gc")
        try store.autosave(dayState(5, ironman: false), gameID: "ga")
        try setModified(store.url(forSlot: a), 1_000)
        try setModified(store.url(forSlot: b), 3_000)
        try setModified(store.url(forSlot: c), 3_000)
        try setModified(store.url(forSlot: SlotStore.autosaveID), 2_000)
        let ignored = ["notes.txt", "slot-NOT-A-UUID.parsecsave", "slot-\(a)-copy.parsecsave", ".slot.tmp-x", "other.parsecsave"]
        for name in ignored { try Data("x".utf8).write(to: store.savesDirectory.appendingPathComponent(name)) }
        let list = try store.list()
        #expect(list.map(\.id) == [b, c, SlotStore.autosaveID, a])
        let first = try #require(list.first)
        #expect(first.rulesetID == .palm122 && first.gameID == "gb" && first.generation == 1 && !first.isAutosave)
        #expect(first.summary.day == 3 && !first.recoveredFromBackup && first.url == store.url(forSlot: b))
        #expect(list[2].isAutosave && list[2].gameID == "ga")
        #expect(list[3].summary.day == 2)
        for name in ignored { #expect(FileOps.exists(store.savesDirectory.appendingPathComponent(name))) }
        #expect(!FileOps.exists(store.corruptDirectory))
    }

    @Test("SAV-023 loading never rewrites the file")
    func loadDoesNotWrite() throws {
        let root = makeTempRoot()
        defer { cleanUp(root) }
        let store = SlotStore(root: root, appVersion: "t")
        let id = SlotStore.newSlotID()
        // A valid but non-canonical (compact) file stays byte-for-byte as it is after load and list.
        let compact = try editedSave(dayState(8)) { _ in }
        try FileManager.default.createDirectory(at: store.savesDirectory, withIntermediateDirectories: true)
        try compact.write(to: store.url(forSlot: id))
        try setModified(store.url(forSlot: id), 5_000)
        #expect(try store.load(slot: id).state.commander.days == 8)
        _ = try store.list()
        #expect(try Data(contentsOf: store.url(forSlot: id)) == compact)
        let date = try store.url(forSlot: id).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        #expect(date == Date(timeIntervalSince1970: 5_000))
        // The next save writes the canonical current format.
        try store.save(dayState(9), slot: id, gameID: "g")
        #expect(try Data(contentsOf: store.url(forSlot: id)) == SaveCodec.encode(store.load(slot: id)))
    }

    @Test("SAV-024 ALR-091 unreadable files move to Corrupt/ (numbered on clashes); future versions stay and are not listed")
    func quarantine() throws {
        let root = makeTempRoot()
        defer { cleanUp(root) }
        let store = SlotStore(root: root, appVersion: "t")
        let id = SlotStore.newSlotID()
        try FileManager.default.createDirectory(at: store.savesDirectory, withIntermediateDirectories: true)
        let main = store.url(forSlot: id)
        try Data("garbage".utf8).write(to: main)
        #expect(saveError { _ = try store.load(slot: id) } == .notASave)
        #expect(!FileOps.exists(main) && fileNames(store.corruptDirectory) == [main.lastPathComponent])
        // The same name again (via list) gets the 1- prefix; corrupt saves are quarantined like notASave.
        try editedSave { $0["state"] = 1 }.write(to: main)
        #expect(try store.list().isEmpty)
        #expect(fileNames(store.corruptDirectory) == ["1-" + main.lastPathComponent, main.lastPathComponent])
        try editedSave { $0["state"] = 1 }.write(to: main)
        if case .corrupt = saveError({ _ = try store.load(slot: id) }) {} else { Issue.record("expected corrupt") }
        #expect(fileNames(store.corruptDirectory).count == 3)
        // The quarantined bytes are moved, not altered.
        #expect(try Data(contentsOf: store.corruptDirectory.appendingPathComponent(main.lastPathComponent)) == Data("garbage".utf8))
        // A newer app's save is left in place and omitted.
        let future = try editedSave { $0["schemaVersion"] = 99 }
        try future.write(to: main)
        #expect(saveError { _ = try store.load(slot: id) } == .unsupportedFutureVersion(99))
        #expect(try store.list().isEmpty)
        #expect(try Data(contentsOf: main) == future && fileNames(store.corruptDirectory).count == 3)
    }

    @Test("SAV-025 recovery: the first readable backup replaces an unreadable main; unreadable backups are quarantined")
    func recovery() throws {
        let root = makeTempRoot()
        defer { cleanUp(root) }
        let store = SlotStore(root: root, appVersion: "t")
        let id = SlotStore.newSlotID()
        for d in 1...4 { try store.save(dayState(d), slot: id, gameID: "g") }  // main 4, bak1 3, bak2 2, bak3 1
        try Data("bad main".utf8).write(to: store.url(forSlot: id))
        try Data("bad bak1".utf8).write(to: store.backupURL(forSlot: id, index: 1))
        let info = try store.info(slot: id)
        #expect(info.recoveredFromBackup && info.summary.day == 2)
        #expect(fileNames(store.savesDirectory) == ["slot-\(id).parsecsave", "slot-\(id).parsecsave.bak3"])
        #expect(fileNames(store.corruptDirectory) == ["slot-\(id).parsecsave", "slot-\(id).parsecsave.bak1"])
        #expect(try store.load(slot: id).state.commander.days == 2 && !store.info(slot: id).recoveredFromBackup)
        // Through list() too.
        try Data("bad again".utf8).write(to: store.url(forSlot: id))
        let listed = try #require(try store.list().first)
        #expect(listed.recoveredFromBackup && listed.summary.day == 1)
        // No readable backup left: load rethrows the main file's error and the slot disappears.
        try Data("bad".utf8).write(to: store.url(forSlot: id))
        #expect(saveError { _ = try store.load(slot: id) } == .notASave)
        #expect(try store.list().isEmpty)
        #expect(fileNames(store.corruptDirectory).count == 4)
    }

    @Test("SAV-026 delete removes the main file and all backups; missing slots are a no-op; the autosave can be deleted")
    func delete() throws {
        let root = makeTempRoot()
        defer { cleanUp(root) }
        let store = SlotStore(root: root, appVersion: "t")
        let id = SlotStore.newSlotID(), keep = SlotStore.newSlotID()
        for d in 1...5 { try store.save(dayState(d), slot: id, gameID: "g") }
        try store.save(dayState(1), slot: keep, gameID: "k")
        try store.autosave(dayState(1), gameID: "g")
        try store.delete(slot: id)
        try store.delete(slot: SlotStore.newSlotID())
        try store.delete(slot: SlotStore.autosaveID)
        #expect(fileNames(store.savesDirectory) == ["slot-\(keep).parsecsave"])
    }
}

@Suite("SAV import, export and game identity (SAV §6–7)")
struct SlotStoreImportSpecTests {
    @Test("SAV-027 import validates, writes a new slot with a fresh gameID at the current schema; failures write nothing")
    func importSave() throws {
        let root = makeTempRoot()
        defer { cleanUp(root) }
        let store = SlotStore(root: root, appVersion: "t")
        let data = try editedSave(dayState(12)) { _ in }
        let id = try store.importSave(data)
        #expect(UUID(uuidString: id) != nil && id == id.lowercased())
        let env = try store.load(slot: id)
        #expect(env.gameID != "g" && UUID(uuidString: env.gameID) != nil && env.schemaVersion == SaveMigrator.currentSchemaVersion)
        #expect(env.state.commander.days == 12 && env.generation == 1)
        #expect(try Data(contentsOf: store.url(forSlot: id)) == SaveCodec.encode(env))
        let second = try store.importSave(data)
        #expect(try second != id && store.load(slot: second).gameID != env.gameID)
        // Bad data: rethrown, nothing written or quarantined.
        let names = fileNames(store.savesDirectory)
        #expect(saveError { _ = try store.importSave(Data("nope".utf8)) } == .notASave)
        #expect(saveError { _ = try store.importSave(editedSave { $0["schemaVersion"] = 7 }) } == .unsupportedFutureVersion(7))
        #expect(fileNames(store.savesDirectory) == names && !FileOps.exists(store.corruptDirectory))
    }

    @Test("SAV-028 an import is never Ironman and counts as a reload; cheatsUsed and the rest are kept")
    func importClearsIronman() throws {
        let root = makeTempRoot()
        defer { cleanUp(root) }
        let store = SlotStore(root: root, appVersion: "t")
        var state = dayState(30, .palm122, ironman: true)
        state.reloadCount = 2
        state.cheatsUsed = true
        let id = try store.importSave(editedSave(state) { _ in })
        let got = try store.load(slot: id).state
        #expect(!got.ironman && got.reloadCount == 3 && got.cheatsUsed)
        var expected = state
        expected.ironman = false
        expected.reloadCount = 3
        #expect(got == expected)
    }

    @Test("SAV-029 export returns the file's canonical bytes for any slot, including the autosave and an Ironman slot")
    func export() throws {
        let root = makeTempRoot()
        defer { cleanUp(root) }
        let store = SlotStore(root: root, appVersion: "t")
        let id = SlotStore.newSlotID()
        try store.save(dayState(3), slot: id, gameID: "g")
        try store.autosave(dayState(4), gameID: "g")
        let iron = SlotStore.newSlotID()
        try store.save(dayState(5, ironman: true), slot: iron, gameID: iron)
        for slot in [id, SlotStore.autosaveID, iron] {
            #expect(try store.exportSave(slot: slot) == Data(contentsOf: store.url(forSlot: slot)))
        }
        let back = try store.importSave(store.exportSave(slot: iron))
        #expect(try !store.load(slot: back).state.ironman && store.load(slot: back).state.reloadCount == 1)
    }

    @Test("SAV-031 the gameID travels with every envelope of a game, is kept by load and is not part of GameState")
    func gameID() throws {
        let root = makeTempRoot()
        defer { cleanUp(root) }
        let store = SlotStore(root: root, appVersion: "t")
        let game = SlotStore.newSlotID()
        let a = SlotStore.newSlotID(), b = SlotStore.newSlotID()
        try store.save(dayState(1), slot: a, gameID: game)
        try store.save(dayState(2), slot: b, gameID: game)
        try store.autosave(dayState(3), gameID: game)
        for slot in [a, b, SlotStore.autosaveID] { #expect(try store.load(slot: slot).gameID == game) }
        #expect(try store.loadForPlay(slot: a, revert: false, currentGameID: nil).gameID == game)
        let stateJSON = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(dayState(1))) as? [String: Any])
        #expect(stateJSON["gameID"] == nil && stateJSON["generation"] == nil)
        // Two saves of the same state under different games carry identical states.
        try store.save(dayState(1), slot: b, gameID: "other")
        #expect(try store.load(slot: a).state == store.load(slot: b).state)
    }

    @Test("SAV-032 each write is stamped 1 + the highest generation of that game on disk")
    func generations() throws {
        let root = makeTempRoot()
        defer { cleanUp(root) }
        let store = SlotStore(root: root, appVersion: "t")
        let a = SlotStore.newSlotID(), b = SlotStore.newSlotID(), c = SlotStore.newSlotID()
        try store.save(dayState(1), slot: a, gameID: "G")
        try store.save(dayState(2), slot: b, gameID: "G")
        try store.autosave(dayState(3), gameID: "G")
        try store.save(dayState(4), slot: a, gameID: "G")
        try store.save(dayState(1), slot: c, gameID: "H")
        #expect(try store.load(slot: b).generation == 2)
        #expect(try store.load(slot: SlotStore.autosaveID).generation == 3)
        #expect(try store.load(slot: a).generation == 4)
        #expect(try store.load(slot: c).generation == 1)
        let newest = try store.list().filter { $0.gameID == "G" }.max { $0.generation < $1.generation }
        #expect(newest?.id == a)
    }
}
