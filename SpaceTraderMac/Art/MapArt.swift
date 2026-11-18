// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecArt
import ParsecEngine
import SwiftUI

/// MAP-095: the procedural-art options of a map render.
struct MapArt: Equatable, Sendable {
    var galaxySeed: UInt64
    var reduceTransparency: Bool
    /// The wormhole vortices are drawn (turning) by the overlay canvas instead of the static main canvas.
    var vorticesInOverlay: Bool
}

/// MAP-095, ART-029: starfield and nebula behind the map, and mini-planets from zoom 4.
enum MapArtRenderer {
    /// The map is drawn on deep space in both appearances, so the art uses the dark palette.
    static let ink = ArtInk(scheme: .dark, contrast: false)
    /// Parallax factors of the nebula and the three star layers relative to the map pan.
    static let parallax = (nebula: 0.3, stars: [0.3, 0.45, 0.6])
    static let planetZoom = 4.0

    static func drawsPlanets(zoom: Double) -> Bool { zoom >= planetZoom }

    /// The pan of the map in points (the galaxy origin at the top-left, scaled).
    static func pan(_ projection: MapProjection) -> CGPoint {
        CGPoint(x: -projection.origin.x * projection.scale, y: -projection.origin.y * projection.scale)
    }

    static func drawSpace(_ ctx: inout GraphicsContext, size: CGSize, projection: MapProjection, art: MapArt) {
        let pan = pan(projection)
        Nebula(seed: art.galaxySeed).draw(&ctx, size: size, offset: CGPoint(x: pan.x * parallax.nebula, y: pan.y * parallax.nebula),
                                          accessibility: ArtAccessibility(reduceTransparency: art.reduceTransparency), ink: ink)
        let offsets = parallax.stars.map { CGPoint(x: pan.x * $0, y: pan.y * $0) }
        Starfield(seed: art.galaxySeed, density: 0.3).draw(&ctx, size: size, offsets: offsets)
    }

    /// ART-020/029: the same input as the Bridge portrait, without the pressure.
    static func planetInput(_ system: MapSystem, galaxySeed: UInt64) -> PlanetArtInput {
        PlanetArtInput(seed: ArtSeed.system(galaxySeed: galaxySeed, index: system.index), sizeClass: system.size.rawValue,
                       tech: min(7, system.techLevel.rawValue), government: system.politics.rawValue, resource: system.knownResource?.rawValue,
                       pressure: nil)
    }

    /// The pixel scale of mini-planet sprites: sharp on 2x displays, and one projection per system and radius.
    static let spriteScale = 2.0

    /// ART-029: a mini-planet sprite (projected once, cached) with the M8 glyph kept as an outline ring: solid for visited,
    /// dashed for unvisited (the shape twin).
    static func drawPlanet(_ ctx: inout GraphicsContext, system: MapSystem, center c: CGPoint, radius r: Double, filled: Bool, art: MapArt) {
        PlanetRenderer.drawSprite(&ctx, input: planetInput(system, galaxySeed: art.galaxySeed), center: c, radius: r, scale: spriteScale)
        let ring = Path(ellipseIn: CGRect(x: c.x - r - 1.5, y: c.y - r - 1.5, width: 2 * r + 3, height: 2 * r + 3))
        if filled {
            ctx.stroke(ring, with: .color(MapStyle.visited), lineWidth: 1.4)
        } else {
            ctx.stroke(ring, with: .color(MapStyle.unvisited), style: StrokeStyle(lineWidth: 1.4, dash: [2.5, 2]))
        }
    }
}
