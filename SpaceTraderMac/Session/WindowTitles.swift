// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// The main window's title and subtitle (UI-SHELL-042, UI-NAV-007). Pure. The title names the commander (never the app,
/// as the HIG asks); the subtitle names the page. Cash, day and system are in the status bar.
enum WindowTitles {
    static func make(state: GameState?, page: Section = .bridge) -> (title: String, subtitle: String?) {
        guard let state else { return (String(localized: "Parsec Merchant"), nil) }
        let commander = state.commander.name
        let title: String
        if let ship = state.commander.shipName, !ship.isEmpty {
            title = String(localized: "Cmdr. \(commander) · “\(ship)”")
        } else {
            title = String(localized: "Cmdr. \(commander)")
        }
        let subtitle: String
        switch state.phase {
        case .docked: subtitle = String(localized: page.title)
        case .inTransit: subtitle = String(localized: "In Transit")
        case .encounter: subtitle = String(localized: "Encounter")
        case .gameOver: subtitle = String(localized: "Game Over")
        }
        return (title, subtitle)
    }
}
