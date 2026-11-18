// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// ART-041: the four endings (engine `GameEndType` order).
public enum GameEndArt: Int, CaseIterable, Sendable, Hashable {
    case killed = 0, retired, boughtMoon, boughtMoonGirl
}

/// ART-041, ART-084…086: the ending cinematic. Each scene is built from the planet projector and the ship generator and
/// lit by one sun; it animates for at most 4 s and then holds (the final frame under Reduce Motion).
public struct GameOverScene: View {
    public var end: GameEndArt
    public var phase: Double
    public var ship: ShipArtKind
    public var accessibility: ArtAccessibility
    /// The player's own ship (statistics and equipment); nil = the kind's reference design.
    public var shipInput: ShipArtInput?
    @Environment(\.displayScale) private var displayScale

    public static let duration = EndingScenes.duration

    public init(end: GameEndArt, phase: Double = duration, ship: ShipArtKind = .gnat, accessibility: ArtAccessibility = .standard,
                shipInput: ShipArtInput? = nil) {
        self.end = end
        self.phase = phase
        self.ship = ship
        self.accessibility = accessibility
        self.shipInput = shipInput
    }

    /// The scene time (clamped to 0…4 s; the final frame under Reduce Motion).
    public static func time(phase: Double, reduceMotion: Bool) -> Double {
        reduceMotion ? duration : min(duration, max(0, phase))
    }

    public var body: some View {
        let t = Self.time(phase: phase, reduceMotion: accessibility.reduceMotion)
        let u = t / Self.duration
        let end = end, scale = displayScale
        // Space is dark in both appearances.
        let ink = ArtInk(scheme: .dark, contrast: accessibility.increaseContrast)
        var wreck = shipInput ?? ShipArtInput(kind: ship)
        wreck.hullFraction = EndingScenes.wreckHull
        wreck.disabled = true
        wreck.cloaked = false
        wreck.shield = nil
        wreck.facing = .right
        let wreckModel = ShipArtModel.make(wreck)
        let visitor = ShipArtInput(kind: .gnat, facing: .left, disabled: true)
        let visitorModel = ShipArtModel.make(visitor)
        return Canvas { ctx, size in
            switch end {
            case .killed: EndingScenes.killed(&ctx, size: size, t: t, wreck: wreck, model: wreckModel, ink: ink)
            case .retired: EndingScenes.retired(&ctx, size: size, u: u, scale: scale, ink: ink)
            case .boughtMoon, .boughtMoonGirl:
                EndingScenes.moon(&ctx, size: size, u: u, scale: scale, princess: end == .boughtMoonGirl, visitor: visitor, model: visitorModel,
                                  ink: ink)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
    }
}

/// The drawing code of the endings.
enum EndingScenes {
    typealias V3 = SIMD3<Float>

    /// ART-041: every ending animates for this long, then holds.
    static let duration = 4.0
    /// ART-086: the wreck's hull fraction and tumble.
    static let wreckHull = 0.25
    static let tumblePeriod = 8.0
    static let fragments = 12

    static func normalized(_ v: V3) -> V3 { v / (v * v).sum().squareRoot() }

    static func recipe(resource: Int, seed: UInt64, size: Int = 4, tech: Int = 6) -> PlanetRecipe {
        PlanetRecipe.make(PlanetArtInput(seed: seed, sizeClass: size, tech: tech, government: 6, resource: resource))
    }

    static func space(_ ctx: inout GraphicsContext, size: CGSize, seed: UInt64, stars: Double, ink: ArtInk) {
        let frame = CGRect(origin: .zero, size: size)
        ctx.fill(Path(frame), with: .linearGradient(Gradient(colors: [ArtRGB(0.02, 0.02, 0.06).color, ink(.spaceBottom)]), startPoint: .zero,
                                                    endPoint: CGPoint(x: 0, y: size.height)))
        guard stars > 0 else { return }
        var s = ctx
        s.opacity = stars
        s.scaleBy(x: 0.5, y: 0.5)
        Starfield(seed: seed, density: 1).draw(&s, size: CGSize(width: size.width * 2, height: size.height * 2))
    }

    /// A window on a sphere whose disk reaches outside the frame: centre and radius in points.
    static func limb(_ ctx: inout GraphicsContext, size: CGSize, scale: Double, recipe: PlanetRecipe, center: CGPoint, radius: Double,
                     light: V3, lod: PlanetLOD = .cinema, bump: Float = 1, turn: Double = 0) {
        let w = max(1, Int((size.width * scale).rounded())), h = max(1, Int((size.height * scale).rounded()))
        let maps = PlanetRenderer.maps(recipe, lod: lod)
        var u = PlanetSphere.uniforms(recipe: recipe, phase: turn, pixelSize: w, radius: radius * scale, mapWidth: maps.width, ring: false)
        u.viewport = SIMD4(Float(center.x * scale), Float(center.y * scale), Float(radius * scale), 0)
        let l = normalized(light)
        u.light = SIMD4(l.x, l.y, l.z, 0.012)
        u.surface.y *= bump
        guard let image = PlanetSphere.project(maps, uniforms: u, width: w, height: h) else { return }
        ctx.draw(Image(decorative: image, scale: scale), in: CGRect(origin: .zero, size: size))
    }

    // MARK: Retired (ART-084)

    /// An orbital sunset: the sun sinks behind the planet's limb through layered atmosphere while the stars come out.
    static func retired(_ ctx: inout GraphicsContext, size: CGSize, u: Double, scale: Double, ink: ArtInk) {
        let w = size.width, h = size.height
        space(&ctx, size: size, seed: 0x5245_5449, stars: 0.15 + 0.85 * u, ink: ink)
        let radius = w * 1.25
        let limbY = h * 0.60
        let center = CGPoint(x: w / 2, y: limbY + radius)
        let sun = CGPoint(x: w * 0.5, y: limbY - h * (0.11 - 0.17 * u))
        // Layered scattering: white at the limb, orange above it, deep blue higher, strongest around the sun.
        ctx.drawLayer { layer in
            let outer = radius + h * 0.34
            layer.fill(Path(ellipseIn: CGRect(x: center.x - outer, y: center.y - outer, width: 2 * outer, height: 2 * outer)),
                       with: .radialGradient(Gradient(stops: [.init(color: ArtRGB(1.0, 0.97, 0.90, 0.95).color, location: radius / outer),
                                                              .init(color: ArtRGB(1.0, 0.62, 0.22, 0.85).color, location: (radius + h * 0.030) / outer),
                                                              .init(color: ArtRGB(0.80, 0.30, 0.25, 0.55).color, location: (radius + h * 0.075) / outer),
                                                              .init(color: ArtRGB(0.16, 0.26, 0.62, 0.40).color, location: (radius + h * 0.16) / outer),
                                                              .init(color: ArtRGB(0.05, 0.08, 0.30, 0).color, location: 1)]),
                                             center: center, startRadius: 0, endRadius: outer))
            layer.blendMode = .destinationIn
            let reach = w * (0.62 - 0.14 * u)
            layer.fill(Path(CGRect(origin: .zero, size: size)),
                       with: .radialGradient(Gradient(colors: [.white, .white.opacity(0.55), .white.opacity(0.06)]),
                                             center: CGPoint(x: sun.x, y: limbY), startRadius: 0, endRadius: reach))
        }
        // The sun and its bloom.
        let disc = h * 0.045
        let bloom = h * (0.42 - 0.12 * u)
        ctx.fill(Path(ellipseIn: CGRect(x: sun.x - bloom, y: sun.y - bloom, width: 2 * bloom, height: 2 * bloom)),
                 with: .radialGradient(Gradient(stops: [.init(color: ArtRGB(1, 0.96, 0.82, 0.9).color, location: 0),
                                                        .init(color: ArtRGB(1, 0.78, 0.40, 0.42).color, location: 0.16),
                                                        .init(color: ArtRGB(1, 0.50, 0.20, 0.12).color, location: 0.5),
                                                        .init(color: ArtRGB(1, 0.40, 0.20, 0).color, location: 1)]),
                                       center: sun, startRadius: 0, endRadius: bloom))
        ctx.fill(Path(ellipseIn: CGRect(x: sun.x - disc, y: sun.y - disc, width: 2 * disc, height: 2 * disc)), with: .color(.white))
        // The planet: night side towards us, the low sun catching the cloud tops along the limb.
        let recipe = recipe(resource: 5, seed: 0x5245_5449)
        limb(&ctx, size: size, scale: scale, recipe: recipe, center: center, radius: radius,
             light: V3(0, Float(0.50 - 0.22 * u), Float(-0.30 - 0.35 * u)), turn: u * 0.6)
        // The glare where the sun meets the limb.
        let glare = h * 0.16 * (1 - 0.55 * u)
        let touch = CGPoint(x: sun.x, y: limbY)
        var g = ctx
        g.blendMode = .plusLighter
        g.translateBy(x: touch.x, y: touch.y)
        g.scaleBy(x: 3.2, y: 0.5)
        g.fill(Path(ellipseIn: CGRect(x: -glare, y: -glare, width: 2 * glare, height: 2 * glare)),
               with: .radialGradient(Gradient(colors: [ArtRGB(1, 0.92, 0.75, 0.75).color, ArtRGB(1, 0.6, 0.3, 0.2).color, ArtRGB(1, 0.5, 0.2, 0).color]),
                                     center: .zero, startRadius: 0, endRadius: glare))
    }

    // MARK: Bought moon (ART-085)

    /// A cratered moon under a low sun, a glass dome habitat on its horizon and the parent planet in the sky.
    static func moon(_ ctx: inout GraphicsContext, size: CGSize, u: Double, scale: Double, princess: Bool, visitor: ShipArtInput,
                     model: ShipArtModel, ink: ArtInk) {
        let w = size.width, h = size.height
        space(&ctx, size: size, seed: 0x4D4F_4F4E, stars: 1, ink: ink)
        let sunLight = V3(-0.78, 0.30, 0.46)
        // The parent planet, high on the right, lit by the same sun.
        let parent = recipe(resource: 4, seed: 0x5041_5245, size: 5)
        let pr = h * 0.21
        let pc = CGPoint(x: w * 0.80, y: h * (0.27 + 0.03 * (1 - u)))
        let side = Int((pr * 2.5 * scale).rounded())
        let maps = PlanetRenderer.maps(parent, lod: .hero)
        var pu = PlanetSphere.uniforms(recipe: parent, phase: 0, pixelSize: side, radius: pr * scale, mapWidth: maps.width, ring: false)
        let l = normalized(sunLight)
        pu.light = SIMD4(l.x, l.y, l.z, 0.015)
        if let image = PlanetSphere.project(maps, uniforms: pu, pixelSize: side) {
            ctx.draw(Image(decorative: image, scale: scale), in: CGRect(x: pc.x - pr * 1.25, y: pc.y - pr * 1.25, width: pr * 2.5, height: pr * 2.5))
        }
        // The moon rises into the frame, then holds.
        let radius = w * 0.80
        let horizon = h * (0.62 + 0.16 * (1 - u) * (1 - u))
        let center = CGPoint(x: w / 2, y: horizon + radius)
        let ground = recipe(resource: 8, seed: 0x4D4F_4F4E, tech: 0)
        limb(&ctx, size: size, scale: scale, recipe: ground, center: center, radius: radius, light: sunLight, bump: 1.7)
        // The habitat sits on the horizon, left of centre; the sun is low on the left, so shadows run to the right.
        let base = CGPoint(x: w * 0.42, y: horizon + h * 0.012)
        let dr = h * 0.20
        var shadow = ctx
        shadow.translateBy(x: base.x + dr * 1.9, y: base.y + dr * 0.10)
        shadow.scaleBy(x: 2.6, y: 0.16)
        shadow.fill(Path(ellipseIn: CGRect(x: -dr, y: -dr, width: 2 * dr, height: 2 * dr)),
                    with: .radialGradient(Gradient(colors: [.black.opacity(0.75), .black.opacity(0.45), .black.opacity(0)]), center: .zero,
                                          startRadius: 0, endRadius: dr))
        habitat(&ctx, base: base, radius: dr, princess: princess, ink: ink)
        if princess {
            // The second ship, docked beside the dome.
            let box = CGSize(width: dr * 1.5, height: dr * 0.9)
            let origin = CGPoint(x: base.x + dr * 1.25, y: base.y - box.height * 0.74)
            let pad = CGRect(x: origin.x + box.width * 0.08, y: base.y - dr * 0.03, width: box.width * 0.84, height: dr * 0.06)
            ctx.fill(Path(roundedRect: pad, cornerRadius: dr * 0.02),
                     with: .linearGradient(Gradient(colors: [ArtRGB(0.74, 0.74, 0.78).color, ArtRGB(0.22, 0.22, 0.26).color]),
                                           startPoint: CGPoint(x: pad.minX, y: pad.midY), endPoint: CGPoint(x: pad.maxX, y: pad.midY)))
            var s = ctx
            s.translateBy(x: origin.x, y: origin.y)
            ShipRenderer.draw(&s, size: box, model: model, input: visitor, mode: .fit, ink: ink, sparks: false)
        }
    }

    /// A glass dome with interior light, a reflection highlight and lit buildings inside.
    static func habitat(_ ctx: inout GraphicsContext, base: CGPoint, radius r: Double, princess: Bool, ink: ArtInk) {
        var dome = Path()
        dome.move(to: CGPoint(x: base.x - r, y: base.y))
        dome.addArc(center: base, radius: r, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        dome.closeSubpath()
        // Interior light.
        ctx.fill(dome, with: .radialGradient(Gradient(colors: [ArtRGB(1.0, 0.86, 0.55, 0.55).color, ArtRGB(0.55, 0.75, 0.95, 0.22).color,
                                                               ArtRGB(0.45, 0.70, 0.95, 0.12).color]),
                                             center: CGPoint(x: base.x, y: base.y - r * 0.15), startRadius: 0, endRadius: r))
        // Buildings: two blocks and a tower, with one lit window, or two for the princess.
        var inside = ctx
        inside.clip(to: dome)
        let wall = ArtRGB(0.80, 0.78, 0.72), dark = ArtRGB(0.36, 0.36, 0.40)
        let blocks = [CGRect(x: base.x - r * 0.52, y: base.y - r * 0.30, width: r * 0.42, height: r * 0.30),
                      CGRect(x: base.x - r * 0.06, y: base.y - r * 0.52, width: r * 0.30, height: r * 0.52),
                      CGRect(x: base.x + r * 0.28, y: base.y - r * 0.22, width: r * 0.30, height: r * 0.22)]
        for b in blocks {
            inside.fill(Path(roundedRect: b, cornerRadius: r * 0.02),
                        with: .linearGradient(Gradient(colors: [wall.color, dark.color]), startPoint: CGPoint(x: b.minX, y: b.midY),
                                              endPoint: CGPoint(x: b.maxX, y: b.midY)))
        }
        let lit = ArtRGB(1.0, 0.86, 0.45)
        for k in 0..<(princess ? 2 : 1) {
            let win = CGRect(x: blocks[1].minX + blocks[1].width * 0.22, y: blocks[1].minY + blocks[1].height * (0.14 + 0.30 * Double(k)),
                             width: blocks[1].width * 0.56, height: blocks[1].height * 0.16)
            inside.fill(Path(ellipseIn: win.insetBy(dx: -win.width * 0.5, dy: -win.height)),
                        with: .radialGradient(Gradient(colors: [lit.opacity(0.55).color, lit.opacity(0).color]),
                                              center: CGPoint(x: win.midX, y: win.midY), startRadius: 0, endRadius: win.width))
            inside.fill(Path(roundedRect: win, cornerRadius: r * 0.01), with: .color(lit.color))
        }
        // Glass: a rim, and the sun's reflection on the lit (left) flank.
        ctx.stroke(dome, with: .linearGradient(Gradient(colors: [ArtRGB(1, 1, 1, 0.9).color, ArtRGB(0.6, 0.8, 1, 0.35).color]),
                                               startPoint: CGPoint(x: base.x - r, y: base.y - r), endPoint: CGPoint(x: base.x + r, y: base.y)),
                   lineWidth: max(1, r * 0.022))
        var glint = Path()
        glint.addArc(center: base, radius: r * 0.86, startAngle: .degrees(196), endAngle: .degrees(246), clockwise: false)
        ctx.stroke(glint, with: .color(.white.opacity(0.75)), style: StrokeStyle(lineWidth: max(1, r * 0.05), lineCap: .round))
        ctx.fill(Path(roundedRect: CGRect(x: base.x - r * 1.06, y: base.y - r * 0.03, width: r * 2.12, height: r * 0.07), cornerRadius: r * 0.02),
                 with: .linearGradient(Gradient(colors: [ArtRGB(0.80, 0.80, 0.84).color, ArtRGB(0.22, 0.22, 0.26).color]),
                                       startPoint: CGPoint(x: base.x - r, y: base.y), endPoint: CGPoint(x: base.x + r, y: base.y)))
    }

    // MARK: Killed (ART-086)

    /// One hull-plate fragment: where it starts on the ship, where it drifts, how it spins.
    struct Fragment: Sendable, Hashable {
        var origin: CGPoint
        var drift: CGPoint
        var size: Double
        var spin: Double
        var skew: Double
    }

    /// The fragments (unit space: origin and drift as fractions of the frame's short side).
    static func plates(seed: UInt64) -> [Fragment] {
        var rng = ArtRandom(seed: ArtSeed.mix(seed, 0x504C_4154))
        return (0..<fragments).map { k in
            let a = (Double(k) + rng.range(0...0.8)) / Double(fragments) * 2 * .pi
            let d = rng.range(0.34...0.80)
            return Fragment(origin: CGPoint(x: cos(a) * 0.08, y: sin(a) * 0.05), drift: CGPoint(x: cos(a) * d, y: sin(a) * d * 0.62),
                            size: rng.range(0.022...0.060), spin: rng.range(-2.4...2.4), skew: rng.range(0.25...0.75))
        }
    }

    static func killed(_ ctx: inout GraphicsContext, size: CGSize, t: Double, wreck: ShipArtInput, model: ShipArtModel, ink: ArtInk) {
        let u = t / duration
        let w = size.width, h = size.height, side = min(w, h)
        space(&ctx, size: size, seed: 0x4B49_4C4C, stars: 1, ink: ink)
        Nebula(seed: 0x4B49_4C4C).draw(&ctx, size: size, accessibility: .standard, ink: ink)
        let c = CGPoint(x: w * (0.46 + 0.06 * u), y: h * (0.52 + 0.02 * u))
        // The fading glow of the explosion.
        let fade = 1 - u
        let blast = side * (0.30 + 0.45 * u)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - blast, y: c.y - blast, width: 2 * blast, height: 2 * blast)),
                 with: .radialGradient(Gradient(colors: [ArtRGB(1.0, 0.74, 0.36, 0.55 * fade).color, ArtRGB(1.0, 0.40, 0.14, 0.22 * fade).color,
                                                         ArtRGB(1.0, 0.30, 0.10, 0).color]),
                                       center: c, startRadius: 0, endRadius: blast))
        // The player's own ship, scorched, powerless and tumbling.
        let box = CGSize(width: min(w * 0.46, h * 0.95), height: h * 0.52)
        var s = ctx
        s.translateBy(x: c.x, y: c.y)
        s.rotate(by: .degrees(-18 + 360 * t / tumblePeriod))
        s.translateBy(x: -box.width / 2, y: -box.height / 2)
        ShipRenderer.draw(&s, size: box, model: model, input: wreck, mode: .fit, ink: ink, sparks: false)
        // Hull plates torn loose: each a quadrilateral with a lit and a shadowed face.
        let paint = ink.rgb(model.blueprint.livery.primary)
        for f in plates(seed: ArtSeed.kind(wreck.kind)) {
            let p = CGPoint(x: c.x + (f.origin.x + f.drift.x * (0.25 + 0.75 * u)) * side, y: c.y + (f.origin.y + f.drift.y * (0.25 + 0.75 * u)) * side)
            let r = f.size * side
            let glow = r * 2.6
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - glow, y: p.y - glow, width: 2 * glow, height: 2 * glow)),
                     with: .radialGradient(Gradient(colors: [ArtRGB(1.0, 0.55, 0.20, 0.50 * fade).color, ArtRGB(1.0, 0.40, 0.10, 0).color]),
                                           center: p, startRadius: 0, endRadius: glow))
            var plate = ctx
            plate.translateBy(x: p.x, y: p.y)
            plate.rotate(by: .radians(f.spin * (0.4 + t)))
            let corners = [CGPoint(x: -r, y: -r * 0.55), CGPoint(x: r * 0.85, y: -r * 0.75), CGPoint(x: r, y: r * 0.5), CGPoint(x: -r * 0.7, y: r * 0.7)]
            let ridge = (CGPoint(x: -r + (r * 1.85) * f.skew, y: -r * 0.55 - r * 0.2 * f.skew),
                         CGPoint(x: -r * 0.7 + r * 1.7 * f.skew, y: r * 0.7 - r * 0.2 * f.skew))
            plate.fill(ArtGeometry.polygon([corners[0], ridge.0, ridge.1, corners[3]]), with: .color(paint.shade(1.22).color))
            plate.fill(ArtGeometry.polygon([ridge.0, corners[1], corners[2], ridge.1]), with: .color(paint.shade(0.42).color))
            plate.stroke(ArtGeometry.polygon(corners), with: .color(ink(.outline).opacity(0.5)), lineWidth: max(0.4, r * 0.05))
        }
    }
}
