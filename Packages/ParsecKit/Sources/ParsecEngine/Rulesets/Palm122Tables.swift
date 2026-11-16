// SPDX-License-Identifier: GPL-2.0-or-later
// swiftlint:disable line_length
// Original Palm 1.2.2 content pack, transcribed from the Palm source (Src/Global.c tables, Src/spacetrader.h constants).
// docs/specs/RUL.md §1 and docs/specs/GAL.md are normative. Values are re-read in the source; do not hand-edit without
// citing Global.c.

public enum Palm122Tables {
    /// Global.c `Shiptype[]` (ships 0…14). Columns follow Palm: `CostOfFuel` → `fuelCost`, `RepairCosts` → `repairCost`.
    /// MOD-017 / RUL-117: these are the *Palm* columns (Gnat fuel 2, repair 1); the C# port swapped them, so this table
    /// already holds the restored values and must never be swapped again. Palm activity `-1` (never) and the special
    /// ships' `8` (above Swarms: never) both map to `.na`. The Custom (15) and Scorpion (16) rows do not exist in Palm;
    /// they are kept as unreachable placeholders so `ShipType` raw values index the table (no shipyards, no Scorpion).
    public static let ships: [ShipSpec] = [
        ShipSpec(.flea, .tiny, bays: 10, weapons: 0, shields: 0, gadgets: 0, crew: 1, fuel: 20, fuelCost: 1, hull: 25, repairCost: 1, price: 2000, occurrence: 2, police: .na, pirates: .na, traders: .absent, tech: .earlyIndustrial),
        ShipSpec(.gnat, .small, bays: 15, weapons: 1, shields: 0, gadgets: 1, crew: 1, fuel: 14, fuelCost: 2, hull: 100, repairCost: 1, price: 10000, occurrence: 28, police: .absent, pirates: .absent, traders: .absent, tech: .industrial),
        ShipSpec(.firefly, .small, bays: 20, weapons: 1, shields: 1, gadgets: 1, crew: 1, fuel: 17, fuelCost: 3, hull: 100, repairCost: 1, price: 25000, occurrence: 20, police: .absent, pirates: .absent, traders: .absent, tech: .industrial),
        ShipSpec(.mosquito, .small, bays: 15, weapons: 2, shields: 1, gadgets: 1, crew: 1, fuel: 13, fuelCost: 5, hull: 100, repairCost: 1, price: 30000, occurrence: 20, police: .absent, pirates: .minimal, traders: .absent, tech: .industrial),
        ShipSpec(.bumblebee, .medium, bays: 25, weapons: 1, shields: 2, gadgets: 2, crew: 2, fuel: 15, fuelCost: 7, hull: 100, repairCost: 1, price: 60000, occurrence: 15, police: .minimal, pirates: .minimal, traders: .absent, tech: .industrial),
        ShipSpec(.beetle, .medium, bays: 50, weapons: 0, shields: 1, gadgets: 1, crew: 3, fuel: 14, fuelCost: 10, hull: 50, repairCost: 1, price: 80000, occurrence: 3, police: .na, pirates: .na, traders: .absent, tech: .industrial),
        ShipSpec(.hornet, .large, bays: 20, weapons: 3, shields: 2, gadgets: 1, crew: 2, fuel: 16, fuelCost: 15, hull: 150, repairCost: 2, price: 100000, occurrence: 6, police: .few, pirates: .some, traders: .minimal, tech: .postIndustrial),
        ShipSpec(.grasshopper, .large, bays: 30, weapons: 2, shields: 2, gadgets: 3, crew: 3, fuel: 15, fuelCost: 15, hull: 150, repairCost: 3, price: 150000, occurrence: 2, police: .some, pirates: .moderate, traders: .few, tech: .postIndustrial),
        ShipSpec(.termite, .huge, bays: 60, weapons: 1, shields: 3, gadgets: 2, crew: 3, fuel: 13, fuelCost: 20, hull: 200, repairCost: 4, price: 225000, occurrence: 2, police: .moderate, pirates: .many, traders: .some, tech: .hiTech),
        ShipSpec(.wasp, .huge, bays: 35, weapons: 3, shields: 2, gadgets: 2, crew: 3, fuel: 14, fuelCost: 20, hull: 200, repairCost: 5, price: 300000, occurrence: 2, police: .many, pirates: .abundant, traders: .moderate, tech: .hiTech),
        ShipSpec(.spaceMonster, .huge, bays: 0, weapons: 3, shields: 0, gadgets: 0, crew: 1, fuel: 1, fuelCost: 1, hull: 500, repairCost: 1, price: 500000, occurrence: 0, police: .na, pirates: .na, traders: .na, tech: .unavailable),
        ShipSpec(.dragonfly, .small, bays: 0, weapons: 2, shields: 3, gadgets: 2, crew: 1, fuel: 1, fuelCost: 1, hull: 10, repairCost: 1, price: 500000, occurrence: 0, police: .na, pirates: .na, traders: .na, tech: .unavailable),
        ShipSpec(.mantis, .medium, bays: 0, weapons: 3, shields: 1, gadgets: 3, crew: 3, fuel: 1, fuelCost: 1, hull: 300, repairCost: 1, price: 500000, occurrence: 0, police: .na, pirates: .na, traders: .na, tech: .unavailable),
        ShipSpec(.scarab, .large, bays: 20, weapons: 2, shields: 0, gadgets: 0, crew: 2, fuel: 1, fuelCost: 1, hull: 400, repairCost: 1, price: 500000, occurrence: 0, police: .na, pirates: .na, traders: .na, tech: .unavailable),
        ShipSpec(.bottle, .small, bays: 0, weapons: 0, shields: 0, gadgets: 0, crew: 0, fuel: 1, fuelCost: 1, hull: 10, repairCost: 1, price: 100, occurrence: 0, police: .na, pirates: .na, traders: .na, tech: .unavailable),
        ShipSpec(.custom, .huge, bays: 0, weapons: 0, shields: 0, gadgets: 0, crew: 0, fuel: 0, fuelCost: 0, hull: 0, repairCost: 0, price: 0, occurrence: 0, police: .na, pirates: .na, traders: .na, tech: .unavailable),
        ShipSpec(.scorpion, .huge, bays: 30, weapons: 2, shields: 2, gadgets: 2, crew: 2, fuel: 1, fuelCost: 1, hull: 300, repairCost: 1, price: 500000, occurrence: 0, police: .na, pirates: .na, traders: .na, tech: .unavailable),
    ]

    /// Global.c `Weapontype[]`: Pulse, Beam, Military and Morgan's lasers only (`MAXWEAPONTYPE 3` + 1 extra). No
    /// disruptors (RUL-015): the table ends at Morgan's laser, so disruptor raw values are out of range by design.
    public static let weapons: [WeaponSpec] = [
        WeaponSpec(type: .pulseLaser, power: 15, disabling: false, price: 2000, minTechLevel: .industrial, chance: 50),
        WeaponSpec(type: .beamLaser, power: 25, disabling: false, price: 12500, minTechLevel: .postIndustrial, chance: 35),
        WeaponSpec(type: .militaryLaser, power: 35, disabling: false, price: 35000, minTechLevel: .hiTech, chance: 15),
        WeaponSpec(type: .morgansLaser, power: 85, disabling: false, price: 50000, minTechLevel: .unavailable, chance: 0),
    ]

    /// Global.c `Shieldtype[]`.
    public static let shields: [ShieldSpec] = [
        ShieldSpec(type: .energy, power: 100, price: 5000, minTechLevel: .industrial, chance: 70),
        ShieldSpec(type: .reflective, power: 200, price: 20000, minTechLevel: .postIndustrial, chance: 30),
        ShieldSpec(type: .lightning, power: 350, price: 45000, minTechLevel: .unavailable, chance: 0),
    ]

    /// Global.c `Gadgettype[]` (`MAXGADGETTYPE 5` + the fuel compactor). No hidden cargo bays (RUL-016).
    /// The skill each gadget boosts follows Src/Skill.c (the cloak's +2 pilot bonus size is RUL-048, an economy flag).
    public static let gadgets: [GadgetSpec] = [
        GadgetSpec(type: .extraCargoBays, skillBonus: nil, price: 2500, minTechLevel: .earlyIndustrial, chance: 35),
        GadgetSpec(type: .autoRepairSystem, skillBonus: .engineer, price: 7500, minTechLevel: .industrial, chance: 20),
        GadgetSpec(type: .navigatingSystem, skillBonus: .pilot, price: 15000, minTechLevel: .postIndustrial, chance: 20),
        GadgetSpec(type: .targetingSystem, skillBonus: .fighter, price: 25000, minTechLevel: .postIndustrial, chance: 20),
        GadgetSpec(type: .cloakingDevice, skillBonus: .pilot, price: 100000, minTechLevel: .hiTech, chance: 5),
        GadgetSpec(type: .fuelCompactor, skillBonus: nil, price: 30000, minTechLevel: .unavailable, chance: 0),
    ]

    /// Global.c `Tradeitem[]` (value-identical to the C# table).
    public static let tradeItems: [TradeItemSpec] = [
        TradeItemSpec(type: .water, techProduction: .preAgricultural, techUsage: .preAgricultural, techTopProduction: .medieval, priceLowTech: 30, priceIncrease: 3, variance: 4, pressurePriceHike: .drought, resourceLowPrice: .sweetOceans, resourceHighPrice: .desert, minTradePrice: 30, maxTradePrice: 50, roundOff: 1),
        TradeItemSpec(type: .furs, techProduction: .preAgricultural, techUsage: .preAgricultural, techTopProduction: .preAgricultural, priceLowTech: 250, priceIncrease: 10, variance: 10, pressurePriceHike: .cold, resourceLowPrice: .richFauna, resourceHighPrice: .lifeless, minTradePrice: 230, maxTradePrice: 280, roundOff: 5),
        TradeItemSpec(type: .food, techProduction: .agricultural, techUsage: .preAgricultural, techTopProduction: .agricultural, priceLowTech: 100, priceIncrease: 5, variance: 5, pressurePriceHike: .cropFailure, resourceLowPrice: .richSoil, resourceHighPrice: .poorSoil, minTradePrice: 90, maxTradePrice: 160, roundOff: 5),
        TradeItemSpec(type: .ore, techProduction: .medieval, techUsage: .medieval, techTopProduction: .renaissance, priceLowTech: 350, priceIncrease: 20, variance: 10, pressurePriceHike: .war, resourceLowPrice: .mineralRich, resourceHighPrice: .mineralPoor, minTradePrice: 350, maxTradePrice: 420, roundOff: 10),
        TradeItemSpec(type: .games, techProduction: .renaissance, techUsage: .agricultural, techTopProduction: .postIndustrial, priceLowTech: 250, priceIncrease: -10, variance: 5, pressurePriceHike: .boredom, resourceLowPrice: .artistic, resourceHighPrice: nil, minTradePrice: 160, maxTradePrice: 270, roundOff: 5),
        TradeItemSpec(type: .firearms, techProduction: .renaissance, techUsage: .agricultural, techTopProduction: .industrial, priceLowTech: 1250, priceIncrease: -75, variance: 100, pressurePriceHike: .war, resourceLowPrice: .warlike, resourceHighPrice: nil, minTradePrice: 600, maxTradePrice: 1100, roundOff: 25),
        TradeItemSpec(type: .medicine, techProduction: .earlyIndustrial, techUsage: .agricultural, techTopProduction: .postIndustrial, priceLowTech: 650, priceIncrease: -20, variance: 10, pressurePriceHike: .plague, resourceLowPrice: .specialHerbs, resourceHighPrice: nil, minTradePrice: 400, maxTradePrice: 700, roundOff: 25),
        TradeItemSpec(type: .machines, techProduction: .earlyIndustrial, techUsage: .renaissance, techTopProduction: .industrial, priceLowTech: 900, priceIncrease: -30, variance: 5, pressurePriceHike: .employment, resourceLowPrice: nil, resourceHighPrice: nil, minTradePrice: 600, maxTradePrice: 800, roundOff: 25),
        TradeItemSpec(type: .narcotics, techProduction: .industrial, techUsage: .preAgricultural, techTopProduction: .industrial, priceLowTech: 3500, priceIncrease: -125, variance: 150, pressurePriceHike: .boredom, resourceLowPrice: .weirdMushrooms, resourceHighPrice: nil, minTradePrice: 2000, maxTradePrice: 3000, roundOff: 50),
        TradeItemSpec(type: .robots, techProduction: .postIndustrial, techUsage: .earlyIndustrial, techTopProduction: .hiTech, priceLowTech: 5000, priceIncrease: -150, variance: 100, pressurePriceHike: .employment, resourceLowPrice: nil, resourceHighPrice: nil, minTradePrice: 3500, maxTradePrice: 5000, roundOff: 100),
    ]

    /// Global.c `Politics[]` (value-identical to the C# table; Palm writes "none wanted" as `-1`).
    public static let politicalSystems: [PoliticalSystemSpec] = [
        PoliticalSystemSpec(type: .anarchy, reactionIllegal: 0, activityPolice: .absent, activityPirates: .swarms, activityTraders: .minimal, minTech: .preAgricultural, maxTech: .industrial, bribeLevel: 7, drugsOK: true, firearmsOK: true, wanted: .food),
        PoliticalSystemSpec(type: .capitalist, reactionIllegal: 2, activityPolice: .some, activityPirates: .few, activityTraders: .swarms, minTech: .earlyIndustrial, maxTech: .hiTech, bribeLevel: 1, drugsOK: true, firearmsOK: true, wanted: .ore),
        PoliticalSystemSpec(type: .communist, reactionIllegal: 6, activityPolice: .abundant, activityPirates: .moderate, activityTraders: .moderate, minTech: .agricultural, maxTech: .industrial, bribeLevel: 5, drugsOK: true, firearmsOK: true, wanted: nil),
        PoliticalSystemSpec(type: .confederacy, reactionIllegal: 5, activityPolice: .moderate, activityPirates: .some, activityTraders: .many, minTech: .agricultural, maxTech: .postIndustrial, bribeLevel: 3, drugsOK: true, firearmsOK: true, wanted: .games),
        PoliticalSystemSpec(type: .corporate, reactionIllegal: 2, activityPolice: .abundant, activityPirates: .few, activityTraders: .swarms, minTech: .earlyIndustrial, maxTech: .hiTech, bribeLevel: 2, drugsOK: true, firearmsOK: true, wanted: .robots),
        PoliticalSystemSpec(type: .cybernetic, reactionIllegal: 0, activityPolice: .swarms, activityPirates: .swarms, activityTraders: .many, minTech: .postIndustrial, maxTech: .hiTech, bribeLevel: 0, drugsOK: false, firearmsOK: false, wanted: .ore),
        PoliticalSystemSpec(type: .democracy, reactionIllegal: 4, activityPolice: .some, activityPirates: .few, activityTraders: .many, minTech: .renaissance, maxTech: .hiTech, bribeLevel: 2, drugsOK: true, firearmsOK: true, wanted: .games),
        PoliticalSystemSpec(type: .dictatorship, reactionIllegal: 3, activityPolice: .moderate, activityPirates: .many, activityTraders: .some, minTech: .preAgricultural, maxTech: .hiTech, bribeLevel: 2, drugsOK: true, firearmsOK: true, wanted: nil),
        PoliticalSystemSpec(type: .fascist, reactionIllegal: 7, activityPolice: .swarms, activityPirates: .swarms, activityTraders: .minimal, minTech: .earlyIndustrial, maxTech: .hiTech, bribeLevel: 0, drugsOK: false, firearmsOK: true, wanted: .machines),
        PoliticalSystemSpec(type: .feudal, reactionIllegal: 1, activityPolice: .minimal, activityPirates: .abundant, activityTraders: .few, minTech: .preAgricultural, maxTech: .renaissance, bribeLevel: 6, drugsOK: true, firearmsOK: true, wanted: .firearms),
        PoliticalSystemSpec(type: .military, reactionIllegal: 7, activityPolice: .swarms, activityPirates: .absent, activityTraders: .abundant, minTech: .medieval, maxTech: .hiTech, bribeLevel: 0, drugsOK: false, firearmsOK: true, wanted: .robots),
        PoliticalSystemSpec(type: .monarchy, reactionIllegal: 3, activityPolice: .moderate, activityPirates: .some, activityTraders: .moderate, minTech: .preAgricultural, maxTech: .industrial, bribeLevel: 4, drugsOK: true, firearmsOK: true, wanted: .medicine),
        PoliticalSystemSpec(type: .pacifist, reactionIllegal: 7, activityPolice: .few, activityPirates: .minimal, activityTraders: .many, minTech: .preAgricultural, maxTech: .renaissance, bribeLevel: 1, drugsOK: true, firearmsOK: false, wanted: nil),
        PoliticalSystemSpec(type: .socialist, reactionIllegal: 4, activityPolice: .few, activityPirates: .many, activityTraders: .some, minTech: .preAgricultural, maxTech: .industrial, bribeLevel: 6, drugsOK: true, firearmsOK: true, wanted: nil),
        PoliticalSystemSpec(type: .satori, reactionIllegal: 0, activityPolice: .minimal, activityPirates: .minimal, activityTraders: .minimal, minTech: .preAgricultural, maxTech: .agricultural, bribeLevel: 0, drugsOK: false, firearmsOK: false, wanted: nil),
        PoliticalSystemSpec(type: .technocracy, reactionIllegal: 1, activityPolice: .abundant, activityPirates: .some, activityTraders: .abundant, minTech: .earlyIndustrial, maxTech: .hiTech, bribeLevel: 2, drugsOK: true, firearmsOK: true, wanted: .water),
        PoliticalSystemSpec(type: .theocracy, reactionIllegal: 5, activityPolice: .abundant, activityPirates: .minimal, activityTraders: .moderate, minTech: .preAgricultural, maxTech: .earlyIndustrial, bribeLevel: 0, drugsOK: true, firearmsOK: true, wanted: .narcotics),
    ]

    /// Global.c `SpecialEvent[MAXSPECIALEVENT]`: 37 entries in Palm index order (spacetrader.h:237-276). Indices 0…6 and
    /// 30…36 are fixed (`ENDFIXED 7`), 7…29 are placed randomly. Every Palm event maps onto the C# event type with the
    /// same meaning, so the app shows the C# title and text (PRD §4.4, RUL-005).
    public static let specialEvents: [SpecialEventSpec] = [
        SpecialEventSpec(type: .dragonflyDestroyed, price: 0, occurrence: 0, messageOnly: true),      // 0 DRAGONFLYDESTROYED
        SpecialEventSpec(type: .dragonflyBaratas, price: 0, occurrence: 0, messageOnly: true),        // 1 FLYBARATAS
        SpecialEventSpec(type: .dragonflyMelina, price: 0, occurrence: 0, messageOnly: true),         // 2 FLYMELINA
        SpecialEventSpec(type: .dragonflyRegulas, price: 0, occurrence: 0, messageOnly: true),        // 3 FLYREGULAS
        SpecialEventSpec(type: .spaceMonsterKilled, price: -15000, occurrence: 0, messageOnly: true), // 4 MONSTERKILLED
        SpecialEventSpec(type: .japoriDelivery, price: 0, occurrence: 0, messageOnly: true),          // 5 MEDICINEDELIVERY
        SpecialEventSpec(type: .moonRetirement, price: 0, occurrence: 0, messageOnly: false),         // 6 MOONBOUGHT
        SpecialEventSpec(type: .moon, price: 500000, occurrence: 4, messageOnly: false),              // 7 MOONFORSALE
        SpecialEventSpec(type: .skill, price: 3000, occurrence: 3, messageOnly: false),               // 8 SKILLINCREASE
        SpecialEventSpec(type: .tribble, price: 1000, occurrence: 1, messageOnly: false),             // 9 TRIBBLE
        SpecialEventSpec(type: .eraseRecord, price: 5000, occurrence: 3, messageOnly: false),         // 10 ERASERECORD
        SpecialEventSpec(type: .tribbleBuyer, price: 0, occurrence: 3, messageOnly: false),           // 11 BUYTRIBBLE
        SpecialEventSpec(type: .spaceMonster, price: 0, occurrence: 1, messageOnly: true),            // 12 SPACEMONSTER
        SpecialEventSpec(type: .dragonfly, price: 0, occurrence: 1, messageOnly: true),               // 13 DRAGONFLY
        SpecialEventSpec(type: .cargoForSale, price: 1000, occurrence: 3, messageOnly: false),        // 14 CARGOFORSALE
        SpecialEventSpec(type: .dragonflyShield, price: 0, occurrence: 0, messageOnly: false),        // 15 INSTALLLIGHTNINGSHIELD
        SpecialEventSpec(type: .japori, price: 0, occurrence: 1, messageOnly: false),                 // 16 JAPORIDISEASE
        SpecialEventSpec(type: .lottery, price: -1000, occurrence: 0, messageOnly: true),             // 17 LOTTERYWINNER
        SpecialEventSpec(type: .artifactDelivery, price: -20000, occurrence: 0, messageOnly: true),   // 18 ARTIFACTDELIVERY
        SpecialEventSpec(type: .artifact, price: 0, occurrence: 1, messageOnly: false),               // 19 ALIENARTIFACT
        SpecialEventSpec(type: .jarek, price: 0, occurrence: 1, messageOnly: false),                  // 20 AMBASSADORJAREK
        SpecialEventSpec(type: .gemulon, price: 0, occurrence: 0, messageOnly: true),                 // 21 ALIENINVASION
        SpecialEventSpec(type: .gemulonInvaded, price: 0, occurrence: 0, messageOnly: true),          // 22 GEMULONINVADED
        SpecialEventSpec(type: .gemulonFuel, price: 0, occurrence: 0, messageOnly: false),            // 23 GETFUELCOMPACTOR
        SpecialEventSpec(type: .experiment, price: 0, occurrence: 0, messageOnly: true),              // 24 EXPERIMENT
        SpecialEventSpec(type: .wild, price: 0, occurrence: 1, messageOnly: false),                   // 25 TRANSPORTWILD
        SpecialEventSpec(type: .reactor, price: 0, occurrence: 0, messageOnly: false),                // 26 GETREACTOR
        SpecialEventSpec(type: .reactorLaser, price: 0, occurrence: 0, messageOnly: false),           // 27 GETSPECIALLASER
        SpecialEventSpec(type: .scarab, price: 0, occurrence: 1, messageOnly: true),                  // 28 SCARAB
        SpecialEventSpec(type: .scarabUpgradeHull, price: 0, occurrence: 0, messageOnly: false),      // 29 GETHULLUPGRADED
        SpecialEventSpec(type: .scarabDestroyed, price: 0, occurrence: 0, messageOnly: true),         // 30 SCARABDESTROYED
        SpecialEventSpec(type: .reactorDelivered, price: 0, occurrence: 0, messageOnly: true),        // 31 REACTORDELIVERED
        SpecialEventSpec(type: .jarekGetsOut, price: 0, occurrence: 0, messageOnly: true),            // 32 JAREKGETSOUT
        SpecialEventSpec(type: .gemulonRescued, price: 0, occurrence: 0, messageOnly: true),          // 33 GEMULONRESCUED
        SpecialEventSpec(type: .experimentStopped, price: 0, occurrence: 0, messageOnly: true),       // 34 EXPERIMENTSTOPPED
        SpecialEventSpec(type: .experimentFailed, price: 0, occurrence: 0, messageOnly: true),        // 35 EXPERIMENTNOTSTOPPED
        SpecialEventSpec(type: .wildGetsOut, price: 0, occurrence: 0, messageOnly: true),             // 36 WILDGETSOUT
    ]

    /// Traveler.c:StartNewGame fixed placements (assigned first, no draws). The quest end-points ReactorDelivered,
    /// GemulonRescued and ExperimentStopped are not fixed in Palm: they are set only when their distant placement succeeds.
    public static let fixedSpecialEvents: [FixedSpecialEvent] = [
        FixedSpecialEvent(system: SystemID.acamar, event: .spaceMonsterKilled),
        FixedSpecialEvent(system: SystemID.baratas, event: .dragonflyBaratas),
        FixedSpecialEvent(system: SystemID.melina, event: .dragonflyMelina),
        FixedSpecialEvent(system: SystemID.regulas, event: .dragonflyRegulas),
        FixedSpecialEvent(system: SystemID.zalkon, event: .dragonflyDestroyed),
        FixedSpecialEvent(system: SystemID.japori, event: .japoriDelivery),
        FixedSpecialEvent(system: SystemID.utopia, event: .moonRetirement),
        FixedSpecialEvent(system: SystemID.devidia, event: .jarekGetsOut),
        FixedSpecialEvent(system: SystemID.kravat, event: .wildGetsOut),
    ]

    /// Global.c `SolarSystemName[MAXSOLARSYSTEM]`: 120 names, identical to C# ids 0…119.
    public static let systemNames: [String] = [
        "Acamar", "Adahn", "Aldea", "Andevian", "Antedi", "Balosnee", "Baratas", "Brax", "Bretel", "Calondia",
        "Campor", "Capelle", "Carzon", "Castor", "Cestus", "Cheron", "Courteney", "Daled", "Damast", "Davlos",
        "Deneb", "Deneva", "Devidia", "Draylon", "Drema", "Endor", "Esmee", "Exo", "Ferris", "Festen", "Fourmi",
        "Frolix", "Gemulon", "Guinifer", "Hades", "Hamlet", "Helena", "Hulst", "Iodine", "Iralius", "Janus",
        "Japori", "Jarada", "Jason", "Kaylon", "Khefka", "Kira", "Klaatu", "Klaestron", "Korma", "Kravat", "Krios",
        "Laertes", "Largo", "Lave", "Ligon", "Lowry", "Magrat", "Malcoria", "Melina", "Mentar", "Merik", "Mintaka",
        "Montor", "Mordan", "Myrthe", "Nelvana", "Nix", "Nyle", "Odet", "Og", "Omega", "Omphalos", "Orias",
        "Othello", "Parade", "Penthara", "Picard", "Pollux", "Quator", "Rakhar", "Ran", "Regulas", "Relva", "Rhymus",
        "Rochani", "Rubicum", "Rutia", "Sarpeidon", "Sefalla", "Seltrice", "Sigma", "Sol", "Somari", "Stakoron",
        "Styris", "Talani", "Tamus", "Tantalos", "Tanuga", "Tarchannen", "Terosa", "Thera", "Titan", "Torin",
        "Triacus", "Turkana", "Tyrus", "Umberlee", "Utopia", "Vadera", "Vagra", "Vandor", "Ventax", "Xenon",
        "Xerxes", "Yew", "Yojimbo", "Zalkon", "Zuul",
    ]
}
