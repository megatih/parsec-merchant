// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// The drawing code of `ShipArt` (ART-015…019).
enum ShipRenderer {
    static func draw(_ ctx: inout GraphicsContext, size: CGSize, model: ShipArtModel, input: ShipArtInput, mode: ShipScaleMode,
                     ink: ArtInk) {
        guard input.hullFraction > 0 else { return } // ART-018: destroyed ships are replaced by the explosion effect.
        let g = model.geometry
        let t = ShipArtLayout.transform(bounds: g.bounds, size: size, mode: mode, sizeClass: input.sizeClass, facing: input.facing)
        let box = g.bounds.applying(t)
        let a11y = input.accessibility
        let unit = abs(t.a) // view points per unit
        if input.cloaked {
            ctx.opacity = 0.35
            ctx.stroke(g.silhouette.applying(t), with: .color(ink(.outline)),
                       style: StrokeStyle(lineWidth: 1.2 * a11y.outlineScale, dash: [4, 3]))
            return
        }
        if !input.disabled { drawGlow(&ctx, g: g, t: t, unit: unit, input: input, ink: ink, livery: model.blueprint.livery) }
        drawParts(&ctx, g: g, t: t, box: box, unit: unit, input: input, ink: ink, livery: model.blueprint.livery)
        let hull = g.silhouette.applying(t)
        ctx.stroke(hull, with: .color(ink(.outline).opacity(0.85)), lineWidth: max(0.6, unit * 0.006) * a11y.outlineScale)
        drawScorch(&ctx, model: model, t: t, hull: hull, input: input, ink: ink)
        if input.disabled { drawSparks(&ctx, box: box, ink: ink) }
        if let shield = input.shield, shield.fraction > 0 { drawShield(&ctx, box: box, shield: shield, a11y: a11y, ink: ink) }
    }

    // MARK: Glow (ART-016)

    /// The glow intensity: a 0.4 s flicker of ±12%, steady under Reduce Motion.
    static func glowIntensity(phase: Double, reduceMotion: Bool) -> Double {
        reduceMotion ? 1 : 1 + 0.12 * sin(2 * .pi * phase / 0.4)
    }

    private static func drawGlow(_ ctx: inout GraphicsContext, g: ShipGeometry, t: CGAffineTransform, unit: Double, input: ShipArtInput,
                                 ink: ArtInk, livery: Livery) {
        let k = glowIntensity(phase: input.phase, reduceMotion: input.accessibility.reduceMotion)
        let glow = ink.rgb(livery.glow)
        for e in g.glows {
            let c = CGPoint(x: e.x, y: 0.5 + e.yOffset).applying(t)
            let r = e.radius * unit * 1.8 * k
            let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
            ctx.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(colors: [glow.opacity(min(1, 0.95 * k)).color,
                                                                                     glow.opacity(0.35 * k).color, glow.opacity(0).color]),
                                                                  center: c, startRadius: 0, endRadius: r))
        }
    }

    // MARK: Parts (ART-015 light from the top left in both facings)

    private static func color(_ role: ShipPart.Role, livery: Livery, ink: ArtInk) -> ArtRGB {
        switch role {
        case .primary: ink.rgb(livery.primary)
        case .secondary: ink.rgb(livery.secondary)
        case .accent: ink.rgb(livery.accent)
        case .glass: ink.rgb(.glassTint)
        case .cockpit: ink.rgb(.iridescentBlue).mix(ink.rgb(.highlight), 0.25)
        case .glow: ink.rgb(livery.glow)
        case .cork: ink.rgb(.cork)
        case .parchment: ink.rgb(.parchment)
        case .dark: ink.rgb(livery.secondary).shade(0.6)
        }
    }

    private static func drawParts(_ ctx: inout GraphicsContext, g: ShipGeometry, t: CGAffineTransform, box: CGRect, unit: Double,
                                  input: ShipArtInput, ink: ArtInk, livery: Livery) {
        let a11y = input.accessibility
        let light = CGPoint(x: box.minX, y: box.minY), dark = CGPoint(x: box.maxX, y: box.maxY)
        for part in g.parts {
            var c = color(part.role, livery: livery, ink: ink)
            if input.disabled { c = c.saturation(0.3).shade(0.8) }
            let path = part.path.applying(t)
            if let w = part.lineWidth {
                ctx.stroke(path, with: .color(c.color), style: StrokeStyle(lineWidth: max(0.5, w * unit), lineCap: .round))
                continue
            }
            if part.role == .glass {
                if !a11y.reduceTransparency {
                    ctx.fill(path, with: .linearGradient(Gradient(colors: [c.shade(1.4).color, c.color]), startPoint: light, endPoint: dark))
                }
                ctx.stroke(path, with: .color(c.opacity(1 / max(0.01, c.a)).shade(0.8).color), lineWidth: max(0.7, unit * 0.008) * a11y.outlineScale)
                continue
            }
            if part.role == .glow {
                ctx.fill(path, with: .color(input.disabled ? c.color : c.shade(1.15).color))
                continue
            }
            ctx.fill(path, with: .linearGradient(Gradient(colors: [c.shade(1.3).color, c.color, c.shade(0.62).color]),
                                                 startPoint: light, endPoint: dark))
        }
        // A soft highlight on the upper-left of the hull (not mirrored with the geometry).
        var hctx = ctx
        hctx.clip(to: g.hull.applying(t))
        let hr = CGRect(x: box.minX + box.width * 0.15, y: box.minY + box.height * 0.18, width: box.width * 0.45, height: box.height * 0.22)
        hctx.fill(Path(ellipseIn: hr), with: .radialGradient(Gradient(colors: [.white.opacity(0.35), .white.opacity(0)]),
                                                              center: CGPoint(x: hr.midX, y: hr.midY), startRadius: 0, endRadius: hr.width / 2))
    }

    // MARK: Scorch (ART-018)

    private static func drawScorch(_ ctx: inout GraphicsContext, model: ShipArtModel, t: CGAffineTransform, hull: Path,
                                   input: ShipArtInput, ink: ArtInk) {
        guard input.hullFraction < 1 else { return }
        let scorch = model.scorch.revealed(hullFraction: input.hullFraction).applying(t)
        var c = ctx
        c.clip(to: hull)
        c.fill(scorch, with: .color(ink(.scorch).opacity(0.82)))
        if input.accessibility.differentiateWithoutColor {
            c.clip(to: scorch)
            let b = hull.boundingRect
            var hatch = Path()
            var x = b.minX - b.height
            while x < b.maxX {
                hatch.move(to: CGPoint(x: x, y: b.maxY))
                hatch.addLine(to: CGPoint(x: x + b.height, y: b.minY))
                x += 4
            }
            c.stroke(hatch, with: .color(ink(.highlight).opacity(0.7)), lineWidth: 0.8)
        }
    }

    // MARK: Disabled (ART-019)

    private static func drawSparks(_ ctx: inout GraphicsContext, box: CGRect, ink: ArtInk) {
        for (fx, fy) in [(0.38, 0.32), (0.66, 0.62)] {
            let c = CGPoint(x: box.minX + box.width * fx, y: box.minY + box.height * fy)
            let r = max(3, min(box.width, box.height) * 0.12)
            ctx.fill(ArtGeometry.star(center: c, points: 4, outer: r, inner: r * 0.25), with: .color(ink(.spark)))
        }
    }

    // MARK: Shield (ART-017)

    static func bubbleRect(_ box: CGRect) -> CGRect {
        box.insetBy(dx: -box.width * 0.06, dy: -box.height * 0.06)
    }

    private static func drawShield(_ ctx: inout GraphicsContext, box: CGRect, shield: ShieldDisplay, a11y: ArtAccessibility, ink: ArtInk) {
        let token: ArtToken = switch shield.kind {
        case .energy: .shieldEnergy
        case .reflective: .shieldReflective
        case .lightning: .shieldLightning
        }
        let tint = ink.rgb(token)
        let bubble = Path(ellipseIn: bubbleRect(box))
        if a11y.reduceTransparency {
            ctx.stroke(bubble, with: .color(tint.color), lineWidth: 1 + 3 * shield.fraction)
            return
        }
        ctx.fill(bubble, with: .color(tint.opacity(0.12 + 0.40 * shield.fraction).color))
        if a11y.differentiateWithoutColor {
            let circumference = Double.pi * (bubbleRect(box).width + bubbleRect(box).height) / 2
            let dashes = max(2, Int((shield.fraction * 24).rounded()))
            let seg = circumference / Double(dashes)
            ctx.stroke(bubble, with: .color(tint.color), style: StrokeStyle(lineWidth: 1.5 * a11y.outlineScale, dash: [seg * 0.6, seg * 0.4]))
        } else {
            ctx.stroke(bubble, with: .color(tint.color), lineWidth: 1.2 * a11y.outlineScale)
        }
    }
}
