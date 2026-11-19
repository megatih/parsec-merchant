// SPDX-License-Identifier: GPL-2.0-or-later

/// Identifiers the M12 accessibility flows use (A11Y §8, §11, §12), mirrored from the app's `AXID`. Extend, never rename.
extension AXID {
    enum A11y {
        static let welcomeRoot = "welcome.root"
        static let aboutWindow = "about.window"
        static let aboutLicense = "about.license"
        static let aboutLicenseClose = "about.license.close"
        static let helpWindow = "help.window"
        static let helpContent = "help.content"
        static func helpTopic(_ topic: String) -> String { "help.topic.\(topic)" }
        static func settingsTab(_ tab: String) -> String { "settings.tab.\(tab)" }
        static let settingsTabs = ["general", "sound", "intelligence", "advanced"]
        /// One control per Settings tab, proving the tab is shown.
        static let settingsTabProbe = ["general": "settings.textSize", "sound": "settings.sound.mute",
                                       "intelligence": "settings.intel.recommendations", "advanced": "settings.resetTips"]
        static let logbookStats = "logbook.stats"
        static let logbookAchievements = "logbook.achievements"
        static let openSavedDelete = "openSaved.delete"
        static let appConfirmationCancel = "appConfirmation.cancel"
        static let findSystemSheet = "findSystem.sheet"
        static let findSystemCancel = "findSystem.cancel"
        static func shipyardBuy(_ ship: String) -> String { "shipyard.ship.\(ship).buy" }
        static let shipPurchaseSheet = "shipPurchase.sheet"
        static let shipPurchaseCancel = "shipPurchase.cancel"
        static let retireCancel = "retire.cancel"
        static let feedList = "status.feed.list"
        static let feedClose = "status.feed.close"
        static let narrativeAccept = "narrative.accept"
        static let marketWhy = "market.why"
        static let tipMarket = "tip.market"
        static let tipGalaxy = "tip.galaxy"
        static let tipWarp = "tip.warp"
        static let tips = ["market": tipMarket, "galaxy": tipGalaxy, "warp": tipWarp]
        static let resetTips = "settings.resetTips"
        static let resetTipsStatus = "settings.resetTips.status"
        static let settingsTextSize = "settings.textSize"
    }
}
