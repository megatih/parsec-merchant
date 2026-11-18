// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// The Dock tile hooks the session drives (UI-ENC-010/011). The app injects an AppKit implementation; tests use `NoDock`
/// or a recorder.
@MainActor
protocol SessionDock {
    /// Shows a thin progress bar over the app icon (`nil` restores the plain icon).
    func setProgress(_ fraction: Double?)
    /// Sets or clears the Dock badge label.
    func setBadge(_ label: String?)
    /// Requests informational attention (bounces the Dock icon once).
    func requestAttention()
}

/// No Dock output (tests, previews).
struct NoDock: SessionDock {
    func setProgress(_ fraction: Double?) {}
    func setBadge(_ label: String?) {}
    func requestAttention() {}
}

/// Transit playback (UI-ENC-007…014) and Dock attention (UI-ENC-011).
extension GameSession {
    /// Settings › Fast travel, `-PMFastTravel` or Reduce Motion skip the playback (UI-ENC-007, CHEAT-050).
    var isFastTravel: Bool {
        launchOptions.fastTravel || defaults.bool(forKey: AppSettingsKey.fastTravel) || reduceMotion
    }

    /// Starts the playback for `step`, if it has one, and schedules its ticks on `playbackClock`.
    func startPlayback(for step: StepRecord) {
        guard let playback = TransitPlayback.make(step: step, fast: isFastTravel), playback.tickCount > 0 else { return }
        transitPlayback = playback
        transitTick = 0
        audio.transit(.started)
        dock.setProgress(DockTileProgress.fraction(playback: playback, tick: 0))
        guard let clock = playbackClock else { return }
        let interval = TransitPlayback.tickInterval * launchOptions.slowTravel
        playbackTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await clock.sleep(for: interval)
                } catch {
                    return
                }
                guard let self, !Task.isCancelled, advancePlayback() else { return }
            }
        }
    }

    /// One tick: the next click; ends the playback after its last click. Returns whether it is still running.
    @discardableResult
    func advancePlayback() -> Bool {
        guard let playback = transitPlayback else { return false }
        transitTick += 1
        audio.transit(.tick(clicksFlown: playback.clicksFlown(atTick: transitTick)))
        if transitTick >= playback.tickCount {
            finishPlayback()
            return false
        }
        dock.setProgress(DockTileProgress.fraction(playback: playback, tick: transitTick))
        return true
    }

    /// Skip, Return or Esc in the Transit view (UI-ENC-008): ends the playback at once. The engine state is already final.
    func skipPlayback() {
        finishPlayback()
    }

    /// Ends the playback, restores the Dock icon and shows what the step raised meanwhile (UI-ENC-009).
    func finishPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        guard transitPlayback != nil else { return }
        transitPlayback = nil
        transitTick = 0
        dock.setProgress(nil)
        audio.transit(.ended)
        let deferred = deferredPresentations
        deferredPresentations = []
        for p in deferred { present(p) }
        showPendingArrival()
        if sendDepth == 0 { runNewsAutoShowIfPending() }
        updateDockAttention()
    }

    /// Presents now, or after the running playback (UI-ENC-009).
    func presentAfterPlayback(_ p: Presentation) {
        if transitPlayback != nil {
            deferredPresentations.append(p)
        } else {
            present(p)
        }
    }

    /// UI-ENC-011: the "!" badge while an encounter waits and the app is inactive; one attention request per encounter.
    func updateDockAttention() {
        let phase: GamePhase? = transitPlayback == nil ? state?.phase : nil
        let badge = DockAttention.badge(phase: phase, isActive: isAppActive)
        dock.setBadge(badge)
        if badge != nil, !attentionRequested {
            attentionRequested = true
            dock.requestAttention()
        }
        if case .encounter = state?.phase {} else { attentionRequested = false }
    }

    /// The app became active or inactive (AppDelegate).
    func setAppActive(_ active: Bool) {
        isAppActive = active
        audio.setAppActive(active)
        haptics.setAppActive(active)
        updateDockAttention()
    }
}

/// Decision answers that close their presentation first (UI-ENC-049).
extension GameSession {
    /// The scoop dialog's answer: Pick It Up or Leave It (ALR-070).
    func answerScoop(accept: Bool) {
        dismissPresentation()
        send(.resolveScoop(accept: accept))
    }
}
