// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// ART-027: a deterministic starfield in three parallax layers, tiled in 1000 × 1000 pt tiles.
public struct Starfield: Sendable, Hashable {
    public struct Star: Sendable, Hashable {
        public var position: CGPoint
        public var radius: Double
        public var brightness: Double
        /// 0 = warm (orange), 1 = cool (blue-white).
        public var temperature: Double
        public var twinklePeriod: Double
    }

    public static let tile = 1000.0
    public static let maxPerTile = 600
    public static let layers = 3

    public var seed: UInt64
    /// 0…1 of the maximum density.
    public var density: Double

    public init(seed: UInt64, density: Double = 0.5) {
        self.seed = seed
        self.density = min(1, max(0, density))
    }

    /// Stars per tile and layer.
    public var perLayer: Int { Int(Double(Self.maxPerTile / Self.layers) * density) }

    /// The stars of one tile and layer (pure).
    public func stars(tileX: Int, tileY: Int, layer: Int) -> [Star] {
        var rng = ArtRandom(seed: ArtSeed.mix(ArtSeed.mix(ArtSeed.mix(seed, UInt64(bitPattern: Int64(tileX))), UInt64(bitPattern: Int64(tileY))),
                                              UInt64(layer)))
        let n = layer == 0 ? perLayer : perLayer / (layer + 1)
        return (0..<n).map { _ in
            let p = CGPoint(x: (Double(tileX) + rng.unit()) * Self.tile, y: (Double(tileY) + rng.unit()) * Self.tile)
            let base = 0.3 + 0.45 * Double(layer)
            return Star(position: p, radius: min(1.6, base + rng.unit() * 0.45), brightness: rng.range(0.35...1), temperature: rng.unit(),
                        twinklePeriod: rng.range(2...6))
        }
    }

    /// ART-027: the stars of `layer` inside `rect` (pure).
    public func stars(in rect: CGRect, layer: Int) -> [Star] {
        guard rect.width > 0, rect.height > 0 else { return [] }
        let x0 = Int((rect.minX / Self.tile).rounded(.down)), x1 = Int((rect.maxX / Self.tile).rounded(.down))
        let y0 = Int((rect.minY / Self.tile).rounded(.down)), y1 = Int((rect.maxY / Self.tile).rounded(.down))
        var out: [Star] = []
        for ty in y0...y1 {
            for tx in x0...x1 { out += stars(tileX: tx, tileY: ty, layer: layer).filter { rect.contains($0.position) } }
        }
        return out
    }

    /// Draws the three layers over `size`; layer k is offset by `offsets[k]` (parallax). Twinkle only when `twinkle`.
    public func draw(_ ctx: inout GraphicsContext, size: CGSize, offsets: [CGPoint] = [.zero, .zero, .zero], phase: Double = 0,
                     twinkle: Bool = false) {
        for layer in 0..<Self.layers {
            let o = offsets.indices.contains(layer) ? offsets[layer] : .zero
            let view = CGRect(x: -o.x, y: -o.y, width: size.width, height: size.height)
            for s in stars(in: view, layer: layer) {
                var b = s.brightness
                if twinkle { b *= 1 + 0.2 * sin(2 * .pi * phase / s.twinklePeriod + s.temperature * 6) }
                let warm = ArtRGB(1, 0.82, 0.62), cool = ArtRGB(0.78, 0.88, 1)
                let c = warm.mix(cool, s.temperature).opacity(min(1, b))
                let p = CGPoint(x: s.position.x + o.x, y: s.position.y + o.y)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - s.radius, y: p.y - s.radius, width: 2 * s.radius, height: 2 * s.radius)),
                         with: .color(c.color))
            }
        }
    }
}

/// ART-028: 3–5 soft blobs from the `spaceTop` and wormhole ramps at ≤ 18% opacity; omitted under Reduce Transparency.
public struct Nebula: Sendable, Hashable {
    public struct Blob: Sendable, Hashable {
        public var center: CGPoint
        public var radius: Double
        public var token: ArtToken
        public var opacity: Double
    }

    public var seed: UInt64

    public init(seed: UInt64) { self.seed = seed }

    /// Blobs in unit space (0…1 of the view).
    public var blobs: [Blob] {
        var rng = ArtRandom(seed: ArtSeed.mix(seed, 0x4E45_4255))
        let tokens: [ArtToken] = [.spaceTop, .wormholeB, .wormholeA, .visited, .wormholeB]
        return (0..<rng.int(3...5)).map { i in
            Blob(center: CGPoint(x: rng.unit(), y: rng.unit()), radius: rng.range(0.25...0.55), token: tokens[i], opacity: rng.range(0.08...0.18))
        }
    }

    public func draw(_ ctx: inout GraphicsContext, size: CGSize, offset: CGPoint = .zero, accessibility: ArtAccessibility, ink: ArtInk) {
        guard !accessibility.reduceTransparency else { return }
        let side = max(size.width, size.height)
        for b in blobs {
            let c = CGPoint(x: b.center.x * size.width + offset.x, y: b.center.y * size.height + offset.y)
            let r = b.radius * side
            let tint = ink.rgb(b.token).shade(b.token == .spaceTop ? 1.8 : 1)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                     with: .radialGradient(Gradient(colors: [tint.opacity(b.opacity).color, tint.opacity(0).color]), center: c, startRadius: 0,
                                           endRadius: r))
        }
    }
}

/// ART-030: a three-arm spiral that turns once per 6 s; at phase 0 it equals the M8 map vortex (MAP-037).
public enum WormholeVortex {
    public static let period = 6.0

    /// The arms at `phase` (stroke them with the wormhole gradient, 1.3 pt).
    public static func arms(center c: CGPoint, radius r: Double, phase: Double) -> [Path] {
        let turn = phase / period * 360
        return (0..<3).map { k in
            var p = Path()
            let start = Angle.degrees(Double(k) * 120 + turn)
            p.addArc(center: c, radius: r * (0.45 + 0.25 * Double(k)), startAngle: start, endAngle: start + .degrees(200), clockwise: false)
            return p
        }
    }

    public static func draw(_ ctx: inout GraphicsContext, center c: CGPoint, radius r: Double, phase: Double, reduceMotion: Bool,
                            ink: ArtInk, lineWidth: Double = 1.3) {
        let shading = GraphicsContext.Shading.linearGradient(Gradient(colors: [ink(.wormholeA), ink(.wormholeB)]),
                                                             startPoint: CGPoint(x: c.x - r, y: c.y), endPoint: CGPoint(x: c.x + r, y: c.y))
        for arm in arms(center: c, radius: r, phase: reduceMotion ? 0 : phase) {
            ctx.stroke(arm, with: shading, lineWidth: lineWidth)
        }
    }
}

/// A space backdrop: the `spaceTop → spaceBottom` gradient, nebula and starfield.
public struct SpaceBackground: View {
    public var seed: UInt64
    public var phase: Double
    public var drift: CGPoint
    public var accessibility: ArtAccessibility
    @Environment(\.colorScheme) private var scheme

    public init(seed: UInt64, phase: Double = 0, drift: CGPoint = .zero, accessibility: ArtAccessibility = .standard) {
        self.seed = seed
        self.phase = phase
        self.drift = drift
        self.accessibility = accessibility
    }

    public var body: some View {
        let seed = seed, phase = accessibility.ambientPhase(phase), a11y = accessibility, drift = drift
        let ink = ArtInk(scheme: scheme, contrast: accessibility.increaseContrast)
        Canvas { ctx, size in
            SpaceBackground.draw(&ctx, size: size, seed: seed, phase: phase, drift: drift, accessibility: a11y, ink: ink)
        }
        .accessibilityHidden(true)
    }

    public static func draw(_ ctx: inout GraphicsContext, size: CGSize, seed: UInt64, phase: Double, drift: CGPoint,
                            accessibility: ArtAccessibility, ink: ArtInk) {
        ctx.clip(to: Path(CGRect(origin: .zero, size: size)))
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(colors: [ink(.spaceTop), ink(.spaceBottom)]),
                                                                                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        Nebula(seed: seed).draw(&ctx, size: size, offset: CGPoint(x: drift.x * 0.3, y: drift.y * 0.3), accessibility: accessibility, ink: ink)
        let offsets = [0.3, 0.45, 0.6].map { CGPoint(x: drift.x * $0, y: drift.y * $0) }
        Starfield(seed: seed, density: 0.35).draw(&ctx, size: size, offsets: offsets, phase: phase,
                                                  twinkle: !accessibility.reduceMotion && phase != 0)
    }
}

/// A view of the starfield (twinkles only when `animated` and Reduce Motion is off).
public struct StarfieldView: View {
    public var seed: UInt64
    public var density: Double
    public var phase: Double
    public var animated: Bool
    public var accessibility: ArtAccessibility

    public init(seed: UInt64, density: Double = 0.5, phase: Double = 0, animated: Bool = false, accessibility: ArtAccessibility = .standard) {
        self.seed = seed
        self.density = density
        self.phase = phase
        self.animated = animated
        self.accessibility = accessibility
    }

    public var body: some View {
        let field = Starfield(seed: seed, density: density), phase = phase
        let twinkle = animated && !accessibility.reduceMotion
        Canvas { ctx, size in field.draw(&ctx, size: size, phase: phase, twinkle: twinkle) }
            .accessibilityHidden(true)
    }
}

/// A view of the nebula.
public struct NebulaView: View {
    public var seed: UInt64
    public var accessibility: ArtAccessibility
    @Environment(\.colorScheme) private var scheme

    public init(seed: UInt64, accessibility: ArtAccessibility = .standard) {
        self.seed = seed
        self.accessibility = accessibility
    }

    public var body: some View {
        let nebula = Nebula(seed: seed), a11y = accessibility, ink = ArtInk(scheme: scheme, contrast: accessibility.increaseContrast)
        Canvas { ctx, size in
            ctx.clip(to: Path(CGRect(origin: .zero, size: size)))
            nebula.draw(&ctx, size: size, accessibility: a11y, ink: ink)
        }
            .accessibilityHidden(true)
    }
}

/// A view of one wormhole vortex filling its frame.
public struct WormholeVortexView: View {
    public var phase: Double
    public var accessibility: ArtAccessibility
    @Environment(\.colorScheme) private var scheme

    public init(phase: Double = 0, accessibility: ArtAccessibility = .standard) {
        self.phase = phase
        self.accessibility = accessibility
    }

    public var body: some View {
        let phase = phase, reduce = accessibility.reduceMotion, ink = ArtInk(scheme: scheme, contrast: accessibility.increaseContrast)
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2 * 0.9
            WormholeVortex.draw(&ctx, center: CGPoint(x: size.width / 2, y: size.height / 2), radius: r, phase: phase, reduceMotion: reduce,
                                ink: ink, lineWidth: max(1.3, r * 0.12))
        }
        .accessibilityHidden(true)
    }
}

/// ART-078: the system's sun as a soft glow with a bright core and faint rays, placed towards the upper-left corner along
/// the projection of `PlanetSphere.lightDirection`, so the glow and the planet's terminator agree.
public enum StarGlow {
    /// The glow's centre in a frame of `size`.
    public static func center(in size: CGSize) -> CGPoint {
        let l = PlanetSphere.lightDirection
        let len = Double((l.x * l.x + l.y * l.y).squareRoot())
        let side = min(size.width, size.height)
        return CGPoint(x: size.width / 2 + Double(l.x) / len * side * 0.60, y: size.height / 2 - Double(l.y) / len * side * 0.60)
    }

    /// The star's colour: one of four temperatures by seed.
    public static func tint(seed: UInt64) -> ArtRGB {
        let tints = [ArtRGB(1.0, 0.96, 0.86), ArtRGB(1.0, 0.86, 0.62), ArtRGB(0.84, 0.92, 1.0), ArtRGB(1.0, 0.74, 0.52)]
        return tints[Int(ArtSeed.mix(seed, 0x5354_4152) % 4)]
    }

    public static func draw(_ ctx: inout GraphicsContext, size: CGSize, seed: UInt64, accessibility: ArtAccessibility) {
        let c = center(in: size), side = min(size.width, size.height), tint = tint(seed: seed)
        let core = side * 0.035
        if accessibility.reduceTransparency {
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - core * 1.6, y: c.y - core * 1.6, width: core * 3.2, height: core * 3.2)),
                     with: .color(tint.color))
            return
        }
        let r = side * 0.62
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                 with: .radialGradient(Gradient(stops: [.init(color: tint.opacity(0.55).color, location: 0),
                                                        .init(color: tint.opacity(0.16).color, location: 0.22),
                                                        .init(color: tint.opacity(0.04).color, location: 0.6),
                                                        .init(color: tint.opacity(0).color, location: 1)]),
                                       center: c, startRadius: 0, endRadius: r))
        var rng = ArtRandom(seed: ArtSeed.mix(seed, 0x5241_5953))
        for k in 0..<6 {
            let a = Double(k) * .pi / 3 + rng.range(0...0.4), len = side * rng.range(0.16...0.32), w = core * 0.22
            var ray = Path()
            ray.move(to: ArtGeometry.polar(c, w, a + .pi / 2))
            ray.addLine(to: ArtGeometry.polar(c, len, a))
            ray.addLine(to: ArtGeometry.polar(c, w, a - .pi / 2))
            ray.addLine(to: ArtGeometry.polar(c, len, a + .pi))
            ray.closeSubpath()
            ctx.fill(ray, with: .radialGradient(Gradient(colors: [tint.opacity(0.5).color, tint.opacity(0).color]), center: c, startRadius: 0,
                                                endRadius: len))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - core * 2.4, y: c.y - core * 2.4, width: core * 4.8, height: core * 4.8)),
                 with: .radialGradient(Gradient(colors: [Color.white, tint.opacity(0.9).color, tint.opacity(0).color]), center: c,
                                       startRadius: core * 0.5, endRadius: core * 2.4))
    }
}

/// ART-078: the stage behind the Bridge's hero planet: deep space, a faint nebula, the densest starfield at half scale
/// (four times the stars per area) and the system's star glow, clipped to a rounded rectangle.
public struct HeroBackdrop: View {
    public var seed: UInt64
    public var accessibility: ArtAccessibility
    public static let cornerRadius = 14.0
    /// The starfield is drawn at this scale, so it is denser than ART-027's maximum per area.
    public static let starScale = 0.5

    public init(seed: UInt64, accessibility: ArtAccessibility = .standard) {
        self.seed = seed
        self.accessibility = accessibility
    }

    public var body: some View {
        let seed = seed, a11y = accessibility
        // Space is dark in both appearances.
        let ink = ArtInk(scheme: .dark, contrast: accessibility.increaseContrast)
        Canvas { ctx, size in
            let frame = CGRect(origin: .zero, size: size)
            ctx.clip(to: Path(roundedRect: frame, cornerRadius: Self.cornerRadius))
            ctx.fill(Path(frame), with: .linearGradient(Gradient(colors: [ink(.spaceTop), ink(.spaceBottom)]), startPoint: .zero,
                                                        endPoint: CGPoint(x: size.width, y: size.height)))
            Nebula(seed: seed).draw(&ctx, size: size, accessibility: a11y, ink: ink)
            var stars = ctx
            stars.scaleBy(x: Self.starScale, y: Self.starScale)
            Starfield(seed: seed, density: 1).draw(&stars, size: CGSize(width: size.width / Self.starScale, height: size.height / Self.starScale))
            StarGlow.draw(&ctx, size: size, seed: seed, accessibility: a11y)
        }
        .accessibilityHidden(true)
    }
}
