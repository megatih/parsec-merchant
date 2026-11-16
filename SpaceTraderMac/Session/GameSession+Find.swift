// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// What the Find text did (CHEAT-013). The Find System sheet calls `submitFind(_:)` and performs `.search` itself.
enum FindOutcome: Equatable, Sendable {
    /// A normal system search for the text.
    case search(String)
    /// A cheat code was sent to the engine.
    case cheatSent
    /// `Cheetah` (or Palm `Cheetah`): the cheat console opened.
    case openedConsole
    /// Palm "Very rare": the console opened (its very-rare form is a later addition).
    case openedVeryRareForm
    /// Palm "Timewarp" (CHEAT-046).
    case timewarp
    /// Nothing happened (empty Palm text, or no game).
    case none
}

extension GameSession {
    /// CHEAT-013: parses the Find text with `FindInput.parse` and acts on it. Dismiss the Find sheet before calling, so
    /// a console or confirmation it opens is shown at once (one presentation at a time).
    @discardableResult
    func submitFind(_ text: String) -> FindOutcome {
        guard let state else { return .none }
        guard let input = FindInput.parse(text, cheatSet: state.ruleset.content.cheatSet, cheatsEnabled: state.cheatsUsed) else {
            return .none
        }
        switch input {
        case let .search(s):
            return .search(s)
        case .cheat(.enable):
            send(.cheat(.enable))
            present(.sheet(.cheatConsole))
            return .openedConsole
        case let .cheat(code):
            send(.cheat(code))
            return .cheatSent
        case .palmVeryRareForm:
            present(.sheet(.cheatConsole))
            return .openedVeryRareForm
        case .timewarp:
            requestTimewarp()
            return .timewarp
        }
    }

    /// CHEAT-046: Palm "Timewarp". Refused in an Ironman game; otherwise warns (first reload) or asks, then opens the
    /// Open sheet.
    func requestTimewarp() {
        guard let state else { return }
        if state.ironman {
            present(.systemAlert(.openFailed(reason: String(localized: "Timewarp isn't available in an Ironman game."),
                                             suggestion: String(localized: "An Ironman game has a single save and no reloading."))))
            return
        }
        present(.appConfirmation(.timewarpLoad(reloaded: state.reloadCount > 0)))
    }
}
