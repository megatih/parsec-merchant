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
    /// Special-event table in the content pack's own index order (C# 46 events; Palm 37 entries).
    public var specialEvents: [SpecialEventSpec]
    /// Events assigned to fixed systems before any random placement.
    public var fixedSpecialEvents: [FixedSpecialEvent]
    public var systemNames: [String]
    public var galaxyWidth: Int
    public var galaxyHeight: Int
    /// Minimum spacing during generation (C# `MinDistance 7`, Palm `MINDISTANCE 6`); see `GalaxyRules.minDistanceTest`.
    public var minDistance: Int
    /// Each new system needs a neighbour closer than this.
    public var closeDistance: Int
    /// Offset range for the six central (wormhole) systems; see `GalaxyRules.centreOffsetRoll` (C# 13, Palm 6).
    public var centralOffset: Int
    public var startingCash: Int

    public func ship(_ t: ShipType) -> ShipSpec { ships[t.rawValue] }
    public func weapon(_ t: WeaponType) -> WeaponSpec { weapons[t.rawValue] }
    public func shield(_ t: ShieldType) -> ShieldSpec { shields[t.rawValue] }
    public func gadget(_ t: GadgetType) -> GadgetSpec { gadgets[t.rawValue] }
    public func item(_ t: TradeItemType) -> TradeItemSpec { tradeItems[t.rawValue] }
    public func politics(_ t: PoliticalSystemType) -> PoliticalSystemSpec { politicalSystems[t.rawValue] }
    /// False when the content pack has no such weapon (Palm: disruptors, RUL-015).
    public func contains(_ t: WeaponType) -> Bool { t.rawValue < weapons.count }
    /// False when the content pack has no such gadget (Palm: hidden cargo bays, RUL-016).
    public func contains(_ t: GadgetType) -> Bool { t.rawValue < gadgets.count }
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
    /// MOD-007: restock drift tests each system's own `ItemTraded` (C# tests the arrival system: ECO-037).
    public var restockUsesOwnSystemItemTraded: Bool
    /// MOD-008: in-orbit purchases are capped using the in-orbit price (C# uses the system price: ECO-068).
    public var tradeInOrbitCashCapUsesOrbitPrice: Bool
    /// MOD-005: random skill increases can reach 10 (C# stops at 9: CRW-052).
    public var randomSkillIncreaseReachesTen: Bool
    /// MOD-020: the Wasp can be a random opponent (C# weights only ships 0…8).
    public var waspOpponentReachable: Bool
    /// MOD-009: the Kravat/Wild engineer boost checks Wild aboard the player's ship (C# checks the opponent: never true).
    public var kravatEngineerChecksPlayerWild: Bool
    /// MOD-014: the reactor damage multiplier is a real factor (C# truncates it to an integer: CMB).
    public var reactorDamageRealFactor: Bool
    /// MOD-004: the hardened (Scarab) hull halves damage to the player only (C# halves it for any defender).
    public var hardenedHullProtectsPlayerOnly: Bool
    /// Palm credits pirate bounties regardless of police record (C# only at record ≥ −5).
    public var bountyCreditedRegardlessOfRecord: Bool
    /// MOD-010: the Marie Celeste exclusion tests the destination (C# tests the departure system).
    public var marieCelesteChecksDestination: Bool
    /// MOD-002: the arrest fine never goes negative (C# can pay a commander with a positive record).
    public var arrestFineNeverNegative: Bool
    /// MOD-012 (RUL-112): pirate looting clamps the hidden-bay protection (C# `RemoveRange` throws: POL-080).
    public var pirateLootHiddenBaysClamp = false
    /// Area rule groups (M5). Each preset lives in its own file (GalaxyRules.swift, EconomyRules.swift, …).
    public var galaxy: GalaxyRules = .windows201
    public var economy: EconomyRules = .windows201
    public var travel: TravelRules = .windows201
    public var encounter: EncounterRules = .windows201
    public var quest: QuestRules = .windows201
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
    /// Crew ids that get a random system and four random skills, generated in this (ascending) order
    /// (C# 1…29 and 38…52; Palm 1…31, `MAXCREWMEMBER` inclusive).
    public var randomMercenaryIDs: [Int]
    /// Mercenary slots pre-counted at Kravat before generation (C# 1 → at most 2 there; Palm 1 with a cap of 1 → none).
    public var kravatMercenaryPreCount: Int
    /// Ids whose drawn system is cleared after generation: Palm Zeethibal (30, `CurSystem = 255`) and the opponent
    /// scratch slot (31, never hireable).
    public var unplacedMercenaryIDs: [Int]
    /// RUL-006: the cosmetic "moon-girl" ending after the Princess quest (Modern only; score equals the moon score).
    public var hasMoonGirlEnding = false
}

/// A complete ruleset.
public struct Ruleset: Sendable {
    public var id: RulesetID
    public var tables: RulesTables
    public var flags: RuleFlags
    public var content: ContentPacks
    public var rngKind: RNGKind
    /// Newspaper generator variant (RNG-002): C# for Windows 2.01 and Modern, Palm for Palm 1.2.2.
    public var newspaperRNG: PieterRand.Variant

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
            fixedSpecialEvents: Windows201Tables.fixedSpecialEvents, systemNames: GameNames.systems,
            galaxyWidth: 154, galaxyHeight: 110, minDistance: 7, closeDistance: 13, centralOffset: 13, startingCash: 1000),
        flags: RuleFlags(distance: .floor, distinctShipyards: false, resourcesAffectUnvisitedSystems: false,
                         resetPriceCargoOnHoldClear: false, restockUsesOwnSystemItemTraded: false,
                         tradeInOrbitCashCapUsesOrbitPrice: false, randomSkillIncreaseReachesTen: false,
                         waspOpponentReachable: false, kravatEngineerChecksPlayerWild: false,
                         reactorDamageRealFactor: false, hardenedHullProtectsPlayerOnly: false,
                         bountyCreditedRegardlessOfRecord: false, marieCelesteChecksDestination: false,
                         arrestFineNeverNegative: false),
        content: ContentPacks(hasShipyards: true, hasSculptureQuest: true, hasPrincessQuest: true, hasDisruptors: true,
                              hasHiddenBays: true, mercenariesPerSystem: 3,
                              randomMercenaryIDs: Array(1...29) + Array(38...52), kravatMercenaryPreCount: 1,
                              unplacedMercenaryIDs: []),
        rngKind: .dotNet, newspaperRNG: .csharp)

    /// Modern (default): Windows 2.01 with the PRD §4.3 fixes. Remaining MOD flags land in M5.
    public static let modern: Ruleset = {
        var r = Ruleset.windows201
        r.id = .modern
        r.rngKind = .xoshiro
        r.flags.distinctShipyards = true
        r.flags.resourcesAffectUnvisitedSystems = true
        r.flags.resetPriceCargoOnHoldClear = true
        r.flags.restockUsesOwnSystemItemTraded = true
        r.flags.tradeInOrbitCashCapUsesOrbitPrice = true
        r.flags.randomSkillIncreaseReachesTen = true
        r.flags.waspOpponentReachable = true
        r.flags.kravatEngineerChecksPlayerWild = true
        r.flags.reactorDamageRealFactor = true
        r.flags.hardenedHullProtectsPlayerOnly = true
        r.flags.marieCelesteChecksDestination = true
        r.flags.arrestFineNeverNegative = true
        r.flags.pirateLootHiddenBaysClamp = true
        r.content.hasMoonGirlEnding = true
        r.flags.galaxy = .modern
        r.flags.economy = .modern
        r.flags.travel = .modern
        r.flags.encounter = .modern
        r.flags.quest = .modern
        return r
    }()

    /// Original Palm 1.2.2: the Palm content pack (Palm122Tables) and Palm behaviour flags.
    public static let palm122: Ruleset = {
        var r = Ruleset.windows201
        r.id = .palm122
        r.rngKind = .palmLCG
        r.newspaperRNG = .palm
        r.tables = RulesTables(
            ships: Palm122Tables.ships, weapons: Palm122Tables.weapons, shields: Palm122Tables.shields,
            gadgets: Palm122Tables.gadgets, tradeItems: Palm122Tables.tradeItems,
            politicalSystems: Palm122Tables.politicalSystems, specialEvents: Palm122Tables.specialEvents,
            fixedSpecialEvents: Palm122Tables.fixedSpecialEvents, systemNames: Palm122Tables.systemNames,
            galaxyWidth: 150, galaxyHeight: 110, minDistance: 6, closeDistance: 13, centralOffset: 6, startingCash: 1000)
        r.content = ContentPacks(hasShipyards: false, hasSculptureQuest: false, hasPrincessQuest: false,
                                 hasDisruptors: false, hasHiddenBays: false, mercenariesPerSystem: 1,
                                 randomMercenaryIDs: Array(1...31), kravatMercenaryPreCount: 1,
                                 unplacedMercenaryIDs: [CrewID.zeethibal, CrewID.opponent])
        r.flags.distance = .rounded
        r.flags.galaxy = .palm122
        r.flags.economy = .palm122
        r.flags.travel = .palm122
        r.flags.encounter = .palm122
        r.flags.quest = .palm122
        return r
    }()
}
