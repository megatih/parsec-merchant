// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecArt
import SwiftUI

/// ART-075, ART-076: the Bridge planet. It is the live Metal view (a display link outside SwiftUI's update cycle, ART-052)
/// when that is possible, and the CPU still otherwise: under Reduce Motion, without a Metal device or pipeline, and while
/// the hero maps are being baked off the main actor.
struct PlanetPortrait: View {
    let input: PlanetArtInput
    @Environment(\.appearsActive) private var appearsActive
    @State private var heroMaps: PlanetMaps?

    var body: some View {
        let recipe = PlanetRenderer.recipe(input)
        ArtAccessibilityReader { a11y in
            let renderer = a11y.reduceMotion ? nil : PlanetMetalRenderer.shared
            let mode = PlanetLiveSupport.mode(reduceMotion: a11y.reduceMotion, deviceAvailable: renderer != nil, pipelineReady: renderer != nil)
            if mode == .live, let renderer, let maps = heroMaps {
                ZStack {
                    PlanetOverlayArt(Self.with(input, a11y), part: .behind)
                    // The layer fills its view, so the view is the centred square the projection covers (PlanetRenderer.Frame).
                    PlanetMetalView(renderer: renderer, recipe: recipe, maps: maps, accessibility: a11y, appearsActive: appearsActive)
                        .aspectRatio(1, contentMode: .fit)
                        .allowsHitTesting(false)
                    PlanetOverlayArt(Self.with(input, a11y), part: .front)
                }
            } else {
                // Until the hero maps exist the still comes from the small maps, so nothing blocks the main actor.
                PlanetArt(Self.with(input, a11y), lod: heroMaps == nil ? .still : nil)
            }
        }
        .task(id: recipe) {
            heroMaps = PlanetRenderer.cachedMaps(recipe, lod: .hero)
            if heroMaps == nil {
                heroMaps = await Task.detached(priority: .userInitiated) { PlanetRenderer.maps(recipe, lod: .hero) }.value
            }
        }
    }

    static func with(_ input: PlanetArtInput, _ a11y: ArtAccessibility) -> PlanetArtInput {
        var i = input
        i.accessibility = a11y
        i.phase = 0
        return i
    }
}

/// ART-077: the hero stage of the Bridge system card: the system's star glow and a dense starfield behind the planet.
struct PlanetHero: View {
    let input: PlanetArtInput
    /// The square stage beside the facts, and the height of the full-width stage above them.
    static let besideSide: CGFloat = 240
    static let stackedHeight: CGFloat = 230
    /// The narrowest facts column that may sit beside the stage.
    static let factsMinWidth: CGFloat = 250
    static let spacing: CGFloat = 16
    /// The card content width from which the stage sits beside the facts.
    static var besideMinWidth: CGFloat { besideSide + spacing + factsMinWidth }

    var body: some View {
        ZStack {
            ArtAccessibilityReader { a11y in HeroBackdrop(seed: input.seed, accessibility: a11y) }
            PlanetPortrait(input: input).padding(6)
        }
    }
}
