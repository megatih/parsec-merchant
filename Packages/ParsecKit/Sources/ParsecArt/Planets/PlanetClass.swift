// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// ART-068: the planet class taxonomy. Rings are a modifier (`PlanetRecipe.ring`), not a class.
public enum PlanetClass: Int, CaseIterable, Sendable, Hashable {
    case terran = 0, ocean, desert, ice, jungle, rocky, barren, volcanic, toxic, gasGiant

    /// ART-068: the seed weights, in case order.
    public static let weights: [Double] = [22, 10, 12, 10, 8, 12, 8, 6, 4, 8]
    /// ART-068: gas giants appear only from this size class (large) up.
    public static let gasGiantMinimumSize = 3

    /// The seed-weighted class for a roll in `[0, 1)`.
    public static func seeded(roll: Double, sizeClass: Int) -> PlanetClass {
        var w = weights
        if sizeClass < gasGiantMinimumSize { w[PlanetClass.gasGiant.rawValue] = 0 }
        var x = roll * w.reduce(0, +)
        for c in allCases {
            x -= w[c.rawValue]
            if x < 0 { return c }
        }
        return .terran
    }

    /// ART-069: the class and tint a known resource forces (`SpecialResource` raw values 0…12); nil class = seed-weighted.
    public static func forResource(_ look: PlanetResourceLook) -> (planetClass: PlanetClass?, tint: PlanetTint, accent: PlanetAccent) {
        switch look {
        case .nothing: (nil, .none, .none)
        case .mineralRich: (.rocky, .ore, .none)
        case .mineralPoor: (.rocky, .dull, .none)
        case .desert: (.desert, .none, .none)
        case .sweetOceans: (.ocean, .none, .none)
        case .richSoil: (.terran, .fertile, .none)
        case .poorSoil: (.terran, .pale, .none)
        case .richFauna: (.jungle, .none, .none)
        case .lifeless: (.barren, .none, .none)
        case .weirdMushrooms: (.toxic, .fungal, .none)
        case .specialHerbs: (.jungle, .herbal, .none)
        case .artistic: (nil, .none, .artistic)
        case .warlike: (nil, .none, .warlike)
        }
    }

    /// ART-068: the chance of a natural ring.
    public var ringChance: Double {
        switch self {
        case .gasGiant: 0.6
        case .ice, .rocky, .barren: 0.08
        case .terran, .ocean, .desert, .jungle, .volcanic, .toxic: 0
        }
    }

    public var hasWater: Bool { self == .terran || self == .ocean || self == .jungle || self == .ice }
    public var hasAir: Bool { self != .barren }
}

/// ART-069: a palette tint within a class.
public enum PlanetTint: Int, CaseIterable, Sendable, Hashable {
    case none = 0, ore, dull, fertile, pale, fungal, herbal
}

/// ART-069: an atmosphere accent for cultural resources.
public enum PlanetAccent: Int, CaseIterable, Sendable, Hashable {
    case none = 0, artistic, warlike
}

/// ART-068: a natural ring (radii in planet radii).
public struct PlanetNaturalRing: Sendable, Hashable {
    public var inner: Double
    public var outer: Double
    public var opacity: Double
    public var seed: Double
    public var tint: Int
}
