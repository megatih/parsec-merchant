// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// Localized display names of engine values. Data names (systems, crew) are not localized: they are proper names.
enum Names {
    static func system(_ index: Int, in state: GameState) -> String {
        let names = state.ruleset.tables.systemNames
        return names.indices.contains(index) ? names[index] : "#\(index)"
    }

    static func crew(_ id: Int, in state: GameState) -> String {
        if id == CrewID.commander { return state.commander.name }
        return GameNames.crew.indices.contains(id) ? GameNames.crew[id] : "#\(id)"
    }

    static func item(_ t: TradeItemType) -> LocalizedStringResource {
        switch t {
        case .water: "Water"
        case .furs: "Furs"
        case .food: "Food"
        case .ore: "Ore"
        case .games: "Games"
        case .firearms: "Firearms"
        case .medicine: "Medicine"
        case .machines: "Machines"
        case .narcotics: "Narcotics"
        case .robots: "Robots"
        }
    }

    static func ship(_ t: ShipType) -> LocalizedStringResource {
        switch t {
        case .flea: "Flea"
        case .gnat: "Gnat"
        case .firefly: "Firefly"
        case .mosquito: "Mosquito"
        case .bumblebee: "Bumblebee"
        case .beetle: "Beetle"
        case .hornet: "Hornet"
        case .grasshopper: "Grasshopper"
        case .termite: "Termite"
        case .wasp: "Wasp"
        case .spaceMonster: "Space Monster"
        case .dragonfly: "Dragonfly"
        case .mantis: "Mantis"
        case .scarab: "Scarab"
        case .bottle: "Bottle"
        case .custom: "Custom Ship"
        case .scorpion: "Scorpion"
        }
    }

    static func skill(_ s: SkillType) -> LocalizedStringResource {
        switch s {
        case .pilot: "Pilot"
        case .fighter: "Fighter"
        case .trader: "Trader"
        case .engineer: "Engineer"
        }
    }

    static func difficulty(_ d: Difficulty) -> LocalizedStringResource {
        switch d {
        case .beginner: "Beginner"
        case .easy: "Easy"
        case .normal: "Normal"
        case .hard: "Hard"
        case .impossible: "Impossible"
        }
    }

    static func ruleset(_ r: RulesetID) -> LocalizedStringResource {
        switch r {
        case .modern: "Modern"
        case .windows201: "Windows 2.01"
        case .palm122: "Original Palm 1.2.2"
        }
    }

    static func policeRecord(_ r: PoliceRecordType) -> LocalizedStringResource {
        switch r {
        case .psychopath: "Psychopath"
        case .villain: "Villain"
        case .criminal: "Criminal"
        case .crook: "Crook"
        case .dubious: "Dubious"
        case .clean: "Clean"
        case .lawful: "Lawful"
        case .trusted: "Trusted"
        case .liked: "Liked"
        case .hero: "Hero"
        }
    }

    static func reputation(_ r: ReputationType) -> LocalizedStringResource {
        switch r {
        case .harmless: "Harmless"
        case .mostlyHarmless: "Mostly harmless"
        case .poor: "Poor"
        case .average: "Average"
        case .aboveAverage: "Above average"
        case .competent: "Competent"
        case .dangerous: "Dangerous"
        case .deadly: "Deadly"
        case .elite: "Elite"
        }
    }

    static func ending(_ e: GameEndType) -> LocalizedStringResource {
        switch e {
        case .killed: "You were killed."
        case .retired: "You retired."
        case .boughtMoon: "You claimed your moon."
        case .boughtMoonGirl: "You claimed your moon and retired there with Ziyal."
        }
    }

    static func weapon(_ w: WeaponType) -> LocalizedStringResource {
        switch w {
        case .pulseLaser: "Pulse laser"
        case .beamLaser: "Beam laser"
        case .militaryLaser: "Military laser"
        case .morgansLaser: "Morgan's laser"
        case .photonDisruptor: "Photon disruptor"
        case .quantumDisruptor: "Quantum disruptor"
        }
    }

    static func shield(_ s: ShieldType) -> LocalizedStringResource {
        switch s {
        case .energy: "Energy shield"
        case .reflective: "Reflective shield"
        case .lightning: "Lightning shield"
        }
    }

    static func gadget(_ g: GadgetType) -> LocalizedStringResource {
        switch g {
        case .extraCargoBays: "5 extra cargo bays"
        case .autoRepairSystem: "Auto-repair system"
        case .navigatingSystem: "Navigating system"
        case .targetingSystem: "Targeting system"
        case .cloakingDevice: "Cloaking device"
        case .fuelCompactor: "Fuel compactor"
        case .hiddenCargoBays: "Hidden cargo bays"
        }
    }

    static func transfer(_ t: TransferItem) -> LocalizedStringResource {
        switch t {
        case .morgansLaser: "Morgan's laser"
        case .quantumDisruptor: "Quantum disruptor"
        case .lightningShield: "Lightning shield"
        case .fuelCompactor: "Fuel compactor"
        case .hiddenCargoBays: "Hidden cargo bays"
        case .escapePod: "Escape pod"
        }
    }

    static func encounterAction(_ a: EncounterAction) -> LocalizedStringResource {
        switch a {
        case .attack: "Attack"
        case .flee: "Flee"
        case .surrender: "Surrender"
        case .bribe: "Bribe"
        case .submit: "Submit"
        case .yield: "Yield"
        case .ignore: "Ignore"
        case .plunder: "Plunder"
        case .trade: "Trade"
        case .board: "Board"
        case .drink: "Drink"
        case .meet: "Meet"
        case .stop: "Stop"
        case .autoRepeat: "Continue"
        case .resolve: "Fight It Out"
        }
    }

    static func badge(_ b: EncounterBadge) -> LocalizedStringResource {
        switch b {
        case .special: "special ship"
        case .pirate: "pirate"
        case .alien: "alien ship"
        case .police: "police ship"
        case .trader: "trader"
        }
    }

    static func size(_ s: SystemSize) -> LocalizedStringResource {
        switch s {
        case .tiny: "Tiny"
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .huge: "Huge"
        case .gargantuan: "Gargantuan"
        }
    }

    static func killKind(_ k: KillKind?) -> LocalizedStringResource {
        switch k {
        case .pirate: "pirates"
        case .police: "police"
        case .trader: "traders"
        case nil: "nobody"
        }
    }
}
