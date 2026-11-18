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

    /// The portrait frame of the bulk tests: small enough that the disk uses the `still` maps.
    static let small = CGSize(width: 60, height: 60)

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
            #expect(r.tilt >= -25 && r.tilt <= 25)
            #expect(r.planetClass == .ocean)
            distinct.insert(r)
        }
        #expect(distinct.count >= 195)
    }

    @Test("ART-022 tech layers: the table; city lights only on the night side; orbital ring and satellites by style")
    func styles() throws {
        #expect(PlanetStyle.allCases.count == 8)
        #expect(PlanetStyle.allCases.map(\.farmland) == [0, 0.5, 0.7, 0.8, 0.6, 0.5, 0.3, 0.2])
        #expect(PlanetStyle.allCases.map(\.cityLights) == [0, 0.012, 0.03, 0.07, 0.15, 0.30, 0.55, 0.90])
        #expect(PlanetStyle.allCases.map(\.smog) == [0, 0, 0, 0, 0.25, 0.40, 0.15, 0])
        #expect(PlanetStyle.hiTech.ring == .full && PlanetStyle.hiTech.satellites == 2)
        #expect(PlanetStyle.postIndustrial.ring == .partial && PlanetStyle.industrial.ring == .none)
        // The projector shows the lights channel only where the sun is down: switching it off changes night pixels only.
        let n = 160
        for tech in 5...7 {
            let rc = PlanetRecipe.make(PlanetArtInput(seed: 12, tech: tech, resource: 5))
            let maps = PlanetTextureBaker.bake(rc, lod: .hero)
            #expect(stride(from: 1, to: maps.aux.count, by: 4).contains { maps.aux[$0] > 64 })
            var u = PlanetSphere.uniforms(recipe: rc, phase: 0, pixelSize: n, radius: 70, mapWidth: maps.width)
            let lit = PlanetSphere.pixels(maps, uniforms: u, pixelSize: n)
            u.night.w = 0
            let dark = PlanetSphere.pixels(maps, uniforms: u, pixelSize: n)
            let l = PlanetSphere.lightDirection
            var changed = 0
            for y in 0..<n {
                for x in 0..<n where (0..<3).contains(where: { lit[(y * n + x) * 4 + $0] != dark[(y * n + x) * 4 + $0] }) {
                    changed += 1
                    let qx = (Float(x) + 0.5 - 80) / 70, qy = (80 - Float(y) - 0.5) / 70
                    let z = max(0, 1 - qx * qx - qy * qy).squareRoot()
                    #expect(qx * l.x + qy * l.y + z * l.z < 0.23, "a light on the day side at \(x),\(y)")
                }
            }
            #expect(changed > 0, "tech \(tech)")
        }
        let renders = (0..<8).map { Self.render(PlanetArtInput(seed: 5, tech: $0, resource: 5)) }
        #expect(Set(renders.map(\.fingerprint)).count == 8, "\(renders.map { $0.fingerprint.prefix(6) })")
    }

    @Test("ART-023 portrait radius 0.55 + 0.08 × size, reduced to fit a ring; mini-planets fill the frame; one motif per government")
    func sizeAndMotif() {
        for s in 0...5 { #expect(abs(PlanetRecipe.make(PlanetArtInput(seed: 1, sizeClass: s)).radiusFraction - (0.55 + 0.08 * Double(s))) < 1e-12) }
        #expect(GovernmentMotif.table.count == 17)
        let expected: [GovernmentMotif] = [.debrisField, .beacons, .grid, .beacons, .beacons, .grid, .none, .defensePlatforms, .defensePlatforms,
                                           .none, .defensePlatforms, .none, .halo, .grid, .halo, .grid, .halo]
        #expect(GovernmentMotif.table == expected)
        let widths = [0, 5].map { Self.render(PlanetArtInput(seed: 2, sizeClass: $0, tech: 0, government: 6, resource: 8)).maskWidth }
        #expect(widths[1] > widths[0])
        let frame = CGSize(width: 100, height: 100)
        let plain = PlanetRecipe.make(PlanetArtInput(seed: 2, sizeClass: 5, tech: 0, government: 6, resource: 8))
        #expect(abs(PlanetRenderer.Frame(size: frame, recipe: plain, fills: false).radius - 47.5) < 1e-9)
        #expect(PlanetRenderer.Frame(size: frame, recipe: plain, fills: true).radius == 50)
        var ringed = plain
        ringed.ring = PlanetNaturalRing(inner: 1.3, outer: 2.0, opacity: 0.7, seed: 1, tint: 0)
        #expect(abs(PlanetRenderer.Frame(size: frame, recipe: ringed, fills: false).radius - 50 * 0.98 / 2.0) < 1e-9)
        // Every motif draws something of its own.
        let base = Self.render(PlanetArtInput(seed: 2, tech: 0, government: 6, resource: 5))
        for g in [0, 1, 2, 7, 12] { #expect(Self.render(PlanetArtInput(seed: 2, tech: 0, government: g, resource: 5)) != base, "government \(g)") }
    }

    @Test("ART-024 a known resource decides the class and tint; nothing and unknown use the seed look")
    func resources() {
        let base = PlanetArtInput(seed: 21, tech: 0, government: 6)
        #expect(PlanetRecipe.make(base) == PlanetRecipe.make(PlanetArtInput(seed: 21, tech: 0, government: 6, resource: 0)).with(look: nil))
        let seedLook = Self.render(base).fingerprint
        var looks = Set<String>()
        for r in 1...12 {
            var i = base
            i.resource = r
            let print = Self.render(i).fingerprint
            #expect(print != seedLook, "resource \(r)")
            looks.insert(print)
        }
        #expect(looks.count == 12)
        #expect(PlanetRecipe.make(PlanetArtInput(seed: 1, resource: 3)).planetClass == .desert)
        #expect(PlanetRecipe.make(PlanetArtInput(seed: 1, resource: 8)).cloudCover == 0)
        #expect(PlanetRecipe.make(PlanetArtInput(seed: 1, resource: 4)).landRatio < 0.2)
    }

    @Test("ART-025 pressure overlays decorate only when shown; war fires flicker and are steady under Reduce Motion")
    func pressure() {
        let base = PlanetArtInput(seed: 8, tech: 3, government: 6, resource: 5)
        let none = Self.render(base)
        for p in [0, 4, 7] {
            var i = base
            i.pressure = p
            #expect(Self.render(i) == none, "none, boredom and employment draw nothing")
        }
        for p in [1, 2, 3, 5, 6] {
            var i = base
            i.pressure = p
            #expect(Self.render(i) != none, "pressure \(p)")
        }
        var war = base
        war.pressure = 1
        var later = war
        later.phase = 0.4
        #expect(Self.render(war) != Self.render(later))
        war.accessibility = ArtAccessibility(reduceMotion: true)
        later.accessibility = war.accessibility
        #expect(Self.render(war) == Self.render(later))
        let maps = PlanetTextureBaker.bake(PlanetRecipe.make(war), lod: .still)
        #expect(stride(from: 2, to: maps.aux.count, by: 4).contains { maps.aux[$0] > 128 }, "war fires are emissive")
    }

    @Test("ART-026 surface 24 s, clouds 20 s, bands 15 s; phase 600 equals phase 0; Reduce Motion freezes; Reduce Transparency and Increase Contrast")
    func motion() {
        #expect(PlanetSphere.surfacePeriod == 24 && PlanetSphere.cloudPeriod == 20 && PlanetSphere.bandPeriod == 15)
        for period in [PlanetSphere.surfacePeriod, PlanetSphere.cloudPeriod, PlanetSphere.bandPeriod] {
            #expect(PlanetSphere.phaseWrap.truncatingRemainder(dividingBy: period) == 0)
        }
        let base = PlanetArtInput(seed: 5, tech: 6, government: 6, resource: 5)
        func at(_ phase: Double, _ a11y: ArtAccessibility = .standard) -> ArtPixels {
            var i = base
            i.phase = phase
            i.accessibility = a11y
            return Self.render(i)
        }
        #expect(at(0) == at(600))
        #expect(at(0) != at(6))
        #expect(at(0) != at(24), "the clouds have their own period")
        #expect(at(0) == at(120), "24 s and 20 s meet again after 120 s")
        let reduced = ArtAccessibility(reduceMotion: true)
        #expect(at(17, reduced) == at(0, reduced))
        #expect(at(0, ArtAccessibility(reduceTransparency: true)) != at(0))
        #expect(at(0, ArtAccessibility(increaseContrast: true)) != at(0))
        // A gas giant's bands turn once per 15 s.
        let giant = PlanetRecipe.make(PlanetArtInput(seed: PlanetSphereTests.seed(for: .gasGiant, size: 4), sizeClass: 4))
        let u0 = PlanetSphere.uniforms(recipe: giant, phase: 0, pixelSize: 64, radius: 30, mapWidth: 128)
        #expect(PlanetSphere.uniforms(recipe: giant, phase: 15, pixelSize: 64, radius: 30, mapWidth: 128).turn.x == u0.turn.x)
        #expect(PlanetSphere.uniforms(recipe: giant, phase: 7.5, pixelSize: 64, radius: 30, mapWidth: 128).turn.x == 0.5)
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

    @Test("ART-061 planets: every class × size, tech level, motif, resource and pressure renders identically twice and non-empty; seeds differ")
    func planetDeterminism() {
        var inputs: [PlanetArtInput] = []
        for cls in PlanetClass.allCases {
            for size in 0...5 where cls != .gasGiant || size >= PlanetClass.gasGiantMinimumSize {
                inputs.append(PlanetArtInput(seed: PlanetSphereTests.seed(for: cls, size: size), sizeClass: size, tech: 4, government: 6))
            }
        }
        for tech in 0...7 { inputs.append(PlanetArtInput(seed: 42, tech: tech, government: 6, resource: 5)) }
        for g in 0...16 { inputs.append(PlanetArtInput(seed: 42, tech: 4, government: g)) }
        for r in 0...12 { inputs.append(PlanetArtInput(seed: 42, tech: 4, government: 6, resource: r)) }
        for p in 0...7 { inputs.append(PlanetArtInput(seed: 42, tech: 4, government: 6, pressure: p)) }
        #expect(Set(inputs.map { PlanetRecipe.make($0).planetClass }).count == 10)
        for input in inputs {
            let (a, b) = ArtSnapshot.twice(PlanetArt(input), size: Self.small)
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
