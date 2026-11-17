// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import ParsecInsights

/// STAT-014: localized labels and values of the Statistics tiles.
enum StatFigureText {
    static func label(_ kind: StatFigureKind) -> String {
        switch kind {
        case .daysPlayed: String(localized: "Days played")
        case .parsecsTravelled: String(localized: "Parsecs travelled")
        case .systemsVisited: String(localized: "Systems visited")
        case .wormholeJumps: String(localized: "Wormhole jumps")
        case .trades: String(localized: "Trades")
        case .totalTradeProfit: String(localized: "Total trade profit")
        case .bestTrade: String(localized: "Best trade")
        case .encountersWon: String(localized: "Encounters won")
        case .encountersFled: String(localized: "Encounters fled")
        case .encountersSurrendered: String(localized: "Encounters surrendered")
        case .killsPirates: String(localized: "Pirates killed")
        case .killsPolice: String(localized: "Police killed")
        case .killsTraders: String(localized: "Traders killed")
        case .bounties: String(localized: "Bounties")
        case .finesAndBribes: String(localized: "Fines and bribes")
        case .arrests: String(localized: "Arrests")
        case .peakWorth: String(localized: "Peak net worth")
        }
    }

    static func value(_ value: StatFigureValue) -> String {
        switch value {
        case let .days(n): String(localized: "\(n) days")
        case let .parsecs(n): String(localized: "\(n) parsecs")
        case let .systems(visited, of): String(localized: "\(visited) of \(of)")
        case let .credits(n): String(localized: "\(n.formatted()) cr.")
        case let .count(n): n.formatted()
        case let .trade(best):
            if let best {
                String(localized: "\(String(localized: Names.item(best.item))) +\(best.profit.formatted()) cr.")
            } else {
                String(localized: "None yet")
            }
        }
    }
}

/// STAT-017 / STAT-018: everything the Statistics tab shows, from `CareerStats` only.
struct StatisticsModel: Equatable {
    struct Tile: Equatable, Identifiable {
        var kind: StatFigureKind
        var label: String
        var value: String
        var id: StatFigureKind { kind }
    }

    struct Bar: Equatable, Identifiable {
        var label: String
        var value: Int
        /// "+"/"−" sign text so colour is never the only signal (STAT-017).
        var signText: String
        var id: String { label }
    }

    static let worthPoints = 400

    var tiles: [Tile]
    var worth: [WorthSample]
    var profitBars: [Bar]
    var killBars: [Bar]
    /// STAT-018: "Statistics since day N" (partial history) or "Statistics since the start".
    var sinceText: String
    /// STAT-018: shown for a cheated game; no figure is hidden.
    var cheatNotice: String?

    static func make(stats: CareerStats) -> StatisticsModel {
        let tiles = stats.figures.map { Tile(kind: $0.kind, label: StatFigureText.label($0.kind), value: StatFigureText.value($0.value)) }
        let profit = TradeItemType.allCases.compactMap { item -> Bar? in
            let v = stats.profitByItem.indices.contains(item.rawValue) ? stats.profitByItem[item.rawValue] : 0
            guard v != 0 else { return nil }
            return Bar(label: String(localized: Names.item(item)), value: v, signText: v > 0 ? "+" : "−")
        }
        let kills = ShipType.allCases.compactMap { ship -> Bar? in
            let v = stats.destroyedByShipType.indices.contains(ship.rawValue) ? stats.destroyedByShipType[ship.rawValue] : 0
            guard v > 0 else { return nil }
            return Bar(label: String(localized: Names.ship(ship)), value: v, signText: "")
        }
        return StatisticsModel(tiles: tiles, worth: stats.worthSeries(maxPoints: worthPoints), profitBars: profit, killBars: kills,
                               sinceText: stats.isPartial ? String(localized: "Statistics since day \(stats.startDay ?? 0)")
                                   : String(localized: "Statistics since the start"),
                               cheatNotice: stats.cheatsUsed ? String(localized: "Cheats were used in this game") : nil)
    }

    /// STAT-019: Edit › Copy with the Statistics tab shown.
    static func copyText(stats: CareerStats) -> String {
        StatsMarkdown.render(stats: stats, header: (String(localized: "Statistic"), String(localized: "Value")),
                             labels: StatFigureText.label, values: StatFigureText.value)
    }
}

/// ACH-010, ACH-019, ACH-020: the Achievements tab.
struct AchievementsModel: Equatable {
    struct Badge: Equatable, Identifiable {
        var id: AchievementID
        var name: String
        var description: String
        var symbol: String
        var unlocked: Bool
        /// "Unlocked <date>" from the app-wide store.
        var unlockedText: String?
        /// "in this game, day N" when this journal has the unlock entry.
        var inGameText: String?
        /// "current / target" for threshold achievements (nil for flags and in a cheated game).
        var progress: (current: Int, target: Int)?

        static func == (a: Badge, b: Badge) -> Bool {
            a.id == b.id && a.name == b.name && a.unlocked == b.unlocked && a.unlockedText == b.unlockedText
                && a.inGameText == b.inGameText && a.progress?.current == b.progress?.current && a.progress?.target == b.progress?.target
                && a.symbol == b.symbol && a.description == b.description
        }
    }

    var badges: [Badge]
    var unavailable: [Badge]
    var headerText: String
    /// ACH-010.
    var disabledBanner: String?

    static func make(stats: CareerStats?, ruleset: Ruleset, records: [AchievementRecord], journal: GameJournal?,
                     cheatsUsed: Bool, dateFormatter: (String) -> String = AchievementsModel.formatDate) -> AchievementsModel {
        let cheated = cheatsUsed || stats?.cheatsUsed == true
        let progress = (stats.map { AchievementCatalog.evaluate($0, ruleset: ruleset) } ?? [])
        let inGame: [AchievementID: Int] = (journal?.entries ?? []).reduce(into: [:]) { acc, e in
            if case let .achievementUnlocked(id) = e.kind, acc[id] == nil { acc[id] = e.day }
        }
        let available = Set(AchievementCatalog.available(in: ruleset))
        func badge(_ id: AchievementID) -> Badge {
            let record = records.first { $0.id == id.rawValue }
            let p = progress.first { $0.id == id }
            let showProgress: (current: Int, target: Int)? = if !cheated, let p, p.target > 1 { (p.current, p.target) } else { nil }
            return Badge(id: id, name: AchievementText.name(id), description: AchievementText.description(id),
                         symbol: AchievementText.symbol(id, unlocked: record != nil), unlocked: record != nil,
                         unlockedText: record.map { String(localized: "Unlocked \(dateFormatter($0.unlockedAt))") },
                         inGameText: inGame[id].map { String(localized: "in this game, day \($0)") }, progress: showProgress)
        }
        let badges = AchievementID.allCases.filter { available.contains($0) }.map(badge)
        let unavailable = AchievementID.allCases.filter { !available.contains($0) }.map(badge)
        let unlockedCount = badges.filter(\.unlocked).count
        return AchievementsModel(badges: badges, unavailable: unavailable,
                                 headerText: String(localized: "\(unlockedCount) of \(badges.count) unlocked"),
                                 disabledBanner: cheated
                                     ? String(localized: "Achievements are disabled for this game because cheats were used.") : nil)
    }

    /// ISO 8601 UTC from the store, shown as a medium date.
    nonisolated static func formatDate(_ iso: String) -> String {
        guard let date = try? Date(iso, strategy: .iso8601) else { return iso }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
