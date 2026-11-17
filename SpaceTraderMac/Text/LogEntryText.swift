// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import ParsecInsights

/// LOG-023: localized text of every log entry kind.
@MainActor
enum LogEntryText {
    static func text(for entry: LogEntry, journal: GameJournal, state: GameState) -> String {
        switch entry.kind {
        case .journalStarted: String(localized: "The log begins.")
        case .cheatsEnabled: String(localized: "Cheats were enabled for this game.")
        case let .gameEnded(end, score): String(localized: "\(String(localized: Names.ending(end))) Score: \(score).")
        case let .achievementUnlocked(id): String(localized: "Achievement unlocked: \(AchievementText.name(id))")
        case let .trade(t): String(localized: "Traded \(t.quantity) \(String(localized: Names.item(t.item))).")
        case let .encounter(r): String(localized: "Encounter with a \(String(localized: Names.ship(r.opponent))).")
        }
    }

    /// LOG-031: the expanded encounter row: outcome, rounds and lowest hull.
    static func encounterDetails(_ r: EncounterRecord) -> String {
        String(localized: "\(r.rounds) rounds · lowest hull \(r.minHullPercent)%")
    }
}
