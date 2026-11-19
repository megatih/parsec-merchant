// SPDX-License-Identifier: GPL-2.0-or-later

/// Arrival report, report sheets, newspaper and feed identifiers (UI-ENC §17 "Arrival, reports", "Newspaper", "Shell").
nonisolated extension AXID {
    enum Arrival {
        static let card = "arrival.card"
        static let toggle = "arrival.card.toggle"
        static let dismiss = "arrival.card.dismiss"
        static func section(_ kind: ArrivalSectionKind) -> String { "arrival.section.\(kind.rawValue)" }
        static func encounter(_ index: Int) -> String { "arrival.encounter.\(index)" }
        static let news = "arrival.news"
        static let newsRead = "arrival.news.read"
        /// `status.arrivalReport`: the status-bar chip that selects Bridge (UI-ENC-055).

        static let all: [String] = [card, toggle, dismiss, news, newsRead]
            + ArrivalSectionKind.allCases.map(section) + (0..<4).map(encounter)
    }

    enum Report {
        static let sheet = "report.sheet"
        static let continueButton = "report.continue"

        static let all = [sheet, continueButton]
    }

    enum Newspaper {
        static let sheet = "newspaper.sheet"
        static let masthead = "newspaper.masthead"
        static func headline(_ index: Int) -> String { "newspaper.headline.\(index)" }
        /// The Bridge card (UI-ENC-072); its Read button is `AXID.Bridge.newspaperRead`.
        static let bridgeCard = "bridge.newspaper"

        static let all: [String] = [sheet, masthead, bridgeCard] + (0..<4).map(headline)
    }

    enum Feed {
        static func group(day: Int, systemIndex: Int) -> String { "status.feed.group.\(day).\(systemIndex)" }
        static func rounds(_ feedID: Int) -> String { "status.feed.rounds.\(feedID)" }

        static let all: [String] = [group(day: 0, systemIndex: 0), rounds(0)]
    }

    /// UI-ENC §17 arrival, newspaper and feed lists (appended to `encounterAreaAll`).
    static var arrivalAreaAll: [String] { Arrival.all + Report.all + Newspaper.all + Feed.all }
}
