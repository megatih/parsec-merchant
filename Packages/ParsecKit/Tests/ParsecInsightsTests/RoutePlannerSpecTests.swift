// SPDX-License-Identifier: GPL-2.0-or-later
// MAP-054…061, MAP-094 (docs/specs/MAP.md §12, §17): the ParsecInsights route planner.
import Testing
import ParsecEngine
@testable import ParsecInsights

/// Deterministic test values (SplitMix64).
private struct SplitMix {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func int(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.upperBound - range.lowerBound + 1))
    }
}

private func fresh(_ r: RulesetID, seed: UInt64) -> GameState {
    GameEngine(config: NewGameConfig(commanderName: "Route", ruleset: r, seed: seed)).state
}

/// A hand-built snapshot (fuel cost 1, no daily costs unless given).
private func snapshot(_ points: [(Int, Int)], wormholes: [Int] = [], capacity: Int, fuel: Int? = nil,
                      tax: Int = 25, perWarp: Int = 0, rule: DistanceRule = .floor) -> RouteSnapshot {
    RouteSnapshot(points: points.map { RoutePoint(x: $0.0, y: $0.1) }, wormholes: wormholes, distanceRule: rule,
                  fuelCapacity: capacity, currentFuel: fuel ?? capacity, fuelCostPerParsec: 1, wormholeTax: tax,
                  perWarpCosts: perWarp)
}

/// A reference edge definition straight from MAP-055 (independent of the planner's code).
private struct RefEdge: Equatable {
    var via: Bool
    var distance: Int
    var parsecs: Int
    var credits: Int
    var risk = 0
}

private func refEdge(_ s: RouteSnapshot, _ a: Int, _ b: Int) -> RefEdge? {
    guard a != b else { return nil }
    let d = GalaxyGenerator.distance(s.points[a].x, s.points[a].y, s.points[b].x, s.points[b].y, rule: s.distanceRule)
    if let k = s.wormholes.firstIndex(of: a), s.wormholes[(k + 1) % s.wormholes.count] == b {
        return RefEdge(via: true, distance: d, parsecs: 0, credits: s.wormholeTax + s.perWarpCosts, risk: s.risk(b))
    }
    guard d <= s.fuelCapacity else { return nil }
    return RefEdge(via: false, distance: d, parsecs: d, credits: d * s.fuelCostPerParsec + s.perWarpCosts, risk: s.risk(b))
}

private func key(_ e: RefEdge, _ o: RouteObjective) -> [Int] {
    switch o {
    case .fewestJumps: [1, e.parsecs, e.credits]
    case .cheapest: [e.credits, 1, e.parsecs]
    case .lowestRisk: [e.risk, 1, e.credits]
    }
}

private func add(_ a: [Int], _ b: [Int]) -> [Int] { zip(a, b).map { $0 + $1 } }

/// Bellman-Ford over the reference edges: the optimal lexicographic key to every node.
private func referenceKeys(_ s: RouteSnapshot, from: Int, _ o: RouteObjective) -> [[Int]?] {
    let n = s.points.count
    var edges: [(Int, Int, [Int])] = []
    for a in 0..<n {
        for b in 0..<n {
            if let e = refEdge(s, a, b) { edges.append((a, b, key(e, o))) }
        }
    }
    var best = [[Int]?](repeating: nil, count: n)
    best[from] = [0, 0, 0]
    var changed = true
    while changed {
        changed = false
        for (a, b, k) in edges {
            guard let ka = best[a] else { continue }
            let c = add(ka, k)
            if best[b].map({ c.lexicographicallyPrecedes($0) }) ?? true {
                best[b] = c
                changed = true
            }
        }
    }
    return best
}

/// Brute-force BFS over the reference edges.
private func referenceJumps(_ s: RouteSnapshot, from: Int) -> [Int?] {
    var out = [Int?](repeating: nil, count: s.points.count)
    out[from] = 0
    var frontier = [from]
    var depth = 0
    while !frontier.isEmpty {
        depth += 1
        var next: [Int] = []
        for a in frontier {
            for b in s.points.indices where out[b] == nil && refEdge(s, a, b) != nil {
                out[b] = depth
                next.append(b)
            }
        }
        frontier = next
    }
    return out
}

private func routeKey(_ r: Route, _ s: RouteSnapshot) -> [Int] {
    r.hops.reduce([0, 0, 0]) { acc, h in
        add(acc, key(refEdge(s, h.from, h.to) ?? RefEdge(via: false, distance: 0, parsecs: 0, credits: 0), r.objective))
    }
}

/// Checks every structural invariant of MAP-055, MAP-056 and MAP-059.
private func checkValid(_ r: Route, _ s: RouteSnapshot, from: Int, to: Int, _ context: String) {
    #expect(r.from == from && r.to == to, "\(context)")
    #expect(r.hops.first?.from == from && r.hops.last?.to == to, "\(context)")
    #expect(r.totalJumps == r.hops.count, "\(context)")
    var fuel = min(s.currentFuel, s.fuelCapacity)
    var parsecs = 0
    var credits = 0
    var refuel = 0
    for (i, h) in r.hops.enumerated() {
        if i > 0 { #expect(h.from == r.hops[i - 1].to, "\(context) contiguous") }
        guard let e = refEdge(s, h.from, h.to) else {
            Issue.record("\(context) hop \(h.from)→\(h.to) is not an edge")
            continue
        }
        #expect(e.via == h.viaWormhole && e.distance == h.distance && e.credits == h.cost, "\(context)")
        #expect(h.fuelBefore == fuel, "\(context)")
        let need = h.viaWormhole ? 0 : h.distance
        #expect(h.refuelUnits == max(0, need - fuel), "\(context)")
        #expect(h.refuelCost == h.refuelUnits * s.fuelCostPerParsec, "\(context)")
        #expect(h.fuelUsed == need)
        fuel += h.refuelUnits
        #expect(fuel <= s.fuelCapacity, "\(context) tank overflow")
        fuel -= need
        #expect(fuel >= 0, "\(context) negative fuel")
        parsecs += e.parsecs
        credits += h.cost
        refuel += h.refuelUnits
    }
    #expect(r.totalParsecs == parsecs && r.estimatedCredits == credits && r.totalRefuelUnits == refuel, "\(context)")
    #expect(r.stops == [from] + r.hops.map(\.to))
}

@Suite("Route planner (MAP-054…061, MAP-094)")
struct RoutePlannerSpecTests {
    // MARK: MAP-054 / MAP-094 snapshot

    @Test("MAP-054 RouteSnapshot(state) copies coordinates, ring, rule, fuel, fuel cost, tax and per-warp costs")
    func snapshotFields() {
        for r in RulesetID.allCases {
            var s = fresh(r, seed: 9)
            s.commander.debt = 2_000
            let snap = RouteSnapshot(s)
            #expect(snap.points == s.galaxy.systems.map { RoutePoint(x: $0.x, y: $0.y) })
            #expect(snap.wormholes == s.galaxy.wormholes)
            #expect(snap.distanceRule == s.ruleset.flags.distance)
            #expect(snap.fuelCapacity == s.fuelCapacity)
            #expect(snap.currentFuel == s.commander.ship.fuel)
            #expect(snap.fuelCostPerParsec == s.fuelCostPerParsec)
            #expect(snap.wormholeTax == s.wormholeTaxPerJump)
            let d = s.dailyCosts(to: s.warpSystem)
            #expect(d.interest > 0)
            #expect(snap.perWarpCosts == d.mercenaries + d.insurance + d.interest)
            #expect(snap.distance(0, 1) == GalaxyGenerator.distance(s.galaxy.systems[0], s.galaxy.systems[1],
                                                                     rule: s.ruleset.flags.distance))
        }
    }

    @Test("MAP-094 two states differing only in hidden fields give equal snapshots")
    func snapshotFairness() {
        for r in RulesetID.allCases {
            let a = fresh(r, seed: 11)
            var b = a
            for i in b.galaxy.systems.indices where i != b.commander.currentSystem {
                b.galaxy.systems[i].specialResource = .lifeless
                b.galaxy.systems[i].specialEvent = .moon
                b.galaxy.systems[i].tradeItems = b.galaxy.systems[i].tradeItems.map { $0 + 17 }
                b.galaxy.systems[i].countDown += 3
                b.galaxy.systems[i].visited = false
            }
            b.warpSystem = (a.warpSystem + 1) % a.galaxy.systems.count
            #expect(RouteSnapshot(a) == RouteSnapshot(b), "\(r)")
        }
    }

    // MARK: MAP-055 graph

    @Test("MAP-055 a wormhole edge replaces the normal edge to the same system and is one-way")
    func wormholeReplacesNormal() {
        // 0 → 1 is a wormhole and also within range; 1 → 0 is a normal edge (the ring is 0 → 1 → 2 → 0).
        let s = snapshot([(0, 0), (5, 0), (40, 0)], wormholes: [0, 1, 2], capacity: 10, tax: 50, perWarp: 3)
        let e01 = RoutePlanner.edges(from: 0, in: s).first { $0.to == 1 }
        #expect(e01 == RouteEdge(to: 1, viaWormhole: true, distance: 5, parsecs: 0, credits: 53))
        let e10 = RoutePlanner.edges(from: 1, in: s).first { $0.to == 0 }
        #expect(e10 == RouteEdge(to: 0, viaWormhole: false, distance: 5, parsecs: 5, credits: 8))
        #expect(RoutePlanner.edges(from: 1, in: s).map(\.to) == [0, 2])
        #expect(RoutePlanner.edges(from: 2, in: s).map(\.to) == [0])
        let route = RoutePlanner.plan(from: 0, to: 1, in: s, objective: .cheapest)
        #expect(route?.hops.map(\.viaWormhole) == [true], "the engine always counts that warp as via the wormhole")
        #expect(route?.totalParsecs == 0)
    }

    @Test("MAP-055 jumpCounts is a BFS over the edges: 0 at from, nil when unreachable")
    func jumpCountsBasics() {
        let s = snapshot([(0, 0), (10, 0), (20, 0), (100, 100)], capacity: 10)
        #expect(RoutePlanner.jumpCounts(from: 0, in: s) == [0, 1, 2, nil])
        #expect(RoutePlanner.jumpCounts(from: 3, in: s) == [nil, nil, nil, 0])
        #expect(RoutePlanner.jumpCounts(from: 9, in: s) == [nil, nil, nil, nil])
        #expect(RoutePlanner.plan(from: 0, to: 3, in: s) == nil)
    }

    @Test("MAP-055 MAP-060 jumpCounts equals a brute-force BFS for many seeds and every ruleset")
    func jumpCountsMatchReference() {
        for r in RulesetID.allCases {
            for seed in UInt64(1)...40 {
                let snap = RouteSnapshot(fresh(r, seed: seed))
                let from = Int(seed) % snap.points.count
                #expect(RoutePlanner.jumpCounts(from: from, in: snap) == referenceJumps(snap, from: from), "\(r) \(seed)")
            }
        }
    }

    // MARK: MAP-056 refuel

    @Test("MAP-056 the first hop buys the shortfall and the second, a wormhole, uses no fuel")
    func refuelFixture() {
        // 0 —(9 pc)→ 1 —wormhole→ 2 (60 pc away); fuel 4 of 10, fuel cost 3, tax 75, per-warp 10.
        let s = RouteSnapshot(points: [RoutePoint(x: 0, y: 0), RoutePoint(x: 9, y: 0), RoutePoint(x: 69, y: 0)],
                              wormholes: [1, 2], distanceRule: .floor, fuelCapacity: 10, currentFuel: 4,
                              fuelCostPerParsec: 3, wormholeTax: 75, perWarpCosts: 10)
        let route = RoutePlanner.plan(from: 0, to: 2, in: s)
        let expected = Route(from: 0, to: 2, objective: .fewestJumps, hops: [
            RouteHop(from: 0, to: 1, viaWormhole: false, distance: 9, fuelBefore: 4, refuelUnits: 5, refuelCost: 15,
                     cost: 9 * 3 + 10),
            RouteHop(from: 1, to: 2, viaWormhole: true, distance: 60, fuelBefore: 0, refuelUnits: 0, refuelCost: 0,
                     cost: 75 + 10),
        ], totalJumps: 2, totalParsecs: 9, estimatedCredits: 37 + 85, totalRefuelUnits: 5)
        #expect(route == expected)
        if let route { checkValid(route, s, from: 0, to: 2, "fixture") }
    }

    @Test("MAP-056 each normal hop is limited by the full tank, not by the current fuel")
    func fullTankCapacity() {
        let s = snapshot([(0, 0), (8, 0), (16, 0)], capacity: 8, fuel: 0)
        let route = RoutePlanner.plan(from: 0, to: 2, in: s)
        #expect(route?.hops.map(\.refuelUnits) == [8, 8])
        #expect(route?.totalRefuelUnits == 16)
        // A hop longer than the tank never appears.
        #expect(RoutePlanner.plan(from: 0, to: 2, in: snapshot([(0, 0), (9, 0), (18, 0)], capacity: 8)) == nil)
    }

    // MARK: MAP-057 objectives

    @Test("MAP-057 fewestJumps takes an expensive wormhole, cheapest takes two cheap hops")
    func objectivesDiffer() {
        let s = snapshot([(0, 0), (10, 0), (20, 0)], wormholes: [0, 2], capacity: 10, tax: 100)
        let fewest = RoutePlanner.plan(from: 0, to: 2, in: s, objective: .fewestJumps)
        let cheapest = RoutePlanner.plan(from: 0, to: 2, in: s, objective: .cheapest)
        #expect(fewest?.stops == [0, 2] && fewest?.estimatedCredits == 100 && fewest?.objective == .fewestJumps)
        #expect(cheapest?.stops == [0, 1, 2] && cheapest?.estimatedCredits == 20 && cheapest?.objective == .cheapest)
    }

    @Test("MAP-057 fewestJumps breaks equal jumps by parsecs, then credits")
    func fewestJumpsSecondaryKeys() {
        // Two 2-jump routes 0→1→3 (13 + 9 pc) and 0→2→3 (10 + 10 pc): the shorter wins although 1 has the lower index.
        let s = snapshot([(0, 0), (12, 5), (10, -1), (20, 0)], capacity: 13)
        let route = RoutePlanner.plan(from: 0, to: 3, in: s)
        #expect(route?.stops == [0, 2, 3])
    }

    // MARK: MAP-058 determinism

    @Test("MAP-058 equal routes resolve to the lower-index predecessor, on every run")
    func tieBreaking() {
        // Symmetric diamond: 0 → {1, 2} → 3 with equal distances; 0 → 3 is out of range.
        let a = snapshot([(0, 0), (5, 5), (5, -5), (10, 0)], capacity: 8)
        let b = snapshot([(0, 0), (5, -5), (5, 5), (10, 0)], capacity: 8)
        for _ in 0..<50 {
            for s in [a, b] {
                for objective in RouteObjective.allCases {
                    #expect(RoutePlanner.plan(from: 0, to: 3, in: s, objective: objective)?.stops == [0, 1, 3])
                    #expect(RoutePlanner.plan(from: 3, to: 0, in: s, objective: objective)?.stops == [3, 1, 0])
                }
            }
        }
    }

    // MARK: MAP-059 nil cases

    @Test("MAP-059 plan is nil for from == to, out-of-range indices and unreachable targets")
    func nilCases() {
        let s = snapshot([(0, 0), (5, 0), (90, 90)], capacity: 10)
        #expect(RoutePlanner.plan(from: 1, to: 1, in: s) == nil)
        #expect(RoutePlanner.plan(from: -1, to: 1, in: s) == nil)
        #expect(RoutePlanner.plan(from: 0, to: 3, in: s) == nil)
        #expect(RoutePlanner.plan(from: 0, to: 2, in: s) == nil)
        #expect(RoutePlanner.plan(from: 0, to: 2, in: s, objective: .cheapest) == nil)
        #expect(RoutePlanner.plan(from: 0, to: 1, in: s) != nil)
    }

    // MARK: MAP-060 properties

    @Test("MAP-060 routes are valid and optimal for 200 seeds per ruleset and random pairs", arguments: RulesetID.allCases)
    func properties(_ r: RulesetID) {
        var rng = SplitMix(state: 2_026 &+ UInt64(RulesetID.allCases.firstIndex(of: r) ?? 0))
        do {
            for seed in UInt64(1)...200 {
                var state = fresh(r, seed: seed)
                state.commander.ship.fuel = rng.int(0...state.fuelCapacity)
                if seed % 3 == 0 { state.commander.debt = rng.int(1...20_000) }
                let snap = RouteSnapshot(state)
                let n = snap.points.count
                let from = rng.int(0...(n - 1))
                let jumps = RoutePlanner.jumpCounts(from: from, in: snap)
                // Reference optimum keys for both objectives, checked on a few random targets.
                let checkOptimum = seed % 8 == 0
                let refFewest = checkOptimum ? referenceKeys(snap, from: from, .fewestJumps) : []
                let refCheapest = checkOptimum ? referenceKeys(snap, from: from, .cheapest) : []
                for _ in 0..<4 {
                    let to = rng.int(0...(n - 1))
                    let context = "\(r) seed \(seed) \(from)→\(to)"
                    let fewest = RoutePlanner.plan(from: from, to: to, in: snap, objective: .fewestJumps)
                    let cheapest = RoutePlanner.plan(from: from, to: to, in: snap, objective: .cheapest)
                    guard to != from, let reach = jumps[to] else {
                        #expect(fewest == nil && cheapest == nil, "\(context)")
                        continue
                    }
                    guard let fewest, let cheapest else {
                        Issue.record("\(context) reachable in \(reach) but no route")
                        continue
                    }
                    checkValid(fewest, snap, from: from, to: to, context)
                    checkValid(cheapest, snap, from: from, to: to, context)
                    #expect(fewest.totalJumps == reach, "\(context)")
                    #expect(cheapest.totalJumps >= reach, "\(context)")
                    #expect(cheapest.estimatedCredits <= fewest.estimatedCredits, "\(context)")
                    if checkOptimum {
                        #expect(routeKey(fewest, snap) == refFewest[to], "\(context)")
                        #expect(routeKey(cheapest, snap) == refCheapest[to], "\(context)")
                    }
                    // Determinism: the same snapshot always gives the same route.
                    #expect(RoutePlanner.plan(from: from, to: to, in: snap, objective: .cheapest) == cheapest)
                }
            }
        }
    }

    @Test("MAP-060 optimality against exhaustive path enumeration on small random graphs")
    func bruteForceSmall() {
        var rng = SplitMix(state: 77)
        for trial in 0..<300 {
            let n = rng.int(3...7)
            let points = (0..<n).map { _ in (rng.int(0...30), rng.int(0...30)) }
            let ring = Array((0..<n).filter { _ in rng.int(0...3) == 0 }.prefix(4))
            let s = RouteSnapshot(points: points.map { RoutePoint(x: $0.0, y: $0.1) }, wormholes: ring.count >= 2 ? ring : [],
                                  distanceRule: trial.isMultiple(of: 2) ? .floor : .rounded, fuelCapacity: rng.int(5...15),
                                  currentFuel: rng.int(0...5), fuelCostPerParsec: rng.int(0...4),
                                  wormholeTax: rng.int(0...120), perWarpCosts: rng.int(0...20))
            for objective in RouteObjective.allCases {
                for to in 1..<n {
                    // Every simple path from 0 to `to`.
                    var bestKey: [Int]?
                    func dfs(_ node: Int, _ visited: Set<Int>, _ acc: [Int]) {
                        if node == to {
                            if bestKey.map({ acc.lexicographicallyPrecedes($0) }) ?? true { bestKey = acc }
                            return
                        }
                        for b in 0..<n where !visited.contains(b) {
                            if let e = refEdge(s, node, b) { dfs(b, visited.union([b]), add(acc, key(e, objective))) }
                        }
                    }
                    dfs(0, [0], [0, 0, 0])
                    let route = RoutePlanner.plan(from: 0, to: to, in: s, objective: objective)
                    #expect((route == nil) == (bestKey == nil), "trial \(trial) \(objective) to \(to)")
                    if let route {
                        checkValid(route, s, from: 0, to: to, "trial \(trial)")
                        #expect(routeKey(route, s) == bestKey, "trial \(trial) \(objective) to \(to)")
                    }
                }
            }
        }
    }

    // MARK: MAP-061 agreement with the engine

    @Test("MAP-061 a one-hop plan to an in-range destination agrees with warpTargetPreview")
    func agreesWithPreview() {
        for r in RulesetID.allCases {
            for seed in UInt64(1)...10 {
                var state = fresh(r, seed: seed)
                state.commander.ship.fuel = state.fuelCapacity
                state.commander.debt = Int(seed) * 1_000
                // Stand on a wormhole system so the wormhole destination is among the destinations.
                if seed.isMultiple(of: 2), let w = state.galaxy.wormholes.first { state.commander.currentSystem = w }
                let snap = RouteSnapshot(state)
                let cur = state.commander.currentSystem
                #expect(!state.destinations.isEmpty)
                for to in state.destinations {
                    let preview = state.warpTargetPreview(to)
                    guard let route = RoutePlanner.plan(from: cur, to: to, in: snap), route.hops.count == 1 else {
                        Issue.record("\(r) \(seed) \(to): expected one hop")
                        continue
                    }
                    let hop = route.hops[0]
                    #expect(hop.viaWormhole == preview.viaWormhole, "\(r) \(seed) \(to)")
                    #expect(hop.cost - hop.refuelCost == preview.costs.total + hop.fuelUsed * snap.fuelCostPerParsec,
                            "\(r) \(seed) \(to)")
                    #expect(hop.refuelUnits == 0)
                    #expect(state.commander.ship.fuel - hop.fuelUsed == preview.fuelAfter)
                }
            }
        }
    }

    // MARK: MAP-092 performance

    @Test("MAP-092 plan and jumpCounts stay well inside budget (Release budgets: pmsim bench --check)")
    func boundedWork() {
        let clock = ContinuousClock()
        var plans: [Duration] = []
        var counts: [Duration] = []
        var rng = SplitMix(state: 92)
        for r in RulesetID.allCases {
            let snap = RouteSnapshot(fresh(r, seed: 92))
            for i in 0..<100 {
                let from = rng.int(0...(snap.points.count - 1))
                let to = rng.int(0...(snap.points.count - 1))
                var start = clock.now
                _ = RoutePlanner.plan(from: from, to: to, in: snap, objective: i.isMultiple(of: 2) ? .fewestJumps : .cheapest)
                plans.append(clock.now - start)
                start = clock.now
                _ = RoutePlanner.jumpCounts(from: from, in: snap)
                counts.append(clock.now - start)
            }
        }
        // Debug builds are far slower than Release; this only catches an accidental complexity blow-up.
        #expect(plans.sorted()[plans.count / 2] < .milliseconds(20))
        #expect(counts.sorted()[counts.count / 2] < .milliseconds(10))
    }
}
