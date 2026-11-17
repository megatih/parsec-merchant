// SPDX-License-Identifier: GPL-2.0-or-later
import CoreGraphics
import Foundation
import ParsecInsights

/// What a point on the map hits (MAP-019).
nonisolated enum MapHit: Sendable, Equatable, Hashable {
    case system(Int)
    /// The wormhole glyph beside system `i`.
    case wormhole(Int)

    /// The system the hit belongs to (a wormhole glyph acts on its system for ⌥-click, MAP-052).
    var systemIndex: Int {
        switch self {
        case let .system(i), let .wormhole(i): i
        }
    }
}

nonisolated enum MapHitTester {
    /// MAP-019…022: nearest candidate within its hit radius; ties go to systems, then the lower index.
    static func hit(at point: CGPoint, snapshot s: MapSnapshot, projection p: MapProjection, metrics m: GlyphMetrics,
                    viewSize: CGSize) -> MapHit? {
        guard CGRect(origin: .zero, size: viewSize).contains(point) else { return nil }
        let bounds = CGRect(origin: .zero, size: viewSize)
        var best: (hit: MapHit, d: Double, rank: Int)?
        func consider(_ hit: MapHit, center: CGPoint, radius: Double, rank: Int) {
            guard bounds.contains(center) else { return }
            let dx = center.x - point.x, dy = center.y - point.y
            let d = (dx * dx + dy * dy).squareRoot()
            guard d <= radius else { return }
            if let b = best {
                if d < b.d - 1e-9 || (abs(d - b.d) <= 1e-9 && rank < b.rank) { best = (hit, d, rank) }
            } else {
                best = (hit, d, rank)
            }
        }
        let n = s.systems.count
        for sys in s.systems {
            consider(.system(sys.index), center: p.toView(x: sys.x, y: sys.y), radius: m.systemHitRadius(sys.size), rank: sys.index)
        }
        for w in s.wormholes where s.systems.indices.contains(w) {
            consider(.wormhole(w), center: MapGeometry.wormholeGlyphCenter(w, snapshot: s, projection: p, metrics: m),
                     radius: m.wormholeHitRadius, rank: n + w)
        }
        return best?.hit
    }
}
