// SPDX-License-Identifier: GPL-2.0-or-later
// Achievements as pure folds over the log (docs/specs/ACH.md §1, §2, §6; ACH-001…009, ACH-030…065).
// Availability reads ruleset content, never the ruleset id. A cheated game satisfies nothing.
import ParsecEngine

/// ACH-001: the 36 achievements in catalog order. Raw values are permanent (they key the store).
public enum AchievementID: String, Codable, Sendable, Equatable, CaseIterable {
    case firstProfit, worth10k, worth100k, worth1m
    case dragonfly, spaceMonster, scarab, japori, jarek, wild, reactor, gemulon, experiment, artifact, sculpture, princess
    case moon, waspKiller, closeCall, hero, villain, debtFree, explorer50, explorerAll, wormhole, winHard, winImpossible
    case allCommodities, tribbleMax, marieCeleste, famousCaptains, escapePod, designer, ironman, bountyHunter, bigScore
}

/// ACH-002: a threshold (progress ≥ target) or a flag (progress == 1).
public enum AchievementKind: Sendable, Equatable {
    case threshold(target: Int)
    case flag

    public var target: Int {
        switch self {
        case let .threshold(target): target
        case .flag: 1
        }
    }
}

/// ACH-002: one catalog entry.
public struct AchievementDefinition: Sendable {
    public var id: AchievementID
    public var kind: AchievementKind
    public var availability: @Sendable (Ruleset) -> Bool
    public var progress: @Sendable (CareerStats) -> Int

    /// ACH-002.
    public func isSatisfied(by stats: CareerStats) -> Bool {
        let p = progress(stats)
        switch kind {
        case let .threshold(target): return p >= target
        case .flag: return p == 1
        }
    }
}

/// ACH-004: progress of one available achievement.
public struct AchievementProgress: Sendable, Equatable {
    public var id: AchievementID
    public var current: Int
    public var target: Int
    public var satisfied: Bool

    public init(id: AchievementID, current: Int, target: Int, satisfied: Bool) {
        self.id = id
        self.current = current
        self.target = target
        self.satisfied = satisfied
    }
}

public enum AchievementCatalog {
    /// Thresholds of the catalog (ACH-031…065).
    public static let tribbleCap = 100_000

    // swiftlint:disable cyclomatic_complexity
    /// ACH-002: the definition of `id`. `ruleset` sizes the Cartographer goal (ACH-053).
    public static func definition(_ id: AchievementID, ruleset: Ruleset = .windows201) -> AchievementDefinition {
        func flag(_ condition: @escaping @Sendable (CareerStats) -> Bool) -> AchievementDefinition {
            AchievementDefinition(id: id, kind: .flag, availability: { _ in true }, progress: { condition($0) ? 1 : 0 })
        }
        func threshold(_ target: Int, _ value: @escaping @Sendable (CareerStats) -> Int) -> AchievementDefinition {
            AchievementDefinition(id: id, kind: .threshold(target: target), availability: { _ in true }, progress: value)
        }
        func quest(_ event: SpecialEventType) -> AchievementDefinition { flag { $0.completed(event) } }
        let worth: @Sendable (CareerStats) -> Int = { max(0, $0.peakWorth ?? 0) }
        switch id {
        case .firstProfit: return flag { $0.firstProfitDay != nil }
        case .worth10k: return threshold(10_000, worth)
        case .worth100k: return threshold(100_000, worth)
        case .worth1m: return threshold(1_000_000, worth)
        case .dragonfly: return quest(.dragonflyShield)
        case .spaceMonster: return quest(.spaceMonsterKilled)
        case .scarab: return quest(.scarabUpgradeHull)
        case .japori: return quest(.japoriDelivery)
        case .jarek: return quest(.jarekGetsOut)
        case .wild: return quest(.wildGetsOut)
        case .reactor: return quest(.reactorLaser)
        case .gemulon: return quest(.gemulonFuel)
        case .experiment: return quest(.experimentStopped)
        case .artifact: return quest(.artifactDelivery)
        case .sculpture:
            var d = quest(.sculptureHiddenBays)
            d.availability = { $0.content.hasSculptureQuest }
            return d
        case .princess:
            var d = quest(.princessQuantum)
            d.availability = { $0.content.hasPrincessQuest }
            return d
        case .moon: return flag(won)
        case .waspKiller: return flag { $0.destroyedByShipType[ShipType.wasp.rawValue] >= 1 }
        case .closeCall: return flag { ($0.lowestHullPercentSurvived ?? 100) < 10 }
        case .hero: return flag { $0.policeRecordHighest == .hero }
        case .villain: return flag { $0.policeRecordLowest <= .villain }
        case .debtFree: return flag { $0.loansPaidOff >= 1 }
        case .explorer50: return threshold(50) { $0.visitedCount }
        case .explorerAll: return threshold(ruleset.tables.systemNames.count) { $0.visitedCount }
        case .wormhole: return flag { $0.wormholeJumps >= 1 }
        case .winHard: return flag { won($0) && ($0.difficulty ?? .beginner) >= .hard }
        case .winImpossible: return flag { won($0) && $0.difficulty == .impossible }
        case .allCommodities:
            return threshold(TradeItemType.allCases.count) { s in
                TradeItemType.allCases.indices.filter { s.itemsBought[$0] || s.itemsSold[$0] }.count
            }
        case .tribbleMax: return threshold(tribbleCap) { $0.maxTribbles }
        case .marieCeleste: return flag { $0.marieCelesteFound }
        case .famousCaptains: return threshold(3) { $0.famousCaptainsMet.filter { $0 }.count }
        case .escapePod: return flag { $0.escapePodsUsed >= 1 }
        case .designer:
            var d = flag { $0.customShipsBuilt >= 1 }
            d.availability = { $0.content.hasShipyards }
            return d
        case .ironman: return flag { $0.ironman && ($0.ended == .retired || won($0)) }
        case .bountyHunter: return threshold(10) { $0.bountiesCollected }
        case .bigScore: return threshold(10_000) { max(0, $0.bestSale?.profit ?? 0) }
        }
    }
    // swiftlint:enable cyclomatic_complexity

    /// "Win": the game ended by buying the moon (ACH §6).
    @Sendable static func won(_ s: CareerStats) -> Bool {
        s.ended == .boughtMoon || s.ended == .boughtMoonGirl
    }

    /// ACH-003: the achievements available in a ruleset, in catalog order.
    public static func available(in ruleset: Ruleset) -> [AchievementID] {
        AchievementID.allCases.filter { definition($0, ruleset: ruleset).availability(ruleset) }
    }

    /// ACH-004: progress of every available achievement, `current` clamped to `0...target`.
    public static func evaluate(_ stats: CareerStats, ruleset: Ruleset) -> [AchievementProgress] {
        available(in: ruleset).map { id in
            let d = definition(id, ruleset: ruleset)
            let target = d.kind.target
            return AchievementProgress(id: id, current: min(target, max(0, d.progress(stats))), target: target,
                                       satisfied: d.isSatisfied(by: stats))
        }
    }

    /// ACH-005 / ACH-008: the satisfied achievements in catalog order; empty for a cheated game.
    public static func satisfied(_ stats: CareerStats, ruleset: Ruleset) -> [AchievementID] {
        guard !stats.cheatsUsed else { return [] }
        return available(in: ruleset).filter { definition($0, ruleset: ruleset).isSatisfied(by: stats) }
    }

    /// ACH-006: `satisfied(after) − satisfied(before)`, in catalog order.
    public static func newlyUnlocked(before: CareerStats, after: CareerStats, ruleset: Ruleset) -> [AchievementID] {
        let now = satisfied(after, ruleset: ruleset)
        guard !now.isEmpty else { return [] }
        let old = satisfied(before, ruleset: ruleset)
        return now.filter { !old.contains($0) }
    }
}
