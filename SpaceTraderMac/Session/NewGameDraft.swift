// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// Whether something can be done now, and why not.
struct Availability: Equatable, Sendable {
    var isEnabled: Bool
    var reason: LocalizedStringResource?

    static let enabled = Availability(isEnabled: true, reason: nil)
    static func disabled(_ reason: LocalizedStringResource) -> Availability { Availability(isEnabled: false, reason: reason) }

    static func == (a: Availability, b: Availability) -> Bool {
        a.isEnabled == b.isEnabled && a.reason.map { String(localized: $0) } == b.reason.map { String(localized: $0) }
    }
}

/// The New Game wizard's model (UI-SHELL-031). A value type with pure validation.
struct NewGameDraft: Equatable, Sendable {
    enum Step: Int, CaseIterable, Sendable {
        case commander, difficulty, ruleset, skills, galaxy, summary

        var title: LocalizedStringResource {
            switch self {
            case .commander: "Commander"
            case .difficulty: "Difficulty"
            case .ruleset: "Ruleset"
            case .skills: "Skills"
            case .galaxy: "Galaxy & Extras"
            case .summary: "Summary"
            }
        }
    }

    static let maxShipNameLength = 30

    var commanderName: String
    var difficulty: Difficulty = .normal
    var ruleset: RulesetID = .modern
    /// Pilot, fighter, trader, engineer; each starts at 1.
    var skills: [Int] = [1, 1, 1, 1]
    var seed: UInt64
    var ironman = false
    var shipName = ""
    /// The galaxy code text field; kept in sync with ruleset, difficulty and seed unless the player is editing it.
    var galaxyCodeText: String
    var options: GameOptions?

    init(commanderName: String, seed: UInt64, options: GameOptions? = nil) {
        self.commanderName = commanderName
        self.seed = seed
        self.options = options
        galaxyCodeText = GalaxyCodeAdapter.string(ruleset: .modern, difficulty: .normal, seed: seed)
    }

    // MARK: Galaxy code (UI-SHELL-028)

    /// The canonical code of the current ruleset, difficulty and seed.
    var galaxyCode: String { GalaxyCodeAdapter.string(ruleset: ruleset, difficulty: difficulty, seed: seed) }

    /// True when the code field holds something that does not parse.
    var galaxyCodeInvalid: Bool { GalaxyCodeAdapter.parse(galaxyCodeText) == nil }

    /// Rewrites the code field from the current values (after editing the seed, ruleset or difficulty, or Randomize).
    mutating func syncGalaxyCode() { galaxyCodeText = galaxyCode }

    /// Sets the seed and rewrites the code.
    mutating func setSeed(_ s: UInt64) {
        seed = s
        syncGalaxyCode()
    }

    mutating func setRuleset(_ r: RulesetID) {
        ruleset = r
        syncGalaxyCode()
    }

    mutating func setDifficulty(_ d: Difficulty) {
        difficulty = d
        syncGalaxyCode()
    }

    /// The player edited the code: a valid code sets ruleset, difficulty and seed; an invalid one changes nothing else.
    mutating func setGalaxyCodeText(_ text: String) {
        galaxyCodeText = text
        if let v = GalaxyCodeAdapter.parse(text) {
            ruleset = v.ruleset
            difficulty = v.difficulty
            seed = v.seed
        }
    }

    // MARK: Skills (UI-SHELL-026)

    var preview: NewCommanderPreview { CommanderRules.preview(name: commanderName, skills: skills) }

    func canIncrement(_ s: SkillType) -> Bool { skills[s.rawValue] < preview.maxima[s.rawValue] }
    func canDecrement(_ s: SkillType) -> Bool { skills[s.rawValue] > 1 }

    mutating func increment(_ s: SkillType) { if canIncrement(s) { skills[s.rawValue] += 1 } }
    mutating func decrement(_ s: SkillType) { if canDecrement(s) { skills[s.rawValue] -= 1 } }
    mutating func balance() { skills = [5, 5, 5, 5] }

    // MARK: Config and validation

    /// The ship name trimmed; empty means none (at most 30 characters).
    var trimmedShipName: String? {
        let t = shipName.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : String(t.prefix(Self.maxShipNameLength))
    }

    var config: NewGameConfig {
        NewGameConfig(commanderName: commanderName, difficulty: difficulty, skills: skills, ruleset: ruleset, seed: seed,
                      ironman: ironman, shipName: trimmedShipName, options: options)
    }

    /// The name rules of CRW-004/005 on the chosen ruleset.
    var nameError: CommandError? {
        switch CommanderRules.validate(NewGameConfig(commanderName: commanderName, skills: [5, 5, 5, 5], ruleset: ruleset, seed: 0)) {
        case .commanderNameRequired: .commanderNameRequired
        case .commanderNameTooLong: .commanderNameTooLong
        default: nil
        }
    }

    func canAdvance(from step: Step) -> Availability {
        switch step {
        case .commander:
            if let e = nameError { return .disabled(ReasonText.text(for: e)) }
            return .enabled
        case .difficulty, .ruleset:
            return .enabled
        case .skills:
            return preview.pointsRemaining == 0 ? .enabled : .disabled("Distribute all points.")
        case .galaxy:
            return galaxyCodeInvalid ? .disabled("Not a valid galaxy code.") : .enabled
        case .summary:
            return canStart
        }
    }

    /// Start is enabled iff the whole config validates and the code is valid (UI-SHELL-029).
    var canStart: Availability {
        if galaxyCodeInvalid { return .disabled("Not a valid galaxy code.") }
        if let e = CommanderRules.validate(config) { return .disabled(ReasonText.text(for: e)) }
        return .enabled
    }

    /// The first step whose rules fail, for the summary's "go back to" hint.
    var firstFailingStep: Step? {
        Step.allCases.dropLast().first { !canAdvance(from: $0).isEnabled }
    }
}
