// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import ParsecInsights

/// Accessibility text of a system element (MAP-080). Pure and localized.
enum MapAccessibility {
    /// "<Name>, visited|not visited, <N> parsecs, <Government>, <Tech level>"; "current system" replaces the distance.
    static func label(for i: Int, snapshot s: MapSnapshot) -> String {
        let sys = s.systems[i]
        let visit = sys.visited ? String(localized: "visited") : String(localized: "not visited")
        let place = i == s.currentSystem ? String(localized: "current system") : MapText.parsecs(sys.distance)
        return [sys.name, visit, place, String(localized: SystemText.government(sys.politics)),
                String(localized: SystemText.techLevel(sys.techLevel))].joined(separator: ", ")
    }

    /// Applicable states in order: target, tracked, in/out of range, wormhole to X, quest location, route stop n.
    static func value(for i: Int, snapshot s: MapSnapshot) -> String {
        let sys = s.systems[i]
        var parts: [String] = []
        if s.hasTarget, s.warpSystem == i { parts.append(String(localized: "target")) }
        if s.trackedSystem == i { parts.append(String(localized: "tracked")) }
        if i != s.currentSystem { parts.append(sys.inRange ? String(localized: "in range") : String(localized: "out of range")) }
        if let d = sys.wormholeDestination { parts.append(String(localized: "wormhole to \(s.systems[d].name)")) }
        if sys.isQuestLocation { parts.append(String(localized: "quest location")) }
        if let n = MapGeometry.routeStops(s).firstIndex(of: i) { parts.append(String(localized: "route stop \(n + 1)")) }
        return parts.joined(separator: ", ")
    }

    /// MAP-081: system elements, current system first, then by distance, then index.
    static func order(_ s: MapSnapshot) -> [Int] {
        [s.currentSystem] + s.byDistance(s.systems.indices.filter { $0 != s.currentSystem })
    }

    /// MAP-085: "Target <X>, <N> parsecs" or "Target <X>, out of range".
    static func targetAnnouncement(_ s: MapSnapshot) -> String? {
        guard s.hasTarget else { return nil }
        let t = s.systems[s.warpSystem]
        return t.inRange ? String(localized: "Target \(t.name), \(MapText.parsecs(t.distance))")
            : String(localized: "Target \(t.name), out of range")
    }
}

/// Custom VoiceOver rotors (MAP-083, MAP-084).
nonisolated enum MapRotor: String, CaseIterable, Sendable {
    case inRange, questLocations, wormholes, visited, unvisited

    var title: LocalizedStringResource {
        switch self {
        case .inRange: "In Range"
        case .questLocations: "Quest Locations"
        case .wormholes: "Wormholes"
        case .visited: "Visited"
        case .unvisited: "Unvisited"
        }
    }

    /// MAP-083: pure membership; every rotor except `wormholes` (ring order) is ordered by distance, then index.
    static func members(_ rotor: MapRotor, snapshot s: MapSnapshot) -> [Int] {
        let others = s.systems.indices.filter { $0 != s.currentSystem }
        switch rotor {
        case .inRange: return s.byDistance(others.filter { s.systems[$0].inRange })
        case .questLocations: return s.byDistance(s.systems.indices.filter { s.systems[$0].isQuestLocation })
        case .wormholes: return s.wormholes
        case .visited: return s.byDistance(others.filter { s.systems[$0].visited })
        case .unvisited: return s.byDistance(others.filter { !s.systems[$0].visited })
        }
    }
}
