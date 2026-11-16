// SPDX-License-Identifier: GPL-2.0-or-later
// High-score storage (SAV-049/050, SCORE-036…038, PRD §6.4): one versioned JSON file of per-ruleset tables.
// The ranking and insertion logic is in the engine (HighScoreTable).
import Foundation
import ParsecEngine

public struct HighScoreStore: Sendable {
    public static let formatName = "parsec-merchant-highscores"
    public static let currentSchemaVersion = 1

    public let root: URL

    public init(root: URL) { self.root = root }

    public var fileURL: URL { root.appendingPathComponent("HighScores.json") }
    public var corruptDirectory: URL { root.appendingPathComponent("Corrupt", isDirectory: true) }

    /// The decoded file: known tables, tables under unknown ruleset keys (kept verbatim) and recorded game ids.
    struct Contents {
        var tables: [RulesetID: HighScoreTable] = [:]
        var unknownTables: [String: Any] = [:]
        var recordedGames: [String] = []
    }

    /// Reads the file. Missing → empty; unreadable → quarantined, empty (SAV-050); future version → throws.
    func read() throws -> Contents {
        guard FileOps.exists(fileURL) else { return Contents() }
        let data = try Data(contentsOf: fileURL)
        do {
            return try Self.parse(data)
        } catch SaveError.unsupportedFutureVersion(let v) {
            throw SaveError.unsupportedFutureVersion(v)
        } catch {
            try FileOps.quarantine(fileURL, into: corruptDirectory)
            return Contents()
        }
    }

    static func parse(_ data: Data) throws -> Contents {
        guard let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              raw["format"] as? String == formatName else { throw SaveError.notASave }
        guard let version = raw["schemaVersion"] as? Int, version >= 1 else { throw SaveError.corrupt("schemaVersion") }
        if version > currentSchemaVersion { throw SaveError.unsupportedFutureVersion(version) }
        guard let tables = raw["tables"] as? [String: Any] else { throw SaveError.corrupt("tables") }
        var out = Contents()
        for (key, value) in tables {
            guard let id = RulesetID(rawValue: key) else {
                out.unknownTables[key] = value
                continue
            }
            guard value is [String: Any] else { throw SaveError.corrupt("table \(key)") }
            let bytes = try JSONSerialization.data(withJSONObject: value)
            out.tables[id] = try JSONDecoder().decode(HighScoreTable.self, from: bytes)
        }
        out.recordedGames = raw["recordedGames"] as? [String] ?? []
        return out
    }

    func write(_ contents: Contents) throws {
        var tables = contents.unknownTables
        let enc = JSONEncoder()
        for (id, table) in contents.tables {
            tables[id.rawValue] = try JSONSerialization.jsonObject(with: enc.encode(table))
        }
        let object: [String: Any] = ["format": Self.formatName, "schemaVersion": Self.currentSchemaVersion,
                                     "tables": tables, "recordedGames": contents.recordedGames]
        let data = try JSONSerialization.data(withJSONObject: object,
                                              options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
        try FileOps.atomicWrite(data, to: fileURL)
    }

    /// All known tables, keyed by ruleset. A missing or quarantined file means empty tables (SCORE-038); a file from a
    /// newer app reads as empty and can't be overwritten.
    public func load() throws -> [RulesetID: HighScoreTable] {
        do {
            return try read().tables
        } catch SaveError.unsupportedFutureVersion {
            return [:]
        }
    }

    public func table(for id: RulesetID) throws -> HighScoreTable { try load()[id] ?? HighScoreTable() }

    /// Replaces the known tables; tables under unknown ruleset keys and the recorded ids are kept (SAV-050).
    public func save(_ tables: [RulesetID: HighScoreTable]) throws {
        var contents = try read()
        contents.tables = tables
        try write(contents)
    }

    /// SCORE-034…037: offers an ended game's entry to its ruleset's table, once per `gameID`. Returns nil, changing
    /// nothing, when that game was already recorded.
    @discardableResult
    public func record(_ state: GameState, end: GameEndType, gameID: String) throws -> HighScoreOutcome? {
        var contents = try read()
        guard !contents.recordedGames.contains(gameID) else { return nil }
        let current = contents.tables[state.rulesetID] ?? HighScoreTable()
        let (updated, outcome) = current.inserting(state.highScoreEntry(for: end), eligible: state.highScoreExclusion)
        contents.tables[state.rulesetID] = updated
        contents.recordedGames.append(gameID)
        try write(contents)
        return outcome
    }

    /// SCORE-038: clears one ruleset's table.
    public func clear(_ id: RulesetID) throws {
        var contents = try read()
        contents.tables[id] = HighScoreTable()
        try write(contents)
    }
}
