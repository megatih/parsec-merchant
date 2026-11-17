// SPDX-License-Identifier: GPL-2.0-or-later
// The public facts of the current state (docs/specs/INT.md §1, INT-001…005). INT reads only this and the IntelBook,
// so no hidden field (another system's stock, prices, countdown, pressure or true resource, the RNG, special-event
// placement) can reach a quote, a recommendation or a heatmap.
import ParsecEngine

/// INT-002: what the classic UI showed about one system.
public struct SystemFacts: Sendable, Equatable {
    public var x: Int
    public var y: Int
    public var size: SystemSize
    public var techLevel: TechLevel
    public var politics: PoliticalSystemType
    public var visited: Bool
    /// The special resource once visited, else `.nothing`.
    public var knownResource: SpecialResource
    /// The shipyard once visited.
    public var shipyard: ShipyardID?

    public init(x: Int, y: Int, size: SystemSize, techLevel: TechLevel, politics: PoliticalSystemType, visited: Bool,
                knownResource: SpecialResource, shipyard: ShipyardID?) {
        self.x = x
        self.y = y
        self.size = size
        self.techLevel = techLevel
        self.politics = politics
        self.visited = visited
        self.knownResource = visited ? knownResource : .nothing
        self.shipyard = visited ? shipyard : nil
    }
}

/// INT-002 / INT-003: the Sendable snapshot every INT function reads.
public struct IntelSnapshot: Sendable, Equatable {
    public var rulesetID: RulesetID
    public var day: Int
    public var currentSystem: Int
    public var isDocked: Bool
    public var systems: [SystemFacts]
    public var wormholes: [Int]
    public var distanceRule: DistanceRule
    public var fuelCapacity: Int
    /// Systems in range now (excluding the current one), ascending.
    public var destinations: [Int]
    /// The current system's market (only meaningful while docked).
    public var buyPrices: [Int]
    public var sellPrices: [Int]
    public var stock: [Int]
    public var pressure: SystemPressure
    /// The hold and its cost basis per item.
    public var cargo: [Int]
    public var priceCargo: [Int]
    /// ECO-077 market limits per item (Leave Empty and Reserve Money applied).
    public var maxBuy: [Int]
    public var maxSell: [Int]
    public var policeRecordScore: Int

    /// INT-002: copies only public facts.
    public init(_ state: GameState) {
        rulesetID = state.rulesetID
        day = state.commander.days
        currentSystem = state.commander.currentSystem
        if case .docked = state.phase { isDocked = true } else { isDocked = false }
        systems = state.galaxy.systems.map {
            SystemFacts(x: $0.x, y: $0.y, size: $0.size, techLevel: $0.techLevel, politics: $0.politics, visited: $0.visited,
                        knownResource: $0.knownResource, shipyard: $0.shipyard)
        }
        wormholes = state.galaxy.wormholes
        distanceRule = state.ruleset.flags.distance
        fuelCapacity = state.fuelCapacity
        destinations = state.destinations
        buyPrices = state.buyPrices
        sellPrices = state.sellPrices
        stock = state.currentSystem.tradeItems
        pressure = state.currentSystem.pressure
        cargo = state.commander.ship.cargo
        priceCargo = state.commander.priceCargo
        let rows = state.marketRows
        maxBuy = rows.map(\.maxBuy)
        maxSell = rows.map(\.maxSell)
        policeRecordScore = state.commander.policeRecordScore
    }

    public var ruleset: Ruleset { .named(rulesetID) }

    /// The distance between two systems under the ruleset's rule.
    public func distance(_ a: Int, _ b: Int) -> Int {
        GalaxyGenerator.distance(systems[a].x, systems[a].y, systems[b].x, systems[b].y, rule: distanceRule)
    }

    /// True when the hold holds anything.
    public var hasCargo: Bool { cargo.contains { $0 > 0 } }

    /// A stand-in `StarSystem` with only public facts: the resource is the known one, the pressure is none.
    func publicSystem(_ index: Int) -> StarSystem {
        let f = systems[index]
        var s = StarSystem(id: index, x: f.x, y: f.y, size: f.size, techLevel: f.techLevel, politics: f.politics,
                           pressure: .none, specialResource: f.knownResource)
        s.visited = f.visited
        return s
    }
}
