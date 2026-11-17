// SPDX-License-Identifier: GPL-2.0-or-later
// Route planner (docs/specs/MAP.md §12, MAP-054…061, MAP-094): Dijkstra and breadth-first search over in-range hops
// plus wormholes, on a fair Sendable snapshot of the game state. Pure, deterministic, no RNG.
import ParsecEngine

/// A system's galaxy coordinates.
public struct RoutePoint: Sendable, Equatable, Hashable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

/// MAP-054 / MAP-094: everything the planner reads, and nothing else (no prices, no hidden fields).
public struct RouteSnapshot: Sendable, Equatable {
    /// System coordinates, indexed by system.
    public var points: [RoutePoint]
    /// The wormhole ring (`wormholes[k] → wormholes[(k + 1) % count]`).
    public var wormholes: [Int]
    public var distanceRule: DistanceRule
    /// The per-hop fuel limit (MAP-056): a full tank.
    public var fuelCapacity: Int
    public var currentFuel: Int
    public var fuelCostPerParsec: Int
    /// The tax for one wormhole jump (MAP-093 `wormholeTaxPerJump`).
    public var wormholeTax: Int
    /// Mercenaries + insurance + interest of `dailyCosts`, taken at their current values.
    public var perWarpCosts: Int
    /// INT-026 / MAP-069: the risk weight of arriving at each system, from public data only (government pirate
    /// activity, plus police activity when the commander is a criminal). Empty or short arrays count 0.
    public var hopRisk: [Int]

    public init(points: [RoutePoint], wormholes: [Int], distanceRule: DistanceRule, fuelCapacity: Int, currentFuel: Int,
                fuelCostPerParsec: Int, wormholeTax: Int, perWarpCosts: Int, hopRisk: [Int] = []) {
        self.hopRisk = hopRisk
        self.points = points
        self.wormholes = wormholes
        self.distanceRule = distanceRule
        self.fuelCapacity = fuelCapacity
        self.currentFuel = currentFuel
        self.fuelCostPerParsec = fuelCostPerParsec
        self.wormholeTax = wormholeTax
        self.perWarpCosts = perWarpCosts
    }

    /// MAP-094: reads only coordinates, the wormhole ring, the distance rule, fuel, fuel cost, wormhole tax, the
    /// per-warp daily costs and (INT-026) each system's government activity levels and the police record score.
    public init(_ state: GameState) {
        let daily = state.dailyCosts(to: state.commander.currentSystem)
        self.init(points: state.galaxy.systems.map { RoutePoint(x: $0.x, y: $0.y) },
                  wormholes: state.galaxy.wormholes,
                  distanceRule: state.ruleset.flags.distance,
                  fuelCapacity: state.fuelCapacity,
                  currentFuel: state.commander.ship.fuel,
                  fuelCostPerParsec: state.fuelCostPerParsec,
                  wormholeTax: state.wormholeTaxPerJump,
                  perWarpCosts: daily.mercenaries + daily.insurance + daily.interest,
                  hopRisk: Self.hopRisk(state))
    }

    /// INT-026: pirate activity of the system's government, plus its police activity when the police record score is
    /// below −5 (the engine's criminal threshold); `.na` counts 0.
    public static func hopRisk(_ state: GameState) -> [Int] {
        let tables = state.ruleset.tables
        let criminal = state.commander.policeRecordScore < -5
        return state.galaxy.systems.map { system in
            let pol = tables.politics(system.politics)
            return activityWeight(pol.activityPirates) + (criminal ? activityWeight(pol.activityPolice) : 0)
        }
    }

    /// INT-025 / INT-026: an activity level as a number (`.na`, "never", counts 0).
    public static func activityWeight(_ a: Activity) -> Int { a == .na ? 0 : a.rawValue }

    /// The risk weight of arriving at `system`.
    public func risk(_ system: Int) -> Int { hopRisk.indices.contains(system) ? hopRisk[system] : 0 }

    /// The destination of the wormhole at each system, if any.
    var wormholeDestinations: [Int?] {
        var out = [Int?](repeating: nil, count: points.count)
        for (k, w) in wormholes.enumerated() where points.indices.contains(w) {
            out[w] = wormholes[(k + 1) % wormholes.count]
        }
        return out
    }

    /// The distance between two systems under the snapshot's rule.
    public func distance(_ a: Int, _ b: Int) -> Int {
        GalaxyGenerator.distance(points[a].x, points[a].y, points[b].x, points[b].y, rule: distanceRule)
    }

    func squaredDistance(_ a: Int, _ b: Int) -> Int {
        let dx = points[a].x - points[b].x
        let dy = points[a].y - points[b].y
        return dx * dx + dy * dy
    }
}

/// MAP-054 / MAP-057 / MAP-069: what a route minimises.
public enum RouteObjective: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    /// Lexicographic (jumps, parsecs, credits).
    case fewestJumps
    /// Lexicographic (credits, jumps, parsecs).
    case cheapest
    /// INT-027: lexicographic (risk, jumps, credits), risk from `RouteSnapshot.hopRisk`.
    case lowestRisk
}

/// MAP-059: one warp of a planned route.
public struct RouteHop: Sendable, Equatable {
    public var from: Int
    public var to: Int
    public var viaWormhole: Bool
    /// Parsecs between the systems (the wormhole hop still reports it; it uses no fuel and adds 0 route parsecs).
    public var distance: Int
    /// Fuel aboard on arrival at `from`, before refuelling (MAP-056).
    public var fuelBefore: Int
    /// Fuel bought at `from` before the hop: exactly the shortfall.
    public var refuelUnits: Int
    public var refuelCost: Int
    /// The edge cost of MAP-055: `distance × fuelCostPerParsec + perWarpCosts`, or `wormholeTax + perWarpCosts`.
    public var cost: Int
    /// INT-026: the risk weight of `to`.
    public var risk: Int

    public init(from: Int, to: Int, viaWormhole: Bool, distance: Int, fuelBefore: Int, refuelUnits: Int,
                refuelCost: Int, cost: Int, risk: Int = 0) {
        self.risk = risk
        self.from = from
        self.to = to
        self.viaWormhole = viaWormhole
        self.distance = distance
        self.fuelBefore = fuelBefore
        self.refuelUnits = refuelUnits
        self.refuelCost = refuelCost
        self.cost = cost
    }

    /// Fuel the hop consumes.
    public var fuelUsed: Int { viaWormhole ? 0 : distance }
}

/// MAP-059: a planned route. Costs are estimates (MAP-056).
public struct Route: Sendable, Equatable {
    public var from: Int
    public var to: Int
    public var objective: RouteObjective
    public var hops: [RouteHop]
    public var totalJumps: Int
    /// Parsecs flown on normal hops (wormhole hops add 0).
    public var totalParsecs: Int
    /// Sum of the hop edge costs.
    public var estimatedCredits: Int
    public var totalRefuelUnits: Int

    public init(from: Int, to: Int, objective: RouteObjective, hops: [RouteHop], totalJumps: Int, totalParsecs: Int,
                estimatedCredits: Int, totalRefuelUnits: Int) {
        self.from = from
        self.to = to
        self.objective = objective
        self.hops = hops
        self.totalJumps = totalJumps
        self.totalParsecs = totalParsecs
        self.estimatedCredits = estimatedCredits
        self.totalRefuelUnits = totalRefuelUnits
    }

    /// INT-027: the sum of the hop risk weights.
    public var totalRisk: Int { hops.reduce(0) { $0 + $1.risk } }

    /// The systems the route visits, `from` first and `to` last.
    public var stops: [Int] { [from] + hops.map(\.to) }
}

/// MAP-055: one directed edge of the route graph.
public struct RouteEdge: Sendable, Equatable {
    public var to: Int
    public var viaWormhole: Bool
    public var distance: Int
    /// Parsecs the edge adds to a route (0 for a wormhole).
    public var parsecs: Int
    public var credits: Int
    /// INT-026: the risk weight of the destination system.
    public var risk: Int = 0
}

/// MAP-054…058: the route planner.
public enum RoutePlanner {
    /// MAP-055: the outgoing edges of `a`, in system-index order. A wormhole edge replaces any normal edge to the same
    /// system; a normal edge exists iff the distance is at most `fuelCapacity`.
    public static func edges(from a: Int, in snapshot: RouteSnapshot) -> [RouteEdge] {
        edges(from: a, in: snapshot, wormholeTo: snapshot.wormholeDestinations[a])
    }

    static func edges(from a: Int, in s: RouteSnapshot, wormholeTo: Int?) -> [RouteEdge] {
        let limit = s.distanceRule.maxSquaredDistance(withinRange: s.fuelCapacity)
        var out: [RouteEdge] = []
        for b in s.points.indices where b != a {
            if b == wormholeTo {
                out.append(RouteEdge(to: b, viaWormhole: true, distance: s.distance(a, b), parsecs: 0,
                                     credits: s.wormholeTax + s.perWarpCosts, risk: s.risk(b)))
            } else if s.squaredDistance(a, b) <= limit {
                let d = s.distance(a, b)
                out.append(RouteEdge(to: b, viaWormhole: false, distance: d, parsecs: d,
                                     credits: d * s.fuelCostPerParsec + s.perWarpCosts, risk: s.risk(b)))
            }
        }
        return out
    }

    /// MAP-055: breadth-first jump counts from `from` (0 there, nil when unreachable or `from` is out of range).
    public static func jumpCounts(from: Int, in snapshot: RouteSnapshot) -> [Int?] {
        var counts = [Int?](repeating: nil, count: snapshot.points.count)
        guard counts.indices.contains(from) else { return counts }
        let worm = snapshot.wormholeDestinations
        counts[from] = 0
        var queue = [from]
        var head = 0
        while head < queue.count {
            let a = queue[head]
            head += 1
            let next = (counts[a] ?? 0) + 1
            for e in edges(from: a, in: snapshot, wormholeTo: worm[a]) where counts[e.to] == nil {
                counts[e.to] = next
                queue.append(e.to)
            }
        }
        return counts
    }

    /// MAP-057: the Dijkstra key of an objective.
    struct Key: Comparable {
        var a: Int
        var b: Int
        var c: Int

        static func < (l: Key, r: Key) -> Bool { (l.a, l.b, l.c) < (r.a, r.b, r.c) }

        static func + (l: Key, r: Key) -> Key { Key(a: l.a + r.a, b: l.b + r.b, c: l.c + r.c) }
    }

    static func key(_ e: RouteEdge, _ objective: RouteObjective) -> Key {
        switch objective {
        case .fewestJumps: Key(a: 1, b: e.parsecs, c: e.credits)
        case .cheapest: Key(a: e.credits, b: 1, c: e.parsecs)
        case .lowestRisk: Key(a: e.risk, b: 1, c: e.credits)
        }
    }

    /// MAP-054…059: the best route from `from` to `to`, or nil when `from == to`, an index is out of range or `to` is
    /// unreachable. Ties are broken by (key, system index), keeping the lower-index predecessor (MAP-058).
    public static func plan(from: Int, to: Int, in snapshot: RouteSnapshot,
                            objective: RouteObjective = .fewestJumps) -> Route? {
        let n = snapshot.points.count
        guard from != to, (0..<n).contains(from), (0..<n).contains(to) else { return nil }
        let worm = snapshot.wormholeDestinations
        var best = [Key?](repeating: nil, count: n)
        var pred = [RouteEdge?](repeating: nil, count: n)
        var predFrom = [Int](repeating: -1, count: n)
        var settled = [Bool](repeating: false, count: n)
        best[from] = Key(a: 0, b: 0, c: 0)
        while true {
            // The frontier minimum by (key, index): the first strictly smaller key in index order wins.
            var pick: (index: Int, key: Key)?
            for i in 0..<n where !settled[i] {
                guard let k = best[i] else { continue }
                if let p = pick, !(k < p.key) { continue }
                pick = (i, k)
            }
            guard let (u, base) = pick, u != to else { break }
            settled[u] = true
            for e in edges(from: u, in: snapshot, wormholeTo: worm[u]) where !settled[e.to] {
                let candidate = base + key(e, objective)
                if let current = best[e.to], !(candidate < current), !(candidate == current && u < predFrom[e.to]) {
                    continue
                }
                best[e.to] = candidate
                pred[e.to] = e
                predFrom[e.to] = u
            }
        }
        guard best[to] != nil else { return nil }
        var path: [(Int, RouteEdge)] = []
        var node = to
        while node != from, let e = pred[node] {
            path.append((predFrom[node], e))
            node = predFrom[node]
        }
        return route(from: from, to: to, objective: objective, path: path.reversed(), snapshot: snapshot)
    }

    /// MAP-056: simulates fuel along the path, buying exactly the shortfall before each normal hop.
    static func route(from: Int, to: Int, objective: RouteObjective, path: [(Int, RouteEdge)],
                      snapshot s: RouteSnapshot) -> Route {
        var fuel = max(0, min(s.currentFuel, s.fuelCapacity))
        var hops: [RouteHop] = []
        hops.reserveCapacity(path.count)
        for (a, e) in path {
            let need = e.viaWormhole ? 0 : e.distance
            let refuel = max(0, need - fuel)
            hops.append(RouteHop(from: a, to: e.to, viaWormhole: e.viaWormhole, distance: e.distance, fuelBefore: fuel,
                                 refuelUnits: refuel, refuelCost: refuel * s.fuelCostPerParsec, cost: e.credits,
                                 risk: e.risk))
            fuel += refuel - need
        }
        return Route(from: from, to: to, objective: objective, hops: hops, totalJumps: hops.count,
                     totalParsecs: path.reduce(0) { $0 + $1.1.parsecs },
                     estimatedCredits: hops.reduce(0) { $0 + $1.cost },
                     totalRefuelUnits: hops.reduce(0) { $0 + $1.refuelUnits })
    }
}
