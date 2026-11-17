// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import ParsecPersistence

/// `-PMScenario` fixtures (CHEAT-049, UI-ENC-093). Returns an exit status when the scenario ends the process, nil when
/// the app keeps running with the scenario's game. `LaunchOptions` already drops every name but `smoke` in Release
/// (CHEAT-047), `-PMResetState` has run before the session exists (CHEAT-051), and named scenarios ignore `-PMSeed`.
enum ScenarioRunner {
    static let smokeSeed: UInt64 = 20_261_117

    static func run(_ name: String, session: GameSession) -> Int32? {
        switch name {
        case "smoke": return smoke(session: session) ? 0 : 1
        case "pirateAmbush":
            runPirateAmbush(session: session)
            return nil
        default: return 2
        }
    }

    /// Creates a game, saves it to a slot, loads it back and checks the loaded state equals the saved one.
    static func smoke(session: GameSession) -> Bool {
        var state = GameState(config: NewGameConfig(commanderName: "Smoke", seed: smokeSeed))
        state.cheatsUsed = true
        let gameID = SlotStore.newSlotID()
        do {
            _ = try session.slotStore.save(state, slot: gameID, gameID: gameID)
            let loaded = try session.slotStore.load(slot: gameID)
            try? session.slotStore.delete(slot: gameID)
            return loaded.state == state
        } catch {
            return false
        }
    }

    /// UI-ENC-090: installs the ambush game, writes its creation autosave, then warps through `GameSession.send`, so the
    /// encounter, playback, log and persistence follow the normal path.
    static func runPirateAmbush(session: GameSession) {
        session.install(PirateAmbushScenario.make(), gameID: SlotStore.newSlotID(), slotID: nil)
        session.writeAutosave()
        session.send(.warp)
    }
}

/// UI-ENC-090/091: the flow-2 fixture, built by play. The constants were found by a search over seeds 1…400 and every
/// in-range target (the first hit with the fewest attacks); `SpaceTraderMacUITests/UITestFixtures.swift` mirrors them.
enum PirateAmbushScenario {
    static let seed: UInt64 = 292
    static let target = 46
    /// `.encounter(.attack)` commands that destroy the pirate.
    static let expectedAttacks = 6
    /// The UI flow's bound on Attack clicks (≤ 30).
    static let maxAttacks = 12

    /// Modern, Normal, 5/5/5/5; cheats enabled and a military laser in weapon slot 0 (neither draws RNG, CHEAT-006,
    /// CHEAT-026); the target selected. The game has `cheatsUsed` (CHEAT-049).
    static func make() -> GameEngine {
        var engine = GameEngine(config: NewGameConfig(commanderName: "Ambush", difficulty: .normal, skills: [5, 5, 5, 5],
                                                      ruleset: .modern, seed: seed))
        engine.perform(.cheat(.enable))
        engine.perform(.cheat(.iron(slot: 0, weapon: 2)))
        engine.perform(.selectTarget(target))
        return engine
    }
}
