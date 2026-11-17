// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// UI-ENC-092 / CHEAT-038: the Debug developer tester (C# `FormTest`). It previews every ALR presentation and every
/// special-event narrative page with fixture values. Previews render inside the tester, so no button of a preview can
/// send a command: the game state is never touched.
enum DeveloperTester {
    /// `.cheat(.test)` opens the tester in Debug builds; Release builds only show the console (CHEAT-038).
    static func opens(after command: Command, isDebug: Bool = LaunchOptions.isDebugBuild) -> Bool {
        isDebug && command == .cheat(.test)
    }

    /// What the tester lists.
    enum Item: Hashable, Sendable {
        case alr(Int)
        case narrative(SpecialEventType)
    }

    static var items: [Item] {
        ALRCatalog.rows.map { .alr($0.number) } + SpecialEventType.allCases.map(Item.narrative)
    }
}

/// One preview of the developer tester: a dialog-like card with the real text of the presentation.
struct TesterSample: Equatable, Sendable {
    /// The kind of surface ("Confirmation", "Inline reason", …).
    var surface: String
    var title: String
    var message: String
    /// Button labels as the real presentation shows them (inert in the tester).
    var buttons: [String] = []
    var isDestructive = false
}

extension ALRCatalog {
    /// UI-ENC-092: the fixture presentation of a row (the same fixtures as the UI-ENC-004 coverage test).
    static func sample(for row: ALRRow, state: GameState, session: GameSession) -> TesterSample {
        switch row.presentation {
        case let .inlineReason(error):
            return TesterSample(surface: String(localized: "Inline reason"), title: row.alertType,
                                message: String(localized: ReasonText.text(for: error)))
        case let .previewNote(note):
            return TesterSample(surface: String(localized: "Preview note"), title: row.alertType, message: note.rawValue)
        case let .confirmation(warning):
            let c = ConfirmationText.content(for: Confirmation(warning, amounts: [100, 50]), state: state)
            return TesterSample(surface: String(localized: "Confirmation"), title: c.title, message: c.message,
                                buttons: [c.confirmLabel, String(localized: "Cancel")], isDestructive: c.isDestructive)
        case .transferOption:
            return TesterSample(surface: String(localized: "Purchase sheet option"), title: row.alertType,
                                message: String(localized: "Transfer equipment to the new ship"))
        case let .decision(kind):
            return TesterSample(surface: String(localized: "Decision sheet"), title: row.alertType, message: kind.rawValue)
        case let .appConfirmation(kind):
            let c = AppConfirmationText.content(for: kind.sample, session: session)
            return TesterSample(surface: String(localized: "App confirmation"), title: c.title, message: c.message,
                                buttons: [c.confirmLabel, String(localized: "Cancel")], isDestructive: c.isDestructive)
        case let .event(_, surfaces):
            let event = sampleEvent(for: row)
            return TesterSample(surface: surfaces.map(\.rawValue).sorted().joined(separator: ", "), title: row.alertType,
                                message: event.map { String(localized: EventText.text(for: $0, state: state)) } ?? "")
        case let .narrative(key):
            let titles: [String] = if case let .specialEventResult(types) = key {
                types.map { String(localized: SpecialEventText.title($0)) }
            } else { [] }
            return TesterSample(surface: String(localized: "Narrative"), title: titles.first ?? row.alertType,
                                message: String(localized: EventText.text(for: key.sampleEvent, state: state)),
                                buttons: [String(localized: "Continue")])
        case let .highScoreOutcome(kind):
            return TesterSample(surface: String(localized: "Game-over card"), title: row.alertType,
                                message: HighScoreOutcomeText.text(for: kind.sample))
        case let .systemAlert(kind):
            return TesterSample(surface: String(localized: "System alert"), title: SystemAlertText.title(kind.sample),
                                message: SystemAlertText.message(kind.sample), buttons: [String(localized: "OK")])
        case let .removed(replacement):
            return TesterSample(surface: String(localized: "Removed"), title: row.alertType,
                                message: String(describing: replacement))
        }
    }

    /// A special event's narrative offer page with its real title and story.
    static func narrativeSample(_ type: SpecialEventType) -> TesterSample {
        TesterSample(surface: String(localized: "Narrative"), title: String(localized: SpecialEventText.title(type)),
                     message: String(localized: SpecialEventText.story(type)),
                     buttons: [String(localized: "Accept"), String(localized: "Decline")])
    }
}
