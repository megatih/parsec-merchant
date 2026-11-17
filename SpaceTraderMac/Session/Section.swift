// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// Facts about the session that decide which sections can be used.
struct SectionContext: Equatable, Sendable {
    var hasGame: Bool
    var ended: Bool
    var hasShipyards: Bool
    var currentSystemHasShipyard: Bool

    static let noGame = SectionContext(hasGame: false, ended: false, hasShipyards: false, currentSystemHasShipyard: false)

    static func make(state: GameState?) -> SectionContext {
        guard let state else { return .noGame }
        let ended = if case .gameOver = state.phase { true } else { false }
        return SectionContext(hasGame: true, ended: ended, hasShipyards: state.ruleset.content.hasShipyards,
                              currentSystemHasShipyard: state.currentSystem.shipyard != nil)
    }

    /// Shipyard's Designer tab: shipyards exist in the ruleset and the current system has one (UI-SHELL-038/069).
    var designerAvailable: Bool { hasGame && !ended && hasShipyards && currentSystemHasShipyard }
}

/// The sidebar sections of the playing window, in display order (UI-SHELL-035; Logbook ⌘9 from M10, LOG-029).
nonisolated enum Section: String, CaseIterable, Identifiable, Sendable {
    case bridge, market, shipyard, outfitter, crew, bank, galaxy, quests, logbook

    var id: String { rawValue }

    /// Every section needs a loaded game that has not ended; the Logbook is also available in an ended game and is the
    /// only one then (LOG-029, MENU-023).
    func isAvailable(in context: SectionContext) -> Bool {
        guard context.hasGame else { return false }
        return self == .logbook || !context.ended
    }

    /// The restored section for a stored raw value; unknown or unavailable values fall back to Bridge (UI-SHELL-016).
    /// An ended game always reopens on its game-over card.
    static func restored(rawValue: String?, context: SectionContext) -> Section {
        guard !context.ended, let rawValue, let s = Section(rawValue: rawValue), s.isAvailable(in: context) else { return .bridge }
        return s
    }

    /// The ⌘-digit shortcut.
    var shortcutDigit: Character {
        switch self {
        case .bridge: "1"
        case .market: "2"
        case .shipyard: "3"
        case .outfitter: "4"
        case .crew: "5"
        case .bank: "6"
        case .galaxy: "7"
        case .quests: "8"
        case .logbook: "9"
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .bridge: "Bridge"
        case .market: "Market"
        case .shipyard: "Shipyard"
        case .outfitter: "Outfitter"
        case .crew: "Crew"
        case .bank: "Bank"
        case .galaxy: "Galaxy"
        case .quests: "Quests"
        case .logbook: "Logbook"
        }
    }

    var systemImage: String {
        switch self {
        case .bridge: "scope"
        case .market: "cart"
        case .shipyard: "airplane"
        case .outfitter: "wrench.and.screwdriver"
        case .crew: "person.3"
        case .bank: "building.columns"
        case .galaxy: "map"
        case .quests: "list.star"
        case .logbook: "book.closed"
        }
    }

    var axID: String { AXID.Sidebar.row(self) }
}
