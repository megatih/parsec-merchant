// SPDX-License-Identifier: GPL-2.0-or-later
// swiftlint:disable line_length
// GENERATED from SpaceTraderSource201/Consts.cs by a one-off script (M1). Windows 2.01 data tables.
// Do not hand-edit values without citing Consts.cs; fixes for other rulesets live in their own tables.

public enum Windows201Tables {
    /// Consts.cs:249-267 ShipSpecs. Note: C# fuelCost/repairCost are swapped relative to Palm (PRD MOD-017).
    public static let ships: [ShipSpec] = [
        ShipSpec(.flea, .tiny, bays: 10, weapons: 0, shields: 0, gadgets: 0, crew: 1, fuel: 20, fuelCost: 1, hull: 25, repairCost: 1, price: 2000, occurrence: 2, police: .na, pirates: .na, traders: .absent, tech: .earlyIndustrial),
        ShipSpec(.gnat, .small, bays: 15, weapons: 1, shields: 0, gadgets: 1, crew: 1, fuel: 14, fuelCost: 1, hull: 100, repairCost: 2, price: 10000, occurrence: 28, police: .absent, pirates: .absent, traders: .absent, tech: .industrial),
        ShipSpec(.firefly, .small, bays: 20, weapons: 1, shields: 1, gadgets: 1, crew: 1, fuel: 17, fuelCost: 1, hull: 100, repairCost: 3, price: 25000, occurrence: 20, police: .absent, pirates: .absent, traders: .absent, tech: .industrial),
        ShipSpec(.mosquito, .small, bays: 15, weapons: 2, shields: 1, gadgets: 1, crew: 1, fuel: 13, fuelCost: 1, hull: 100, repairCost: 5, price: 30000, occurrence: 20, police: .absent, pirates: .minimal, traders: .absent, tech: .industrial),
        ShipSpec(.bumblebee, .medium, bays: 25, weapons: 1, shields: 2, gadgets: 2, crew: 2, fuel: 15, fuelCost: 1, hull: 100, repairCost: 7, price: 60000, occurrence: 15, police: .minimal, pirates: .minimal, traders: .absent, tech: .industrial),
        ShipSpec(.beetle, .medium, bays: 50, weapons: 0, shields: 1, gadgets: 1, crew: 3, fuel: 14, fuelCost: 1, hull: 50, repairCost: 10, price: 80000, occurrence: 3, police: .na, pirates: .na, traders: .absent, tech: .industrial),
        ShipSpec(.hornet, .large, bays: 20, weapons: 3, shields: 2, gadgets: 1, crew: 2, fuel: 16, fuelCost: 2, hull: 150, repairCost: 15, price: 100000, occurrence: 6, police: .few, pirates: .some, traders: .minimal, tech: .postIndustrial),
        ShipSpec(.grasshopper, .large, bays: 30, weapons: 2, shields: 2, gadgets: 3, crew: 3, fuel: 15, fuelCost: 3, hull: 150, repairCost: 15, price: 150000, occurrence: 2, police: .some, pirates: .moderate, traders: .few, tech: .postIndustrial),
        ShipSpec(.termite, .huge, bays: 60, weapons: 1, shields: 3, gadgets: 2, crew: 3, fuel: 13, fuelCost: 4, hull: 200, repairCost: 20, price: 225000, occurrence: 2, police: .moderate, pirates: .many, traders: .some, tech: .hiTech),
        ShipSpec(.wasp, .huge, bays: 35, weapons: 3, shields: 2, gadgets: 2, crew: 3, fuel: 14, fuelCost: 5, hull: 200, repairCost: 20, price: 300000, occurrence: 2, police: .many, pirates: .abundant, traders: .moderate, tech: .hiTech),
        ShipSpec(.spaceMonster, .huge, bays: 0, weapons: 3, shields: 0, gadgets: 0, crew: 1, fuel: 1, fuelCost: 1, hull: 500, repairCost: 1, price: 500000, occurrence: 0, police: .na, pirates: .na, traders: .na, tech: .unavailable),
        ShipSpec(.dragonfly, .small, bays: 0, weapons: 2, shields: 3, gadgets: 2, crew: 1, fuel: 1, fuelCost: 1, hull: 10, repairCost: 1, price: 500000, occurrence: 0, police: .na, pirates: .na, traders: .na, tech: .unavailable),
        ShipSpec(.mantis, .medium, bays: 0, weapons: 3, shields: 1, gadgets: 3, crew: 3, fuel: 1, fuelCost: 1, hull: 300, repairCost: 1, price: 500000, occurrence: 0, police: .na, pirates: .na, traders: .na, tech: .unavailable),
        ShipSpec(.scarab, .large, bays: 20, weapons: 2, shields: 0, gadgets: 0, crew: 2, fuel: 1, fuelCost: 1, hull: 400, repairCost: 1, price: 500000, occurrence: 0, police: .na, pirates: .na, traders: .na, tech: .unavailable),
        ShipSpec(.bottle, .small, bays: 0, weapons: 0, shields: 0, gadgets: 0, crew: 0, fuel: 1, fuelCost: 1, hull: 10, repairCost: 1, price: 100, occurrence: 0, police: .na, pirates: .na, traders: .na, tech: .unavailable),
        ShipSpec(.custom, .huge, bays: 0, weapons: 0, shields: 0, gadgets: 0, crew: 0, fuel: 0, fuelCost: 0, hull: 0, repairCost: 0, price: 0, occurrence: 0, police: .na, pirates: .na, traders: .na, tech: .unavailable),
        ShipSpec(.scorpion, .huge, bays: 30, weapons: 2, shields: 2, gadgets: 2, crew: 2, fuel: 1, fuelCost: 1, hull: 300, repairCost: 1, price: 500000, occurrence: 0, police: .na, pirates: .na, traders: .na, tech: .unavailable),
    ]

    /// Consts.cs Weapons.
    public static let weapons: [WeaponSpec] = [
        WeaponSpec(type: .pulseLaser, power: 15, disabling: false, price: 2000, minTechLevel: .industrial, chance: 50),
        WeaponSpec(type: .beamLaser, power: 25, disabling: false, price: 12500, minTechLevel: .postIndustrial, chance: 35),
        WeaponSpec(type: .militaryLaser, power: 35, disabling: false, price: 35000, minTechLevel: .hiTech, chance: 15),
        WeaponSpec(type: .morgansLaser, power: 85, disabling: false, price: 50000, minTechLevel: .unavailable, chance: 0),
        WeaponSpec(type: .photonDisruptor, power: 20, disabling: true, price: 15000, minTechLevel: .postIndustrial, chance: 0),
        WeaponSpec(type: .quantumDisruptor, power: 60, disabling: true, price: 50000, minTechLevel: .unavailable, chance: 0),
    ]

    /// Consts.cs Shields.
    public static let shields: [ShieldSpec] = [
        ShieldSpec(type: .energy, power: 100, price: 5000, minTechLevel: .industrial, chance: 70),
        ShieldSpec(type: .reflective, power: 200, price: 20000, minTechLevel: .postIndustrial, chance: 30),
        ShieldSpec(type: .lightning, power: 350, price: 45000, minTechLevel: .unavailable, chance: 0),
    ]

    /// Consts.cs Gadgets (SkillBonus is +3 per gadget; the cloak boosts Pilot).
    public static let gadgets: [GadgetSpec] = [
        GadgetSpec(type: .extraCargoBays, skillBonus: nil, price: 2500, minTechLevel: .earlyIndustrial, chance: 35),
        GadgetSpec(type: .autoRepairSystem, skillBonus: .engineer, price: 7500, minTechLevel: .industrial, chance: 20),
        GadgetSpec(type: .navigatingSystem, skillBonus: .pilot, price: 15000, minTechLevel: .postIndustrial, chance: 20),
        GadgetSpec(type: .targetingSystem, skillBonus: .fighter, price: 25000, minTechLevel: .postIndustrial, chance: 20),
        GadgetSpec(type: .cloakingDevice, skillBonus: .pilot, price: 100000, minTechLevel: .hiTech, chance: 5),
        GadgetSpec(type: .fuelCompactor, skillBonus: nil, price: 30000, minTechLevel: .unavailable, chance: 0),
        GadgetSpec(type: .hiddenCargoBays, skillBonus: nil, price: 60000, minTechLevel: .unavailable, chance: 0),
    ]

    /// Consts.cs TradeItems.
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

    /// Consts.cs PoliticalSystems.
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

    /// Consts.cs SpecialEvents (price, occurrence, message-only).
    public static let specialEvents: [SpecialEventSpec] = [
        SpecialEventSpec(type: .artifact, price: 0, occurrence: 1, messageOnly: false),
        SpecialEventSpec(type: .artifactDelivery, price: -20000, occurrence: 0, messageOnly: true),
        SpecialEventSpec(type: .cargoForSale, price: 1000, occurrence: 3, messageOnly: false),
        SpecialEventSpec(type: .dragonfly, price: 0, occurrence: 1, messageOnly: true),
        SpecialEventSpec(type: .dragonflyBaratas, price: 0, occurrence: 0, messageOnly: true),
        SpecialEventSpec(type: .dragonflyDestroyed, price: 0, occurrence: 0, messageOnly: true),
        SpecialEventSpec(type: .dragonflyMelina, price: 0, occurrence: 0, messageOnly: true),
        SpecialEventSpec(type: .dragonflyRegulas, price: 0, occurrence: 0, messageOnly: true),
        SpecialEventSpec(type: .dragonflyShield, price: 0, occurrence: 0, messageOnly: false),
        SpecialEventSpec(type: .eraseRecord, price: 5000, occurrence: 3, messageOnly: false),
        SpecialEventSpec(type: .experiment, price: 0, occurrence: 0, messageOnly: true),
        SpecialEventSpec(type: .experimentFailed, price: 0, occurrence: 0, messageOnly: true),
        SpecialEventSpec(type: .experimentStopped, price: 0, occurrence: 0, messageOnly: true),
        SpecialEventSpec(type: .gemulon, price: 0, occurrence: 0, messageOnly: true),
        SpecialEventSpec(type: .gemulonFuel, price: 0, occurrence: 0, messageOnly: false),
        SpecialEventSpec(type: .gemulonInvaded, price: 0, occurrence: 0, messageOnly: true),
        SpecialEventSpec(type: .gemulonRescued, price: 0, occurrence: 0, messageOnly: true),
        SpecialEventSpec(type: .japori, price: 0, occurrence: 1, messageOnly: false),
        SpecialEventSpec(type: .japoriDelivery, price: 0, occurrence: 0, messageOnly: true),
        SpecialEventSpec(type: .jarek, price: 0, occurrence: 1, messageOnly: false),
        SpecialEventSpec(type: .jarekGetsOut, price: 0, occurrence: 0, messageOnly: true),
        SpecialEventSpec(type: .lottery, price: -1000, occurrence: 0, messageOnly: true),
        SpecialEventSpec(type: .moon, price: 500000, occurrence: 4, messageOnly: false),
        SpecialEventSpec(type: .moonRetirement, price: 0, occurrence: 0, messageOnly: false),
        SpecialEventSpec(type: .reactor, price: 0, occurrence: 0, messageOnly: false),
        SpecialEventSpec(type: .reactorDelivered, price: 0, occurrence: 0, messageOnly: true),
        SpecialEventSpec(type: .reactorLaser, price: 0, occurrence: 0, messageOnly: false),
        SpecialEventSpec(type: .scarab, price: 0, occurrence: 1, messageOnly: true),
        SpecialEventSpec(type: .scarabDestroyed, price: 0, occurrence: 0, messageOnly: true),
        SpecialEventSpec(type: .scarabUpgradeHull, price: 0, occurrence: 0, messageOnly: false),
        SpecialEventSpec(type: .skill, price: 3000, occurrence: 3, messageOnly: false),
        SpecialEventSpec(type: .spaceMonster, price: 0, occurrence: 1, messageOnly: true),
        SpecialEventSpec(type: .spaceMonsterKilled, price: -15000, occurrence: 0, messageOnly: true),
        SpecialEventSpec(type: .tribble, price: 1000, occurrence: 1, messageOnly: false),
        SpecialEventSpec(type: .tribbleBuyer, price: 0, occurrence: 3, messageOnly: false),
        SpecialEventSpec(type: .wild, price: 0, occurrence: 1, messageOnly: false),
        SpecialEventSpec(type: .wildGetsOut, price: 0, occurrence: 0, messageOnly: true),
        SpecialEventSpec(type: .sculpture, price: -2000, occurrence: 0, messageOnly: false),
        SpecialEventSpec(type: .sculptureDelivered, price: 0, occurrence: 0, messageOnly: true),
        SpecialEventSpec(type: .sculptureHiddenBays, price: 0, occurrence: 0, messageOnly: false),
        SpecialEventSpec(type: .princess, price: 0, occurrence: 0, messageOnly: true),
        SpecialEventSpec(type: .princessCentauri, price: 0, occurrence: 0, messageOnly: true),
        SpecialEventSpec(type: .princessInthara, price: 0, occurrence: 0, messageOnly: true),
        SpecialEventSpec(type: .princessQonos, price: 0, occurrence: 0, messageOnly: false),
        SpecialEventSpec(type: .princessQuantum, price: 0, occurrence: 0, messageOnly: false),
        SpecialEventSpec(type: .princessReturned, price: 0, occurrence: 0, messageOnly: true),
    ]
}
