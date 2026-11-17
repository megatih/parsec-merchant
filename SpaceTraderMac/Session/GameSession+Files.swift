// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import ParsecPersistence

/// Session-level save, open, import and export operations (SAV-034…047). The menus, sheets and file panels that call
/// these live with their own views; this file only owns the rules.
extension GameSession {
    /// Slots newest first (empty on a read error).
    func listSlots() -> [SlotInfo] {
        SlotListCache.slots(of: slotStore)
    }

    /// The 10 newest slots for Welcome and Open Recent (SAV-042).
    func recentSlots(limit: Int = 10) -> [SlotInfo] {
        Array(listSlots().prefix(limit))
    }

    /// SAV-040: the newest autosave or Ironman slot that has not ended.
    var continueCandidate: SlotInfo? {
        Self.continueCandidate(in: listSlots())
    }

    /// SAV-040 over a newest-first list (shared with `CommanderStatusQuery`).
    nonisolated static func continueCandidate(in slots: [SlotInfo]) -> SlotInfo? {
        slots.first { ($0.isAutosave || $0.summary.ironman) && !$0.summary.ended }
    }

    /// The game id passed to `loadForPlay`: the loaded game, or nil when none is loaded or it has ended (SAV-034).
    var currentGameIDForReload: String? {
        guard let state, !Self.isGameOver(state.phase) else { return nil }
        return gameID
    }

    /// UI-SHELL-021: Welcome › Continue. Returns false when there is nothing to continue.
    @discardableResult
    func continueGame() -> Bool {
        guard let slot = continueCandidate else { return false }
        openSlot(slot.id)
        return true
    }

    /// Loads a slot for play and makes it the current game (call through `requestOpen(slotID:)` to apply SAV-043).
    func openSlot(_ slotID: String, revert: Bool = false) {
        do {
            let loaded = try slotStore.loadForPlay(slot: slotID, revert: revert, currentGameID: currentGameIDForReload)
            install(loaded)
        } catch {
            present(SlotText.openFailedAlert(error).presentation)
        }
    }

    /// Makes a loaded save the current game (UI-SHELL-021/088).
    func install(_ loaded: LoadedGame) {
        let slot = loaded.slotID == SlotStore.autosaveID ? nil : loaded.slotID
        install(GameEngine(state: loaded.state), gameID: loaded.gameID, slotID: slot)
        if loaded.recoveredFromBackup { appendNote(.recoveredFromBackup) }
    }

    /// SAV-041 / SAV-047: ⌘S writes the current slot (or behaves as Save As when there is none).
    func save() {
        guard let state, let gameID, !Self.isGameOver(state.phase) else { return }
        if state.ironman {
            writeIronmanSlot()
            return
        }
        write(to: currentSlotID ?? SlotStore.newSlotID(), state: state, gameID: gameID)
    }

    /// SAV-041: ⇧⌘S always writes a new slot (disabled for Ironman).
    func saveAs() {
        guard let state, let gameID, !state.ironman, !Self.isGameOver(state.phase) else { return }
        write(to: SlotStore.newSlotID(), state: state, gameID: gameID)
    }

    private func write(to slot: String, state: GameState, gameID: String) {
        do {
            _ = try slotStore.save(state, slot: slot, gameID: gameID)
            currentSlotID = slot
            lastManualSaveDays = state.commander.days
            appendNote(.gameSaved)
        } catch {
            present(.systemAlert(.saveFailed(reason: SlotText.saveFailure(error))))
        }
    }

    /// SAV-039: Revert to Autosave is possible for a loaded, non-Ironman game whose autosave is its own and not ended.
    var canRevertToAutosave: Bool {
        guard let state, !state.ironman, let gameID,
              let info = try? slotStore.info(slot: SlotStore.autosaveID) else { return false }
        return info.gameID == gameID && !info.summary.ended
    }

    func revertToAutosave() {
        guard canRevertToAutosave else { return }
        openSlot(SlotStore.autosaveID, revert: true)
    }

    /// SAV-026 / UI-SHELL-091: deleting the current slot keeps the game loaded with no current slot.
    func deleteSlot(_ id: String) {
        do {
            try slotStore.delete(slot: id)
            if currentSlotID == id { currentSlotID = nil }
        } catch {
            present(.systemAlert(.saveFailed(reason: SlotText.saveFailure(error))))
        }
    }

    /// SAV-027 / UI-SHELL-093: imports a save and offers to load it.
    func importSave(_ data: Data) {
        do {
            let id = try slotStore.importSave(data)
            present(.appConfirmation(.loadImportedSave(id)))
        } catch {
            present(SlotText.openFailedAlert(error).presentation)
        }
    }

    /// SAV-030: imports a file chosen in the import panel or opened from Finder (security-scoped in the sandbox).
    func importFile(at url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            importSave(try Data(contentsOf: url))
        } catch {
            present(SlotText.openFailedAlert(error).presentation)
        }
    }

    /// UI-SHELL-093: Finder-open imports each file in turn; the confirmations queue one at a time.
    func openFromFinder(_ urls: [URL]) {
        for url in urls { importFile(at: url) }
    }

    /// UI-SHELL-092: the export of the current game, or nil (with an alert on failure) when there is none.
    func makeCurrentExport() -> PendingExport? {
        guard let state else { return nil }
        do {
            guard let data = try exportCurrentGame() else { return nil }
            return PendingExport(document: SaveFileDocument(data: data),
                                 defaultName: SlotText.exportBaseName(commander: state.commander.name, day: state.commander.days))
        } catch {
            present(.systemAlert(.saveFailed(reason: SlotText.saveFailure(error))))
            return nil
        }
    }

    /// UI-SHELL-092: the export of a stored slot (Open sheet), or nil with an alert.
    func makeSlotExport(_ slot: SlotInfo) -> PendingExport? {
        do {
            let data = try slotStore.exportSave(slot: slot.id)
            return PendingExport(document: SaveFileDocument(data: data),
                                 defaultName: SlotText.exportBaseName(commander: slot.summary.commander, day: slot.summary.day))
        } catch {
            present(SlotText.openFailedAlert(error).presentation)
            return nil
        }
    }

    /// SAV-029: the current game's export data, stamped with its game id.
    func exportCurrentGame() throws -> Data? {
        guard let state, let gameID else { return nil }
        return try SaveCodec.encode(SaveEnvelope(state: state, appVersion: slotStore.appVersion, gameID: gameID))
    }

    /// SCORE-038.
    func clearHighScores(_ ruleset: RulesetID) {
        defer { highScoresRevision += 1 }
        do {
            try highScoreStore.clear(ruleset)
        } catch {
            present(.systemAlert(.saveFailed(reason: SlotText.saveFailure(error))))
        }
    }
}

/// Caches `SlotStore.list()` per store until the Saves folder changes (menus re-read it on every session change).
@MainActor
enum SlotListCache {
    private struct Entry {
        var stamp: Date?
        var slots: [SlotInfo]
    }

    private static var entries: [URL: Entry] = [:]

    static func slots(of store: SlotStore) -> [SlotInfo] {
        let dir = store.savesDirectory
        let stamp = (try? dir.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let e = entries[dir], e.stamp == stamp, stamp != nil { return e.slots }
        let slots = ((try? store.list()) ?? []).sorted { $0.modified > $1.modified }
        // Listing can quarantine files, which changes the folder again: stamp after listing.
        let after = (try? dir.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        entries[dir] = Entry(stamp: after, slots: slots)
        return slots
    }
}
