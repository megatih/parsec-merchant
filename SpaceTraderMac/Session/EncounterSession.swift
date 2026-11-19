// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Observation
import ParsecEngine

/// The Encounter view's session state (UI-ENC-024, -025, -033, -038, -043, -049): the combat log, the header, the
/// auto-repeat driver and switch, and the Make Room flow. Not saved.
@Observable @MainActor
final class EncounterSession {
    /// UI-ENC-024: the current encounter's log (cleared at each `encounterStarted`).
    private(set) var log: [CombatLogLine] = []
    /// UI-ENC-016: the header of the current encounter.
    private(set) var intro: EncounterIntro?
    /// UI-ENC-043: an encounter step was accepted since `encounterStarted` (hides the tactical readout).
    private(set) var actedInEncounter = false
    /// UI-ENC-033: the session-only Auto-repeat switch (default on); change it with `GameSession.setAutoRepeat`.
    fileprivate(set) var autoRepeatEnabled = true
    /// UI-ENC-049: the canister waiting while the player makes room (the jettison sheet over the Encounter view).
    fileprivate(set) var makeRoomItem: TradeItemType?
    /// UI-ENC-025 / A11Y-011: the last announcement (one per step).
    private(set) var lastAnnouncement: String?
    /// The current step's new combat rows, joined; the session posts them with the rest of the step (A11Y-011).
    @ObservationIgnored private(set) var pendingCombatText: String?

    @ObservationIgnored let driver = AutoRepeatDriver()
    /// A11Y-011: the session's one announcer (`GameSession.announcer` reads and writes this).
    @ObservationIgnored var announcer: any Announcer = VoiceOverAnnouncer()

    /// Takes the combat text collected during the step.
    func takePendingCombatText() -> String? {
        defer { pendingCombatText = nil }
        return pendingCombatText
    }

    /// Records what the session posted for the step.
    func noteAnnounced(_ text: String) { lastAnnouncement = text }

    fileprivate func start(intro: EncounterIntro?) {
        log = []
        self.intro = intro
        actedInEncounter = false
        makeRoomItem = nil
    }

    fileprivate func append(_ lines: [CombatLogLine]) {
        guard !lines.isEmpty else { return }
        log.append(contentsOf: lines)
        pendingCombatText = lines.map(\.display).joined(separator: " ")
    }

    fileprivate func markActed() { actedInEncounter = true }

    fileprivate func reset(resumed state: GameState?) {
        driver.reset()
        log = []
        intro = nil
        actedInEncounter = false
        makeRoomItem = nil
        lastAnnouncement = nil
        pendingCombatText = nil
        guard let state, let resumedIntro = EncounterIntro.resumed(state: state) else { return }
        intro = resumedIntro
        actedInEncounter = true
        log = [CombatLogLine(round: nil, text: String(localized: "Encounter resumed.")),
               CombatLogLine(round: nil, text: resumedIntro.headline), CombatLogLine(round: nil, text: resumedIntro.action)]
    }
}

/// UI-ENC-036: the decision the state holds but nothing presents (after a load or a dismissed sheet).
enum EncounterResume {
    static func presentation(state: GameState) -> Presentation? {
        if let offer = state.pendingOrbitTrade { return .sheet(.tradeInOrbit(offer)) }
        if let plunder = state.pendingPlunder {
            let source: PlunderSheetContext.Source = plunder.marieCeleste ? .marieCeleste : .opponent
            return .sheet(.plunder(PlunderSheetContext(victimCargo: plunder.victimCargo, source: source)))
        }
        if let item = state.pendingScoop { return .scoop(item) }
        return nil
    }
}

// MARK: Session hooks (called from GameSession) and encounter actions

extension GameSession {
    private var encounterDriver: AutoRepeatDriver {
        let driver = encounterUI.driver
        if driver.send == nil { driver.send = { [weak self] command in self?.send(command) } }
        return driver
    }

    /// UI-ENC-039 rule 3: every encounter command other than the tick is a manual action.
    func encounterWillSend(_ command: Command) {
        if case let .encounter(a) = command, a != .autoRepeat { encounterDriver.handle(.manualAction) }
    }

    /// UI-ENC-039 rule 5: a rejected auto-repeat cancels and never retries.
    func encounterStepRejected(_ command: Command) {
        guard command == .encounter(.autoRepeat) else { return }
        let inEncounter = if case .encounter = state?.phase { true } else { false }
        encounterDriver.handle(.stepApplied(canAutoRepeat: false, inEncounter: inEncounter))
    }

    /// UI-ENC-005 first consumer: the combat log (UI-ENC-022…025), the readout gate (UI-ENC-043) and auto-repeat
    /// scheduling (UI-ENC-039 rule 1).
    func consumeEncounterStep(_ step: StepRecord) {
        let lastStart = step.events.last { if case .encounterStarted = $0 { true } else { false } }
        if let lastStart {
            encounterUI.start(intro: EncounterIntro.make(started: lastStart, state: step.after))
        } else if case .encounter = step.before.phase {
            encounterUI.markActed()
        }
        // UI-ENC-206: when the step ended one encounter and started the next, the old one's last round opens the new log.
        encounterUI.append(CombatLog.closingLines(for: step) + CombatLog.lines(for: step))
        let inEncounter = if case .encounter = step.after.phase { true } else { false }
        let canRepeat = engine?.encounterPreview?.canAutoRepeat ?? false
        encounterDriver.handle(.stepApplied(canAutoRepeat: canRepeat, inEncounter: inEncounter))
    }

    /// UI-ENC-039 rule 4: presentations suspend the repeat.
    func encounterPresentationChanged() {
        encounterDriver.handle(.presentationChanged(isModal: presentation != nil))
    }

    func encounterPlaybackChanged() {
        encounterDriver.handle(.playbackChanged(running: transitPlayback != nil))
    }

    /// Load, new game and close: a game loaded mid-encounter starts its log with "Encounter resumed." (UI-ENC-024).
    func resetEncounterUI() {
        encounterUI.reset(resumed: state)
    }

    /// An action-bar button, menu item or Return (UI-ENC-027, -029, -034). Nothing is sent while input is locked.
    func performEncounterAction(_ action: EncounterAction) {
        guard !isInputLocked else { return }
        send(.encounter(action))
    }

    /// Stop or Esc (UI-ENC-032, -040): sends `.stop` and cancels the repeat only while the engine can stop.
    func stopEncounter() {
        guard !isInputLocked else { return }
        encounterDriver.handle(.escape(canStop: engine?.encounterPreview?.canStop ?? false))
    }

    /// The ⌥A switch (UI-ENC-033): gates the app timer only.
    func setAutoRepeat(_ on: Bool) {
        encounterUI.autoRepeatEnabled = on
        encounterDriver.handle(.toggle(enabled: on))
    }

    /// UI-ENC-043: the tactical readout shows before the first accepted action of an encounter, if the setting is on.
    var showsTacticalReadout: Bool {
        guard case let .encounter(enc) = state?.phase else { return false }
        let setting = defaults.object(forKey: AppSettingsKey.tacticalReadout) as? Bool ?? true
        return setting && enc.round == 0 && !encounterUI.actedInEncounter
    }

    /// UI-ENC-036: the decision to re-present, when nothing presents it.
    var encounterResumePresentation: Presentation? {
        guard !isModal, encounterUI.makeRoomItem == nil, let state else { return nil }
        return EncounterResume.presentation(state: state)
    }

    // MARK: Scoop and Make Room (UI-ENC-049)

    /// Make Room: closes the full-hold scoop dialog and opens the jettison sheet over the Encounter view.
    func beginMakeRoom(for item: TradeItemType) {
        dismissPresentation()
        encounterUI.makeRoomItem = item
    }

    /// Jettisons from the Make Room sheet. The sheet states the littering consequence, so its button is the consent
    /// (UI-SHELL-004 inline form). With a free bay the scoop dialog comes back with Pick It Up.
    func makeRoomJettison(_ item: TradeItemType, quantity: Int) {
        send(.jettisonCargo(item, quantity: quantity), acknowledging: [.litteringWarning, .jettisonAll])
        if let state, state.freeCargoBays > 0 { endMakeRoom() }
    }

    /// Leaves the Make Room sheet; the scoop question is asked again.
    func endMakeRoom() {
        guard let item = encounterUI.makeRoomItem else { return }
        encounterUI.makeRoomItem = nil
        if state?.pendingScoop == item { present(.scoop(item)) }
    }
}
