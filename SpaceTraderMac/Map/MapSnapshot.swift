// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import ParsecInsights

/// One system as the map knows it (MAP-001). Only what the player legitimately knows (MAP-002).
nonisolated struct MapSystem: Sendable, Equatable, Identifiable {
    var index: Int
    var name: String
    var x: Int
    var y: Int
    var size: SystemSize
    var techLevel: TechLevel
    var politics: PoliticalSystemType
    var visited: Bool
    /// The resource the player knows (`knownResource`); nil until visited.
    var knownResource: SpecialResource?
    var police: Activity
    var pirates: Activity
    var wormholeDestination: Int?
    var distance: Int
    var squaredDistance: Int
    var inRange: Bool
    var questKinds: [QuestLogKind]
    var hasSpecialEventHere: Bool
    /// A shipyard the player has seen (visited systems only, MAP-072).
    var hasShipyard: Bool

    var id: Int { index }
    var isQuestLocation: Bool { !questKinds.isEmpty || hasSpecialEventHere }
}

/// The Sendable value every map draws from (MAP-001). Built once per state generation and planned route (MAP-003).
nonisolated struct MapSnapshot: Sendable, Equatable {
    var generation: Int
    var galaxyWidth: Int
    var galaxyHeight: Int
    var distanceRule: DistanceRule
    var systems: [MapSystem]
    /// Ring order: `wormholes[k]` leads to `wormholes[(k + 1) % count]`.
    var wormholes: [Int]
    var currentSystem: Int
    var warpSystem: Int
    /// The origin wormhole system of the targeted link, when the target is selected through a wormhole.
    var targetWormhole: Int?
    var trackedSystem: Int?
    var fuel: Int
    var fuelCapacity: Int
    var showTrackedRange: Bool
    var wormholeSelectionScope: WormholeSelectionScope
    var isDocked: Bool
    var route: Route?
    /// `ruleset.content.hasShipyards` (offers the shipyard search filter).
    var hasShipyards: Bool

    var current: MapSystem { systems[currentSystem] }
    var hasTarget: Bool { warpSystem != currentSystem }

    /// MAP-001: the snapshot of `state`. Reads no prices, stock, hidden resource, special event field or RNG (MAP-002).
    static func make(state: GameState, generation: Int, route: Route?) -> MapSnapshot {
        let cur = state.commander.currentSystem
        let here = state.galaxy.systems[cur]
        let rule = state.ruleset.flags.distance
        var quests: [Int: [QuestLogKind]] = [:]
        for entry in state.questLog {
            for s in entry.systems where !(quests[s]?.contains(entry.kind) ?? false) { quests[s, default: []].append(entry.kind) }
        }
        let specialHere = state.specialEventAvailable != nil
        let names = state.ruleset.tables.systemNames
        let systems = state.galaxy.systems.enumerated().map { i, s in
            let politics = state.ruleset.tables.politics(s.politics)
            let dx = s.x - here.x, dy = s.y - here.y
            return MapSystem(index: i, name: names.indices.contains(i) ? names[i] : "#\(i)", x: s.x, y: s.y, size: s.size,
                             techLevel: s.techLevel, politics: s.politics, visited: s.visited,
                             knownResource: s.visited ? s.knownResource : nil,
                             police: politics.activityPolice, pirates: politics.activityPirates,
                             wormholeDestination: state.galaxy.wormholeDestination(from: i),
                             distance: GalaxyGenerator.distance(s, here, rule: rule), squaredDistance: dx * dx + dy * dy,
                             inRange: state.destinationOK(i), questKinds: quests[i] ?? [],
                             hasSpecialEventHere: i == cur && specialHere, hasShipyard: s.visited && s.shipyard != nil)
        }
        var targetWormhole: Int?
        if state.targetWormhole {
            targetWormhole = state.galaxy.wormholeExists(from: cur, to: state.warpSystem)
                ? cur : state.galaxy.wormholes.first { state.galaxy.wormholeDestination(from: $0) == state.warpSystem }
        }
        return MapSnapshot(generation: generation, galaxyWidth: state.ruleset.tables.galaxyWidth,
                           galaxyHeight: state.ruleset.tables.galaxyHeight, distanceRule: rule, systems: systems,
                           wormholes: state.galaxy.wormholes, currentSystem: cur, warpSystem: state.warpSystem,
                           targetWormhole: targetWormhole, trackedSystem: state.trackedSystem, fuel: state.commander.ship.fuel,
                           fuelCapacity: state.fuelCapacity, showTrackedRange: state.options.showTrackedRange,
                           wormholeSelectionScope: state.ruleset.flags.travel.wormholeSelectionScope,
                           isDocked: state.phase == .docked, route: route, hasShipyards: state.ruleset.content.hasShipyards)
    }

    /// The distance between two systems under the ruleset rule.
    func distance(_ a: Int, _ b: Int) -> Int {
        GalaxyGenerator.distance(systems[a].x, systems[a].y, systems[b].x, systems[b].y, rule: distanceRule)
    }

    /// The systems by distance from the current system, then index (MAP-081, MAP-083).
    func byDistance(_ indices: [Int]) -> [Int] {
        indices.sorted { (systems[$0].distance, $0) < (systems[$1].distance, $1) }
    }
}
