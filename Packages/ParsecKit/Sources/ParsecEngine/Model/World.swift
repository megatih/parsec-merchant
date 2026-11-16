// SPDX-License-Identifier: GPL-2.0-or-later
// World state value types: star systems, galaxy, crew, ships, commander.

/// A star system (C# `StarSystem`).
public struct StarSystem: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var x: Int
    public var y: Int
    public var size: SystemSize
    public var techLevel: TechLevel
    public var politics: PoliticalSystemType
    public var pressure: SystemPressure
    /// The true special resource. What the player sees depends on `visited` (see `knownResource`).
    public var specialResource: SpecialResource
    public var specialEvent: SpecialEventType?
    public var shipyard: ShipyardID?
    /// Market stock per `TradeItemType` raw value.
    public var tradeItems: [Int]
    public var countDown: Int
    public var visited: Bool

    public init(id: Int, x: Int, y: Int, size: SystemSize, techLevel: TechLevel, politics: PoliticalSystemType,
                pressure: SystemPressure, specialResource: SpecialResource) {
        self.id = id
        self.x = x
        self.y = y
        self.size = size
        self.techLevel = techLevel
        self.politics = politics
        self.pressure = pressure
        self.specialResource = specialResource
        specialEvent = nil
        shipyard = nil
        tradeItems = Array(repeating: 0, count: TradeItemType.allCases.count)
        countDown = 0
        visited = false
    }

    /// C# `StarSystem.SpecialResource` getter: hidden (`.nothing`) until the system has been visited.
    public var knownResource: SpecialResource {
        visited ? specialResource : .nothing
    }
}

/// The galaxy: systems plus the wormhole ring (`wormholes[k] -> wormholes[(k+1) % count]`).
public struct Galaxy: Codable, Sendable, Equatable {
    public var systems: [StarSystem]
    public var wormholes: [Int]

    /// True if a wormhole leads from `a` to `b`; with `b == nil`, true if `a` has a wormhole at all (C# `WormholeExists`).
    public func wormholeExists(from a: Int, to b: Int?) -> Bool {
        guard let i = wormholes.firstIndex(of: a) else { return false }
        guard let b else { return true }
        return wormholes[(i + 1) % wormholes.count] == b
    }

    /// Destination of the wormhole at system `a`, if any.
    public func wormholeDestination(from a: Int) -> Int? {
        guard let i = wormholes.firstIndex(of: a) else { return nil }
        return wormholes[(i + 1) % wormholes.count]
    }
}

/// A crew member (C# `CrewMember`). Skills are indexed by `SkillType` raw value.
public struct CrewMember: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var skills: [Int]
    /// The system where this mercenary waits for hire; `nil` when aboard or unplaced (C# `StarSystemId.NA`).
    public var systemID: Int?

    public init(id: Int, pilot: Int, fighter: Int, trader: Int, engineer: Int, systemID: Int?) {
        self.id = id
        skills = [pilot, fighter, trader, engineer]
        self.systemID = systemID
    }

    public func skill(_ s: SkillType) -> Int { skills[s.rawValue] }
}

/// An installed shield with its current charge.
public struct ShieldInstance: Codable, Sendable, Equatable {
    public var type: ShieldType
    public var charge: Int
}

/// A ship instance (C# `Ship`). Equipment arrays are compact (no holes); capacities come from the ship spec.
public struct Ship: Codable, Sendable, Equatable {
    public var type: ShipType
    public var fuel: Int
    public var hull: Int
    public var tribbles: Int
    /// Units per `TradeItemType` raw value.
    public var cargo: [Int]
    public var weapons: [WeaponType]
    public var shields: [ShieldInstance]
    public var gadgets: [GadgetType]
    /// Crew member ids aboard, slot 0 = captain. `nil` = vacant quarter.
    public var crew: [Int?]
    public var escapePod: Bool
    /// Hull upgrade from the Scarab quest (+50 hull strength).
    public var hullUpgraded: Bool
    /// The player's custom design, when `type == .custom`.
    public var customSpec: ShipSpec?

    /// A fresh ship of `type` with full fuel and hull (C# `Ship.SetValues`).
    public init(type: ShipType, spec: ShipSpec) {
        self.type = type
        fuel = spec.fuelTanks
        hull = spec.hullStrength
        tribbles = 0
        cargo = Array(repeating: 0, count: TradeItemType.allCases.count)
        weapons = []
        shields = []
        gadgets = []
        crew = Array(repeating: nil, count: spec.crewQuarters)
        escapePod = false
        hullUpgraded = false
        customSpec = nil
    }
}

/// Kill counters.
public struct Kills: Codable, Sendable, Equatable {
    public var pirates = 0
    public var police = 0
    public var traders = 0
}

/// The player (C# `Commander`, which extends `CrewMember` id 0).
public struct Commander: Codable, Sendable, Equatable {
    public var name: String
    public var cash: Int
    public var debt: Int
    public var kills: Kills
    public var policeRecordScore: Int
    public var reputationScore: Int
    public var days: Int
    public var insurance: Bool
    public var noClaim: Int
    public var ship: Ship
    /// Cost basis of the cargo per item (C# `PriceCargo`): total credits paid for the units currently held.
    public var priceCargo: [Int]
    public var currentSystem: Int
    /// Optional cosmetic ship name (PRD §4.3).
    public var shipName: String?
}
