// SPDX-License-Identifier: GPL-2.0-or-later
// High-score storage (SCORE-036/038, PRD §6.4): one JSON file of per-ruleset tables. The ranking logic is in the engine.
import Foundation
import ParsecEngine

public struct HighScoreStore: Sendable {
    public let root: URL

    public init(root: URL) { self.root = root }

    public var fileURL: URL { root.appendingPathComponent("HighScores.json") }

    /// All tables, keyed by ruleset; a missing file means empty tables.
    public func load() throws -> [RulesetID: HighScoreTable] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        let raw = try JSONDecoder().decode([String: HighScoreTable].self, from: Data(contentsOf: fileURL))
        var out: [RulesetID: HighScoreTable] = [:]
        for (key, table) in raw { if let id = RulesetID(rawValue: key) { out[id] = table } }
        return out
    }

    public func table(for id: RulesetID) throws -> HighScoreTable { try load()[id] ?? HighScoreTable() }

    public func save(_ tables: [RulesetID: HighScoreTable]) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var raw: [String: HighScoreTable] = [:]
        for (id, table) in tables { raw[id.rawValue] = table }
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .prettyPrinted]
        try enc.encode(raw).write(to: fileURL, options: .atomic)
    }

    /// SCORE-034…037: offers an ended game's entry to its ruleset's table and stores the result.
    @discardableResult
    public func record(_ state: GameState, end: GameEndType) throws -> HighScoreOutcome {
        var tables = try load()
        let current = tables[state.rulesetID] ?? HighScoreTable()
        let (updated, outcome) = current.inserting(state.highScoreEntry(for: end), eligible: state.highScoreExclusion)
        if case .entered = outcome {
            tables[state.rulesetID] = updated
            try save(tables)
        }
        return outcome
    }

    /// SCORE-038: clears one ruleset's table.
    public func clear(_ id: RulesetID) throws {
        var tables = try load()
        tables[id] = HighScoreTable()
        try save(tables)
    }
}
