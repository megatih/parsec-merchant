// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// LOG-035 / STAT-020: when the buttons that open the Logbook from elsewhere are enabled.
enum LogbookLinks {
    /// LOG-035: the feed overlay's "Show Logbook" is disabled while the encounter lock applies (an encounter, a transit
    /// playback or anything presented).
    static func feedShowLogbookEnabled(state: GameState, inputLocked: Bool) -> Bool {
        guard !inputLocked else { return false }
        switch state.phase {
        case .docked, .gameOver: return true
        case .encounter, .inTransit: return false
        }
    }

    /// STAT-020: the inspector's "Show Statistics" needs the Logbook to be available and no lock.
    static func showStatisticsEnabled(sectionContext: SectionContext, inputLocked: Bool) -> Bool {
        Section.logbook.isAvailable(in: sectionContext) && !inputLocked
    }
}
