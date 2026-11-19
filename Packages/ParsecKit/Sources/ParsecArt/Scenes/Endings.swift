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
        // ART-END-003: the player's own ship as it was at the end of the game (statistics, equipment and livery).
        var own = shipInput ?? ShipArtInput(kind: ship)
        own.cloaked = false
        own.shield = nil
        own.accessibility = accessibility
        let cast = EndingCast(own: own, u: u)
        return Canvas { ctx, size in
            switch end {
            case .killed: EndingScenes.killed(&ctx, size: size, t: t, cast: cast, ink: ink)
            case .retired: EndingScenes.retired(&ctx, size: size, u: u, scale: scale, cast: cast, ink: ink)
            case .boughtMoon, .boughtMoonGirl:
                EndingScenes.moon(&ctx, size: size, u: u, scale: scale, princess: end == .boughtMoonGirl, cast: cast, ink: ink)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
    }

    /// ART-END-001: what the scene shows, for VoiceOver (the host labels the card with it).
    public static func sceneDescription(_ end: GameEndArt) -> String {
        switch end {
        case .killed: "Your ship drifts in pieces among cooling debris."
        case .retired: "Your ship comes to rest in low orbit as the sun sets behind the planet."
        case .boughtMoon: "Your ship stands on the landing pad of your own moon base, the planet large in the black sky."
        case .boughtMoonGirl: "Two ships stand on the landing pads of your moon base, two windows lit, the planet large in the black sky."
        }
    }
}

/// The ships of an ending: the player's own in the states the scenes need, and the princess's.
struct EndingCast {
    /// Under way, engines lit (retired, first half).
    var flying: ShipArtInput
    var flyingModel: ShipArtModel
    /// Powered down, intact (retired at rest, landed on the moon).
    var resting: ShipArtInput
    var restingModel: ShipArtModel
    /// Scorched and dead (killed).
    var wreck: ShipArtInput
    var wreckModel: ShipArtModel
    /// The second ship of the princess ending: a small courier in a fixed royal livery.
    var visitor: ShipArtInput
    var visitorModel: ShipArtModel

    @MainActor
    init(own: ShipArtInput, u: Double) {
        var f = own
        f.facing = .left
        f.disabled = false
        f.hullFraction = 1
        f.phase = u * 4
        flying = f
        flyingModel = ShipArtModel.make(f)
        var r = f
        r.disabled = true
        resting = r
        restingModel = ShipArtModel.make(r)
        var w = own
        w.facing = .right
        w.disabled = true
        w.hullFraction = EndingScenes.wreckHull
        wreck = w
        wreckModel = ShipArtModel.make(w)
        visitor = ShipArtInput(kind: .firefly, facing: .right, disabled: true, role: .famousCaptain, liverySeed: EndingScenes.visitorLivery)
        visitorModel = ShipArtModel.make(visitor)
    }
}

/// The drawing code of the endings. One light per scene: every shadow, lit flank and rim agrees with it.
enum EndingScenes {
    typealias V3 = SIMD3<Float>

    /// ART-041: every ending animates for this long, then holds.
    static let duration = 4.0
    /// ART-086: the wreck's hull fraction.
    static let wreckHull = 0.5
    /// The fixed livery of the princess's ship.
    static let visitorLivery: UInt64 = 0x5052_494E_4345_5353
    /// ART-086: the wreck breaks into this many hull sections, among this many shards.
    static let sections = 3
    static let shards = 22

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

    /// Eases a motion to rest.
    static func settle(_ u: Double) -> Double { 1 - (1 - u) * (1 - u) }

    /// Draws a ship in `box`, then lets `light` repaint it where it is opaque (`sourceAtop`): the scene's own light and shade.
    static func ship(_ ctx: inout GraphicsContext, box: CGRect, model: ShipArtModel, input: ShipArtInput, ink: ArtInk, opacity: Double = 1,
                     light: ((inout GraphicsContext, CGRect) -> Void)? = nil) {
        ctx.drawLayer { layer in
            layer.opacity = opacity
            var s = layer
            s.translateBy(x: box.minX, y: box.minY)
            ShipRenderer.draw(&s, size: box.size, model: model, input: input, mode: .fit, ink: ink, sparks: false)
            if let light {
                var lit = layer
                lit.blendMode = .sourceAtop
                light(&lit, box)
            }
        }
    }

    // MARK: Retired (ART-084)

    /// Low orbit at sunset: the sun sinks behind the planet's limb through layered atmosphere while the stars come out, and
    /// the player's ship, small against the planet, drifts to a stop with its engines dying.
    static func retired(_ ctx: inout GraphicsContext, size: CGSize, u: Double, scale: Double, cast: EndingCast, ink: ArtInk) {
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
        // The ship: small against the planet, coasting in from the right and coming to rest high on the left of the sun.
        // It is lit from below and behind, so it reads as a dark hull with a warm rim towards the sun.
        let s = settle(u)
        let box = CGRect(x: w * (0.78 - 0.26 * s), y: h * (0.16 + 0.035 * s), width: w * 0.22, height: h * 0.26)
        let relight: (inout GraphicsContext, CGRect) -> Void = { lit, box in
            let area = Path(box.insetBy(dx: -box.width, dy: -box.height))
            // The sun is below and behind: the upper surfaces are in shade, the underside catches the glow of the limb.
            lit.fill(area, with: .linearGradient(Gradient(stops: [.init(color: ArtRGB(0.02, 0.03, 0.08, 0.70).color, location: 0),
                                                                  .init(color: ArtRGB(0.03, 0.04, 0.09, 0.52).color, location: 0.55),
                                                                  .init(color: ArtRGB(1.0, 0.66, 0.36, 0.50).color, location: 1)]),
                                                 startPoint: CGPoint(x: box.midX, y: box.minY + box.height * 0.2),
                                                 endPoint: CGPoint(x: box.midX, y: box.maxY - box.height * 0.2)))
        }
        // Engines lit while it brakes, dark once it rests.
        ship(&ctx, box: box, model: cast.restingModel, input: cast.resting, ink: ink, light: relight)
        if u < 1 { ship(&ctx, box: box, model: cast.flyingModel, input: cast.flying, ink: ink, opacity: (1 - u) * (1 - u), light: relight) }
    }

    // MARK: Bought moon (ART-085)

    /// The sun of the moon scenes: low on the left, a little towards the viewer. Shadows run to the right.
    static let moonLight = V3(-0.78, 0.30, 0.46)

    /// The surface of the moon at Utopia: cratered regolith to a close horizon under a low sun, a pressurised habitat with
    /// lit windows, a landing pad with the player's ship on it, and the parent planet large in the black sky.
    static func moon(_ ctx: inout GraphicsContext, size: CGSize, u: Double, scale: Double, princess: Bool, cast: EndingCast, ink: ArtInk) {
        let w = size.width, h = size.height
        space(&ctx, size: size, seed: 0x4D4F_4F4E, stars: 1, ink: ink)
        // The parent planet, large in the sky, lit by the same sun.
        let parent = recipe(resource: 4, seed: 0x5041_5245, size: 5)
        let pr = h * 0.34
        let pc = CGPoint(x: w * 0.74, y: h * (0.25 + 0.04 * (1 - settle(u))))
        let side = Int((pr * 2.5 * scale).rounded())
        let maps = PlanetRenderer.maps(parent, lod: .hero)
        var pu = PlanetSphere.uniforms(recipe: parent, phase: 0, pixelSize: side, radius: pr * scale, mapWidth: maps.width, ring: false)
        let l = normalized(moonLight)
        pu.light = SIMD4(l.x, l.y, l.z, 0.015)
        if let image = PlanetSphere.project(maps, uniforms: pu, pixelSize: side) {
            ctx.draw(Image(decorative: image, scale: scale), in: CGRect(x: pc.x - pr * 1.25, y: pc.y - pr * 1.25, width: pr * 2.5, height: pr * 2.5))
        }
        // The ground: a big sphere seen from just above its surface, so the horizon is close and nearly flat. The camera
        // settles onto the scene, then holds.
        let radius = w * 1.35
        let horizon = h * (0.55 + 0.10 * (1 - settle(u)))
        let center = CGPoint(x: w * 0.5, y: horizon + radius)
        let ground = recipe(resource: 8, seed: 0x4D4F_4F4E, tech: 0)
        limb(&ctx, size: size, scale: scale, recipe: ground, center: center, radius: radius, light: moonLight, bump: 1.6)
        // Distance haze is absent on an airless moon; instead the ground darkens towards the viewer, away from the sun.
        ctx.fill(Path(CGRect(x: 0, y: horizon, width: w, height: h - horizon)),
                 with: .linearGradient(Gradient(colors: [.black.opacity(0), .black.opacity(0.38)]), startPoint: CGPoint(x: 0, y: horizon),
                                       endPoint: CGPoint(x: w * 0.4, y: h)))
        // The base stands on the plain between the viewer and the horizon.
        let floor = horizon + h * 0.20
        let unit = h * 0.070
        habitat(&ctx, base: CGPoint(x: w * 0.26, y: floor), unit: unit, windows: princess ? 2 : 1)
        // The pad and the player's ship. The ship lies flat on the ground, so it is foreshortened like the pad's circle.
        let pad = CGPoint(x: w * 0.58, y: floor + unit * 1.0)
        landingPad(&ctx, center: pad, radius: unit * 3.3, beacon: 0.55 + 0.45 * cos(u * .pi * 6))
        landedShip(&ctx, center: CGPoint(x: pad.x, y: pad.y - unit * 0.70), width: unit * 5.6, model: cast.restingModel, input: cast.resting, ink: ink)
        if princess {
            // The second, smaller ship in its own livery, on its own pad further off.
            let second = CGPoint(x: w * 0.86, y: floor - unit * 0.3)
            landingPad(&ctx, center: second, radius: unit * 2.1, beacon: 0.55 + 0.45 * cos(u * .pi * 6 + 1.6))
            landedShip(&ctx, center: CGPoint(x: second.x, y: second.y - unit * 0.45), width: unit * 3.4, model: cast.visitorModel, input: cast.visitor,
                       ink: ink)
        }
    }

    /// A long shadow on the ground: a soft ellipse stretched away from the sun (to the right).
    static func groundShadow(_ ctx: inout GraphicsContext, from p: CGPoint, length: Double, height: Double, strength: Double = 0.78) {
        var shadow = ctx
        shadow.translateBy(x: p.x + length * 0.5, y: p.y)
        shadow.scaleBy(x: length / max(1, height), y: 1)
        let r = height
        shadow.fill(Path(ellipseIn: CGRect(x: -r / 2, y: -r / 2, width: r, height: r)),
                    with: .radialGradient(Gradient(colors: [.black.opacity(strength), .black.opacity(strength * 0.7), .black.opacity(0)]), center: .zero,
                                          startRadius: 0, endRadius: r / 2))
    }

    /// A pressurised module seen from the side: a cylinder lying on the ground, lit from the upper left.
    static func module(_ ctx: inout GraphicsContext, rect: CGRect) {
        let body = Path(roundedRect: rect, cornerRadius: rect.height / 2)
        ctx.fill(body, with: .linearGradient(Gradient(stops: [.init(color: ArtRGB(0.93, 0.93, 0.90).color, location: 0),
                                                              .init(color: ArtRGB(0.74, 0.75, 0.76).color, location: 0.34),
                                                              .init(color: ArtRGB(0.30, 0.31, 0.35).color, location: 0.78),
                                                              .init(color: ArtRGB(0.14, 0.15, 0.19).color, location: 1)]),
                                             startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
        // The end away from the sun falls into shade.
        ctx.fill(body, with: .linearGradient(Gradient(colors: [.black.opacity(0), .black.opacity(0.42)]), startPoint: CGPoint(x: rect.midX, y: rect.midY),
                                             endPoint: CGPoint(x: rect.maxX, y: rect.midY)))
        // Hull rings.
        var rings = ctx
        rings.clip(to: body)
        for k in 1..<4 {
            let x = rect.minX + rect.width * Double(k) / 4
            rings.fill(Path(CGRect(x: x, y: rect.minY, width: max(0.5, rect.height * 0.03), height: rect.height)), with: .color(.black.opacity(0.28)))
        }
    }

    /// The habitat: two modules joined by a domed hub with an airlock, a mast with a dish, legs, and lit windows.
    static func habitat(_ ctx: inout GraphicsContext, base: CGPoint, unit u: Double, windows: Int) {
        let long = CGRect(x: base.x - u * 4.6, y: base.y - u * 1.55, width: u * 4.2, height: u * 1.25)
        let short = CGRect(x: base.x + u * 0.9, y: base.y - u * 1.40, width: u * 2.9, height: u * 1.10)
        // Shadows first: everything on the ground throws one to the right.
        groundShadow(&ctx, from: CGPoint(x: long.minX + u * 0.6, y: base.y + u * 0.10), length: u * 12, height: u * 0.95)
        groundShadow(&ctx, from: CGPoint(x: base.x, y: base.y - u * 0.02), length: u * 9, height: u * 0.55, strength: 0.6)
        // Legs.
        for x in [long.minX + u * 0.7, long.maxX - u * 0.7, short.minX + u * 0.6, short.maxX - u * 0.6] {
            ctx.fill(Path(CGRect(x: x - u * 0.06, y: base.y - u * 0.42, width: u * 0.12, height: u * 0.46)), with: .color(ArtRGB(0.22, 0.23, 0.27).color))
            ctx.fill(Path(ellipseIn: CGRect(x: x - u * 0.22, y: base.y - u * 0.02, width: u * 0.44, height: u * 0.12)),
                     with: .color(ArtRGB(0.30, 0.31, 0.35).color))
        }
        module(&ctx, rect: long)
        module(&ctx, rect: short)
        // The hub: a domed node between the modules, with the airlock at its foot.
        let hub = CGRect(x: base.x - u * 0.75, y: base.y - u * 2.45, width: u * 2.0, height: u * 2.45)
        var dome = Path()
        dome.move(to: CGPoint(x: hub.minX, y: hub.maxY))
        dome.addLine(to: CGPoint(x: hub.minX, y: hub.minY + hub.width / 2))
        dome.addArc(center: CGPoint(x: hub.midX, y: hub.minY + hub.width / 2), radius: hub.width / 2, startAngle: .degrees(180), endAngle: .degrees(360),
                    clockwise: false)
        dome.addLine(to: CGPoint(x: hub.maxX, y: hub.maxY))
        dome.closeSubpath()
        ctx.fill(dome, with: .linearGradient(Gradient(stops: [.init(color: ArtRGB(0.95, 0.94, 0.90).color, location: 0),
                                                              .init(color: ArtRGB(0.66, 0.67, 0.70).color, location: 0.42),
                                                              .init(color: ArtRGB(0.16, 0.17, 0.21).color, location: 1)]),
                                             startPoint: CGPoint(x: hub.minX, y: hub.midY), endPoint: CGPoint(x: hub.maxX, y: hub.midY)))
        ctx.fill(Path(roundedRect: CGRect(x: hub.midX - u * 0.30, y: hub.maxY - u * 0.95, width: u * 0.60, height: u * 0.95), cornerRadius: u * 0.10),
                 with: .color(ArtRGB(0.10, 0.11, 0.14).color))
        // The mast and its dish, on the hub.
        let top = CGPoint(x: hub.midX + u * 0.35, y: hub.minY + u * 0.12)
        ctx.fill(Path(CGRect(x: top.x - u * 0.035, y: top.y - u * 1.5, width: u * 0.07, height: u * 1.5)), with: .color(ArtRGB(0.62, 0.63, 0.66).color))
        var dish = ctx
        dish.translateBy(x: top.x, y: top.y - u * 1.5)
        dish.rotate(by: .degrees(-28))
        dish.fill(Path(ellipseIn: CGRect(x: -u * 0.50, y: -u * 0.16, width: u * 1.0, height: u * 0.32)),
                  with: .linearGradient(Gradient(colors: [ArtRGB(0.92, 0.92, 0.90).color, ArtRGB(0.36, 0.37, 0.42).color]),
                                        startPoint: CGPoint(x: -u * 0.5, y: 0), endPoint: CGPoint(x: u * 0.5, y: 0)))
        // Windows: warm light and its spill, on the long module; one for the commander, two when the princess lives here.
        let lit = ArtRGB(1.0, 0.84, 0.48)
        for k in 0..<4 {
            let win = CGRect(x: long.minX + long.width * (0.16 + 0.19 * Double(k)), y: long.minY + long.height * 0.30, width: long.width * 0.10,
                             height: long.height * 0.26)
            let on = k < windows
            if on {
                ctx.fill(Path(ellipseIn: win.insetBy(dx: -win.width * 1.6, dy: -win.height * 1.8)),
                         with: .radialGradient(Gradient(colors: [lit.opacity(0.55).color, lit.opacity(0).color]),
                                               center: CGPoint(x: win.midX, y: win.midY), startRadius: 0, endRadius: win.width * 2.1))
                // Light spilling onto the ground under the window.
                ctx.fill(Path(ellipseIn: CGRect(x: win.midX - u * 0.9, y: base.y - u * 0.05, width: u * 1.8, height: u * 0.5)),
                         with: .radialGradient(Gradient(colors: [lit.opacity(0.30).color, lit.opacity(0).color]),
                                               center: CGPoint(x: win.midX, y: base.y + u * 0.2), startRadius: 0, endRadius: u * 0.9))
            }
            ctx.fill(Path(roundedRect: win, cornerRadius: win.height * 0.3), with: .color(on ? lit.color : ArtRGB(0.07, 0.09, 0.13).color))
        }
    }

    /// A landing pad: a circle seen at a shallow angle, with a ring, a centre mark and four beacons.
    static func landingPad(_ ctx: inout GraphicsContext, center c: CGPoint, radius r: Double, beacon: Double) {
        let squash = 0.24
        let rect = CGRect(x: c.x - r, y: c.y - r * squash, width: 2 * r, height: 2 * r * squash)
        ctx.fill(Path(ellipseIn: rect), with: .linearGradient(Gradient(colors: [ArtRGB(0.50, 0.50, 0.52).color, ArtRGB(0.20, 0.20, 0.23).color]),
                                                              startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
        ctx.stroke(Path(ellipseIn: rect.insetBy(dx: r * 0.10, dy: r * 0.10 * squash)), with: .color(ArtRGB(0.95, 0.80, 0.30, 0.75).color),
                   lineWidth: max(0.6, r * 0.03))
        ctx.stroke(Path(ellipseIn: rect.insetBy(dx: r * 0.62, dy: r * 0.62 * squash)), with: .color(.white.opacity(0.45)), lineWidth: max(0.5, r * 0.02))
        for a in [0.0, 0.5, 1.0, 1.5] {
            let p = CGPoint(x: c.x + cos(a * .pi + 0.4) * r * 0.97, y: c.y + sin(a * .pi + 0.4) * r * 0.97 * squash)
            let glow = r * 0.20
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - glow, y: p.y - glow, width: 2 * glow, height: 2 * glow)),
                     with: .radialGradient(Gradient(colors: [ArtRGB(0.45, 0.85, 1.0, 0.75 * beacon).color, ArtRGB(0.45, 0.85, 1.0, 0).color]), center: p,
                                           startRadius: 0, endRadius: glow))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.022, y: p.y - r * 0.022, width: r * 0.044, height: r * 0.044)), with: .color(.white))
        }
    }

    /// A ship standing on the ground: its plan foreshortened by the shallow viewing angle, its long shadow to the right,
    /// its sunward side lit and the other in shade.
    static func landedShip(_ ctx: inout GraphicsContext, center c: CGPoint, width: Double, model: ShipArtModel, input: ShipArtInput, ink: ArtInk) {
        let squash = 0.52
        let full = CGSize(width: width, height: width * 0.62)
        groundShadow(&ctx, from: CGPoint(x: c.x - width * 0.30, y: c.y + full.height * squash * 0.42), length: width * 1.9, height: full.height * squash * 0.8)
        var flat = ctx
        flat.translateBy(x: c.x - width / 2, y: c.y - full.height * squash / 2)
        flat.scaleBy(x: 1, y: squash)
        ship(&flat, box: CGRect(origin: .zero, size: full), model: model, input: input, ink: ink) { lit, box in
            lit.fill(Path(box.insetBy(dx: -box.width, dy: -box.height)),
                     with: .linearGradient(Gradient(stops: [.init(color: ArtRGB(1.0, 0.97, 0.90, 0.22).color, location: 0),
                                                            .init(color: ArtRGB(0, 0, 0, 0).color, location: 0.40),
                                                            .init(color: ArtRGB(0.01, 0.01, 0.04, 0.50).color, location: 1)]),
                                           startPoint: CGPoint(x: box.minX, y: box.minY), endPoint: CGPoint(x: box.maxX, y: box.maxY)))
        }
    }

    // MARK: Killed (ART-086)

    /// One piece of the broken hull: the part of the ship between two cuts, and how it drifts and turns.
    struct Section: Sendable, Hashable {
        /// The piece's outline in the ship's box (unit square).
        var outline: [CGPoint]
        /// Drift in box widths over the 4 s, and the turn in degrees.
        var drift: CGPoint
        var turn: Double
    }

    /// A shard of plating.
    struct Shard: Sendable, Hashable {
        var origin: CGPoint
        var drift: CGPoint
        var size: Double
        var spin: Double
        var slender: Double
        var painted: Bool
    }

    /// A jagged cut across the hull at `x` (unit box): the same points close one section and open the next.
    static func cut(at x: Double, rng: inout ArtRandom) -> [CGPoint] {
        (0...8).map { k in CGPoint(x: x + rng.range(-0.035...0.035), y: -0.1 + 1.2 * Double(k) / 8) }
    }

    /// ART-086: the hull breaks behind the nose and ahead of the engines; the three sections drift apart and turn.
    static func hullSections(seed: UInt64) -> [Section] {
        var rng = ArtRandom(seed: ArtSeed.mix(seed, 0x5345_4354))
        let aft = cut(at: rng.range(0.30...0.38), rng: &rng), fore = cut(at: rng.range(0.62...0.70), rng: &rng)
        let left = [CGPoint(x: -0.2, y: -0.1), CGPoint(x: -0.2, y: 1.1)], right = [CGPoint(x: 1.2, y: 1.1), CGPoint(x: 1.2, y: -0.1)]
        return [
            Section(outline: [left[0]] + aft + [left[1]], drift: CGPoint(x: rng.range(-0.34 ... -0.22), y: rng.range(0.06...0.16)),
                    turn: rng.range(-38 ... -18)),
            Section(outline: aft + fore.reversed(), drift: CGPoint(x: rng.range(-0.04...0.04), y: rng.range(-0.08 ... -0.02)), turn: rng.range(6...14)),
            Section(outline: fore + right, drift: CGPoint(x: rng.range(0.24...0.36), y: rng.range(-0.22 ... -0.10)), turn: rng.range(22...46)),
        ]
    }

    /// The shards, thrown from the two breaks.
    static func plating(seed: UInt64) -> [Shard] {
        var rng = ArtRandom(seed: ArtSeed.mix(seed, 0x5348_4152))
        return (0..<shards).map { k in
            let a = rng.range(0...(2 * .pi)), d = rng.range(0.18...0.95)
            let from = k % 2 == 0 ? 0.34 : 0.66
            return Shard(origin: CGPoint(x: from - 0.5 + rng.range(-0.05...0.05), y: rng.range(-0.10...0.10)),
                         drift: CGPoint(x: cos(a) * d, y: sin(a) * d * 0.6), size: rng.range(0.006...0.028), spin: rng.range(-2.6...2.6),
                         slender: rng.range(0.18...0.6), painted: rng.unit() < 0.45)
        }
    }

    /// The player's own ship broken into drifting sections, its livery and fittings still recognisable, among cooling
    /// debris and venting gas, the light of the explosion fading on the nearest pieces. No pilot is shown.
    static func killed(_ ctx: inout GraphicsContext, size: CGSize, t: Double, cast: EndingCast, ink: ArtInk) {
        let u = t / duration
        let w = size.width, h = size.height, side = min(w, h)
        space(&ctx, size: size, seed: 0x4B49_4C4C, stars: 1, ink: ink)
        Nebula(seed: 0x4B49_4C4C).draw(&ctx, size: size, accessibility: .standard, ink: ink)
        let seed = ArtSeed.kind(cast.wreck.kind)
        let box = CGRect(x: w * 0.5 - min(w * 0.30, h * 0.52), y: h * 0.26, width: min(w * 0.60, h * 1.04), height: h * 0.48)
        let c = CGPoint(x: box.midX - box.width * 0.02, y: box.midY)
        let fade = (1 - u) * (1 - u)
        let spread = 0.18 + 0.82 * settle(u)
        // The light of the explosion: wide and dim, dying over the four seconds.
        let blast = side * (0.28 + 0.50 * u)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - blast, y: c.y - blast, width: 2 * blast, height: 2 * blast)),
                 with: .radialGradient(Gradient(colors: [ArtRGB(1.0, 0.78, 0.46, 0.50 * fade).color, ArtRGB(1.0, 0.42, 0.16, 0.20 * fade).color,
                                                         ArtRGB(1.0, 0.30, 0.10, 0).color]),
                                       center: c, startRadius: 0, endRadius: blast))
        // Gas venting from the two breaks: a trail of pale puffs, larger and thinner the further they have drifted.
        for (k, x) in [0.34, 0.66].enumerated() {
            let from = CGPoint(x: box.minX + box.width * x, y: box.midY)
            let angle = (k == 0 ? 205.0 : -38.0) * .pi / 180
            for n in 0..<7 {
                let far = (Double(n) + 0.5) / 7 * (0.25 + 0.75 * u)
                let p = CGPoint(x: from.x + cos(angle) * far * side * 0.42 + sin(Double(n) * 2.1) * side * 0.012,
                                y: from.y + sin(angle) * far * side * 0.42 + cos(Double(n) * 1.7) * side * 0.012)
                let r = side * (0.018 + 0.060 * far)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                         with: .radialGradient(Gradient(colors: [ArtRGB(0.82, 0.88, 1.0, 0.16 * (1 - far) * (1 - 0.5 * u)).color,
                                                                 ArtRGB(0.82, 0.88, 1.0, 0).color]),
                                               center: p, startRadius: 0, endRadius: r))
            }
        }
        // The hull sections. Each is the ship itself, clipped to its piece, so livery and fittings stay recognisable.
        for section in hullSections(seed: seed) {
            let outline = section.outline.map { CGPoint(x: box.minX + $0.x * box.width, y: box.minY + $0.y * box.height) }
            let mid = CGPoint(x: outline.map(\.x).reduce(0, +) / Double(outline.count), y: box.midY)
            var piece = ctx
            piece.translateBy(x: section.drift.x * box.width * spread, y: section.drift.y * box.width * spread)
            piece.translateBy(x: mid.x, y: mid.y)
            piece.rotate(by: .degrees(section.turn * spread))
            piece.translateBy(x: -mid.x, y: -mid.y)
            let shape = ArtGeometry.polygon(outline)
            piece.drawLayer { layer in
                layer.clip(to: shape)
                var s = layer
                s.translateBy(x: box.minX, y: box.minY)
                ShipRenderer.draw(&s, size: box.size, model: cast.wreckModel, input: cast.wreck, mode: .fit, ink: ink, sparks: false)
                // Scorch near the breaks, the explosion's light on the side that faces it, and deep shade elsewhere.
                var lit = layer
                lit.blendMode = .sourceAtop
                lit.fill(Path(box.insetBy(dx: -box.width, dy: -box.height)), with: .color(ArtRGB(0.02, 0.02, 0.05, 0.06 + 0.16 * u).color))
                // Starlight from the upper left keeps the cold hull readable once the fire has died.
                lit.fill(Path(box.insetBy(dx: -box.width, dy: -box.height)),
                         with: .linearGradient(Gradient(colors: [ArtRGB(0.70, 0.80, 1.0, 0.20).color, ArtRGB(0.70, 0.80, 1.0, 0).color]),
                                               startPoint: CGPoint(x: box.minX, y: box.minY), endPoint: CGPoint(x: box.midX, y: box.maxY)))
                lit.fill(Path(box.insetBy(dx: -box.width, dy: -box.height)),
                         with: .radialGradient(Gradient(colors: [ArtRGB(1.0, 0.62, 0.30, 0.55 * fade).color, ArtRGB(1.0, 0.45, 0.20, 0).color]),
                                               center: c, startRadius: 0, endRadius: box.width * 0.5))
                // The torn edge: dark metal with embers that cool.
                lit.stroke(shape, with: .color(ArtRGB(0.03, 0.03, 0.04, 0.9).color), lineWidth: max(1, box.height * 0.05))
                lit.stroke(shape, with: .color(ArtRGB(1.0, 0.50, 0.16, 0.85 * fade).color), lineWidth: max(0.5, box.height * 0.014))
            }
        }
        // Shards of plating: thin, tumbling, some still in the ship's paint; lit on the side that faces the blast.
        let paint = cast.wreckModel.geometry.paint
        for shard in plating(seed: seed) {
            let p = CGPoint(x: c.x + (shard.origin.x + shard.drift.x * spread) * box.width, y: c.y + (shard.origin.y + shard.drift.y * spread) * box.width)
            let r = shard.size * side
            var piece = ctx
            piece.translateBy(x: p.x, y: p.y)
            piece.rotate(by: .radians(shard.spin * (0.4 + t)))
            let points = [CGPoint(x: -r, y: -r * shard.slender), CGPoint(x: r * 0.7, y: -r * shard.slender * 0.5), CGPoint(x: r, y: r * shard.slender * 0.8),
                          CGPoint(x: -r * 0.5, y: r * shard.slender)]
            let base = shard.painted ? paint : ArtRGB(0.34, 0.35, 0.38)
            piece.fill(ArtGeometry.polygon(points), with: .color(base.shade(0.55).color))
            piece.fill(ArtGeometry.polygon([points[0], points[1], CGPoint(x: 0, y: 0)]), with: .color(base.shade(1.05).color))
            piece.fill(ArtGeometry.polygon(points), with: .color(ArtRGB(1.0, 0.55, 0.22, 0.45 * fade).color))
        }
    }
}
