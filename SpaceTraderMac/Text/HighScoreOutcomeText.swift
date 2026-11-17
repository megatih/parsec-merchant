// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// UI-ENC-084: the game-over card's high-score line (ALR-098…100, SCORE-035…037).
enum HighScoreOutcomeText {
    /// The outcome sentence, followed by "Ironman" and "↺" when the entry carries them. `table` is the game's ruleset
    /// table, used to show the rank of an already recorded game (a reopened ended save) when it is still listed.
    /// Nil only before the session has recorded the game.
    static func text(for recorded: RecordedScore?, entry: HighScoreEntry, table: HighScoreTable? = nil) -> String? {
        guard let recorded else { return nil }
        let sentence: String
        switch recorded {
        case let .outcome(outcome):
            sentence = text(for: outcome)
        case .alreadyRecorded:
            if let index = table?.entries.firstIndex(of: entry) {
                sentence = String(localized: "This game's score was already recorded, at rank \(index + 1).")
            } else {
                sentence = String(localized: "This game's score was already recorded.")
            }
        case .failed:
            sentence = String(localized: "The high-score table couldn't be updated.")
        }
        return ([sentence] + markers(ironman: entry.ironman, reloaded: entry.reloaded)).joined(separator: " ")
    }

    static func text(for outcome: HighScoreOutcome) -> String {
        switch outcome {
        case let .entered(rank): String(localized: "You entered the high-score table at rank \(rank).")
        case .missed: String(localized: "Your score didn't make the high-score table.")
        case .excludedForCheats: String(localized: "Cheats were used, so this game is not on the high-score table.")
        case .excludedForReload: String(localized: "This game was reloaded, so it is not on the high-score table.")
        }
    }

    /// The Ironman badge and the ↺ reload marker as text (SCORE-029).
    static func markers(ironman: Bool, reloaded: Bool) -> [String] {
        var out: [String] = []
        if ironman { out.append(String(localized: "Ironman")) }
        if reloaded { out.append(String(localized: "↺ reloaded")) }
        return out
    }
}
