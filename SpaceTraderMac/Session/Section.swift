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

/// The pages of the playing window, in dock order (UI-NAV-001). Raw values are stored (scene state) and are part of
/// the accessibility identifiers, so the cases keep their 1.x names; the titles carry the game's vocabulary.
/// The 1.x Market page is gone: trading is the Bridge's Cargo region (a stored "market" restores to the Bridge).
nonisolated enum Section: String, CaseIterable, Identifiable, Sendable {
    case bridge, shipyard, outfitter, crew, bank
    /// Commander Status (the former inspector), a page since release 2.0.
    case status
    case quests, galaxy, logbook
    /// The per-game options, a page since release 2.0 (⌥⌘O; it has no ⌘-digit).
    case options

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

    /// The ⌘-digit shortcut; nil for Options.
    var shortcutDigit: Character? {
        switch self {
        case .bridge: "1"
        case .shipyard: "2"
        case .outfitter: "3"
        case .crew: "4"
        case .bank: "5"
        case .status: "6"
        case .quests: "7"
        case .galaxy: "8"
        case .logbook: "9"
        case .options: nil
        }
    }

    /// The key cap shown on the page's dock button.
    var keyCap: String? { shortcutDigit.map { "⌘\($0)" } ?? (self == .options ? "⌥⌘O" : nil) }

    var title: LocalizedStringResource {
        switch self {
        case .bridge: "Bridge"
        case .shipyard: "Shipyard"
        case .outfitter: "Equipment"
        case .crew: "Personnel"
        case .bank: "Bank"
        case .galaxy: "Galactic Chart"
        case .quests: "Quests"
        case .logbook: "Logbook"
        case .status: "Commander Status"
        case .options: "Options"
        }
    }

    var systemImage: String {
        switch self {
        case .bridge: "scope"
        case .shipyard: "airplane"
        case .outfitter: "wrench.and.screwdriver"
        case .crew: "person.3"
        case .bank: "building.columns"
        case .galaxy: "map"
        case .quests: "list.star"
        case .logbook: "book.closed"
        case .status: "person.text.rectangle"
        case .options: "gearshape"
        }
    }

    var axID: String { AXID.Dock.button(self) }
}
