// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import ParsecInsights

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
    /// ACH-016: an achievement newly added to the app-wide store.
    case achievementUnlocked(AchievementID)
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
    /// ACH-021: Settings › Advanced › Reset Achievements.
    case resetAchievements

    var key: String {
        switch self {
        case .discardUnsavedGame: "discardUnsavedGame"
        case .revertToAutosave: "revertToAutosave"
        case let .deleteSlot(id): "deleteSlot.\(id)"
        case let .loadImportedSave(id): "loadImportedSave.\(id)"
        case let .clearHighScores(r): "clearHighScores.\(r.rawValue)"
        case let .timewarpLoad(reloaded): "timewarpLoad.\(reloaded)"
        case .closeGame: "closeGame"
        case .resetAchievements: "resetAchievements"
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

/// Sheets on the main window (UI-SHELL-005, UI-ENC-002).
enum SheetRoute: Equatable, Sendable {
    case newGame
    case openSavedGame
    case findSystem
    case shipPurchase(ShipPurchaseRequest)
    /// The retire confirmation (ALR-104) is a sheet; it carries the pending confirmation to resend.
    case retire(PendingConfirmation)
    case cheatConsole
    /// UI-ENC-047: the trade-in-orbit offer (ECO-081).
    case tradeInOrbit(OrbitTradeOffer)
    /// UI-ENC-045: plunder the victim's hold (an opponent, or the Marie Celeste after boarding).
    case plunder(PlunderSheetContext)
    /// UI-ENC-071: the styled newspaper.
    case newspaper(Newspaper)
    /// UI-ENC-074: a special event's offer or result page.
    case narrative(NarrativePage)
    /// UI-ENC-058: the arrival, arrest, escape-pod or reactor report.
    case report(ReportSheet)
    /// UI-ENC-092: the Debug developer tester (CHEAT-038).
    case developerTester
    /// UI-BRG-008: "Why this price?" and the price history of one good.
    case priceDetails(TradeItemType)
    /// UI-SHELL-065: the quantity to dump or jettison.
    case cargoDisposal(CargoDisposal)
    /// PRD §4.2: a partial fuel or repair purchase (Trade › Buy Fuel…, Repair…).
    case serviceAmount(DockServiceModel.Kind)

    var key: String {
        switch self {
        case .newGame: "newGame"
        case .openSavedGame: "openSavedGame"
        case .findSystem: "findSystem"
        case let .shipPurchase(r): "shipPurchase.\(r.key)"
        case .retire: "retire"
        case .cheatConsole: "cheatConsole"
        case .tradeInOrbit: "tradeInOrbit"
        case let .plunder(c): "plunder.\(c.source.rawValue)"
        case .newspaper: "newspaper"
        case let .narrative(page): "narrative.\(page.key)"
        case let .report(r): "report.\(r.kind.rawValue)"
        case .developerTester: "developerTester"
        case let .priceDetails(item): "priceDetails.\(item)"
        case let .cargoDisposal(d): "cargoDisposal.\(d.id)"
        case let .serviceAmount(kind): "serviceAmount.\(kind)"
        }
    }
}

/// Everything the main window can present modally. At most one at a time; the rest wait in a FIFO queue.
enum Presentation: Identifiable, Equatable, Sendable {
    case confirmation(PendingConfirmation)
    case appConfirmation(AppConfirmation)
    case systemAlert(SystemAlert)
    case sheet(SheetRoute)
    /// UI-ENC-049: the scoop question (ALR-070/071), a confirmation dialog.
    case scoop(TradeItemType)

    var id: String {
        switch self {
        case let .confirmation(p): "confirmation.\(p.confirmation.warning.rawValue).\(p.acknowledged.count)"
        case let .appConfirmation(c): "appConfirmation.\(c.key)"
        case let .systemAlert(a): "systemAlert.\(a.key)"
        case let .sheet(s): "sheet.\(s.key)"
        case let .scoop(item): "scoop.\(item)"
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
