// SPDX-License-Identifier: GPL-2.0-or-later
// pmsim bench (PRD §8.1): release build, N = 1000 samples, medians measured with ContinuousClock.
// Budgets: engine `perform` median < 0.5 ms; a full arrival pipeline (a warp step that docks, which runs the whole
// arrival) median < 5 ms. MAP-092: `RoutePlanner.plan` median < 1 ms (both objectives), `jumpCounts` median < 0.5 ms.
import Foundation
import ParsecEngine
import ParsecInsights

enum Bench {
    static let samples = 1_000
    static let performBudget: Duration = .microseconds(500)
    static let arrivalBudget: Duration = .milliseconds(5)
    static let routeBudget: Duration = .milliseconds(1)
    static let jumpCountsBudget: Duration = .microseconds(500)

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

extension Bench {
    /// MAP-092: times `RoutePlanner.plan` (alternating objectives) and `jumpCounts` over seeded random pairs of fresh
    /// games of every ruleset.
    static func routeSamples() -> (plan: [Duration], jumpCounts: [Duration]) {
        let clock = ContinuousClock()
        let snapshots = (0..<30).map { i in
            RouteSnapshot(GameEngine(config: NewGameConfig(commanderName: "Bench", difficulty: .normal,
                                                           ruleset: RulesetID.allCases[i % RulesetID.allCases.count],
                                                           seed: UInt64(i + 1))).state)
        }
        var r = Xoshiro256StarStar(seed: 92)
        var plans: [Duration] = []
        var counts: [Duration] = []
        plans.reserveCapacity(samples)
        counts.reserveCapacity(samples)
        for i in 0..<samples {
            let snap = snapshots[i % snapshots.count]
            let from = r.next(below: snap.points.count)
            let to = r.next(below: snap.points.count)
            let objective: RouteObjective = i.isMultiple(of: 2) ? .fewestJumps : .cheapest
            var start = clock.now
            let route = RoutePlanner.plan(from: from, to: to, in: snap, objective: objective)
            plans.append(clock.now - start)
            start = clock.now
            let jumps = RoutePlanner.jumpCounts(from: from, in: snap)
            counts.append(clock.now - start)
            precondition((route == nil) == (from == to || jumps[to] == nil), "route and jumpCounts disagree")
        }
        return (plans, counts)
    }
}

/// Runs the benchmarks; with `check`, returns 1 when a median exceeds its budget.
func runBench(check: Bool) -> Int32 {
    let perform = Bench.median(Bench.performSamples())
    let arrival = Bench.median(Bench.arrivalSamples())
    let routes = Bench.routeSamples()
    let plan = Bench.median(routes.plan)
    let jumps = Bench.median(routes.jumpCounts)
    let performOK = perform < Bench.performBudget
    let arrivalOK = arrival < Bench.arrivalBudget
    let planOK = plan < Bench.routeBudget
    let jumpsOK = jumps < Bench.jumpCountsBudget
    print("bench perform: median \(Bench.ms(perform)) over \(Bench.samples) commands (budget \(Bench.ms(Bench.performBudget))) \(performOK ? "OK" : "OVER")")
    print("bench arrival: median \(Bench.ms(arrival)) over \(Bench.samples) docking warps (budget \(Bench.ms(Bench.arrivalBudget))) \(arrivalOK ? "OK" : "OVER")")
    print("bench route plan: median \(Bench.ms(plan)) over \(Bench.samples) pairs (budget \(Bench.ms(Bench.routeBudget))) \(planOK ? "OK" : "OVER")")
    print("bench route jumpCounts: median \(Bench.ms(jumps)) over \(Bench.samples) sources (budget \(Bench.ms(Bench.jumpCountsBudget))) \(jumpsOK ? "OK" : "OVER")")
    let insightsOK = Bench.runInsights()
    return check && !(performOK && arrivalOK && planOK && jumpsOK && insightsOK) ? 1 : 0
}
