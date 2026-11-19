// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// Warp's enablement and help tag: the cost breakdown, or the blocking reason.
struct WarpButtonModel: Equatable {
    var isEnabled: Bool
    var help: String

    /// Enablement comes from `MenuRules.warp` (MENU-004/030), shared with Game › Warp and the Bridge.
    static func make(state: GameState?, isModal: Bool) -> WarpButtonModel {
        let availability = MenuRules.warp(MenuContext.make(state: state, isModal: isModal))
        guard availability.isEnabled, let state else {
            return WarpButtonModel(isEnabled: false, help: availability.reason?.text ?? DisabledReason.notDocked.text)
        }
        let c = state.warpTargetPreview(state.warpSystem).costs
        let help = String(localized: """
            Mercenaries \(c.mercenaries.formatted()) cr., insurance \(c.insurance.formatted()) cr., \
            interest \(c.interest.formatted()) cr., wormhole tax \(c.wormholeTax.formatted()) cr. Total \(c.total.formatted()) cr.
            """)
        return WarpButtonModel(isEnabled: true, help: help)
    }
}
