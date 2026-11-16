// SPDX-License-Identifier: GPL-2.0-or-later
// Shoebox save slots (docs/specs/SAV.md, PRD §6.4): URL-injected root, atomic writes, rotating backups,
// autosave, import/export, and quarantine of unreadable files in Corrupt/ (never deleted).
import Foundation
import ParsecEngine

/// One listed save.
public struct SlotInfo: Sendable, Equatable {
    public var id: String
    public var url: URL
    public var summary: SaveSummary
    public var rulesetID: RulesetID
    public var modified: Date
    public var isAutosave: Bool
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

    public func url(forSlot id: String) -> URL {
        let name = id == Self.autosaveID ? Self.autosaveID : "slot-\(id)"
        return savesDirectory.appendingPathComponent("\(name).\(Self.fileExtension)")
    }

    func backupURL(forSlot id: String, index: Int) -> URL {
        url(forSlot: id).appendingPathExtension("bak\(index)")
    }

    private func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: savesDirectory, withIntermediateDirectories: true)
    }

    /// Creates a new slot id (a lowercase UUID).
    public static func newSlotID() -> String { UUID().uuidString.lowercased() }

    /// Writes `state` to a slot atomically; the previous file rotates into `.bak1…bak3` (autosave keeps no backups).
    @discardableResult
    public func save(_ state: GameState, slot id: String) throws -> URL {
        try ensureDirectories()
        let data = try SaveCodec.encode(SaveEnvelope(state: state, appVersion: appVersion))
        let target = url(forSlot: id)
        let fm = FileManager.default
        if id != Self.autosaveID, fm.fileExists(atPath: target.path) {
            let oldest = backupURL(forSlot: id, index: Self.backupCount)
            if fm.fileExists(atPath: oldest.path) { try fm.removeItem(at: oldest) }
            for i in stride(from: Self.backupCount - 1, through: 1, by: -1) {
                let from = backupURL(forSlot: id, index: i)
                if fm.fileExists(atPath: from.path) { try fm.moveItem(at: from, to: backupURL(forSlot: id, index: i + 1)) }
            }
            try fm.copyItem(at: target, to: backupURL(forSlot: id, index: 1))
        }
        try data.write(to: target, options: .atomic)
        return target
    }

    /// Writes the autosave.
    @discardableResult
    public func autosave(_ state: GameState) throws -> URL { try save(state, slot: Self.autosaveID) }

    /// Loads a slot. An unreadable file is moved to `Corrupt/` and the error is rethrown.
    public func load(slot id: String) throws -> SaveEnvelope {
        let source = url(forSlot: id)
        let data = try Data(contentsOf: source)
        do {
            return try SaveCodec.decode(data)
        } catch let error as SaveError {
            if case .unsupportedFutureVersion = error { throw error }  // a newer app can still read it: leave it alone
            try quarantine(source)
            throw error
        }
    }

    /// Moves an unreadable file into `Corrupt/` under a unique name. Never deletes it.
    public func quarantine(_ file: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: corruptDirectory, withIntermediateDirectories: true)
        var dest = corruptDirectory.appendingPathComponent(file.lastPathComponent)
        var n = 1
        while fm.fileExists(atPath: dest.path) {
            dest = corruptDirectory.appendingPathComponent("\(n)-\(file.lastPathComponent)")
            n += 1
        }
        try fm.moveItem(at: file, to: dest)
    }

    /// Lists readable saves, newest first. Unreadable files are quarantined and skipped.
    public func list() throws -> [SlotInfo] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: savesDirectory.path) else { return [] }
        let files = try fm.contentsOfDirectory(at: savesDirectory, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.pathExtension == Self.fileExtension }
        var infos: [SlotInfo] = []
        for file in files {
            let base = file.deletingPathExtension().lastPathComponent
            let id = base == Self.autosaveID ? Self.autosaveID : String(base.dropFirst("slot-".count))
            guard let data = try? Data(contentsOf: file) else { continue }
            let envelope: SaveEnvelope
            do {
                envelope = try SaveCodec.decode(data)
            } catch SaveError.unsupportedFutureVersion {
                continue  // written by a newer app: keep it where it is
            } catch {
                try quarantine(file)
                continue
            }
            let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            infos.append(SlotInfo(id: id, url: file, summary: envelope.summary, rulesetID: envelope.rulesetID, modified: date,
                                  isAutosave: id == Self.autosaveID))
        }
        return infos.sorted { $0.modified != $1.modified ? $0.modified > $1.modified : $0.id < $1.id }
    }

    /// Deletes a slot and its backups.
    public func delete(slot id: String) throws {
        let fm = FileManager.default
        for url in [url(forSlot: id)] + (1...Self.backupCount).map({ backupURL(forSlot: id, index: $0) })
        where fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    /// Imports save data (fileImporter, Finder open) into a new slot after validating it. Returns the new slot id.
    public func importSave(_ data: Data) throws -> String {
        let envelope = try SaveCodec.decode(data)
        let id = Self.newSlotID()
        try save(envelope.state, slot: id)
        return id
    }

    /// The bytes for fileExporter.
    public func exportSave(slot id: String) throws -> Data {
        try SaveCodec.encode(load(slot: id))
    }
}
