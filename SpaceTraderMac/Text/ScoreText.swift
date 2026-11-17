// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// UI-ENC-081: the single score formatter (game-over card, retire sheet, career card, high-score rows).
enum ScoreText {
    /// SCORE-024/025: tenths of a percent as "X.Y%". Both parts keep the C# sign (`-5969` → "-596.-9%", `-5` →
    /// "0.-5%"). The integer part is grouped like C# `FormatNumber`, except where the ruleset uses the Palm score
    /// formula, which prints it ungrouped.
    static func tenths(_ t: Int, ruleset: Ruleset, locale: Locale = .current) -> String {
        let whole = t / 10
        let integer = ruleset.flags.travel.scoreFormula == .palm
            ? String(whole)
            : whole.formatted(.number.grouping(.automatic).locale(locale))
        return "\(integer).\(t % 10)%"
    }

    /// The display tenths of a ruleset-native score (`HighScoreEntry.score`, `Confirmation` amounts): Palm scores are
    /// divided by 5 with C truncation (SCORE-025), C# scores are already tenths (SCORE-024).
    static func displayTenths(score: Int, ruleset: Ruleset) -> Int {
        ruleset.flags.travel.scoreFormula == .palm ? score / 5 : score
    }

    /// A ruleset-native score formatted for display.
    static func score(_ score: Int, ruleset: Ruleset, locale: Locale = .current) -> String {
        tenths(displayTenths(score: score, ruleset: ruleset), ruleset: ruleset, locale: locale)
    }
}
