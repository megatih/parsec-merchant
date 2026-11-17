// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import ParsecInsights

/// M10 identifiers: Logbook (LOG §10, STAT §8, ACH §7), market intel and system intel (INT §12), Settings ›
/// Intelligence (LLM §8) and the elsewhere-buttons. Extend, never rename.
nonisolated extension AXID {
    enum Logbook {
        static let root = "logbook.root"
        static let tab = "logbook.tab"
        static func tab(_ t: LogbookTab) -> String { "logbook.tab.\(t.rawValue)" }
        static let backToSummary = "logbook.backToSummary"
        static let list = "logbook.log.list"
        static func entry(_ id: Int) -> String { "logbook.entry.\(id)" }
        static let search = "logbook.search"
        static let filter = "logbook.filter"
        static func filter(_ c: LogCategory) -> String { "logbook.filter.\(c.rawValue)" }
        static let filterClear = "logbook.filter.clear"
        static let export = "logbook.export"
        static let stats = "logbook.stats"
        static func figure(_ k: StatFigureKind) -> String { "logbook.stats.figure.\(k.rawValue)" }
        static let worthChart = "logbook.stats.worthChart"
        static let profitChart = "logbook.stats.profitChart"
        static let killsChart = "logbook.stats.killsChart"
        static let achievements = "logbook.achievements"
        static func badge(_ id: AchievementID) -> String { "logbook.achievements.badge.\(id.rawValue)" }
        static let achievementsDisabled = "logbook.achievements.disabled"
        static let achievementsUnavailable = "logbook.achievements.unavailable"
        // `logbook.root` is registered by `SectionRoot` and `sidebar.logbook` by `Sidebar`.
        static let all: [String] = [tab, backToSummary, list, search, filter, filterClear, export, stats, worthChart,
                                    profitChart, killsChart, achievements, achievementsDisabled, achievementsUnavailable]
            + LogbookTab.allCases.map(tab) + LogCategory.allCases.map(filter) + StatFigureKind.allCases.map(figure)
            + AchievementID.allCases.map(badge)
    }

    enum MarketIntel {
        static func target(_ item: TradeItemType) -> String { "market.row.\(item).target" }
        static func history(_ item: TradeItemType) -> String { "market.row.\(item).history" }
        static let why = "market.why"
        static let whyShowAll = "market.why.showAll"
        static let recommendations = "market.recommendations"
        static func recommendationBuy(_ n: Int) -> String { "market.recommendation.buy.\(n)" }
        static func recommendationDestination(_ n: Int) -> String { "market.recommendation.destination.\(n)" }
        static let footerProjected = "market.footer.projected"
        static let all: [String] = [why, whyShowAll, recommendations, footerProjected]
            + TradeItemType.allCases.flatMap { [target($0), history($0)] }
            + (1...3).flatMap { [recommendationBuy($0), recommendationDestination($0)] }
    }

    enum SystemIntel {
        static let sheet = "systemIntel.sheet"
        static func row(_ item: TradeItemType) -> String { "systemIntel.row.\(item)" }
        static let done = "systemIntel.done"
        static let all: [String] = [sheet, done] + TradeItemType.allCases.map(row)
    }

    enum IntelSettings {
        static let recommendations = "settings.intel.recommendations"
        static let foundationModels = "settings.flavor.foundationModels"
        static let flavorStatus = "settings.flavor.status"
        static let showFlavor = "settings.flavor.show"
        static let resetAchievements = "settings.resetAchievements"
        static let all = [recommendations, foundationModels, flavorStatus, showFlavor, resetAchievements]
    }

    enum LogbookLinks {
        static let feedShowLogbook = "status.feed.showLogbook"
        static let gameOverShowLogbook = "gameOver.showLogbook"
        static let inspectorShowStatistics = "inspector.showStatistics"
        static let all = [feedShowLogbook, gameOverShowLogbook, inspectorShowStatistics]
    }

    /// Every identifier of the M10 area (registered in `AXID.all`).
    static var insightsAll: [String] {
        Logbook.all + MarketIntel.all + SystemIntel.all + IntelSettings.all + LogbookLinks.all
    }
}
