// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Testing
@testable import ParsecEngine

/// A random source that returns scripted values first (each checked against its bound), then falls back to a seeded LCG.
private struct ScriptedRNG: RandomSource {
    var script: [Int]
    var fallback = PalmLCG(seed: 7)
    var calls = 0

    init(_ script: [Int]) { self.script = script }

    mutating func next(below max: Int) -> Int {
        calls += 1
        guard !script.isEmpty else { return fallback.next(below: max) }
        let v = script.removeFirst()
        precondition(v >= 0 && v < max, "scripted \(v) out of 0..<\(max)")
        return v
    }

    mutating func next(in min: Int, _ max: Int) -> Int { min + next(below: max - min) }
}

/// Records every draw (bound and kind) while delegating to a real generator.
private struct RecordingRNG: RandomSource {
    enum Call: Equatable { case below(Int), range(Int, Int) }
    var inner: RNGState
    var calls: [Call] = []

    mutating func next(below max: Int) -> Int {
        calls.append(.below(max))
        return inner.next(below: max)
    }

    mutating func next(in min: Int, _ max: Int) -> Int {
        calls.append(.range(min, max))
        return inner.next(in: min, max)
    }
}

/// Shared builders for the galaxy ruleset suites.
enum GalKit {
    static func game(_ r: Ruleset, seed: UInt64, difficulty: Difficulty = .normal) -> GeneratedGame {
        GalaxyGenerator.newGame(ruleset: r, difficulty: difficulty, seed: seed, commanderName: "T", skills: [5, 5, 5, 5])
    }

    /// A hand-built galaxy: every system at `(0, 0)` with the given tech, wormholes 0…5, no events.
    static func flatGalaxy(count: Int = 120, tech: TechLevel = .agricultural) -> Galaxy {
        let systems = (0..<count).map {
            StarSystem(id: $0, x: 0, y: 0, size: .small, techLevel: tech, politics: .democracy, pressure: .none,
                       specialResource: .nothing)
        }
        return Galaxy(systems: systems, wormholes: Array(0..<6))
    }

    static func palmLiteralSqrt(_ a: Int) -> Int {
        var i = 0
        while i * i < a { i += 1 }
        if i > 0 {
            if (i * i - a) > (a - (i - 1) * (i - 1)) { i -= 1 }
        }
        return i
    }

    static func ruleset(_ base: Ruleset, _ edit: (inout Ruleset) -> Void) -> Ruleset {
        var r = base
        edit(&r)
        return r
    }
}

/// Palm galaxy generation, placement and start system; the Palm/Modern GAL rows and RUL-020…031.
@Suite("Galaxy rulesets (RUL-020…031, Palm GAL)")
struct GalaxyRulesetSpecTests {
    // MARK: Distances

    @Test("RUL-020 distance: floor in Modern/Windows, round-to-nearest in Palm ((5,5) → 7/7, (6,5) → 7/8)")
    func distanceRounding() {
        #expect(Ruleset.modern.flags.distance == .floor && Ruleset.windows201.flags.distance == .floor)
        #expect(Ruleset.palm122.flags.distance == .rounded)
        #expect(GalaxyGenerator.distance(0, 0, 5, 5, rule: .floor) == 7 && GalaxyGenerator.distance(0, 0, 5, 5, rule: .rounded) == 7)
        #expect(GalaxyGenerator.distance(0, 0, 6, 5, rule: .floor) == 7 && GalaxyGenerator.distance(0, 0, 6, 5, rule: .rounded) == 8)
        // The engine's travel distance follows the ruleset's rule.
        let e = makeEngine(.palm122)
        let a = e.state.galaxy.systems[0], b = e.state.galaxy.systems[1]
        #expect(GalaxyGenerator.distance(a, b, rule: e.ruleset.flags.distance)
                == GalaxyGenerator.palmSqrt(GalaxyGenerator.sqrDistance(a, b)))
    }

    @Test("GAL-008 the Palm sqrt equals a literal Math.c transliteration for every a in 0…34600 (12→3, 13→4, 56→7, 57→8)")
    func palmSqrtTransliteration() {
        for a in 0...34_600 { #expect(GalaxyGenerator.palmSqrt(a) == GalKit.palmLiteralSqrt(a)) }
        #expect(GalaxyGenerator.palmSqrt(12) == 3 && GalaxyGenerator.palmSqrt(13) == 4)
        #expect(GalaxyGenerator.palmSqrt(56) == 7 && GalaxyGenerator.palmSqrt(57) == 8)
    }

    @Test("GAL-009 sqrDistance and realDistance are exact integers beyond 32767 (opposite corners)")
    func exactArithmetic() {
        let a = StarSystem(id: 0, x: 1, y: 1, size: .tiny, techLevel: .hiTech, politics: .anarchy, pressure: .none,
                           specialResource: .nothing)
        var b = a
        b.x = 150
        b.y = 110
        let sq = GalaxyGenerator.sqrDistance(a, b)
        #expect(sq == 149 * 149 + 109 * 109 && sq > 32_767)
        #expect(GalaxyGenerator.distance(a, b, rule: .rounded) == 185)   // 184² = 33856 < 34082 < 34225 = 185², nearer 185
    }

    @Test("RUL-021 a candidate exactly 7 away is accepted in Modern/Windows (floor(d) < 7) and rejected in Palm (d² ≤ 49)")
    func minDistanceTest() {
        #expect(!GalaxyGenerator.tooClose(squared: 49, ruleset: .windows201))
        #expect(!GalaxyGenerator.tooClose(squared: 49, ruleset: .modern))
        #expect(GalaxyGenerator.tooClose(squared: 48, ruleset: .windows201))
        #expect(GalaxyGenerator.tooClose(squared: 49, ruleset: .palm122))
        #expect(!GalaxyGenerator.tooClose(squared: 50, ruleset: .palm122))
        var exactSeven = false
        for seed in UInt64(0)..<30 {
            let p = GalKit.game(.palm122, seed: seed).galaxy.systems
            let w = GalKit.game(.windows201, seed: seed).galaxy.systems
            for i in p.indices {
                for j in (i + 1)..<p.count { #expect(GalaxyGenerator.sqrDistance(p[i], p[j]) >= 50) }
            }
            for i in w.indices {
                for j in (i + 1)..<w.count where GalaxyGenerator.sqrDistance(w[i], w[j]) == 49 { exactSeven = true }
            }
        }
        #expect(exactSeven, "Windows accepts pairs at exactly 7")
    }

    @Test("RUL-022 GAL-024 wormhole offsets: ±12 around 25/77/128 × 27/82 (Modern/Windows), ±6 around 25/75/125 × 27/82 (Palm)")
    func centreOffsets() {
        var lo = ScriptedRNG([0]), hi = ScriptedRNG([24])
        #expect(GalaxyGenerator.centreOffset(.symmetricRange, 13, rng: &lo) == 12)
        #expect(GalaxyGenerator.centreOffset(.symmetricRange, 13, rng: &hi) == -12)
        var plo = ScriptedRNG([0]), phi = ScriptedRNG([12])
        #expect(GalaxyGenerator.centreOffset(.subtractFromHalf, 6, rng: &plo) == 6)
        #expect(GalaxyGenerator.centreOffset(.subtractFromHalf, 6, rng: &phi) == -6)
        func boxes(_ r: Ruleset, xs: [ClosedRange<Int>], ys: [ClosedRange<Int>]) {
            for seed in UInt64(0)..<100 {
                let g = GalKit.game(r, seed: seed).galaxy
                var hit = Set<Int>()
                for w in g.wormholes {
                    let s = g.systems[w]
                    let bx = xs.firstIndex { $0.contains(s.x) }, by = ys.firstIndex { $0.contains(s.y) }
                    #expect(bx != nil && by != nil, "\(r.id) seed \(seed) wormhole at \(s.x),\(s.y)")
                    if let bx, let by { hit.insert(by * 3 + bx) }
                }
                #expect(hit.count == 6, "\(r.id) seed \(seed): one wormhole per box")
            }
        }
        boxes(.windows201, xs: [13...37, 65...89, 116...140], ys: [15...39, 70...94])
        boxes(.modern, xs: [13...37, 65...89, 116...140], ys: [15...39, 70...94])
        boxes(.palm122, xs: [19...31, 69...81, 119...131], ys: [21...33, 76...88])
    }

    // MARK: Per-system generation

    @Test("RUL-023 GAL-026 Palm (TL, government) pairs are uniform over the 81 valid pairs; Windows governments are uniform")
    func governmentDistribution() {
        let t = Ruleset.palm122.tables
        let valid = t.politicalSystems.map { $0.maxTech.rawValue - $0.minTech.rawValue + 1 }
        #expect(valid.reduce(0, +) == 81 && valid[PoliticalSystemType.dictatorship.rawValue] == 8
                && valid[PoliticalSystemType.satori.rawValue] == 2)
        var palm = [Int](repeating: 0, count: 17), win = [Int](repeating: 0, count: 17)
        var n = 0, nw = 0
        for seed in UInt64(0)..<100 {
            for s in GalKit.game(.palm122, seed: seed).galaxy.systems {
                let pol = t.politics(s.politics)
                #expect(s.techLevel >= pol.minTech && s.techLevel <= pol.maxTech)
                palm[s.politics.rawValue] += 1
                n += 1
            }
            for s in GalKit.game(.windows201, seed: seed).galaxy.systems where s.id != SystemID.galvon {
                win[s.politics.rawValue] += 1
                nw += 1
            }
        }
        func within(_ count: Int, _ total: Int, _ p: Double) -> Bool {
            let mean = Double(total) * p, sigma = (Double(total) * p * (1 - p)).squareRoot()
            return abs(Double(count) - mean) <= 3 * sigma
        }
        for g in 0..<17 {
            #expect(within(palm[g], n, Double(valid[g]) / 81), "Palm government \(g): \(palm[g]) of \(n)")
            #expect(within(win[g], nw, 1.0 / 17), "Windows government \(g): \(win[g]) of \(nw)")
        }
    }

    @Test("RUL-024 GAL-023 per-system draw order: C# size, gov, TL, pressure… ; Palm X, Y, TL, gov, resource, size, status")
    func perSystemDrawOrder() {
        var w = RecordingRNG(inner: RNGState(kind: .dotNet, seed: 9))
        _ = GalaxyGenerator.generateUniverse(ruleset: .windows201, difficulty: .normal, rng: &w)
        #expect(Array(w.calls.prefix(2)) == [.below(5), .below(17)])
        if case .range = w.calls[2] {} else { Issue.record("C# third draw is the TL range: \(w.calls[2])") }
        #expect(w.calls[3] == .below(100))

        var p = RecordingRNG(inner: RNGState(kind: .palmLCG, seed: 9))
        let galaxy = GalaxyGenerator.generateUniverse(ruleset: .palm122, difficulty: .normal, rng: &p)
        #expect(Array(p.calls.prefix(4)) == [.below(13), .below(13), .below(8), .below(17)])
        // Find the first accepted attempt of slot 0 and check the remaining order: resource, (kind), size, status.
        var i = 0
        while i + 4 < p.calls.count {
            guard Array(p.calls[i..<(i + 4)]) == [.below(13), .below(13), .below(8), .below(17)] else { break }
            i += 4
            if p.calls[i] == .below(5) { break }   // accepted: resource roll follows
        }
        #expect(p.calls[i] == .below(5))
        var j = i + 1
        if galaxy.systems[0].specialResource != .nothing {
            #expect(p.calls[j] == .below(12))
            j += 1
        }
        #expect(p.calls[j] == .below(5) && p.calls[j + 1] == .below(100))
        // Non-wormhole slots draw X = 1 + r(148), Y = 1 + r(108).
        #expect(p.calls.contains(.below(148)) && p.calls.contains(.below(108)) && !p.calls.contains(.range(1, 150)))
    }

    @Test("RUL-024 GAL-011 new-game order: C# universe, events, start, crew; Palm universe, mercenaries, events, start")
    func newGameOrder() {
        for seed in UInt64(0)..<5 {
            let palm = GalKit.game(.palm122, seed: seed)
            var rng = RNGState(kind: .palmLCG, seed: seed)
            var g = GalaxyGenerator.generateUniverse(ruleset: .palm122, difficulty: .normal, rng: &rng)
            let mercs = GalaxyGenerator.generateCrew(galaxy: g, ruleset: .palm122, difficulty: .normal, rng: &rng)
            #expect(GalaxyGenerator.placeSpecialEvents(&g, ruleset: .palm122, rng: &rng))
            let start = GalaxyGenerator.startSystem(galaxy: g, ruleset: .palm122, reach: 14, rng: &rng)
            #expect(palm.commander.currentSystem == start && palm.attempts == 1)
            #expect(palm.mercenaries.dropFirst().map(\.systemID) == mercs.dropFirst().map(\.systemID))
            #expect(palm.galaxy.systems.map(\.specialEvent) == g.systems.map(\.specialEvent))

            let win = GalKit.game(.windows201, seed: seed)
            var wr = RNGState(kind: .dotNet, seed: seed)
            var wg = GalaxyGenerator.generateUniverse(ruleset: .windows201, difficulty: .normal, rng: &wr)
            guard win.attempts == 1 else { continue }
            #expect(GalaxyGenerator.placeSpecialEvents(&wg, ruleset: .windows201, rng: &wr))
            #expect(GalaxyGenerator.placeShipyards(&wg, ruleset: .windows201, rng: &wr))
            let ws = GalaxyGenerator.startSystem(galaxy: wg, ruleset: .windows201, reach: 14, rng: &wr)
            let wm = GalaxyGenerator.generateCrew(galaxy: wg, ruleset: .windows201, difficulty: .normal, rng: &wr)
            #expect(win.commander.currentSystem == ws && win.mercenaries.dropFirst().map(\.systemID) == wm.dropFirst().map(\.systemID))
        }
    }

    @Test("GAL-025 Palm positions: X = 1 + r(148), Y = 1 + r(108); d² ≤ 49 to an earlier system rejects, a d² < 169 neighbour is required")
    func palmPositionTest() {
        // Wormhole slots: offset draw 6 (→ 0), TL 0, Anarchy, no resource, Tiny, no status, then 2 traded items × 3 draws.
        let wormholeSlot = [6, 6, 0, 0, 0, 0, 99, 0, 0, 0, 0, 0, 0]
        let slot6 = [31, 26,          // (32, 27): d² = 49 to (25, 27) → rejected
                     32, 26] + Array(wormholeSlot.dropFirst(2))   // (33, 27): d² = 64 → accepted
        var rng = ScriptedRNG(Array(repeating: wormholeSlot, count: 6).flatMap { $0 } + slot6)
        let g = GalaxyGenerator.generateUniverse(ruleset: .palm122, difficulty: .normal, rng: &rng)
        let coords = Set(g.systems.map { [$0.x, $0.y] })
        #expect(coords.isSuperset(of: [[25, 27], [75, 27], [125, 27], [25, 82], [75, 82], [125, 82]]))
        #expect(coords.contains([33, 27]) && !coords.contains([32, 27]))
        // Every non-wormhole system lies in 1…148 × 1…108 and the X/Y draws use r(148) and r(108).
        var rec = RecordingRNG(inner: RNGState(kind: .palmLCG, seed: 2))
        let h = GalaxyGenerator.generateUniverse(ruleset: .palm122, difficulty: .normal, rng: &rec)
        #expect(rec.calls.filter { $0 == .below(148) }.count == rec.calls.filter { $0 == .below(108) }.count)
        #expect(h.systems.allSatisfy { (1...148).contains($0.x) && (1...108).contains($0.y) })
        for (i, s) in h.systems.enumerated() {
            let near = h.systems.indices.contains { $0 != i && GalaxyGenerator.sqrDistance(h.systems[$0], s) < 169 }
            #expect(near || h.wormholes.contains(i), "system \(i) has a close neighbour")
        }
    }

    @Test("GAL-012 the Palm galaxy uses the wizard's difficulty: same layout and draws, robot/narcotics stock follows difficulty")
    func palmDifficultyAtGeneration() {
        let easy = GalKit.game(.palm122, seed: 11, difficulty: .beginner).galaxy
        let hard = GalKit.game(.palm122, seed: 11, difficulty: .impossible).galaxy
        #expect(easy.systems.map(\.x) == hard.systems.map(\.x) && easy.systems.map(\.y) == hard.systems.map(\.y))
        #expect(easy.systems.map(\.techLevel) == hard.systems.map(\.techLevel))
        let illegalHigh = easy.systems.indices.contains {
            easy.systems[$0].tradeItems[TradeItemType.robots.rawValue] != hard.systems[$0].tradeItems[TradeItemType.robots.rawValue]
        }
        #expect(illegalHigh)
        // Lower items do not depend on difficulty.
        #expect(easy.systems.map { $0.tradeItems[0] } == hard.systems.map { $0.tradeItems[0] })
    }

    @Test("GAL-021 Modern starting quantities use the true resource with the same draw count as without MOD-006")
    func modernResourceQuantities() {
        let hidden = GalKit.ruleset(.modern) { $0.flags.resourcesAffectUnvisitedSystems = false }
        var differs = false
        for seed in UInt64(0)..<10 {
            let a = GalKit.game(.modern, seed: seed), b = GalKit.game(hidden, seed: seed)
            #expect(a.galaxy.systems.map(\.x) == b.galaxy.systems.map(\.x), "draw count unchanged")
            #expect(a.rng == b.rng)
            for (s, t) in zip(a.galaxy.systems, b.galaxy.systems) where s.specialResource != .nothing && s.tradeItems != t.tradeItems {
                differs = true
            }
        }
        #expect(differs)
    }

    @Test("GAL-028 each Palm system starts with no event, countdown 0 and not visited")
    func palmFreshSystems() {
        var rng = RNGState(kind: .palmLCG, seed: 4)
        let g = GalaxyGenerator.generateUniverse(ruleset: .palm122, difficulty: .normal, rng: &rng)
        #expect(g.systems.count == 120)
        #expect(g.systems.allSatisfy { $0.specialEvent == nil && $0.countDown == 0 && !$0.visited && $0.shipyard == nil })
    }
}

/// Palm/Windows special-event placement, shipyards, mercenaries, start system and the Palm invariants.
@Suite("Galaxy placement rulesets (RUL-025…031, Palm GAL)")
struct GalaxyPlacementSpecTests {
    // MARK: Placement

    @Test("RUL-025 Palm never regenerates: placement failures are skipped (Windows fails and regenerates)")
    func noRegeneration() {
        for seed in UInt64(0)..<200 { #expect(GalKit.game(.palm122, seed: seed).attempts == 1) }
        var noHiTech = GalKit.flatGalaxy()
        var w = noHiTech
        var r1 = ScriptedRNG([])
        #expect(GalaxyGenerator.placeSpecialEvents(&noHiTech, ruleset: .palm122, rng: &r1))
        var r2 = ScriptedRNG([])
        #expect(!GalaxyGenerator.placeSpecialEvents(&w, ruleset: .windows201, rng: &r2))
    }

    @Test("RUL-026 GAL-042 Scarab end-point: Windows first free wormhole; Palm ≤ 20 re-draws, G/D/N quirk, else no Scarab")
    func scarabEndpoint() {
        // Windows: wormholes 0…5 ring order; 0 and 1 occupied → 2.
        var w = GalKit.flatGalaxy(count: 128)
        w.systems[0].specialEvent = .lottery
        w.wormholes = [0, 1, 2, 3, 4, 5]
        w.systems[1].specialEvent = .skill
        let only = GalKit.ruleset(.windows201) { $0.flags.galaxy.eventPlacement = [.scarabEndpoint] }
        var none = ScriptedRNG([])
        #expect(GalaxyGenerator.placeSpecialEvents(&w, ruleset: only, rng: &none))
        #expect(w.systems[2].specialEvent == .scarabDestroyed && none.calls == 0)

        let palmOnly = GalKit.ruleset(.palm122) { $0.flags.galaxy.eventPlacement = [.scarabEndpoint, .randomEvents] }
        // Every wormhole occupied (non-G/D/N): 21 draws, then no Scarab; its random placement draws are still consumed.
        var g = GalKit.flatGalaxy()
        g.wormholes = [1, 2, 3, 4, 5, 7]
        for s in g.wormholes { g.systems[s].specialEvent = .skill }
        var rng = ScriptedRNG(Array(repeating: 0, count: 21))
        #expect(GalaxyGenerator.placeSpecialEvents(&g, ruleset: palmOnly, rng: &rng))
        #expect(rng.script.isEmpty && !g.systems.contains { $0.specialEvent == .scarabDestroyed })
        #expect(!g.systems.contains { $0.specialEvent == .scarab })
        // A free wormhole on the 20th draw (k = 19) is accepted; on the 21st (k = 20) it is not.
        for (draws, placed) in [(20, true), (21, false)] {
            var h = GalKit.flatGalaxy()
            h.wormholes = [1, 2, 3, 4, 5, 7]
            for s in h.wormholes.dropLast() { h.systems[s].specialEvent = .skill }
            var rng2 = ScriptedRNG(Array(repeating: 0, count: draws - 1) + [5])
            _ = GalaxyGenerator.placeSpecialEvents(&h, ruleset: palmOnly, rng: &rng2)
            #expect((h.systems[7].specialEvent == .scarabDestroyed) == placed, "\(draws) draws")
            #expect(h.systems.filter { $0.specialEvent == .scarab }.count == (placed ? 1 : 0), "\(draws) draws")
        }
        // Quirk: an occupied Gemulon wormhole stops the loop and the end-point overwrites it.
        var q = GalKit.flatGalaxy()
        q.wormholes = [1, 2, 3, 4, 5, SystemID.gemulon]
        for s in q.wormholes { q.systems[s].specialEvent = .skill }
        var rng3 = ScriptedRNG([5])
        _ = GalaxyGenerator.placeSpecialEvents(&q, ruleset: palmOnly, rng: &rng3)
        #expect(q.systems[SystemID.gemulon].specialEvent == .scarabDestroyed)
    }

    @Test("RUL-027 GAL-043 GAL-045 GAL-046 GAL-048 distant placement: Palm's ineffective/sticky exclusions and overwrites")
    func distantPlacement() {
        // Scenario 1 (Invasion sticks on Daled): cluster at (0,0); Nix 283 away (< the 999 start); Daled 80 and system 60 75 from Gemulon.
        func scenario1() -> Galaxy {
            var g = GalKit.flatGalaxy()
            g.systems[SystemID.nix].x = -200
            g.systems[SystemID.nix].y = -200
            g.systems[SystemID.daled].x = 80
            g.systems[60].y = 75
            return g
        }
        var bug = scenario1()
        var rng = ScriptedRNG([1])   // Scarab: wormhole 1 (free) on the first draw
        #expect(GalaxyGenerator.placeSpecialEvents(&bug, ruleset: .palm122, rng: &rng))
        #expect(bug.systems[SystemID.nix].specialEvent == .reactorDelivered)
        let reactorAt = bug.systems.firstIndex { $0.specialEvent == .reactor }
        #expect(reactorAt == 2, "Reactor: closest ≥ 70 from Nix, lowest free index on ties (0 Acamar, 1 Scarab end-point)")
        #expect(bug.systems[SystemID.gemulon].specialEvent == .gemulonRescued)
        // GAL-045: Daled (index 17) became the best invasion candidate, so system 60 (closer) could not replace it.
        #expect(bug.systems[60].specialEvent != .gemulon)
        // GAL-046: the Experiment then overwrites Daled's AlienInvasion with ExperimentStopped → no invasion left.
        #expect(bug.systems[SystemID.daled].specialEvent == .experimentStopped)
        #expect(!bug.systems.contains { $0.specialEvent == .gemulon })
        #expect(bug.systems.filter { $0.specialEvent == .experiment }.count == 1)

        let fixed = GalKit.ruleset(.palm122) { $0.flags.galaxy.distantPlacementExclusionBug = false }
        var ok = scenario1()
        var rng2 = ScriptedRNG([1])
        _ = GalaxyGenerator.placeSpecialEvents(&ok, ruleset: fixed, rng: &rng2)
        #expect(ok.systems[60].specialEvent == .gemulon, "without the bug the closer system wins")

        // Scenario 2 (GAL-043/048): Gemulon is the only system ≥ 70 from Nix, so GetReactor lands there (the distance
        // exclusion never fires) and the invasion overwrites it; Nix keeps ReactorDelivered.
        var g2 = GalKit.flatGalaxy()
        g2.systems[SystemID.gemulon].x = 70
        var rng3 = ScriptedRNG([1])
        _ = GalaxyGenerator.placeSpecialEvents(&g2, ruleset: .palm122, rng: &rng3)
        #expect(g2.systems[SystemID.nix].specialEvent == .reactorDelivered)
        #expect(g2.systems[SystemID.gemulon].specialEvent == .gemulonRescued)
        #expect(!g2.systems.contains { $0.specialEvent == .reactor }, "reactor quest unreachable (reproduced)")
        #expect(g2.systems.filter { $0.specialEvent == .gemulon }.count == 1)
        // Windows: no exclusion and no base overwrite (its end-points are fixed events).
        var g3 = GalKit.flatGalaxy(count: 128, tech: .hiTech)
        g3.systems[90].x = 70
        let distantOnly = GalKit.ruleset(.windows201) {
            $0.flags.galaxy.eventPlacement = [.distant(base: SystemID.nix, event: .reactor, baseEvent: nil, exclusion: .none)]
        }
        var none = ScriptedRNG([])
        #expect(GalaxyGenerator.placeSpecialEvents(&g3, ruleset: distantOnly, rng: &none))
        #expect(g3.systems[90].specialEvent == .reactor && g3.systems[SystemID.nix].specialEvent == .reactorDelivered)
        #expect(g3.systems[SystemID.gemulon].specialEvent == .gemulonRescued)
    }

    @Test("RUL-028 GAL-044 artifact delivery: Windows lowest-index Hi-Tech; Palm ≤ 120 random tries, failure zeroes the artifact")
    func artifactDelivery() {
        let artifactOnly = GalKit.ruleset(.windows201) { $0.flags.galaxy.eventPlacement = [.artifactDelivery] }
        var w = GalKit.flatGalaxy(count: 128)
        w.systems[40].techLevel = .hiTech
        w.systems[90].techLevel = .hiTech
        var none = ScriptedRNG([])
        #expect(GalaxyGenerator.placeSpecialEvents(&w, ruleset: artifactOnly, rng: &none))
        #expect(w.systems[40].specialEvent == .artifactDelivery && w.systems[90].specialEvent == nil)

        let palmSteps = GalKit.ruleset(.palm122) { $0.flags.galaxy.eventPlacement = [.artifactDelivery, .randomEvents] }
        // Hi-Tech only at Gemulon and Daled (excluded) and system 0 (never drawn): 120 tries fail → no Alien Artifact.
        var p = GalKit.flatGalaxy()
        for s in [0, SystemID.gemulon, SystemID.daled] { p.systems[s].techLevel = .hiTech }
        var rng = ScriptedRNG([SystemID.gemulon - 1, SystemID.daled - 1] + Array(repeating: 0, count: 118))
        #expect(GalaxyGenerator.placeSpecialEvents(&p, ruleset: palmSteps, rng: &rng))
        #expect(!p.systems.contains { $0.specialEvent == .artifactDelivery || $0.specialEvent == .artifact })
        #expect(p.systems.filter { $0.specialEvent == .moon }.count == 4)
        // Success on a later try.
        var q = GalKit.flatGalaxy()
        q.systems[77].techLevel = .hiTech
        var rng2 = ScriptedRNG([3, 76])
        _ = GalaxyGenerator.placeSpecialEvents(&q, ruleset: palmSteps, rng: &rng2)
        #expect(q.systems[77].specialEvent == .artifactDelivery && q.systems.filter { $0.specialEvent == .artifact }.count == 1)
    }

    @Test("RUL-029 GAL-047 random events: 0…127 (Windows) vs 1…119 (Palm), table order × occurrence; never on Acamar")
    func randomEventRange() {
        // A scripted draw of 0 lands on Acamar in Windows only (Palm adds 1).
        let randomOnly = GalKit.ruleset(.windows201) {
            $0.flags.galaxy.eventPlacement = [.randomEvents]
            $0.tables.fixedSpecialEvents = []
        }
        var w = GalKit.flatGalaxy(count: 128)
        var wr = ScriptedRNG([0])
        _ = GalaxyGenerator.placeSpecialEvents(&w, ruleset: randomOnly, rng: &wr)
        #expect(w.systems[0].specialEvent == .artifact)   // first C# random event; the fixed Acamar event is absent here
        let palmRandom = GalKit.ruleset(.palm122) {
            $0.flags.galaxy.eventPlacement = [.randomEvents]
            $0.tables.fixedSpecialEvents = []
        }
        var p = GalKit.flatGalaxy()
        var pr = ScriptedRNG([0])
        _ = GalaxyGenerator.placeSpecialEvents(&p, ruleset: palmRandom, rng: &pr)
        #expect(p.systems[1].specialEvent == .moon && p.systems[0].specialEvent == nil)   // Palm order starts at MOONFORSALE
        for seed in UInt64(0)..<100 {
            for r in [Ruleset.palm122, .windows201, .modern] {
                let g = GalKit.game(r, seed: seed).galaxy
                #expect(g.systems[SystemID.acamar].specialEvent == .spaceMonsterKilled, "\(r.id) seed \(seed)")
            }
        }
    }

    @Test("GAL-041 Palm fixed events: Acamar, Baratas, Melina, Regulas, Zalkon, Japori, Utopia, Devidia, Kravat")
    func palmFixedEvents() {
        let expected: [(Int, SpecialEventType)] = [
            (SystemID.acamar, .spaceMonsterKilled), (SystemID.baratas, .dragonflyBaratas),
            (SystemID.melina, .dragonflyMelina), (SystemID.regulas, .dragonflyRegulas),
            (SystemID.zalkon, .dragonflyDestroyed), (SystemID.japori, .japoriDelivery),
            (SystemID.utopia, .moonRetirement), (SystemID.devidia, .jarekGetsOut), (SystemID.kravat, .wildGetsOut),
        ]
        #expect(Ruleset.palm122.tables.fixedSpecialEvents.map { ($0.system, $0.event) }.elementsEqual(expected) { $0 == $1 })
        var g = GalKit.flatGalaxy()
        let fixedOnly = GalKit.ruleset(.palm122) { $0.flags.galaxy.eventPlacement = [] }
        var none = ScriptedRNG([])
        _ = GalaxyGenerator.placeSpecialEvents(&g, ruleset: fixedOnly, rng: &none)
        #expect(none.calls == 0 && g.systems.compactMap(\.specialEvent).count == 9)
        for (s, e) in expected { #expect(g.systems[s].specialEvent == e) }
        for seed in UInt64(0)..<30 {
            let gg = GalKit.game(.palm122, seed: seed).galaxy
            for (s, e) in expected { #expect(gg.systems[s].specialEvent == e, "seed \(seed)") }
        }
    }

    // MARK: Shipyards and mercenaries

    @Test("GAL-050 Modern: 5 shipyards on 5 distinct Hi-Tech systems with the same 5 draws as Windows")
    func modernShipyards() {
        for seed in UInt64(0)..<200 {
            let yards = GalKit.game(.modern, seed: seed).galaxy.systems.filter { $0.shipyard != nil }
            #expect(yards.count == 5 && Set(yards.compactMap(\.shipyard)).count == 5 && yards.allSatisfy { $0.techLevel == .hiTech })
        }
        var rng = RNGState(kind: .xoshiro, seed: 3)
        let g = GalaxyGenerator.generateUniverse(ruleset: .modern, difficulty: .normal, rng: &rng)
        var a = g, b = g
        var ra = rng, rb = rng
        let collide = GalKit.ruleset(.modern) { $0.flags.distinctShipyards = false }
        _ = GalaxyGenerator.placeShipyards(&a, ruleset: .modern, rng: &ra)
        _ = GalaxyGenerator.placeShipyards(&b, ruleset: collide, rng: &rb)
        #expect(ra == rb, "same number of draws")
    }

    @Test("GAL-051 Palm places no shipyards and makes no shipyard draws")
    func palmNoShipyardDraws() {
        var rng = RNGState(kind: .palmLCG, seed: 3)
        var g = GalaxyGenerator.generateUniverse(ruleset: .palm122, difficulty: .normal, rng: &rng)
        for i in g.systems.indices { g.systems[i].techLevel = .hiTech }
        let before = rng
        #expect(GalaxyGenerator.placeShipyards(&g, ruleset: .palm122, rng: &rng))
        #expect(rng == before && g.systems.allSatisfy { $0.shipyard == nil })
    }

    @Test("GAL-055 GAL-056 Palm mercenaries: slots 1…31 draw r(120) then four skills; redo on a used system or Kravat")
    func palmMercenaryDraws() {
        let galaxy = GalKit.flatGalaxy()
        // Slot 1 draws Kravat (redo) then 3; slot 2 draws 3 (redo) then 4.
        var script = [SystemID.kravat, 3, 0, 0, 0, 0, 0, 0, 0, 0, 3, 4, 4, 5, 4, 5, 4, 5, 4, 5]
        for k in 3...31 { script += [k + 2, 1, 1, 1, 1, 1, 1, 1, 1] }
        var rng = ScriptedRNG(script)
        let crew = GalaxyGenerator.generateCrew(galaxy: galaxy, ruleset: .palm122, difficulty: .normal, rng: &rng)
        #expect(rng.script.isEmpty, "exactly the scripted draws were consumed")
        #expect(crew[1].systemID == 3 && crew[1].skills == [1, 1, 1, 1])
        #expect(crew[2].systemID == 4 && crew[2].skills == [10, 10, 10, 10])
        #expect(crew[29].systemID == 31 && crew[3].skills == [3, 3, 3, 3])
        #expect(crew[CrewID.zeethibal].systemID == nil && crew[CrewID.opponent].systemID == nil)
        // The hire lookup never offers the scratch slot.
        var e = makeEngine(.palm122)
        e.state.mercenaries[CrewID.opponent].systemID = nil
        for s in e.state.galaxy.systems.indices {
            e.state.commander.currentSystem = s
            #expect(!e.state.mercenariesForHire.contains(CrewID.opponent) && !e.state.mercenariesForHire.contains(CrewID.zeethibal))
        }
    }

    // MARK: Start system

    @Test("RUL-030 GAL-058 start: Windows unbounded with TL 1…6; Palm 200 tries, TL 1…5 on tries 0…99, last draw fallback")
    func startSystemSearch() {
        // Systems 0…2 cluster with system 10; system 10 is post-industrial (TL 6).
        var g = GalKit.flatGalaxy()
        g.systems[10].techLevel = .postIndustrial
        for s in g.systems.indices where s != 10 && s > 3 { g.systems[s].x = 500 + 20 * s }
        // Windows: TL 6 accepted on the first try.
        var w = ScriptedRNG([10])
        #expect(GalaxyGenerator.startSystem(galaxy: g, ruleset: .windows201, reach: 14, rng: &w) == 10)
        // Palm: rejected while i < 100, accepted on try 100.
        var p = ScriptedRNG(Array(repeating: 10, count: 101))
        #expect(GalaxyGenerator.startSystem(galaxy: g, ruleset: .palm122, reach: 14, rng: &p) == 10 && p.calls == 101)
        // Palm: every try fails (system 50 is isolated) → after 200 draws the last one is used unchecked.
        var all = ScriptedRNG(Array(repeating: 1, count: 199) + [50])
        g.systems[1].specialEvent = .skill
        #expect(GalaxyGenerator.startSystem(galaxy: g, ruleset: .palm122, reach: 14, rng: &all) == 50 && all.calls == 200)
        // An event always disqualifies.
        var ev = ScriptedRNG([1, 10])
        #expect(GalaxyGenerator.startSystem(galaxy: g, ruleset: .windows201, reach: 14, rng: &ev) == 10)
    }

    @Test("RUL-031 start reach: three systems with floor(d) ≤ 14 (Modern/Windows) vs d² ≤ 196 (Palm)")
    func startReach() {
        var g = GalKit.flatGalaxy()
        for s in g.systems.indices { g.systems[s].x = 1000 + 30 * s }
        g.systems[10].x = 0
        for (k, s) in [11, 12, 13].enumerated() {
            g.systems[s].x = 14
            g.systems[s].y = k == 0 ? 1 : -1   // d² = 197: floor(√197) = 14 but 197 > 196
        }
        var w = ScriptedRNG([10])
        #expect(GalaxyGenerator.startSystem(galaxy: g, ruleset: .windows201, reach: 14, rng: &w) == 10)
        var p = ScriptedRNG([10] + Array(repeating: 11, count: 199))
        #expect(GalaxyGenerator.startSystem(galaxy: g, ruleset: .palm122, reach: 14, rng: &p) == 11 && p.calls == 200)
        for seed in UInt64(0)..<100 {
            let game = GalKit.game(.palm122, seed: seed)
            let start = game.galaxy.systems[game.commander.currentSystem]
            let close = game.galaxy.systems.filter { $0.id != start.id && GalaxyGenerator.sqrDistance($0, start) <= 196 }
            #expect(close.count >= 3, "seed \(seed)")
        }
    }

    @Test("GAL-061 Palm Lottery only on a start system without an event; Windows overwrites")
    func lottery() {
        var g = GalKit.flatGalaxy()
        g.systems[5].specialEvent = .skill
        var w = g
        GalaxyGenerator.placeLottery(&g, start: 5, difficulty: .beginner, ruleset: .palm122)
        #expect(g.systems[5].specialEvent == .skill)
        GalaxyGenerator.placeLottery(&g, start: 6, difficulty: .easy, ruleset: .palm122)
        #expect(g.systems[6].specialEvent == .lottery)
        GalaxyGenerator.placeLottery(&g, start: 7, difficulty: .normal, ruleset: .palm122)
        #expect(g.systems[7].specialEvent == nil)
        GalaxyGenerator.placeLottery(&w, start: 5, difficulty: .beginner, ruleset: .windows201)
        #expect(w.systems[5].specialEvent == .lottery)
        let beginner = GalKit.game(.palm122, seed: 8, difficulty: .beginner)
        #expect(beginner.galaxy.systems[beginner.commander.currentSystem].specialEvent == .lottery)
    }

    @Test("GAL-065 Palm marks the start system and every arrival visited")
    func palmVisited() throws {
        var e = makeEngine(.palm122, seed: 21)
        #expect(e.state.currentSystem.visited)
        #expect(e.state.galaxy.systems.filter(\.visited).count == 1)
        let here = e.state.commander.currentSystem
        let target = try #require(e.state.galaxy.systems.indices.first {
            $0 != here && GalaxyGenerator.distance(e.state.galaxy.systems[$0], e.state.currentSystem,
                                                   rule: e.ruleset.flags.distance) <= e.state.commander.ship.fuel
        })
        #expect(!e.state.galaxy.systems[target].visited)
        _ = try #require(QSTKit.arrive(&e, at: target))
        #expect(e.state.commander.currentSystem == target && e.state.galaxy.systems[target].visited)
    }

    // MARK: Invariants

    @Test("GAL-071 Palm galaxies satisfy the Palm invariants over 1000 seeds")
    func palmInvariants() {
        let palm = Ruleset.palm122
        var fallbacks = 0
        for seed in UInt64(0)..<1000 {
            let game = GalKit.game(palm, seed: seed)
            let g = game.galaxy, s = g.systems
            let tag = "seed \(seed)"
            #expect(s.allSatisfy { (1...148).contains($0.x) && (1...108).contains($0.y) }, "\(tag) bounds")
            var minSq = Int.max
            for i in s.indices { for j in (i + 1)..<s.count { minSq = min(minSq, GalaxyGenerator.sqrDistance(s[i], s[j])) } }
            #expect(minSq >= 50, "\(tag) spacing")
            #expect(s.allSatisfy { palm.tables.politics($0.politics).minTech <= $0.techLevel
                && $0.techLevel <= palm.tables.politics($0.politics).maxTech }, "\(tag) gov/TL")
            // Reachability through hops of d² < 169 plus wormholes.
            var seen = Set([0]), stack = [0]
            while let i = stack.popLast() {
                var next = s.indices.filter { !seen.contains($0) && GalaxyGenerator.sqrDistance(s[i], s[$0]) < 169 }
                if let w = g.wormholeDestination(from: i) { next.append(w) }
                if let k = g.wormholes.firstIndex(of: i) { next.append(g.wormholes[(k + 5) % 6]) }
                for j in next where seen.insert(j).inserted { stack.append(j) }
            }
            #expect(seen.count == 120, "\(tag) reachability")
            let events = s.compactMap(\.specialEvent)
            let hasDelivery = events.contains(.artifactDelivery)
            for spec in palm.tables.specialEvents where spec.occurrence > 0 {
                let n = events.filter { $0 == spec.type }.count
                switch spec.type {
                case .scarab: #expect(n <= 1, "\(tag) scarab")
                case .artifact: #expect(n == (hasDelivery ? 1 : 0), "\(tag) artifact")
                default: #expect(n == spec.occurrence, "\(tag) \(spec.type)")
                }
            }
            for (base, e) in [(SystemID.nix, SpecialEventType.reactor), (SystemID.gemulon, .gemulon), (SystemID.daled, .experiment)] {
                for i in s.indices where s[i].specialEvent == e {
                    #expect(GalaxyGenerator.distance(s[base], s[i], rule: .rounded) >= 70, "\(tag) \(e)")
                }
            }
            let mercs = game.mercenaries.filter { $0.systemID != nil }
            #expect(Set(mercs.compactMap(\.systemID)).count == mercs.count && !mercs.contains { $0.systemID == SystemID.kravat })
            let start = s[game.commander.currentSystem]
            #expect(start.specialEvent == nil, "\(tag) start has no event before the Lottery")
            let close = s.filter { $0.id != start.id && GalaxyGenerator.sqrDistance($0, start) <= 196 }.count
            if close < 3 { fallbacks += 1 }
        }
        #expect(fallbacks == 0, "seeds that needed the relaxed or unchecked start fallback: \(fallbacks)")
    }
}
