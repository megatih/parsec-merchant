// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// The drawing code of `ShipArt` (ART-015…019).
enum ShipRenderer {
    /// `sparks: false` draws a powerless ship without the spark marks (the wreck of ART-086).
    static func draw(_ ctx: inout GraphicsContext, size: CGSize, model: ShipArtModel, input: ShipArtInput, mode: ShipScaleMode,
                     ink: ArtInk, sparks: Bool = true) {
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
        let livery = model.blueprint.livery
        if !input.disabled { drawPlumes(&ctx, g: g, t: t, unit: unit, input: input, ink: ink, livery: livery) }
        drawNozzles(&ctx, g: g, t: t, unit: unit, ink: ink, organic: model.blueprint.organicSeed != nil)
        drawParts(&ctx, g: g, t: t, box: box, unit: unit, input: input, ink: ink, livery: livery)
        let hull = g.silhouette.applying(t)
        drawShading(&ctx, g: g, hull: hull, t: t, box: box, unit: unit, glass: model.blueprint.isGlassHull)
        // A hull has no drawn outline: only a thin dark edge that reads as shadow (the contrast outline under Increase Contrast).
        let edge = a11y.increaseContrast ? ink(.outline) : ArtRGB(0.05, 0.06, 0.09, 0.7).color
        ctx.stroke(hull, with: .color(edge), lineWidth: max(0.5, unit * 0.004) * a11y.outlineScale)
        drawScorch(&ctx, model: model, t: t, hull: hull, input: input, ink: ink)
        if !input.disabled { drawLights(&ctx, g: g, t: t, unit: unit) }
        if input.disabled, sparks { drawSparks(&ctx, box: box, ink: ink) }
        if let shield = input.shield, shield.fraction > 0 { drawShield(&ctx, box: box, shield: shield, a11y: a11y, ink: ink) }
    }

    // MARK: Engines (ART-016)

    /// The glow intensity: a 0.4 s flicker of ±12%, steady under Reduce Motion.
    static func glowIntensity(phase: Double, reduceMotion: Bool) -> Double {
        reduceMotion ? 1 : 1 + 0.12 * sin(2 * .pi * phase / 0.4)
    }

    /// ART-016: a bloom plume aft of each engine: a soft tail and a bright core.
    private static func drawPlumes(_ ctx: inout GraphicsContext, g: ShipGeometry, t: CGAffineTransform, unit: Double, input: ShipArtInput,
                                   ink: ArtInk, livery: Livery) {
        let k = glowIntensity(phase: input.phase, reduceMotion: input.accessibility.reduceMotion)
        let glow = ink.rgb(livery.glow)
        let aft: Double = t.a < 0 ? 1 : -1 // view-space direction of "astern"
        for e in g.glows {
            let c = CGPoint(x: e.x, y: 0.5 + e.yOffset).applying(t)
            let r = e.radius * unit
            if e.radius > 0.1 {
                // A body glow (the space monster's bioluminescence), not an exhaust.
                let br = r * 1.8 * k
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - br, y: c.y - br, width: 2 * br, height: 2 * br)),
                         with: .radialGradient(Gradient(colors: [glow.opacity(min(1, 0.9 * k)).color, glow.opacity(0.3 * k).color, glow.opacity(0).color]),
                                               center: c, startRadius: 0, endRadius: br))
                continue
            }
            // The tail: a radial gradient stretched astern.
            var tail = ctx
            tail.translateBy(x: c.x, y: c.y)
            tail.scaleBy(x: 3.4 * k, y: 1)
            let tr = r * 1.25
            tail.fill(Path(ellipseIn: CGRect(x: aft > 0 ? 0 : -tr * 1.0, y: -tr, width: tr * 1.0, height: 2 * tr)),
                      with: .radialGradient(Gradient(colors: [glow.opacity(min(1, 0.85 * k)).color, glow.opacity(0.3 * k).color, glow.opacity(0).color]),
                                            center: .zero, startRadius: 0, endRadius: tr))
            let core = r * 0.75 * k
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - core + aft * r * 0.5, y: c.y - core * 0.7, width: 2 * core, height: core * 1.4)),
                     with: .radialGradient(Gradient(colors: [ArtRGB(1, 1, 1, min(1, 0.95 * k)).color, glow.opacity(0.7 * k).color, glow.opacity(0).color]),
                                           center: CGPoint(x: c.x + aft * r * 0.5, y: c.y), startRadius: 0, endRadius: core))
        }
    }

    /// ART-016: a dark nozzle bell at each engine mount.
    private static func drawNozzles(_ ctx: inout GraphicsContext, g: ShipGeometry, t: CGAffineTransform, unit: Double, ink: ArtInk, organic: Bool) {
        guard !organic else { return }
        let aft: Double = t.a < 0 ? 1 : -1
        for e in g.glows where e.radius <= 0.1 {
            let c = CGPoint(x: e.x, y: 0.5 + e.yOffset).applying(t)
            let r = e.radius * unit
            let bell = CGRect(x: min(c.x, c.x + aft * r * 0.9) - r * 0.2, y: c.y - r * 0.95, width: r * 1.3, height: r * 1.9)
            ctx.fill(Path(roundedRect: bell, cornerRadius: r * 0.3),
                     with: .linearGradient(Gradient(colors: [ink.rgb(.steel).shade(0.9).color, ink.rgb(.nightBlack).color]),
                                           startPoint: CGPoint(x: bell.midX, y: bell.minY), endPoint: CGPoint(x: bell.midX, y: bell.maxY)))
        }
    }

    // MARK: Parts (ART-015: one light, from the upper left, in both facings)

    private static func color(_ role: ShipPart.Role, livery: Livery, ink: ArtInk) -> ArtRGB {
        switch role {
        case .primary: ink.rgb(livery.primary)
        case .secondary: ink.rgb(livery.secondary)
        case .accent: ink.rgb(livery.accent)
        case .glass: ink.rgb(.glassTint)
        case .cockpit: ArtRGB(0.10, 0.16, 0.26)
        case .glow: ink.rgb(livery.glow)
        case .cork: ink.rgb(.cork)
        case .parchment: ink.rgb(.parchment)
        case .dark: ink.rgb(livery.secondary).shade(0.55)
        }
    }

    private static func drawParts(_ ctx: inout GraphicsContext, g: ShipGeometry, t: CGAffineTransform, box: CGRect, unit: Double,
                                  input: ShipArtInput, ink: ArtInk, livery: Livery) {
        let a11y = input.accessibility
        for part in g.parts {
            var c = color(part.role, livery: livery, ink: ink)
            if input.disabled { c = c.saturation(0.3).shade(0.8) }
            let path = part.path.applying(t)
            if let w = part.lineWidth {
                ctx.stroke(path, with: .color(c.opacity(0.55).color), style: StrokeStyle(lineWidth: max(0.4, w * unit), lineCap: .round))
                continue
            }
            if part.role == .glass {
                if !a11y.reduceTransparency {
                    ctx.fill(path, with: .linearGradient(Gradient(colors: [c.shade(1.4).color, c.color]), startPoint: CGPoint(x: box.minX, y: box.minY),
                                                         endPoint: CGPoint(x: box.maxX, y: box.maxY)))
                }
                ctx.stroke(path, with: .color(c.opacity(1 / max(0.01, c.a)).shade(0.8).color), lineWidth: max(0.7, unit * 0.008) * a11y.outlineScale)
                continue
            }
            if part.role == .glow {
                ctx.fill(path, with: .color(input.disabled ? c.color : c.shade(1.15).color))
                continue
            }
            let b = path.boundingRect
            if part.role == .cockpit {
                // Glass: dark at the sill, a cool reflection towards the light, and a glint.
                ctx.fill(path, with: .linearGradient(Gradient(colors: [ArtRGB(0.50, 0.72, 0.90).color, c.color, c.shade(0.6).color]),
                                                     startPoint: CGPoint(x: b.minX, y: b.minY), endPoint: CGPoint(x: b.maxX, y: b.maxY)))
                let glint = CGRect(x: b.minX + b.width * 0.18, y: b.minY + b.height * 0.14, width: b.width * 0.34, height: b.height * 0.22)
                ctx.fill(Path(ellipseIn: glint), with: .color(.white.opacity(0.55)))
                ctx.stroke(path, with: .color(ArtRGB(0.05, 0.06, 0.09, 0.6).color), lineWidth: max(0.4, unit * 0.004))
                continue
            }
            // Plating: each part is lit across its own depth, top (towards the light) to bottom.
            ctx.fill(path, with: .linearGradient(Gradient(stops: [.init(color: c.shade(1.32).color, location: 0),
                                                                   .init(color: c.shade(1.06).color, location: 0.3),
                                                                   .init(color: c.shade(0.88).color, location: 0.62),
                                                                   .init(color: c.shade(0.52).color, location: 1)]),
                                                 startPoint: CGPoint(x: b.minX + b.width * 0.35, y: b.minY),
                                                 endPoint: CGPoint(x: b.minX + b.width * 0.65, y: b.maxY)))
            ctx.stroke(path, with: .color(ArtRGB(0.05, 0.06, 0.09, 0.35).color), lineWidth: max(0.3, unit * 0.0025))
        }
    }

    /// D6: edge occlusion darkening inside the outline and a specular strip along the lit flank of the hull.
    private static func drawShading(_ ctx: inout GraphicsContext, g: ShipGeometry, hull: Path, t: CGAffineTransform, box: CGRect, unit: Double,
                                    glass: Bool) {
        guard !glass else { return }
        var inner = ctx
        inner.clip(to: hull)
        for (width, alpha) in [(0.05, 0.10), (0.03, 0.12), (0.014, 0.16)] {
            inner.stroke(hull, with: .color(.black.opacity(alpha)), lineWidth: max(1, unit * width))
        }
        var strip = ctx
        let body = g.hull.applying(t)
        strip.clip(to: body)
        let hb = body.boundingRect
        strip.fill(Path(hb), with: .linearGradient(Gradient(stops: [.init(color: .white.opacity(0), location: 0.10),
                                                                    .init(color: .white.opacity(0.34), location: 0.24),
                                                                    .init(color: .white.opacity(0), location: 0.40)]),
                                                   startPoint: CGPoint(x: hb.midX, y: hb.minY), endPoint: CGPoint(x: hb.midX, y: hb.maxY)))
    }

    /// ART-016: navigation lights: red to port, green to starboard, white at the tail.
    private static func drawLights(_ ctx: inout GraphicsContext, g: ShipGeometry, t: CGAffineTransform, unit: Double) {
        for light in g.lights {
            let c = light.position.applying(t)
            let tint: ArtRGB = switch light.kind {
            case .port: ArtRGB(1.0, 0.20, 0.16)
            case .starboard: ArtRGB(0.20, 1.0, 0.36)
            case .tail: ArtRGB(1, 1, 1)
            }
            let r = max(1.4, unit * 0.022)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                     with: .radialGradient(Gradient(colors: [tint.opacity(0.9).color, tint.opacity(0.25).color, tint.opacity(0).color]),
                                           center: c, startRadius: 0, endRadius: r))
            let core = max(0.6, r * 0.28)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - core, y: c.y - core, width: 2 * core, height: 2 * core)), with: .color(.white.opacity(0.95)))
        }
    }

    // MARK: Scorch (ART-018)

    private static func drawScorch(_ ctx: inout GraphicsContext, model: ShipArtModel, t: CGAffineTransform, hull: Path,
                                   input: ShipArtInput, ink: ArtInk) {
        guard input.hullFraction < 1 else { return }
        let scorch = model.scorch.revealed(hullFraction: input.hullFraction).applying(t)
        var c = ctx
        c.clip(to: hull)
        // The mask's cells are the contract (ART-018); they are drawn as soft burns, not as squares.
        let soften = max(0.8, hull.boundingRect.width * 0.012)
        c.drawLayer { layer in
            layer.addFilter(.blur(radius: soften))
            layer.fill(scorch, with: .color(ink(.scorch).opacity(0.9)))
        }
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
        // A bubble, not a disc: thin in the middle, denser towards the rim, with a highlight on the lit side.
        let rect = bubbleRect(box), opacity = 0.12 + 0.40 * shield.fraction
        var b = ctx
        b.translateBy(x: rect.midX, y: rect.midY)
        b.scaleBy(x: 1, y: rect.height / rect.width)
        let r = rect.width / 2
        b.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)),
               with: .radialGradient(Gradient(stops: [.init(color: tint.opacity(opacity * 0.35).color, location: 0),
                                                      .init(color: tint.opacity(opacity * 0.6).color, location: 0.7),
                                                      .init(color: tint.opacity(min(1, opacity * 1.5)).color, location: 1)]),
                                     center: .zero, startRadius: 0, endRadius: r))
        b.fill(Path(ellipseIn: CGRect(x: -r * 0.75, y: -r * 0.8, width: r * 0.8, height: r * 0.5)),
               with: .radialGradient(Gradient(colors: [.white.opacity(0.22 * shield.fraction), .white.opacity(0)]),
                                     center: CGPoint(x: -r * 0.35, y: -r * 0.55), startRadius: 0, endRadius: r * 0.45))
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
