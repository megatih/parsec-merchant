// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// ART-020…026, ART-072: a planet portrait: the sphere projection of the baked maps with the vector overlays (orbital
/// ring, satellites, government motif) around it. This is the path of stills, Reduce Motion, vignettes and tests.
public struct PlanetArt: View {
    public var input: PlanetArtInput
    /// `true`: the disk fills the frame and draws no ring or overlays (map mini-planets); `false`: the portrait size rule.
    public var fillsFrame: Bool
    /// The map size to project from; nil picks it from the disk's size on screen.
    public var lod: PlanetLOD?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale

    public init(_ input: PlanetArtInput, fillsFrame: Bool = false, lod: PlanetLOD? = nil) {
        self.input = input
        self.fillsFrame = fillsFrame
        self.lod = lod
    }

    public var body: some View {
        let recipe = PlanetRenderer.recipe(input)
        let input = input, fills = fillsFrame, scale = displayScale, lod = lod
        let ink = ArtInk(scheme: scheme, contrast: input.accessibility.increaseContrast)
        Canvas { ctx, size in
            let frame = PlanetRenderer.Frame(size: size, recipe: recipe, fills: fills)
            if !fills { PlanetLayers.behind(&ctx, rc: recipe, c: frame.center, r: frame.radius, ink: ink) }
            let px = max(1, Int((frame.side * scale).rounded()))
            if let image = PlanetRenderer.image(recipe: recipe, phase: input.phase, accessibility: input.accessibility, pixelSize: px,
                                                radius: frame.radius * scale, ring: !fills, lod: lod) {
                ctx.draw(Image(decorative: image.cgImage, scale: scale), in: frame.square)
            }
            if !fills {
                PlanetLayers.front(&ctx, rc: recipe, c: frame.center, r: frame.radius, phase: input.accessibility.ambientPhase(input.phase),
                                   a11y: input.accessibility, ink: ink)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The vector overlays alone, for the live view: the app draws `.behind`, then its Metal layer, then `.front` (ART-075).
public struct PlanetOverlayArt: View {
    public enum Part: Sendable {
        case behind, front
    }

    public var input: PlanetArtInput
    public var part: Part
    @Environment(\.colorScheme) private var scheme

    public init(_ input: PlanetArtInput, part: Part) {
        self.input = input
        self.part = part
    }

    public var body: some View {
        let recipe = PlanetRenderer.recipe(input)
        let input = input, part = part
        let ink = ArtInk(scheme: scheme, contrast: input.accessibility.increaseContrast)
        Canvas { ctx, size in
            let frame = PlanetRenderer.Frame(size: size, recipe: recipe, fills: false)
            switch part {
            case .behind: PlanetLayers.behind(&ctx, rc: recipe, c: frame.center, r: frame.radius, ink: ink)
            case .front:
                PlanetLayers.front(&ctx, rc: recipe, c: frame.center, r: frame.radius, phase: 0, a11y: input.accessibility, ink: ink)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Recipes, maps and projected images of planets, shared with the map and the app's live view.
public enum PlanetRenderer {
    /// ART-023: where the disk sits in a frame.
    public struct Frame: Sendable {
        public var center: CGPoint
        /// The side of the centred square the projection covers, in points.
        public var side: Double
        /// The disk radius in points.
        public var radius: Double

        public init(size: CGSize, recipe: PlanetRecipe, fills: Bool) {
            side = min(size.width, size.height)
            center = CGPoint(x: size.width / 2, y: size.height / 2)
            let half = side / 2
            radius = fills ? half : half * min(recipe.radiusFraction, 0.98 / recipe.extent)
        }

        public var square: CGRect { CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side) }
    }

    private struct RecipeKey: Hashable {
        var input: PlanetArtInput
    }

    /// The recipe, cached per input (phase and accessibility excluded).
    @MainActor
    public static func recipe(_ input: PlanetArtInput) -> PlanetRecipe {
        var key = input
        key.phase = 0
        key.accessibility = .standard
        return ArtCache.shared.value(RecipeKey(input: key)) { PlanetRecipe.make(key) }
    }

    private struct MapsKey: Hashable, Sendable {
        var recipe: PlanetRecipe
        var lod: PlanetLOD
    }

    /// The baked maps, cached (ART-080). Safe from any thread; a cold hero bake belongs off the main actor (ART-006).
    public static func maps(_ recipe: PlanetRecipe, lod: PlanetLOD) -> PlanetMaps {
        PlanetCache.shared.value(MapsKey(recipe: recipe, lod: lod), bytes: { $0.byteCount }, make: { PlanetTextureBaker.bake(recipe, lod: lod) })
    }

    /// The maps if they are already baked.
    public static func cachedMaps(_ recipe: PlanetRecipe, lod: PlanetLOD) -> PlanetMaps? {
        PlanetCache.shared.peek(MapsKey(recipe: recipe, lod: lod))
    }

    private struct ImageKey: Hashable, Sendable {
        var recipe: PlanetRecipe
        var uniforms: PlanetSphere.Uniforms
        var pixelSize: Int
        var lod: PlanetLOD
    }

    /// The projected image, cached per recipe, uniforms and size.
    public static func image(recipe: PlanetRecipe, phase: Double, accessibility: ArtAccessibility, pixelSize: Int, radius: Double,
                             ring: Bool, lod: PlanetLOD? = nil) -> PlanetImage? {
        let lod = lod ?? PlanetLOD.forDiameter(Int((radius * 2).rounded()))
        let uniforms = PlanetSphere.uniforms(recipe: recipe, phase: phase, accessibility: accessibility, pixelSize: pixelSize,
                                             radius: radius, mapWidth: lod.width, ring: ring)
        let key = ImageKey(recipe: recipe, uniforms: uniforms, pixelSize: pixelSize, lod: lod)
        if let hit: PlanetImage = PlanetCache.shared.peek(key) { return hit }
        guard let cg = PlanetSphere.project(maps(recipe, lod: lod), uniforms: uniforms, pixelSize: pixelSize) else { return nil }
        let image = PlanetImage(cg)
        PlanetCache.shared.insert(key, image, bytes: image.byteCount)
        return image
    }

    /// ART-029: draws a mini-planet sprite of radius `r` points at `c`, projected once per input and pixel size and cached.
    /// `scale` is the sprite's pixels per point.
    @MainActor
    public static func drawSprite(_ ctx: inout GraphicsContext, input: PlanetArtInput, center c: CGPoint, radius r: Double, scale: Double) {
        let pixels = max(4, Int((2 * r * scale).rounded()))
        guard let sprite = sprite(input, pixelDiameter: pixels) else { return }
        ctx.draw(Image(decorative: sprite.cgImage, scale: scale), in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }

    /// ART-029: a mini-planet sprite of `pixelDiameter` pixels: the disk fills the image, `phase = 0`, no ring.
    @MainActor
    public static func sprite(_ input: PlanetArtInput, pixelDiameter: Int) -> PlanetImage? {
        image(recipe: recipe(input), phase: 0, accessibility: .standard, pixelSize: pixelDiameter, radius: Double(pixelDiameter) / 2,
              ring: false)
    }
}
