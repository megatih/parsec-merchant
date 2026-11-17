// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// What the interim newspaper sheet shows (UI-SHELL-058; replaced by the UI-ENC newspaper). Trade, plunder and scoop moved
/// to `TradeOfferModel`, `PlunderSheetModel` and `ScoopDialogModel` (UI-ENC-046, -048, -049). Pure.
enum InterimDecisionModel {
    /// Newspaper: one plain line per headline after the masthead.
    static func newspaperLines(_ paper: Newspaper, state: GameState) -> [LocalizedStringResource] {
        paper.headlines.map { NewspaperText.interimLine($0, state: state) }
    }
}
