// SPDX-License-Identifier: GPL-2.0-or-later
// pmsim bench (PRD §8.1): release build, N = 1000 samples, medians measured with ContinuousClock.
// Budgets: engine `perform` median < 0.5 ms; a full arrival pipeline (a warp step that docks, which runs the whole
// arrival) median < 5 ms.
import Foundation
import ParsecEngine

enum Bench {
    static let samples = 1_000
    static let performBudget: Duration = .microseconds(500)
    static let arrivalBudget: Duration = .milliseconds(5)

    static func median(_ xs: [Duration]) -> Duration {
        let sorted = xs.sorted()
        return sorted[sorted.count / 2]
    }

    static func ms(_ d: Duration) -> String {
        let c = d.components
        return String(format: "%.4f ms", Double(c.seconds) * 1_000 + Double(c.attoseconds) / 1e15)
    }

    /// Times `samples` random legal commands (the fuzzer's command picker) across all rulesets.
    static func performSamples() -> [Duration] {
        let clock = ContinuousClock()
        var out: [Duration] = []
        out.reserveCapacity(samples)
        var game = 0
        while out.count < samples {
            let id = RulesetID.allCases[game % RulesetID.allCases.count]
            var engine = GameEngine(config: NewGameConfig(commanderName: "Bench", difficulty: .normal, ruleset: id,
                                                          seed: UInt64(game + 1)))
            var r = Xoshiro256StarStar(seed: UInt64(game) &* 0x9E37_79B9 &+ 99)
            for _ in 0..<200 where out.count < samples {
                if case .gameOver = engine.state.phase { break }
                let cmd = Fuzzer.pickCommand(engine.state, &r)
                let start = clock.now
                engine.perform(cmd, acknowledging: Fuzzer.ackAll)
                out.append(clock.now - start)
            }
            game += 1
        }
        return out
    }

    /// Times warp steps that end docked at the target (a full departure + transit + arrival pipeline).
    static func arrivalSamples() -> [Duration] {
        let clock = ContinuousClock()
        var out: [Duration] = []
        out.reserveCapacity(samples)
        var seed: UInt64 = 1
        while out.count < samples {
            let id = RulesetID.allCases[Int(seed) % RulesetID.allCases.count]
            var engine = GameEngine(config: NewGameConfig(commanderName: "Bench", difficulty: .normal, ruleset: id, seed: seed))
            var quiet = engine.state.options
            quiet.alwaysIgnoreTraders = true
            quiet.alwaysIgnorePolice = true
            quiet.alwaysIgnorePirates = true
            _ = engine.perform(.setOptions(quiet))
            for target in engine.state.destinations.prefix(4) where out.count < samples {
                var trial = engine
                _ = trial.perform(.selectTarget(target))
                let start = clock.now
                trial.perform(.warp, acknowledging: Fuzzer.ackAll)
                let elapsed = clock.now - start
                if case .docked = trial.state.phase, trial.state.commander.currentSystem == target { out.append(elapsed) }
            }
            seed += 1
        }
        return out
    }
}

/// Runs the benchmarks; with `check`, returns 1 when a median exceeds its budget.
func runBench(check: Bool) -> Int32 {
    let perform = Bench.median(Bench.performSamples())
    let arrival = Bench.median(Bench.arrivalSamples())
    let performOK = perform < Bench.performBudget
    let arrivalOK = arrival < Bench.arrivalBudget
    print("bench perform: median \(Bench.ms(perform)) over \(Bench.samples) commands (budget \(Bench.ms(Bench.performBudget))) \(performOK ? "OK" : "OVER")")
    print("bench arrival: median \(Bench.ms(arrival)) over \(Bench.samples) docking warps (budget \(Bench.ms(Bench.arrivalBudget))) \(arrivalOK ? "OK" : "OVER")")
    return check && !(performOK && arrivalOK) ? 1 : 0
}
