// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// Helpers for template glyphs drawn in a unit square and scaled into a rect.
enum GlyphKit {
    static func fit(_ unitPath: Path, in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        return unitPath.applying(CGAffineTransform(a: side, b: 0, c: 0, d: side, tx: origin.x, ty: origin.y))
    }

    static func circle(_ x: Double, _ y: Double, _ r: Double) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }

    static func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, corner: Double = 0) -> Path {
        corner > 0 ? Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: corner) : Path(CGRect(x: x, y: y, width: w, height: h))
    }

    static func line(_ points: [(Double, Double)], width: Double, round: Bool = true) -> Path {
        var p = Path()
        guard let f = points.first else { return p }
        p.move(to: CGPoint(x: f.0, y: f.1))
        for q in points.dropFirst() { p.addLine(to: CGPoint(x: q.0, y: q.1)) }
        return ArtGeometry.stroke(p, width: width, round: round)
    }

    static func arc(_ x: Double, _ y: Double, _ r: Double, from a: Double, to b: Double, width: Double, round: Bool = true) -> Path {
        var p = Path()
        p.addArc(center: CGPoint(x: x, y: y), radius: r, startAngle: .degrees(a), endAngle: .degrees(b), clockwise: false)
        return ArtGeometry.stroke(p, width: width, round: round)
    }

    static func union(_ paths: [Path]) -> Path {
        paths.dropFirst().reduce(paths.first ?? Path()) { $0.union($1) }
    }

    static func poly(_ points: [(Double, Double)]) -> Path {
        ArtGeometry.polygon(points.map { CGPoint(x: $0.0, y: $0.1) })
    }

    static func rotated(_ path: Path, degrees: Double, about c: CGPoint = CGPoint(x: 0.5, y: 0.5)) -> Path {
        path.applying(CGAffineTransform(translationX: -c.x, y: -c.y).concatenating(CGAffineTransform(rotationAngle: degrees * .pi / 180))
            .concatenating(CGAffineTransform(translationX: c.x, y: c.y)))
    }
}
