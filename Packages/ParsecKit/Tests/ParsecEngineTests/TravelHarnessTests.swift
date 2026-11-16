// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecEngine

struct HarnessTravel: Decodable {
    struct Enc: Decodable {
        let clicks, type: Int
        let opp: HarnessOpponents.ShipDump
    }
    struct Warp: Decodable {
        let target, arrived, days, cash, debt, record, fuel, hull: Int
        let encounters: [Enc]
        let shields, buy, sell, stock, news, opponentSkills: [Int]
    }
    let seed: Int32
    let difficulty: Int
    let warps: [Warp]
}

// Journeys replayed against C# Game.Warp with a recording FormEncounter stub (returns Normal, no fighting).
// Bit-exact agreement verifies warp checks/departure (costs, fuel, interest, IncDays, countdown, departure prices),
// per-click repairs, fixed/random/very-rare encounter determination, opponent generation in context, the cloak test,
// police inspection flag, trade-in-orbit roll, and the arrival pipeline (tribbles, debt, repairs, shields,
// pressures/quantities, Easter egg, prices, arrival news).
@Suite("Journeys vs C# harness (Windows 2.01)")
struct TravelHarnessTests {
    static let runs: [HarnessTravel] = (try? Fixtures.decode([HarnessTravel].self, "harness/travel-windows201.json")) ?? []

    @Test("Warps, encounters and arrivals match C#", arguments: 0..<9)
    func replay(_ index: Int) throws {
        try #require(index < Self.runs.count)
        let run = Self.runs[index]
        var e = GameEngine(config: NewGameConfig(commanderName: "Harness", difficulty: Difficulty(rawValue: run.difficulty) ?? .normal,
                                                 ruleset: .windows201, seed: UInt64(UInt32(bitPattern: run.seed))))
        e.state.options.alwaysIgnoreTraders = false
        for (w, expected) in run.warps.enumerated() {
            let tag = "seed \(run.seed) diff \(run.difficulty) warp \(w)"
            e.state.commander.ship.fuel = e.state.commander.ship.fuelTanks(e.ruleset)
            e.state.commander.cash = max(e.state.commander.cash, 20_000)
            if w % 5 == 4 { e.state.commander.policeRecordScore = -12 }
            e.state.commander.ship.hull = max(1, e.state.commander.ship.hull - (w % 3) * 7)
            let dest = e.state.destinations
            let target = dest[(w * 7) % dest.count]
            #expect(target == expected.target, "\(tag) target")
            _ = e.perform(.selectTarget(target))
            var seen: [EncounterState] = []
            _ = e.perform(.warp)
            while case let .encounter(enc) = e.state.phase {
                seen.append(enc)
                _ = e.finishEncounter(.normal)
            }
            #expect(seen.count == expected.encounters.count, "\(tag) encounter count \(seen.count) vs \(expected.encounters.count)")
            for (mine, theirs) in zip(seen, expected.encounters) {
                #expect(mine.clicks == theirs.clicks && mine.type.rawValue == theirs.type, "\(tag) encounter at \(theirs.clicks)")
                #expect(mine.opponent.type.rawValue == theirs.opp.type && mine.opponent.hull == theirs.opp.hull, "\(tag) opponent")
                #expect(mine.opponent.weapons.map(\.rawValue) == theirs.opp.weapons.filter { $0 >= 0 }, "\(tag) opp weapons")
                #expect(mine.opponent.cargo == theirs.opp.cargo, "\(tag) opp cargo")
            }
            let s = e.state
            #expect(s.commander.currentSystem == expected.arrived, "\(tag) arrived")
            #expect(s.commander.days == expected.days, "\(tag) days")
            #expect(s.commander.cash == expected.cash && s.commander.debt == expected.debt, "\(tag) cash/debt")
            #expect(s.commander.policeRecordScore == expected.record, "\(tag) record")
            #expect(s.commander.ship.fuel == expected.fuel && s.commander.ship.hull == expected.hull, "\(tag) fuel/hull")
            #expect(s.commander.ship.shields.map(\.charge) == expected.shields, "\(tag) shields")
            #expect(s.buyPrices == expected.buy && s.sellPrices == expected.sell, "\(tag) prices")
            #expect(s.currentSystem.tradeItems == expected.stock, "\(tag) stock")
            #expect(s.newsEvents.map(\.rawValue) == expected.news, "\(tag) news")
            #expect(s.mercenaries[CrewID.opponent].skills == expected.opponentSkills, "\(tag) opponent crew skills")
            if s.commander.currentSystem != expected.arrived || seen.count != expected.encounters.count { return }
        }
    }
}
