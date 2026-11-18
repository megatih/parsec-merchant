// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// ART-038: the Welcome backdrop: starfield and nebula with a slow forward drift (20 s cycle) behind the wordmark.
public struct WelcomeScene: View {
    /// Welcome has no galaxy, so the seed is a constant.
    public static let seed: UInt64 = 0x5745_4C43_4F4D_45

    public var phase: Double
    public var accessibility: ArtAccessibility
    public var showsWordmark: Bool
    @Environment(\.colorScheme) private var scheme

    public init(phase: Double = 0, accessibility: ArtAccessibility = .standard, showsWordmark: Bool = true) {
        self.phase = phase
        self.accessibility = accessibility
        self.showsWordmark = showsWordmark
    }

    public static let cycle = 20.0

    public var body: some View {
        let phase = accessibility.ambientPhase(phase), a11y = accessibility, ink = ArtInk(scheme: scheme, contrast: accessibility.increaseContrast)
        ZStack {
            Canvas { ctx, size in
                ctx.clip(to: Path(CGRect(origin: .zero, size: size)))
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(colors: [ink(.spaceTop), ink(.spaceBottom)]),
                                                                                        startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                Nebula(seed: Self.seed).draw(&ctx, size: size, accessibility: a11y, ink: ink)
                Self.drawDrift(&ctx, size: size, phase: phase)
            }
            if showsWordmark { Wordmark(size: 40, increaseContrast: accessibility.increaseContrast) }
        }
        .accessibilityHidden(true)
    }

    /// Stars that move outward from the centre, wrapping every `cycle` seconds.
    static func drawDrift(_ ctx: inout GraphicsContext, size: CGSize, phase: Double) {
        var rng = ArtRandom(seed: seed)
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let reach = hypot(size.width, size.height) / 2
        for _ in 0..<220 {
            let a = rng.unit() * 2 * .pi
            let d0 = rng.unit()
            let d = (d0 + phase / cycle).truncatingRemainder(dividingBy: 1)
            let p = ArtGeometry.polar(c, d * d * reach, a)
            let r = 0.3 + 1.3 * d
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(.white.opacity(0.25 + 0.75 * d)))
        }
    }
}

/// ART-039: the transit scene: the player's ship travelling along the 20-segment track over a starfield with speed streaks.
public struct TransitScene: View {
    public var input: ShipArtInput
    public var progress: Double
    public var phase: Double
    public var wormhole: Bool
    public var seed: UInt64

    public init(input: ShipArtInput, progress: Double, phase: Double = 0, wormhole: Bool = false, seed: UInt64 = 1) {
        self.input = input
        self.progress = min(1, max(0, progress))
        self.phase = phase
        self.wormhole = wormhole
        self.seed = seed
    }

    public var body: some View {
        let a11y = input.accessibility
        let progress = a11y.reduceMotion ? 1 : progress
        let phase = a11y.ambientPhase(phase), wormhole = wormhole
        var ship = input
        ship.facing = .right
        ship.phase = phase
        return GeometryReader { geo in
            let size = geo.size
            // D7: the stage is as tall as the strip; `.relative` then sizes the ship by its class within it.
            let shipSize = CGSize(width: min(size.width * 0.42, size.height * 2.0), height: size.height * 0.94)
            let x = size.width * (0.12 + 0.76 * progress)
            ZStack(alignment: .topLeading) {
                TransitBackdrop(seed: seed, phase: phase, wormhole: wormhole, accessibility: a11y)
                ShipArt(ship, scaleMode: .relative)
                    .frame(width: shipSize.width, height: shipSize.height)
                    .position(x: x, y: size.height / 2)
            }
        }
        .accessibilityHidden(true)
    }
}

struct TransitBackdrop: View {
    var seed: UInt64
    var phase: Double
    var wormhole: Bool
    var accessibility: ArtAccessibility
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let seed = seed, phase = phase, wormhole = wormhole, a11y = accessibility, ink = ArtInk(scheme: scheme, contrast: accessibility.increaseContrast)
        Canvas { ctx, size in
            SpaceBackground.draw(&ctx, size: size, seed: seed, phase: phase, drift: CGPoint(x: -phase * 60, y: 0), accessibility: a11y, ink: ink)
            var rng = ArtRandom(seed: ArtSeed.mix(seed, 0x5354_5245))
            var streaks = Path()
            for _ in 0..<26 {
                let y = rng.unit() * size.height
                let speed = rng.range(120...320)
                let len = rng.range(18...60)
                var x = (rng.unit() * size.width - phase * speed).truncatingRemainder(dividingBy: size.width + len)
                if x < -len { x += size.width + len }
                streaks.move(to: CGPoint(x: x, y: y))
                streaks.addLine(to: CGPoint(x: x + len, y: y))
            }
            ctx.stroke(streaks, with: .color(.white.opacity(0.35)), lineWidth: 1)
            var track = Path()
            for k in 0...20 {
                let x = size.width * (0.12 + 0.76 * Double(k) / 20)
                track.addEllipse(in: CGRect(x: x - 1.2, y: size.height * 0.92 - 1.2, width: 2.4, height: 2.4))
            }
            ctx.fill(track, with: .color(ink.rgb(.brass).opacity(0.7).color))
            if wormhole {
                WormholeVortex.draw(&ctx, center: CGPoint(x: size.width * 0.08, y: size.height / 2), radius: size.height * 0.3, phase: phase,
                                    reduceMotion: a11y.reduceMotion, ink: ink, lineWidth: 3)
            }
        }
    }
}
