// SPDX-License-Identifier: GPL-2.0-or-later
import CoreGraphics
import Foundation
import ParsecInsights

/// Galaxy ↔ view mapping (MAP-005): `v = (g − origin) × scale`, `g = v / scale + origin`; y grows downward.
nonisolated struct MapProjection: Sendable, Equatable {
    /// Points per parsec.
    var scale: Double
    /// The galaxy coordinate at the view's top-left.
    var origin: CGPoint

    func toView(_ g: CGPoint) -> CGPoint {
        CGPoint(x: (g.x - origin.x) * scale, y: (g.y - origin.y) * scale)
    }

    func toView(x: Int, y: Int) -> CGPoint { toView(CGPoint(x: x, y: y)) }

    func toGalaxy(_ v: CGPoint) -> CGPoint {
        CGPoint(x: v.x / scale + origin.x, y: v.y / scale + origin.y)
    }

    /// The margin around the galaxy, in parsecs (MAP-006).
    static let margin: Double = 4

    /// The content rectangle `[−4, w + 4] × [−4, h + 4]` (MAP-006).
    static func content(galaxyWidth: Int, galaxyHeight: Int) -> CGRect {
        CGRect(x: -margin, y: -margin, width: Double(galaxyWidth) + 2 * margin, height: Double(galaxyHeight) + 2 * margin)
    }

    /// MAP-007: the scale at which the content fits the view.
    static func fitScale(viewSize: CGSize, content: CGRect) -> Double {
        guard content.width > 0, content.height > 0 else { return 1 }
        return max(0.0001, min(viewSize.width / content.width, viewSize.height / content.height))
    }
}
