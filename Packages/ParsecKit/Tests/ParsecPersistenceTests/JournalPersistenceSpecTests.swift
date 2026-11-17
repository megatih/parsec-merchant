// SPDX-License-Identifier: GPL-2.0-or-later
// LOG §1 (LOG-001…004, LOG-007; ADR-0003): the journal saved beside the state in the envelope and the slot store.
import Foundation
import Testing
@testable import ParsecEngine
import ParsecInsights
@testable import ParsecPersistence

/// A journal with entries of every kind, template and generated flavor, an open ledger and intel histories.
private func richJournal(_ state: GameState) -> GameJournal {
    var journal = GameJournal.start(state: state)
    var engine = GameEngine(state: state)
    var r = Xoshiro256StarStar(seed: 99)
    for _ in 0..<250 {
        if case .gameOver = engine.state.phase { break }
        let command = FuzzPlayer.pickCommand(engine.state, &r)
        let before = engine.state
        let result = engine.perform(command, acknowledging: FuzzPlayer.ackAll)
        JournalRecorder.record(JournalStep(command: command, before: before, result: result, after: engine.state), into: &journal)
    }
    let kinds: [LogEntryKind] = [
        .cheatsEnabled, .gameEnded(.boughtMoonGirl, score: 9), .achievementUnlocked(.moon),
        .trade(TradeEntry(action: .orbitSell, item: .robots, quantity: 2, total: 9, profit: -3)),
        .departed(from: 0, to: 1, viaWormhole: true, parsecs: 0), .fabricRip(newDestination: 2), .singularityLost,
        .arrived(TripArrival(system: 1, from: 0, viaWormhole: true, firstVisit: true, uneventful: false, encounterCount: 2)),
        .encounter(EncounterRecord(type: .captainAhab, opponent: .wasp, rounds: 3, outcome: .trained(.pilot), bounty: 0,
                                   minHullPercent: 9, killsAfter: Kills(pirates: 1, police: 2, traders: 3))),
        .police(.arrested(term: 30, fine: 1, shipSold: true)), .finance(.repaid(amount: 1, remainingDebt: 0)),
        .ship(.equipment(.soldGadget(.cloakingDevice), price: 4)), .crew(.passengerImpatient(crewID: 33)),
        .quest(.tribblesDied(.narcotics(converted: 2))), .news(NewsEntry(headlines: [.canned(government: .anarchy, index: 1)], cost: 2)),
        .status(.reputation(from: .poor, to: .elite)),
    ]
    for (i, kind) in kinds.enumerated() {
        let id = journal.nextEntryID
        journal.entries.append(LogEntry(id: id, day: state.commander.days, system: 0, worth: Int.max - i, kind: kind,
                                        flavor: i % 2 == 0 ? .generated(text: "Zoë sagte \"Hallo\" \\ / 🚀\n") : nil))
        journal.nextEntryID += 1
    }
    journal.openEncounter = EncounterLedger(type: .policeInspect, opponent: .gnat, startDay: 1, startSystem: 0, clicks: 4, rounds: 1,
                                            minPlayerHull: 3, playerHullStrength: 100,
                                            events: [.combatRound(round: 1, playerHit: true, opponentHit: false, playerHull: 3,
                                                                  opponentHull: 9), .bribed(5)],
                                            surrendered: true)
    return journal
}

@Suite("LOG journal persistence")
struct JournalPersistenceSpecTests {
    @Test("LOG-001 the journal is a top-level envelope key beside state; GameState and its encoding are unchanged")
    func besideState() throws {
        let state = newState(.modern)
        let journal = richJournal(state)
        let e = SaveEnvelope(state: state, appVersion: "t", gameID: "g", generation: 1, journal: journal)
        let raw = try SaveCodec.rawObject(SaveCodec.encode(e))
        #expect(raw["journal"] != nil)
        let stateObject = try #require(raw["state"] as? [String: Any])
        #expect(stateObject["journal"] == nil && stateObject["entries"] == nil && stateObject["intel"] == nil)
        // The state's canonical bytes do not depend on the journal.
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let plain = SaveEnvelope(state: state, appVersion: "t", gameID: "g", generation: 1)
        #expect(try enc.encode(e.state) == enc.encode(plain.state))
    }

    @Test("LOG-003 byte-identical round trips with every entry kind, both flavors, non-ASCII text, an open ledger and intel",
          arguments: RulesetID.allCases)
    func roundTrip(_ ruleset: RulesetID) throws {
        let state = newState(ruleset, name: "Zoë 🚀")
        let e = SaveEnvelope(state: state, appVersion: "t", gameID: "g", generation: 1, journal: richJournal(state))
        let bytes = try SaveCodec.encode(e)
        let decoded = try SaveCodec.decode(bytes)
        #expect(decoded == e && decoded.journal.openEncounter?.surrendered == true)
        #expect(try SaveCodec.encode(decoded) == bytes)
        #expect(decoded.journal.intel.systems.contains { !$0.history.isEmpty })
    }

    @Test("LOG-004 a save without journal bootstraps one; an undecodable journal is corrupt; v1 fixtures carry journals")
    func schema() throws {
        let state = newState(.windows201)
        let missing = try SaveCodec.decode(editedSave(state) { $0["journal"] = nil })
        #expect(missing.journal == GameJournal.bootstrap(from: state))
        #expect(saveError { _ = try SaveCodec.decode(editedSave(state) { $0["journal"] = ["entries": 5] }) } != nil)
        if case .corrupt? = saveError({ _ = try SaveCodec.decode(editedSave(state) { $0["journal"] = "nope" }) }) {} else {
            Issue.record("expected corrupt")
        }
        var shortIntel = GameJournal.start(state: state)
        shortIntel.intel.systems.removeLast()
        let bad = try SaveCodec.encode(SaveEnvelope(state: state, appVersion: "t", gameID: "g", generation: 1, journal: shortIntel))
        if case .corrupt? = saveError({ _ = try SaveCodec.decode(bad) }) {} else { Issue.record("expected corrupt intel") }
        // The regenerated v1 fixtures hold recorded journals.
        for ruleset in RulesetID.allCases {
            let data = try Data(contentsOf: saveFixturesRoot.appendingPathComponent("v1/\(ruleset.rawValue).parsecsave"))
            #expect(try SaveCodec.rawObject(data)["journal"] != nil)
            let journal = try SaveCodec.decode(data).journal
            guard case let .journalStarted(start)? = journal.entries.first?.kind else { Issue.record("no start entry"); continue }
            #expect(start.origin == .newGame && journal.entries.count > 1)
        }
    }

    @Test("LOG-007 save, autosave, load for play, import and export carry the journal; Revert rewinds it")
    func slots() throws {
        let root = makeTempRoot()
        defer { cleanUp(root) }
        let store = SlotStore(root: root, appVersion: "t")
        let state = newState(.modern)
        let early = GameJournal.start(state: state)
        let late = richJournal(state)
        try store.autosave(state, journal: early, gameID: "game")
        try store.save(state, journal: late, slot: "s1", gameID: "game")
        #expect(try store.load(slot: "s1").journal == late)
        #expect(try store.loadForPlay(slot: "s1", revert: false, currentGameID: nil).journal == late)
        // Revert to Autosave restores the journal saved with that state.
        #expect(try store.loadForPlay(slot: SlotStore.autosaveID, revert: true, currentGameID: "game").journal == early)
        let exported = try store.exportSave(slot: "s1")
        #expect(try SaveCodec.decode(exported).journal == late)
        let imported = try store.importSave(exported)
        #expect(try store.load(slot: imported).journal == late)
        // Pre-M10 entry points write a bootstrapped journal.
        try store.save(state, slot: "s2", gameID: "other")
        #expect(try store.load(slot: "s2").journal == GameJournal.bootstrap(from: state))
        try store.autosave(state, gameID: "other")
        #expect(try store.load(slot: SlotStore.autosaveID).journal == GameJournal.bootstrap(from: state))
    }
}
