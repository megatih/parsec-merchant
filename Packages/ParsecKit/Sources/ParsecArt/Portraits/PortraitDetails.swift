// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// ART-FACE: hair, facial hair, attire, insignia and marks.
extension PortraitPainter {
    // MARK: Hair

    /// The hair that sits on the skull: an outer contour `pad` outside the head down to `sideY`, and a hairline.
    /// `hairline` lists (x as a share of the cranium half width, y offset from the default hairline), left to right.
    func cap(pad: Double, sideY: Double, hairline: [(Double, Double)]) -> Path {
        let c = l.craniumHalf, line = top + 0.120
        var points: [SplinePoint] = [
            SplinePoint(cx - c - pad * 0.5, sideY, sharp: true), SplinePoint(cx - c - pad, top + 0.16),
                SplinePoint(cx - c * 0.66 - pad * 0.8, top + 0.035 - pad * 0.6),
            SplinePoint(cx, top - pad * 1.1), SplinePoint(cx + c * 0.66 + pad * 0.8, top + 0.035 - pad * 0.6), SplinePoint(cx + c + pad, top + 0.16),
            SplinePoint(cx + c + pad * 0.5, sideY, sharp: true), SplinePoint(cx + c - 0.016, sideY - 0.004, sharp: true),
            SplinePoint(cx + c * 0.86, line + 0.050),
        ]
        points += hairline.reversed().map { SplinePoint(cx + $0.0 * c, line + $0.1) }
        points += [SplinePoint(cx - c * 0.86, line + 0.050), SplinePoint(cx - c + 0.016, sideY - 0.004, sharp: true)]
        return ArtGeometry.closedSpline(points)
    }

    /// Paints a hair mass with a lit band on the near side and a darker far side.
    func paintHair(_ ctx: inout GraphicsContext, _ path: Path, opacity: Double = 1) {
        fill(&ctx, path, ink.hair.opacity(opacity))
        var c = clipped(ctx, to: path)
        gradient(&c, Path(CGRect(x: 0, y: -0.2, width: 1, height: 1.4)), ArtRGB(0, 0, 0, 0), ArtRGB(0, 0, 0, 0.42 * opacity),
                 from: (cx - 0.04, 0.3), to: (cx + l.craniumHalf + 0.06, 0.3))
        let lum = 0.299 * ink.hair.r + 0.587 * ink.hair.g + 0.114 * ink.hair.b
        fill(&c, open([(cx - l.craniumHalf * 0.92, top + 0.13), (cx - l.craniumHalf * 0.62, top + 0.035), (cx - l.craniumHalf * 0.16, top - 0.004)],
                      width: 0.030), ArtRGB(1, 1, 1, (lum > 0.5 ? 0.30 : 0.16) * opacity))
    }

    func hairBack(_ ctx: inout GraphicsContext) {
        let c = l.craniumHalf
        var path: Path?
        switch g.hairStyle % 14 {
        case 7: // Bob: to the jaw.
            path = closed([(cx - c - 0.030, top + 0.10), (cx - c - 0.040, l.eyeY + 0.06), (cx - c - 0.025, l.chinY - 0.03), (cx - c + 0.03, l.chinY - 0.01),
                           (cx + c - 0.03, l.chinY - 0.01), (cx + c + 0.025, l.chinY - 0.03), (cx + c + 0.040, l.eyeY + 0.06), (cx + c + 0.030, top + 0.10),
                           (cx, top - 0.02)])
        case 8: // Long: to the shoulders.
            path = closed([(cx - c - 0.028, top + 0.10), (cx - c - 0.042, l.eyeY + 0.08), (cx - c - 0.050, 0.80), (cx - c - 0.01, 0.90), (cx - 0.05, 0.86),
                           (cx + 0.05, 0.86), (cx + c + 0.01, 0.90), (cx + c + 0.050, 0.80), (cx + c + 0.042, l.eyeY + 0.08), (cx + c + 0.028, top + 0.10),
                           (cx, top - 0.02)])
        case 9: // Tied back: a tail over the far shoulder.
            path = closed([(cx + c - 0.03, top + 0.16), (cx + c + 0.030, l.eyeY + 0.02), (cx + c + 0.050, 0.76), (cx + c + 0.030, 0.90),
                           (cx + c - 0.010, 0.86), (cx + c + 0.002, 0.74), (cx + c - 0.03, l.eyeY + 0.10)])
        case 6: // Full, tightly curled hair: a rounded mass that hugs the skull.
            path = ellipse(cx, top + 0.105, c * 1.13, 0.150)
        default: break
        }
        if let path { paintHair(&ctx, path) }
    }

    func hairFront(_ ctx: inout GraphicsContext) {
        let c = l.craniumHalf, ear = l.eyeY - 0.015
        let straight: [(Double, Double)] = [(-0.66, 0.012), (-0.22, 0.0), (0.22, 0.0), (0.66, 0.012)]
        let high: [(Double, Double)] = [(-0.68, -0.004), (-0.26, -0.024), (0.26, -0.024), (0.68, -0.004)]
        switch g.hairStyle % 14 {
        case 0: // Bald: a sheen on the scalp.
            var s = clipped(ctx, to: l.head)
            fill(&s, ellipse(cx - 0.05, top + 0.055, 0.070, 0.028), ink.light.shade(1.3).opacity(0.35))
        case 1: // Buzz cut: the scalp shows through.
            paintHair(&ctx, cap(pad: 0.004, sideY: ear - 0.035, hairline: [(-0.62, 0.010), (0, -0.004), (0.62, 0.010)]), opacity: 0.62)
        case 2: // Short crop.
            paintHair(&ctx, cap(pad: 0.014, sideY: ear, hairline: straight))
        case 3: // Side part with a fringe swept across.
            paintHair(&ctx, cap(pad: 0.018, sideY: ear + 0.01, hairline: [(-0.70, 0.030), (-0.46, -0.030), (-0.10, 0.006), (0.36, 0.036), (0.72, 0.042)]))
            fill(&ctx, open([(cx - c * 0.46, top + 0.075), (cx - c * 0.40, top + 0.02)], width: 0.005), ArtRGB(0, 0, 0, 0.26))
        case 4: // Swept back.
            paintHair(&ctx, cap(pad: 0.024, sideY: ear, hairline: [(-0.70, -0.004), (-0.3, -0.028), (0.3, -0.028), (0.70, -0.004)]))
        case 5: // Short curls: a soft, slightly uneven crown.
            var path = cap(pad: 0.016, sideY: ear - 0.02, hairline: [(-0.66, 0.016), (-0.22, 0.020), (0.22, 0.016), (0.66, 0.020)])
            for i in 0..<7 {
                let a = (Double(i) + 0.5) / 7
                path = path.union(ellipse(cx - c * 0.74 + a * c * 1.48, top + 0.030 - sin(a * .pi) * 0.036, 0.040, 0.030))
            }
            paintHair(&ctx, path)
        case 6: // Full curls: the front of the mass.
            paintHair(&ctx, cap(pad: 0.026, sideY: ear + 0.005, hairline: [(-0.70, 0.006), (-0.25, -0.010), (0.25, -0.010), (0.70, 0.006)]))
        case 7: // Bob with a straight fringe.
            let fringe = l.browY - top - 0.120 - 0.028
            paintHair(&ctx, cap(pad: 0.022, sideY: l.eyeY + 0.05, hairline: [(-0.80, fringe), (-0.3, fringe + 0.006), (0.3, fringe + 0.004), (0.80, fringe)]))
        case 8: // Long with a centre part.
            paintHair(&ctx, cap(pad: 0.020, sideY: l.eyeY + 0.07, hairline: [(-0.78, 0.062), (-0.36, 0.010), (0, -0.036), (0.36, 0.010), (0.78, 0.062)]))
        case 9: // Tied back.
            paintHair(&ctx, cap(pad: 0.012, sideY: ear - 0.01, hairline: high))
        case 10: // A crest: short sides, a longer strip brushed up along the top of the head.
            let crest = closed([(cx - c * 0.34, top + 0.120), (cx - c * 0.40, top + 0.030), (cx - c * 0.24, top - 0.030), (cx, top - 0.040),
                                (cx + c * 0.24, top - 0.030), (cx + c * 0.40, top + 0.030), (cx + c * 0.34, top + 0.120), (cx, top + 0.108)])
            paintHair(&ctx, cap(pad: 0.006, sideY: ear - 0.03, hairline: [(-0.62, 0.008), (0, -0.004), (0.62, 0.008)]).union(crest))
        case 11: // Short back and sides, longer on top.
            paintHair(&ctx, cap(pad: 0.006, sideY: ear - 0.02, hairline: [(-0.62, 0.012), (0, 0.004), (0.62, 0.012)]))
            paintHair(&ctx, closed([(cx - c * 0.84, top + 0.130), (cx - c * 0.92, top + 0.055), (cx - c * 0.52, top - 0.018), (cx, top - 0.030),
                                    (cx + c * 0.52, top - 0.018), (cx + c * 0.92, top + 0.055), (cx + c * 0.84, top + 0.130), (cx + c * 0.30, top + 0.116),
                                    (cx - c * 0.30, top + 0.122)]))
        case 12: // Top knot: tied close on the crown, joined to the hair below.
            paintHair(&ctx, cap(pad: 0.012, sideY: ear - 0.01, hairline: high).union(ellipse(cx, top - 0.012, 0.048, 0.034)))
        default: // Receding.
            paintHair(&ctx, cap(pad: 0.010, sideY: ear, hairline: [(-0.72, 0.022), (-0.50, -0.056), (-0.12, -0.018), (0.12, -0.018), (0.50, -0.056),
                                                                (0.72, 0.022)]))
        }
    }

    // MARK: Facial hair

    func facialHair(_ ctx: inout GraphicsContext) {
        guard g.facialHair > 0 else { return }
        let y = l.mouthY, m = l.mouthHalf, lh = l.lipHeight
        // Facial hair is never paler than the skin's own shadow, or it would read as a mask.
        let color = ink.browColor.mix(ink.deep, ink.hair.r > 0.5 ? 0.45 : 0.10)
        var c = clipped(ctx, to: l.head)
        let jawArea = closed([(cx - l.cheekHalf - 0.02, l.noseBaseY - 0.030), (cx - m * 1.20, y - lh * 1.2), (cx - m * 0.6, l.noseBaseY + 0.018),
                              (cx, l.noseBaseY + 0.012), (cx + m * 0.6, l.noseBaseY + 0.018), (cx + m * 1.20, y - lh * 1.2),
                              (cx + l.cheekHalf + 0.02, l.noseBaseY - 0.030), (cx + l.jawHalf + 0.03, l.chinY), (cx, l.chinY + 0.04),
                              (cx - l.jawHalf - 0.03, l.chinY)])
        // A moustache is two tapered strokes that follow the upper lip.
        func moustache(_ opacity: Double) {
            for side in [-1.0, 1.0] {
                let topY = max(l.noseBaseY + 0.016, y - lh * 1.9)
                fill(&c, closed([(cx + side * 0.002, topY), (cx + side * m * 0.60, y - lh * 1.30), (cx + side * m * 1.14, y - lh * 0.10),
                                 (cx + side * m * 0.62, y - lh * 0.78), (cx + side * 0.002, y - lh * 0.90)]), color.opacity(opacity))
            }
        }
        let chinTuft = closed([(cx - m * 0.46, y + lh * 1.75), (cx, y + lh * 1.50), (cx + m * 0.46, y + lh * 1.75), (cx + m * 0.40, l.chinY - 0.004),
                               (cx, l.chinY + 0.012), (cx - m * 0.40, l.chinY - 0.004)])
        switch g.facialHair {
        case 1: // Stubble: a soft shadow along the jaw, whatever the hair colour.
            c.drawLayer { layer in
                layer.addFilter(.blur(radius: 0.012 * t.a))
                layer.fill(jawArea.applying(t), with: .color(ink.deep.mix(color, 0.3).opacity(0.24).color))
            }
        case 2: moustache(0.94)
        case 3:
            moustache(0.94)
            fill(&c, chinTuft, color.opacity(0.94))
        case 4: // Full beard, darker on the far side.
            fill(&c, jawArea, color.opacity(0.96))
            gradient(&c, jawArea, ArtRGB(0, 0, 0, 0), ArtRGB(0, 0, 0, 0.30), from: (cx - 0.02, 0.6), to: (cx + l.jawHalf, 0.6))
        default: // Short boxed beard.
            fill(&c, jawArea, color.opacity(0.62))
            moustache(0.70)
        }
    }

    // MARK: Attire

    func attire(_ ctx: inout GraphicsContext, base: ArtRGB) {
        let n = neckHalf, dark = ArtRGB(0, 0, 0, 0.45)
        func lapels(width: Double, shirt: ArtRGB) {
            fill(&ctx, GlyphKit.poly([(cx - n * 0.9, 0.79), (cx, 0.955), (cx + n * 0.9, 0.79), (cx, 0.83)]), shirt)
            fill(&ctx, GlyphKit.poly([(cx - n - 0.012, 0.790), (cx - n - width, 0.835), (cx - 0.035, 0.93), (cx - 0.004, 0.955), (cx - n * 0.9, 0.80)]),
                 base.shade(1.32))
            fill(&ctx, GlyphKit.poly([(cx + n + 0.012, 0.790), (cx + n + width, 0.835), (cx + 0.035, 0.93), (cx + 0.004, 0.955), (cx + n * 0.9, 0.80)]),
                 base.shade(0.78))
        }
        switch g.attire % 8 {
        case 0: // Flight jacket.
            lapels(width: 0.075, shirt: ArtRGB(0.80, 0.78, 0.72))
            fill(&ctx, GlyphKit.line([(cx - 0.30, 0.94), (cx - 0.21, 0.94)], width: 0.012), base.shade(0.6))
        case 1: // Crew jumpsuit.
            fill(&ctx, GlyphKit.arc(cx, 0.800, n + 0.022, from: 10, to: 170, width: 0.024), base.shade(0.70))
            fill(&ctx, GlyphKit.line([(cx, 0.845), (cx, 1.02)], width: 0.006), dark)
        case 2: // Armoured collar.
            fill(&ctx, GlyphKit.poly([(cx - n - 0.045, 0.745), (cx - n - 0.030, 0.865), (cx + n + 0.030, 0.865), (cx + n + 0.045, 0.745), (cx + n * 0.5, 0.805),
                                      (cx - n * 0.5, 0.805)]), PortraitInk.steel.shade(0.80))
            fill(&ctx, GlyphKit.poly([(cx - n - 0.045, 0.745), (cx - n - 0.030, 0.865), (cx - 0.004, 0.865), (cx - n * 0.5, 0.805)]), PortraitInk.steel)
            for side in [-1.0, 1.0] {
                fill(&ctx, ellipse(cx + side * 0.30, 0.905, 0.125, 0.048), PortraitInk.steel.shade(side < 0 ? 0.95 : 0.62))
            }
        case 3: // Engineer overalls over a shirt.
            for side in [-1.0, 1.0] {
                fill(&ctx, GlyphKit.poly([(cx + side * 0.13, 0.825), (cx + side * 0.19, 0.845), (cx + side * 0.14, 1.02), (cx + side * 0.08, 1.02)]),
                     ink.attire.shade(side < 0 ? 1.15 : 0.80))
            }
            fill(&ctx, GlyphKit.rect(cx - 0.14, 0.945, 0.28, 0.1), ink.attire)
            fill(&ctx, GlyphKit.arc(cx, 0.800, n + 0.016, from: 15, to: 165, width: 0.014), ArtRGB(0.55, 0.53, 0.48))
        case 4: // Formal high collar.
            fill(&ctx, GlyphKit.rect(cx - n - 0.016, 0.752, n * 2 + 0.032, 0.062, corner: 0.012), base.shade(1.22))
            fill(&ctx, GlyphKit.rect(cx + 0.004, 0.752, n + 0.012, 0.062, corner: 0.012), base.shade(0.82))
            fill(&ctx, GlyphKit.line([(cx, 0.755), (cx, 1.02)], width: 0.005), dark)
            fill(&ctx, ellipse(cx, 0.840, 0.013, 0.013), PortraitInk.brass)
        case 5: // Naval coat with gold shoulder stripes.
            lapels(width: 0.095, shirt: ArtRGB(0.90, 0.90, 0.88))
            for side in [-1.0, 1.0] {
                fill(&ctx, GlyphKit.line([(cx + side * 0.235, 0.868), (cx + side * 0.385, 0.925)], width: 0.014, round: false), PortraitInk.brass)
                fill(&ctx, ellipse(cx + side * 0.075, 0.975, 0.010, 0.010), PortraitInk.brass.shade(side < 0 ? 1 : 0.75))
            }
        case 6: // Scarf.
            let scarf = ink.attire.mix(ArtRGB(0.80, 0.72, 0.55), 0.55)
            let wrap = closed([(cx - n - 0.050, 0.775), (cx - n * 0.3, 0.748), (cx + n * 0.5, 0.752), (cx + n + 0.050, 0.782), (cx + n + 0.040, 0.850),
                               (cx + 0.01, 0.885), (cx - n - 0.040, 0.850)])
            gradient(&ctx, wrap, scarf.shade(1.15), scarf.shade(0.66), from: (cx - 0.12, 0.76), to: (cx + 0.12, 0.88))
            fill(&ctx, open([(cx - n - 0.03, 0.815), (cx, 0.835), (cx + n + 0.03, 0.812)], width: 0.005), dark.opacity(0.5))
        default: // Pressure suit with a neck ring.
            fill(&ctx, GlyphKit.arc(cx, 0.796, n + 0.036, from: 0, to: 360, width: 0.030), PortraitInk.steel.shade(0.72))
            fill(&ctx, GlyphKit.arc(cx, 0.796, n + 0.036, from: 180, to: 300, width: 0.012), ArtRGB(1, 1, 1, 0.55))
            fill(&ctx, ellipse(cx - 0.215, 0.925, 0.022, 0.022), PortraitInk.steel.shade(0.9))
            fill(&ctx, ellipse(cx - 0.215, 0.925, 0.010, 0.010), dark)
        }
    }

    /// The best skill as a brass badge on the chest: wings, chevrons, ledger bars or a cog. It sits where the outfit
    /// leaves the cloth clear: on the bib of overalls, under an armoured collar, otherwise on the far side of the chest.
    func insignia(_ ctx: inout GraphicsContext) {
        let spot: (Double, Double) = switch g.attire % 8 {
        case 3: (cx, 0.964)
        case 2: (cx, 0.945)
        case 5: (cx + 0.185, 0.962)
        default: (cx + 0.225, 0.965)
        }
        let x = spot.0, y = spot.1, brass = PortraitInk.brass, k = 1.25
        switch g.insignia % 4 {
        case 0:
            fill(&ctx, GlyphKit.poly([(x - 0.050 * k, y - 0.012 * k), (x - 0.008 * k, y - 0.004 * k),
                (x - 0.008 * k, y + 0.010 * k), (x - 0.036 * k, y + 0.004 * k)]), brass)
            fill(&ctx, GlyphKit.poly([(x + 0.050 * k, y - 0.012 * k), (x + 0.008 * k, y - 0.004 * k),
                (x + 0.008 * k, y + 0.010 * k), (x + 0.036 * k, y + 0.004 * k)]), brass)
            fill(&ctx, ellipse(x, y, 0.008 * k, 0.010 * k), brass)
        case 1:
            for i in 0..<2 {
                let o = Double(i) * 0.016 * k
                fill(&ctx, GlyphKit.line([(x - 0.028 * k, y - 0.006 * k + o), (x, y - 0.020 * k + o), (x + 0.028 * k, y - 0.006 * k + o)], width: 0.008 * k,
                                         round: false), brass)
            }
        case 2:
            for i in 0..<3 {
                fill(&ctx, GlyphKit.rect(x - 0.030 * k, y - 0.016 * k + Double(i) * 0.012 * k, (0.060 - Double(i) * 0.014) * k, 0.007 * k), brass)
            }
        default:
            fill(&ctx, ArtGeometry.star(center: CGPoint(x: x, y: y), points: 8, outer: 0.024 * k, inner: 0.016 * k), brass)
            fill(&ctx, ellipse(x, y, 0.007 * k, 0.007 * k), ink.attire.shade(0.6))
        }
    }

    // MARK: Marks

    func marks(_ ctx: inout GraphicsContext) {
        switch g.mark {
        case 1: // A scar: one clean line through the near brow and down the cheek.
            let e = l.eyeCenter(-1), w = l.eyeWidth
            let color = ink.light.mix(ArtRGB(0.80, 0.52, 0.52), 0.55)
            fill(&ctx, open([(e.x - w * 0.42, l.browY - 0.030), (e.x - w * 0.36, l.browY + 0.004)], width: 0.006), color)
            fill(&ctx, open([(e.x - w * 0.30, e.y + w * 0.42), (e.x - w * 0.20, e.y + w * 0.90), (e.x - w * 0.16, e.y + w * 1.35)], width: 0.006), color)
        case 2: // Freckles over the nose and cheeks.
            var rng = ArtRandom(seed: UInt64(truncatingIfNeeded: g.skin * 31 + g.noseShape * 7 + g.eyeShape))
            for _ in 0..<22 {
                let x = cx + rng.range(-1...1) * l.cheekHalf * 0.70, y = l.eyeY + 0.035 + rng.range(0...1) * 0.050
                fill(&ctx, ellipse(x, y, 0.0045, 0.0040), ink.deep.opacity(0.42))
            }
        default: break
        }
    }

    /// Things worn over the hair and face: an implant, an eye patch, the Princess's circlet.
    func accessories(_ ctx: inout GraphicsContext) {
        if g.mark == 3 {
            let x = cx + l.craniumHalf * 0.80, y = l.browY - 0.030
            fill(&ctx, GlyphKit.rect(x - 0.026, y - 0.020, 0.046, 0.036, corner: 0.008), PortraitInk.steel.shade(0.78))
            fill(&ctx, GlyphKit.rect(x - 0.026, y - 0.020, 0.046, 0.010, corner: 0.005), ArtRGB(1, 1, 1, 0.35))
            fill(&ctx, ellipse(x - 0.006, y + 0.002, 0.006, 0.006), ArtRGB(0.35, 0.95, 0.90))
            fill(&ctx, GlyphKit.line([(x - 0.024, y + 0.014), (x - 0.050, y + 0.040)], width: 0.004), PortraitInk.steel.shade(0.70))
        }
        if g.mark == 4 {
            let e = l.eyeCenter(-1), w = l.eyeWidth
            fill(&ctx, GlyphKit.line([(cx - l.craniumHalf - 0.01, l.browY - 0.045), (e.x, e.y - 0.004), (cx + l.craniumHalf + 0.01, l.browY - 0.100)],
                                     width: 0.009, round: false), ArtRGB(0.08, 0.08, 0.09))
            fill(&ctx, closed([(e.x - w * 0.72, e.y - w * 0.42), (e.x + w * 0.72, e.y - w * 0.46), (e.x + w * 0.62, e.y + w * 0.36),
                               (e.x, e.y + w * 0.62), (e.x - w * 0.62, e.y + w * 0.36)]), ArtRGB(0.10, 0.10, 0.11))
            fill(&ctx, open([(e.x - w * 0.50, e.y - w * 0.30), (e.x - w * 0.10, e.y - w * 0.34)], width: 0.005), ArtRGB(1, 1, 1, 0.14))
        }
        if g == PortraitGenome.fixed(.princess) {
            let y = top + 0.090, c = l.craniumHalf
            fill(&ctx, open([(cx - c * 0.90, y + 0.030), (cx - c * 0.45, y + 0.002), (cx, y - 0.006), (cx + c * 0.45, y + 0.002), (cx + c * 0.90, y + 0.030)],
                            width: 0.010), PortraitInk.brass)
            fill(&ctx, GlyphKit.poly([(cx, y - 0.026), (cx + 0.014, y - 0.004), (cx, y + 0.016), (cx - 0.014, y - 0.004)]), ArtRGB(0.55, 0.85, 0.95))
        }
    }
}

/// ART-FACE: a character's portrait. The picture is square; the view centres it in its frame.
public struct CharacterPortrait: View {
    public var genome: PortraitGenome

    public init(genome: PortraitGenome) { self.genome = genome }

    /// The portrait of a seed.
    public init(seed: UInt64) { genome = PortraitGenome.make(seed: seed) }

    /// The authored portrait of a special character.
    public init(role: PortraitRole) { genome = PortraitGenome.fixed(role) }

    public var body: some View {
        let genome = genome
        Canvas { ctx, size in
            var c = ctx
            PortraitRenderer.draw(&c, genome: genome, in: CGRect(origin: .zero, size: size))
        }
        .accessibilityHidden(true)
    }
}
