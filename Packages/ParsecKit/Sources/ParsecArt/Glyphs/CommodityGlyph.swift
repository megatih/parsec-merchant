// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// ART-031: the 10 commodities in `TradeItemType` order.
public enum CommodityGlyphKind: Int, CaseIterable, Sendable, Hashable {
    case water = 0, furs, food, ore, games, firearms, medicine, machines, narcotics, robots
}

/// ART-031: one template glyph per commodity; it takes the foreground style.
public struct CommodityGlyph: Shape {
    public var kind: CommodityGlyphKind

    public init(kind: CommodityGlyphKind) { self.kind = kind }

    public func path(in rect: CGRect) -> Path { GlyphKit.fit(Self.unitPath(kind), in: rect) }

    static func unitPath(_ kind: CommodityGlyphKind) -> Path {
        typealias GK = GlyphKit
        switch kind {
        case .water:
            return ArtGeometry.closedSpline([SplinePoint(0.5, 0.06, sharp: true), SplinePoint(0.72, 0.42), SplinePoint(0.78, 0.64),
                                             SplinePoint(0.5, 0.92), SplinePoint(0.22, 0.64), SplinePoint(0.28, 0.42)])
                .subtracting(GK.arc(0.5, 0.64, 0.17, from: 100, to: 170, width: 0.06))
        case .furs:
            return ArtGeometry.closedSpline([SplinePoint(0.3, 0.1), SplinePoint(0.5, 0.18), SplinePoint(0.7, 0.1), SplinePoint(0.78, 0.3),
                                             SplinePoint(0.9, 0.42), SplinePoint(0.74, 0.55), SplinePoint(0.84, 0.86), SplinePoint(0.6, 0.78),
                                             SplinePoint(0.5, 0.92), SplinePoint(0.4, 0.78), SplinePoint(0.16, 0.86), SplinePoint(0.26, 0.55),
                                             SplinePoint(0.1, 0.42), SplinePoint(0.22, 0.3)])
        case .food:
            var parts = [GK.line([(0.5, 0.95), (0.5, 0.3)], width: 0.06), GK.line([(0.5, 0.95), (0.3, 0.42)], width: 0.05),
                         GK.line([(0.5, 0.95), (0.7, 0.42)], width: 0.05)]
            for (x, y, a) in [(0.5, 0.18, 0.0), (0.5, 0.36, 0.0), (0.3, 0.3, -25.0), (0.7, 0.3, 25.0), (0.36, 0.5, -30.0), (0.64, 0.5, 30.0)] {
                parts.append(GK.rotated(Path(ellipseIn: CGRect(x: x - 0.06, y: y - 0.1, width: 0.12, height: 0.2)), degrees: a,
                                       about: CGPoint(x: x, y: y)))
            }
            parts.append(GK.rect(0.36, 0.66, 0.28, 0.07, corner: 0.03))
            return GK.union(parts)
        case .ore:
            return GK.poly([(0.3, 0.14), (0.66, 0.1), (0.9, 0.42), (0.76, 0.86), (0.28, 0.9), (0.1, 0.5)])
                .subtracting(GK.line([(0.3, 0.14), (0.46, 0.46), (0.9, 0.42)], width: 0.04))
                .subtracting(GK.line([(0.46, 0.46), (0.28, 0.9)], width: 0.04))
        case .games:
            var die = GK.rect(0.12, 0.12, 0.76, 0.76, corner: 0.14)
            for (x, y) in [(0.3, 0.3), (0.7, 0.3), (0.5, 0.5), (0.3, 0.7), (0.7, 0.7)] { die = die.subtracting(GK.circle(x, y, 0.07)) }
            return die
        case .firearms:
            let barrelA = GK.rotated(GK.rect(0.08, 0.44, 0.84, 0.12, corner: 0.03), degrees: 35)
            let barrelB = GK.rotated(GK.rect(0.08, 0.44, 0.84, 0.12, corner: 0.03), degrees: -35)
            return GK.union([barrelA, barrelB, GK.arc(0.5, 0.5, 0.16, from: 0, to: 360, width: 0.06)])
        case .medicine:
            let vial = GK.union([GK.rect(0.28, 0.24, 0.44, 0.68, corner: 0.1), GK.rect(0.36, 0.08, 0.28, 0.14, corner: 0.03)])
            return vial.subtracting(GK.union([GK.rect(0.44, 0.38, 0.12, 0.38), GK.rect(0.33, 0.51, 0.34, 0.12)]))
        case .machines:
            return ArtGeometry.star(center: CGPoint(x: 0.5, y: 0.5), points: 9, outer: 0.44, inner: 0.34, rotation: 0)
                .union(GK.circle(0.5, 0.5, 0.35)).subtracting(GK.circle(0.5, 0.5, 0.14))
        case .narcotics:
            let pill = GK.rotated(GK.rect(0.12, 0.34, 0.76, 0.32, corner: 0.16), degrees: -40)
            return pill.subtracting(GK.rotated(GK.rect(0.48, 0.2, 0.04, 0.6), degrees: -40))
        case .robots:
            let head = GK.union([GK.rect(0.18, 0.3, 0.64, 0.56, corner: 0.12), GK.line([(0.5, 0.3), (0.5, 0.14)], width: 0.05),
                                GK.circle(0.5, 0.12, 0.06), GK.rect(0.08, 0.48, 0.1, 0.2, corner: 0.03), GK.rect(0.82, 0.48, 0.1, 0.2, corner: 0.03)])
            return head.subtracting(GK.union([GK.circle(0.37, 0.52, 0.08), GK.circle(0.63, 0.52, 0.08), GK.rect(0.34, 0.7, 0.32, 0.06)]))
        }
    }
}

/// ART-031: the illegal-goods badge: a small octagon with a bar (a shape, never only a colour).
public struct IllegalBadge: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let octagon = ArtGeometry.star(center: CGPoint(x: 0.5, y: 0.5), points: 4, outer: 0.48, inner: 0.48 * cos(.pi / 8) / cos(.pi / 8),
                                       rotation: -.pi / 8)
        return GlyphKit.fit(octagon.subtracting(GlyphKit.rect(0.22, 0.43, 0.56, 0.14)), in: rect)
    }
}
