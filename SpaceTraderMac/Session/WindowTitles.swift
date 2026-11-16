// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// The main window's title and subtitle (UI-SHELL-042). Pure; numbers are locale-formatted.
enum WindowTitles {
    static func make(state: GameState?) -> (title: String, subtitle: String?) {
        let app = String(localized: "Parsec Merchant")
        guard let state else { return (app, nil) }
        var title = String(localized: "Parsec Merchant — Cmdr. \(state.commander.name)")
        if let ship = state.commander.shipName, !ship.isEmpty {
            title += String(localized: " · “\(ship)”")
        }
        let days = state.commander.days.formatted()
        let subtitle: String
        switch state.phase {
        case .docked:
            let system = Names.system(state.commander.currentSystem, in: state)
            subtitle = String(localized: "Day \(days) · \(system) · Credits \(state.commander.cash.formatted()) · Debt \(state.commander.debt.formatted())")
        case .inTransit, .encounter:
            let dest = state.transitPreview.map { Names.system($0.destination, in: state) } ?? ""
            subtitle = String(localized: "Day \(days) · In transit to \(dest)")
        case .gameOver:
            subtitle = String(localized: "Day \(days) · Game over")
        }
        return (title, subtitle)
    }
}
