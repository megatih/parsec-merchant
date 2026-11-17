// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// ParsecArt module of Parsec Merchant: procedural vector art drawn in code. It never sees game state.
public enum ParsecArtInfo {
    public static let version = "1.0.0"
}

/// ART-002: a value-type SplitMix64 generator. Independent of every engine generator (RNG-036).
public struct ArtRandom: Sendable, Hashable {
    public private(set) var state: UInt64

    public init(seed: UInt64) { state = seed }

    /// The next 64-bit output.
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        return ArtSeed.finalize(state)
    }

    /// A double in `[0, 1)` from the top 53 bits.
    public mutating func unit() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// A double in `range` (half-open at the top).
    public mutating func range(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + unit() * (range.upperBound - range.lowerBound)
    }

    /// An integer in `range`, both ends included.
    public mutating func int(_ range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % span)
    }
}

/// ART-002: seed derivation with fixed arithmetic only.
public enum ArtSeed {
    /// The SplitMix64 finaliser.
    public static func finalize(_ value: UInt64) -> UInt64 {
        var z = value
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// The SplitMix64 finaliser of `a ^ (b &* 0x9E3779B97F4A7C15)`.
    public static func mix(_ a: UInt64, _ b: UInt64) -> UInt64 {
        finalize(a ^ (b &* 0x9E37_79B9_7F4A_7C15))
    }

    /// The seed of a star system's art.
    public static func system(galaxySeed: UInt64, index: Int) -> UInt64 {
        mix(mix(galaxySeed, 0x5359_5354), UInt64(truncatingIfNeeded: index))
    }

    /// The seed of a crew member's avatar.
    public static func crew(galaxySeed: UInt64, crewID: Int) -> UInt64 {
        mix(mix(galaxySeed, 0x4352_4557), UInt64(truncatingIfNeeded: crewID))
    }

    /// A constant per ship kind (scorch blotches, monster tentacles).
    public static func kind(_ kind: ShipArtKind) -> UInt64 {
        mix(0x5348_4950, UInt64(kind.rawValue))
    }

    /// A seed from small integers (sparks, debris).
    public static func of(_ values: Int...) -> UInt64 {
        values.reduce(0x4152_5453) { mix($0, UInt64(truncatingIfNeeded: $1)) }
    }
}
