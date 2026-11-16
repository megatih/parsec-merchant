// SPDX-License-Identifier: GPL-2.0-or-later
// Effective ship skills (docs/specs/CRW.md).

public enum Skills {
    /// C# `Functions.AdjustSkillForDifficulty`: Beginner/Easy +1, Hard/Impossible −1. Palm `AdaptDifficulty` leaves Hard
    /// unchanged (`hardAdjustment` 0, RUL-050).
    public static func adjustForDifficulty(_ skill: Int, _ difficulty: Difficulty, hardAdjustment: Int = -1) -> Int {
        switch difficulty {
        case .beginner, .easy: skill + 1
        case .hard: skill + hardAdjustment
        case .impossible: skill - 1
        case .normal: skill
        }
    }

    /// Effective skills (Pilot, Fighter, Trader, Engineer) of `ship`.
    ///
    /// C# `Ship.Skills` (Ship.cs:1228): best crew value per skill (floor 1), difficulty-adjusted (floor 1), plus a bonus
    /// per gadget boosting that skill. Palm (`Src/Skill.c`, RUL-049): best value of the crew slots up to the first
    /// vacancy, plus each gadget type's bonus once, plus the haggling bonus on Trader, then `AdaptDifficulty`. Passengers
    /// (Jarek, Wild) contribute nothing when `passengersAsCrew` is off (RUL-057). `haggling` is only used by the Palm
    /// computation; the C# path adds it in `GameState.skill(_:)` after the adjustment (RUL-051).
    public static func shipSkills(_ ship: Ship, crew: [CrewMember], difficulty: Difficulty, ruleset: Ruleset,
                                  haggling: Bool = false) -> [Int] {
        let rules = ruleset.flags.economy
        let passengers: Set<Int> = rules.passengersAsCrew ? [] : [CrewID.jarek, CrewID.wild]
        func bonus(_ g: GadgetType) -> Int { g == .cloakingDevice ? rules.cloakPilotBonus : 3 }
        switch rules.skillComputation {
        case .adjustThenGadgets:
            var skills = [Int](repeating: 1, count: 4)
            for s in 0..<4 {
                var best = 1
                for id in ship.crew.compactMap({ $0 }) where crew.indices.contains(id) && !passengers.contains(id) {
                    best = max(best, crew[id].skills[s])
                }
                skills[s] = max(1, adjustForDifficulty(best, difficulty, hardAdjustment: rules.hardSkillAdjustment))
            }
            for g in ship.gadgets {
                if let skill = ruleset.tables.gadget(g).skillBonus { skills[skill.rawValue] += bonus(g) }
            }
            return skills
        case .gadgetsThenAdjust:
            var best = [Int](repeating: 0, count: 4)
            for slot in ship.crew {
                guard let id = slot else { break }
                guard crew.indices.contains(id), !passengers.contains(id) else { continue }
                for s in 0..<4 { best[s] = max(best[s], crew[id].skills[s]) }
            }
            for g in GadgetType.allCases where ship.has(g) {
                if let skill = ruleset.tables.gadget(g).skillBonus { best[skill.rawValue] += bonus(g) }
            }
            if haggling { best[SkillType.trader.rawValue] += 1 }
            return best.map { level in
                difficulty == .impossible ? max(1, level - 1)
                    : adjustForDifficulty(level, difficulty, hardAdjustment: rules.hardSkillAdjustment)
            }
        }
    }
}
