// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// ART-032: 6 weapons, 3 shields and 7 gadgets, in engine enum order.
public enum EquipmentGlyphKind: Hashable, Sendable {
    case weapon(Int)
    case shield(Int)
    case gadget(Int)

    public static let allCases: [EquipmentGlyphKind] = (0..<6).map { .weapon($0) } + (0..<3).map { .shield($0) } + (0..<7).map { .gadget($0) }
}

/// ART-032: one template glyph per equipment item.
public struct EquipmentGlyph: Shape {
    public var kind: EquipmentGlyphKind

    public init(kind: EquipmentGlyphKind) { self.kind = kind }

    public func path(in rect: CGRect) -> Path { GlyphKit.fit(Self.unitPath(kind), in: rect) }

    static func unitPath(_ kind: EquipmentGlyphKind) -> Path {
        switch kind {
        case let .weapon(i): weapon(i)
        case let .shield(i): shield(i)
        case let .gadget(i): gadget(i)
        }
    }

    private static func emitter() -> Path { GlyphKit.rect(0.06, 0.3, 0.22, 0.4, corner: 0.05) }

    private static func weapon(_ i: Int) -> Path {
        typealias GK = GlyphKit
        switch i {
        case 0, 1, 2:
            let beams = i + 1
            var parts = [emitter()]
            for b in 0..<beams {
                let y = 0.5 + (Double(b) - Double(beams - 1) / 2) * 0.14
                parts.append(GK.line([(0.3, y), (0.92, y)], width: 0.07))
            }
            return GK.union(parts)
        case 3:
            return GK.union([emitter(), GK.line([(0.3, 0.5), (0.62, 0.5)], width: 0.07),
                            ArtGeometry.star(center: CGPoint(x: 0.78, y: 0.5), points: 5, outer: 0.18, inner: 0.08)])
        case 4:
            var rays: [Path] = [GK.arc(0.58, 0.5, 0.18, from: 0, to: 360, width: 0.07), GK.rect(0.04, 0.42, 0.18, 0.16, corner: 0.04)]
            for k in 0..<8 {
                let a = Double(k) * .pi / 4
                rays.append(GK.line([(0.58 + cos(a) * 0.27, 0.5 + sin(a) * 0.27), (0.58 + cos(a) * 0.38, 0.5 + sin(a) * 0.38)], width: 0.05))
            }
            return GK.union(rays)
        default:
            return GK.union([emitter(), GK.line([(0.3, 0.5), (0.48, 0.3), (0.6, 0.66), (0.74, 0.34), (0.92, 0.5)], width: 0.07, round: false)])
        }
    }

    private static func shield(_ i: Int) -> Path {
        typealias GK = GlyphKit
        let round = i == 0
        let outer = GK.arc(0.5, 0.62, 0.38, from: 200, to: 340, width: 0.08, round: round)
        let inner = GK.arc(0.5, 0.62, 0.22, from: 205, to: 335, width: 0.08, round: round)
        var parts = [outer, inner, GK.circle(0.5, 0.62, 0.07)]
        switch i {
        case 1:
            parts.append(GK.line([(0.12, 0.2), (0.28, 0.32), (0.12, 0.44)], width: 0.05))
            parts.append(GK.line([(0.88, 0.2), (0.72, 0.32), (0.88, 0.44)], width: 0.05))
        case 2:
            parts.append(GK.line([(0.5, 0.04), (0.42, 0.16), (0.56, 0.2), (0.48, 0.32)], width: 0.05, round: false))
            parts.append(GK.line([(0.86, 0.5), (0.94, 0.66), (0.82, 0.72), (0.9, 0.88)], width: 0.04, round: false))
            parts.append(GK.line([(0.14, 0.5), (0.06, 0.66), (0.18, 0.72), (0.1, 0.88)], width: 0.04, round: false))
        default: break
        }
        return GK.union(parts)
    }

    private static func gadget(_ i: Int) -> Path {
        typealias GK = GlyphKit
        switch i {
        case 0:
            return GK.union([GK.rect(0.14, 0.52, 0.34, 0.34, corner: 0.04), GK.rect(0.52, 0.52, 0.34, 0.34, corner: 0.04),
                            GK.rect(0.33, 0.14, 0.34, 0.34, corner: 0.04)])
                .union(GK.line([(0.5, 0.2), (0.5, 0.42)], width: 0.05)).subtracting(GK.line([(0.5, 0.22), (0.5, 0.4)], width: 0.03))
        case 1:
            let wrench = GK.union([GK.line([(0.26, 0.74), (0.62, 0.38)], width: 0.12), GK.circle(0.68, 0.32, 0.17)])
            return wrench.subtracting(GK.rotated(GK.rect(0.64, 0.12, 0.1, 0.22), degrees: 45, about: CGPoint(x: 0.69, y: 0.23)))
        case 2:
            return GK.arc(0.5, 0.5, 0.4, from: 0, to: 360, width: 0.06)
                .union(ArtGeometry.star(center: CGPoint(x: 0.5, y: 0.5), points: 4, outer: 0.32, inner: 0.08))
        case 3:
            return GK.union([GK.arc(0.5, 0.5, 0.3, from: 0, to: 360, width: 0.07), GK.line([(0.5, 0.06), (0.5, 0.32)], width: 0.06),
                            GK.line([(0.5, 0.68), (0.5, 0.94)], width: 0.06), GK.line([(0.06, 0.5), (0.32, 0.5)], width: 0.06),
                            GK.line([(0.68, 0.5), (0.94, 0.5)], width: 0.06), GK.circle(0.5, 0.5, 0.06)])
        case 4:
            let eye = ArtGeometry.closedSpline([SplinePoint(0.06, 0.5, sharp: true), SplinePoint(0.5, 0.22), SplinePoint(0.94, 0.5, sharp: true),
                                                SplinePoint(0.5, 0.78)])
            return eye.subtracting(GK.circle(0.5, 0.5, 0.16)).subtracting(GK.line([(0.12, 0.88), (0.88, 0.12)], width: 0.1))
                .union(GK.line([(0.16, 0.84), (0.84, 0.16)], width: 0.05))
        case 5:
            let drop = ArtGeometry.closedSpline([SplinePoint(0.5, 0.2, sharp: true), SplinePoint(0.64, 0.46), SplinePoint(0.5, 0.64),
                                                 SplinePoint(0.36, 0.46)])
            return GK.union([drop, GK.line([(0.1, 0.12), (0.22, 0.24)], width: 0.06), GK.line([(0.9, 0.12), (0.78, 0.24)], width: 0.06),
                            GK.line([(0.1, 0.88), (0.22, 0.76)], width: 0.06), GK.line([(0.9, 0.88), (0.78, 0.76)], width: 0.06),
                            GK.rect(0.26, 0.72, 0.48, 0.08, corner: 0.03)])
        default:
            let box = GK.rect(0.14, 0.3, 0.72, 0.56, corner: 0.05).subtracting(GK.rect(0.22, 0.38, 0.56, 0.4))
            var dashes = [box]
            for k in 0..<4 { dashes.append(GK.rect(0.22 + Double(k) * 0.15, 0.56, 0.09, 0.06)) }
            dashes.append(GK.rect(0.3, 0.14, 0.4, 0.1, corner: 0.03))
            return GK.union(dashes)
        }
    }
}
