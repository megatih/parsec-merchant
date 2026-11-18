// SPDX-License-Identifier: GPL-2.0-or-later
import CoreGraphics
import Foundation
import ParsecEngine
import ParsecInsights

/// The galaxy extent a viewport works in (from the snapshot's ruleset tables).
nonisolated struct MapBounds: Sendable, Equatable, Hashable {
    var galaxyWidth: Int
    var galaxyHeight: Int

    init(galaxyWidth: Int, galaxyHeight: Int) {
        self.galaxyWidth = galaxyWidth
        self.galaxyHeight = galaxyHeight
    }

    init(_ snapshot: MapSnapshot) {
        self.init(galaxyWidth: snapshot.galaxyWidth, galaxyHeight: snapshot.galaxyHeight)
    }

    var content: CGRect { MapProjection.content(galaxyWidth: galaxyWidth, galaxyHeight: galaxyHeight) }
    var contentCenter: CGPoint { CGPoint(x: content.midX, y: content.midY) }
}

/// Resolution-independent viewport (MAP-008…012): a zoom over Fit Galaxy and a centre in galaxy coordinates.
nonisolated struct MapViewport: Sendable, Equatable, Hashable, Codable {
    static let minZoom: Double = 1
    static let maxZoom: Double = 12
    /// ⌘+ / ⌘− step (MAP-015).
    static let zoomStep: Double = 2.0.squareRoot()
    /// ⌘-scroll step per wheel notch (MAP-014).
    static let wheelZoomStep: Double = 1.1

    var zoom: Double
    var center: CGPoint

    /// MAP-011: zoom 1 at the content centre.
    static func fitGalaxy(_ bounds: MapBounds) -> MapViewport {
        MapViewport(zoom: 1, center: bounds.contentCenter)
    }

    var isAtMinZoom: Bool { zoom <= Self.minZoom + 1e-9 }
    var isAtMaxZoom: Bool { zoom >= Self.maxZoom - 1e-9 }

    func scale(viewSize: CGSize, bounds: MapBounds) -> Double {
        MapProjection.fitScale(viewSize: viewSize, content: bounds.content) * zoom
    }

    /// MAP-008: `origin = center − viewSize / (2 × scale)`.
    func projection(viewSize: CGSize, bounds: MapBounds) -> MapProjection {
        let s = scale(viewSize: viewSize, bounds: bounds)
        return MapProjection(scale: s, origin: CGPoint(x: center.x - viewSize.width / (2 * s), y: center.y - viewSize.height / (2 * s)))
    }

    /// MAP-009: zoom in [1, 12]; centre in the galaxy rectangle; forced to the content centre at zoom 1.
    func clamped(_ bounds: MapBounds) -> MapViewport {
        let z = min(max(zoom.isFinite ? zoom : 1, Self.minZoom), Self.maxZoom)
        if z <= Self.minZoom + 1e-9 { return MapViewport(zoom: Self.minZoom, center: bounds.contentCenter) }
        let x = min(max(center.x.isFinite ? center.x : 0, 0), Double(bounds.galaxyWidth))
        let y = min(max(center.y.isFinite ? center.y : 0, 0), Double(bounds.galaxyHeight))
        return MapViewport(zoom: z, center: CGPoint(x: x, y: y))
    }

    /// MAP-010: keeps the galaxy point under `anchor` fixed (unless a clamp applies).
    func zoomed(by factor: Double, anchor: CGPoint, viewSize: CGSize, bounds: MapBounds) -> MapViewport {
        let before = projection(viewSize: viewSize, bounds: bounds)
        let g = before.toGalaxy(anchor)
        let z = min(max(zoom * factor, Self.minZoom), Self.maxZoom)
        let s = MapProjection.fitScale(viewSize: viewSize, content: bounds.content) * z
        // Choose the centre so that g maps to anchor: origin = g − anchor / s; centre = origin + view / (2s).
        let origin = CGPoint(x: g.x - anchor.x / s, y: g.y - anchor.y / s)
        let c = CGPoint(x: origin.x + viewSize.width / (2 * s), y: origin.y + viewSize.height / (2 * s))
        return MapViewport(zoom: z, center: c).clamped(bounds)
    }

    /// Zoom around the view centre (keys, HUD buttons, menu items).
    func zoomed(by factor: Double, viewSize: CGSize, bounds: MapBounds) -> MapViewport {
        zoomed(by: factor, anchor: CGPoint(x: viewSize.width / 2, y: viewSize.height / 2), viewSize: viewSize, bounds: bounds)
    }

    /// MAP-010: the centre moves by `−delta / scale`.
    func panned(byViewDelta delta: CGSize, viewSize: CGSize, bounds: MapBounds) -> MapViewport {
        let s = scale(viewSize: viewSize, bounds: bounds)
        return MapViewport(zoom: zoom, center: CGPoint(x: center.x - delta.width / s, y: center.y - delta.height / s)).clamped(bounds)
    }

    /// MAP-015: arrow keys pan by one eighth of the visible extent.
    func pannedByArrow(dx: Int, dy: Int, viewSize: CGSize, bounds: MapBounds) -> MapViewport {
        panned(byViewDelta: CGSize(width: -Double(dx) * viewSize.width / 8, height: -Double(dy) * viewSize.height / 8),
               viewSize: viewSize, bounds: bounds)
    }

    /// MAP-011: centred on the current system, a circle of radius max(R, 5) parsecs plus 20% fills the shorter side.
    static func fitRange(snapshot: MapSnapshot, viewSize: CGSize) -> MapViewport {
        let bounds = MapBounds(snapshot)
        let r = max(MapRange.ringRadius(snapshot), 5)
        let diameter = 2 * r * 1.2
        let fit = MapProjection.fitScale(viewSize: viewSize, content: bounds.content)
        let shorter = min(viewSize.width, viewSize.height)
        let zoom = shorter / diameter / fit
        let c = snapshot.current
        return MapViewport(zoom: zoom, center: CGPoint(x: c.x, y: c.y)).clamped(bounds)
    }

    /// MAP-012: centre on a system and raise the zoom to at least 3.
    func centered(on index: Int, snapshot: MapSnapshot) -> MapViewport {
        guard snapshot.systems.indices.contains(index) else { return self }
        let s = snapshot.systems[index]
        return MapViewport(zoom: max(zoom, 3), center: CGPoint(x: s.x, y: s.y)).clamped(MapBounds(snapshot))
    }
}

/// Range-ring radii (MAP-034, MAP-036) in parsecs.
nonisolated enum MapRange {
    /// `√maxSquaredDistance(fuel)`; 0 when fuel is 0 (nothing drawn).
    static func ringRadius(_ s: MapSnapshot) -> Double {
        guard s.fuel > 0 else { return 0 }
        return Double(s.distanceRule.maxSquaredDistance(withinRange: s.fuel)).squareRoot()
    }

    /// The full-tank ring, or nil at a full tank.
    static func fullTankRadius(_ s: MapSnapshot) -> Double? {
        guard s.fuel < s.fuelCapacity else { return nil }
        return Double(max(0, s.distanceRule.maxSquaredDistance(withinRange: s.fuelCapacity))).squareRoot()
    }
}

/// UI-PTR-012, MAP-014: what a scroll event does to the map. Pure.
nonisolated enum MapScroll {
    enum Action: Equatable, Sendable {
        /// Zoom by `wheelZoomStep ^ steps` about the pointer.
        case zoom(steps: Double)
        case pan(CGSize)
    }

    /// A mouse wheel (non-precise deltas) zooms one step per notch; two-finger trackpad scrolling (precise deltas) pans,
    /// unless ⌘ is held, which zooms at a tenth of a step per point.
    static func action(deltaX: Double, deltaY: Double, precise: Bool, command: Bool) -> Action {
        if !precise { return .zoom(steps: deltaY) }
        if command { return .zoom(steps: deltaY / 10) }
        return .pan(CGSize(width: deltaX, height: deltaY))
    }
}
