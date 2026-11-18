// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// ART-007: the 17 ship art kinds, in engine `ShipType` order with equal raw values.
public enum ShipArtKind: Int, CaseIterable, Sendable, Hashable {
    case flea = 0, gnat, firefly, mosquito, bumblebee, beetle, hornet, grasshopper, termite, wasp
    case spaceMonster, dragonfly, mantis, scarab, bottle, custom, scorpion

    /// The ten kinds a shipyard sells (the designer silhouettes).
    public static let buyable: [ShipArtKind] = [.flea, .gnat, .firefly, .mosquito, .bumblebee, .beetle, .hornet, .grasshopper,
                                                .termite, .wasp]

    public var isBuyable: Bool { rawValue <= ShipArtKind.wasp.rawValue }
}

/// Which way the ship points.
public enum ShipFacing: Sendable, Hashable {
    case right, left
}

/// ART-008: the strongest installed shield and the summed charge over the summed power.
public struct ShieldDisplay: Sendable, Hashable {
    public enum Kind: Int, Sendable, Hashable, CaseIterable {
        case energy = 0, reflective, lightning
    }

    public var kind: Kind
    public var fraction: Double

    public init(kind: Kind, fraction: Double) {
        self.kind = kind
        self.fraction = min(1, max(0, fraction))
    }
}

/// ART-008: the statistics that shape a ship's picture, and optionally what is installed on it.
public struct ShipArtStats: Sendable, Hashable {
    /// `ShipSpec.size` raw value, 0…5.
    public var sizeClass: Int
    public var cargoBays: Int
    public var weaponSlots: Int
    public var shieldSlots: Int
    public var gadgetSlots: Int
    public var crewQuarters: Int
    public var fuelTanks: Int
    public var hullStrength: Int
    /// 0…5: how many of `priceThresholds` the price reaches.
    public var priceTier: Int
    /// 0…7: the tech level a shipyard needs to sell it (7 for ships no shipyard sells).
    public var techTier: Int
    /// The installed equipment's raw type values; nil = not known (every slot is drawn filled).
    public var weapons: [Int]?
    public var shields: [Int]?
    public var gadgets: [Int]?

    public static let priceThresholds = [5000, 20000, 50000, 90000, 200_000]

    public static func priceTier(price: Int) -> Int { priceThresholds.filter { price >= $0 }.count }

    public init(sizeClass: Int, cargoBays: Int, weaponSlots: Int, shieldSlots: Int, gadgetSlots: Int, crewQuarters: Int, fuelTanks: Int,
                hullStrength: Int, priceTier: Int, techTier: Int, weapons: [Int]? = nil, shields: [Int]? = nil, gadgets: [Int]? = nil) {
        self.sizeClass = min(5, max(0, sizeClass))
        self.cargoBays = max(0, cargoBays)
        self.weaponSlots = max(0, weaponSlots)
        self.shieldSlots = max(0, shieldSlots)
        self.gadgetSlots = max(0, gadgetSlots)
        self.crewQuarters = max(0, crewQuarters)
        self.fuelTanks = max(0, fuelTanks)
        self.hullStrength = max(0, hullStrength)
        self.priceTier = min(5, max(0, priceTier))
        self.techTier = min(7, max(0, techTier))
        self.weapons = weapons
        self.shields = shields
        self.gadgets = gadgets
    }

    /// ART-088: the art's reference table: size, bays, weapons, shields, gadgets, crew, fuel, hull, price, tech (the
    /// Windows 2.01 statistics in `ShipArtKind` order; the custom entry is a mid-sized yard design).
    private static let table: [[Int]] = [
        [0, 10, 0, 0, 0, 1, 20, 25, 2000, 4], [1, 15, 1, 0, 1, 1, 14, 100, 10000, 5], [1, 20, 1, 1, 1, 1, 17, 100, 25000, 5],
        [1, 15, 2, 1, 1, 1, 13, 100, 30000, 5], [2, 25, 1, 2, 2, 2, 15, 100, 60000, 5], [2, 50, 0, 1, 1, 3, 14, 50, 80000, 5],
        [3, 20, 3, 2, 1, 2, 16, 150, 100_000, 6], [3, 30, 2, 2, 3, 3, 15, 150, 150_000, 6], [4, 60, 1, 3, 2, 3, 13, 200, 225_000, 7],
        [4, 35, 3, 2, 2, 3, 14, 200, 300_000, 7], [4, 0, 3, 0, 0, 1, 1, 500, 500_000, 7], [1, 0, 2, 3, 2, 1, 1, 10, 500_000, 7],
        [2, 0, 3, 1, 3, 3, 1, 300, 500_000, 7], [3, 20, 2, 0, 0, 2, 1, 400, 500_000, 7], [1, 0, 0, 0, 0, 0, 1, 10, 100, 7],
        [2, 20, 1, 1, 1, 1, 15, 100, 60000, 5], [4, 30, 2, 2, 2, 2, 1, 300, 500_000, 7]
    ]

    public static func standard(_ kind: ShipArtKind) -> ShipArtStats {
        let r = table[kind.rawValue]
        return ShipArtStats(sizeClass: r[0], cargoBays: r[1], weaponSlots: r[2], shieldSlots: r[3], gadgetSlots: r[4], crewQuarters: r[5],
                            fuelTanks: r[6], hullStrength: r[7], priceTier: priceTier(price: r[8]), techTier: r[9])
    }
}

/// ART-008: everything `ShipArt` needs; no game state.
public struct ShipArtInput: Sendable, Hashable {
    public var kind: ShipArtKind
    public var stats: ShipArtStats
    public var facing: ShipFacing
    public var hullFraction: Double
    public var shield: ShieldDisplay?
    public var disabled: Bool
    public var cloaked: Bool
    /// The planform, wing and nacelle families; nil = `ArtSeed.kind(kind)` (ART-010).
    public var variant: UInt64?
    public var phase: Double
    public var accessibility: ArtAccessibility

    /// `stats` nil = the reference table (ART-088); `sizeClass` overrides the statistics' size class.
    public init(kind: ShipArtKind, stats: ShipArtStats? = nil, sizeClass: Int? = nil, facing: ShipFacing = .right, hullFraction: Double = 1,
                shield: ShieldDisplay? = nil, disabled: Bool = false, cloaked: Bool = false, variant: UInt64? = nil,
                phase: Double = 0, accessibility: ArtAccessibility = .standard) {
        self.kind = kind
        var s = stats ?? ShipArtStats.standard(kind)
        if let sizeClass { s.sizeClass = min(5, max(0, sizeClass)) }
        self.stats = s
        self.facing = facing
        self.hullFraction = min(1, max(0, hullFraction))
        self.shield = shield
        self.disabled = disabled
        self.cloaked = cloaked
        self.variant = variant
        self.phase = phase
        self.accessibility = accessibility
    }

    public var sizeClass: Int { stats.sizeClass }

    /// The blueprint drawn for this input: a special design, or the generator's hull for the statistics (ART-009…012).
    public var blueprint: ShipBlueprint {
        if let special = ShipSpecials.blueprint(kind, stats: stats) { return special }
        var bp = ShipHullGenerator.make(stats, variant: variant ?? ArtSeed.kind(kind))
        if kind == .custom { bp.livery = Livery(primary: .brass, secondary: .slate, accent: .ivory) }
        return bp
    }
}
