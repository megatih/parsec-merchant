// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine

/// Game-over card, High Scores window and developer tester identifiers (UI-ENC §17). The M7 strings are unchanged.
nonisolated extension AXID {
    enum GameOver {
        static let card = "gameOver.card"
        static let vignette = "gameOver.vignette"
        static let score = "gameOver.score"
        static let highScore = "gameOver.highScore"
        static let career = "gameOver.career"
        static let newGame = "gameOver.newGame"
        static let mainMenu = "gameOver.mainMenu"
        static let highScores = "gameOver.highScores"
        static let share = "gameOver.share"
        static let all = [card, vignette, score, highScore, career, newGame, mainMenu, highScores, share]
    }

    enum Scores {
        static let window = "scores.window"
        static func ruleset(_ r: RulesetID) -> String { "scores.ruleset.\(r.rawValue)" }
        static func row(_ rank: Int) -> String { "scores.row.\(rank)" }
        static func rowIronman(_ rank: Int) -> String { "scores.row.\(rank).ironman" }
        static let all: [String] = [window] + RulesetID.allCases.map(ruleset)
            + (1...HighScoreTable.capacity).flatMap { [row($0), rowIronman($0)] }
    }

    enum DevTester {
        static let sheet = "devTester.sheet"
        static let close = "devTester.close"
        static func alr(_ number: Int) -> String { "devTester.alr.\(number)" }
        static func narrative(_ t: SpecialEventType) -> String { "devTester.narrative.\(t)" }
        static let all: [String] = [sheet, close] + (1...188).map(alr) + SpecialEventType.allCases.map(narrative)
    }

    static var gameOverArea: [String] { GameOver.all + Scores.all + DevTester.all }
}
