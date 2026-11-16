// SPDX-License-Identifier: GPL-2.0-or-later
// pmsim write-save-fixtures (SAV-015): deterministic saves, one per ruleset, from fixed seeds and fuzz commands.
import Foundation
import ParsecEngine
import ParsecPersistence

func writeSaveFixtures(to dir: URL) throws {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for (i, ruleset) in RulesetID.allCases.enumerated() {
        let seed = UInt64(1_001 + i)
        var engine = GameEngine(config: NewGameConfig(commanderName: "Fixture Zoë", ruleset: ruleset, seed: seed))
        var r = Xoshiro256StarStar(seed: seed)
        for _ in 0..<400 {
            if case .gameOver = engine.state.phase { break }
            engine.perform(Fuzzer.pickCommand(engine.state, &r), acknowledging: Fuzzer.ackAll)
        }
        let envelope = SaveEnvelope(state: engine.state, appVersion: "fixture",
                                    gameID: String(format: "00000000-0000-4000-8000-%012d", i + 1), generation: 1)
        let file = dir.appendingPathComponent("\(ruleset.rawValue).parsecsave")
        try SaveCodec.encode(envelope).write(to: file)
        print("wrote \(file.path) (phase \(engine.state.phase), day \(engine.state.commander.days))")
    }
}
