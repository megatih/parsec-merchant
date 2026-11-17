// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// Text of the game-over card and the career card (UI-ENC-082/083).
enum CareerText {
    /// The cause line of a `killed` ending ("Your ship was destroyed by the pirate Hornet.").
    static func cause(_ cause: GameOverCause) -> String {
        switch cause {
        case .reactorMeltdown:
            return String(localized: "Your ship was destroyed when the reactor melted down.")
        case let .destroyedBy(badge, ship):
            let s = String(localized: Names.ship(ship))
            switch badge {
            case .pirate: return String(localized: "Your ship was destroyed by the pirate \(s).")
            case .police: return String(localized: "Your ship was destroyed by the police \(s).")
            case .trader: return String(localized: "Your ship was destroyed by the trader \(s).")
            case .alien: return String(localized: "Your ship was destroyed by the alien \(s).")
            case .special: return String(localized: "Your ship was destroyed by the \(s).")
            }
        }
    }

    /// "You achieved a score of X.Y%" (SCORE-015).
    static func score(_ scoreText: String) -> String {
        String(localized: "You achieved a score of \(scoreText).")
    }

    /// The share preview title (UI-ENC-085).
    static func shareTitle(commander: String) -> String {
        String(localized: "Parsec Merchant — \(commander)")
    }

    /// The ship line: "Gnat “Rocinante”" or just the type.
    static func ship(_ card: CareerCard) -> String {
        let type = String(localized: Names.ship(card.shipType))
        guard let name = card.shipName, !name.isEmpty else { return type }
        return String(localized: "\(type) “\(name)”")
    }

    /// The badges as words, in card order.
    static func badges(_ card: CareerCard) -> [String] {
        var out = HighScoreOutcomeText.markers(ironman: card.ironman, reloaded: card.reloaded)
        if card.cheatsUsed { out.append(String(localized: "Cheats used")) }
        return out
    }
}
