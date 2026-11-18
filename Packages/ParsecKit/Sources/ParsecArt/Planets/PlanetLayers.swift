// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// The vector overlays around the sphere: the built orbital ring and satellites of the tech layers (ART-022), the
/// government motif (ART-023) and the Increase Contrast rim (ART-026).
enum PlanetLayers {
    /// The k-th seeded point inside the unit disk (polar, uniform by area).
    static func mark(_ rc: PlanetRecipe, _ k: Int, c: CGPoint, r: Double) -> CGPoint {
        let a = rc.marks[(2 * k) % rc.marks.count] * 2 * .pi
        let d = rc.marks[(2 * k + 1) % rc.marks.count].squareRoot() * 0.92
        return CGPoint(x: c.x + cos(a) * d * r, y: c.y + sin(a) * d * r)
    }

    static func dot(_ p: CGPoint, _ size: Double) -> CGRect {
        CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)
    }

    /// The night side of the disk for the projector's light: the half away from the light minus the terminator ellipse.
    static func nightPath(c: CGPoint, r: Double) -> Path {
        let l = PlanetSphere.lightDirection
        let away = atan2(Double(l.y), Double(-l.x))
        var half = Path()
        half.move(to: CGPoint(x: 0, y: -r))
        half.addArc(center: .zero, radius: r, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
        half.closeSubpath()
        let lit = Path(ellipseIn: CGRect(x: -r * Double(l.z), y: -r, width: 2 * r * Double(l.z), height: 2 * r))
        return half.subtracting(lit).applying(CGAffineTransform(translationX: c.x, y: c.y).rotated(by: away))
    }

    static func behind(_ ctx: inout GraphicsContext, rc: PlanetRecipe, c: CGPoint, r: Double, ink: ArtInk) {
        if rc.motif == .halo {
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 1.25, y: c.y - r * 1.25, width: 2.5 * r, height: 2.5 * r)),
                     with: .radialGradient(Gradient(colors: [ink.rgb(.brass).opacity(0.32).color, ink.rgb(.brass).opacity(0).color]),
                                           center: c, startRadius: r * 0.95, endRadius: r * 1.25))
        }
        orbitalRing(&ctx, rc: rc, c: c, r: r, front: false, ink: ink)
    }

    static func front(_ ctx: inout GraphicsContext, rc: PlanetRecipe, c: CGPoint, r: Double, phase: Double, a11y: ArtAccessibility,
                      ink: ArtInk) {
        let disk = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        if rc.motif == .grid { grid(&ctx, c: c, r: r, ink: ink) }
        if a11y.increaseContrast {
            ctx.stroke(disk, with: .color(ink.rgb(.outline).color), lineWidth: max(0.8, r * 0.03) * a11y.outlineScale)
            ctx.stroke(nightPath(c: c, r: r), with: .color(.black.opacity(0.6)), lineWidth: 1)
        }
        orbitalRing(&ctx, rc: rc, c: c, r: r, front: true, ink: ink)
        satellites(&ctx, rc: rc, c: c, r: r, phase: phase, ink: ink)
        motif(&ctx, rc: rc, c: c, r: r, phase: phase, a11y: a11y, ink: ink)
    }

    /// ART-023: a faint lattice on the night side.
    static func grid(_ ctx: inout GraphicsContext, c: CGPoint, r: Double, ink: ArtInk) {
        var n = ctx
        n.clip(to: nightPath(c: c, r: r))
        var g = Path()
        for k in -7...7 {
            let o = Double(k) * r * 0.13
            g.move(to: CGPoint(x: c.x + o - r, y: c.y - r))
            g.addLine(to: CGPoint(x: c.x + o + r, y: c.y + r))
            g.move(to: CGPoint(x: c.x + o + r, y: c.y - r))
            g.addLine(to: CGPoint(x: c.x + o - r, y: c.y + r))
        }
        n.stroke(g, with: .color(ink.rgb(.visited).opacity(0.22).color), lineWidth: max(0.4, r * 0.005))
    }

    /// ART-022: the built orbital ring: a thin lit structure in the planet's equatorial plane.
    static func orbitalRing(_ ctx: inout GraphicsContext, rc: PlanetRecipe, c: CGPoint, r: Double, front: Bool, ink: ArtInk) {
        let kind = rc.style.ring
        guard kind != .none else { return }
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .degrees(-rc.tilt))
        let a = r * 1.22, b = a * max(0.12, sin(rc.inclination * .pi / 180))
        // The front half is the lower half of the ellipse (the north pole tips towards the viewer).
        let span: Double = kind == .full ? 180 : 110
        let start: Double = front ? 0 : 180
        var arc = Path()
        arc.addArc(center: .zero, radius: 1, startAngle: .degrees(start + (180 - span) / 2), endAngle: .degrees(start + (180 + span) / 2),
                   clockwise: false)
        let scaled = arc.applying(CGAffineTransform(scaleX: a, y: b))
        let dim = front ? 1.0 : 0.55
        g.stroke(scaled, with: .color(ink.rgb(.steel).shade(0.7).opacity(dim).color), style: StrokeStyle(lineWidth: max(0.8, r * 0.022)))
        g.stroke(scaled, with: .color(ink.rgb(.metal).opacity(dim).color), style: StrokeStyle(lineWidth: max(0.4, r * 0.008)))
        let lights = kind == .full ? 9 : 5
        var dots = Path()
        for k in 0..<lights {
            let t = (start + (180 - span) / 2 + span * (Double(k) + 0.5) / Double(lights)) * .pi / 180
            dots.addEllipse(in: dot(CGPoint(x: cos(t) * a, y: sin(t) * b), max(0.8, r * 0.02)))
        }
        g.fill(dots, with: .color(ink.rgb(.cityLight).opacity(dim).color))
    }

    static func satellites(_ ctx: inout GraphicsContext, rc: PlanetRecipe, c: CGPoint, r: Double, phase: Double, ink: ArtInk) {
        guard rc.style.satellites > 0 else { return }
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .degrees(-rc.tilt))
        let a = r * 1.36, b = a * max(0.12, sin(rc.inclination * .pi / 180))
        for k in 0..<rc.style.satellites {
            let t = phase * 2 * .pi / 20 + Double(k) * .pi + rc.marks[k] * 2 * .pi
            let p = CGPoint(x: cos(t) * a, y: sin(t) * b)
            // Behind the planet on the far half of its orbit.
            if sin(t) < 0, hypot(p.x, p.y) < r { continue }
            let s = max(1.6, r * 0.05)
            g.fill(Path(CGRect(x: p.x - s * 1.4, y: p.y - s * 0.16, width: s * 2.8, height: s * 0.32)), with: .color(ink(.slateBlue)))
            g.fill(Path(ellipseIn: dot(p, s)), with: .color(ink(.metal)))
        }
    }

    static func motif(_ ctx: inout GraphicsContext, rc: PlanetRecipe, c: CGPoint, r: Double, phase: Double, a11y: ArtAccessibility, ink: ArtInk) {
        switch rc.motif {
        case .none, .grid, .halo: return
        case .debrisField:
            for k in 0..<14 {
                let a = rc.marks[k + 30] * 2 * .pi, d = r * (1.12 + 0.2 * rc.marks[k + 50])
                let p = ArtGeometry.polar(c, d, a)
                let s = max(0.8, r * (0.018 + 0.02 * rc.marks[k + 70]))
                var shard = Path()
                shard.move(to: CGPoint(x: p.x - s, y: p.y - s * 0.5))
                shard.addLine(to: CGPoint(x: p.x + s * 0.8, y: p.y - s * 0.8))
                shard.addLine(to: CGPoint(x: p.x + s, y: p.y + s * 0.6))
                shard.addLine(to: CGPoint(x: p.x - s * 0.6, y: p.y + s * 0.7))
                shard.closeSubpath()
                ctx.fill(shard, with: .color(ink.rgb(.steel).shade(0.6 + 0.6 * rc.marks[k + 90]).color))
            }
        case .defensePlatforms:
            for k in 0..<3 {
                let p = ArtGeometry.polar(c, r * 1.22, -2.4 + Double(k) * 0.9)
                let s = max(2, r * 0.07)
                ctx.fill(Path(CGRect(x: p.x - s, y: p.y - s * 0.1, width: 2 * s, height: s * 0.2)), with: .color(ink(.slate)))
                ctx.fill(Path(roundedRect: CGRect(x: p.x - s * 0.4, y: p.y - s * 0.4, width: s * 0.8, height: s * 0.8), cornerRadius: s * 0.15),
                         with: .linearGradient(Gradient(colors: [ink(.metal), ink(.steel)]), startPoint: CGPoint(x: p.x - s, y: p.y - s),
                                               endPoint: CGPoint(x: p.x + s, y: p.y + s)))
            }
        case .beacons:
            for k in 0..<4 {
                let blink = a11y.reduceMotion ? 1 : 0.5 + 0.5 * sin(phase * .pi * 0.8 + Double(k))
                let p = ArtGeometry.polar(c, r * 1.12, -.pi / 4 + Double(k) * .pi / 2)
                let s = max(2, r * 0.05)
                ctx.fill(Path(ellipseIn: dot(p, s * 2.6)),
                         with: .radialGradient(Gradient(colors: [ink.rgb(.brass).opacity(0.55 * blink).color, ink.rgb(.brass).opacity(0).color]),
                                               center: p, startRadius: 0, endRadius: s * 1.3))
                ctx.fill(Path(ellipseIn: dot(p, s * 0.7)), with: .color(ink.rgb(.brass).opacity(0.4 + 0.6 * blink).color))
            }
        }
    }
}
