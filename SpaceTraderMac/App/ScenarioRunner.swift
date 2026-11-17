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
        case EncounterFixtureScenario.specialEventName:
            session.install(EncounterFixtureScenario.makeSpecialEvent(), gameID: SlotStore.newSlotID(), slotID: nil)
            return nil
        case EncounterFixtureScenario.transitName:
            session.install(EncounterFixtureScenario.makeTransit(), gameID: SlotStore.newSlotID(), slotID: nil)
            return nil
        case let name where EncounterFixtureScenario.type(named: name) != nil:
            if let type = EncounterFixtureScenario.type(named: name) {
                session.install(EncounterFixtureScenario.make(type), gameID: SlotStore.newSlotID(), slotID: nil)
            }
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

/// UI-ENC-096: `-PMScenario encounter:<EncounterType>` (Debug only) puts a Modern Normal game into an encounter of that
/// type, 7 clicks from the warp system, with an opponent gnat carrying 5 furs and 2 ore. The identifier walk uses it to
/// reach the plunder, trade-in-orbit and arrest-report sheets, which no played scenario reaches deterministically. The
/// game is flagged `cheatsUsed` (CHEAT-049).
enum EncounterFixtureScenario {
    static let prefix = "encounter:"
    static let seed: UInt64 = 1

    static func type(named name: String) -> EncounterType? {
        guard name.hasPrefix(prefix) else { return nil }
        let wanted = String(name.dropFirst(prefix.count))
        return EncounterType.allCases.first { "\($0)" == wanted }
    }

    static func make(_ type: EncounterType) -> GameEngine {
        var engine = GameEngine(config: NewGameConfig(commanderName: "Fixture", difficulty: .normal, skills: [5, 5, 5, 5],
                                                      ruleset: .modern, seed: seed))
        engine.perform(.cheat(.enable))
        var state = engine.state
        var opponent = Ship(type: .gnat, spec: state.ruleset.tables.ship(.gnat))
        opponent.weapons = [.pulseLaser]
        opponent.cargo[TradeItemType.furs.rawValue] = 5
        opponent.cargo[TradeItemType.ore.rawValue] = 2
        state.encounterTransit = TransitState(destination: state.warpSystem, clicksRemaining: 7, viaWormhole: false)
        state.phase = .encounter(EncounterState(type: type, opponent: opponent, clicks: 7))
        return GameEngine(state: state)
    }

    /// `-PMScenario specialEvent` (Debug only): the same game docked, its current system offering the first special
    /// event (in `SpecialEventType` order) that is available there, for the walk of the Bridge card and narrative sheet.
    static let specialEventName = "specialEvent"

    static func makeSpecialEvent() -> GameEngine {
        var engine = GameEngine(config: NewGameConfig(commanderName: "Fixture", difficulty: .normal, skills: [5, 5, 5, 5],
                                                      ruleset: .modern, seed: seed))
        engine.perform(.cheat(.enable))
        let base = engine.state
        for type in SpecialEventType.allCases {
            var state = base
            state.galaxy.systems[state.commander.currentSystem].specialEvent = type
            if state.specialEventAvailable != nil { return GameEngine(state: state) }
        }
        return engine
    }

    /// `-PMScenario transit` (Debug only): the same game resting in `.inTransit` halfway to its warp target, so the
    /// Transit view stays up (frozen, UI-ENC-013) for the surface walks; a played-back trip lasts only 1.2 s.
    static let transitName = "transit"

    static func makeTransit() -> GameEngine {
        var engine = GameEngine(config: NewGameConfig(commanderName: "Fixture", difficulty: .normal, skills: [5, 5, 5, 5],
                                                      ruleset: .modern, seed: seed))
        engine.perform(.cheat(.enable))
        var state = engine.state
        state.phase = .inTransit(TransitState(destination: state.warpSystem, clicksRemaining: 10, viaWormhole: false))
        return GameEngine(state: state)
    }
}
