// SPDX-License-Identifier: GPL-2.0-or-later
// High-score table (docs/specs/SCORE.md §6). Pure value types; ParsecPersistence only loads and saves it.

/// SCORE-029: one high-score entry.
public struct HighScoreEntry: Codable, Sendable, Equatable {
    public var name: String
    public var endType: GameEndType
    public var score: Int
    public var days: Int
    public var worth: Int
    public var difficulty: Difficulty
    public var rulesetID: RulesetID
    public var ironman: Bool
    public var reloaded: Bool

    public init(name: String, endType: GameEndType, score: Int, days: Int, worth: Int, difficulty: Difficulty,
                rulesetID: RulesetID, ironman: Bool = false, reloaded: Bool = false) {
        self.name = name
        self.endType = endType
        self.score = score
        self.days = days
        self.worth = worth
        self.difficulty = difficulty
        self.rulesetID = rulesetID
        self.ironman = ironman
        self.reloaded = reloaded
    }

    /// SCORE-031: score, then worth, then more days.
    public func ranksAbove(_ other: HighScoreEntry) -> Bool {
        if score != other.score { return score > other.score }
        if worth != other.worth { return worth > other.worth }
        return days > other.days
    }
}

/// SCORE-036: the outcome of offering an entry to the table.
public enum HighScoreOutcome: Codable, Sendable, Equatable {
    case entered(rank: Int)
    case missed
    case excludedForCheats
    case excludedForReload
}

/// SCORE-030/032: one ruleset's table (top 10).
public struct HighScoreTable: Codable, Sendable, Equatable {
    public static let capacity = 10
    public var entries: [HighScoreEntry]

    public init(entries: [HighScoreEntry] = [], capacity: Int = HighScoreTable.capacity) {
        self.entries = Array(entries.prefix(capacity))
        self.capacity = capacity
    }

    /// Classic tables have 3 slots (SCORE-032); Parsec Merchant uses 10.
    public var capacity: Int

    /// Whether `entry` would enter: a free slot, or it ranks strictly above the lowest entry (SCORE-032).
    public func qualifies(_ entry: HighScoreEntry) -> Bool {
        guard entries.count >= capacity, let last = entries.last else { return true }
        return entry.ranksAbove(last)
    }

    /// SCORE-034/035/036: pure insertion. `blocked` is the reason the game may not be stored, if any.
    public func inserting(_ entry: HighScoreEntry, eligible blocked: HighScoreOutcome? = nil) -> (HighScoreTable, HighScoreOutcome) {
        guard qualifies(entry) else { return (self, .missed) }
        if let blocked { return (self, blocked) }
        // SCORE-033: the new entry goes below every entry it does not rank strictly above.
        let index = entries.firstIndex { entry.ranksAbove($0) } ?? entries.count
        var copy = self
        copy.entries.insert(entry, at: index)
        if copy.entries.count > capacity { copy.entries.removeLast() }
        return (copy, .entered(rank: index + 1))
    }
}

public extension GameState {
    /// SCORE-029: the entry for this ended game.
    func highScoreEntry(for end: GameEndType) -> HighScoreEntry {
        HighScoreEntry(name: commander.name, endType: end, score: score(for: end), days: commander.days, worth: worth,
                       difficulty: difficulty, rulesetID: rulesetID, ironman: ironman, reloaded: reloadCount > 0)
    }

    /// SCORE-034/035: why this game may not enter the table (nil when eligible).
    var highScoreExclusion: HighScoreOutcome? {
        if cheatsUsed { return .excludedForCheats }
        if highScoreBlocked { return .excludedForReload }
        return nil
    }
}
