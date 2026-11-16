// SPDX-License-Identifier: GPL-2.0-or-later

/// A deterministic random number source with the semantics of the original game's `GetRandom` helpers.
///
/// - `next(below: max)` ≡ C# `Functions.GetRandom(max)` ≡ `Random.Next(0, max)`: uniform in `0..<max`; returns 0 when `max <= 0`
///   (matching .NET `Next(0, 0) == 0`, which the original relies on, e.g. `GetRandom(Opponent.Pilot)`).
/// - `next(in: min, max)` ≡ C# `Functions.GetRandom(min, max)`: uniform in `min..<max` (exclusive upper bound); returns `min`
///   when `max <= min`.
public protocol RandomSource: Sendable {
    mutating func next(below max: Int) -> Int
    mutating func next(in min: Int, _ max: Int) -> Int
}

public extension RandomSource {
    /// `Functions.RandomSkill()`: `1 + GetRandom(5) + GetRandom(6)` → 1…10.
    mutating func randomSkill() -> Int {
        1 + next(below: 5) + next(below: 6)
    }

    /// Convenience: a fair coin, `GetRandom(2) == 0`.
    mutating func coin() -> Bool {
        next(below: 2) == 0
    }
}

/// The game-logic generator kinds a ruleset can use.
public enum RNGKind: String, Codable, Sendable, CaseIterable {
    /// Exact port of .NET's seeded `System.Random` (Windows 2.01 ruleset).
    case dotNet
    /// Documented LCG stand-in for the Palm OS ROM `SysRandom` (Palm 1.2.2 ruleset; rule-faithful, not sequence-faithful).
    case palmLCG
    /// xoshiro256** seeded through SplitMix64 (Modern ruleset).
    case xoshiro
}

/// Serializable game-logic RNG state. Stored in the save so that games are reproducible.
public enum RNGState: Codable, Sendable, Equatable, RandomSource {
    case dotNet(DotNetRandom)
    case palmLCG(PalmLCG)
    case xoshiro(Xoshiro256StarStar)

    public init(kind: RNGKind, seed: UInt64) {
        switch kind {
        case .dotNet: self = .dotNet(DotNetRandom(seed: Int32(truncatingIfNeeded: seed)))
        case .palmLCG: self = .palmLCG(PalmLCG(seed: UInt32(truncatingIfNeeded: seed)))
        case .xoshiro: self = .xoshiro(Xoshiro256StarStar(seed: seed))
        }
    }

    public var kind: RNGKind {
        switch self {
        case .dotNet: .dotNet
        case .palmLCG: .palmLCG
        case .xoshiro: .xoshiro
        }
    }

    public mutating func next(below max: Int) -> Int {
        switch self {
        case .dotNet(var g): let v = g.next(below: max); self = .dotNet(g); return v
        case .palmLCG(var g): let v = g.next(below: max); self = .palmLCG(g); return v
        case .xoshiro(var g): let v = g.next(below: max); self = .xoshiro(g); return v
        }
    }

    public mutating func next(in min: Int, _ max: Int) -> Int {
        switch self {
        case .dotNet(var g): let v = g.next(in: min, max); self = .dotNet(g); return v
        case .palmLCG(var g): let v = g.next(in: min, max); self = .palmLCG(g); return v
        case .xoshiro(var g): let v = g.next(in: min, max); self = .xoshiro(g); return v
        }
    }
}
