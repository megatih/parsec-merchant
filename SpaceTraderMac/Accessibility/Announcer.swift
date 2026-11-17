// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import ParsecInsights
import SwiftUI

/// The speech priority of an announcement (A11Y-011).
nonisolated enum AnnouncementPriority: Equatable, Sendable {
    case normal
    /// Combat outcomes, arrests and game over.
    case high
}

/// One announcement: the joined texts of a step and its priority.
nonisolated struct Announcement: Equatable, Sendable {
    var text: String
    var priority: AnnouncementPriority
}

/// Posts VoiceOver announcements (A11Y-011, generalizing UI-ENC-025). The app posts
/// `AccessibilityNotification.Announcement`; tests record. macOS has no live-region modifier (UX-VISION §9).
@MainActor
protocol Announcer {
    func announce(_ text: String, priority: AnnouncementPriority)
}

/// UI-ENC-025's name for the same protocol.
typealias EncounterAnnouncer = Announcer

/// Posts the announcement with `accessibilitySpeechAnnouncementPriority` (A11Y-011).
struct VoiceOverAnnouncer: Announcer {
    func announce(_ text: String, priority: AnnouncementPriority) {
        var s = AttributedString(text)
        s.accessibilitySpeechAnnouncementPriority = priority == .high ? .high : .default
        AccessibilityNotification.Announcement(s).post()
    }
}

/// Builds the one announcement of a step (A11Y-011, A11Y-012). Pure.
enum AnnouncementText {
    /// What the session knows about the step beyond the record.
    struct Context: Equatable, Sendable {
        /// The step's new combat-log rows, joined (UI-ENC-025).
        var combat: String?
        /// The encounter intro sentence when the step interrupted the transit (UI-ENC-016).
        var intro: String?
        /// The arrival card or sheet has sections or encounters.
        var reportAvailable = false
        /// The command came from the keyboard or a menu (clicked buttons whose result shows in place do not announce).
        var fromKeyboard = false
        /// Extra texts raised by the step (achievement unlocks).
        var extras: [String] = []
    }

    static func make(step: StepRecord, before: GameState, after: GameState, context: Context) -> Announcement? {
        var parts: [String] = []
        var high = false
        if let combat = context.combat, !combat.isEmpty { parts.append(combat) }
        for e in step.events {
            switch e {
            case let .boughtCargo(item, quantity, total) where context.fromKeyboard:
                parts.append(String(localized: "Bought \(quantity) \(Names.item(item)) for \(total) credits."))
            case let .soldCargo(item, quantity, total, _) where context.fromKeyboard:
                parts.append(String(localized: "Sold \(quantity) \(Names.item(item)) for \(total) credits."))
            case .boughtFuel where context.fromKeyboard:
                parts.append(String(localized: "Refuelled, \(after.commander.ship.fuel) of \(after.fuelCapacity)."))
            case .repairedHull where context.fromKeyboard:
                parts.append(String(localized: "Hull repaired, \(hullPercent(after)) percent."))
            case let .arrived(system):
                parts.append(String(localized: "Arrived at \(Names.system(system, in: after)), day \(after.commander.days)."))
                if context.reportAvailable { parts.append(String(localized: "Arrival report available.")) }
            case .encounterStarted:
                if let intro = context.intro { parts.append(intro) }
            case .playerDestroyed, .bothDestroyed, .opponentDestroyed, .opponentDisabled, .playerEscaped, .opponentEscaped:
                high = true
            case let .arrested(term, _, _):
                high = true
                parts.append(String(localized: "Arrested. Sentenced to \(term) days."))
            case let .gameEnded(end, score):
                high = true
                parts.append(String(localized: "\(Names.ending(end)) Score \(score)."))
            default:
                break
            }
        }
        parts.append(contentsOf: context.extras)
        guard !parts.isEmpty else { return nil }
        return Announcement(text: parts.joined(separator: " "), priority: high ? .high : .normal)
    }

    static func rejection(_ error: CommandError) -> String { ReasonText.string(for: error) }
    static var saved: String { String(localized: "Game saved.") }
    static var exported: String { String(localized: "Game exported.") }
    static func achievement(_ id: AchievementID) -> String {
        String(localized: "Achievement unlocked: \(AchievementText.name(id)).")
    }

    static func hullPercent(_ state: GameState) -> Int {
        let ship = state.commander.ship
        let strength = ship.hullStrength(state.ruleset)
        return strength > 0 ? ship.hull * 100 / strength : 0
    }
}
