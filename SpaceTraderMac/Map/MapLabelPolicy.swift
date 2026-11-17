// SPDX-License-Identifier: GPL-2.0-or-later
import CoreGraphics
import Foundation
import ParsecEngine
import ParsecInsights

/// A placed system label (MAP-026). The caption's text is resolved by the renderer (it is localized).
nonisolated struct MapLabel: Sendable, Equatable {
    var system: Int
    var name: String
    var caption: Caption?
    var rect: CGRect

    struct Caption: Sendable, Equatable {
        var techLevel: TechLevel
        var politics: PoliticalSystemType
    }
}

nonisolated enum MapLabelPolicy {
    static let allLabelsZoom: Double = 2
    static let captionZoom: Double = 6
    static let nameHeight: Double = 13
    static let captionHeight: Double = 12
    static let nameCharWidth: Double = 6.4
    static let captionWidth: Double = 150

    /// MAP-026: always label current, target, tracked, hovered and route stops; all others from zoom 2; captions from
    /// zoom 6; greedy collision removal in priority order. `labelAll` is the mini chart (every system labelled).
    static func labels(snapshot s: MapSnapshot, projection p: MapProjection, zoom: Double, hovered: Int?,
                       viewSize: CGSize = CGSize(width: 1e9, height: 1e9), labelAll: Bool = false) -> [MapLabel] {
        var priority: [Int] = [s.currentSystem]
        if s.hasTarget { priority.append(s.warpSystem) }
        if let t = s.trackedSystem { priority.append(t) }
        if let hovered { priority.append(hovered) }
        priority += MapGeometry.routeStops(s)
        var seen = Set<Int>()
        priority = priority.filter { s.systems.indices.contains($0) && seen.insert($0).inserted }
        let always = Set(priority)
        let others = (zoom >= allLabelsZoom || labelAll) ? s.systems.indices.filter { !always.contains($0) } : []
        let m = GlyphMetrics(zoom: zoom)
        let view = CGRect(origin: .zero, size: viewSize).insetBy(dx: -ProjectedMap.cullMargin, dy: -ProjectedMap.cullMargin)
        var placed: [MapLabel] = []
        for i in priority + others {
            let sys = s.systems[i]
            let c = p.toView(x: sys.x, y: sys.y)
            let withCaption = zoom >= captionZoom
            let w = max(Double(sys.name.count) * nameCharWidth + 2, withCaption ? captionWidth : 0)
            let h = nameHeight + (withCaption ? captionHeight : 0)
            let r = m.radius(sys.size)
            let vortex = sys.wormholeDestination != nil ? 2 * m.wormholeRadius + 4 : 0
            let rect = CGRect(x: c.x + r + 4 + vortex, y: c.y - nameHeight / 2, width: w, height: h)
            guard view.intersects(rect) else { continue }
            if placed.contains(where: { $0.rect.intersects(rect) }) { continue }
            placed.append(MapLabel(system: i, name: sys.name,
                                   caption: withCaption ? .init(techLevel: sys.techLevel, politics: sys.politics) : nil, rect: rect))
        }
        return placed
    }
}
