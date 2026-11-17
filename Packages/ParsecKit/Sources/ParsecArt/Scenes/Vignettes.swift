// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// ART-040: items that have no ship or planet of their own.
public enum VignetteObject: String, CaseIterable, Sendable, Hashable {
    case artifact, reactor, jewels, antidote, japoriMedicine, moonDeed, tonicBottle, gemulonFleet, experimentRip
}

/// ART-040: what a narrative sheet illustrates.
public enum VignetteKind: Sendable, Hashable {
    case planet(PlanetArtInput)
    case ship(ShipArtInput)
    case object(VignetteObject)
}

/// ART-040: a small composed scene for a narrative sheet.
public struct Vignette: View {
    public var kind: VignetteKind
    public var seed: UInt64

    public init(kind: VignetteKind, seed: UInt64 = 7) {
        self.kind = kind
        self.seed = seed
    }

    public var body: some View {
        ZStack {
            SpaceBackground(seed: seed)
            switch kind {
            case let .planet(input): PlanetArt(input).padding(6)
            case let .ship(input): ShipArt(input, scaleMode: .fit).padding(10)
            case let .object(object): VignetteObjectArt(object: object)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityHidden(true)
    }
}

struct VignetteObjectArt: View {
    var object: VignetteObject
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let object = object, ink = ArtInk(scheme: scheme, contrast: false)
        Canvas { ctx, size in
            let side = min(size.width, size.height)
            let t = CGAffineTransform(a: side, b: 0, c: 0, d: side, tx: (size.width - side) / 2, ty: (size.height - side) / 2)
            VignetteObjectArt.draw(&ctx, object, t: t, ink: ink)
        }
    }

    static func draw(_ ctx: inout GraphicsContext, _ object: VignetteObject, t: CGAffineTransform, ink: ArtInk) {
        typealias GK = GlyphKit
        func fill(_ p: Path, _ c: ArtRGB) { ctx.fill(p.applying(t), with: .color(c.color)) }
        func glow(_ x: Double, _ y: Double, _ r: Double, _ c: ArtRGB) {
            let center = CGPoint(x: x, y: y).applying(t), rr = r * t.a
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - rr, y: center.y - rr, width: 2 * rr, height: 2 * rr)),
                     with: .radialGradient(Gradient(colors: [c.color, c.opacity(0).color]), center: center, startRadius: 0, endRadius: rr))
        }
        switch object {
        case .artifact:
            glow(0.5, 0.5, 0.34, ink.rgb(.alienGlow).opacity(0.6))
            fill(GK.poly([(0.5, 0.18), (0.72, 0.5), (0.5, 0.82), (0.28, 0.5)]), ink.rgb(.teal))
            fill(GK.poly([(0.5, 0.28), (0.62, 0.5), (0.5, 0.72), (0.38, 0.5)]), ink.rgb(.alienGlow))
        case .reactor:
            glow(0.5, 0.5, 0.36, ink.rgb(.yellowGreen).opacity(0.7))
            fill(GK.rect(0.32, 0.26, 0.36, 0.5, corner: 0.05), ink.rgb(.steel))
            fill(GK.rect(0.38, 0.34, 0.24, 0.34, corner: 0.04), ink.rgb(.yellowGreen))
            fill(ArtGeometry.star(center: CGPoint(x: 0.5, y: 0.51), points: 3, outer: 0.1, inner: 0.03), ink.rgb(.nightBlack))
        case .jewels:
            fill(GK.rect(0.3, 0.62, 0.4, 0.14, corner: 0.02), ink.rgb(.cream))
            fill(GK.poly([(0.36, 0.62), (0.4, 0.3), (0.5, 0.2), (0.6, 0.3), (0.64, 0.62)]), ink.rgb(.ivory).shade(0.9))
            for (x, y) in [(0.44, 0.36), (0.56, 0.36), (0.5, 0.48)] {
                fill(ArtGeometry.star(center: CGPoint(x: x, y: y), points: 4, outer: 0.05, inner: 0.02), ink.rgb(.danger))
            }
        case .antidote, .japoriMedicine:
            let tint = object == .antidote ? ink.rgb(.profit) : ink.rgb(.shieldEnergy)
            for k in 0..<3 {
                let x = 0.28 + Double(k) * 0.16
                fill(GK.rect(x, 0.34, 0.12, 0.38, corner: 0.04), ArtRGB(0.85, 0.92, 0.95, 0.9))
                fill(GK.rect(x, 0.5, 0.12, 0.22, corner: 0.04), tint)
                fill(GK.rect(x + 0.02, 0.28, 0.08, 0.07, corner: 0.02), ink.rgb(.slate))
            }
            if object == .japoriMedicine { fill(GK.union([GK.rect(0.47, 0.12, 0.06, 0.14), GK.rect(0.43, 0.16, 0.14, 0.06)]), ink.rgb(.danger)) }
        case .moonDeed:
            fill(GK.rect(0.22, 0.26, 0.56, 0.5, corner: 0.03), ink.rgb(.parchment))
            for k in 0..<4 { fill(GK.rect(0.3, 0.36 + Double(k) * 0.07, 0.4 - Double(k % 2) * 0.1, 0.025), ink.rgb(.landBrown)) }
            fill(GK.circle(0.64, 0.66, 0.06), ink.rgb(.danger))
            fill(GK.circle(0.78, 0.2, 0.08).subtracting(GK.circle(0.82, 0.18, 0.07)), ink.rgb(.ivory))
        case .tonicBottle:
            let bottle = ShipArtEmblem.path(.bottle)
            fill(GlyphKit.rotated(bottle, degrees: -70), ArtRGB(0.55, 0.85, 0.6, 0.8))
        case .gemulonFleet:
            for k in 0..<5 {
                let p = CGPoint(x: 0.2 + Double(k) * 0.14, y: 0.3 + Double(k % 2) * 0.3 + Double(k) * 0.02)
                let s = ShipArtEmblem.path(.mantis).applying(CGAffineTransform(a: 0.18, b: 0, c: 0, d: 0.18, tx: p.x - 0.09, ty: p.y - 0.09))
                fill(s, ink.rgb(.teal))
            }
        case .experimentRip:
            var rip = Path()
            rip.move(to: CGPoint(x: 0.5, y: 0.1))
            for k in 1...8 { rip.addLine(to: CGPoint(x: 0.5 + (k.isMultiple(of: 2) ? 0.07 : -0.07), y: 0.1 + Double(k) * 0.1)) }
            glow(0.5, 0.5, 0.3, ink.rgb(.wormholeB).opacity(0.6))
            ctx.stroke(rip.applying(t), with: .color(ink(.wormholeA)), lineWidth: max(2, t.a * 0.03))
        }
    }
}

/// ART-041: the four endings (engine `GameEndType` order).
public enum GameEndArt: Int, CaseIterable, Sendable, Hashable {
    case killed = 0, retired, boughtMoon, boughtMoonGirl
}

/// ART-041: the ending cinematic; it animates for at most 4 s and then holds (final frame under Reduce Motion).
public struct GameOverScene: View {
    public var end: GameEndArt
    public var phase: Double
    public var ship: ShipArtKind
    public var accessibility: ArtAccessibility
    @Environment(\.colorScheme) private var scheme

    public static let duration = 4.0

    public init(end: GameEndArt, phase: Double = duration, ship: ShipArtKind = .gnat, accessibility: ArtAccessibility = .standard) {
        self.end = end
        self.phase = phase
        self.ship = ship
        self.accessibility = accessibility
    }

    /// The scene time (clamped to 0…4 s; the final frame under Reduce Motion).
    public static func time(phase: Double, reduceMotion: Bool) -> Double {
        reduceMotion ? duration : min(duration, max(0, phase))
    }

    public var body: some View {
        let u = Self.time(phase: phase, reduceMotion: accessibility.reduceMotion) / Self.duration
        ZStack {
            switch end {
            case .killed:
                SpaceBackground(seed: 3)
                ShipArt(ShipArtInput(kind: ship, hullFraction: 0.08, disabled: true), scaleMode: .fit)
                    .rotationEffect(.degrees(-20 - 25 * u))
                    .offset(x: -30 + 60 * u, y: 8 * u)
                    .padding(24)
                EndingCanvas(end: end, u: u)
            default:
                EndingCanvas(end: end, u: u)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
    }
}

struct EndingCanvas: View {
    var end: GameEndArt
    var u: Double
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let end = end, u = u, ink = ArtInk(scheme: scheme, contrast: false)
        Canvas { ctx, size in
            switch end {
            case .killed: EndingCanvas.debris(&ctx, size: size, u: u, ink: ink)
            case .retired: EndingCanvas.sunset(&ctx, size: size, u: u, ink: ink)
            case .boughtMoon, .boughtMoonGirl: EndingCanvas.moon(&ctx, size: size, u: u, girl: end == .boughtMoonGirl, ink: ink)
            }
        }
    }

    static func debris(_ ctx: inout GraphicsContext, size: CGSize, u: Double, ink: ArtInk) {
        var rng = ArtRandom(seed: 0xDEB_0001)
        for _ in 0..<14 {
            let p = CGPoint(x: size.width * rng.unit() + 40 * u * rng.range(-1...1), y: size.height * rng.unit() + 30 * u * rng.range(-1...1))
            ctx.fill(ArtGeometry.star(center: p, points: 3, outer: rng.range(3...7), inner: 1.5, rotation: u * 3 + rng.unit() * 6),
                     with: .color(ink(.steel)))
        }
    }

    static func sunset(_ ctx: inout GraphicsContext, size: CGSize, u: Double, ink: ArtInk) {
        let sky = Gradient(colors: [ink(.spaceTop), ArtRGB(0.85, 0.35, 0.35).color, ArtRGB(1, 0.7, 0.35).color])
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(sky, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        let sunR = size.height * 0.18
        let sun = CGPoint(x: size.width * 0.5, y: size.height * (0.5 + 0.22 * u))
        ctx.fill(Path(ellipseIn: CGRect(x: sun.x - sunR, y: sun.y - sunR, width: 2 * sunR, height: 2 * sunR)),
                 with: .color(ArtRGB(1, 0.86, 0.5).color))
        let horizonR = size.width * 1.4
        let hc = CGPoint(x: size.width / 2, y: size.height * 0.72 + horizonR)
        ctx.fill(Path(ellipseIn: CGRect(x: hc.x - horizonR, y: hc.y - horizonR, width: 2 * horizonR, height: 2 * horizonR)),
                 with: .linearGradient(Gradient(colors: [ink.rgb(.landDark).color, ink.rgb(.nightBlack).color]),
                                       startPoint: CGPoint(x: 0, y: size.height * 0.72), endPoint: CGPoint(x: 0, y: size.height)))
    }

    static func moon(_ ctx: inout GraphicsContext, size: CGSize, u: Double, girl: Bool, ink: ArtInk) {
        SpaceBackground.draw(&ctx, size: size, seed: 5, phase: 0, drift: .zero, accessibility: .standard, ink: ink)
        let r = size.height * 0.75
        let c = CGPoint(x: size.width / 2, y: size.height * 0.62 + r * 0.6 + (1 - u) * size.height * 0.2)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                 with: .linearGradient(Gradient(colors: [ink.rgb(.ivory).color, ink.rgb(.landGrey).color]), startPoint: CGPoint(x: c.x, y: c.y - r),
                                       endPoint: CGPoint(x: c.x, y: c.y)))
        let top = c.y - r
        let dome = CGRect(x: c.x - size.height * 0.2, y: top - size.height * 0.16, width: size.height * 0.4, height: size.height * 0.32)
        ctx.fill(Path(ellipseIn: dome), with: .color(ArtRGB(0.7, 0.88, 1, 0.45).color))
        ctx.stroke(Path(ellipseIn: dome), with: .color(.white.opacity(0.8)), lineWidth: 1.5)
        let villa = CGRect(x: c.x - size.height * 0.1, y: top - size.height * 0.09, width: size.height * 0.2, height: size.height * 0.09)
        ctx.fill(Path(villa), with: .color(ink(.cream)))
        let windows = girl ? 2 : 1
        for k in 0..<windows {
            let w = CGRect(x: villa.minX + villa.width * (0.2 + 0.4 * Double(k)), y: villa.minY + villa.height * 0.3,
                           width: villa.width * 0.18, height: villa.height * 0.35)
            ctx.fill(Path(w), with: .color(ink(.cityLight)))
        }
        if girl {
            let ship = ShipArtEmblem.path(.gnat)
            let s = size.height * 0.16
            ctx.fill(ship.applying(CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: villa.maxX + s * 0.2, ty: top - s * 0.7)), with: .color(ink(.brass)))
        }
    }
}
