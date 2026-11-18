// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// Where the two ships are, in the layer's coordinate space.
public struct CombatGeometry: Sendable, Hashable {
    public var player: CGRect
    public var opponent: CGRect

    public init(player: CGRect, opponent: CGRect) {
        self.player = player
        self.opponent = opponent
    }

    public func rect(_ side: CombatSide) -> CGRect { side == .player ? player : opponent }

    /// ART-083: a beam leaves the firing ship's nose (the edge of its box that faces the target) and ends at the centre of
    /// the target's box; a miss passes above the target.
    public func beamEndpoints(from: CombatSide, hit: Bool) -> (start: CGPoint, end: CGPoint) {
        let src = rect(from), dst = rect(from.other)
        let a = CGPoint(x: from == .player ? src.maxX : src.minX, y: src.midY)
        var b = CGPoint(x: dst.midX, y: dst.midY)
        if !hit { b = CGPoint(x: b.x + (b.x - a.x) * 0.25, y: dst.minY - dst.height * 0.1) }
        return (a, b)
    }

    /// Two panes side by side in a frame of `size` (the ship boxes take the middle of each half).
    public static func sideBySide(_ size: CGSize) -> CombatGeometry {
        let w = size.width / 2
        return CombatGeometry(player: CGRect(x: w * 0.15, y: size.height * 0.2, width: w * 0.7, height: size.height * 0.6),
                              opponent: CGRect(x: w + w * 0.15, y: size.height * 0.2, width: w * 0.7, height: size.height * 0.6))
    }
}

/// ART-042…047: draws the effects of a plan at `phase` seconds over the two ship panes.
public struct CombatEffectsLayer: View {
    public var effects: [CombatEffect]
    public var phase: Double
    public var geometry: CombatGeometry?
    @Environment(\.colorScheme) private var scheme

    public init(effects: [CombatEffect], phase: Double, geometry: CombatGeometry? = nil) {
        self.effects = effects
        self.phase = phase
        self.geometry = geometry
    }

    public var body: some View {
        let effects = effects, t = phase, fixed = geometry, ink = ArtInk(scheme: scheme, contrast: false)
        Canvas { ctx, size in
            let g = fixed ?? CombatGeometry.sideBySide(size)
            for e in effects where t >= e.start && t <= e.end + (e.isFlash ? CombatTiming.symbolHold : 0) {
                let u = e.duration > 0 ? min(1, max(0, (t - e.start) / e.duration)) : 1
                CombatEffectRenderer.draw(&ctx, effect: e, u: u, t: t, geometry: g, ink: ink)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

enum CombatEffectRenderer {
    static func beamColor(_ kind: BeamKind) -> ArtRGB {
        switch kind {
        case .pulse: ArtRGB(1, 0.2, 0.15)
        case .beam: ArtRGB(1, 0.55, 0.1)
        case .military: ArtRGB(0.75, 0.85, 1)
        case .morgans: ArtRGB(0.7, 0.3, 1)
        case .photon: ArtRGB(0.2, 0.9, 1)
        case .quantum: ArtRGB(1, 0.2, 0.85)
        }
    }

    static func center(_ r: CGRect) -> CGPoint { CGPoint(x: r.midX, y: r.midY) }

    static func draw(_ ctx: inout GraphicsContext, effect e: CombatEffect, u: Double, t: Double, geometry g: CombatGeometry, ink: ArtInk) {
        switch e.kind {
        case let .beam(from, weapon, hit): beam(&ctx, from: from, weapon: weapon, hit: hit, u: u, g: g)
        case let .shieldRipple(on, kind): ripple(&ctx, on: on, kind: kind, u: u, g: g, ink: ink)
        case let .sparks(on, count): sparks(&ctx, on: on, count: count, u: u, seed: e.seed, g: g, ink: ink)
        case .shake:
            let r = g.player.insetBy(dx: -8, dy: -8)
            var lines = Path()
            for k in 0..<4 {
                let y = r.minY + r.height * (0.2 + 0.2 * Double(k))
                lines.move(to: CGPoint(x: r.minX - 6, y: y))
                lines.addLine(to: CGPoint(x: r.minX + 6, y: y))
            }
            ctx.stroke(lines, with: .color(.white.opacity(0.6 * (1 - u))), lineWidth: 2)
        case let .explosion(on): explosion(&ctx, rect: g.rect(on), u: u, seed: e.seed, ink: ink)
        case let .powerDown(on):
            let r = g.rect(on)
            ctx.fill(Path(roundedRect: r, cornerRadius: 6), with: .color(.gray.opacity(0.25 * u)))
            for (fx, fy) in [(0.35, 0.35), (0.65, 0.6)] {
                let c = CGPoint(x: r.minX + r.width * fx, y: r.minY + r.height * fy)
                let s = max(3, r.height * 0.12) * u
                ctx.fill(ArtGeometry.star(center: c, points: 4, outer: s, inner: s * 0.25), with: .color(ink.rgb(.spark).opacity(u).color))
            }
        case let .escape(side):
            let r = g.rect(side)
            let dir: Double = side == .player ? -1 : 1
            let tail = CGPoint(x: dir > 0 ? r.minX : r.maxX, y: r.midY)
            var flare = Path()
            flare.move(to: tail)
            flare.addLine(to: CGPoint(x: tail.x - dir * r.width * (0.3 + 0.7 * u), y: r.midY))
            ctx.stroke(flare, with: .color(ink.rgb(.engineGlow).opacity(1 - u * 0.6).color),
                       style: StrokeStyle(lineWidth: max(2, r.height * 0.1), lineCap: .round))
        case let .arrive(side):
            let r = g.rect(side)
            var trail = Path()
            for k in 0..<3 {
                let y = r.minY + r.height * (0.35 + 0.15 * Double(k))
                trail.move(to: CGPoint(x: r.maxX, y: y))
                trail.addLine(to: CGPoint(x: r.maxX + r.width * 0.4 * (1 - u), y: y))
            }
            ctx.stroke(trail, with: .color(.white.opacity(0.5 * (1 - u))), lineWidth: 1.5)
        case let .flash(on, tone): flash(&ctx, on: on, tone: tone, t: t, start: e.start, g: g, ink: ink)
        }
    }

    static func beam(_ ctx: inout GraphicsContext, from: CombatSide, weapon: BeamKind, hit: Bool, u: Double, g: CombatGeometry) {
        let (a, b) = g.beamEndpoints(from: from, hit: hit)
        let travel = min(1, u / (CombatTiming.land / CombatTiming.beam))
        let head = CGPoint(x: a.x + (b.x - a.x) * travel, y: a.y + (b.y - a.y) * travel)
        let fade = u < 0.6 ? 1 : max(0, 1 - (u - 0.6) / 0.4)
        let c = beamColor(weapon).opacity(fade * (hit ? 1 : 0.6))
        var line = Path()
        line.move(to: a)
        line.addLine(to: head)
        switch weapon {
        case .pulse:
            ctx.stroke(line, with: .color(c.color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [8, 6], dashPhase: -u * 40))
        case .beam:
            ctx.stroke(line, with: .color(c.color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        case .military:
            ctx.stroke(line, with: .color(c.color), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            ctx.stroke(line, with: .color(ArtRGB(1, 1, 1, fade).color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        case .morgans:
            ctx.stroke(line, with: .color(c.color), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            ctx.stroke(line, with: .color(ArtRGB(1, 0.92, 1, fade).color), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        case .photon:
            let p = CGPoint(x: a.x + (b.x - a.x) * min(1, u * 1.4), y: a.y + (b.y - a.y) * min(1, u * 1.4))
            let r = 4 + 10 * u
            ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(c.color), lineWidth: 2.5)
        case .quantum:
            var bolt = Path()
            bolt.move(to: a)
            for k in 1...6 {
                let f = Double(k) / 6 * travel
                let off: Double = k == 6 ? 0 : (k.isMultiple(of: 2) ? 7 : -7)
                bolt.addLine(to: CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f + off))
            }
            ctx.stroke(bolt, with: .color(c.color), style: StrokeStyle(lineWidth: 2.5, lineJoin: .miter))
        }
    }

    static func ripple(_ ctx: inout GraphicsContext, on: CombatSide, kind: ShieldDisplay.Kind, u: Double, g: CombatGeometry, ink: ArtInk) {
        let r = g.rect(on)
        let token: ArtToken = switch kind {
        case .energy: .shieldEnergy
        case .reflective: .shieldReflective
        case .lightning: .shieldLightning
        }
        let impact = CGPoint(x: on == .player ? r.maxX + r.width * 0.06 : r.minX - r.width * 0.06, y: r.midY)
        let start: Double = on == .player ? -60 : 120
        for k in 0..<3 {
            let rad = (6 + Double(k) * 7) * (0.4 + u)
            var arc = Path()
            arc.addArc(center: impact, radius: rad, startAngle: .degrees(start), endAngle: .degrees(start + 120), clockwise: false)
            ctx.stroke(arc, with: .color(ink.rgb(token).opacity((1 - u) * (1 - Double(k) * 0.25)).color), lineWidth: 2)
        }
    }

    static func sparks(_ ctx: inout GraphicsContext, on: CombatSide, count: Int, u: Double, seed: Int, g: CombatGeometry, ink: ArtInk) {
        let r = g.rect(on)
        var rng = ArtRandom(seed: ArtSeed.of(seed, on == .player ? 1 : 2))
        var streaks = Path()
        for _ in 0..<max(1, count) {
            let c = CGPoint(x: r.minX + r.width * rng.range(0.25...0.75), y: r.minY + r.height * rng.range(0.3...0.7))
            let a = rng.unit() * 2 * .pi
            let len = (4 + 10 * rng.unit()) * (0.3 + u)
            streaks.move(to: ArtGeometry.polar(c, len * 0.3, a))
            streaks.addLine(to: ArtGeometry.polar(c, len, a))
        }
        ctx.stroke(streaks, with: .color(ink.rgb(.spark).opacity(1 - u * 0.8).color), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
    }

    static func explosion(_ ctx: inout GraphicsContext, rect r: CGRect, u: Double, seed: Int, ink: ArtInk) {
        let c = center(r)
        let ring = max(r.width, r.height) * 0.7 * u
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - ring, y: c.y - ring, width: 2 * ring, height: 2 * ring)),
                   with: .color(ink.rgb(.engineGlow).opacity(1 - u).color), lineWidth: 3)
        let core = max(r.width, r.height) * 0.35 * (u < 0.3 ? u / 0.3 : 1 - (u - 0.3) / 0.7)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - core, y: c.y - core, width: 2 * core, height: 2 * core)), with: .color(.white.opacity(0.9)))
        var rng = ArtRandom(seed: ArtSeed.of(seed, 0xDEB))
        for _ in 0..<10 {
            let a = rng.unit() * 2 * .pi, speed = rng.range(0.3...0.8) * max(r.width, r.height)
            let p = ArtGeometry.polar(c, speed * u, a)
            ctx.fill(ArtGeometry.star(center: p, points: 3, outer: 4, inner: 1.5, rotation: a + u * 6),
                     with: .color(ink.rgb(.steel).opacity(1 - u * 0.5).color))
        }
    }

    static func flash(_ ctx: inout GraphicsContext, on: CombatSide, tone: FlashTone, t: Double, start: Double, g: CombatGeometry, ink: ArtInk) {
        let r = g.rect(on).insetBy(dx: -10, dy: -10)
        let local = t - start
        if local <= CombatTiming.flash {
            let color: ArtRGB = switch tone {
            case .hullHit, .heavyHit: ink.rgb(.danger)
            case .shieldHit: ink.rgb(.shieldEnergy)
            case .explosion: ArtRGB(1, 1, 1)
            case .powerDown: ArtRGB(0.55, 0.55, 0.55)
            case .miss, .escape, .arrive: ArtRGB(0.85, 0.85, 0.9)
            }
            let a = 0.45 * sin(min(1, local / CombatTiming.flash) * .pi)
            ctx.fill(Path(roundedRect: r, cornerRadius: 10), with: .color(color.opacity(max(0.08, a)).color))
        }
        // The static symbol (not colour only).
        let c = CGPoint(x: r.maxX - 14, y: r.minY + 14)
        switch tone {
        case .hullHit, .heavyHit:
            var crack = Path()
            crack.move(to: CGPoint(x: c.x - 6, y: c.y - 8))
            crack.addLine(to: CGPoint(x: c.x, y: c.y - 1))
            crack.addLine(to: CGPoint(x: c.x - 3, y: c.y + 2))
            crack.addLine(to: CGPoint(x: c.x + 5, y: c.y + 8))
            ctx.stroke(crack, with: .color(ink(.danger)), lineWidth: 2.5)
        case .shieldHit:
            ctx.fill(EncounterBadgeShape(badge: .police).path(in: CGRect(x: c.x - 8, y: c.y - 8, width: 16, height: 16)), with: .color(ink(.shieldEnergy)))
        case .explosion:
            ctx.fill(ArtGeometry.star(center: c, points: 8, outer: 9, inner: 4), with: .color(.white))
        case .powerDown:
            ctx.fill(ArtGeometry.star(center: c, points: 4, outer: 8, inner: 2), with: .color(.gray))
        case .miss, .escape, .arrive:
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)), with: .color(.white.opacity(0.8)), lineWidth: 1.5)
        }
    }
}
