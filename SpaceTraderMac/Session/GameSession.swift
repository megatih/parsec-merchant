// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Observation
import os
import ParsecEngine
import ParsecPersistence

/// The one session of the app (UI-SHELL-001). Owns the engine and all presentation state; views read it and call its
/// methods. No view keeps a `GameEngine` or `GameState` copy beyond a render.
@Observable @MainActor
final class GameSession {
    static let feedLimit = 500
    static let defaultCommanderName = "Jameson"

    // MARK: Game
    private(set) var engine: GameEngine?
    private(set) var gameID: String?
    var currentSlotID: String?
    var lastManualSaveDays = 0

    // MARK: Presentation
    private(set) var feed: [FeedItem] = []
    private(set) var presentation: Presentation?
    private(set) var pendingPresentations: [Presentation] = []
    var selectedSection: Section = .bridge
    var marketSelection: TradeItemType?
    /// Find System's "Track this system" toggle, remembered for the session as in C# (UI-SHELL-085).
    var findTrackSystem = false
    /// The last rejected command's reason, shown briefly in the status bar (UI-SHELL-045).
    private(set) var lastRejection: CommandError?
    /// Bumped on every rejection so views can restart their 4-second timer even for a repeated error.
    private(set) var rejectionSerial = 0
    /// The high-score result of the current ended game (UI-SHELL-097).
    private(set) var recordedScore: RecordedScore?
    /// What to do after the player agrees to discard the unsaved game (SAV-043).
    private(set) var pendingReplace: ReplaceIntent?
    /// File panels requested by menus or Welcome; the view that owns `fileImporter`/`fileExporter` binds to these.
    var isImporterPresented = false
    var isExporterPresented = false

    // MARK: Services
    let slotStore: SlotStore
    let highScoreStore: HighScoreStore
    let audio: any SessionAudio
    let haptics: any SessionHaptics
    let achievements: any SessionAchievements
    let flavor: any SessionFlavor
    let launchOptions: LaunchOptions
    let defaults: UserDefaults

    @ObservationIgnored private var nextFeedID = 0
    @ObservationIgnored let log = Logger(subsystem: "io.github.megatih.ParsecMerchant", category: "session")

    init(stores: SessionStores, launchOptions: LaunchOptions = .none, defaults: UserDefaults = .standard,
         audio: any SessionAudio = SilentAudio(), haptics: any SessionHaptics = NoHaptics(),
         achievements: any SessionAchievements = NoAchievements(), flavor: any SessionFlavor = TemplateFlavor()) {
        slotStore = stores.slotStore
        highScoreStore = stores.highScoreStore
        self.launchOptions = launchOptions
        self.defaults = defaults
        self.audio = audio
        self.haptics = haptics
        self.achievements = achievements
        self.flavor = flavor
    }

    // MARK: Derived state

    /// The current game state (read it during a render; never store it).
    var state: GameState? { engine?.state }
    var mode: SessionMode { SessionMode.derive(from: engine?.state) }
    /// True while anything is presented; menus disable game commands (MENU-006).
    var isModal: Bool { presentation != nil }
    var sectionContext: SectionContext { SectionContext.make(state: engine?.state) }
    var isDocked: Bool { engine?.state.phase == .docked }

    // MARK: Commands (UI-SHELL-003/004)

    /// Performs a command synchronously and applies the result.
    func send(_ command: Command) {
        send(command, acknowledging: [])
    }

    /// Performs a command with warnings already acknowledged (e.g. the ship purchase review sends `[.buyShip]`).
    func send(_ command: Command, acknowledging: Set<WarningID>) {
        guard var engine else { return }
        let before = engine.state.phase
        let result = engine.perform(command, acknowledging: acknowledging)
        self.engine = engine
        apply(result, command: command, acknowledged: acknowledging, phaseBefore: before)
    }

    /// Handles a step result: rejection, confirmation, other decisions, feed, persistence and high scores.
    func apply(_ result: StepResult, command: Command, acknowledged: Set<WarningID>, phaseBefore: GamePhase) {
        guard let state = engine?.state else { return }
        if let rejection = result.rejection {
            lastRejection = rejection
            rejectionSerial += 1
            return
        }
        lastRejection = nil
        if let decision = result.decision {
            present(PresentationRouter.route(decision, state: state, command: command, acknowledged: acknowledged))
        }
        let isConfirmationRequest = if case .confirm = result.decision, result.events.isEmpty { true } else { false }
        guard !isConfirmationRequest else { return }
        appendToFeed(result.events.map(FeedItem.Entry.event), state: state)
        audio.play(events: result.events)
        haptics.perform(events: result.events)
        achievements.observe(events: result.events, state: state)
        let arrived = result.events.contains { if case .arrived = $0 { true } else { false } }
        runPersistenceTriggers(phaseBefore: phaseBefore, state: state, arrived: arrived)
    }

    /// The player confirmed: resend the same command with every warning acknowledged so far plus this one.
    func confirm(_ pending: PendingConfirmation) {
        dismissPresentation()
        send(pending.command, acknowledging: pending.acknowledgingOnConfirm)
    }

    /// The player cancelled a dialog: drop the command; nothing changes.
    func cancel() {
        pendingReplace = nil
        dismissPresentation()
    }

    // MARK: Presentation queue (UI-SHELL-005)

    func present(_ p: Presentation) {
        if presentation == nil {
            presentation = p
        } else {
            pendingPresentations.append(p)
        }
    }

    /// Dismisses the current presentation and shows the next queued one.
    func dismissPresentation() {
        presentation = pendingPresentations.isEmpty ? nil : pendingPresentations.removeFirst()
    }

    /// Dismisses only if `id` is still the one shown (SwiftUI resets bindings after button actions already ran).
    func dismissPresentation(ifCurrent id: String) {
        if presentation?.id == id { cancel() }
    }

    // MARK: Feed (UI-SHELL-008)

    func appendNote(_ note: FeedNote) {
        guard let state else { return }
        appendToFeed([.note(note)], state: state)
    }

    private func appendToFeed(_ entries: [FeedItem.Entry], state: GameState) {
        guard !entries.isEmpty else { return }
        for e in entries {
            feed.append(FeedItem(id: nextFeedID, day: state.commander.days, systemIndex: state.commander.currentSystem, entry: e))
            nextFeedID += 1
        }
        if feed.count > Self.feedLimit { feed.removeFirst(feed.count - Self.feedLimit) }
    }

    // MARK: Starting and replacing games

    /// UI-SHELL-020: the seed for a new game (the `-PMSeed` value, else a fresh random one).
    func newGameSeed() -> UInt64 {
        if let seed = launchOptions.seed { return seed }
        var g = SystemRandomNumberGenerator()
        return UInt64.random(in: .min ... .max, using: &g)
    }

    var lastCommanderName: String {
        let stored = defaults.string(forKey: DefaultsKey.lastCommanderName) ?? ""
        return stored.trimmingCharacters(in: .whitespaces).isEmpty ? Self.defaultCommanderName : stored
    }

    /// UI-SHELL-019: the Quick Start configuration (Modern, Normal, 5/5/5/5, not Ironman).
    func quickStartConfig() -> NewGameConfig {
        NewGameConfig(commanderName: lastCommanderName, difficulty: .normal, skills: [5, 5, 5, 5], ruleset: .modern,
                      seed: newGameSeed(), ironman: false, shipName: nil,
                      options: OptionsTemplate.load(for: .modern, defaults: defaults))
    }

    /// UI-SHELL-030/033: Quick Start and the wizard's Start converge here. Returns the validation error, if any.
    @discardableResult
    func startNewGame(_ config: NewGameConfig) -> CommandError? {
        switch GameEngine.newGame(config) {
        case let .failure(error):
            return error
        case let .success(newEngine):
            let id = SlotStore.newSlotID()
            install(newEngine, gameID: id, slotID: config.ironman ? id : nil)
            appendToFeed([.event(.gameStarted(ruleset: config.ruleset, seed: config.seed))], state: newEngine.state)
            defaults.set(config.commanderName, forKey: DefaultsKey.lastCommanderName)
            writeCreationSave()
            return nil
        }
    }

    /// Makes `engine` the current game and resets the per-game presentation state.
    func install(_ newEngine: GameEngine, gameID id: String, slotID: String?) {
        engine = newEngine
        gameID = id
        currentSlotID = slotID
        lastManualSaveDays = newEngine.state.commander.days
        feed = []
        lastRejection = nil
        recordedScore = nil
        marketSelection = nil
        selectedSection = .bridge
        if case let .gameOver(end) = newEngine.state.phase { recordHighScore(end: end) }
    }

    /// SAV-043: whether replacing the current game needs the discard confirmation.
    var needsDiscardConfirmation: Bool {
        guard let state else { return false }
        if state.ironman { return false }
        if case .gameOver = state.phase { return false }
        return state.commander.days != lastManualSaveDays
    }

    /// Runs `intent` after SAV-043 (asks to discard) or SAV-047 (writes the Ironman slot first).
    func replaceGame(then intent: ReplaceIntent) {
        if state?.ironman == true { writeIronmanSlot() }
        if needsDiscardConfirmation {
            pendingReplace = intent
            present(.appConfirmation(.discardUnsavedGame))
        } else {
            perform(intent)
        }
    }

    func requestNewGame() { replaceGame(then: .newGame) }
    func requestQuickStart() { replaceGame(then: .quickStart) }
    func requestCloseGame() { replaceGame(then: .closeGame) }
    func requestOpen(slotID: String) { replaceGame(then: .open(slotID: slotID)) }
    func requestImport() { isImporterPresented = true }
    func requestExport() { isExporterPresented = true }

    private func perform(_ intent: ReplaceIntent) {
        switch intent {
        case .newGame: present(.sheet(.newGame))
        case .quickStart: startNewGame(quickStartConfig())
        case .closeGame: closeGame()
        case let .open(slotID): openSlot(slotID)
        }
    }

    /// UI-SHELL-095: back to Welcome; clears the game, ids and feed.
    func closeGame() {
        engine = nil
        gameID = nil
        currentSlotID = nil
        lastManualSaveDays = 0
        feed = []
        lastRejection = nil
        recordedScore = nil
        selectedSection = .bridge
    }

    // MARK: App confirmations

    /// The player confirmed an app-layer dialog.
    func confirm(_ appConfirmation: AppConfirmation) {
        dismissPresentation()
        switch appConfirmation {
        case .discardUnsavedGame:
            let intent = pendingReplace
            pendingReplace = nil
            if let intent { perform(intent) }
        case .revertToAutosave:
            revertToAutosave()
        case let .deleteSlot(id):
            deleteSlot(id)
        case let .loadImportedSave(id):
            requestOpen(slotID: id)
        case let .clearHighScores(ruleset):
            clearHighScores(ruleset)
        case .timewarpLoad:
            present(.sheet(.openSavedGame))
        case .closeGame:
            requestCloseGame()
        }
    }

    // MARK: Persistence triggers (SAV-038, SAV-046) and high scores (SCORE-037)

    /// `arrived`: the step docked at a new system (a warp without encounters goes docked → docked in one step).
    private func runPersistenceTriggers(phaseBefore: GamePhase, state: GameState, arrived: Bool) {
        let endedNow: GameEndType? = if case let .gameOver(e) = state.phase, !Self.isGameOver(phaseBefore) { e } else { nil }
        if state.ironman {
            writeIronmanSlot()
        } else if (state.phase == .docked && (phaseBefore != .docked || arrived)) || endedNow != nil {
            writeAutosave()
        }
        if let endedNow { recordHighScore(end: endedNow) }
    }

    static func isGameOver(_ phase: GamePhase) -> Bool {
        if case .gameOver = phase { return true }
        return false
    }

    private func writeCreationSave() {
        guard let state else { return }
        if state.ironman { writeIronmanSlot() } else { writeAutosave() }
    }

    /// Writes `Saves/autosave` for a non-Ironman game. Failures are logged, never shown (autosave is silent).
    func writeAutosave() {
        guard let state, let gameID, !state.ironman else { return }
        do {
            _ = try slotStore.autosave(state, gameID: gameID)
        } catch {
            log.error("autosave failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Writes an Ironman game's single slot (slot id == game id).
    func writeIronmanSlot() {
        guard let state, let gameID, state.ironman else { return }
        do {
            _ = try slotStore.save(state, slot: gameID, gameID: gameID)
        } catch {
            log.error("ironman save failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Writes whatever quitting must write (SAV-038 autosave or SAV-046 Ironman slot).
    func writeOnQuit() {
        guard let state else { return }
        if state.ironman { writeIronmanSlot() } else { writeAutosave() }
    }

    private func recordHighScore(end: GameEndType) {
        guard let state, let gameID else { return }
        do {
            if let outcome = try highScoreStore.record(state, end: end, gameID: gameID) {
                recordedScore = .outcome(outcome)
            } else {
                recordedScore = .alreadyRecorded
            }
        } catch {
            recordedScore = .failed
            log.error("high score failed: \(String(describing: error), privacy: .public)")
        }
    }
}
