// SPDX-License-Identifier: GPL-2.0-or-later
// SAV §8, §11, §13: reload accounting, the Palm per-session chances, Ironman and the classic save features mapped.
import Foundation
import Testing
@testable import ParsecEngine
@testable import ParsecPersistence

@Suite("SAV reload accounting (SAV §8)")
struct ReloadSpecTests {
    @Test("SAV-033 reloadCount starts at 0 and is kept by save, load, export and migration")
    func reloadCountKept() throws {
        let root = makeTempRoot()
        defer { cleanUp(root) }
        for ruleset in RulesetID.allCases { #expect(newState(ruleset).reloadCount == 0) }
        let store = SlotStore(root: root, appVersion: "t")
        var state = dayState(5)
        state.reloadCount = 4
        let id = SlotStore.newSlotID()
        try store.save(state, slot: id, gameID: "g")
        #expect(try store.load(slot: id).state.reloadCount == 4)
        #expect(try SaveCodec.decode(store.exportSave(slot: id)).state.reloadCount == 4)
        let identity: SaveMigrator.Step = { $0 }
        let migrated = try SaveMigrator.migrate(SaveCodec.rawObject(store.exportSave(slot: id)), steps: [1: identity], target: 2)
        let typed = try JSONDecoder().decode(SaveEnvelope.self, from: JSONSerialization.data(withJSONObject: migrated))
        #expect(typed.state.reloadCount == 4)
        // Only reload-counting loads change it, and only upwards.
        let resumed = try store.loadForPlay(slot: id, revert: true, currentGameID: nil)
        #expect(resumed.state.reloadCount == 5 && resumed.countedAsReload)
        #expect(try store.load(slot: id).state.reloadCount == 4)
    }

    @Test("SAV-034 loadForPlay applies resumedAfterLoad; load (inspect/export) never changes reloadCount")
    func loadForPlay() throws {
        let root = makeTempRoot()
        defer { cleanUp(root) }
        let store = SlotStore(root: root, appVersion: "t")
        let id = SlotStore.newSlotID()
        try store.save(dayState(5), slot: id, gameID: "g")
        let loaded = try store.loadForPlay(slot: id, revert: true, currentGameID: nil)
        let envelope = try store.load(slot: id)
        #expect(loaded.state == envelope.state.resumedAfterLoad(countsAsReload: true))
        #expect(loaded.gameID == "g" && loaded.slotID == id && !loaded.recoveredFromBackup)
        for _ in 0..<3 { _ = try store.load(slot: id) }
        #expect(try store.load(slot: id).state.reloadCount == 0)
    }

    @Test("SAV-035 a load counts as a reload iff not Ironman and (revert, or the current unended game, or a newer save exists)")
    func reloadRule() throws {
        let root = makeTempRoot()
        defer { cleanUp(root) }
        let store = SlotStore(root: root, appVersion: "t")
        let old = SlotStore.newSlotID(), latest = SlotStore.newSlotID(), other = SlotStore.newSlotID()
        try store.save(dayState(1), slot: old, gameID: "G")
        try store.save(dayState(2), slot: latest, gameID: "G")
        try store.save(dayState(9), slot: other, gameID: "H")
        func counts(_ slot: String, revert: Bool = false, current: String? = nil) throws -> Bool {
            try store.loadForPlay(slot: slot, revert: revert, currentGameID: current).countedAsReload
        }
        // Resuming the newest save of a game is not a reload (Continue at launch, switching back from another game).
        #expect(try !counts(latest))
        #expect(try !counts(latest, current: "H"))
        #expect(try !counts(other, current: "G"))
        // (a) revert; (b) the game in memory; (c) an older save of a game that has a newer one.
        #expect(try counts(latest, revert: true))
        #expect(try counts(latest, current: "G"))
        #expect(try counts(old))
        #expect(try counts(old, current: "H"))
        // The autosave can't rewind for free: once a newer manual save exists, the autosave is older.
        try store.autosave(dayState(3), gameID: "G")
        #expect(try !counts(SlotStore.autosaveID))
        try store.save(dayState(4), slot: latest, gameID: "G")
        #expect(try counts(SlotStore.autosaveID))
        // An ended game in memory is passed as nil: reopening its newest save is not a reload.
        #expect(try !counts(latest, current: nil))
        // Ironman never counts, even reverting or reloading the current game.
        let iron = SlotStore.newSlotID()
        try store.save(dayState(5, ironman: true), slot: iron, gameID: iron)
        #expect(try !counts(iron, revert: true, current: iron))
    }

    @Test("SAV-036 resumedAfterLoad adds one only when counted, draws nothing and changes nothing else")
    func resumedAfterLoad() {
        for ruleset in [RulesetID.modern, .windows201] {
            var s = dayState(7, ruleset)
            s.reloadCount = 2
            s.chanceOfVeryRareEncounter = 900
            #expect(s.resumedAfterLoad(countsAsReload: false) == s)
            var expected = s
            expected.reloadCount = 3
            let r = s.resumedAfterLoad(countsAsReload: true)
            #expect(r == expected && r.rng == s.rng)
        }
    }

    @Test("SAV-037 Palm resets the cheat chances to 5 and 100 on load; Windows 2.01 and Modern keep the saved values")
    func palmChances() throws {
        #expect(!Ruleset.palm122.flags.travel.cheatChancesPersist)
        #expect(Ruleset.windows201.flags.travel.cheatChancesPersist && Ruleset.modern.flags.travel.cheatChancesPersist)
        let root = makeTempRoot()
        defer { cleanUp(root) }
        let store = SlotStore(root: root, appVersion: "t")
        for ruleset in RulesetID.allCases {
            var s = dayState(3, ruleset)
            s.chanceOfVeryRareEncounter = 1_000
            s.chanceOfTradeInOrbit = 0
            let id = SlotStore.newSlotID()
            try store.save(s, slot: id, gameID: id)
            // The file holds the cheated values in every ruleset; only the resumed Palm state resets them.
            #expect(try store.load(slot: id).state.chanceOfVeryRareEncounter == 1_000)
            let loaded = try store.loadForPlay(slot: id, revert: false, currentGameID: nil).state
            if ruleset == .palm122 {
                #expect(loaded.chanceOfVeryRareEncounter == 5 && loaded.chanceOfTradeInOrbit == 100)
                var expected = s
                expected.chanceOfVeryRareEncounter = 5
                expected.chanceOfTradeInOrbit = 100
                #expect(loaded == expected)
            } else {
                #expect(loaded == s)
            }
        }
    }
}

@Suite("SAV Ironman and classic features (SAV §11, §13)")
struct IronmanSpecTests {
    @Test("SAV-044 ironman comes only from NewGameConfig; no command changes it; only import clears it")
    func ironmanSource() throws {
        for ruleset in RulesetID.allCases {
            #expect(GameState(config: NewGameConfig(commanderName: "I", ruleset: ruleset, seed: 3, ironman: true)).ironman)
            #expect(!GameState(config: NewGameConfig(commanderName: "I", ruleset: ruleset, seed: 3)).ironman)
            for ironman in [true, false] {
                var engine = GameEngine(config: NewGameConfig(commanderName: "I", ruleset: ruleset, seed: 11, ironman: ironman))
                var r = Xoshiro256StarStar(seed: 99)
                for _ in 0..<400 {
                    engine.perform(FuzzPlayer.pickCommand(engine.state, &r), acknowledging: FuzzPlayer.ackAll)
                    if engine.state.ironman != ironman { Issue.record("ironman changed in \(ruleset)") ; break }
                }
                engine.perform(.setOptions(GameOptions()))
                engine.perform(.retire, acknowledging: FuzzPlayer.ackAll)
                #expect(engine.state.ironman == ironman)
            }
        }
        let root = makeTempRoot()
        defer { cleanUp(root) }
        let store = SlotStore(root: root, appVersion: "t")
        let id = try store.importSave(editedSave(dayState(2, ironman: true)) { _ in })
        #expect(try !store.load(slot: id).state.ironman)
    }

    @Test("SAV-045 an Ironman game lives in one slot named by its gameID, without backups, and never counts as a reload")
    func ironmanSlot() throws {
        let root = makeTempRoot()
        defer { cleanUp(root) }
        let store = SlotStore(root: root, appVersion: "t")
        let game = SlotStore.newSlotID()
        for d in 1...5 { try store.save(dayState(d, ironman: true), slot: game, gameID: game) }
        #expect(fileNames(store.savesDirectory) == ["slot-\(game).parsecsave"])
        let info = try #require(try store.list().first)
        #expect(info.id == info.gameID && info.summary.ironman && info.generation == 5)
        for (revert, current) in [(false, nil), (true, nil), (false, game), (true, game)] as [(Bool, String?)] {
            let loaded = try store.loadForPlay(slot: game, revert: revert, currentGameID: current)
            #expect(!loaded.countedAsReload && loaded.state.reloadCount == 0)
        }
    }

    @Test("SAV-048 an ended Ironman slot is kept with its final state and records its high score once with the badge")
    func endedIronman() throws {
        let root = makeTempRoot()
        defer { cleanUp(root) }
        let store = SlotStore(root: root, appVersion: "t")
        let scores = HighScoreStore(root: root)
        let game = SlotStore.newSlotID()
        var engine = GameEngine(state: dayState(40, ironman: true))
        try store.save(engine.state, slot: game, gameID: game)
        engine.perform(.retire, acknowledging: [.retire])
        try store.save(engine.state, slot: game, gameID: game)
        let listed = try store.list()
        #expect(listed.count == 1 && listed[0].summary.ended && listed[0].summary.ironman)
        #expect(try store.load(slot: game).state.phase == .gameOver(.retired))
        #expect(try scores.record(engine.state, end: .retired, gameID: game) == .entered(rank: 1))
        #expect(try scores.record(store.load(slot: game).state, end: .retired, gameID: game) == nil)
        let table = try scores.table(for: .modern)
        #expect(table.entries.count == 1 && table.entries[0].ironman && !table.entries[0].reloaded)
        try store.delete(slot: game)
        #expect(try store.list().isEmpty)
    }

    @Test("SAV-051 Palm Timewarp is a reloading load: reloadCount > 0 is GameLoaded and blocks the Palm high score")
    func palmGameLoaded() throws {
        let root = makeTempRoot()
        defer { cleanUp(root) }
        let store = SlotStore(root: root, appVersion: "t")
        for ruleset in RulesetID.allCases {
            // Snapshot = a manual slot; Switch Game = another game's slot; Timewarp = reopening an older snapshot.
            let snapshot = SlotStore.newSlotID(), later = SlotStore.newSlotID(), otherGame = SlotStore.newSlotID()
            try store.save(dayState(10, ruleset), slot: snapshot, gameID: snapshot)
            try store.save(dayState(20, ruleset), slot: later, gameID: snapshot)
            try store.save(dayState(5, ruleset), slot: otherGame, gameID: otherGame)
            let switched = try store.loadForPlay(slot: otherGame, revert: false, currentGameID: snapshot).state
            #expect(switched.reloadCount == 0 && switched.highScoreExclusion == nil)
            let warped = try store.loadForPlay(slot: snapshot, revert: false, currentGameID: otherGame).state
            #expect(warped.reloadCount == 1)
            #expect(warped.highScoreExclusion == (ruleset == .palm122 ? .excludedForReload : nil))
        }
    }
}
