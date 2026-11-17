// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// ART-034: special passengers with a fixed avatar.
public enum CrewAvatarRole: Int, CaseIterable, Sendable, Hashable {
    case wild, jarek, princess
}

/// ART-034: a procedural, faceless bust.
public struct CrewAvatar: View {
    public struct Traits: Sendable, Hashable {
        public var helmet: Int
        public var visor: Int
        public var helmetColor: Int
        public var insignia: Int
        public var background: Int

        public static func make(seed: UInt64, role: CrewAvatarRole? = nil) -> Traits {
            if let role {
                return switch role {
                case .wild: Traits(helmet: 4, visor: 2, helmetColor: 6, insignia: 6, background: 5)
                case .jarek: Traits(helmet: 1, visor: 0, helmetColor: 3, insignia: 7, background: 1)
                case .princess: Traits(helmet: 2, visor: 3, helmetColor: 7, insignia: 8, background: 4)
                }
            }
            var rng = ArtRandom(seed: seed)
            return Traits(helmet: rng.int(0...4), visor: rng.int(0...3), helmetColor: rng.int(0...7), insignia: rng.int(0...5),
                          background: rng.int(0...5))
        }
    }

    static let helmetColors: [ArtToken] = [.hullGrey, .slateBlue, .rust, .olive, .ivory, .teal, .crimson, .brass]
    static let backgrounds: [ArtToken] = [.spaceTop, .slate, .oceanDeep, .landDark, .violet, .nightBlack]

    public var traits: Traits
    @Environment(\.colorScheme) private var scheme

    public init(seed: UInt64, role: CrewAvatarRole? = nil) {
        traits = Traits.make(seed: seed, role: role)
    }

    public var body: some View {
        let tr = traits, ink = ArtInk(scheme: scheme, contrast: false)
        Canvas { ctx, size in
            let side = min(size.width, size.height)
            let o = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
            let t = CGAffineTransform(a: side, b: 0, c: 0, d: side, tx: o.x, ty: o.y)
            let disk = GlyphKit.circle(0.5, 0.5, 0.5).applying(t)
            ctx.fill(disk, with: .color(ink(Self.backgrounds[tr.background % Self.backgrounds.count])))
            var c = ctx
            c.clip(to: disk)
            let helmet = ink.rgb(Self.helmetColors[tr.helmetColor % Self.helmetColors.count])
            let shoulders = GlyphKit.rect(0.14, 0.72, 0.72, 0.4, corner: 0.16).applying(t)
            c.fill(shoulders, with: .color(helmet.shade(0.75).color))
            c.fill(Self.helmetPath(tr.helmet).applying(t), with: .linearGradient(Gradient(colors: [helmet.shade(1.3).color, helmet.shade(0.8).color]),
                                                                                  startPoint: o, endPoint: CGPoint(x: o.x + side, y: o.y + side)))
            c.fill(Self.visorPath(tr.visor).applying(t), with: .linearGradient(Gradient(colors: [ArtRGB(0.2, 0.3, 0.45).color,
                                                                                               ArtRGB(0.55, 0.75, 0.95).color]),
                                                                            startPoint: CGPoint(x: o.x, y: o.y + side * 0.6),
                                                                            endPoint: CGPoint(x: o.x + side, y: o.y + side * 0.3)))
            c.fill(Self.insigniaPath(tr.insignia).applying(t), with: .color(ink(.brass)))
        }
        .accessibilityHidden(true)
    }

    static func helmetPath(_ v: Int) -> Path {
        switch v % 5 {
        case 0: GlyphKit.circle(0.5, 0.44, 0.26)
        case 1: GlyphKit.rect(0.25, 0.18, 0.5, 0.52, corner: 0.12)
        case 2: GlyphKit.circle(0.5, 0.44, 0.25).union(GlyphKit.poly([(0.42, 0.2), (0.5, 0.06), (0.58, 0.2)]))
        case 3: GlyphKit.circle(0.5, 0.46, 0.27).union(GlyphKit.rect(0.18, 0.4, 0.64, 0.12, corner: 0.05))
        default: GlyphKit.poly([(0.5, 0.14), (0.78, 0.3), (0.74, 0.7), (0.26, 0.7), (0.22, 0.3)])
        }
    }

    static func visorPath(_ v: Int) -> Path {
        switch v % 4 {
        case 0: GlyphKit.rect(0.32, 0.36, 0.36, 0.14, corner: 0.06)
        case 1: GlyphKit.rect(0.3, 0.34, 0.4, 0.22, corner: 0.1)
        case 2: GlyphKit.rect(0.34, 0.4, 0.32, 0.06, corner: 0.03)
        default: GlyphKit.circle(0.5, 0.44, 0.13)
        }
    }

    static func insigniaPath(_ v: Int) -> Path {
        let c = CGPoint(x: 0.66, y: 0.84)
        return switch v {
        case 0: ArtGeometry.star(center: c, points: 5, outer: 0.06, inner: 0.025)
        case 1: GlyphKit.circle(c.x, c.y, 0.045)
        case 2: GlyphKit.poly([(c.x - 0.06, c.y + 0.04), (c.x, c.y - 0.05), (c.x + 0.06, c.y + 0.04)])
        case 3: GlyphKit.rect(c.x - 0.05, c.y - 0.03, 0.1, 0.06)
        case 4: GlyphKit.line([(c.x - 0.06, c.y - 0.03), (c.x, c.y + 0.03), (c.x + 0.06, c.y - 0.03)], width: 0.025)
        case 5: ArtGeometry.star(center: c, points: 4, outer: 0.06, inner: 0.02)
        case 6: GlyphKit.line([(c.x - 0.06, c.y - 0.05), (c.x + 0.06, c.y + 0.05)], width: 0.03)
            .union(GlyphKit.line([(c.x - 0.06, c.y + 0.05), (c.x + 0.06, c.y - 0.05)], width: 0.03))
        case 7: GlyphKit.circle(c.x, c.y, 0.06).subtracting(GlyphKit.circle(c.x, c.y, 0.03))
        default: GlyphKit.poly([(c.x - 0.07, c.y + 0.04), (c.x - 0.05, c.y - 0.04), (c.x - 0.02, c.y + 0.0), (c.x, c.y - 0.06),
                                (c.x + 0.02, c.y), (c.x + 0.05, c.y - 0.04), (c.x + 0.07, c.y + 0.04)])
        }
    }
}

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
