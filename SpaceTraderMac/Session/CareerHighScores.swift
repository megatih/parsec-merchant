// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// UI-ENC-088: one rank of the High Scores window.
struct HighScoreRow: Equatable, Sendable, Identifiable {
    struct Filled: Equatable, Sendable {
        var name: String
        var scoreText: String
        /// SCORE-039: "<ending> in <N day(s)>, worth <N credit(s)> on <difficulty> level."
        var line: String
        var ironman: Bool
        var reloaded: Bool
    }

    var rank: Int
    /// Nil for an empty rank ("Empty").
    var entry: Filled?

    var id: Int { rank }
}

/// UI-ENC-088: the rows of a ruleset's table (pure).
enum HighScoreRowModel {
    /// Always `HighScoreTable.capacity` rows, one per rank; ranks without an entry are empty.
    static func rows(table: HighScoreTable, ruleset: Ruleset, locale: Locale = .current) -> [HighScoreRow] {
        (0..<HighScoreTable.capacity).map { index in
            let filled = table.entries.indices.contains(index) ? table.entries[index] : nil
            return HighScoreRow(rank: index + 1, entry: filled.map { e in
                HighScoreRow.Filled(name: e.name, scoreText: ScoreText.score(e.score, ruleset: ruleset, locale: locale),
                                    line: line(for: e, locale: locale), ironman: e.ironman, reloaded: e.reloaded)
            })
        }
    }

    /// SCORE-039 (Form_ViewHighScores.cs, `Strings.HighScoreStatus`): the difficulty is lower-cased as in C#.
    static func line(for e: HighScoreEntry, locale: Locale = .current) -> String {
        let ending = ending(e.endType)
        let days = String(AttributedString(localized: "^[\(e.days) day](inflect: true)", locale: locale).characters)
        let worth = String(AttributedString(localized: "^[\(e.worth) credit](inflect: true)", locale: locale).characters)
        let level = String(localized: Names.difficulty(e.difficulty)).lowercased(with: locale)
        return String(localized: "\(ending) in \(days), worth \(worth) on \(level) level.")
    }

    /// `Strings.GameCompletionTypes`, plus the Modern moon-girl ending.
    static func ending(_ end: GameEndType) -> String {
        switch end {
        case .killed: String(localized: "Was killed")
        case .retired: String(localized: "Retired")
        case .boughtMoon: String(localized: "Claimed moon")
        case .boughtMoonGirl: String(localized: "Claimed moon with Ziyal")
        }
    }

    /// UI-ENC-089: the rank the current game just entered in `ruleset`'s table, if any.
    static func highlightedRank(recorded: RecordedScore?, gameRuleset: RulesetID?, shown: RulesetID) -> Int? {
        guard gameRuleset == shown, case let .outcome(.entered(rank))? = recorded else { return nil }
        return rank
    }
}

/// UI-ENC-087: which ruleset the High Scores window shows.
enum HighScoresSelection {
    /// `UserDefaults` key of the last ruleset viewed.
    static let defaultsKey = "scores.ruleset"

    /// The current or just-ended game's ruleset, else the last one viewed, else Modern.
    static func initial(gameRuleset: RulesetID?, stored: String?) -> RulesetID {
        gameRuleset ?? stored.flatMap(RulesetID.init(rawValue:)) ?? .modern
    }
}
