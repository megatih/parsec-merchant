// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecEngine

struct HarnessMarket: Decodable {
    struct Step: Decodable {
        let warp: Int
        let record: Int
        let quantities: [[Int]]
        let pressures: [Int]
        let countdowns: [Int]
        let buyPrices: [Int]
        let sellPrices: [Int]
    }
    let seed: Int32
    let difficulty: Int
    let steps: [Step]
}

// Replays harness/Driver.cs `MarketSteps` against the Swift engine (Windows 2.01).
// Bit-exact agreement verifies ECO-011 ECO-012 ECO-014 ECO-015 ECO-018 ECO-025 ECO-026 ECO-028 ECO-029 ECO-030
// ECO-031 ECO-034 ECO-035 ECO-036 ECO-037 ECO-005 ECO-009 ECO-019.
@Suite("Market evolution vs C# harness (Windows 2.01)")
struct MarketHarnessTests {
    static let runs: [HarnessMarket] = (try? Fixtures.decode([HarnessMarket].self, "harness/market-windows201.json")) ?? []

    @Test("ECO-034 ECO-036 ECO-037 restock, drift, pressures and prices match C# step by step", arguments: 0..<4)
    func replay(_ index: Int) throws {
        try #require(index < Self.runs.count)
        let run = Self.runs[index]
        var s = GameState(config: NewGameConfig(commanderName: "Harness", difficulty: Difficulty(rawValue: run.difficulty) ?? .normal,
                                                ruleset: .windows201, seed: UInt64(UInt32(bitPattern: run.seed))))
        for (n, step) in run.steps.enumerated() {
            for i in stride(from: 0, to: s.galaxy.systems.count, by: 3) { s.galaxy.systems[i].countDown = (i + n) % 7 }
            for i in stride(from: 0, to: s.galaxy.systems.count, by: 5) { s.galaxy.systems[i].visited = true }
            s.commander.policeRecordScore = step.record
            s.updatePressuresAndQuantities(arrival: step.warp)
            s.calculatePrices(for: step.warp)
            let tag = "seed \(run.seed) diff \(run.difficulty) step \(n)"
            #expect(s.galaxy.systems.map(\.pressure.rawValue) == step.pressures, "\(tag) pressures")
            #expect(s.galaxy.systems.map(\.countDown) == step.countdowns, "\(tag) countdowns")
            #expect(s.galaxy.systems.map(\.tradeItems) == step.quantities, "\(tag) quantities")
            #expect(s.sellPrices == step.sellPrices, "\(tag) sell")
            #expect(s.buyPrices == step.buyPrices, "\(tag) buy")
        }
    }
}
