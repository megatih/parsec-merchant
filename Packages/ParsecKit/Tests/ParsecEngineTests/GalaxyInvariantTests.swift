// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Testing
@testable import ParsecEngine

@Suite("Galaxy invariants (GAL-068, GAL-070, GAL-072)")
struct GalaxyInvariantTests {
    static func reachableAll(_ g: Galaxy, maxHop: Int, rule: DistanceRule) -> Bool {
        let n = g.systems.count
        var seen = [Bool](repeating: false, count: n)
        var stack = [0]
        seen[0] = true
        while let i = stack.popLast() {
            var next: [Int] = (0..<n).filter {
                !seen[$0] && GalaxyGenerator.distance(g.systems[i], g.systems[$0], rule: rule) <= maxHop
            }
            if let w = g.wormholeDestination(from: i), !seen[w] { next.append(w) }
            if let k = g.wormholes.firstIndex(of: i) {
                let prev = g.wormholes[(k + g.wormholes.count - 1) % g.wormholes.count]
                if !seen[prev] { next.append(prev) }
            }
            for j in next where !seen[j] {
                seen[j] = true
                stack.append(j)
            }
        }
        return seen.allSatisfy { $0 }
    }

    static func check(_ ruleset: Ruleset, seeds: Range<UInt64>) {
        for seed in seeds {
            let game = GalaxyGenerator.newGame(ruleset: ruleset, difficulty: .normal, seed: seed, commanderName: "T",
                                               skills: [5, 5, 5, 5])
            let g = game.galaxy
            let rule = ruleset.flags.distance
            let tag = "\(ruleset.id) seed \(seed)"
            #expect(g.systems.allSatisfy { (1...153).contains($0.x) && (1...109).contains($0.y) }, "\(tag) bounds")
            var minD = Int.max
            for i in g.systems.indices {
                for j in (i + 1)..<g.systems.count {
                    minD = min(minD, GalaxyGenerator.distance(g.systems[i], g.systems[j], rule: rule))
                }
            }
            #expect(minD >= 7, "\(tag) min distance \(minD)")
            #expect(Set(g.wormholes).count == 6, "\(tag) wormholes distinct")
            #expect(reachableAll(g, maxHop: 12, rule: rule), "\(tag) reachability")
            func at(_ e: SpecialEventType) -> Int? { g.systems.firstIndex { $0.specialEvent == e } }
            for (base, event) in [(SystemID.nix, SpecialEventType.reactor), (SystemID.gemulon, .gemulon),
                                  (SystemID.daled, .experiment), (SystemID.endor, .sculpture)] {
                if let s = at(event) {
                    #expect(GalaxyGenerator.distance(g.systems[base], g.systems[s], rule: rule) >= 70, "\(tag) \(event)")
                } else {
                    Issue.record("\(tag) \(event) not placed")
                }
            }
            let yards = g.systems.filter { $0.shipyard != nil }
            #expect(yards.allSatisfy { $0.techLevel == .hiTech }, "\(tag) shipyards on Hi-Tech")
            if ruleset.flags.distinctShipyards { #expect(yards.count == 5, "\(tag) 5 distinct shipyards") }
            let start = g.systems[game.commander.currentSystem]
            #expect(start.techLevel > .preAgricultural && start.techLevel < .hiTech, "\(tag) start tech")
            #expect(start.visited)
            let close = g.systems.indices.filter {
                $0 != start.id && GalaxyGenerator.distance(g.systems[$0], start, rule: rule) <= 14
            }.count
            #expect(close >= 3, "\(tag) start reach")
            var perSystem = [Int: Int]()
            for m in game.mercenaries { if let s = m.systemID { perSystem[s, default: 0] += 1 } }
            #expect(perSystem.values.allSatisfy { $0 <= 3 }, "\(tag) mercenaries per system")
            for spec in ruleset.tables.specialEvents where spec.occurrence > 0 {
                #expect(g.systems.filter { $0.specialEvent == spec.type }.count == spec.occurrence, "\(tag) \(spec.type)")
            }
        }
    }

    @Test("GAL-070 Windows 2.01 galaxies satisfy the invariants over 1000 seeds")
    func windowsInvariants() { Self.check(.windows201, seeds: 0..<1000) }

    @Test("GAL-072 Modern galaxies satisfy the invariants and have 5 distinct shipyards over 1000 seeds")
    func modernInvariants() { Self.check(.modern, seeds: 0..<1000) }

    @Test("GAL-068 same ruleset, difficulty and seed give byte-identical canonical JSON")
    func determinism() throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        for ruleset in [RulesetID.windows201, .modern, .palm122] {
            let a = GameState(config: NewGameConfig(commanderName: "D", ruleset: ruleset, seed: 99))
            let b = GameState(config: NewGameConfig(commanderName: "D", ruleset: ruleset, seed: 99))
            #expect(try enc.encode(a) == enc.encode(b), "\(ruleset)")
            let c = GameState(config: NewGameConfig(commanderName: "D", ruleset: ruleset, seed: 100))
            #expect(try enc.encode(a) != enc.encode(c), "\(ruleset) different seed differs")
        }
    }
}
