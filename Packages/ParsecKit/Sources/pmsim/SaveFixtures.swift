// SPDX-License-Identifier: GPL-2.0-or-later
// pmsim write-save-fixtures (SAV-015): deterministic saves, one per ruleset, from fixed seeds and fuzz commands.
import Foundation
import ParsecEngine
import ParsecInsights
import ParsecPersistence

func writeSaveFixtures(to dir: URL) throws {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for (i, ruleset) in RulesetID.allCases.enumerated() {
        let seed = UInt64(1_001 + i)
        var engine = GameEngine(config: NewGameConfig(commanderName: "Fixture Zoë", ruleset: ruleset, seed: seed))
        var r = Xoshiro256StarStar(seed: seed)
        // LOG-004: the journal recorded alongside the commands.
        var journal = GameJournal.start(state: engine.state)
        for _ in 0..<400 {
            if case .gameOver = engine.state.phase { break }
            let command = Fuzzer.pickCommand(engine.state, &r)
            let before = engine.state
            let result = engine.perform(command, acknowledging: Fuzzer.ackAll)
            JournalRecorder.record(JournalStep(command: command, before: before, result: result, after: engine.state),
                                   into: &journal)
        }
        let envelope = SaveEnvelope(state: engine.state, appVersion: "fixture",
                                    gameID: String(format: "00000000-0000-4000-8000-%012d", i + 1), generation: 1,
                                    journal: journal)
        let file = dir.appendingPathComponent("\(ruleset.rawValue).parsecsave")
        try SaveCodec.encode(envelope).write(to: file)
        print("wrote \(file.path) (phase \(engine.state.phase), day \(engine.state.commander.days), \(journal.entries.count) entries)")
    }
}
