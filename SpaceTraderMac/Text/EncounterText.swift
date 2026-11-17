// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// Encounter stance wording for the feed. The Encounter view's header is `EncounterIntro` (UI-ENC-016).
enum EncounterText {
    // One line per encounter type; the case count is the complexity.
    // swiftlint:disable:next cyclomatic_complexity
    static func stance(_ type: EncounterType) -> LocalizedStringResource {
        switch type {
        case .bottleGood, .bottleOld: "a bottle floats in space"
        case .captainAhab: "Captain Ahab hails you"
        case .captainConrad: "Captain Conrad hails you"
        case .captainHuie: "Captain Huie hails you"
        case .dragonflyAttack: "the Dragonfly attacks"
        case .dragonflyIgnore: "the Dragonfly ignores you"
        case .famousCaptainAttack: "the famous captain attacks"
        case .famousCaptDisabled: "the famous captain's ship is disabled"
        case .marieCeleste: "a derelict ship drifts nearby"
        case .marieCelestePolice: "the customs police want a word"
        case .pirateAttack: "the pirate attacks"
        case .pirateIgnore: "the pirate ignores you"
        case .pirateFlee: "the pirate flees"
        case .pirateSurrender: "the pirate surrenders"
        case .pirateDisabled: "the pirate ship is disabled"
        case .policeAttack: "the police attack"
        case .policeIgnore: "the police ignore you"
        case .policeFlee: "the police flee"
        case .policeSurrender: "the police surrender"
        case .policeDisabled: "the police ship is disabled"
        case .policeInspect: "the police want to inspect your ship"
        case .scarabAttack: "the Scarab attacks"
        case .scarabIgnore: "the Scarab ignores you"
        case .scorpionAttack: "the Scorpion attacks"
        case .scorpionIgnore: "the Scorpion ignores you"
        case .spaceMonsterAttack: "the space monster attacks"
        case .spaceMonsterIgnore: "the space monster ignores you"
        case .traderAttack: "the trader attacks"
        case .traderIgnore: "the trader ignores you"
        case .traderFlee: "the trader flees"
        case .traderSurrender: "the trader surrenders"
        case .traderDisabled: "the trader ship is disabled"
        case .traderBuy: "the trader offers to buy cargo"
        case .traderSell: "the trader offers to sell cargo"
        }
    }
}

/// Special-event titles (Strings.cs SpecialEventTitles). The Bridge adds the story texts.
enum SpecialEventText {
    // One line per event; the case count is the complexity.
    // swiftlint:disable:next cyclomatic_complexity
    static func title(_ type: SpecialEventType) -> LocalizedStringResource {
        switch type {
        case .artifact: "Alien Artifact"
        case .artifactDelivery: "Artifact Delivery"
        case .cargoForSale: "Cargo For Sale"
        case .dragonfly: "Dragonfly"
        case .dragonflyBaratas: "Weird Ship"
        case .dragonflyDestroyed: "Dragonfly Destroyed"
        case .dragonflyMelina: "Lightning Ship"
        case .dragonflyRegulas: "Strange Ship"
        case .dragonflyShield: "Lightning Shield"
        case .eraseRecord: "Erase Record"
        case .experiment: "Dangerous Experiment"
        case .experimentFailed: "Experiment Failed"
        case .experimentStopped: "Disaster Averted"
        case .gemulon: "Alien Invasion"
        case .gemulonFuel: "Fuel Compactor"
        case .gemulonInvaded: "Gemulon Invaded"
        case .gemulonRescued: "Gemulon Rescued"
        case .japori: "Japori Disease"
        case .japoriDelivery: "Medicine Delivery"
        case .jarek: "Ambassador Jarek"
        case .jarekGetsOut: "Jarek Gets Out"
        case .lottery: "Lottery Winner"
        case .moon: "Moon For Sale"
        case .moonRetirement: "Retirement"
        case .reactor: "Morgan's Reactor"
        case .reactorDelivered: "Reactor Delivered"
        case .reactorLaser: "Install Morgan's Laser"
        case .scarab: "Scarab Stolen"
        case .scarabDestroyed: "Scarab Destroyed"
        case .scarabUpgradeHull: "Upgrade Hull"
        case .skill: "Skill Increase"
        case .spaceMonster: "Space Monster"
        case .spaceMonsterKilled: "Monster Killed"
        case .tribble: "Merchant Prince"
        case .tribbleBuyer: "Tribble Buyer"
        case .wild: "Jonathan Wild"
        case .wildGetsOut: "Wild Gets Out"
        case .sculpture: "Stolen Sculpture"
        case .sculptureDelivered: "Sculpture Delivered"
        case .sculptureHiddenBays: "Install Hidden Compartments"
        case .princess: "Kidnapped"
        case .princessCentauri: "Aggressive Ship"
        case .princessInthara: "Dangerous Scorpion"
        case .princessQonos: "Royal Rescue"
        case .princessQuantum: "Quantum Disruptor"
        case .princessReturned: "Royal Return"
        }
    }
}
