// SPDX-License-Identifier: GPL-2.0-or-later
import CoreGraphics
import Foundation
import ParsecInsights

/// A one-way wormhole link (MAP-038): from the vortex beside `origin` to the system `destination`.
nonisolated struct WormholeLink: Sendable, Equatable {
    var origin: Int
    var destination: Int
}

/// A quadratic arc in view coordinates.
nonisolated struct MapArc: Sendable, Equatable {
    var start: CGPoint
    var control: CGPoint
    var end: CGPoint
}

/// One leg of the drawn route (MAP-066).
nonisolated struct RouteSegment: Sendable, Equatable {
    var hop: Int
    var start: CGPoint
    /// Set for a wormhole hop, which follows its link arc.
    var control: CGPoint?
    var end: CGPoint
    var isNext: Bool
}

/// Pure geometry shared by the renderer, the hit tester and the tests.
nonisolated enum MapGeometry {
    /// MAP-038: `wormholes[k] → wormholes[(k + 1) % count]` for every k.
    static func wormholeLinks(_ s: MapSnapshot) -> [WormholeLink] {
        guard s.wormholes.count > 1 else { return [] }
        return s.wormholes.indices.map { WormholeLink(origin: s.wormholes[$0], destination: s.wormholes[($0 + 1) % s.wormholes.count]) }
    }

    /// The vortex glyph centre beside system `i` (MAP-037).
    static func wormholeGlyphCenter(_ i: Int, snapshot s: MapSnapshot, projection p: MapProjection, metrics m: GlyphMetrics) -> CGPoint {
        let c = p.toView(x: s.systems[i].x, y: s.systems[i].y)
        return CGPoint(x: c.x + m.wormholeOffset(s.systems[i].size), y: c.y)
    }

    /// MAP-038: the arc bows by 15% of its chord to the left of the travel direction (y grows downward).
    static func arc(from a: CGPoint, to b: CGPoint) -> MapArc {
        let dx = b.x - a.x, dy = b.y - a.y
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        // Left of (dx, dy) on screen is (dy, −dx).
        return MapArc(start: a, control: CGPoint(x: mid.x + 0.15 * dy, y: mid.y - 0.15 * dx), end: b)
    }

    static func linkArc(_ link: WormholeLink, snapshot s: MapSnapshot, projection p: MapProjection, metrics m: GlyphMetrics) -> MapArc {
        arc(from: wormholeGlyphCenter(link.origin, snapshot: s, projection: p, metrics: m),
            to: p.toView(x: s.systems[link.destination].x, y: s.systems[link.destination].y))
    }

    /// MAP-041 (mini chart): a triangle `length` pt long from `center` toward `target`; nil when they coincide.
    static func bearingTriangle(from center: CGPoint, toward target: CGPoint, length: Double = 25, halfWidth: Double = 4) -> [CGPoint]? {
        let dx = target.x - center.x, dy = target.y - center.y
        let d = (dx * dx + dy * dy).squareRoot()
        guard d > 1e-9 else { return nil }
        let ux = dx / d, uy = dy / d
        let tip = CGPoint(x: center.x + ux * length, y: center.y + uy * length)
        return [tip, CGPoint(x: center.x - uy * halfWidth, y: center.y + ux * halfWidth),
                CGPoint(x: center.x + uy * halfWidth, y: center.y - ux * halfWidth)]
    }

    /// MAP-041 (galaxy): the dotted bearing line, current → tracked; nil when nothing (else) is tracked.
    static func trackedBearing(_ s: MapSnapshot, projection p: MapProjection) -> (CGPoint, CGPoint)? {
        guard let t = s.trackedSystem, t != s.currentSystem, s.systems.indices.contains(t) else { return nil }
        return (p.toView(x: s.current.x, y: s.current.y), p.toView(x: s.systems[t].x, y: s.systems[t].y))
    }

    /// MAP-066: the route polyline; a wormhole hop follows its link arc. Hop `n` (1-based) ends at its stop.
    static func routeSegments(_ s: MapSnapshot, projection p: MapProjection, metrics m: GlyphMetrics) -> [RouteSegment] {
        guard let route = s.route else { return [] }
        let nextHop = route.hops.firstIndex { $0.from == s.currentSystem }
        return route.hops.enumerated().map { n, hop in
            let end = p.toView(x: s.systems[hop.to].x, y: s.systems[hop.to].y)
            if hop.viaWormhole {
                let a = linkArc(WormholeLink(origin: hop.from, destination: hop.to), snapshot: s, projection: p, metrics: m)
                return RouteSegment(hop: n + 1, start: p.toView(x: s.systems[hop.from].x, y: s.systems[hop.from].y),
                                    control: a.control, end: end, isNext: n == nextHop)
            }
            return RouteSegment(hop: n + 1, start: p.toView(x: s.systems[hop.from].x, y: s.systems[hop.from].y), control: nil,
                                end: end, isNext: n == nextHop)
        }
    }

    /// The route's stops after the origin (labelled and numbered).
    static func routeStops(_ s: MapSnapshot) -> [Int] { s.route?.hops.map(\.to) ?? [] }
}

/// Projected positions for one (generation, viewport, view size) (MAP-088). Hover never touches it.
nonisolated struct ProjectedMap: Sendable, Equatable {
    struct Key: Sendable, Equatable, Hashable {
        var generation: Int
        var viewport: MapViewport
        var width: Double
        var height: Double
        var labelAll: Bool
    }

    var key: Key
    var projection: MapProjection
    var metrics: GlyphMetrics
    var centers: [CGPoint]
    /// Systems whose glyph lies in the view plus 16 pt (MAP-025).
    var visible: [Int]
    var labels: [MapLabel]

    static let cullMargin: Double = 16

    static func make(snapshot s: MapSnapshot, viewport: MapViewport, viewSize: CGSize, labelAll: Bool = false) -> ProjectedMap {
        let p = viewport.projection(viewSize: viewSize, bounds: MapBounds(s))
        let m = GlyphMetrics(zoom: viewport.zoom)
        let centers = s.systems.map { p.toView(x: $0.x, y: $0.y) }
        let bounds = CGRect(origin: .zero, size: viewSize).insetBy(dx: -cullMargin, dy: -cullMargin)
        let visible = s.systems.indices.filter { i in
            let r = m.radius(s.systems[i].size) + m.wormholeOffset(s.systems[i].size) + m.wormholeRadius
            return bounds.intersects(CGRect(x: centers[i].x - r, y: centers[i].y - r, width: 2 * r, height: 2 * r))
        }
        let labels = MapLabelPolicy.labels(snapshot: s, projection: p, zoom: viewport.zoom, hovered: nil, viewSize: viewSize,
                                           labelAll: labelAll)
        return ProjectedMap(key: Key(generation: s.generation, viewport: viewport, width: viewSize.width, height: viewSize.height,
                                     labelAll: labelAll),
                            projection: p, metrics: m, centers: centers, visible: visible, labels: labels)
    }
}

/// Caches the projected map per key and counts rebuilds (MAP-088).
@MainActor
final class ProjectedMapCache {
    private(set) var builds = 0
    private var cached: ProjectedMap?

    func map(snapshot: MapSnapshot, viewport: MapViewport, viewSize: CGSize, labelAll: Bool = false) -> ProjectedMap {
        let key = ProjectedMap.Key(generation: snapshot.generation, viewport: viewport, width: viewSize.width,
                                   height: viewSize.height, labelAll: labelAll)
        if let cached, cached.key == key { return cached }
        let m = ProjectedMap.make(snapshot: snapshot, viewport: viewport, viewSize: viewSize, labelAll: labelAll)
        cached = m
        builds += 1
        return m
    }
}
