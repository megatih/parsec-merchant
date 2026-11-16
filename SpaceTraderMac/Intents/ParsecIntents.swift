// SPDX-License-Identifier: GPL-2.0-or-later
import AppIntents
import AppKit
import Foundation
import ParsecEngine
import ParsecPersistence

/// The commander status read by the "Show Commander Status" intent (UI-SHELL-114).
nonisolated struct CommanderStatus: Equatable, Sendable {
    var name: String
    var day: Int
    var system: String
    var cash: Int
    var debt: Int
    var worth: Int

    init(_ state: GameState) {
        name = state.commander.name
        day = state.commander.days
        system = state.systemName(state.commander.currentSystem)
        cash = state.commander.cash
        debt = state.commander.debt
        worth = state.worth
    }

    var dialogText: String {
        String(localized: """
            Commander \(name), day \(day), at \(system). \(cash.formatted()) credits, debt \(debt.formatted()), \
            worth \(worth.formatted()).
            """)
    }

    static var noSaveText: String { String(localized: "No saved game yet.") }
}

/// UI-SHELL-114: the loaded game's status, else the status of the save Continue would pick. Never loads for play, so
/// `reloadCount` and the slot files are untouched.
nonisolated enum CommanderStatusQuery {
    static func current(store: SlotStore, loaded: GameState?) -> CommanderStatus? {
        if let loaded { return CommanderStatus(loaded) }
        guard let slots = try? store.list(),
              let candidate = GameSession.continueCandidate(in: slots),
              let envelope = try? store.load(slot: candidate.id) else { return nil }
        return CommanderStatus(envelope.state)
    }

    @MainActor
    static func current(store: SlotStore, session: GameSession?) -> CommanderStatus? {
        current(store: store, loaded: session?.state)
    }
}

/// What "Continue Game" did (UI-SHELL-113).
nonisolated enum ContinueOutcome: Equatable, Sendable {
    case alreadyLoaded
    case continued
    case nothingToContinue

    var dialogText: String? {
        switch self {
        case .alreadyLoaded, .continued: nil
        case .nothingToContinue: String(localized: "There's no game to continue.")
        }
    }
}

extension GameSession {
    /// UI-SHELL-113: with a game loaded it only brings it forward; otherwise it performs Welcome › Continue. It never
    /// discards an unsaved game.
    func continueFromIntent() -> ContinueOutcome {
        if engine != nil { return .alreadyLoaded }
        return continueGame() ? .continued : .nothingToContinue
    }
}

/// The app's one session, as App Intents see it (set by `AppDelegate` at launch, before any intent can run).
@MainActor
enum IntentSessionBridge {
    static weak var session: GameSession?
}

/// Brings the main window forward (or lets SwiftUI reopen it through the Dock-reopen path).
@MainActor
enum MainWindowActivator {
    static func activate() {
        NSApp.activate()
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(SceneMetrics.mainWindowID) == true }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

/// "Continue Game" (UI-SHELL-112/113): runs in the foreground.
nonisolated struct ContinueGameIntent: AppIntent {
    static let title: LocalizedStringResource = "Continue Game"
    static let description = IntentDescription("Opens Parsec Merchant and continues your latest game.")
    static var supportedModes: IntentModes { .foreground }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = await MainActor.run {
            MainWindowActivator.activate()
            return IntentSessionBridge.session?.continueFromIntent().dialogText ?? ""
        }
        return .result(dialog: "\(text)")
    }
}

/// "Show Commander Status" (UI-SHELL-112/114): runs in the background and changes nothing.
nonisolated struct ShowCommanderStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Commander Status"
    static let description = IntentDescription("Tells you your commander's day, location, cash, debt and worth.")
    static var supportedModes: IntentModes { .background }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = await MainActor.run {
            guard let session = IntentSessionBridge.session else { return CommanderStatus.noSaveText }
            return CommanderStatusQuery.current(store: session.slotStore, session: session)?.dialogText ?? CommanderStatus.noSaveText
        }
        return .result(dialog: "\(text)")
    }
}

/// One phrase per intent, each with the application name (UI-SHELL-112).
nonisolated struct ParsecShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ContinueGameIntent(), phrases: ["Continue my \(.applicationName) game"],
                    shortTitle: "Continue Game", systemImageName: "play.fill")
        AppShortcut(intent: ShowCommanderStatusIntent(), phrases: ["Show my \(.applicationName) commander status"],
                    shortTitle: "Commander Status", systemImageName: "person.text.rectangle")
    }
}
