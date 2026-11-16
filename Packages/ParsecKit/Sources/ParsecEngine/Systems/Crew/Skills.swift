// SPDX-License-Identifier: GPL-2.0-or-later
// Effective ship skills (docs/specs/CRW.md).

public enum Skills {
    /// C# `Functions.AdjustSkillForDifficulty`: Beginner/Easy +1, Hard/Impossible −1.
    public static func adjustForDifficulty(_ skill: Int, _ difficulty: Difficulty) -> Int {
        switch difficulty {
        case .beginner, .easy: skill + 1
        case .hard, .impossible: skill - 1
        case .normal: skill
        }
    }

    /// C# `Ship.Skills` (Ship.cs:1228): best crew value per skill (floor 1), difficulty-adjusted (floor 1),
    /// plus +3 per gadget boosting that skill.
    public static func shipSkills(_ ship: Ship, crew: [CrewMember], difficulty: Difficulty, ruleset: Ruleset) -> [Int] {
        var skills = [Int](repeating: 1, count: 4)
        for s in 0..<4 {
            var best = 1
            for id in ship.crew.compactMap({ $0 }) where crew.indices.contains(id) {
                best = max(best, crew[id].skills[s])
            }
            skills[s] = max(1, adjustForDifficulty(best, difficulty))
        }
        for g in ship.gadgets {
            if let bonus = ruleset.tables.gadget(g).skillBonus {
                skills[bonus.rawValue] += 3
            }
        }
        return skills
    }
}
