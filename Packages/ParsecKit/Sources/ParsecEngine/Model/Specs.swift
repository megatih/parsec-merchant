// SPDX-License-Identifier: GPL-2.0-or-later
// Static specification records used by ruleset tables.

/// A ship type's static specification (C# `ShipSpec`; Palm `SHIPTYPE`).
public struct ShipSpec: Codable, Sendable, Equatable {
    public var type: ShipType
    public var size: SystemSize
    public var cargoBays: Int
    public var weaponSlots: Int
    public var shieldSlots: Int
    public var gadgetSlots: Int
    public var crewQuarters: Int
    public var fuelTanks: Int
    /// Credits per parsec of fuel.
    public var fuelCost: Int
    public var hullStrength: Int
    /// Credits per point of hull repaired.
    public var repairCost: Int
    public var price: Int
    /// Relative frequency among random opponents (percent weights).
    public var occurrence: Int
    public var police: Activity
    public var pirates: Activity
    public var traders: Activity
    public var minTechLevel: TechLevel

    public init(_ type: ShipType, _ size: SystemSize, bays: Int, weapons: Int, shields: Int, gadgets: Int, crew: Int,
                fuel: Int, fuelCost: Int, hull: Int, repairCost: Int, price: Int, occurrence: Int,
                police: Activity, pirates: Activity, traders: Activity, tech: TechLevel) {
        self.type = type
        self.size = size
        cargoBays = bays
        weaponSlots = weapons
        shieldSlots = shields
        gadgetSlots = gadgets
        crewQuarters = crew
        fuelTanks = fuel
        self.fuelCost = fuelCost
        hullStrength = hull
        self.repairCost = repairCost
        self.price = price
        self.occurrence = occurrence
        self.police = police
        self.pirates = pirates
        self.traders = traders
        minTechLevel = tech
    }
}

public struct WeaponSpec: Codable, Sendable, Equatable {
    public var type: WeaponType
    public var power: Int
    public var disabling: Bool
    public var price: Int
    public var minTechLevel: TechLevel
    /// Chance weight in random opponent equipment.
    public var chance: Int
}

public struct ShieldSpec: Codable, Sendable, Equatable {
    public var type: ShieldType
    public var power: Int
    public var price: Int
    public var minTechLevel: TechLevel
    public var chance: Int
}

public struct GadgetSpec: Codable, Sendable, Equatable {
    public var type: GadgetType
    /// The skill this gadget boosts, if any.
    public var skillBonus: SkillType?
    public var price: Int
    public var minTechLevel: TechLevel
    public var chance: Int
}

/// A commodity's static pricing data (C# `TradeItem`).
public struct TradeItemSpec: Codable, Sendable, Equatable {
    public var type: TradeItemType
    /// Minimum tech level to produce (buy here).
    public var techProduction: TechLevel
    /// Minimum tech level to use (sell here).
    public var techUsage: TechLevel
    /// Tech level with the highest production.
    public var techTopProduction: TechLevel
    public var priceLowTech: Int
    public var priceIncrease: Int
    /// Absolute credits of random variation (despite the original field name "percentage").
    public var variance: Int
    public var pressurePriceHike: SystemPressure
    public var resourceLowPrice: SpecialResource?
    public var resourceHighPrice: SpecialResource?
    public var minTradePrice: Int
    public var maxTradePrice: Int
    public var roundOff: Int
}

/// A government type's static data (C# `PoliticalSystem`).
public struct PoliticalSystemSpec: Codable, Sendable, Equatable {
    public var type: PoliticalSystemType
    public var reactionIllegal: Int
    public var activityPolice: Activity
    public var activityPirates: Activity
    public var activityTraders: Activity
    public var minTech: TechLevel
    public var maxTech: TechLevel
    public var bribeLevel: Int
    public var drugsOK: Bool
    public var firearmsOK: Bool
    public var wanted: TradeItemType?
}

/// A special event's static data (C# `SpecialEvent`). Negative prices are credits paid to the player.
public struct SpecialEventSpec: Codable, Sendable, Equatable {
    public var type: SpecialEventType
    public var price: Int
    public var occurrence: Int
    public var messageOnly: Bool
}

/// A special event assigned to a fixed system before any random placement (C# `PlaceSpecialEvents`, Palm `StartNewGame`).
public struct FixedSpecialEvent: Codable, Sendable, Equatable {
    public var system: Int
    public var event: SpecialEventType
}
