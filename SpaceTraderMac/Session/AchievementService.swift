// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import ParsecInsights
import ParsecPersistence
import os

/// ACH-016 / ACH-017: records each step's unlocks in the app-wide store and reports the ones actually added.
@MainActor
final class AchievementService: SessionAchievements {
    private(set) var store: AchievementStore
    private let log = Logger(subsystem: "io.github.megatih.ParsecMerchant", category: "achievements")

    init(store: AchievementStore) {
        self.store = store
    }

    func observe(_ output: JournalStepOutput, gameID: String, state: GameState) -> [AchievementID] {
        guard !output.unlocked.isEmpty else { return [] }
        do {
            let added = try store.unlock(output.unlocked.map(\.rawValue), gameID: gameID, rulesetID: state.rulesetID.rawValue,
                                         day: state.commander.days)
            return added.compactMap(AchievementID.init(rawValue:))
        } catch {
            log.error("unlock not persisted: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    var records: [AchievementRecord] { (try? store.records()) ?? [] }

    func reset() throws { try store.reset() }
}
