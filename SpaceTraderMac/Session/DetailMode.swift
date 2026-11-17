// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// UI-ENC-001: what the main window's detail area shows. Derived, never stored.
enum DetailMode: Equatable, Sendable {
    case transit(TransitPlayback)
    case encounter
    case gameOver(GameEndType)
    case section(Section)

    /// A running playback wins; then the engine phase; a resting `.inTransit` phase (only reachable from a hand-edited
    /// save) shows a frozen playback at its click (UI-ENC-013).
    static func derive(state: GameState?, playback: TransitPlayback?, selected: Section) -> DetailMode {
        if let playback { return .transit(playback) }
        guard let state else { return .section(selected) }
        switch state.phase {
        case .encounter: return .encounter
        // LOG-035: an ended game shows its card, or the Logbook when the player chose "Show Logbook".
        case let .gameOver(end): return selected == .logbook ? .section(.logbook) : .gameOver(end)
        case let .inTransit(t): return .transit(.frozen(t))
        case .docked: return .section(selected)
        }
    }
}
