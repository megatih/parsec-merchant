// SPDX-License-Identifier: GPL-2.0-or-later
// MAP-033, MAP-093 (docs/specs/MAP.md §17): the pure engine queries the galaxy chart and the route planner read.
import Testing
@testable import ParsecEngine

private func fresh(_ r: RulesetID, seed: UInt64 = 42) -> GameState {
    GameEngine(config: NewGameConfig(commanderName: "Map", ruleset: r, seed: seed)).state
}

@Suite("Galaxy chart engine queries (MAP-033, MAP-093)")
struct MapQueriesSpecTests {
    @Test("MAP-033 maxSquaredDistance closed forms and negative range")
    func closedForms() {
        for r in 0...40 {
            #expect(DistanceRule.floor.maxSquaredDistance(withinRange: r) == (r + 1) * (r + 1) - 1)
            #expect(DistanceRule.rounded.maxSquaredDistance(withinRange: r) == r * r + r)
        }
        for rule in [DistanceRule.floor, .rounded] {
            #expect(rule.maxSquaredDistance(withinRange: -1) == -1)
            #expect(rule.maxSquaredDistance(withinRange: -7) == -1)
        }
    }

    @Test("MAP-033 sq ≤ maxSquaredDistance(r) iff distance(sq) ≤ r, for every sq 0…6400 and r 0…40")
    func agreesWithDistance() {
        for rule in [DistanceRule.floor, .rounded] {
            // Every squared distance, through the rule's own square root.
            for sq in 0...6_400 {
                let d = switch rule {
                case .floor: Int(Double(sq).squareRoot().rounded(.down))
                case .rounded: GalaxyGenerator.palmSqrt(sq)
                }
                for r in 0...40 {
                    #expect((sq <= rule.maxSquaredDistance(withinRange: r)) == (d <= r), "\(rule) sq \(sq) r \(r)")
                }
            }
            // Every representable dx² + dy² ≤ 6400, through the public coordinate distance.
            for dx in 0...80 {
                for dy in 0...80 where dx * dx + dy * dy <= 6_400 {
                    let sq = dx * dx + dy * dy
                    let d = GalaxyGenerator.distance(0, 0, dx, dy, rule: rule)
                    for r in 0...40 where (sq <= rule.maxSquaredDistance(withinRange: r)) != (d <= r) {
                        Issue.record("\(rule) dx \(dx) dy \(dy) r \(r)")
                    }
                }
            }
        }
    }

    @Test("MAP-093 fuelCostPerParsec follows the MOD-017 column swap and wormholeTaxPerJump is 25 × it")
    func fuelCostAndTax() {
        // The starting Gnat: C# fuelCost 1; Palm CostOfFuel 2; Modern reads the C# columns back in Palm order (2).
        let expected: [RulesetID: Int] = [.windows201: 1, .palm122: 2, .modern: 2]
        for r in RulesetID.allCases {
            var s = fresh(r)
            #expect(s.commander.ship.type == .gnat)
            #expect(s.fuelCostPerParsec == expected[r], "\(r)")
            #expect(s.fuelCostPerParsec == s.commander.ship.spec(s.ruleset).fuelCost)
            #expect(s.wormholeTaxPerJump == 25 * s.fuelCostPerParsec)
            #expect(s.fullTankCost == (s.fuelCapacity - s.commander.ship.fuel) * s.fuelCostPerParsec)
            // wormholeCosts uses it for a wormhole target and is 0 otherwise.
            if let cur = s.galaxy.wormholes.first, let dest = s.galaxy.wormholeDestination(from: cur) {
                s.commander.currentSystem = cur
                s.warpSystem = dest
                #expect(s.wormholeCosts == s.wormholeTaxPerJump)
                #expect(s.dailyCosts(to: dest).wormholeTax == s.wormholeTaxPerJump)
                let other = s.galaxy.systems.indices.first { $0 != cur && $0 != dest } ?? cur
                s.warpSystem = other
                #expect(s.wormholeCosts == 0)
            }
        }
    }

    @Test("MAP-093 a Wasp pays more per parsec and per wormhole jump")
    func biggerShip() {
        for r in RulesetID.allCases {
            var s = fresh(r)
            s.commander.ship = Ship(type: .wasp, spec: s.ruleset.tables.ship(.wasp))
            let spec = s.commander.ship.spec(s.ruleset)
            #expect(s.fuelCostPerParsec == spec.fuelCost)
            #expect(s.wormholeTaxPerJump == 25 * spec.fuelCost)
        }
    }
}
