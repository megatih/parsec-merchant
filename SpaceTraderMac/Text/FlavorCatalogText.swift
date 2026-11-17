// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import ParsecInsights

/// LLM-011: localized text of template flavor lines; generated prose is shown as stored.
@MainActor
enum FlavorCatalogText {
    static func text(for flavor: FlavorText?, state: GameState) -> String? {
        switch flavor {
        case nil: nil
        case let .generated(text): text
        case let .template(line): text(for: line, state: state)
        }
    }

    static func text(for line: FlavorLine, state: GameState) -> String {
        line.key
    }
}
