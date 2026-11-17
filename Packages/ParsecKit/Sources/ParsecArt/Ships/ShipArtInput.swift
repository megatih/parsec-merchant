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

/// ART-012: the parameters of a custom ship (from `Ship.customSpec` or the designer draft).
public struct CustomShipParams: Sendable, Hashable {
    public var sizeClass: Int
    public var weaponSlots: Int
    public var shieldSlots: Int
    public var gadgetSlots: Int
    public var crewQuarters: Int
    public var fuelTanks: Int
    public var cargoBays: Int
    public var hullStrength: Int
    /// The designer's silhouette (a buyable kind) for the live preview; nil = the neutral yard frame.
    public var base: ShipArtKind?

    public init(sizeClass: Int, weaponSlots: Int, shieldSlots: Int, gadgetSlots: Int, crewQuarters: Int, fuelTanks: Int,
                cargoBays: Int, hullStrength: Int, base: ShipArtKind? = nil) {
        self.sizeClass = sizeClass
        self.weaponSlots = weaponSlots
        self.shieldSlots = shieldSlots
        self.gadgetSlots = gadgetSlots
        self.crewQuarters = crewQuarters
        self.fuelTanks = fuelTanks
        self.cargoBays = cargoBays
        self.hullStrength = hullStrength
        self.base = base
    }

    /// A mid-sized yard design (used when a custom ship has no saved spec, and by tests).
    public static let standard = CustomShipParams(sizeClass: 2, weaponSlots: 1, shieldSlots: 1, gadgetSlots: 1, crewQuarters: 1,
                                                  fuelTanks: 15, cargoBays: 20, hullStrength: 100)
}

/// ART-008: everything `ShipArt` needs; no game state.
public struct ShipArtInput: Sendable, Hashable {
    public var kind: ShipArtKind
    /// `ShipSpec.size` raw value, 0…5.
    public var sizeClass: Int
    public var facing: ShipFacing
    public var hullFraction: Double
    public var shield: ShieldDisplay?
    public var disabled: Bool
    public var cloaked: Bool
    public var custom: CustomShipParams?
    public var phase: Double
    public var accessibility: ArtAccessibility

    public init(kind: ShipArtKind, sizeClass: Int = 2, facing: ShipFacing = .right, hullFraction: Double = 1,
                shield: ShieldDisplay? = nil, disabled: Bool = false, cloaked: Bool = false, custom: CustomShipParams? = nil,
                phase: Double = 0, accessibility: ArtAccessibility = .standard) {
        self.kind = kind
        self.sizeClass = min(5, max(0, sizeClass))
        self.facing = facing
        self.hullFraction = min(1, max(0, hullFraction))
        self.shield = shield
        self.disabled = disabled
        self.cloaked = cloaked
        self.custom = custom
        self.phase = phase
        self.accessibility = accessibility
    }

    /// The blueprint drawn for this input.
    public var blueprint: ShipBlueprint {
        kind == .custom ? ShipBlueprints.custom(custom ?? .standard) : ShipBlueprints.blueprint(kind)
    }
}
