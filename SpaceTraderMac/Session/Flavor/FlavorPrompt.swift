// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import ParsecInsights

/// LLM-016: the localized names a prompt may use, captured on the main actor for one game. Commander and ship names
/// (player input) are deliberately absent.
nonisolated struct FlavorNames: Sendable, Equatable {
    var systems: [String]
    /// Localized ship type names, indexed by `ShipType.rawValue`.
    var ships: [String] = []
    /// The language the model writes in (the app's current language, e.g. "English").
    var language: String

    static let empty = FlavorNames(systems: [], language: "English")

    func system(_ index: Int) -> String {
        systems.indices.contains(index) ? systems[index] : String(localized: "an unnamed system")
    }

    func ship(_ type: ShipType) -> String {
        ships.indices.contains(type.rawValue) ? ships[type.rawValue] : String(describing: type)
    }

    @MainActor
    static func make(state: GameState, locale: Locale = .current) -> FlavorNames {
        let code = locale.language.languageCode?.identifier ?? "en"
        let language = Locale(identifier: "en").localizedString(forLanguageCode: code) ?? "English"
        return FlavorNames(systems: state.galaxy.systems.indices.map { Names.system($0, in: state) },
                           ships: ShipType.allCases.map { String(localized: Names.ship($0)) }, language: language)
    }
}

/// LLM-016: the fixed instructions and the per-request prompt.
nonisolated enum FlavorPromptBuilder {
    static let instructions = "You write one or two short sentences for a starship captain's log in a classic space trading "
        + "game. Past tense, plain text, no lists, no numbers or names that are not given, never invent game events."

    static func prompt(for request: FlavorRequest, names: FlavorNames) -> String {
        "\(facts(request.subject, names: names)) Write the log line in \(names.language)."
    }

    static func facts(_ subject: FlavorSubject, names: FlavorNames) -> String {
        switch subject {
        case let .arrival(system, viaWormhole, firstVisit, uneventful, encounterCount):
            var s = "The ship arrived at the \(names.system(system)) system"
            s += viaWormhole ? " through a wormhole." : "."
            if firstVisit { s += " It was the first visit there." }
            s += uneventful ? " The trip was uneventful." : " There were \(encounterCount) encounters on the way."
            return s
        case let .encounter(type, opponent, result, rounds, minHullPercent):
            return "The ship met a \(badgeWord(type.badge(opponent: opponent))) \(names.ship(opponent)). "
                + "Result: \(resultWord(result)) after \(rounds) rounds of combat; the hull fell to \(minHullPercent) percent."
        case let .quest(event):
            return "The commander completed a special mission (\(questWord(event)))."
        case let .gameEnded(end):
            return "The career ended: \(endWord(end))."
        case let .achievement(id):
            return "The commander earned the distinction \"\(AchievementText.name(id))\"."
        }
    }

    private static func badgeWord(_ b: EncounterBadge) -> String {
        switch b {
        case .special: "remarkable"
        case .pirate: "pirate"
        case .alien: "alien"
        case .police: "police"
        case .trader: "trader"
        }
    }

    private static func resultWord(_ r: EncounterResultClass) -> String {
        switch r {
        case .won: "the ship won"
        case .fled: "the ship fled"
        case .surrendered: "the ship surrendered"
        case .lost: "the ship lost"
        case .other: "the encounter passed"
        }
    }

    private static func questWord(_ e: SpecialEventType) -> String {
        String(describing: e).unicodeScalars.reduce(into: "") { s, c in
            if CharacterSet.uppercaseLetters.contains(c) { s += " " }
            s += String(c).lowercased()
        }
    }

    private static func endWord(_ e: GameEndType) -> String {
        switch e {
        case .killed: "the ship was destroyed"
        case .retired: "the commander retired"
        case .boughtMoon, .boughtMoonGirl: "the commander bought a moon and retired there"
        }
    }
}

/// LLM-015: cleans model output, or rejects it.
nonisolated enum FlavorOutputValidator {
    static let maxLength = 240

    static func validate(_ raw: String) -> String? {
        var s = raw.replacingOccurrences(of: "\r\n", with: "\n")
            .split(whereSeparator: \.isNewline).joined(separator: " ")
        for mark in ["**", "__", "*", "_", "`", "\"", "\u{201C}", "\u{201D}"] {
            s = s.replacingOccurrences(of: mark, with: "")
        }
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        guard s.count > maxLength else { return s }
        let head = String(s.prefix(maxLength))
        guard let end = head.lastIndex(where: { ".!?".contains($0) }) else { return nil }
        let cut = String(head[...end]).trimmingCharacters(in: .whitespaces)
        return cut.isEmpty ? nil : cut
    }
}
