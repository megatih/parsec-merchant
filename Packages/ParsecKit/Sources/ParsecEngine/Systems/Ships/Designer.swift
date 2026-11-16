// SPDX-License-Identifier: GPL-2.0-or-later
// Custom shipyard designer (docs/specs/SHP.md §12, SHP-063…076, SHP-083). Windows 2.01 and Modern content only.

/// Per-size designer tables (Shipyard.cs:37-77), indexed by `SystemSize` Tiny…Gargantuan.
public enum DesignerTables {
    public static let costFuel = [1, 1, 1, 3, 5, 10]
    public static let costHull = [1, 5, 10, 15, 20, 40]
    public static let baseFuel = [15, 14, 13, 12, 11, 10]
    public static let baseHull = [10, 25, 50, 100, 150, 200]
    public static let designFee = [2_000, 5_000, 10_000, 20_000, 40_000, 100_000]
    public static let maxUnits = [50, 100, 150, 200, 250, 999]
    public static let perUnitFuel = [3, 2, 1, 1, 1, 1]
    public static let perUnitHull = [35, 30, 25, 20, 15, 10]
    public static let pricePerUnit = [75, 250, 500, 750, 1_000, 1_200]
    public static let unitsCrew = 20
    public static let unitsFuel = [1, 1, 1, 5, 10, 15]
    public static let unitsGadget = 5
    public static let unitsHull = [1, 2, 3, 4, 5, 6]
    public static let unitsShield = [10, 10, 10, 8, 8, 8]
    public static let unitsWeapon = [15, 15, 15, 10, 10, 10]

    /// Shipyard specialty size and skill (Consts.cs:272-279).
    public static func shipyard(_ id: ShipyardID) -> (size: SystemSize, skill: ShipyardSkill) {
        switch id {
        case .corellian: (.large, .crewQuarters)
        case .incom: (.medium, .shieldSlotUnits)
        case .kuat: (.huge, .hullPerUnit)
        case .sienar: (.tiny, .weaponSlotUnits)
        case .sorosuub: (.small, .fuelBase)
        }
    }
}

/// A player's design input.
public struct ShipDesign: Codable, Sendable, Equatable {
    public var name: String
    public var size: SystemSize
    public var cargoBays: Int
    public var fuelTanks: Int
    public var hull: Int
    public var weaponSlots: Int
    public var shieldSlots: Int
    public var gadgetSlots: Int
    public var crewQuarters: Int

    public init(name: String, size: SystemSize, cargoBays: Int, fuelTanks: Int, hull: Int, weaponSlots: Int,
                shieldSlots: Int, gadgetSlots: Int, crewQuarters: Int) {
        self.name = name
        self.size = size
        self.cargoBays = cargoBays
        self.fuelTanks = fuelTanks
        self.hull = hull
        self.weaponSlots = weaponSlots
        self.shieldSlots = shieldSlots
        self.gadgetSlots = gadgetSlots
        self.crewQuarters = crewQuarters
    }
}

/// Every derived figure of a design at a given shipyard (SHP-066…071, SHP-083).
public struct DesignQuote: Sendable, Equatable {
    public var design: ShipDesign
    public var baseFuel: Int
    public var baseHull: Int
    public var unitsUsed: Int
    public var maxUnits: Int
    public var percentOfMax: Int
    public var basePrice: Int
    public var penalty: Int
    public var adjustment: Int
    public var adjustedPrice: Int
    public var adjustedPenalty: Int
    public var adjustedFee: Int
    public var tradeIn: Int
    public var totalCost: Int
    public var spec: ShipSpec
    public var canBuild: Bool
    public var blocker: CommandError?
}

public enum Designer {
    /// SHP-065: sizes selectable at a shipyard.
    public static func sizes(for yard: ShipyardID) -> [SystemSize] {
        let s = DesignerTables.shipyard(yard).size.rawValue
        return SystemSize.allCases.filter { abs($0.rawValue - s) <= 2 }
    }

    /// SHP-072/073: clamps inputs and snaps fuel/hull up to whole units.
    public static func normalized(_ d: ShipDesign, yard: ShipyardID) -> ShipDesign {
        var d = d
        let s = d.size.rawValue
        let skill = DesignerTables.shipyard(yard).skill
        let baseFuel = DesignerTables.baseFuel[s] + (skill == .fuelBase ? 2 : 0)
        let baseHull = DesignerTables.baseHull[s]
        let puf = DesignerTables.perUnitFuel[s]
        let puh = DesignerTables.perUnitHull[s] + (skill == .hullPerUnit ? 5 : 0)
        d.cargoBays = min(999, max(0, d.cargoBays))
        d.fuelTanks = min(20, max(baseFuel, d.fuelTanks))
        d.hull = min(9_999, max(baseHull, d.hull))
        d.weaponSlots = min(5, max(0, d.weaponSlots))
        d.shieldSlots = min(5, max(0, d.shieldSlots))
        d.gadgetSlots = min(5, max(0, d.gadgetSlots))
        d.crewQuarters = min(5, max(1, d.crewQuarters))
        let extraFuel = d.fuelTanks - baseFuel
        if extraFuel % puf > 0, d.fuelTanks < 20 {
            d.fuelTanks = min(20, ((extraFuel + puf) / puf) * puf + baseFuel)
        }
        let extraHull = d.hull - baseHull
        if extraHull % puh > 0 {
            d.hull = ((extraHull + puh) / puh) * puh + baseHull
        }
        return d
    }

    /// SHP-066…071: the quote for a design at `yard`, given the current ship's trade-in value.
    public static func quote(_ design: ShipDesign, yard: ShipyardID, tradeIn: Int) -> DesignQuote {
        let d = normalized(design, yard: yard)
        let s = d.size.rawValue
        let (specialty, skill) = DesignerTables.shipyard(yard)
        let baseFuel = DesignerTables.baseFuel[s] + (skill == .fuelBase ? 2 : 0)
        let baseHull = DesignerTables.baseHull[s]
        let perUnitFuel = DesignerTables.perUnitFuel[s]
        let perUnitHull = DesignerTables.perUnitHull[s] + (skill == .hullPerUnit ? 5 : 0)
        let unitsCrew = DesignerTables.unitsCrew - (skill == .crewQuarters ? 2 : 0)
        let unitsShield = DesignerTables.unitsShield[s] - (skill == .shieldSlotUnits ? 2 : 0)
        let unitsWeapon = DesignerTables.unitsWeapon[s] - (skill == .weaponSlotUnits ? 2 : 0)
        let fuelUnits = Int((Double(d.fuelTanks - baseFuel) / Double(perUnitFuel) * Double(DesignerTables.unitsFuel[s])).rounded(.up))
        let units = d.cargoBays + d.crewQuarters * unitsCrew + fuelUnits + d.gadgetSlots * DesignerTables.unitsGadget
            + (d.hull - baseHull) / perUnitHull * DesignerTables.unitsHull[s]
            + d.shieldSlots * unitsShield + d.weaponSlots * unitsWeapon
        let maxUnits = DesignerTables.maxUnits[s]
        let percent = units * 100 / maxUnits
        let basePrice = units * DesignerTables.pricePerUnit[s]
        let penalty = percent >= 90 ? basePrice * 75 / 100 : (percent >= 80 ? basePrice * 25 / 100 : 0)
        let diff = abs(s - specialty.rawValue)
        let adj = diff == 0 ? 90 : (diff == 1 ? 100 : 110)
        let adjustedPrice = basePrice * adj / 100
        let adjustedPenalty = penalty * adj / 100
        let adjustedFee = DesignerTables.designFee[s] * adj / 100
        let total = adjustedPrice + adjustedPenalty + adjustedFee - tradeIn
        let spec = ShipSpec(.custom, d.size, bays: d.cargoBays, weapons: d.weaponSlots, shields: d.shieldSlots,
                            gadgets: d.gadgetSlots, crew: d.crewQuarters, fuel: d.fuelTanks,
                            fuelCost: DesignerTables.costFuel[s], hull: d.hull, repairCost: DesignerTables.costHull[s],
                            price: basePrice + penalty, occurrence: 0, police: .na, pirates: .na, traders: .na, tech: .unavailable)
        var blocker: CommandError?
        if d.name.allSatisfy({ $0 == " " }) { blocker = .designNameEmpty }
        if percent > 100 { blocker = .designOverCapacity }
        return DesignQuote(design: d, baseFuel: baseFuel, baseHull: baseHull, unitsUsed: units, maxUnits: maxUnits,
                           percentOfMax: percent, basePrice: basePrice, penalty: penalty, adjustment: adj,
                           adjustedPrice: adjustedPrice, adjustedPenalty: adjustedPenalty, adjustedFee: adjustedFee,
                           tradeIn: tradeIn, totalCost: total, spec: spec, canBuild: blocker == nil, blocker: blocker)
    }

    /// SHP-076: the minimum design for a size at a yard (template).
    public static func minimumDesign(size: SystemSize, yard: ShipyardID) -> ShipDesign {
        normalized(ShipDesign(name: "", size: size, cargoBays: 0, fuelTanks: 0, hull: 0, weaponSlots: 0, shieldSlots: 0,
                              gadgetSlots: 0, crewQuarters: 1), yard: yard)
    }
}

public extension GameState {
    /// SHP-083: the designer quote at the current system's shipyard, or nil if there is none.
    func designQuote(_ design: ShipDesign) -> DesignQuote? {
        guard ruleset.content.hasShipyards, let yard = currentSystem.shipyard else { return nil }
        return Designer.quote(design, yard: yard, tradeIn: shipWorth(forInsurance: false))
    }
}
