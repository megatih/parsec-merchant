// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// ART-020…026: a procedural planet portrait.
public struct PlanetArt: View {
    public var input: PlanetArtInput
    /// `true`: the disk fills the frame (map mini-planets); `false`: the portrait size rule of ART-023.
    public var fillsFrame: Bool
    @Environment(\.colorScheme) private var scheme

    public init(_ input: PlanetArtInput, fillsFrame: Bool = false) {
        self.input = input
        self.fillsFrame = fillsFrame
    }

    public var body: some View {
        let recipe = PlanetRenderer.recipe(input)
        let input = input, fills = fillsFrame, ink = ArtInk(scheme: scheme, contrast: input.accessibility.increaseContrast)
        Canvas { ctx, size in
            let half = min(size.width, size.height) / 2
            let r = fills ? half : half * recipe.radiusFraction
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            PlanetRenderer.draw(&ctx, recipe: recipe, center: c, radius: r, phase: input.phase, accessibility: input.accessibility,
                                ink: ink, detail: fills ? .mini : .full)
        }
        .accessibilityHidden(true)
    }
}

/// The drawing code of planets, shared with the map (which draws many mini-planets into one Canvas).
public enum PlanetRenderer {
    public enum Detail: Sendable {
        case full, mini
    }

    private struct Key: Hashable {
        var input: PlanetArtInput
    }

    /// The recipe, cached per input (phase excluded).
    @MainActor
    public static func recipe(_ input: PlanetArtInput) -> PlanetRecipe {
        var key = input
        key.phase = 0
        return ArtCache.shared.value(Key(input: key)) { PlanetRecipe.make(key) }
    }

    /// ART-026: one surface turn per 60 s of phase.
    public static let rotationPeriod = 60.0

    public static func draw(_ ctx: inout GraphicsContext, recipe rc: PlanetRecipe, center c: CGPoint, radius r: Double, phase rawPhase: Double,
                            accessibility a11y: ArtAccessibility, ink: ArtInk, detail: Detail = .full) {
        let phase = a11y.ambientPhase(rawPhase)
        let disk = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        if detail == .full { drawBehind(&ctx, rc: rc, c: c, r: r, phase: phase, ink: ink) }
        var surf = ctx
        surf.clip(to: disk)
        let deep = ink.rgb(rc.ocean == .landGrey ? .landGrey : .oceanDeep)
        surf.fill(disk, with: .radialGradient(Gradient(colors: [ink.rgb(rc.ocean).shade(1.15).color, deep.color]),
                                              center: CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.3), startRadius: 0, endRadius: r * 1.6))
        // Tilted, rotating surface.
        surf.translateBy(x: c.x, y: c.y)
        surf.rotate(by: .degrees(rc.tilt))
        surf.translateBy(x: -c.x, y: -c.y)
        let shift = (phase / rotationPeriod).truncatingRemainder(dividingBy: 1) * 2
        let land = landPath(rc, c: c, r: r, shift: shift)
        var landColor = ink.rgb(rc.land)
        if rc.pressure == .drought { landColor = landColor.saturation(0.45).shade(1.1) }
        surf.fill(land, with: .color(landColor.color))
        if detail == .full {
            PlanetLayers.surfaceDetails(&surf, rc: rc, land: land, c: c, r: r, shift: shift, ink: ink)
            PlanetLayers.iceCaps(&surf, rc: rc, c: c, r: r, ink: ink)
            PlanetLayers.clouds(&surf, rc: rc, c: c, r: r, phase: phase, a11y: a11y, ink: ink)
        }
        // Night side (light from the top left). Mini-planets use a cheap gradient instead of the terminator path.
        guard detail == .full else {
            ctx.fill(disk, with: .linearGradient(Gradient(colors: [.black.opacity(0), .black.opacity(0.55)]),
                                                 startPoint: CGPoint(x: c.x - r * 0.2, y: c.y - r * 0.2), endPoint: CGPoint(x: c.x + r, y: c.y + r)))
            ctx.stroke(disk, with: .color(ink.rgb(rc.rim).opacity(0.7).color), lineWidth: max(0.6, r * 0.06) * a11y.outlineScale)
            return
        }
        let night = nightPath(c: c, r: r)
        ctx.fill(night, with: .color(.black.opacity(0.55)))
        if detail == .full {
            PlanetLayers.nightSide(&ctx, rc: rc, night: night, c: c, r: r, ink: ink)
            PlanetLayers.haze(&ctx, rc: rc, disk: disk, ink: ink)
            PlanetLayers.pressure(&ctx, rc: rc, disk: disk, c: c, r: r, rawPhase: rawPhase, a11y: a11y, ink: ink)
        }
        let rimWidth = max(0.8, r * 0.05) * a11y.outlineScale
        ctx.stroke(disk, with: .color(ink.rgb(rc.rim).opacity(a11y.increaseContrast ? 1 : 0.7).color), lineWidth: rimWidth)
        if a11y.increaseContrast { ctx.stroke(night, with: .color(.black.opacity(0.6)), lineWidth: 1) }
        if detail == .full { drawFront(&ctx, rc: rc, c: c, r: r, phase: phase, a11y: a11y, ink: ink) }
    }

    /// The continents at the current rotation (each blob drawn where it is visible on the disk).
    static func landPath(_ rc: PlanetRecipe, c: CGPoint, r: Double, shift: Double) -> Path {
        var land = Path()
        if rc.look == .lifeless { return Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)) }
        for blob in rc.continents {
            var u = (blob.u - shift).truncatingRemainder(dividingBy: 2)
            if u < 0 { u += 2 }
            for wrap in [u, u - 2] where wrap > -0.35 && wrap < 1.35 {
                var rng = ArtRandom(seed: blob.seed)
                let center = CGPoint(x: c.x - r + wrap * 2 * r, y: c.y - r + blob.v * 2 * r)
                land.addPath(ArtGeometry.blob(center: center, radius: blob.radius * r * 1.6, lobes: 9, jitter: 0.32, rng: &rng,
                                              aspect: blob.aspect))
            }
        }
        return land
    }

    static func nightPath(c: CGPoint, r: Double) -> Path {
        let disk = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        let lit = Path(ellipseIn: CGRect(x: c.x - r * 1.5, y: c.y - r * 1.4, width: 2.3 * r, height: 2.3 * r))
        return disk.subtracting(lit)
    }

    private static func drawBehind(_ ctx: inout GraphicsContext, rc: PlanetRecipe, c: CGPoint, r: Double, phase: Double, ink: ArtInk) {
        if rc.motif == .halo {
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 1.25, y: c.y - r * 1.25, width: 2.5 * r, height: 2.5 * r)),
                     with: .radialGradient(Gradient(colors: [ink.rgb(.brass).opacity(0.55).color, ink.rgb(.brass).opacity(0).color]),
                                           center: c, startRadius: r * 0.95, endRadius: r * 1.25))
        }
        PlanetLayers.ring(&ctx, rc: rc, c: c, r: r, front: false, ink: ink)
    }

    private static func drawFront(_ ctx: inout GraphicsContext, rc: PlanetRecipe, c: CGPoint, r: Double, phase: Double,
                                  a11y: ArtAccessibility, ink: ArtInk) {
        PlanetLayers.ring(&ctx, rc: rc, c: c, r: r, front: true, ink: ink)
        PlanetLayers.satellites(&ctx, rc: rc, c: c, r: r, phase: phase, ink: ink)
        PlanetLayers.motif(&ctx, rc: rc, c: c, r: r, phase: phase, a11y: a11y, ink: ink)
    }
}
