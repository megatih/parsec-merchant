// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// The colours of one portrait.
struct PortraitInk {
    var light: ArtRGB
    var mid: ArtRGB
    var shadow: ArtRGB
    var deep: ArtRGB
    var lip: ArtRGB
    var hair: ArtRGB
    var iris: ArtRGB
    var attire: ArtRGB
    var backdrop: ArtRGB
    /// The brightness of the skin, 0…1: eyes and highlights are toned to it.
    var skinLuminance: Double

    static let skins: [ArtRGB] = [
        ArtRGB(0.97, 0.85, 0.76), ArtRGB(0.94, 0.79, 0.67), ArtRGB(0.90, 0.73, 0.59), ArtRGB(0.85, 0.67, 0.51), ArtRGB(0.78, 0.59, 0.43),
        ArtRGB(0.70, 0.51, 0.36), ArtRGB(0.60, 0.42, 0.30), ArtRGB(0.50, 0.34, 0.24), ArtRGB(0.41, 0.27, 0.19), ArtRGB(0.32, 0.21, 0.15),
    ]
    static let hairs: [ArtRGB] = [
        ArtRGB(0.10, 0.09, 0.10), ArtRGB(0.20, 0.15, 0.12), ArtRGB(0.31, 0.22, 0.16), ArtRGB(0.42, 0.31, 0.22), ArtRGB(0.47, 0.25, 0.17),
        ArtRGB(0.80, 0.66, 0.40), ArtRGB(0.58, 0.58, 0.60), ArtRGB(0.87, 0.87, 0.86),
    ]
    static let irises: [ArtRGB] = [
        ArtRGB(0.22, 0.13, 0.08), ArtRGB(0.40, 0.25, 0.12), ArtRGB(0.50, 0.42, 0.20), ArtRGB(0.28, 0.46, 0.30), ArtRGB(0.28, 0.46, 0.70),
        ArtRGB(0.45, 0.52, 0.58),
    ]
    static let attires: [ArtRGB] = [
        ArtRGB(0.17, 0.23, 0.38), ArtRGB(0.25, 0.26, 0.29), ArtRGB(0.33, 0.37, 0.24), ArtRGB(0.52, 0.29, 0.19), ArtRGB(0.43, 0.16, 0.21),
        ArtRGB(0.15, 0.38, 0.40), ArtRGB(0.35, 0.23, 0.43), ArtRGB(0.14, 0.14, 0.17),
    ]
    static let backdrops: [ArtRGB] = [
        ArtRGB(0.24, 0.30, 0.40), ArtRGB(0.36, 0.34, 0.33), ArtRGB(0.26, 0.34, 0.31), ArtRGB(0.32, 0.28, 0.40), ArtRGB(0.40, 0.35, 0.27),
        ArtRGB(0.30, 0.33, 0.37),
    ]
    static let brass = ArtRGB(0.86, 0.69, 0.32)
    static let steel = ArtRGB(0.62, 0.66, 0.71)

    init(_ g: PortraitGenome) {
        let base = Self.skins[g.skin % Self.skins.count]
        // Dark skin takes a smaller step towards the light colour, or its lit planes would read as pale patches.
        let lum = 0.299 * base.r + 0.587 * base.g + 0.114 * base.b
        light = base.mix(ArtRGB(1, 0.95, 0.88), 0.18 + 0.20 * lum)
        skinLuminance = lum
        // Dark skin keeps more of its colour in shadow, or the far side of the face would go black and lose its features.
        let keep = 0.62 + 0.15 * (1 - lum)
        mid = ArtRGB(base.r * 0.93, base.g * 0.91, base.b * 0.89)
        shadow = ArtRGB(base.r * keep, base.g * (keep - 0.09), base.b * (keep - 0.10))
        deep = ArtRGB(base.r * (keep - 0.16), base.g * (keep - 0.24), base.b * (keep - 0.24))
        lip = base.mix(ArtRGB(0.72, 0.30, 0.30), 0.42)
        // Hair close to the skin's brightness would hide the hairline: it goes to black (or to a dark brown on the darkest skin).
        var hairTone = Self.hairs[g.hairColor % Self.hairs.count]
        let hairLum = 0.299 * hairTone.r + 0.587 * hairTone.g + 0.114 * hairTone.b
        if abs(hairLum - lum * 0.93) < 0.13 { hairTone = lum < 0.30 ? ArtRGB(0.05, 0.05, 0.06) : Self.hairs[0] }
        hair = hairTone
        // On dark skin a bright iris glows; it is pulled towards brown.
        iris = Self.irises[g.eyeColor % Self.irises.count].mix(ArtRGB(0.26, 0.17, 0.11), max(0, 0.55 - lum) * 0.9)
        attire = Self.attires[g.attireColor % Self.attires.count]
        backdrop = Self.backdrops[g.backdrop % Self.backdrops.count]
    }

    /// Brows, lashes and facial hair: the hair colour, never lighter than a mid grey-brown so it reads on every skin.
    var browColor: ArtRGB {
        let lum = 0.299 * hair.r + 0.587 * hair.g + 0.114 * hair.b
        let tone = lum > 0.5 ? hair.shade(0.62) : hair
        // Brows frame the eyes: they are always clearly darker than the skin, whatever the hair colour.
        let toneLum = 0.299 * tone.r + 0.587 * tone.g + 0.114 * tone.b
        return toneLum > skinLuminance * 0.70 ? tone.mix(deep, 0.6) : tone
    }
}

/// ART-FACE: draws a portrait from its genome. Everything is laid out in the unit square and mapped to `rect`.
/// The key light comes from the upper left; tones are flat planes with a few soft gradients.
struct PortraitPainter {
    let g: PortraitGenome
    let l: PortraitLayout
    let ink: PortraitInk
    let t: CGAffineTransform
    let cx = PortraitLayout.centerX
    let top = PortraitLayout.top

    init(genome: PortraitGenome, rect: CGRect) {
        g = genome
        l = PortraitLayout(genome)
        ink = PortraitInk(genome)
        let side = min(rect.width, rect.height)
        t = CGAffineTransform(a: side, b: 0, c: 0, d: side, tx: rect.midX - side / 2, ty: rect.midY - side / 2)
    }

    // MARK: Helpers

    func fill(_ ctx: inout GraphicsContext, _ path: Path, _ color: ArtRGB) {
        ctx.fill(path.applying(t), with: .color(color.color))
    }

    func gradient(_ ctx: inout GraphicsContext, _ path: Path, _ a: ArtRGB, _ b: ArtRGB, from p: (Double, Double), to q: (Double, Double)) {
        ctx.fill(path.applying(t), with: .linearGradient(Gradient(colors: [a.color, b.color]),
                                                         startPoint: CGPoint(x: p.0, y: p.1).applying(t), endPoint: CGPoint(x: q.0, y: q.1).applying(t)))
    }

    func clipped(_ ctx: GraphicsContext, to path: Path) -> GraphicsContext {
        var c = ctx
        c.clip(to: path.applying(t))
        return c
    }

    func closed(_ points: [(Double, Double)]) -> Path { ArtGeometry.closedSpline(points.map { SplinePoint($0.0, $0.1) }) }

    func open(_ points: [(Double, Double)], width: Double) -> Path {
        ArtGeometry.stroke(ArtGeometry.openSpline(points.map { SplinePoint($0.0, $0.1) }), width: width)
    }

    func ellipse(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double) -> Path {
        Path(ellipseIn: CGRect(x: x - rx, y: y - ry, width: rx * 2, height: ry * 2))
    }

    /// A region bounded on the left by a spline through `inner` and on the right by the picture edge.
    func rightOf(_ inner: [(Double, Double)]) -> Path {
        var p = ArtGeometry.openSpline(inner.map { SplinePoint($0.0, $0.1) })
        guard let first = inner.first, let last = inner.last else { return p }
        p.addLine(to: CGPoint(x: 1.2, y: last.1))
        p.addLine(to: CGPoint(x: 1.2, y: first.1))
        p.closeSubpath()
        return p
    }

    /// A region bounded on the right by a spline through `inner` and on the left by the picture edge.
    func leftOf(_ inner: [(Double, Double)]) -> Path {
        var p = ArtGeometry.openSpline(inner.map { SplinePoint($0.0, $0.1) })
        guard let first = inner.first, let last = inner.last else { return p }
        p.addLine(to: CGPoint(x: -0.2, y: last.1))
        p.addLine(to: CGPoint(x: -0.2, y: first.1))
        p.closeSubpath()
        return p
    }

    var neckHalf: Double { l.jawHalf * 0.70 }

    // MARK: Drawing

    func draw(_ ctx: inout GraphicsContext) {
        let frame = Path(roundedRect: CGRect(x: 0, y: 0, width: 1, height: 1), cornerRadius: 0.08)
        var c = clipped(ctx, to: frame)
        backdrop(&c)
        hairBack(&c)
        body(&c)
        neck(&c)
        ears(&c)
        head(&c)
        facialHair(&c)
        nose(&c)
        mouth(&c)
        for side in [-1.0, 1.0] where !(g.mark == 4 && side < 0) { eye(&c, side) }
        for side in [-1.0, 1.0] { brow(&c, side) }
        ageLines(&c)
        marks(&c)
        hairFront(&c)
        accessories(&c)
    }

    func backdrop(_ ctx: inout GraphicsContext) {
        let all = Path(CGRect(x: 0, y: 0, width: 1, height: 1))
        gradient(&ctx, all, ink.backdrop.shade(1.18), ink.backdrop.shade(0.62), from: (0.2, 0), to: (0.8, 1))
        fill(&ctx, Path(CGRect(x: 0, y: 0, width: 0.34, height: 1)), ArtRGB(1, 1, 1, 0.05))
        fill(&ctx, Path(CGRect(x: 0, y: 0.60, width: 1, height: 0.012)), ArtRGB(0, 0, 0, 0.14))
        ctx.fill(all.applying(t), with: .radialGradient(Gradient(colors: [ArtRGB(1, 1, 1, 0.10).color, ArtRGB(1, 1, 1, 0).color]),
                                                        center: CGPoint(x: 0.38, y: 0.36).applying(t), startRadius: 0, endRadius: 0.55 * t.a))
    }

    func body(_ ctx: inout GraphicsContext) {
        let n = neckHalf
        let shape = ArtGeometry.closedSpline([
            SplinePoint(cx - n - 0.012, 0.795), SplinePoint(cx - 0.20, 0.842), SplinePoint(cx - 0.355, 0.895), SplinePoint(cx - 0.43, 0.97),
            SplinePoint(cx - 0.46, 1.06, sharp: true), SplinePoint(cx + 0.46, 1.06, sharp: true), SplinePoint(cx + 0.43, 0.97),
            SplinePoint(cx + 0.355, 0.895), SplinePoint(cx + 0.20, 0.842), SplinePoint(cx + n + 0.012, 0.795),
        ])
        let base = g.attire % 8 == 3 ? ArtRGB(0.74, 0.72, 0.66) : ink.attire
        gradient(&ctx, shape, base.shade(1.22), base.shade(0.86), from: (0.1, 0.8), to: (0.9, 1.0))
        var c = clipped(ctx, to: shape)
        gradient(&c, Path(CGRect(x: 0, y: 0.7, width: 1, height: 0.4)), ArtRGB(0, 0, 0, 0), ArtRGB(0, 0, 0, 0.30), from: (cx, 0.8), to: (cx + 0.36, 0.8))
        fill(&c, open([(cx - 0.36, 0.905), (cx - 0.22, 0.86), (cx - 0.12, 0.835)], width: 0.008), ArtRGB(1, 1, 1, 0.16))
        attire(&c, base: base)
        insignia(&c)
    }

    func neck(_ ctx: inout GraphicsContext) {
        let n = neckHalf
        let shape = closed([(cx - n, l.chinY - 0.09), (cx - n * 0.96, 0.76), (cx - n - 0.012, 0.80), (cx - n * 0.5, 0.835), (cx, 0.845),
                            (cx + n * 0.5, 0.835), (cx + n + 0.012, 0.80), (cx + n * 0.96, 0.76), (cx + n, l.chinY - 0.09)])
        guard ![2, 6].contains(g.attire % 8) else {
            fill(&ctx, shape, ink.shadow)
            return
        }
        gradient(&ctx, shape, ink.mid, ink.shadow, from: (cx - n, 0.7), to: (cx + n, 0.8))
        var c = clipped(ctx, to: shape)
        // The jaw's cast shadow.
        fill(&c, l.head.applying(CGAffineTransform(translationX: 0.012, y: 0.045)), ink.deep.opacity(0.62))
        fill(&c, Path(CGRect(x: cx + n * 0.35, y: 0.6, width: 0.3, height: 0.4)), ink.deep.opacity(0.30))
    }

    func ears(_ ctx: inout GraphicsContext) {
        let scale = [1.0, 1.18, 0.86][g.earShape % 3]
        let h = (l.noseBaseY - l.browY) * 0.5 * scale + 0.012
        let y = (l.browY + l.noseBaseY) / 2 + 0.004
        for side in [-1.0, 1.0] {
            let x = cx + side * (l.cheekHalf - 0.002)
            let outer = ellipse(x + side * 0.002 * scale, y, 0.014 * scale, h * 0.80)
            fill(&ctx, outer, side < 0 ? ink.mid : ink.shadow)
            fill(&ctx, ellipse(x + side * 0.003 * scale, y + 0.004, 0.006 * scale, h * 0.46), ink.deep.opacity(side < 0 ? 0.38 : 0.55))
        }
    }

    func head(_ ctx: inout GraphicsContext) {
        let head = l.head
        // The front of the face in the mid tone; the light falls on the near side; the far cheek and jaw turn away in
        // two soft steps. The terminator follows the cheekbone and jaw, well off the centre line.
        fill(&ctx, head, ink.mid)
        var c = clipped(ctx, to: head)
        let k = l.cheekHalf, j = l.jawHalf
        fill(&c, leftOf([(cx + 0.05, top - 0.03), (cx - 0.02, l.eyeY - 0.135), (cx - k * 0.66, l.eyeY - 0.04), (cx - k * 0.64, l.eyeY + 0.085),
                         (cx - j * 0.60, l.mouthY + 0.01), (cx - 0.065, l.chinY + 0.03)]), ink.light.opacity(0.62))
        fill(&c, ellipse(cx - 0.030, top + 0.085, 0.120, 0.070), ink.light.opacity(0.50))
        fill(&c, rightOf([(cx + 0.125, top - 0.03), (cx + 0.140, l.eyeY - 0.10), (cx + k * 0.70, l.eyeY - 0.005), (cx + k * 0.74, l.eyeY + 0.085),
                          (cx + j * 0.66, l.mouthY + 0.01), (cx + 0.060, l.chinY + 0.03)]), ink.shadow.opacity(0.55))
        fill(&c, rightOf([(cx + 0.165, top - 0.03), (cx + k * 0.86, l.eyeY - 0.06), (cx + k * 0.88, l.eyeY + 0.08),
                          (cx + j * 0.82, l.mouthY + 0.0), (cx + 0.085, l.chinY + 0.03)]), ink.shadow.opacity(0.75))
        // Lit accents: the brow ridge, the near cheekbone and the chin; fainter on dark skin.
        let accent = 0.22 + 0.30 * ink.skinLuminance
        fill(&c, ellipse(cx - 0.045, top + 0.155, 0.070, 0.028), ink.light.shade(1.2).opacity(accent))
        fill(&c, ellipse(cx - k * 0.56, l.eyeY + 0.072, 0.038, 0.020), ink.light.shade(1.2).opacity(accent))
        fill(&c, ellipse(cx - 0.012, l.chinY - 0.035, 0.032, 0.016), ink.light.opacity(accent))
        // Eye sockets.
        for side in [-1.0, 1.0] {
            let e = l.eyeCenter(side)
            fill(&c, ellipse(e.x, e.y - l.eyeWidth * 0.10, l.eyeWidth * 0.78, l.eyeWidth * 0.46), ink.shadow.opacity(side < 0 ? 0.36 : 0.44))
        }
    }

    func nose(_ ctx: inout GraphicsContext) {
        let shape = g.noseShape % 6
        let base = l.noseBaseY, half = l.noseHalf, topY = l.eyeY - l.eyeWidth * 0.12
        let bridge = [0.016, 0.019, 0.013, 0.015, 0.018, 0.021][shape]
        let bump = shape == 4 ? 0.006 : 0.0
        // The far side plane of the bridge.
        fill(&ctx, closed([(cx + 0.002, topY + 0.02), (cx + bridge * 0.7 + bump, (topY + base) / 2 - 0.01), (cx + half * 0.88, base - 0.028),
                           (cx + half, base - 0.010), (cx + half * 0.5, base + 0.004), (cx + 0.004, base - 0.004), (cx + 0.006, (topY + base) / 2)]),
             ink.shadow.opacity(0.58))
        // The near wing and the lit ridge.
        fill(&ctx, ellipse(cx - half * 0.72, base - 0.014, half * 0.34, 0.015), ink.shadow.opacity(0.38))
        fill(&ctx, open([(cx - 0.004, topY + 0.02), (cx - 0.005 + bump * 0.5, (topY + base) / 2), (cx - 0.004, base - 0.030)], width: 0.010),
             ink.light.shade(1.25).opacity(0.55))
        let tip = [0.020, 0.024, 0.016, 0.022, 0.018, 0.024][shape]
        fill(&ctx, ellipse(cx - 0.006, base - 0.020, tip * 0.60, tip * 0.48), ink.light.shade(1.3).opacity(0.50))
        // Nostrils and the shadow the nose casts.
        for side in [-1.0, 1.0] {
            fill(&ctx, ellipse(cx + side * half * 0.50, base - 0.004, half * 0.26, 0.006), ink.deep.opacity(0.85))
        }
        fill(&ctx, closed([(cx - half * 0.55, base + 0.004), (cx + half * 0.95, base + 0.002), (cx + half * 0.80, base + 0.020),
                           (cx + 0.004, base + 0.014)]), ink.shadow.opacity(0.55))
    }

    func mouth(_ ctx: inout GraphicsContext) {
        let shape = g.mouthShape % 6
        let y = l.mouthY, half = l.mouthHalf, lh = l.lipHeight
        let corner = [0.0, 0.0, 0.0, -0.005, 0.005, -0.002][shape]
        let bow = [0.22, 0.26, 0.16, 0.20, 0.20, 0.34][shape]
        let upper = closed([(cx - half, y + corner), (cx - half * 0.52, y - lh * 0.62), (cx - half * 0.16, y - lh * 0.92), (cx, y - lh * (0.92 - bow)),
                            (cx + half * 0.16, y - lh * 0.92), (cx + half * 0.52, y - lh * 0.62), (cx + half, y + corner),
                            (cx + half * 0.4, y + 0.003), (cx, y + 0.005), (cx - half * 0.4, y + 0.003)])
        let lower = closed([(cx - half * 0.94, y + corner + 0.002), (cx - half * 0.4, y + 0.004), (cx, y + 0.006), (cx + half * 0.4, y + 0.004),
                            (cx + half * 0.94, y + corner + 0.002), (cx + half * 0.56, y + lh * 0.92), (cx, y + lh * 1.22),
                            (cx - half * 0.56, y + lh * 0.92)])
        fill(&ctx, lower, ink.lip.shade(1.06))
        fill(&ctx, upper, ink.lip.shade(0.80))
        var c = clipped(ctx, to: lower)
        fill(&c, ellipse(cx - half * 0.18, y + lh * 0.55, half * 0.32, lh * 0.26), ArtRGB(1, 1, 1, 0.22))
        fill(&c, Path(CGRect(x: cx + half * 0.30, y: y - 0.05, width: 0.3, height: 0.2)), ink.deep.opacity(0.28))
        fill(&ctx, open([(cx - half, y + corner), (cx - half * 0.4, y + 0.003), (cx, y + 0.005), (cx + half * 0.4, y + 0.003), (cx + half, y + corner)],
                        width: 0.006), ink.deep.shade(0.75))
        // The shadow under the lower lip.
        fill(&ctx, ellipse(cx + 0.006, y + lh * 1.55 + 0.004, half * 0.50, 0.008), ink.shadow.opacity(0.55))
    }

    func eye(_ ctx: inout GraphicsContext, _ side: Double) {
        let shape = g.eyeShape % 6
        let e = l.eyeCenter(side), w = l.eyeWidth / 2, h = l.eyeHeight / 2
        let tilt = [0.0, 0.0, 0.0, -0.007, 0.007, 0.0][shape]
        let inner = CGPoint(x: e.x - side * w, y: e.y + 0.003 - tilt * 0.3), outer = CGPoint(x: e.x + side * w, y: e.y + tilt)
        var almond = Path()
        almond.move(to: inner)
        almond.addQuadCurve(to: outer, control: CGPoint(x: e.x - side * w * 0.10, y: e.y - h * 2.05))
        almond.addQuadCurve(to: inner, control: CGPoint(x: e.x + side * w * 0.10, y: e.y + h * 1.55))
        almond.closeSubpath()
        // The white of the eye is toned to the skin, so it never glows out of a dark face.
        let white = ArtRGB(0.93, 0.92, 0.90).mix(ink.mid, 0.10 + 0.22 * (1 - ink.skinLuminance))
        fill(&ctx, almond, side < 0 ? white : white.shade(0.90))
        var c = clipped(ctx, to: almond)
        let r = l.eyeWidth * 0.235, iy = e.y - h * 0.24
        fill(&c, ellipse(e.x, iy, r, r), ink.iris.shade(0.62))
        fill(&c, ellipse(e.x, iy + r * 0.12, r * 0.80, r * 0.80), ink.iris)
        fill(&c, ellipse(e.x, iy, r * 0.42, r * 0.42), ArtRGB(0.04, 0.04, 0.05))
        fill(&c, ellipse(e.x - r * 0.38, iy - r * 0.10, r * 0.22, r * 0.22), ArtRGB(1, 1, 1, 0.80))
        // The lid's shadow on the eyeball; heavier on a hooded eye.
        fill(&c, Path(CGRect(x: e.x - w, y: e.y - h * 2.2, width: w * 2, height: h * (shape == 2 ? 1.75 : 1.40))), ArtRGB(0.08, 0.05, 0.05, 0.34))
        // The upper lash line, the crease above it and a soft lower lid.
        var lash = Path()
        lash.move(to: inner)
        lash.addQuadCurve(to: outer, control: CGPoint(x: e.x - side * w * 0.10, y: e.y - h * 2.05))
        fill(&ctx, ArtGeometry.stroke(lash, width: 0.009), ink.browColor.shade(0.55))
        let lift = shape == 2 ? 0.55 : 1.0
        fill(&ctx, open([(inner.x + side * w * 0.20, e.y - h * 1.25 * lift - 0.006), (e.x, e.y - h * 1.75 * lift - 0.008),
                         (outer.x - side * w * 0.05, e.y - h * 0.95 * lift - 0.004 + tilt)], width: 0.005), ink.deep.opacity(0.55))
        var under = Path()
        under.move(to: CGPoint(x: inner.x + side * w * 0.25, y: e.y + h * 0.80))
        under.addQuadCurve(to: CGPoint(x: outer.x, y: outer.y + 0.002), control: CGPoint(x: e.x + side * w * 0.2, y: e.y + h * 1.40))
        fill(&ctx, ArtGeometry.stroke(under, width: 0.004), ink.deep.opacity(0.40))
    }

    func brow(_ ctx: inout GraphicsContext, _ side: Double) {
        let shape = g.browShape % 5
        let e = l.eyeCenter(side), w = l.eyeWidth, y = l.browY
        let thick = [0.013, 0.012, 0.011, 0.014, 0.018][shape] * (g.age == 2 ? 1.1 : 1)
        let arch = [0.002, 0.008, 0.014, -0.004, 0.001][shape]
        let innerDrop = shape == 3 ? 0.010 : 0.002
        let inner = (e.x - side * w * 0.58, y + innerDrop), peak = (e.x + side * w * 0.14, y - arch), tail = (e.x + side * w * 0.66, y + 0.008 - arch * 0.2)
        let path = closed([(inner.0, inner.1 - thick * 0.50), (peak.0, peak.1 - thick * 0.55), (tail.0, tail.1 - thick * 0.10),
                           (peak.0, peak.1 + thick * 0.40), (inner.0, inner.1 + thick * 0.50)])
        fill(&ctx, path, ink.browColor.opacity(ink.hair.r > 0.8 ? 0.80 : 0.94))
    }

    func ageLines(_ ctx: inout GraphicsContext) {
        guard g.age > 0 else { return }
        let strength = g.age == 2 ? 0.50 : 0.26
        for side in [-1.0, 1.0] {
            let x = cx + side * l.noseHalf * 1.12
            fill(&ctx, open([(x, l.noseBaseY - 0.012), (x + side * 0.014, l.mouthY - 0.012), (x + side * 0.020, l.mouthY + 0.014)], width: 0.005),
                 ink.deep.opacity(strength))
        }
        guard g.age == 2 else { return }
        for i in 0..<2 {
            let y = l.browY - 0.045 - Double(i) * 0.022
            fill(&ctx, open([(cx - 0.085, y + 0.003), (cx - 0.02, y - 0.002), (cx + 0.07, y + 0.003)], width: 0.004), ink.deep.opacity(0.34))
        }
        for side in [-1.0, 1.0] {
            let e = l.eyeCenter(side)
            let x = e.x + side * l.eyeWidth * 0.60
            fill(&ctx, open([(x, e.y + 0.002), (x + side * 0.020, e.y - 0.006)], width: 0.003), ink.deep.opacity(0.40))
            fill(&ctx, open([(x, e.y + 0.008), (x + side * 0.020, e.y + 0.012)], width: 0.003), ink.deep.opacity(0.40))
            fill(&ctx, open([(e.x - l.eyeWidth * 0.36, e.y + l.eyeHeight * 0.95), (e.x, e.y + l.eyeHeight * 1.18),
                             (e.x + l.eyeWidth * 0.36, e.y + l.eyeHeight * 0.95)], width: 0.004), ink.deep.opacity(0.30))
        }
    }
}

/// ART-FACE: the drawing entry point shared by the view, the sheets and the tests.
public enum PortraitRenderer {
    public static func draw(_ ctx: inout GraphicsContext, genome: PortraitGenome, in rect: CGRect) {
        PortraitPainter(genome: genome, rect: rect).draw(&ctx)
    }
}
