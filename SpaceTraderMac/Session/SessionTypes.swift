// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// What the main window shows. Derived from the session, never stored.
enum SessionMode: Equatable, Sendable {
    case welcome
    case playing
    case gameOver(GameEndType)

    /// `.welcome` iff no engine; `.gameOver` iff the engine's phase is game over; otherwise `.playing`.
    static func derive(from state: GameState?) -> SessionMode {
        guard let state else { return .welcome }
        if case let .gameOver(end) = state.phase { return .gameOver(end) }
        return .playing
    }
}

/// App-side feed notes that are not engine events (e.g. "Game saved.").
enum FeedNote: Equatable, Sendable {
    case gameSaved
    case recoveredFromBackup
}

/// One entry of the in-memory event feed (newest 500 kept; not persisted).
struct FeedItem: Identifiable, Equatable, Sendable {
    enum Entry: Equatable, Sendable {
        case event(GameEvent)
        case note(FeedNote)
    }

    let id: Int
    let day: Int
    let systemIndex: Int
    let entry: Entry

    /// The engine event, when the entry is one.
    var event: GameEvent? {
        if case let .event(e) = entry { return e }
        return nil
    }
}

/// An engine confirmation waiting for the player's answer, with what is needed to resend the command.
struct PendingConfirmation: Equatable, Sendable {
    var command: Command
    var confirmation: Confirmation
    /// Warnings already acknowledged for this command before this confirmation was raised.
    var acknowledged: Set<WarningID>

    /// The set to resend with when the player confirms: the earlier ones plus this one.
    var acknowledgingOnConfirm: Set<WarningID> { acknowledged.union([confirmation.warning]) }
}

/// App-layer consent dialogs (not engine warnings).
enum AppConfirmation: Equatable, Sendable {
    case discardUnsavedGame
    case revertToAutosave
    case deleteSlot(String)
    case loadImportedSave(String)
    case clearHighScores(RulesetID)
    case timewarpLoad(reloaded: Bool)
    case closeGame

    var key: String {
        switch self {
        case .discardUnsavedGame: "discardUnsavedGame"
        case .revertToAutosave: "revertToAutosave"
        case let .deleteSlot(id): "deleteSlot.\(id)"
        case let .loadImportedSave(id): "loadImportedSave.\(id)"
        case let .clearHighScores(r): "clearHighScores.\(r.rawValue)"
        case let .timewarpLoad(reloaded): "timewarpLoad.\(reloaded)"
        case .closeGame: "closeGame"
        }
    }
}

/// Non-consent alerts (failures).
enum SystemAlert: Equatable, Sendable {
    case saveFailed(reason: String)
    case openFailed(reason: String, suggestion: String?)
    case nothingToContinue

    var key: String {
        switch self {
        case .saveFailed: "saveFailed"
        case .openFailed: "openFailed"
        case .nothingToContinue: "nothingToContinue"
        }
    }
}

/// What a ship purchase review sheet is for.
enum ShipPurchaseRequest: Equatable, Sendable {
    case ship(ShipType)
    case design(ShipDesign)

    var key: String {
        switch self {
        case let .ship(t): "ship.\(t)"
        case let .design(d): "design.\(d.name)"
        }
    }
}

/// Sheets on the main window.
enum SheetRoute: Equatable, Sendable {
    case newGame
    case openSavedGame
    case gameOptions
    case findSystem
    case shipPurchase(ShipPurchaseRequest)
    /// The retire confirmation (ALR-104) is a sheet; it carries the pending confirmation to resend.
    case retire(PendingConfirmation)
    case cheatConsole
    case decision(PendingDecision)
    case encounterInterim

    var key: String {
        switch self {
        case .newGame: "newGame"
        case .openSavedGame: "openSavedGame"
        case .gameOptions: "gameOptions"
        case .findSystem: "findSystem"
        case let .shipPurchase(r): "shipPurchase.\(r.key)"
        case .retire: "retire"
        case .cheatConsole: "cheatConsole"
        case let .decision(d): "decision.\(Self.decisionKey(d))"
        case .encounterInterim: "encounterInterim"
        }
    }

    private static func decisionKey(_ d: PendingDecision) -> String {
        switch d {
        case let .confirm(c): "confirm.\(c.warning.rawValue)"
        case .tradeInOrbit: "tradeInOrbit"
        case .plunder: "plunder"
        case .scoop: "scoop"
        case .newspaper: "newspaper"
        }
    }
}

/// Everything the main window can present modally. At most one at a time; the rest wait in a FIFO queue.
enum Presentation: Identifiable, Equatable, Sendable {
    case confirmation(PendingConfirmation)
    case appConfirmation(AppConfirmation)
    case systemAlert(SystemAlert)
    case sheet(SheetRoute)

    var id: String {
        switch self {
        case let .confirmation(p): "confirmation.\(p.confirmation.warning.rawValue).\(p.acknowledged.count)"
        case let .appConfirmation(c): "appConfirmation.\(c.key)"
        case let .systemAlert(a): "systemAlert.\(a.key)"
        case let .sheet(s): "sheet.\(s.key)"
        }
    }
}

/// What to do once replacing the current game is allowed (SAV-043 / SAV-047).
enum ReplaceIntent: Equatable, Sendable {
    case newGame
    case quickStart
    case open(slotID: String)
    case closeGame
}

/// The high-score result of the ended game, as recorded by the session (SCORE-037).
enum RecordedScore: Equatable, Sendable {
    case outcome(HighScoreOutcome)
    case alreadyRecorded
    case failed
}
