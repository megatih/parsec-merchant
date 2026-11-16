// SPDX-License-Identifier: GPL-2.0-or-later
// Commander creation rules, random skill changes and crew previews (docs/specs/CRW.md).

/// CRW-068: the crew screen.
public struct CrewPreview: Sendable, Equatable {
    /// Effective skills (Pilot, Fighter, Trader, Engineer) including the haggling bonus on Trader.
    public var effectiveSkills: [Int]
    /// Best raw crew value per skill (floor 1), before adjustments.
    public var crewMaximum: [Int]
    public var difficultyAdjustment: Int
    /// Gadget bonus per skill.
    public var gadgetBonus: [Int]
    public var hagglingBonus: Int
    public var freeQuarters: Int
    public var dailyMercenaryCost: Int
    /// Mercenaries for hire here with their daily rate.
    public var forHire: [(id: Int, rate: Int)]

    public static func == (a: CrewPreview, b: CrewPreview) -> Bool {
        a.effectiveSkills == b.effectiveSkills && a.crewMaximum == b.crewMaximum && a.freeQuarters == b.freeQuarters
            && a.dailyMercenaryCost == b.dailyMercenaryCost && a.forHire.map(\.id) == b.forHire.map(\.id)
    }
}

/// CRW-069: the new-commander form.
public struct NewCommanderPreview: Sendable, Equatable {
    public var pointsRemaining: Int
    /// Allowed maximum per skill: min(10, skill + remaining).
    public var maxima: [Int]
    public var error: CommandError?
}

public enum CommanderRules {
    public static let totalSkillPoints = 20

    /// CRW-004/007: validates a new-game configuration.
    public static func validate(_ config: NewGameConfig) -> CommandError? {
        if config.commanderName.allSatisfy({ $0 == " " }) { return .commanderNameRequired }
        // CRW-005: Palm's name field holds at most NAMELEN (20) characters.
        if let maxLength = Ruleset.named(config.ruleset).flags.economy.commanderNameMaxLength,
           config.commanderName.count > maxLength {
            return .commanderNameTooLong
        }
        if config.skills.count != 4 || config.skills.contains(where: { !(1...10).contains($0) })
            || config.skills.reduce(0, +) != totalSkillPoints {
            return .invalidSkillAllocation
        }
        return nil
    }

    /// CRW-069.
    public static func preview(name: String, skills: [Int]) -> NewCommanderPreview {
        let remaining = totalSkillPoints - skills.reduce(0, +)
        let cfg = NewGameConfig(commanderName: name, skills: skills, seed: 0)
        return NewCommanderPreview(pointsRemaining: remaining, maxima: skills.map { min(10, $0 + max(0, remaining)) },
                                   error: validate(cfg))
    }
}

public extension GameEngine {
    /// CRW-004/007: starts a validated new game.
    static func newGame(_ config: NewGameConfig) -> Result<GameEngine, CommandError> {
        if let e = CommanderRules.validate(config) { return .failure(e) }
        return .success(GameEngine(config: config))
    }
}

public extension GameState {
    /// CRW-052: C# `ChangeRandomSkill(amount)` on the commander: picks among skills where `skill + amount` stays in
    /// 1…9 (Windows; the `< MaxSkill` quirk) and recalculates buy prices if the effective Trader changed (CRW-062).
    /// Palm (CRW-054/055) re-draws `GetRandom(4)` until the drawn skill is < 10 (increase) or > n (decrease by n), and
    /// returns at once when all four skills are ≥ 10; where Palm would loop forever (no eligible skill) the engine makes
    /// no change. Returns false when nothing could change (no random draw was made).
    @discardableResult
    mutating func changeRandomSkill(_ amount: Int) -> Bool {
        let skills = mercenaries[CrewID.commander].skills
        let pick: Int
        switch ruleset.flags.economy.randomSkillChange {
        case .eligibleList:
            let cap = ruleset.flags.randomSkillIncreaseReachesTen ? 11 : 10
            let candidates = (0..<4).filter {
                let v = skills[$0] + amount
                return v > 0 && v < cap
            }
            guard !candidates.isEmpty else { return false }
            pick = candidates[rng.next(below: candidates.count)]
        case .redraw:
            if skills.allSatisfy({ $0 >= 10 }) { return false }
            let eligible: (Int) -> Bool = { amount > 0 ? skills[$0] < 10 : skills[$0] > -amount }
            guard (0..<4).contains(where: eligible) else { return false }
            var d = rng.next(below: 4)
            while !eligible(d) { d = rng.next(below: 4) }
            pick = d
        }
        let before = skill(.trader)
        mercenaries[CrewID.commander].skills[pick] += amount
        if skill(.trader) != before {
            buyPrices = Pricing.buyPrices(sell: sellPrices, in: currentSystem, criminal: commander.policeRecordScore < -5,
                                          traderSkill: skill(.trader), ruleset: ruleset)
        }
        return true
    }

    /// CRW-068.
    var crewPreview: CrewPreview {
        let r = ruleset
        let crewMax = (0..<4).map { s in
            commander.ship.crew.compactMap { $0 }.reduce(1) { max($0, mercenaries[$1].skills[s]) }
        }
        let gadget = (0..<4).map { s in
            commander.ship.gadgets.filter { r.tables.gadget($0).skillBonus?.rawValue == s }
                .reduce(0) { $0 + ($1 == .cloakingDevice ? r.flags.economy.cloakPilotBonus : 3) }
        }
        let adj = Skills.adjustForDifficulty(0, difficulty, hardAdjustment: r.flags.economy.hardSkillAdjustment)
        return CrewPreview(effectiveSkills: (0..<4).map { skill(SkillType(rawValue: $0) ?? .pilot) }, crewMaximum: crewMax,
                           difficultyAdjustment: adj, gadgetBonus: gadget, hagglingBonus: hagglingComputer ? 1 : 0,
                           freeQuarters: commander.ship.freeQuarters, dailyMercenaryCost: mercenaryCosts,
                           forHire: mercenariesForHire.map { ($0, dailyRate(of: $0)) })
    }
}
