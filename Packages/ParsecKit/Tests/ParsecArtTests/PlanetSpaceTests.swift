// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import Testing
@testable import ParsecArt

@MainActor
@Suite("Planets and space")
struct PlanetSpaceTests {
    static let size = CGSize(width: 120, height: 120)

    static func render(_ input: PlanetArtInput, scheme: ColorScheme = .light) -> ArtPixels {
        ArtSnapshot.render(PlanetArt(input), size: size, scheme: scheme)
    }

    @Test("ART-020 PlanetArtInput clamps its attributes and carries optional resource and pressure")
    func input() {
        let i = PlanetArtInput(seed: 1, sizeClass: 9, tech: 12, government: 40, resource: nil, pressure: nil)
        #expect(i.sizeClass == 5 && i.tech == 7 && i.government == 16)
        #expect(PlanetRecipe.make(i).look == nil && PlanetRecipe.make(i).pressure == nil)
    }

    @Test("ART-021 recipes are pure: equal inputs give equal recipes; 200 seeds give at least 195 distinct recipes")
    func recipes() {
        let a = PlanetArtInput(seed: 77, sizeClass: 3, tech: 5, government: 2, resource: 4)
        #expect(PlanetRecipe.make(a) == PlanetRecipe.make(a))
        var distinct = Set<PlanetRecipe>()
        for s in 0..<200 {
            var i = a
            i.seed = UInt64(s)
            let r = PlanetRecipe.make(i)
            #expect((3...7).contains(r.continents.count))
            #expect(r.tilt >= -25 && r.tilt <= 25)
            distinct.insert(r)
        }
        #expect(distinct.count >= 195)
    }

    @Test("ART-022 eight tech styles; night lights only on the night side; rings and satellites by style")
    func styles() {
        #expect(PlanetStyle.allCases.count == 8)
        #expect(PlanetStyle.preAgricultural.nightLights == 0 && PlanetStyle.preAgricultural.dayDots == 0)
        #expect(PlanetStyle.hiTech.ring == .full && PlanetStyle.hiTech.satellites == 2)
        #expect(PlanetStyle.postIndustrial.ring == .partial && PlanetStyle.industrial.ring == .none)
        for tech in 5...7 {
            let rc = PlanetRecipe.make(PlanetArtInput(seed: 12, tech: tech))
            let c = CGPoint(x: 50, y: 50), r = 40.0
            let night = PlanetRenderer.nightPath(c: c, r: r)
            let lights = PlanetLayers.lightPoints(rc, night: night, c: c, r: r)
            #expect(!lights.isEmpty)
            #expect(lights.allSatisfy { night.contains($0) })
            // ART-052: the cached night layer (computed once, not per frame) equals the direct computation, also on a hit.
            for _ in 0..<2 {
                let layer = PlanetRenderer.nightLayer(rc, c: c, r: r)
                #expect(layer.lights == lights && layer.path == night)
            }
        }
        let renders = (0..<8).map { Self.render(PlanetArtInput(seed: 5, tech: $0)) }
        #expect(Set(renders.map(\.fingerprint)).count == 8, "\(renders.map { $0.fingerprint.prefix(6) })")
    }

    @Test("ART-023 portrait radius 0.55 + 0.08 × size; one motif per government")
    func sizeAndMotif() {
        for s in 0...5 { #expect(abs(PlanetRecipe.make(PlanetArtInput(seed: 1, sizeClass: s)).radiusFraction - (0.55 + 0.08 * Double(s))) < 1e-12) }
        #expect(GovernmentMotif.table.count == 17)
        let expected: [GovernmentMotif] = [.debrisField, .beacons, .grid, .beacons, .beacons, .grid, .none, .defensePlatforms, .defensePlatforms,
                                           .none, .defensePlatforms, .none, .halo, .grid, .halo, .grid, .halo]
        #expect(GovernmentMotif.table == expected)
        let widths = [0, 5].map { Self.render(PlanetArtInput(seed: 2, sizeClass: $0, tech: 0, government: 6)).maskWidth }
        #expect(widths[1] > widths[0])
    }

    @Test("ART-024 a known resource tints the palette; nothing and unknown use the seed palette")
    func resources() {
        let base = PlanetArtInput(seed: 21, tech: 0, government: 6)
        #expect(PlanetRecipe.make(base) == PlanetRecipe.make(PlanetArtInput(seed: 21, tech: 0, government: 6, resource: 0)).with(look: nil))
        var looks = Set<String>()
        for r in 0...12 {
            var i = base
            i.resource = r
            looks.insert(Self.render(i).fingerprint)
        }
        #expect(looks.count >= 12) // nothing equals the seed palette
        #expect(PlanetRecipe.make(PlanetArtInput(seed: 1, resource: 3)).land == .landSand)
        #expect(PlanetRecipe.make(PlanetArtInput(seed: 1, resource: 8)).clouds.isEmpty)
        #expect(PlanetRecipe.make(PlanetArtInput(seed: 1, resource: 4)).landRatio < 0.2)
    }

    @Test("ART-025 pressure overlays decorate only when shown; war flashes are static under Reduce Motion")
    func pressure() {
        let base = PlanetArtInput(seed: 8, tech: 3, government: 6)
        let none = Self.render(base)
        for p in [4, 7] {
            var i = base
            i.pressure = p
            #expect(Self.render(i) == none, "boredom and employment draw nothing")
        }
        for p in [1, 2, 3, 5, 6] {
            var i = base
            i.pressure = p
            #expect(Self.render(i) != none, "pressure \(p)")
        }
        var war = base
        war.pressure = 1
        war.accessibility = ArtAccessibility(reduceMotion: true)
        var later = war
        later.phase = 0.4
        #expect(Self.render(war) == Self.render(later))
    }

    @Test("ART-026 the surface turns once per 60 s; Reduce Motion freezes it; Reduce Transparency makes clouds opaque")
    func motion() {
        let base = PlanetArtInput(seed: 5, tech: 6, government: 6)
        var turned = base
        turned.phase = 60
        var mid = base
        mid.phase = 17
        #expect(Self.render(base) == Self.render(turned))
        #expect(Self.render(base) != Self.render(mid))
        var reduced = mid
        reduced.accessibility = ArtAccessibility(reduceMotion: true)
        #expect(Self.render(reduced) == Self.render(PlanetArtInput(seed: 5, tech: 6, government: 6, accessibility: ArtAccessibility(reduceMotion: true))))
        var opaque = base
        opaque.accessibility = ArtAccessibility(reduceTransparency: true)
        #expect(Self.render(opaque) != Self.render(base))
    }

    @Test("ART-027 the starfield is pure: at most 600 stars per tile in three layers, radius 0.3…1.6 pt")
    func starfield() {
        let f = Starfield(seed: 9, density: 1)
        let tile = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let counts = (0..<3).map { f.stars(in: tile, layer: $0).count }
        #expect(counts.reduce(0, +) <= 600 && counts.allSatisfy { $0 > 0 })
        #expect(f.stars(in: tile, layer: 1) == f.stars(in: tile, layer: 1))
        for layer in 0..<3 { #expect(f.stars(in: tile, layer: layer).allSatisfy { $0.radius >= 0.3 && $0.radius <= 1.6 }) }
        let wide = f.stars(in: CGRect(x: -500, y: -500, width: 2000, height: 2000), layer: 0)
        #expect(wide.count > counts[0])
        let still = ArtSnapshot.render(StarfieldView(seed: 1, phase: 0, animated: true), size: Self.size)
        #expect(still != ArtSnapshot.render(StarfieldView(seed: 1, phase: 1.5, animated: true), size: Self.size))
        #expect(ArtSnapshot.render(StarfieldView(seed: 1, phase: 1.5, animated: true, accessibility: ArtAccessibility(reduceMotion: true)), size: Self.size)
            == ArtSnapshot.render(StarfieldView(seed: 1, phase: 0, animated: true, accessibility: ArtAccessibility(reduceMotion: true)), size: Self.size))
        #expect(ArtSnapshot.render(StarfieldView(seed: 1, phase: 1.5), size: Self.size) == ArtSnapshot.render(StarfieldView(seed: 1), size: Self.size))
    }

    @Test("ART-028 the nebula has 3–5 blobs at ≤ 18% opacity and is omitted under Reduce Transparency")
    func nebula() {
        for s in 0..<50 {
            let blobs = Nebula(seed: UInt64(s)).blobs
            #expect((3...5).contains(blobs.count))
            #expect(blobs.allSatisfy { $0.opacity <= 0.18 })
        }
        #expect(ArtSnapshot.render(NebulaView(seed: 3), size: Self.size).alphaSum > 0)
        #expect(ArtSnapshot.render(NebulaView(seed: 3, accessibility: ArtAccessibility(reduceTransparency: true)), size: Self.size).alphaSum == 0)
    }

    @Test("ART-030 MAP-095 the vortex turns once per 6 s, equals the M8 geometry at phase 0, and is static under Reduce Motion")
    func vortex() {
        let c = CGPoint(x: 10, y: 20)
        let arms = WormholeVortex.arms(center: c, radius: 8, phase: 0)
        for k in 0..<3 {
            var m8 = Path()
            let start = Angle.degrees(Double(k) * 120)
            m8.addArc(center: c, radius: 8 * (0.45 + 0.25 * Double(k)), startAngle: start, endAngle: start + .degrees(200), clockwise: false)
            #expect(arms[k].description == m8.description)
        }
        let full = WormholeVortex.arms(center: c, radius: 8, phase: 6).map(\.boundingRect)
        for (a, b) in zip(full, arms.map(\.boundingRect)) { #expect(abs(a.minX - b.minX) < 1e-3 && abs(a.maxY - b.maxY) < 1e-3) }
        let a0 = ArtSnapshot.render(WormholeVortexView(phase: 0), size: Self.size)
        #expect(a0 != ArtSnapshot.render(WormholeVortexView(phase: 1.5), size: Self.size))
        #expect(a0 == ArtSnapshot.render(WormholeVortexView(phase: 1.5, accessibility: ArtAccessibility(reduceMotion: true)), size: Self.size))
    }

    @Test("ART-061 planets: every style × size, motif, resource and pressure renders identically twice and non-empty; seeds differ")
    func planetDeterminism() {
        var inputs: [PlanetArtInput] = []
        for tech in 0...7 { for size in 0...5 { inputs.append(PlanetArtInput(seed: 42, sizeClass: size, tech: tech, government: 6)) } }
        for g in 0...16 { inputs.append(PlanetArtInput(seed: 42, tech: 4, government: g)) }
        for r in 0...12 { inputs.append(PlanetArtInput(seed: 42, tech: 4, government: 6, resource: r)) }
        for p in 0...7 { inputs.append(PlanetArtInput(seed: 42, tech: 4, government: 6, pressure: p)) }
        for input in inputs {
            let (a, b) = ArtSnapshot.twice(PlanetArt(input), size: Self.size)
            #expect(a.fingerprint == b.fingerprint)
            #expect(a.isNonEmpty(lo: 0.05, hi: 1), "\(input)")
        }
        #expect(Self.render(PlanetArtInput(seed: 1, tech: 3)) != Self.render(PlanetArtInput(seed: 2, tech: 3)))
    }
}

extension PlanetRecipe {
    func with(look: PlanetResourceLook?) -> PlanetRecipe {
        var r = self
        r.look = look
        return r
    }
}
