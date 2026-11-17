// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Observation
import ParsecEngine
import ParsecInsights
import ParsecPersistence
import os

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
    private(set) var presentation: Presentation? { didSet { encounterPresentationChanged() } }
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
    /// UI-ENC-089: bumped when a high-score table changes or the High Scores window is asked to show the game's table.
    var highScoresRevision = 0
    /// What to do after the player agrees to discard the unsaved game (SAV-043).
    private(set) var pendingReplace: ReplaceIntent?
    /// File panels requested by menus or Welcome; the view that owns `fileImporter`/`fileExporter` binds to these.
    var isImporterPresented = false
    var isExporterPresented = false

    // MARK: Galaxy chart (MAP §1, §12, §14; GameSession+Map.swift)
    /// MAP-003: bumped on every accepted step, load, new game and close.
    private(set) var stateGeneration = 0
    /// MAP-063: the session-only planned route.
    var plannedRoute: PlannedRoute?
    /// Per-map viewports, show-on-map requests and window state.
    let map = MapSessionState()
    @ObservationIgnored var mapSnapshotCache: MapSnapshot?
    @ObservationIgnored var mapSnapshotBuilds = 0
    @ObservationIgnored var routeTask: Task<Void, Never>?
    @ObservationIgnored var routePlanner: RoutePlanning = RoutePlanning.standard

    // MARK: Steps, transit and the Dock (UI-ENC §1–2; GameSession+Transit.swift)
    /// UI-ENC-005: the last accepted step (cleared on load, new game and close).
    private(set) var lastStep: StepRecord?
    /// UI-ENC-007: the running transit playback, if any, and its current tick.
    var transitPlayback: TransitPlayback? { didSet { encounterPlaybackChanged() } }
    var transitTick = 0
    /// Set by the main window from `accessibilityReduceMotion` (the playback is then skipped, UI-ENC-007).
    var reduceMotion = false
    /// UI-ENC-011: whether the app is active (the Dock badge shows only while it is not).
    var isAppActive = true
    /// The clock that drives playback ticks; nil leaves ticking to the caller (tests call `advancePlayback()`).
    @ObservationIgnored var playbackClock: (any Clock<Duration>)? = ContinuousClock()
    @ObservationIgnored var playbackTask: Task<Void, Never>?
    /// Presentations raised while a playback runs; shown when it ends (UI-ENC-009).
    @ObservationIgnored var deferredPresentations: [Presentation] = []
    @ObservationIgnored var attentionRequested = false
    /// UI-ENC §3–5: the Encounter view's log, header, auto-repeat and Make Room state (GameSession+… in EncounterSession.swift).
    let encounterUI = EncounterSession()

    // MARK: Arrival, newspaper and narrative (UI-ENC §8–11; GameSession+Arrival.swift)
    /// UI-ENC-053: the trip being collected from the step records.
    @ObservationIgnored var tripAccumulator = TripAccumulator()
    /// UI-ENC-055: the arrival card at the top of Bridge (until dismissed or the next departure).
    var arrivalCard: ArrivalReport?
    /// UI-ENC-061: the finished trip's form, shown when the playback ends.
    @ObservationIgnored var pendingArrival: ArrivalPresentation?
    /// UI-ENC-062: `.readNewspaper` is sent once the arrival form is shown.
    @ObservationIgnored var pendingNewsAutoShow = false
    /// Nesting depth of `send` (the auto-show runs after the outermost step).
    @ObservationIgnored var sendDepth = 0

    // MARK: Services
    let slotStore: SlotStore
    let highScoreStore: HighScoreStore
    let audio: any SessionAudio
    let haptics: any SessionHaptics
    let achievements: any SessionAchievements
    let flavor: any SessionFlavor
    let dock: any SessionDock
    let launchOptions: LaunchOptions
    let defaults: UserDefaults

    @ObservationIgnored private var nextFeedID = 0
    @ObservationIgnored let log = Logger(subsystem: "io.github.megatih.ParsecMerchant", category: "session")

    init(stores: SessionStores, launchOptions: LaunchOptions = .none, defaults: UserDefaults = .standard,
         audio: any SessionAudio = SilentAudio(), haptics: any SessionHaptics = NoHaptics(),
         achievements: any SessionAchievements = NoAchievements(), flavor: any SessionFlavor = TemplateFlavor(),
         dock: any SessionDock = NoDock()) {
        slotStore = stores.slotStore
        highScoreStore = stores.highScoreStore
        self.launchOptions = launchOptions
        self.defaults = defaults
        self.audio = audio
        self.haptics = haptics
        self.achievements = achievements
        self.flavor = flavor
        self.dock = dock
    }

    // MARK: Derived state

    /// The current game state (read it during a render; never store it).
    var state: GameState? { engine?.state }
    var mode: SessionMode { SessionMode.derive(from: engine?.state) }
    /// True while anything is presented; menus disable game commands (MENU-006).
    var isModal: Bool { presentation != nil }
    /// UI-ENC-006: no command is sent from the action bar, menus, keys, toolbar or sidebar while this is true.
    var isInputLocked: Bool { isModal || transitPlayback != nil }
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
        encounterWillSend(command)
        sendDepth += 1
        defer {
            sendDepth -= 1
            if sendDepth == 0 { runNewsAutoShowIfPending() }
        }
        let before = engine.state
        let result = engine.perform(command, acknowledging: acknowledging)
        self.engine = engine
        apply(result, command: command, acknowledged: acknowledging, before: before)
    }

    /// Handles a step result: rejection, confirmation, the step consumers (UI-ENC-005), other decisions, feed,
    /// persistence and high scores.
    func apply(_ result: StepResult, command: Command, acknowledged: Set<WarningID>, before: GameState) {
        guard let state = engine?.state else { return }
        let phaseBefore = before.phase
        if let rejection = result.rejection {
            lastRejection = rejection
            rejectionSerial += 1
            encounterStepRejected(command)
            return
        }
        lastRejection = nil
        stateGeneration += 1
        let isConfirmationRequest = if case .confirm = result.decision, result.events.isEmpty { true } else { false }
        if !isConfirmationRequest {
            consume(StepRecord(command: command, acknowledged: acknowledged, before: before, result: result, after: state))
        }
        if let decision = result.decision {
            presentAfterPlayback(PresentationRouter.route(decision, state: state, command: command, acknowledged: acknowledged))
        }
        guard !isConfirmationRequest else { return }
        appendToFeed(result.events.map(FeedItem.Entry.event), state: state)
        audio.play(events: result.events)
        haptics.perform(events: result.events)
        achievements.observe(events: result.events, state: state)
        let arrived = result.events.contains { if case .arrived = $0 { true } else { false } }
        runPersistenceTriggers(phaseBefore: phaseBefore, state: state, arrived: arrived)
        if state.phase == .docked, phaseBefore != .docked || arrived { followPlannedRouteAfterDocking() }
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

    // MARK: Step consumers (UI-ENC-005)

    /// Runs the step consumers in order, before the presentation queue: (combat log, trip accumulator and report
    /// sheets are added here by their specs), then the transit playback and the Dock attention.
    private func consume(_ step: StepRecord) {
        // A step with events arriving while an older playback runs ends that playback first, so nothing stays deferred.
        // Silent steps (the route follower's target selection after docking) leave it running.
        if transitPlayback != nil, !step.events.isEmpty || step.result.decision != nil { finishPlayback() }
        lastStep = step
        consumeEncounterStep(step)
        consumeArrival(step)
        if step.encounterStarted != nil { attentionRequested = false }
        startPlayback(for: step)
        if transitPlayback == nil { showPendingArrival() }
        updateDockAttention()
        if DeveloperTester.opens(after: step.command) { present(.sheet(.developerTester)) }
    }

    /// Clears the per-game step state (load, new game, close).
    func resetStepState() {
        lastStep = nil
        playbackTask?.cancel()
        playbackTask = nil
        transitPlayback = nil
        transitTick = 0
        deferredPresentations = []
        attentionRequested = false
        resetArrivalState()
        dock.setProgress(nil)
        updateDockAttention()
        resetEncounterUI()
    }

    // MARK: Presentation queue (UI-SHELL-005)

    func present(_ p: Presentation) {
        // UI-ENC-045: a decision re-raised by its own sheet (each plunder Take) updates the open sheet instead of queuing.
        if let current = presentation, current.id == p.id {
            presentation = p
        } else if presentation == nil {
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
            autoShowNewspaperForNewGame()
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
        stateGeneration += 1
        resetMapForNewGame()
        resetStepState()
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
        stateGeneration += 1
        resetMapForNewGame()
        resetStepState()
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
        defer { highScoresRevision += 1 }
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
