// SPDX-License-Identifier: GPL-2.0-or-later
// The tactical readout (docs/specs/UI-ENC.md §15, UI-ENC-104; PRD §6.6): public information only.

/// UI-ENC-104: the flee odds as a word (`.good` ≥ 2/3, `.fair` ≥ 1/3, else `.poor`).
public enum FleeOdds: String, Codable, Sendable, CaseIterable {
    case good, fair, poor

    /// The word for an exact escape probability `numerator / denominator`.
    public static func word(numerator: Int, denominator: Int) -> FleeOdds {
        guard denominator > 0 else { return .good }
        if 3 * numerator >= 2 * denominator { return .good }
        if 3 * numerator >= denominator { return .fair }
        return .poor
    }
}

/// UI-ENC-104: what the player can see about the opponent before acting.
public struct TacticalReadout: Sendable, Equatable {
    public var opponentType: ShipType
    /// The opponent's installed weapons and shields, in slot order.
    public var weapons: [WeaponType]
    public var shields: [ShieldType]
    /// Nil when Flee is not among the encounter's actions.
    public var fleeOdds: FleeOdds?
}

/// An exact probability (numerator / denominator, denominator > 0).
public struct ExactFraction: Sendable, Equatable {
    public var numerator: Int
    public var denominator: Int
}

public extension GameEngine {
    /// UI-ENC-104: the readout for the current encounter (nil outside `.encounter`). Pure: no RNG draw, and the
    /// opponent's actual crew is never read (its pilot is averaged over the generator's range).
    var tacticalReadout: TacticalReadout? {
        guard let enc = encounter else { return nil }
        let offersFlee = enc.type.actions.contains(.flee)
        let odds = offersFlee ? fleeProbability.map { FleeOdds.word(numerator: $0.numerator, denominator: $0.denominator) } : nil
        return TacticalReadout(opponentType: enc.opponent.type, weapons: enc.opponent.weapons,
                               shields: enc.opponent.shields.map(\.type), fleeOdds: odds)
    }

    /// UI-ENC-104 / CMB-049: the exact chance that one Flee round escapes, averaged over the opponent's possible pilot
    /// values (nil outside `.encounter`).
    var fleeProbability: ExactFraction? {
        guard let enc = encounter else { return nil }
        let s = state
        let d = s.difficulty.rawValue
        if s.difficulty == .beginner { return ExactFraction(numerator: 1, denominator: 1) }
        let playerPilot = s.shipSkills[SkillType.pilot.rawValue]
        let pilots = opponentPilotValues(enc.opponent)
        // Sum of count_p / (7 · P_p) over the pilot values, divided by their number, as one exact fraction.
        var num = 0, den = 1
        for p in pilots {
            let n = max(1, p)
            var count = 0
            for a in 0..<7 {
                for b in 0..<n where (a + playerPilot / 3) * 2 >= b * (2 + d) { count += 1 }
            }
            let termDen = 7 * n
            let l = Self.lcm(den, termDen)
            num = num * (l / den) + count * (l / termDen)
            den = l
        }
        den *= pilots.count
        let g = Self.gcd(num, den)
        return ExactFraction(numerator: num / g, denominator: den / g)
    }

    /// The opponent's effective pilot values the player cannot tell apart: the fixed value for table crews (famous
    /// captains, quest ships, bottles: ENC-080…082), else each generator pilot 1…10 (ENC-070…073) through the same
    /// effective-skill function with the opponent's visible gadgets.
    internal func opponentPilotValues(_ opponent: Ship) -> [Int] {
        let s = state
        let fixedCrews: Set<Int> = [CrewID.famousCaptain, CrewID.dragonfly, CrewID.scarab, CrewID.spaceMonster,
                                    CrewID.scorpion]
        let captain = opponent.crew.first ?? nil
        if captain == nil || captain.map({ fixedCrews.contains($0) }) == true {
            return [Skills.shipSkills(opponent, crew: s.mercenaries, difficulty: s.difficulty, ruleset: s.ruleset)[0]]
        }
        var probe = opponent
        probe.crew = [CrewID.opponent] + Array(repeating: nil, count: max(0, opponent.crew.count - 1))
        return (1...10).map { pilot in
            var crew = s.mercenaries
            if crew.indices.contains(CrewID.opponent) { crew[CrewID.opponent].skills = [pilot, 1, 1, 1] }
            return Skills.shipSkills(probe, crew: crew, difficulty: s.difficulty, ruleset: s.ruleset)[0]
        }
    }

    internal static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? max(1, abs(a)) : gcd(b, a % b) }
    internal static func lcm(_ a: Int, _ b: Int) -> Int { a / gcd(a, b) * b }
}
