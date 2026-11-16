// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecEngine

/// Shape of `Fixtures/harness/galaxy-windows201.json` (emitted by harness/Driver.cs from the real C# 2.01 code).
struct HarnessGalaxy: Decodable {
    struct Sys: Decodable {
        let id, x, y, size, tech, politics, pressure, resource, special, shipyard, countdown: Int
        let quantities: [Int]
        let visited: Bool
    }
    struct Crew: Decodable {
        let id: Int
        let skills: [Int]
        let system: Int
    }
    struct Cmdr: Decodable {
        let system, cash, ship, fuel, hull: Int
    }
    let seed: Int32
    let difficulty: Int
    let wormholes: [Int]
    let systems: [Sys]
    let crew: [Crew]
    let commander: Cmdr
    let buyPrices: [Int]
    let sellPrices: [Int]
}

@Suite("Galaxy generation vs C# harness (Windows 2.01)")
struct GalaxyHarnessTests {
    static let snapshots: [HarnessGalaxy] =
        (try? Fixtures.decode([HarnessGalaxy].self, "harness/galaxy-windows201.json")) ?? []

    static func generate(_ snap: HarnessGalaxy) -> GeneratedGame {
        GalaxyGenerator.newGame(ruleset: .windows201, difficulty: Difficulty(rawValue: snap.difficulty) ?? .normal,
                                seed: UInt64(UInt32(bitPattern: snap.seed)), commanderName: "Harness",
                                skills: [5, 5, 5, 5])
    }

    @Test("GAL-010 GAL-069 harness galaxy fixture loaded")
    func fixtureLoaded() {
        #expect(Self.snapshots.count == 21)
    }

    // Bit-exact agreement on 21 galaxies verifies draw order and formulas of GAL-013…GAL-052 and RNG-008/RNG-038:
    // GAL-013 GAL-014 GAL-015 GAL-016 GAL-017 GAL-018 GAL-019 GAL-020 GAL-022 GAL-029 GAL-030
    // GAL-033 GAL-034 GAL-035 GAL-036 GAL-037 GAL-049 GAL-052 RNG-008 RNG-038
    @Test("GAL-013 systems match C# exactly (see list above)", arguments: 0..<21)
    func systemsMatch(_ index: Int) throws {
        try #require(index < Self.snapshots.count)
        let snap = Self.snapshots[index]
        let game = Self.generate(snap)
        #expect(game.galaxy.systems.count == snap.systems.count)
        for (mine, theirs) in zip(game.galaxy.systems, snap.systems) {
            let label = "seed \(snap.seed) diff \(snap.difficulty) system \(theirs.id)"
            #expect(mine.x == theirs.x && mine.y == theirs.y, "\(label) position")
            #expect(mine.size.rawValue == theirs.size, "\(label) size")
            #expect(mine.techLevel.rawValue == theirs.tech, "\(label) tech")
            #expect(mine.politics.rawValue == theirs.politics, "\(label) politics")
            #expect(mine.pressure.rawValue == theirs.pressure, "\(label) pressure")
            #expect(mine.specialResource.rawValue == theirs.resource, "\(label) resource")
            #expect((mine.specialEvent?.rawValue ?? -1) == theirs.special, "\(label) special event")
            #expect((mine.shipyard?.rawValue ?? -1) == theirs.shipyard, "\(label) shipyard")
            #expect(mine.tradeItems == theirs.quantities, "\(label) quantities")
            #expect(mine.visited == theirs.visited, "\(label) visited")
        }
        #expect(game.galaxy.wormholes == snap.wormholes, "wormholes")
    }

    @Test("GAL-010 GAL-054 GAL-057 CRW-024 CRW-025 crew, commander and starting prices match C#", arguments: 0..<21)
    func crewAndPricesMatch(_ index: Int) throws {
        try #require(index < Self.snapshots.count)
        let snap = Self.snapshots[index]
        let game = Self.generate(snap)
        // Crew member 0 is the commander, whose location is tracked in `commander.currentSystem` (checked below).
        for c in snap.crew where c.id != CrewID.commander {
            #expect(game.mercenaries[c.id].skills == c.skills, "crew \(c.id) skills")
            #expect((game.mercenaries[c.id].systemID ?? -1) == c.system, "crew \(c.id) system: mine \(game.mercenaries[c.id].systemID ?? -1) C# \(c.system)")
        }
        #expect(game.commander.currentSystem == snap.commander.system)
        #expect(game.commander.cash == snap.commander.cash)
        #expect(game.commander.ship.fuel == snap.commander.fuel)
        #expect(game.commander.ship.hull == snap.commander.hull)
        #expect(game.sellPrices == snap.sellPrices, "sell prices")
        #expect(game.buyPrices == snap.buyPrices, "buy prices")
    }
}
