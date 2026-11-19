// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// ART-035: a fuzzy ball of 24 seeded fur strokes with two eyes; 4 warm colours by index.
public struct TribbleSprite: View {
    public var index: Int
    /// Seconds since the wiggle started (outside 0…0.2 the sprite is still).
    public var phase: Double
    public var reduceMotion: Bool
    @Environment(\.colorScheme) private var scheme

    public init(index: Int, phase: Double = -1, reduceMotion: Bool = false) {
        self.index = index
        self.phase = phase
        self.reduceMotion = reduceMotion
    }

    static let colors: [ArtRGB] = [ArtRGB(0.72, 0.50, 0.30), ArtRGB(0.86, 0.66, 0.40), ArtRGB(0.62, 0.36, 0.22), ArtRGB(0.90, 0.78, 0.55)]

    /// UI-ENC-026 twin: a ±8° rotation over 0.2 s, or a 0.2 s scale pulse under Reduce Motion.
    public static func wiggle(phase: Double, reduceMotion: Bool) -> (rotation: Double, scale: Double) {
        guard phase >= 0, phase <= 0.2 else { return (0, 1) }
        let s = sin(phase / 0.2 * .pi)
        return reduceMotion ? (0, 1 + 0.15 * s) : (8 * sin(phase / 0.2 * 2 * .pi), 1)
    }

    public var body: some View {
        let w = Self.wiggle(phase: phase, reduceMotion: reduceMotion)
        let color = Self.colors[((index % 4) + 4) % 4]
        let index = index
        Canvas { ctx, size in
            let side = min(size.width, size.height)
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = side * 0.36
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r * 0.9, width: 2 * r, height: 1.8 * r)), with: .color(color.color))
            var rng = ArtRandom(seed: ArtSeed.of(index, 0x5452))
            var fur = Path()
            for k in 0..<24 {
                let a = Double(k) / 24 * 2 * .pi + rng.range(-0.1...0.1)
                let len = r * rng.range(0.25...0.45)
                fur.move(to: ArtGeometry.polar(c, r * 0.75, a))
                fur.addLine(to: ArtGeometry.polar(c, r * 0.75 + len, a + rng.range(-0.25...0.25)))
            }
            ctx.stroke(fur, with: .color(color.shade(0.75).color), style: StrokeStyle(lineWidth: max(0.6, side * 0.035), lineCap: .round))
            for dx in [-0.32, 0.32] {
                let e = CGPoint(x: c.x + dx * r, y: c.y - r * 0.15)
                ctx.fill(Path(ellipseIn: CGRect(x: e.x - r * 0.14, y: e.y - r * 0.14, width: r * 0.28, height: r * 0.28)), with: .color(.white))
                ctx.fill(Path(ellipseIn: CGRect(x: e.x - r * 0.07, y: e.y - r * 0.05, width: r * 0.14, height: r * 0.14)), with: .color(.black))
            }
        }
        .rotationEffect(.degrees(w.rotation))
        .scaleEffect(w.scale)
        .accessibilityHidden(true)
    }
}

/// ART-037: the "Parsec Merchant" wordmark: heavy, wide-tracked system type in a brass gradient after a parsec-ring mark.
public struct Wordmark: View {
    public var increaseContrast: Bool
    public var size: Double
    @Environment(\.colorScheme) private var scheme

    /// The product name (not localised, PRD §2 D1).
    public static let title = "Parsec Merchant"

    public init(size: Double = 40, increaseContrast: Bool = false) {
        self.size = size
        self.increaseContrast = increaseContrast
    }

    public var body: some View {
        let brass = ArtPalette.rgb(.brass, scheme: scheme, contrast: increaseContrast)
        HStack(spacing: size * 0.3) {
            ParsecRingMark(color: brass)
                .frame(width: size * 0.9, height: size * 0.9)
            Text(verbatim: Self.title)
                .font(.system(size: size, weight: .heavy))
                .tracking(size * 0.08)
                .foregroundStyle(increaseContrast ? AnyShapeStyle(brass.color)
                    : AnyShapeStyle(LinearGradient(colors: [brass.shade(1.35).color, brass.color, brass.shade(0.7).color],
                                                   startPoint: .top, endPoint: .bottom)))
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: Self.title))
    }
}

/// The small parsec-ring mark (a ring with a gap at the upper right and a centre point).
struct ParsecRingMark: View {
    var color: ArtRGB

    var body: some View {
        Canvas { ctx, size in
            let side = min(size.width, size.height)
            let t = CGAffineTransform(a: side, b: 0, c: 0, d: side, tx: (size.width - side) / 2, ty: (size.height - side) / 2)
            ctx.fill(GlyphKit.arc(0.5, 0.5, 0.38, from: -28, to: 298, width: 0.14).applying(t), with: .color(color.color))
            ctx.fill(GlyphKit.circle(0.5, 0.5, 0.12).applying(t), with: .color(color.color))
        }
        .accessibilityHidden(true)
    }
}
