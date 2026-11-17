// SPDX-License-Identifier: GPL-2.0-or-later
// LOG-038 / INT-042: the workloads `pmsim bench` times in release (Sources/pmsim/BenchInsights.swift, budgets enforced by
// `pmsim bench --check`). Here they run in debug for correctness only: no timing assertions.
import Foundation
import Testing
import ParsecEngine
@testable import ParsecInsights

@Suite("Bench workloads (correctness)")
struct BenchWorkloadTests {
    @Test("LOG-038 journal.record over fuzz games and journal.encode of a long journal produce valid, decodable output")
    func journalWorkloads() throws {
        var g = RecordedGame(.modern, seed: 2_026)
        var game: UInt64 = 0
        var r = Xoshiro256StarStar(seed: 2_026)
        var steps = 0
        while g.journal.entries.count < 2_000 {
            steps += 1
            let over: Bool = if case .gameOver = g.state.phase { true } else { false }
            if over || steps > 1_000 {
                steps = 0
                game += 1
                let journal = g.journal
                g = RecordedGame(.modern, seed: 2_026 + game)
                g.journal = journal
            }
            g.send(InsightsFuzz.pickCommand(g.state, &r))
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let bytes = try enc.encode(g.journal)
        let decoded = try JSONDecoder().decode(GameJournal.self, from: bytes)
        let again = try enc.encode(decoded)
        #expect(decoded == g.journal && again == bytes)
    }

    @Test("INT-042 intel.heatmap (every mode) and intel.recommendations on a 128-system mid-game state")
    func intelWorkloads() {
        var g = RecordedGame(.modern, seed: 4_242)
        g.fuzz(600, seed: 4_242)
        var state = g.state
        state.phase = .docked
        state.commander.ship.cargo[TradeItemType.ore.rawValue] += 5
        state.commander.priceCargo[TradeItemType.ore.rawValue] += 1_000
        let snap = IntelSnapshot(state)
        #expect(snap.systems.count == 128)
        let modes: [HeatmapMode] = [.none, .price(.robots), .holdProfit, .police, .pirates, .techLevel, .lastVisited]
        for mode in modes { #expect(HeatmapModel.values(mode: mode, intel: g.journal.intel, snapshot: snap).values.count == 128) }
        let target = snap.destinations.first ?? (snap.currentSystem + 1) % 128
        #expect(TradeIntel.bestBuys(for: target, book: g.journal.intel, snapshot: snap).count <= 3)
        #expect(TradeIntel.bestDestinations(book: g.journal.intel, snapshot: snap).count <= 3)
    }
}
