// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import Testing
@testable import ParsecMerchant

@MainActor
@Suite("New Game wizard")
struct NewGameDraftTests {
    private func draft(seed: UInt64 = 1) -> NewGameDraft { NewGameDraft(commanderName: "Jameson", seed: seed) }

    @Test("UI-SHELL-022 six steps in order: Commander, Difficulty, Ruleset, Skills, Galaxy & extras, Summary")
    func steps() {
        #expect(NewGameDraft.Step.allCases == [.commander, .difficulty, .ruleset, .skills, .galaxy, .summary])
        #expect(NewGameDraft.Step.allCases.map(\.rawValue) == Array(0...5))
    }

    @Test("UI-SHELL-023 the name: required, at most 20 characters in Palm, re-validated when the ruleset changes")
    func name() {
        var d = draft()
        #expect(d.canAdvance(from: .commander).isEnabled)
        d.commanderName = "   "
        #expect(d.canAdvance(from: .commander) == .disabled("Enter a name."))
        d.commanderName = String(repeating: "x", count: 21)
        #expect(d.canAdvance(from: .commander).isEnabled)
        d.setRuleset(.palm122)
        #expect(d.canAdvance(from: .commander) == .disabled("At most 20 characters."))
        d.balance()
        #expect(d.canStart.isEnabled == false)
        #expect(d.firstFailingStep == .commander)
    }

    @Test("UI-SHELL-024 difficulty defaults to Normal; five levels with descriptions")
    func difficulty() {
        let d = draft()
        #expect(d.difficulty == .normal)
        #expect(Difficulty.allCases.allSatisfy { !String(localized: WizardText.difficultyDescription($0)).isEmpty })
    }

    @Test("UI-SHELL-025 ruleset defaults to Modern (Recommended); each has 3–5 bullets")
    func ruleset() {
        let d = draft()
        #expect(d.ruleset == .modern)
        #expect(String(localized: WizardText.rulesetTagline(.modern)) == "Recommended")
        #expect(RulesetID.allCases.allSatisfy { (3...5).contains(WizardText.rulesetBullets($0).count) })
    }

    @Test("UI-SHELL-026 skills start at 1, are bounded by the preview maxima and 1, Balanced is 5/5/5/5")
    func skills() {
        var d = draft()
        #expect(d.skills == [1, 1, 1, 1] && d.preview.pointsRemaining == 16)
        #expect(d.canAdvance(from: .skills) == .disabled("Distribute all points."))
        #expect(!d.canDecrement(.pilot))
        for _ in 0..<20 { d.increment(.pilot) }
        #expect(d.skills[0] == 10 && !d.canIncrement(.pilot))
        for _ in 0..<20 { d.increment(.fighter) }
        #expect(d.skills[1] == 8 && d.preview.pointsRemaining == 0 && !d.canIncrement(.trader))
        #expect(d.canAdvance(from: .skills).isEnabled)
        d.decrement(.pilot)
        #expect(d.preview.pointsRemaining == 1)
        d.balance()
        #expect(d.skills == [5, 5, 5, 5] && d.preview.pointsRemaining == 0)
    }

    @Test("UI-SHELL-027 galaxy step: seed, Ironman off, ship name trimmed to at most 30, empty is nil")
    func extras() {
        var d = draft(seed: 77)
        #expect(d.seed == 77 && !d.ironman && d.trimmedShipName == nil)
        d.shipName = "  Heart of Gold  "
        #expect(d.trimmedShipName == "Heart of Gold")
        d.shipName = String(repeating: "a", count: 40)
        #expect(d.trimmedShipName?.count == NewGameDraft.maxShipNameLength)
        d.shipName = "   "
        #expect(d.config.shipName == nil)
    }

    @Test("UI-SHELL-028 code and seed are one value: editing either updates the other; invalid codes block Next")
    func galaxyCode() {
        var d = draft(seed: 1)
        #expect(d.galaxyCodeText == "M2-1-V")
        d.setSeed(3_735_928_559)
        d.setRuleset(.windows201)
        #expect(d.galaxyCodeText == "W2-3FAV-FQF-1")
        d.setGalaxyCodeText("p4-fzzz-zzzz-zzzz-z-s")
        #expect(d.ruleset == .palm122 && d.difficulty == .impossible && d.seed == .max)
        d.setGalaxyCodeText("M2-1-W")
        #expect(d.galaxyCodeInvalid && d.ruleset == .palm122 && d.seed == .max)
        #expect(d.canAdvance(from: .galaxy) == .disabled("Not a valid galaxy code."))
        d.setDifficulty(.beginner)
        d.setRuleset(.modern)
        d.setSeed(0)
        #expect(d.galaxyCodeText == "M0-0-M" && !d.galaxyCodeInvalid)
        #expect(GalaxyCodeAdapter.parse("M 2 1 V") == GalaxyCodeAdapter.Value(ruleset: .modern, difficulty: .normal, seed: 1))
        var g = SystemRandomNumberGenerator()
        for r in RulesetID.allCases {
            for _ in 0..<500 {
                let v = GalaxyCodeAdapter.Value(ruleset: r, difficulty: Difficulty.allCases.randomElement(using: &g) ?? .normal,
                                                seed: UInt64.random(in: .min ... .max, using: &g))
                #expect(GalaxyCodeAdapter.parse(GalaxyCodeAdapter.string(ruleset: v.ruleset, difficulty: v.difficulty, seed: v.seed)) == v)
            }
        }
    }

    @Test("UI-SHELL-029 Start is enabled iff the config validates")
    func summary() {
        var d = draft()
        #expect(!d.canStart.isEnabled && d.firstFailingStep == .skills)
        d.balance()
        #expect(d.canStart.isEnabled && d.firstFailingStep == nil)
        #expect(CommanderRules.validate(d.config) == nil)
    }

    @Test("UI-SHELL-031 the draft's config is pure and carries every wizard field")
    func config() {
        var d = draft(seed: 99)
        d.balance()
        d.setDifficulty(.hard)
        d.ironman = true
        d.shipName = "Bebop"
        let c = d.config
        #expect(c == NewGameConfig(commanderName: "Jameson", difficulty: .hard, skills: [5, 5, 5, 5], ruleset: .modern,
                                   seed: 99, ironman: true, shipName: "Bebop", options: nil))
    }

    @Test("UI-SHELL-032 -PMSeed fills the seed; the code for the same ruleset, difficulty and seed is stable")
    func pmSeed() throws {
        let s = try TestSessions.make(seed: 123_456)
        let d = NewGameDraft(commanderName: "A", seed: s.newGameSeed())
        #expect(d.seed == 123_456)
        #expect(d.galaxyCode == NewGameDraft(commanderName: "B", seed: 123_456).galaxyCode)
    }
}
