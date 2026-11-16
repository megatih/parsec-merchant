// SPDX-License-Identifier: GPL-2.0-or-later

/// Stand-in for the Palm OS ROM `SysRandom` used by Palm 1.2.2 game logic (`GetRandom(a) = SysRandom(0) % a`).
/// The ROM algorithm is unverified, so the Palm ruleset is rule-faithful rather than sequence-faithful (PRD §4.2).
/// Algorithm: `seed = 0x015A4E35 * seed + 1; value = (seed >> 16) & 0x7FFF` (0…32767, like `sysRandomMax`).
public struct PalmLCG: Codable, Sendable, Equatable, RandomSource {
    public private(set) var state: UInt32

    public init(seed: UInt32) {
        state = seed
    }

    /// One `SysRandom(0)` value in `0...0x7FFF`.
    public mutating func sysRandom() -> Int {
        state = 0x015A_4E35 &* state &+ 1
        return Int((state >> 16) & 0x7FFF)
    }

    /// RNG-004/027: `max == 0` returns 0 but still consumes one step, keeping call counts aligned with .NET.
    public mutating func next(below max: Int) -> Int {
        precondition(max >= 0, "next(below:) requires max >= 0 (RNG-003)")
        let v = sysRandom()
        return max > 0 ? v % max : 0
    }

    public mutating func next(in min: Int, _ max: Int) -> Int {
        min + next(below: max - min)
    }
}

/// xoshiro256** 1.0 (Blackman & Vigna), seeded through SplitMix64. Used by the Modern ruleset.
public struct Xoshiro256StarStar: Codable, Sendable, Equatable, RandomSource {
    private var s0: UInt64
    private var s1: UInt64
    private var s2: UInt64
    private var s3: UInt64

    public init(seed: UInt64) {
        var sm = SplitMix64(state: seed)
        s0 = sm.next()
        s1 = sm.next()
        s2 = sm.next()
        s3 = sm.next()
    }

    private static func rotl(_ x: UInt64, _ k: UInt64) -> UInt64 {
        (x << k) | (x >> (64 &- k))
    }

    public mutating func nextUInt64() -> UInt64 {
        let result = Self.rotl(s1 &* 5, 7) &* 9
        let t = s1 << 17
        s2 ^= s0
        s3 ^= s1
        s1 ^= s2
        s0 ^= s3
        s2 ^= t
        s3 = Self.rotl(s3, 45)
        return result
    }

    /// Unbiased bounded integer (Lemire's multiply-shift with rejection).
    /// Lemire multiply-shift with rejection (RNG-031). `max == 0` consumes one draw and returns 0 (RNG-004).
    public mutating func next(below max: Int) -> Int {
        precondition(max >= 0, "next(below:) requires max >= 0 (RNG-003)")
        guard max > 0 else { _ = nextUInt64(); return 0 }
        let bound = UInt64(max)
        var m = nextUInt64().multipliedFullWidth(by: bound)
        if m.low < bound {
            let threshold = (0 &- bound) % bound
            while m.low < threshold {
                m = nextUInt64().multipliedFullWidth(by: bound)
            }
        }
        return Int(m.high)
    }

    public mutating func next(in min: Int, _ max: Int) -> Int {
        min + next(below: max - min)
    }

    // RNG-032: the four state words are encoded as 16-digit upper-case hex strings.
    private enum CodingKeys: String, CodingKey { case s }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let words = try c.decode([String].self, forKey: .s)
        guard words.count == 4, let a = UInt64(words[0], radix: 16), let b = UInt64(words[1], radix: 16),
              let cc = UInt64(words[2], radix: 16), let d = UInt64(words[3], radix: 16) else {
            throw DecodingError.dataCorruptedError(forKey: .s, in: c, debugDescription: "expected 4 hex words")
        }
        (s0, s1, s2, s3) = (a, b, cc, d)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        func hex(_ v: UInt64) -> String {
            let h = String(v, radix: 16, uppercase: true)
            return String(repeating: "0", count: 16 - h.count) + h
        }
        try c.encode([hex(s0), hex(s1), hex(s2), hex(s3)], forKey: .s)
    }
}

/// SplitMix64, used only to expand a 64-bit seed into xoshiro state.
public struct SplitMix64: Sendable {
    public var state: UInt64

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Pieter Spronck's two-seed generator used for newspapers (`Rand` / `RandSeed` / `GetRandom2`), in the two
/// variants the sources actually implement (PRD §4.2).
public struct PieterRand: Codable, Sendable, Equatable {
    public enum Variant: String, Codable, Sendable {
        /// C# `Functions.cs`: 64-bit `long` seeds, defaults 521288629 / 362436069, no truncation. Never negative.
        case csharp
        /// Palm `Math.c`: `UInt16` seeds (defaults truncate to 15285 / 21989); output equals the SeedY recurrence.
        case palm
    }

    public let variant: Variant
    private var seedX: Int64
    private var seedY: Int64

    static let defSeedX: Int64 = 521_288_629
    static let defSeedY: Int64 = 362_436_069

    public init(variant: Variant) {
        self.variant = variant
        seedX = 0
        seedY = 0
        seed(0, 0)
    }

    /// `RandSeed(seed1, seed2)`: a value ≤ 0 (C#) or == 0 after UInt16 truncation (Palm) selects the default seed.
    public mutating func seed(_ seed1: Int, _ seed2: Int) {
        switch variant {
        case .csharp:
            seedX = seed1 > 0 ? Int64(seed1) : Self.defSeedX
            seedY = seed2 > 0 ? Int64(seed2) : Self.defSeedY
        case .palm:
            let s1 = Int64(UInt16(truncatingIfNeeded: seed1))
            let s2 = Int64(UInt16(truncatingIfNeeded: seed2))
            seedX = s1 != 0 ? s1 : Int64(UInt16(truncatingIfNeeded: Self.defSeedX))
            seedY = s2 != 0 ? s2 : Int64(UInt16(truncatingIfNeeded: Self.defSeedY))
        }
    }

    /// `Rand()`.
    public mutating func rand() -> Int64 {
        let a: Int64 = 18_000
        let b: Int64 = 30_903
        switch variant {
        case .csharp:
            seedX = a * (seedX & 0xFFFF) + (seedX >> 16)
            seedY = b * (seedY & 0xFFFF) + (seedY >> 16)
            return (seedX << 16) + (seedY & 0xFFFF)
        case .palm:
            // UInt16 storage: SeedX>>16 == 0 and every product is truncated to 16 bits;
            // the UInt16 return value equals the new SeedY.
            seedX = (a * seedX) & 0xFFFF
            seedY = (b * seedY) & 0xFFFF
            return seedY
        }
    }

    /// `GetRandom2(max)`: `Rand() % max`.
    public mutating func getRandom2(_ max: Int) -> Int {
        guard max > 0 else { return 0 }
        return Int(rand() % Int64(max))
    }
}
