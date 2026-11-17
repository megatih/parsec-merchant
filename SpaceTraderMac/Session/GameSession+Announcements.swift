// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// A11Y-011/012 announcements and A11Y-044 tip triggers.
extension GameSession {
    /// The one announcer of the session (shared with the Encounter view's state, UI-ENC-025).
    var announcer: any Announcer {
        get { encounterUI.announcer }
        set { encounterUI.announcer = newValue }
    }

    /// A11Y-012: sends a command that came from the keyboard or a menu, so its result is announced.
    func sendFromKeyboard(_ command: Command) {
        let previous = keyboardOrigin
        keyboardOrigin = true
        defer { keyboardOrigin = previous }
        send(command)
    }

    /// Posts a text outside a step (save, export).
    func announce(_ text: String, priority: AnnouncementPriority = .normal) {
        announcer.announce(text, priority: priority)
        encounterUI.noteAnnounced(text)
    }

    /// A11Y-012: a rejected keyboard or menu command announces its reason.
    func announceRejection(_ error: CommandError) {
        _ = encounterUI.takePendingCombatText()
        guard keyboardOrigin else { return }
        announce(AnnouncementText.rejection(error))
    }

    /// A11Y-011: one announcement per step; nested steps (the route follower) join the outermost one.
    func announceStep(_ step: StepRecord) {
        let started = step.encounterStarted != nil
        let report = arrivalCard.map { !$0.sections.isEmpty || !$0.encounters.isEmpty } ?? false
        let context = AnnouncementText.Context(combat: encounterUI.takePendingCombatText(),
                                               intro: started ? encounterUI.intro?.headline : nil,
                                               reportAvailable: report || pendingArrival != nil,
                                               fromKeyboard: keyboardOrigin, extras: stepAnnouncementExtras)
        stepAnnouncementExtras = []
        if let a = AnnouncementText.make(step: step, before: step.before, after: step.after, context: context) {
            if let p = pendingAnnouncement {
                pendingAnnouncement = Announcement(text: p.text + " " + a.text,
                                                   priority: p.priority == .high || a.priority == .high ? .high : .normal)
            } else {
                pendingAnnouncement = a
            }
        }
        guard sendDepth <= 1, let a = pendingAnnouncement else { return }
        pendingAnnouncement = nil
        announce(a.text, priority: a.priority)
    }

    // MARK: Tips (A11Y-044)

    /// The tip calls after an accepted step.
    func tipsAfterStep(_ step: StepRecord) {
        updateTips(step: step)
    }

    /// The tip calls for the current section (visibility changes and steps).
    func updateTips(step: StepRecord? = nil) {
        guard let state else { return }
        let inRange = state.warpSystem != state.commander.currentSystem && state.destinationOK(state.warpSystem)
        for call in TipTriggers.apply(step: step, section: selectedSection, docked: state.phase == .docked,
                                      targetInRange: inRange) {
            tipCenter.apply(call)
        }
    }
}
