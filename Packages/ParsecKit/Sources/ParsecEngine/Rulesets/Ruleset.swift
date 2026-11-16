// SPDX-License-Identifier: GPL-2.0-or-later

/// Identifies a ruleset; stored in saves. Engine systems never branch on this value (PRD §4.1).
public enum RulesetID: String, Codable, Sendable, CaseIterable {
    case modern
    case windows201
    case palm122
}

/// Static data tables of a ruleset.
public struct RulesTables: Sendable {
    public var ships: [ShipSpec]
    public var weapons: [WeaponSpec]
    public var shields: [ShieldSpec]
    public var gadgets: [GadgetSpec]
    public var tradeItems: [TradeItemSpec]
    public var politicalSystems: [PoliticalSystemSpec]
    public var specialEvents: [SpecialEventSpec]
    public var systemNames: [String]
    public var galaxyWidth: Int
    public var galaxyHeight: Int
    /// Systems closer than this are rejected during generation.
    public var minDistance: Int
    /// Each new system needs a neighbour closer than this.
    public var closeDistance: Int
    /// Offset range for the six central (wormhole) systems: `GetRandom(-offset+1, offset)`.
    public var centralOffset: Int
    public var startingCash: Int

    public func ship(_ t: ShipType) -> ShipSpec { ships[t.rawValue] }
    public func weapon(_ t: WeaponType) -> WeaponSpec { weapons[t.rawValue] }
    public func shield(_ t: ShieldType) -> ShieldSpec { shields[t.rawValue] }
    public func gadget(_ t: GadgetType) -> GadgetSpec { gadgets[t.rawValue] }
    public func item(_ t: TradeItemType) -> TradeItemSpec { tradeItems[t.rawValue] }
    public func politics(_ t: PoliticalSystemType) -> PoliticalSystemSpec { politicalSystems[t.rawValue] }
}

/// How distances between systems are computed.
public enum DistanceRule: String, Codable, Sendable {
    /// C#: `floor(sqrt(dx² + dy²))`.
    case floor
    /// Palm: integer square root rounded to nearest (`Math.c:RealDistance`).
    case rounded
}

/// Behaviour switches (docs/specs/RUL.md). Grows milestone by milestone.
public struct RuleFlags: Sendable {
    public var distance: DistanceRule
    /// C#: shipyards may land on the same system; Modern (MOD-013) uses distinct systems.
    public var distinctShipyards: Bool
    /// C#: initial quantities read the hidden-until-visited resource (always `.nothing`); Modern (MOD-006) uses the true resource.
    public var resourcesAffectUnvisitedSystems: Bool
    /// MOD-001: reset the cargo cost basis whenever the hold is cleared (C# keeps it: infinite-money exploit).
    public var resetPriceCargoOnHoldClear: Bool
}

/// Large content differences (quest sets, shipyards, disruptors…).
public struct ContentPacks: Sendable {
    public var hasShipyards: Bool
    public var hasSculptureQuest: Bool
    public var hasPrincessQuest: Bool
    public var hasDisruptors: Bool
    public var hasHiddenBays: Bool
    /// Maximum hireable mercenaries waiting in one system.
    public var mercenariesPerSystem: Int
}

/// A complete ruleset.
public struct Ruleset: Sendable {
    public var id: RulesetID
    public var tables: RulesTables
    public var flags: RuleFlags
    public var content: ContentPacks
    public var rngKind: RNGKind

    public static func named(_ id: RulesetID) -> Ruleset {
        switch id {
        case .windows201: .windows201
        case .modern: .modern
        case .palm122: .palm122
        }
    }

    /// Windows 2.01: faithful to the C# port, quirks included.
    public static let windows201 = Ruleset(
        id: .windows201,
        tables: RulesTables(
            ships: Windows201Tables.ships, weapons: Windows201Tables.weapons, shields: Windows201Tables.shields,
            gadgets: Windows201Tables.gadgets, tradeItems: Windows201Tables.tradeItems,
            politicalSystems: Windows201Tables.politicalSystems, specialEvents: Windows201Tables.specialEvents,
            systemNames: GameNames.systems, galaxyWidth: 154, galaxyHeight: 110, minDistance: 7, closeDistance: 13,
            centralOffset: 13, startingCash: 1000),
        flags: RuleFlags(distance: .floor, distinctShipyards: false, resourcesAffectUnvisitedSystems: false,
                         resetPriceCargoOnHoldClear: false),
        content: ContentPacks(hasShipyards: true, hasSculptureQuest: true, hasPrincessQuest: true, hasDisruptors: true,
                              hasHiddenBays: true, mercenariesPerSystem: 3),
        rngKind: .dotNet)

    /// Modern (default): Windows 2.01 with the PRD §4.3 fixes. Remaining MOD flags land in M5.
    public static let modern: Ruleset = {
        var r = Ruleset.windows201
        r.id = .modern
        r.rngKind = .xoshiro
        r.flags.distinctShipyards = true
        r.flags.resourcesAffectUnvisitedSystems = true
        r.flags.resetPriceCargoOnHoldClear = true
        return r
    }()

    /// Original Palm 1.2.2. Content pack and flags are completed in M5; until then it reuses Windows data.
    public static let palm122: Ruleset = {
        var r = Ruleset.windows201
        r.id = .palm122
        r.rngKind = .palmLCG
        return r
    }()
}
