// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine

/// The galaxy code as the wizard, Bridge and Settings use it (UI-SHELL-028, -103, -104), backed by
/// `ParsecEngine.GalaxyCode` (UI-SHELL-116/117).
enum GalaxyCodeAdapter {
    typealias Value = GalaxyCode

    static func string(ruleset: RulesetID, difficulty: Difficulty, seed: UInt64) -> String {
        GalaxyCode(ruleset: ruleset, difficulty: difficulty, seed: seed).string
    }

    static func parse(_ text: String) -> GalaxyCode? {
        GalaxyCode(string: text)
    }
}
