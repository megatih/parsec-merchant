// SPDX-License-Identifier: GPL-2.0-or-later
// pmsim bench, M10 insights (LOG-038, INT-042): journal recording and encoding, heatmaps and recommendations.
// Budgets in release: journal.record median < 0.5 ms; journal.encode of a 20 000-entry journal < 300 ms;
// intel.heatmap (every mode, 128-system mid-game state) and intel.recommendations medians < 2 ms.
import Foundation
import ParsecEngine
import ParsecInsights
import ParsecPersistence

extension Bench {
    static let recordBudget: Duration = .microseconds(500)
    static let encodeBudget: Duration = .milliseconds(300)
    static let intelBudget: Duration = .milliseconds(2)

    /// Plays and records one fuzz command.
    static func recordedStep(_ engine: inout GameEngine, _ r: inout Xoshiro256StarStar) -> JournalStep {
        let cmd = Fuzzer.pickCommand(engine.state, &r)
        let before = engine.state
        let result = engine.perform(cmd, acknowledging: Fuzzer.ackAll)
        return JournalStep(command: cmd, before: before, result: result, after: engine.state)
    }

    /// LOG-038: `JournalRecorder.record` over fuzz games of every ruleset.
    static func recordSamples() -> [Duration] {
        let clock = ContinuousClock()
        var out: [Duration] = []
        out.reserveCapacity(samples)
        var game = 0
        while out.count < samples {
            let id = RulesetID.allCases[game % RulesetID.allCases.count]
            var engine = GameEngine(config: NewGameConfig(commanderName: "Bench", ruleset: id, seed: UInt64(game + 1)))
            var journal = GameJournal.start(state: engine.state)
            var r = Xoshiro256StarStar(seed: UInt64(game) &* 0x9E37_79B9 &+ 38)
            for _ in 0..<400 where out.count < samples {
                if case .gameOver = engine.state.phase { break }
                let step = recordedStep(&engine, &r)
                let start = clock.now
                JournalRecorder.record(step, into: &journal)
                out.append(clock.now - start)
            }
            game += 1
        }
        return out
    }

    /// LOG-038: a journal of at least 20 000 entries recorded by fuzz play (games of one galaxy size), with the state.
    static func bigJournal() -> (GameState, GameJournal) {
        var engine = GameEngine(config: NewGameConfig(commanderName: "Bench", ruleset: .modern, seed: 2_026))
        var journal = GameJournal.start(state: engine.state)
        var r = Xoshiro256StarStar(seed: 2_026)
        var game: UInt64 = 0
        var steps = 0
        while journal.entries.count < 20_000 {
            steps += 1
            if case .gameOver = engine.state.phase {
                steps = 0
                game += 1
                engine = GameEngine(config: NewGameConfig(commanderName: "Bench", ruleset: .modern, seed: 2_026 + game))
            } else if steps > 2_000 {
                // A stuck game (every command refused) is replaced too.
                game += 1
                steps = 0
                engine = GameEngine(config: NewGameConfig(commanderName: "Bench", ruleset: .modern, seed: 2_026 + game))
            }
            JournalRecorder.record(recordedStep(&engine, &r), into: &journal)
        }
        return (engine.state, journal)
    }

    /// LOG-038: encoding the big journal in a save envelope (11 samples).
    static func encodeSamples() -> [Duration] {
        let (state, journal) = bigJournal()
        let envelope = SaveEnvelope(state: state, appVersion: "bench", gameID: "bench", generation: 1, journal: journal)
        let clock = ContinuousClock()
        return (0..<11).map { _ in
            let start = clock.now
            _ = try? SaveCodec.encode(envelope)
            return clock.now - start
        }
    }

    /// INT-042: a 128-system mid-game state (Modern) with its recorded intel and a non-empty hold.
    static func midGame() -> (IntelSnapshot, IntelBook) {
        var engine = GameEngine(config: NewGameConfig(commanderName: "Bench", ruleset: .modern, seed: 4_242))
        var journal = GameJournal.start(state: engine.state)
        var r = Xoshiro256StarStar(seed: 4_242)
        for _ in 0..<1_500 {
            if case .gameOver = engine.state.phase { break }
            JournalRecorder.record(recordedStep(&engine, &r), into: &journal)
        }
        var state = engine.state
        state.phase = .docked
        if !state.commander.ship.cargo.contains(where: { $0 > 0 }) {
            state.commander.ship.cargo[TradeItemType.ore.rawValue] = 5
            state.commander.priceCargo[TradeItemType.ore.rawValue] = 1_000
        }
        return (IntelSnapshot(state), journal.intel)
    }

    /// INT-042: every heatmap mode once per sample, and bestBuys + bestDestinations per sample.
    static func intelSamples() -> (heatmap: [Duration], recommendations: [Duration]) {
        let (snap, book) = midGame()
        let modes: [HeatmapMode] = [.none, .price(.robots), .holdProfit, .police, .pirates, .techLevel, .lastVisited]
        let clock = ContinuousClock()
        var heat: [Duration] = [], recs: [Duration] = []
        for i in 0..<samples {
            var start = clock.now
            for mode in modes { _ = HeatmapModel.values(mode: mode, intel: book, snapshot: snap) }
            heat.append(clock.now - start)
            let target = snap.destinations.isEmpty ? (snap.currentSystem + 1) % snap.systems.count
                : snap.destinations[i % snap.destinations.count]
            start = clock.now
            _ = TradeIntel.bestBuys(for: target, book: book, snapshot: snap)
            _ = TradeIntel.bestDestinations(book: book, snapshot: snap)
            recs.append(clock.now - start)
        }
        return (heat, recs)
    }

    /// Prints and checks the M10 medians; returns true when all are within budget.
    static func runInsights() -> Bool {
        let record = median(recordSamples())
        let encode = median(encodeSamples())
        let intel = intelSamples()
        let heat = median(intel.heatmap), recs = median(intel.recommendations)
        let rows: [(String, Duration, Duration, String)] = [
            ("journal.record", record, recordBudget, "\(samples) steps"),
            ("journal.encode", encode, encodeBudget, "11 encodes of a 20 000-entry journal"),
            ("intel.heatmap", heat, intelBudget, "\(samples) all-mode passes"),
            ("intel.recommendations", recs, intelBudget, "\(samples) targets"),
        ]
        for (name, value, budget, what) in rows {
            print("bench \(name): median \(ms(value)) over \(what) (budget \(ms(budget))) \(value < budget ? "OK" : "OVER")")
        }
        return rows.allSatisfy { $0.1 < $0.2 }
    }
}
