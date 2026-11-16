// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecEngine

struct HarnessOpponents: Decodable {
    struct CrewSlot: Decodable {
        let id: Int
        let skills: [Int]
    }
    struct ShipDump: Decodable {
        let type, hull, fuel: Int
        let weapons, shields, charges, gadgets, cargo: [Int]
        let crew: [CrewSlot?]
    }
    struct Case: Decodable {
        let warp, cash, record, oppType: Int
        let ship: ShipDump
    }
    let seed: Int32
    let difficulty: Int
    let cases: [Case]
}

// Bit-exact agreement with the C# `Ship(OpponentType)` constructor verifies opponent generation (ENC opponent sections):
// ship-type weighting over ships 0…8, crew skills of the shared Opponent record, gadget/shield/weapon counts and
// picks (owned types skipped, index-0 fallback), best-of-5 shield charges and hull, cargo fill, famous captain, bottle.
@Suite("Opponent generation vs C# harness (Windows 2.01)")
struct OpponentHarnessTests {
    static let runs: [HarnessOpponents] = (try? Fixtures.decode([HarnessOpponents].self, "harness/opponents-windows201.json")) ?? []

    @Test("Opponents match C# field by field", arguments: 0..<6)
    func replay(_ index: Int) throws {
        try #require(index < Self.runs.count)
        let run = Self.runs[index]
        var s = GameState(config: NewGameConfig(commanderName: "Harness", difficulty: Difficulty(rawValue: run.difficulty) ?? .normal,
                                                ruleset: .windows201, seed: UInt64(UInt32(bitPattern: run.seed))))
        for (n, c) in run.cases.enumerated() {
            s.warpSystem = c.warp
            s.commander.cash = c.cash
            s.commander.policeRecordScore = c.record
            guard let opp = OpponentType(rawValue: c.oppType) else { Issue.record("bad type"); return }
            let ship = s.generateOpponent(opp)
            let tag = "seed \(run.seed) diff \(run.difficulty) case \(n) type \(opp)"
            #expect(ship.type.rawValue == c.ship.type, "\(tag) ship type")
            #expect(ship.hull == c.ship.hull, "\(tag) hull")
            #expect(ship.fuel == c.ship.fuel, "\(tag) fuel")
            #expect(ship.weapons.map(\.rawValue) == c.ship.weapons.filter { $0 >= 0 }, "\(tag) weapons")
            #expect(ship.shields.map(\.type.rawValue) == c.ship.shields.filter { $0 >= 0 }, "\(tag) shields")
            #expect(ship.shields.map(\.charge) == Array(c.ship.charges.prefix(ship.shields.count)), "\(tag) charges")
            #expect(ship.gadgets.map(\.rawValue) == c.ship.gadgets.filter { $0 >= 0 }, "\(tag) gadgets")
            #expect(ship.cargo == c.ship.cargo, "\(tag) cargo")
            #expect(ship.crew.map { $0 ?? -1 } == c.ship.crew.map { $0?.id ?? -1 }, "\(tag) crew ids")
            if let first = c.ship.crew.first, let f = first, f.id == CrewID.opponent {
                #expect(s.mercenaries[CrewID.opponent].skills == f.skills, "\(tag) opponent skills")
            }
            if ship.type.rawValue != c.ship.type { return }
        }
    }
}
