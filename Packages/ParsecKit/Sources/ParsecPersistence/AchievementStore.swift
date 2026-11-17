// SPDX-License-Identifier: GPL-2.0-or-later
// App-wide achievement storage (docs/specs/ACH.md §3, ACH-011…015; PRD §6.4 "Achievements are stored as JSON").
// Ids are raw strings, so records of achievements this app does not know are kept and rewritten unchanged.
import Foundation

/// ACH-011: one unlocked achievement.
public struct AchievementRecord: Codable, Sendable, Equatable {
    /// The `AchievementID` raw value (kept as a string so newer apps' ids survive).
    public var id: String
    /// ISO 8601 UTC, from the store's injected clock.
    public var unlockedAt: String
    public var gameID: String
    public var rulesetID: String
    public var day: Int

    public init(id: String, unlockedAt: String, gameID: String, rulesetID: String, day: Int) {
        self.id = id
        self.unlockedAt = unlockedAt
        self.gameID = gameID
        self.rulesetID = rulesetID
        self.day = day
    }
}

/// ACH-011…014: `root/Achievements.json`, sorted keys, records sorted by id, written atomically.
public struct AchievementStore: Sendable {
    public static let formatName = "parsec-merchant-achievements"
    public static let currentSchemaVersion = 1

    public let root: URL
    public let clock: @Sendable () -> Date
    /// ACH-013: unlocks that could not be written (the file belongs to a newer app); kept for the session.
    public private(set) var sessionOnly: [AchievementRecord] = []
    /// ACH-013: false after an unlock could not be persisted.
    public private(set) var isPersisting = true

    public init(root: URL, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.root = root
        self.clock = clock
    }

    public var fileURL: URL { root.appendingPathComponent("Achievements.json") }
    public var corruptDirectory: URL { root.appendingPathComponent("Corrupt", isDirectory: true) }

    struct File: Codable {
        var format: String
        var schemaVersion: Int
        var unlocked: [AchievementRecord]
    }

    /// Missing → empty; unreadable → quarantined, empty (ACH-013); future version → throws.
    func read() throws -> [AchievementRecord] {
        guard FileOps.exists(fileURL) else { return [] }
        let data = try Data(contentsOf: fileURL)
        do {
            return try Self.parse(data)
        } catch SaveError.unsupportedFutureVersion(let v) {
            throw SaveError.unsupportedFutureVersion(v)
        } catch {
            try FileOps.quarantine(fileURL, into: corruptDirectory)
            return []
        }
    }

    static func parse(_ data: Data) throws -> [AchievementRecord] {
        guard let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              raw["format"] as? String == formatName else { throw SaveError.notASave }
        guard let version = raw["schemaVersion"] as? Int, version >= 1 else { throw SaveError.corrupt("schemaVersion") }
        if version > currentSchemaVersion { throw SaveError.unsupportedFutureVersion(version) }
        do {
            return try JSONDecoder().decode(File.self, from: data).unlocked
        } catch {
            throw SaveError.corrupt("unlocked")
        }
    }

    func write(_ records: [AchievementRecord]) throws {
        let file = File(format: Self.formatName, schemaVersion: Self.currentSchemaVersion,
                        unlocked: records.sorted { $0.id < $1.id })
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        try FileOps.atomicWrite(enc.encode(file), to: fileURL)
    }

    /// ACH-012: every unlocked record (file plus session-only), sorted by id. A newer app's file reads as its records
    /// only when it can be parsed; otherwise as the session's.
    public func records() throws -> [AchievementRecord] {
        let stored: [AchievementRecord]
        do {
            stored = try read()
        } catch SaveError.unsupportedFutureVersion {
            stored = []
        }
        return (stored + sessionOnly.filter { s in !stored.contains { $0.id == s.id } }).sorted { $0.id < $1.id }
    }

    /// ACH-012.
    public func isUnlocked(_ id: String) throws -> Bool { try records().contains { $0.id == id } }

    /// ACH-012 / ACH-013: adds a record for each id not yet unlocked (first unlock wins) and returns the ids added.
    /// When the file belongs to a newer app nothing is written: the records are kept for the session and
    /// `isPersisting` becomes false.
    @discardableResult
    public mutating func unlock(_ ids: [String], gameID: String, rulesetID: String, day: Int) throws -> [String] {
        let stamp = Self.timestamp(clock())
        var stored: [AchievementRecord]
        var writable = true
        do {
            stored = try read()
        } catch SaveError.unsupportedFutureVersion {
            stored = []
            writable = false
        }
        var added: [String] = []
        for id in ids where !stored.contains(where: { $0.id == id }) && !sessionOnly.contains(where: { $0.id == id })
            && !added.contains(id) {
            let record = AchievementRecord(id: id, unlockedAt: stamp, gameID: gameID, rulesetID: rulesetID, day: day)
            if writable { stored.append(record) } else { sessionOnly.append(record) }
            added.append(id)
        }
        if !writable {
            if !added.isEmpty { isPersisting = false }
            return added
        }
        if !added.isEmpty { try write(stored) }
        return added
    }

    /// ACH-014: deletes every record (writes an empty list); the session-only records go too.
    public mutating func reset() throws {
        sessionOnly = []
        do {
            _ = try read()
        } catch SaveError.unsupportedFutureVersion {
            isPersisting = false
            return
        }
        try write([])
    }

    /// ACH-011: ISO 8601 in UTC.
    static func timestamp(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}
