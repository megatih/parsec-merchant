// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecInsights

/// ACH §6: localized achievement names and one-line descriptions.
nonisolated enum AchievementText {
    static func name(_ id: AchievementID) -> String {
        switch id {
        case .firstProfit: String(localized: "First Profit")
        case .worth10k: String(localized: "Making a Living")
        case .worth100k: String(localized: "Merchant Prince")
        case .worth1m: String(localized: "Millionaire")
        case .dragonfly: String(localized: "Dragon Slayer")
        case .spaceMonster: String(localized: "Monster Hunter")
        case .scarab: String(localized: "Scarab Breaker")
        case .japori: String(localized: "Plague Doctor")
        case .jarek: String(localized: "Diplomatic Courier")
        case .wild: String(localized: "Smuggler's Friend")
        case .reactor: String(localized: "Hot Cargo")
        case .gemulon: String(localized: "Gemulon Saved")
        case .experiment: String(localized: "Fabric Mender")
        case .artifact: String(localized: "Relic Runner")
        case .sculpture: String(localized: "Art Thief's Bane")
        case .princess: String(localized: "Royal Escort")
        case .moon: String(localized: "Lord of the Moon")
        case .waspKiller: String(localized: "Wasp Swatter")
        case .closeCall: String(localized: "Close Call")
        case .hero: String(localized: "Hero of the Spaceways")
        case .villain: String(localized: "Most Wanted")
        case .debtFree: String(localized: "Debt Free")
        case .explorer50: String(localized: "Explorer")
        case .explorerAll: String(localized: "Cartographer")
        case .wormhole: String(localized: "Through the Wormhole")
        case .winHard: String(localized: "Hardened")
        case .winImpossible: String(localized: "Impossible Odds")
        case .allCommodities: String(localized: "Jack of All Trades")
        case .tribbleMax: String(localized: "Tribble Trouble")
        case .marieCeleste: String(localized: "Ghost Ship")
        case .famousCaptains: String(localized: "Star-Struck")
        case .escapePod: String(localized: "Escape Artist")
        case .designer: String(localized: "Shipwright")
        case .ironman: String(localized: "Iron Will")
        case .bountyHunter: String(localized: "Bounty Hunter")
        case .bigScore: String(localized: "Big Score")
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    static func description(_ id: AchievementID) -> String {
        switch id {
        case .firstProfit: String(localized: "Sell cargo for more than you paid.")
        case .worth10k: String(localized: "Reach a net worth of 10,000 credits.")
        case .worth100k: String(localized: "Reach a net worth of 100,000 credits.")
        case .worth1m: String(localized: "Reach a net worth of 1,000,000 credits.")
        case .dragonfly: String(localized: "Destroy the Dragonfly and claim its shield.")
        case .spaceMonster: String(localized: "Kill the space monster at Acamar.")
        case .scarab: String(localized: "Destroy the Scarab and upgrade your hull.")
        case .japori: String(localized: "Deliver the antidote to Japori.")
        case .jarek: String(localized: "Bring Ambassador Jarek safely home.")
        case .wild: String(localized: "Get Jonathan Wild to Kravat.")
        case .reactor: String(localized: "Deliver the unstable reactor.")
        case .gemulon: String(localized: "Warn Gemulon of the invasion in time.")
        case .experiment: String(localized: "Stop Dr. Fehler's experiment.")
        case .artifact: String(localized: "Deliver the alien artifact.")
        case .sculpture: String(localized: "Deliver the stolen sculpture.")
        case .princess: String(localized: "Rescue the Princess and bring her home.")
        case .moon: String(localized: "Buy a moon and retire there.")
        case .waspKiller: String(localized: "Destroy a Wasp.")
        case .closeCall: String(localized: "Survive an encounter with less than 10% hull.")
        case .hero: String(localized: "Reach the police record Hero.")
        case .villain: String(localized: "Reach the police record Villain.")
        case .debtFree: String(localized: "Pay off a bank loan completely.")
        case .explorer50: String(localized: "Visit 50 systems.")
        case .explorerAll: String(localized: "Visit every system in the galaxy.")
        case .wormhole: String(localized: "Travel through a wormhole.")
        case .winHard: String(localized: "Win the game on Hard or Impossible.")
        case .winImpossible: String(localized: "Win the game on Impossible.")
        case .allCommodities: String(localized: "Buy or sell every commodity.")
        case .tribbleMax: String(localized: "Carry 100,000 tribbles.")
        case .marieCeleste: String(localized: "Find the Marie Celeste.")
        case .famousCaptains: String(localized: "Meet Captain Ahab, Captain Conrad and Captain Huie.")
        case .escapePod: String(localized: "Survive in an escape pod.")
        case .designer: String(localized: "Build a ship of your own design.")
        case .ironman: String(localized: "Finish an Ironman game by retiring or buying the moon.")
        case .bountyHunter: String(localized: "Collect 10 bounties.")
        case .bigScore: String(localized: "Make 10,000 credits profit in a single sale.")
        }
    }

    /// The SF Symbol of a badge (vector badge art is M11, ACH-023). Locked badges use a lock, so locked and unlocked
    /// differ by symbol, not colour alone (ACH-019).
    static func symbol(_ id: AchievementID, unlocked: Bool) -> String {
        guard unlocked else { return "lock.circle" }
        return switch id {
        case .firstProfit, .worth10k, .worth100k, .worth1m, .bigScore, .allCommodities: "dollarsign.circle.fill"
        case .waspKiller, .closeCall, .bountyHunter, .villain, .hero: "shield.lefthalf.filled"
        case .explorer50, .explorerAll, .wormhole: "globe"
        case .moon, .winHard, .winImpossible, .ironman: "crown.fill"
        default: "star.circle.fill"
        }
    }
}
