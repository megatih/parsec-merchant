// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// The style, resource, pressure and government layers of a planet (ART-022…025).
enum PlanetLayers {
    /// The k-th seeded point inside the unit disk (polar, uniform by area).
    static func mark(_ rc: PlanetRecipe, _ k: Int, c: CGPoint, r: Double) -> CGPoint {
        let a = rc.marks[(2 * k) % rc.marks.count] * 2 * .pi
        let d = rc.marks[(2 * k + 1) % rc.marks.count].squareRoot() * 0.92
        return CGPoint(x: c.x + cos(a) * d * r, y: c.y + sin(a) * d * r)
    }

    /// Whether `p` is on the lit half (upper left of the terminator).
    static func isDay(_ p: CGPoint, c: CGPoint, r: Double) -> Bool {
        (p.x - c.x) + (p.y - c.y) < r * 0.15
    }

    static func dot(_ p: CGPoint, _ size: Double) -> CGRect {
        CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)
    }

    // MARK: Surface (tilted context, clipped to the disk)

    static func surfaceDetails(_ ctx: inout GraphicsContext, rc: PlanetRecipe, land: Path, c: CGPoint, r: Double, shift: Double, ink: ArtInk) {
        var onLand = ctx
        onLand.clip(to: land)
        let landColor = ink.rgb(rc.land)
        if rc.style == .agricultural || rc.style == .medieval {
            var a = Path(), b = Path()
            let step = r * 0.16
            var y = c.y - r, row = 0
            while y < c.y + r {
                var x = c.x - r + Double(row % 2) * step * 0.5, col = 0
                while x < c.x + r {
                    let cell = CGRect(x: x, y: y, width: step * 0.9, height: step * 0.9)
                    if (row + col).isMultiple(of: 2) { a.addRect(cell) } else { b.addRect(cell) }
                    x += step
                    col += 1
                }
                y += step
                row += 1
            }
            onLand.fill(a, with: .color(landColor.shade(1.18).color))
            onLand.fill(b, with: .color(landColor.shade(0.86).color))
        }
        if let patch = rc.patches {
            var p = Path()
            for k in 0..<14 { p.addEllipse(in: dot(mark(rc, k + 40, c: c, r: r), r * (patch == .metal ? 0.06 : 0.16))) }
            onLand.fill(p, with: .color(ink.rgb(patch).color))
        }
        if rc.pressure == .cropFailure {
            var p = Path()
            for k in 0..<10 { p.addEllipse(in: dot(mark(rc, k + 60, c: c, r: r), r * 0.2)) }
            onLand.fill(p, with: .color(ink.rgb(.landBrown).shade(0.8).color))
        }
        if rc.craters > 0 {
            for k in 0..<rc.craters {
                let rect = dot(mark(rc, k + 20, c: c, r: r), r * (0.1 + 0.08 * rc.marks[k % rc.marks.count]))
                ctx.fill(Path(ellipseIn: rect), with: .color(ink.rgb(.landGrey).shade(0.75).color))
                ctx.stroke(Path(ellipseIn: rect), with: .color(ink.rgb(.landGrey).shade(1.25).color), lineWidth: max(0.5, r * 0.012))
            }
        }
        let dots = rc.style.dayDots
        guard dots > 0 else { return }
        var settlements = Path()
        var points: [CGPoint] = []
        for k in 0..<(dots * 3) where points.count < dots {
            let p = mark(rc, k, c: c, r: r)
            if isDay(p, c: c, r: r) { points.append(p) }
        }
        for p in points { settlements.addEllipse(in: dot(p, max(1, r * 0.035))) }
        onLand.fill(settlements, with: .color(ink.rgb(.ivory).color))
        if rc.style.rawValue >= PlanetStyle.renaissance.rawValue {
            var canals = Path()
            for (a, b) in zip(points, points.dropFirst()) {
                canals.move(to: a)
                canals.addLine(to: b)
            }
            onLand.stroke(canals, with: .color(ink.rgb(.ocean).shade(1.2).opacity(0.8).color), lineWidth: max(0.5, r * 0.012))
        }
    }

    static func iceCaps(_ ctx: inout GraphicsContext, rc: PlanetRecipe, c: CGPoint, r: Double, ink: ArtInk) {
        guard rc.iceCap > 0 else { return }
        let h = rc.iceCap * 2 * r
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.7, y: c.y - r - h * 0.4, width: 1.4 * r, height: h * 1.4)), with: .color(ink(.ice)))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.6, y: c.y + r - h, width: 1.2 * r, height: h * 1.4)), with: .color(ink(.ice)))
    }

    static func clouds(_ ctx: inout GraphicsContext, rc: PlanetRecipe, c: CGPoint, r: Double, phase: Double, a11y: ArtAccessibility,
                       ink: ArtInk) {
        guard !rc.clouds.isEmpty else { return }
        let drift = phase / PlanetRenderer.rotationPeriod
        var cloud = ink.rgb(.cloud)
        if a11y.reduceTransparency { cloud = ArtRGB(0.93, 0.95, 0.98) }
        for band in rc.clouds {
            var p = Path()
            let y = c.y - r + band.v * 2 * r, t = band.thickness * 2 * r
            let steps = 24
            var top: [CGPoint] = [], bottom: [CGPoint] = []
            for i in 0...steps {
                let fx = Double(i) / Double(steps)
                let x = c.x - r + fx * 2 * r
                let w = sin((fx + band.offset + drift) * 2 * .pi * 2) * band.wave * 2 * r
                top.append(CGPoint(x: x, y: y - t / 2 + w))
                bottom.append(CGPoint(x: x, y: y + t / 2 + w * 0.6))
            }
            p = ArtGeometry.polygon(top + bottom.reversed())
            ctx.fill(p, with: .color(cloud.opacity(a11y.reduceTransparency ? 1 : 0.8).color))
        }
    }

    // MARK: Night side, haze, pressure

    static func nightSide(_ ctx: inout GraphicsContext, rc: PlanetRecipe, night: Path, lights: [CGPoint], c: CGPoint, r: Double, ink: ArtInk) {
        var n = ctx
        n.clip(to: night)
        if rc.motif == .grid {
            var g = Path()
            for k in -4...4 {
                let o = Double(k) * r * 0.22
                g.move(to: CGPoint(x: c.x + o - r, y: c.y - r))
                g.addLine(to: CGPoint(x: c.x + o + r, y: c.y + r))
                g.move(to: CGPoint(x: c.x + o + r, y: c.y - r))
                g.addLine(to: CGPoint(x: c.x + o - r, y: c.y + r))
            }
            n.stroke(g, with: .color(ink.rgb(.visited).opacity(0.55).color), lineWidth: max(0.5, r * 0.01))
        }
        guard !lights.isEmpty else { return }
        if rc.style == .hiTech {
            var net = Path()
            for (a, b) in zip(lights, lights.dropFirst()) where hypot(a.x - b.x, a.y - b.y) < r * 0.5 {
                net.move(to: a)
                net.addLine(to: b)
            }
            n.stroke(net, with: .color(ink.rgb(.cityLight).opacity(0.6).color), lineWidth: max(0.5, r * 0.01))
        }
        var dots = Path()
        for p in lights { dots.addEllipse(in: dot(p, max(1, r * 0.03))) }
        n.fill(dots, with: .color(ink(.cityLight)))
    }

    /// ART-022: the city lights; only points on the night side of the terminator.
    static func lightPoints(_ rc: PlanetRecipe, night: Path, c: CGPoint, r: Double) -> [CGPoint] {
        let count = rc.style.nightLights
        var lights: [CGPoint] = []
        for k in 0..<(count * 4) where lights.count < count {
            let p = mark(rc, k + 70, c: c, r: r)
            if night.contains(p) { lights.append(p) }
        }
        return lights
    }

    static func haze(_ ctx: inout GraphicsContext, rc: PlanetRecipe, disk: Path, ink: ArtInk) {
        switch rc.style {
        case .earlyIndustrial: ctx.fill(disk, with: .color(ink.rgb(.haze).opacity(0.5).color))
        case .industrial: ctx.fill(disk, with: .color(ArtRGB(0.55, 0.55, 0.55, 0.22).color))
        default: break
        }
    }

    static func pressure(_ ctx: inout GraphicsContext, rc: PlanetRecipe, disk: Path, c: CGPoint, r: Double, rawPhase: Double,
                         a11y: ArtAccessibility, ink: ArtInk) {
        guard let p = rc.pressure else { return }
        switch p {
        case .war:
            var smoke = Path()
            for k in 0..<5 { smoke.addEllipse(in: dot(mark(rc, k + 90, c: c, r: r), r * 0.28)) }
            var s = ctx
            s.clip(to: disk)
            s.fill(smoke, with: .color(ink(.smoke)))
            for k in 0..<6 {
                let flash = a11y.reduceMotion ? 1 : 0.55 + 0.45 * sin(rawPhase * 7 + Double(k) * 1.7)
                let pt = mark(rc, k + 100, c: c, r: r)
                s.fill(ArtGeometry.star(center: pt, points: 5, outer: r * 0.07, inner: r * 0.03), with: .color(ink.rgb(.fire).opacity(flash).color))
            }
        case .plague: ctx.fill(disk, with: .color(ink(.plague)))
        case .drought: ctx.fill(disk, with: .color(ink.rgb(.landSand).opacity(0.18).color))
        case .none, .boredom, .cold, .cropFailure, .employment: break
        }
    }

    // MARK: Ring, satellites, motifs

    static func ring(_ ctx: inout GraphicsContext, rc: PlanetRecipe, c: CGPoint, r: Double, front: Bool, ink: ArtInk) {
        let kind = rc.style.ring
        guard kind != .none else { return }
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .degrees(rc.tilt * 0.6 - 12))
        let rect = CGRect(x: -r * 1.5, y: -r * 0.34, width: 3 * r, height: r * 0.68)
        var arc = Path()
        // Front half is the lower half of the ellipse.
        let span: Double = kind == .full ? 180 : 110
        let start: Double = front ? 0 : 180
        arc.addArc(center: .zero, radius: 1, startAngle: .degrees(start + (180 - span) / 2), endAngle: .degrees(start + (180 + span) / 2),
                   clockwise: false)
        let scaled = arc.applying(CGAffineTransform(scaleX: rect.width / 2, y: rect.height / 2))
        g.stroke(scaled, with: .color(ink(.ring)), style: StrokeStyle(lineWidth: max(1, r * 0.09), lineCap: .butt))
        g.stroke(scaled, with: .color(ink.rgb(.ring).shade(0.7).color), style: StrokeStyle(lineWidth: max(0.5, r * 0.02)))
    }

    static func satellites(_ ctx: inout GraphicsContext, rc: PlanetRecipe, c: CGPoint, r: Double, phase: Double, ink: ArtInk) {
        for k in 0..<rc.style.satellites {
            let a = phase * 2 * .pi / 20 + Double(k) * .pi + rc.marks[k]
            let p = CGPoint(x: c.x + cos(a) * r * 1.35, y: c.y + sin(a) * r * 0.5)
            ctx.fill(Path(ellipseIn: dot(p, max(2, r * 0.1))), with: .color(ink(.metal)))
        }
    }

    static func motif(_ ctx: inout GraphicsContext, rc: PlanetRecipe, c: CGPoint, r: Double, phase: Double, a11y: ArtAccessibility, ink: ArtInk) {
        switch rc.motif {
        case .none, .grid, .halo: return
        case .debrisField:
            for k in 0..<14 {
                let a = rc.marks[k + 30] * 2 * .pi, d = r * (1.12 + 0.2 * rc.marks[k + 50])
                let p = ArtGeometry.polar(c, d, a)
                ctx.fill(ArtGeometry.star(center: p, points: 3, outer: max(1, r * 0.045), inner: max(0.5, r * 0.02), rotation: a),
                         with: .color(ink(.steel)))
            }
        case .defensePlatforms:
            for k in 0..<3 {
                let p = ArtGeometry.polar(c, r * 1.22, -2.4 + Double(k) * 0.9)
                let s = max(2, r * 0.09)
                ctx.fill(Path(CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s)), with: .color(ink(.steel)))
                ctx.fill(Path(CGRect(x: p.x - s, y: p.y - s * 0.12, width: 2 * s, height: s * 0.24)), with: .color(ink(.slate)))
            }
        case .beacons:
            for k in 0..<4 {
                let blink = a11y.reduceMotion ? 1 : 0.5 + 0.5 * sin(phase * 3 + Double(k))
                let p = ArtGeometry.polar(c, r * 1.12, -.pi / 4 + Double(k) * .pi / 2)
                ctx.fill(Path(ellipseIn: dot(p, max(2, r * 0.07))), with: .color(ink.rgb(.brass).opacity(0.4 + 0.6 * blink).color))
            }
        }
    }
}
