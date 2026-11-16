// SPDX-License-Identifier: GPL-2.0-or-later
// Shoebox save slots (docs/specs/SAV.md §4–8, §11, PRD §6.4): URL-injected root, atomic writes, rotating backups,
// autosave, import/export, game generations, reload accounting and quarantine in Corrupt/ (never deleted).
import Foundation
import ParsecEngine

/// SAV-022: one listed save.
public struct SlotInfo: Sendable, Equatable {
    public var id: String
    public var url: URL
    public var summary: SaveSummary
    public var rulesetID: RulesetID
    public var gameID: String
    public var generation: Int
    public var modified: Date
    public var isAutosave: Bool
    /// SAV-025: the main file was unreadable and a backup took its place during this read.
    public var recoveredFromBackup: Bool
}

/// SAV-034: a slot loaded for play.
public struct LoadedGame: Sendable, Equatable {
    /// The state after `resumedAfterLoad(countsAsReload:)`.
    public var state: GameState
    public var gameID: String
    public var slotID: String
    public var countedAsReload: Bool
    public var recoveredFromBackup: Bool
}

public struct SlotStore: Sendable {
    public static let fileExtension = "parsecsave"
    public static let backupCount = 3
    public static let autosaveID = "autosave"

    public let root: URL
    public let appVersion: String

    public init(root: URL, appVersion: String) {
        self.root = root
        self.appVersion = appVersion
    }

    public var savesDirectory: URL { root.appendingPathComponent("Saves", isDirectory: true) }
    public var corruptDirectory: URL { root.appendingPathComponent("Corrupt", isDirectory: true) }

    /// SAV-017/019: `Saves/slot-<id>.parsecsave`, or `Saves/autosave.parsecsave` for the reserved id.
    public func url(forSlot id: String) -> URL {
        let name = id == Self.autosaveID ? Self.autosaveID : "slot-\(id)"
        return savesDirectory.appendingPathComponent("\(name).\(Self.fileExtension)")
    }

    func backupURL(forSlot id: String, index: Int) -> URL {
        url(forSlot: id).appendingPathExtension("bak\(index)")
    }

    /// SAV-019: a fresh lowercase UUID, never `"autosave"`.
    public static func newSlotID() -> String { UUID().uuidString.lowercased() }

    /// The slot id of a main file name, or nil when the name is not a slot (SAV-022).
    static func slotID(forFileName name: String) -> String? {
        if name == "\(autosaveID).\(fileExtension)" { return autosaveID }
        let prefix = "slot-", suffix = ".\(fileExtension)"
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return nil }
        let id = String(name.dropFirst(prefix.count).dropLast(suffix.count))
        guard let uuid = UUID(uuidString: id), uuid.uuidString.lowercased() == id else { return nil }
        return id
    }

    // MARK: Writing

    /// SAV-018/020/021/032: writes `state` of game `gameID` to a slot atomically, stamped with the next generation of
    /// that game. A non-Ironman manual slot rotates `.bak1…bak3` first; an Ironman state deletes its backups; the
    /// autosave keeps none.
    @discardableResult
    public func save(_ state: GameState, slot id: String, gameID: String) throws -> URL {
        let generation = 1 + (readableMainFiles().filter { $0.envelope.gameID == gameID }.map(\.envelope.generation).max() ?? 0)
        let envelope = SaveEnvelope(state: state, appVersion: appVersion, gameID: gameID, generation: generation)
        let data = try SaveCodec.encode(envelope)
        let target = url(forSlot: id)
        let fm = FileManager.default
        if state.ironman {
            for i in 1...Self.backupCount where FileOps.exists(backupURL(forSlot: id, index: i)) {
                try fm.removeItem(at: backupURL(forSlot: id, index: i))
            }
        } else if id != Self.autosaveID, FileOps.exists(target) {
            let oldest = backupURL(forSlot: id, index: Self.backupCount)
            if FileOps.exists(oldest) { try fm.removeItem(at: oldest) }
            for i in stride(from: Self.backupCount - 1, through: 1, by: -1) {
                let from = backupURL(forSlot: id, index: i)
                if FileOps.exists(from) { try fm.moveItem(at: from, to: backupURL(forSlot: id, index: i + 1)) }
            }
            try FileOps.atomicWrite(Data(contentsOf: target), to: backupURL(forSlot: id, index: 1))
        }
        try FileOps.atomicWrite(data, to: target)
        return target
    }

    /// Writes the autosave (SAV-019).
    @discardableResult
    public func autosave(_ state: GameState, gameID: String) throws -> URL {
        try save(state, slot: Self.autosaveID, gameID: gameID)
    }

    // MARK: Reading

    /// Every main file that decodes, without quarantining anything (generation bookkeeping, SAV-032/035).
    func readableMainFiles() -> [(id: String, envelope: SaveEnvelope)] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: savesDirectory.path) else { return [] }
        return names.sorted().compactMap { name in
            guard let id = Self.slotID(forFileName: name),
                  let data = try? Data(contentsOf: savesDirectory.appendingPathComponent(name)),
                  let envelope = try? SaveCodec.decode(data) else { return nil }
            return (id, envelope)
        }
    }

    /// SAV-023…025: reads a slot's main file; an unreadable one is quarantined and replaced by the first readable
    /// backup. A future-version file is left alone and its error rethrown.
    func read(slot id: String) throws -> (envelope: SaveEnvelope, recovered: Bool) {
        let main = url(forSlot: id)
        let data = try Data(contentsOf: main)
        let mainError: SaveError
        do {
            return (try SaveCodec.decode(data), false)
        } catch let error as SaveError {
            if case .unsupportedFutureVersion = error { throw error }
            mainError = error
        }
        try FileOps.quarantine(main, into: corruptDirectory)
        for i in 1...Self.backupCount {
            let backup = backupURL(forSlot: id, index: i)
            guard let bytes = try? Data(contentsOf: backup) else { continue }
            let envelope: SaveEnvelope
            do {
                envelope = try SaveCodec.decode(bytes)
            } catch SaveError.unsupportedFutureVersion {
                continue  // a newer app can read it: leave it where it is
            } catch {
                try FileOps.quarantine(backup, into: corruptDirectory)
                continue
            }
            try FileManager.default.moveItem(at: backup, to: main)
            return (envelope, true)
        }
        throw mainError
    }

    /// SAV-023: the decoded, migrated envelope. Never rewrites the file (except quarantine and backup recovery).
    public func load(slot id: String) throws -> SaveEnvelope { try read(slot: id).envelope }

    /// The slot's listing entry, after any quarantine or backup recovery.
    public func info(slot id: String) throws -> SlotInfo {
        let (envelope, recovered) = try read(slot: id)
        return makeInfo(id: id, envelope: envelope, recovered: recovered)
    }

    private func makeInfo(id: String, envelope: SaveEnvelope, recovered: Bool) -> SlotInfo {
        let file = url(forSlot: id)
        let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        return SlotInfo(id: id, url: file, summary: envelope.summary, rulesetID: envelope.rulesetID, gameID: envelope.gameID,
                        generation: envelope.generation, modified: date, isAutosave: id == Self.autosaveID,
                        recoveredFromBackup: recovered)
    }

    /// SAV-022/024/025: readable saves, newest first (ties by id). Unreadable main files are quarantined (with backup
    /// recovery); future-version files are skipped and left in place; backups and other names are ignored.
    public func list() throws -> [SlotInfo] {
        guard FileOps.exists(savesDirectory) else { return [] }
        let names = try FileManager.default.contentsOfDirectory(atPath: savesDirectory.path)
        var infos: [SlotInfo] = []
        for name in names.sorted() {
            guard let id = Self.slotID(forFileName: name) else { continue }
            guard let info = try? info(slot: id) else { continue }
            infos.append(info)
        }
        return infos.sorted { $0.modified != $1.modified ? $0.modified > $1.modified : $0.id < $1.id }
    }

    /// SAV-026: removes a slot and its backups; a missing slot is a no-op.
    public func delete(slot id: String) throws {
        let fm = FileManager.default
        for url in [url(forSlot: id)] + (1...Self.backupCount).map({ backupURL(forSlot: id, index: $0) })
        where FileOps.exists(url) {
            try fm.removeItem(at: url)
        }
    }

    // MARK: Import, export, play

    /// SAV-027/028: validates and migrates `data`, then writes it to a new slot under a fresh `gameID`, with Ironman
    /// cleared and the import counted as a reload. Nothing is written when decoding fails.
    public func importSave(_ data: Data) throws -> String {
        var state = try SaveCodec.decode(data).state
        state.ironman = false
        state.reloadCount += 1
        let id = Self.newSlotID()
        try save(state, slot: id, gameID: Self.newSlotID())
        return id
    }

    /// SAV-029: the canonical bytes of the loaded envelope (equal to the file for a current-schema slot).
    public func exportSave(slot id: String) throws -> Data {
        try SaveCodec.encode(load(slot: id))
    }

    /// SAV-035: whether loading `envelope` for play counts as a reload. `currentGameID` is the game in memory, or nil
    /// when none is loaded or it has ended.
    func countsAsReload(_ envelope: SaveEnvelope, revert: Bool, currentGameID: String?) -> Bool {
        if envelope.state.ironman { return false }
        if revert { return true }
        if envelope.gameID == currentGameID { return true }
        return readableMainFiles().contains { $0.envelope.gameID == envelope.gameID && $0.envelope.generation > envelope.generation }
    }

    /// SAV-034…036: loads a slot for play. `currentGameID` is the game in memory, or nil when no game is loaded or the
    /// loaded game has ended.
    public func loadForPlay(slot id: String, revert: Bool, currentGameID: String?) throws -> LoadedGame {
        let (envelope, recovered) = try read(slot: id)
        let reload = countsAsReload(envelope, revert: revert, currentGameID: currentGameID)
        return LoadedGame(state: envelope.state.resumedAfterLoad(countsAsReload: reload), gameID: envelope.gameID, slotID: id,
                          countedAsReload: reload, recoveredFromBackup: recovered)
    }
}
