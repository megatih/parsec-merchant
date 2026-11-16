// SPDX-License-Identifier: GPL-2.0-or-later
// Core enumerations. Raw values match the C# 2.01 enums (Enums.cs) so that table indices and RNG draws
// (e.g. `GetRandom(17)` for a political system) map one-to-one onto the original.

public enum Difficulty: Int, Codable, Sendable, CaseIterable, Comparable {
    case beginner = 0, easy, normal, hard, impossible
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public enum TechLevel: Int, Codable, Sendable, CaseIterable, Comparable {
    case preAgricultural = 0, agricultural, medieval, renaissance, earlyIndustrial, industrial, postIndustrial, hiTech
    /// Marks equipment and ships that can never be bought.
    case unavailable = 8
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public enum SystemSize: Int, Codable, Sendable, CaseIterable, Comparable {
    case tiny = 0, small, medium, large, huge, gargantuan
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public enum PoliticalSystemType: Int, Codable, Sendable, CaseIterable {
    case anarchy = 0, capitalist, communist, confederacy, corporate, cybernetic, democracy, dictatorship, fascist,
         feudal, military, monarchy, pacifist, socialist, satori, technocracy, theocracy
}

/// Temporary system status ("pressure"). Raw values match C# `SystemPressure`.
public enum SystemPressure: Int, Codable, Sendable, CaseIterable {
    case none = 0, war, plague, drought, boredom, cold, cropFailure, employment
}

public enum SpecialResource: Int, Codable, Sendable, CaseIterable {
    case nothing = 0, mineralRich, mineralPoor, desert, sweetOceans, richSoil, poorSoil, richFauna, lifeless,
         weirdMushrooms, specialHerbs, artistic, warlike
}

public enum TradeItemType: Int, Codable, Sendable, CaseIterable {
    case water = 0, furs, food, ore, games, firearms, medicine, machines, narcotics, robots
    public var isIllegal: Bool { self == .firearms || self == .narcotics }
}

/// Police/pirate/trader activity levels. `na` (100) means "never".
public enum Activity: Int, Codable, Sendable, CaseIterable, Comparable {
    case absent = 0, minimal, few, some, moderate, many, abundant, swarms
    case na = 100
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public enum ShipType: Int, Codable, Sendable, CaseIterable {
    case flea = 0, gnat, firefly, mosquito, bumblebee, beetle, hornet, grasshopper, termite, wasp
    case spaceMonster, dragonfly, mantis, scarab, bottle, custom, scorpion
    /// Ships 0...9 can be bought and appear as random opponents (C# `Consts.MaxShip == 9` is an exclusive bound in places).
    public static let buyable: [ShipType] = [.flea, .gnat, .firefly, .mosquito, .bumblebee, .beetle, .hornet, .grasshopper, .termite, .wasp]
}

public enum WeaponType: Int, Codable, Sendable, CaseIterable, Comparable {
    case pulseLaser = 0, beamLaser, militaryLaser, morgansLaser, photonDisruptor, quantumDisruptor
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    public var isLaser: Bool { rawValue <= WeaponType.morgansLaser.rawValue }
    public var isDisruptor: Bool { !isLaser }
}

public enum ShieldType: Int, Codable, Sendable, CaseIterable, Comparable {
    case energy = 0, reflective, lightning
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public enum GadgetType: Int, Codable, Sendable, CaseIterable {
    case extraCargoBays = 0, autoRepairSystem, navigatingSystem, targetingSystem, cloakingDevice, fuelCompactor, hiddenCargoBays
}

public enum SkillType: Int, Codable, Sendable, CaseIterable {
    case pilot = 0, fighter, trader, engineer
}

public enum PoliceRecordType: Int, Codable, Sendable, CaseIterable, Comparable {
    case psychopath = 0, villain, criminal, crook, dubious, clean, lawful, trusted, liked, hero
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public enum ReputationType: Int, Codable, Sendable, CaseIterable, Comparable {
    case harmless = 0, mostlyHarmless, poor, average, aboveAverage, competent, dangerous, deadly, elite
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public enum ShipyardID: Int, Codable, Sendable, CaseIterable {
    case corellian = 0, incom, kuat, sienar, sorosuub
}

public enum ShipyardSkill: Int, Codable, Sendable, CaseIterable {
    case crewQuarters = 0, fuelBase, hullPerUnit, shieldSlotUnits, weaponSlotUnits
}

public enum OpponentType: Int, Codable, Sendable, CaseIterable {
    case bottle = 0, famousCaptain, mantis, pirate, police, trader
}

public enum VeryRareEncounter: Int, Codable, Sendable, CaseIterable {
    case marieCeleste = 0, captainAhab, captainConrad, captainHuie, bottleOld, bottleGood
}

public enum GameEndType: Int, Codable, Sendable, CaseIterable {
    case killed = 0, retired, boughtMoon, boughtMoonGirl
}

/// C# `SpecialEventType` (46 cases). Palm content uses a subset (see `ContentPacks`).
public enum SpecialEventType: Int, Codable, Sendable, CaseIterable {
    case artifact = 0, artifactDelivery, cargoForSale, dragonfly, dragonflyBaratas, dragonflyDestroyed, dragonflyMelina,
         dragonflyRegulas, dragonflyShield, eraseRecord, experiment, experimentFailed, experimentStopped, gemulon,
         gemulonFuel, gemulonInvaded, gemulonRescued, japori, japoriDelivery, jarek, jarekGetsOut, lottery, moon,
         moonRetirement, reactor, reactorDelivered, reactorLaser, scarab, scarabDestroyed, scarabUpgradeHull, skill,
         spaceMonster, spaceMonsterKilled, tribble, tribbleBuyer, wild, wildGetsOut, sculpture, sculptureDelivered,
         sculptureHiddenBays, princess, princessCentauri, princessInthara, princessQonos, princessQuantum, princessReturned
}

/// C# `NewsEvent` (39 cases).
public enum NewsEvent: Int, Codable, Sendable, CaseIterable {
    case artifactDelivery = 0, caughtLittering, dragonfly, dragonflyBaratas, dragonflyDestroyed, dragonflyMelina,
         dragonflyRegulas, dragonflyZalkon, experimentFailed, experimentPerformed, experimentStopped, experimentArrival,
         gemulon, gemulonInvaded, gemulonRescued, captAhabAttacked, captAhabDestroyed, captConradAttacked,
         captConradDestroyed, captHuieAttacked, captHuieDestroyed, japori, japoriDelivery, jarekGetsOut, scarab,
         scarabDestroyed, scarabHarass, spaceMonster, spaceMonsterKilled, wildArrested, wildGetsOut, sculptureStolen,
         sculptureTracked, princess, princessCentauri, princessInthara, princessQonos, princessRescued, princessReturned
}

/// C# `EncounterType` (35 cases).
public enum EncounterType: Int, Codable, Sendable, CaseIterable {
    case bottleGood = 0, bottleOld, captainAhab, captainConrad, captainHuie, dragonflyAttack, dragonflyIgnore,
         famousCaptainAttack, famousCaptDisabled, marieCeleste, marieCelestePolice, pirateAttack, pirateIgnore,
         pirateFlee, pirateSurrender, pirateDisabled, policeAttack, policeIgnore, policeFlee, policeSurrender,
         policeDisabled, policeInspect, scarabAttack, scarabIgnore, scorpionAttack, scorpionIgnore,
         spaceMonsterAttack, spaceMonsterIgnore, traderAttack, traderIgnore, traderFlee, traderSurrender,
         traderDisabled, traderBuy, traderSell
}
