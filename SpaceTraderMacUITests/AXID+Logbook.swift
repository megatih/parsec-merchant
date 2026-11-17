// SPDX-License-Identifier: GPL-2.0-or-later

/// M10 identifiers used by the UI tests (LOG §10, STAT §8, ACH §7), mirrored from the app's `AXID+Logbook.swift`.
extension AXID {
    enum Logbook {
        static let root = "logbook.root"
        static let tab = "logbook.tab"
        static let list = "logbook.log.list"
        static let entryPrefix = "logbook.entry."
        static let search = "logbook.search"
        static let filter = "logbook.filter"
        static let export = "logbook.export"
        static let stats = "logbook.stats"
        static let achievements = "logbook.achievements"
        static func badge(_ id: String) -> String { "logbook.achievements.badge.\(id)" }
        static let backToSummary = "logbook.backToSummary"
        static let feedShowLogbook = "status.feed.showLogbook"
    }
}
