// SPDX-License-Identifier: GPL-2.0-or-later
// PRD §10 `pmsim scenario`: under each ruleset, full games played only through `GameEngine.perform` reach the moon,
// death and retirement endings with the default seed, keeping the fuzzer's invariants on every step.
import Testing
import ParsecEngine
@testable import pmsim

@Suite("pmsim scenario endings")
struct EndingScenarioTests {
    static func play(_ ruleset: RulesetID, _ ending: ScenarioEnding) -> ScenarioOutcome {
        Scenario.play(ruleset, ending, seed: Scenario.defaultSeed)
    }

    @Test("SCORE-007 a traded game buys the moon and claims it at Utopia", arguments: RulesetID.allCases)
    func moon(_ ruleset: RulesetID) {
        let outcome = Self.play(ruleset, .moon)
        #expect(outcome.end == .boughtMoon, "\(outcome.line)")
        #expect(outcome.violations.isEmpty, "\(outcome.violations.prefix(3))")
        #expect(outcome.passed)
    }

    @Test("SCORE-003 SCORE-004 a ship without an escape pod that attacks every ship is destroyed", arguments: RulesetID.allCases)
    func death(_ ruleset: RulesetID) {
        let outcome = Self.play(ruleset, .death)
        #expect(outcome.end == .killed, "\(outcome.line)")
        #expect(outcome.violations.isEmpty, "\(outcome.violations.prefix(3))")
        #expect(outcome.passed)
    }

    @Test("SCORE-006 SCORE-017 a docked commander retires after trading for a while", arguments: RulesetID.allCases)
    func retirement(_ ruleset: RulesetID) {
        let outcome = Self.play(ruleset, .retirement)
        #expect(outcome.end == .retired, "\(outcome.line)")
        #expect(outcome.day == Scenario.retirementDay, "\(outcome.line)")
        #expect(outcome.passed)
    }

    @Test("SCORE-012 scenario games are deterministic for a seed")
    func deterministic() {
        let a = Self.play(.modern, .retirement), b = Self.play(.modern, .retirement)
        #expect(a.line == b.line)
        #expect(a.score == b.score && a.commands == b.commands)
    }
}
