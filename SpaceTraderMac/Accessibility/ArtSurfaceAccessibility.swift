// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import SwiftUI

/// How a custom-drawn surface appears to VoiceOver (A11Y-009).
nonisolated enum AccessibilityRepresentation: Equatable, Sendable {
    /// Decorative: hidden from accessibility.
    case hidden
    /// One element with this label (and the header trait when `header`).
    case label(String, header: Bool = false)
    /// One element with a label and a custom action (tribbles).
    case labelWithAction(String, action: String)
    /// Accessibility children, one per drawn item (the maps, MAP-080…084).
    case children
}

/// Every custom-drawn surface of the app (A11Y-009). The switch in `accessibility` is exhaustive.
nonisolated enum ArtSurface: Equatable, Sendable {
    case galaxyMap, miniChart
    case playerPortrait(ship: String, hull: Int, shields: Int?)
    case opponentPortrait(kind: String, ship: String, hull: Int, shields: Int?)
    case bridgePlanet(system: String, techLevel: String, government: String)
    case starfield, nebula, welcomeScene, transitScene, combatEffects, gameOverScene, engineGlow
    case wordmark
    case tribbles(count: Int)
    case careerCard(summary: String)
    /// A commodity, equipment or badge glyph; `name` is nil when a text beside it names the item.
    case glyph(name: String?)
    case crewAvatar
    case chart(summary: String)

    /// Every case shape, for the exhaustive unit test.
    static let samples: [ArtSurface] = [
        .galaxyMap, .miniChart, .playerPortrait(ship: "Gnat", hull: 78, shields: 40),
        .opponentPortrait(kind: "Pirate", ship: "Mosquito", hull: 100, shields: nil),
        .bridgePlanet(system: "Castor", techLevel: "Renaissance", government: "Democracy"),
        .starfield, .nebula, .welcomeScene, .transitScene, .combatEffects, .gameOverScene, .engineGlow, .wordmark,
        .tribbles(count: 12), .careerCard(summary: "Retired on day 40."), .glyph(name: nil), .glyph(name: "Water"),
        .crewAvatar, .chart(summary: "Worth rose to 12,000 credits."),
    ]

    var accessibility: AccessibilityRepresentation {
        switch self {
        case .galaxyMap, .miniChart:
            return .children
        case let .playerPortrait(ship, hull, shields):
            return .label(String(localized: "Your \(ship), \(Self.condition(hull: hull, shields: shields))"))
        case let .opponentPortrait(kind, ship, hull, shields):
            return .label(String(localized: "\(kind) \(ship), \(Self.condition(hull: hull, shields: shields))"))
        case let .bridgePlanet(system, techLevel, government):
            return .label(String(localized: "\(system), \(techLevel), \(government)"))
        case .starfield, .nebula, .welcomeScene, .transitScene, .combatEffects, .gameOverScene, .engineGlow:
            return .hidden
        case .wordmark:
            return .label(String(localized: "Parsec Merchant"), header: true)
        case let .tribbles(count):
            return .labelWithAction(count == 1 ? String(localized: "1 tribble aboard") : String(localized: "\(count) tribbles aboard"),
                                    action: String(localized: "Pet a tribble"))
        case let .careerCard(summary):
            return .label(summary)
        case let .glyph(name):
            return name.map { .label($0) } ?? .hidden
        case .crewAvatar:
            return .hidden
        case let .chart(summary):
            return .label(summary)
        }
    }

    /// The label text of a labelled surface (nil for hidden surfaces and maps).
    var label: String? {
        switch accessibility {
        case let .label(text, _), let .labelWithAction(text, _): text
        case .hidden, .children: nil
        }
    }

    /// "hull 78%, shields 40%" / "hull 78%, no shields".
    static func condition(hull: Int, shields: Int?) -> String {
        if let shields { return String(localized: "hull \(hull)%, shields \(shields)%") }
        return String(localized: "hull \(hull)%, no shields")
    }
}

extension View {
    /// Applies an `ArtSurface`'s representation (A11Y-009). `.children` leaves the surface's own children in place.
    @ViewBuilder
    func artAccessibility(_ surface: ArtSurface) -> some View {
        switch surface.accessibility {
        case .hidden:
            accessibilityHidden(true)
        case let .label(text, header):
            accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: text))
                .accessibilityAddTraits(header ? [.isHeader, .isImage] : .isImage)
        case let .labelWithAction(text, _):
            accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: text))
                .accessibilityAddTraits(.isImage)
        case .children:
            self
        }
    }
}

// MARK: Rotors (A11Y-014)

/// The Market's custom rotors (A11Y-014). Pure.
enum MarketRotors {
    /// "In Hold": rows with `held > 0`, in table order.
    static func inHold(_ rows: [MarketRowModel]) -> [TradeItemType] {
        rows.filter { $0.row.held > 0 }.map(\.item)
    }

    /// "Profitable at Target": rows whose target quote beats the buy price here, in table order.
    static func profitableAtTarget(_ rows: [MarketRowModel], targetPrice: (TradeItemType) -> Int?) -> [TradeItemType] {
        rows.filter { r in
            guard let buy = r.buyPrice, let target = targetPrice(r.item) else { return false }
            return target > buy
        }.map(\.item)
    }
}

/// The Quests rotor "Deadlines": entries with `daysLeft`, soonest first (A11Y-014).
enum QuestRotors {
    static func deadlines(_ cards: [QuestsModel.Card]) -> [Int] {
        var entries: [(index: Int, days: Int)] = []
        for c in cards {
            if let days = c.entry.daysLeft { entries.append((c.index, days)) }
        }
        entries.sort { a, b in a.days != b.days ? a.days < b.days : a.index < b.index }
        return entries.map(\.index)
    }

    /// The cards of `deadlines`, in rotor order.
    static func deadlineCards(_ cards: [QuestsModel.Card]) -> [QuestsModel.Card] {
        deadlines(cards).compactMap { i in cards.first { $0.index == i } }
    }
}
