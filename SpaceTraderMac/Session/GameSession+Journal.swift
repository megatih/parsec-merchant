// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import ParsecInsights
import ParsecPersistence

/// LOG-025…027, STAT-002/003, ACH-016/017, LLM-018/021: the journal, statistics, achievements and flavor wiring.
extension GameSession {
    /// LOG-025: installs a game's journal (nil on Close Game), cancels pending flavor (LLM-019) and rebuilds the
    /// statistics off the main actor (STAT-003).
    func installJournal(_ newJournal: GameJournal?) {
        flavor.cancelAll()
        journal = newJournal
        journalRevision += 1
        rebuildStats()
    }

    /// STAT-003: folds the journal's entries off the main actor and applies the result only if no other rebuild
    /// started since (a step recorded meanwhile restarts it).
    func rebuildStats() {
        statsTask?.cancel()
        statsTask = nil
        careerStats = nil
        statsEpoch += 1
        guard let entries = journal?.entries else { return }
        let epoch = statsEpoch
        statsTask = Task { [weak self] in
            let stats = await Self.foldOffMain(entries)
            guard let self, !Task.isCancelled, self.statsEpoch == epoch else { return }
            self.careerStats = stats
            self.statsTask = nil
        }
    }

    /// STAT-003: the fold runs in a detached task, off the main actor.
    nonisolated static func foldOffMain(_ entries: [LogEntry]) async -> CareerStats {
        await Task.detached(priority: .userInitiated) { CareerStats.fold(entries) }.value
    }

    /// STAT-003: true while the statistics are being rebuilt (the Statistics tab shows a progress indicator).
    var isRebuildingStats: Bool { journal != nil && careerStats == nil }

    /// LOG-013 / LOG-025: records an accepted, non-confirmation step; then STAT-002 (incremental stats), ACH-016 (store
    /// and feed notes) and LLM-018 (flavor requests).
    func recordJournal(_ step: StepRecord) {
        guard var j = journal else { return }
        let output = JournalRecorder.record(JournalStep(command: step.command, before: step.before, result: step.result,
                                                        after: step.after), into: &j)
        journal = j
        guard !output.newEntries.isEmpty || !output.unlocked.isEmpty else { return }
        journalRevision += 1
        if var stats = careerStats {
            for e in output.newEntries { stats.add(e) }
            careerStats = stats
        } else {
            rebuildStats()
        }
        if let gameID {
            let added = achievements.observe(output, gameID: gameID, state: step.after)
            if !added.isEmpty { achievementsRevision += 1 }
            for id in added { appendNote(.achievementUnlocked(id)) }
            let state = step.after
            flavor.enqueue(output.newEntries, gameID: gameID) { FlavorNames.make(state: state) }
        }
    }

    /// LLM-021 / LLM-022: caches generated prose in the matching entry. Touches only `journal` (no state, generation,
    /// feed, presentation or persistence trigger); persisted by the next save (LOG-027).
    func applyGeneratedFlavor(_ result: FlavorResult) {
        guard result.gameID == gameID, var j = journal,
              let i = j.entries.firstIndex(where: { $0.id == result.entryID }) else { return }
        if case .generated = j.entries[i].flavor { return }
        j.entries[i].flavor = result.text
        journal = j
        journalRevision += 1
    }

    /// LLM-025 / LLM-026: the Settings toggle changed.
    func flavorSettingChanged(useFoundationModels: Bool) {
        flavor.setMode(FlavorMode.derive(launch: launchOptions, useFoundationModels: useFoundationModels))
    }

    /// ACH-021 / ACH-014: empties the app-wide store; journals keep their entries.
    func resetAchievements() {
        do {
            try achievements.reset()
        } catch {
            present(.systemAlert(.saveFailed(reason: SlotText.saveFailure(error))))
        }
        achievementsRevision += 1
    }

    /// LOG-026: the export envelope carries the journal with the state.
    func exportEnvelope(state: GameState, gameID: String) -> SaveEnvelope {
        SaveEnvelope(state: state, appVersion: slotStore.appVersion, gameID: gameID, journal: journal)
    }

    /// LOG-035 / STAT-020: shows the Logbook at a tab (the feed overlay, the game-over card and the inspector).
    func showLogbook(tab: LogbookTab = .log) {
        logbookTab = tab
        selectedSection = .logbook
    }

    /// LOG-035: "Back to Summary" in an ended game returns to the game-over card.
    func backToSummary() {
        selectedSection = .bridge
    }
}
