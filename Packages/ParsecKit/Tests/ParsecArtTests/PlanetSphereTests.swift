// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import Testing
@testable import ParsecArt

/// Statistics of baked maps (ART-071).
struct MapStats {
    var water = 0.0
    var luminance = 0.0
    var saturation = 0.0
    var cloud = 0.0
    var lights = 0.0
    var emissive = 0.0
    var landRGB = (r: 0.0, g: 0.0, b: 0.0)
    var mean = (r: 0.0, g: 0.0, b: 0.0)
    /// The variance of the row means of luminance over the mean variance within rows.
    var banding = 0.0

    /// Every share and mean is weighted by the texel's area on the sphere (the cosine of its latitude).
    init(_ maps: PlanetMaps) {
        var n = 0.0, land = 0.0
        var rowMeans: [Double] = [], within = 0.0
        for y in 0..<maps.height {
            let w = cos((0.5 - (Double(y) + 0.5) / Double(maps.height)) * Double.pi)
            var row: [Double] = []
            for x in 0..<maps.width {
                let i = (y * maps.width + x) * 4
                let r = Double(maps.albedo[i]) / 255, g = Double(maps.albedo[i + 1]) / 255, b = Double(maps.albedo[i + 2]) / 255
                let lum = 0.299 * r + 0.587 * g + 0.114 * b
                row.append(lum)
                n += w
                luminance += lum * w
                saturation += (max(r, g, b) - min(r, g, b)) * w
                mean.r += r * w
                mean.g += g * w
                mean.b += b * w
                if maps.albedo[i + 3] >= 128 {
                    water += w
                } else {
                    land += w
                    landRGB.r += r * w
                    landRGB.g += g * w
                    landRGB.b += b * w
                }
                cloud += Double(maps.aux[i]) / 255 * w
                if maps.aux[i + 1] > 64 { lights += w }
                if maps.aux[i + 2] > 64 { emissive += w }
            }
            let m = row.reduce(0, +) / Double(row.count)
            rowMeans.append(m)
            within += row.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(row.count)
        }
        water /= n
        luminance /= n
        saturation /= n
        cloud /= n
        lights /= n
        emissive /= n
        mean = (mean.r / n, mean.g / n, mean.b / n)
        if land > 0 { landRGB = (landRGB.r / land, landRGB.g / land, landRGB.b / land) }
        let all = rowMeans.reduce(0, +) / Double(rowMeans.count)
        let between = rowMeans.reduce(0) { $0 + ($1 - all) * ($1 - all) } / Double(rowMeans.count)
        banding = between / max(within / Double(maps.height), 1e-9)
    }
}

@MainActor
@Suite("Planet sphere")
struct PlanetSphereTests {
    /// The first seed at or after `start` whose seed-weighted class is `cls` at `size`.
    static func seed(for cls: PlanetClass, size: Int, from start: UInt64 = 1) -> UInt64 {
        var s = start
        while PlanetRecipe.make(PlanetArtInput(seed: s, sizeClass: size)).planetClass != cls { s += 1 }
        return s
    }

    static func recipes(_ cls: PlanetClass, count: Int = 12) -> [PlanetRecipe] {
        var out: [PlanetRecipe] = [], next: UInt64 = 1
        while out.count < count {
            let s = seed(for: cls, size: 4, from: next)
            out.append(PlanetRecipe.make(PlanetArtInput(seed: s, sizeClass: 4, tech: cls == .volcanic ? 0 : 4)))
            next = s + 1
        }
        return out
    }

    @Test("ART-068 ten classes in order; seed weights; gas giants only from large; rings only where allowed")
    func taxonomy() {
        #expect(PlanetClass.allCases == [.terran, .ocean, .desert, .ice, .jungle, .rocky, .barren, .volcanic, .toxic, .gasGiant])
        #expect(PlanetClass.weights == [22, 10, 12, 10, 8, 12, 8, 6, 4, 8])
        for size in 0...5 {
            var counts = [PlanetClass: Int]()
            var rings = [PlanetClass: Int]()
            let n = 2000
            for s in 0..<n {
                let rc = PlanetRecipe.make(PlanetArtInput(seed: UInt64(s) &* 7919 &+ UInt64(size), sizeClass: size))
                counts[rc.planetClass, default: 0] += 1
                if rc.ring != nil { rings[rc.planetClass, default: 0] += 1 }
            }
            var weights = PlanetClass.weights
            if size < 3 { weights[PlanetClass.gasGiant.rawValue] = 0 }
            let total = weights.reduce(0, +)
            for cls in PlanetClass.allCases {
                let share = Double(counts[cls] ?? 0) / Double(n)
                #expect(abs(share - weights[cls.rawValue] / total) < 0.05, "\(cls) at size \(size): \(share)")
                if weights[cls.rawValue] > 0 { #expect((counts[cls] ?? 0) > 0) }
                if cls.ringChance == 0 { #expect(rings[cls] == nil, "\(cls) has a ring") }
            }
            if size < 3 { #expect(counts[.gasGiant] == nil) } else { #expect((rings[.gasGiant] ?? 0) > 0) }
        }
        #expect(PlanetClass.gasGiant.ringChance == 0.6 && PlanetClass.ice.ringChance == 0.08 && PlanetClass.terran.ringChance == 0)
    }

    @Test("ART-069 the resource-to-class table is total over size × resource")
    func resourceTable() {
        let expected: [Int: (PlanetClass, PlanetTint)] = [1: (.rocky, .ore), 2: (.rocky, .dull), 3: (.desert, .none), 4: (.ocean, .none),
                                                          5: (.terran, .fertile), 6: (.terran, .pale), 7: (.jungle, .none), 8: (.barren, .none),
                                                          9: (.toxic, .fungal), 10: (.jungle, .herbal)]
        #expect(PlanetResourceLook.allCases.count == 13)
        for size in 0...5 {
            for resource in 0...12 {
                for seed in [UInt64(3), 90, 4242] {
                    let rc = PlanetRecipe.make(PlanetArtInput(seed: seed, sizeClass: size, resource: resource))
                    if let e = expected[resource] {
                        #expect(rc.planetClass == e.0 && rc.tint == e.1, "resource \(resource) size \(size)")
                    } else {
                        // Nothing, artistic and warlike keep the seed-weighted class.
                        #expect(rc.planetClass == PlanetRecipe.make(PlanetArtInput(seed: seed, sizeClass: size)).planetClass)
                        #expect(rc.tint == .none)
                    }
                    #expect(rc.accent == (resource == 11 ? .artistic : (resource == 12 ? .warlike : .none)))
                }
            }
        }
    }

    @Test("ART-070 the baker is deterministic, the same on any thread, and its LODs sample one field")
    func baker() async {
        #expect(PlanetLOD.allCases.map(\.width) == [64, 128, 512] && PlanetLOD.allCases.map(\.height) == [32, 64, 256])
        for cls in [PlanetClass.terran, .gasGiant, .barren] {
            let rc = Self.recipes(cls, count: 1)[0]
            let a = PlanetTextureBaker.bake(rc, lod: .still)
            #expect(a == PlanetTextureBaker.bake(rc, lod: .still))
            #expect(a.albedo.count == 128 * 64 * 4 && a.aux.count == a.albedo.count)
            let background = await Task.detached { PlanetTextureBaker.bake(rc, lod: .still) }.value
            #expect(background == a)
            let stats = PlanetLOD.allCases.map { MapStats(PlanetTextureBaker.bake(rc, lod: $0)) }
            for s in stats.dropFirst() {
                #expect(abs(s.water - stats[0].water) < 0.04, "\(cls) water")
                #expect(abs(s.mean.r - stats[0].mean.r) < 0.04 && abs(s.mean.g - stats[0].mean.g) < 0.04 && abs(s.mean.b - stats[0].mean.b) < 0.04,
                        "\(cls) colour")
            }
        }
    }

    @Test("ART-071 each class is recognisable from its map statistics; terran seeds differ")
    func classLooks() {
        for cls in PlanetClass.allCases {
            for rc in Self.recipes(cls) {
                let s = MapStats(PlanetTextureBaker.bake(rc, lod: .still))
                switch cls {
                case .terran: #expect(s.water >= 0.40 && s.water <= 0.80, "terran water \(s.water)")
                case .ocean: #expect(s.water >= 0.80, "ocean water \(s.water)")
                case .desert: #expect(s.water == 0)
                case .ice: #expect(s.luminance >= 0.70, "ice luminance \(s.luminance)")
                case .jungle: #expect(s.landRGB.g > s.landRGB.r && s.landRGB.g > s.landRGB.b, "jungle land \(s.landRGB)")
                case .rocky: #expect(s.water == 0)
                case .barren: #expect(s.water == 0 && s.cloud == 0 && s.saturation < 0.06, "barren \(s.saturation)")
                case .volcanic: #expect(s.water == 0 && s.emissive >= 0.02 && s.emissive <= 0.30, "volcanic emissive \(s.emissive)")
                case .toxic: #expect(s.cloud >= 0.55, "toxic cloud \(s.cloud)")
                case .gasGiant: #expect(s.water == 0 && s.lights == 0 && s.banding > 4, "gas giant banding \(s.banding)")
                }
            }
        }
        let terran = Self.recipes(.terran, count: 2).map { PlanetTextureBaker.bake($0, lod: .still) }
        var differing = 0
        for i in stride(from: 0, to: terran[0].albedo.count, by: 4) where (0..<3).contains(where: {
            abs(Int(terran[0].albedo[i + $0]) - Int(terran[1].albedo[i + $0])) > 12
        }) { differing += 1 }
        #expect(Double(differing) / Double(terran[0].albedo.count / 4) >= 0.25)
    }

    @Test("ART-072 the projector: size, transparent corners, lit and dark limb, ring, tilt, determinism")
    func projector() throws {
        var rc = Self.recipes(.gasGiant, count: 1)[0]
        rc.ring = nil
        rc.tilt = 10
        let maps = PlanetTextureBaker.bake(rc, lod: .still)
        let n = 200
        let u = PlanetSphere.uniforms(recipe: rc, phase: 0, pixelSize: n, radius: 45, mapWidth: maps.width)
        let image = try #require(PlanetSphere.project(maps, uniforms: u, pixelSize: n))
        #expect(image.width == n && image.height == n)
        let px = PlanetSphere.pixels(maps, uniforms: u, pixelSize: n)
        #expect(px == PlanetSphere.pixels(maps, uniforms: u, pixelSize: n))
        #expect(ArtSnapshot.decode(image).bytes == px)
        func pixel(_ x: Int, _ y: Int) -> [Int] { (0..<4).map { Int(px[(y * n + x) * 4 + $0]) } }
        for (x, y) in [(0, 0), (n - 1, 0), (0, n - 1), (n - 1, n - 1)] { #expect(pixel(x, y) == [0, 0, 0, 0]) }
        // The light comes from the upper left: a point just inside the lit limb is brighter than its mirror on the dark limb.
        let lit = pixel(100 - 26, 100 - 24), dark = pixel(100 + 26, 100 + 24)
        #expect(lit[3] == 255 && dark[3] == 255)
        #expect(lit[0] + lit[1] + lit[2] > 3 * (dark[0] + dark[1] + dark[2]), "\(lit) \(dark)")
        // The limb is anti-aliased: some pixel on the edge is partly covered.
        #expect((0..<n).contains { let a = pixel($0, 100)[3]; return a > 0 && a < 255 })
        func width(_ bytes: [UInt8]) -> Int { ArtPixels(width: n, height: n, bytes: bytes).maskWidth }
        var ringed = rc
        ringed.ring = PlanetNaturalRing(inner: 1.3, outer: 2.0, opacity: 0.8, seed: 1, tint: 0)
        ringed.inclination = 20
        var plain = ringed
        plain.ring = nil
        let withRing = PlanetSphere.pixels(maps, uniforms: PlanetSphere.uniforms(recipe: ringed, phase: 0, pixelSize: n, radius: 45,
                                                                                 mapWidth: maps.width), pixelSize: n)
        let without = PlanetSphere.pixels(maps, uniforms: PlanetSphere.uniforms(recipe: plain, phase: 0, pixelSize: n, radius: 45,
                                                                                mapWidth: maps.width), pixelSize: n)
        #expect(width(withRing) > width(without) + 40)
        // The ring passes behind the disk at the top and in front of it at the bottom.
        let hidden = PlanetSphere.pixels(maps, uniforms: PlanetSphere.uniforms(recipe: ringed, phase: 0, pixelSize: n, radius: 45,
                                                                               mapWidth: maps.width, ring: false), pixelSize: n)
        #expect(hidden == without)
        var tilted = rc
        tilted.tilt = -20
        #expect(PlanetSphere.pixels(maps, uniforms: PlanetSphere.uniforms(recipe: tilted, phase: 0, pixelSize: n, radius: 45,
                                                                          mapWidth: maps.width), pixelSize: n) != px)
    }

    @Test("ART-073 the uniforms are twelve float4 (192 bytes), periodic over the 600 s wrap, and the only phase input")
    func uniforms() {
        #expect(MemoryLayout<PlanetSphere.Uniforms>.size == 192 && MemoryLayout<PlanetSphere.Uniforms>.stride == 192)
        for cls in PlanetClass.allCases {
            var rc = Self.recipes(cls, count: 1)[0]
            rc.pressure = .war
            func at(_ phase: Double, _ a11y: ArtAccessibility = .standard) -> PlanetSphere.Uniforms {
                PlanetSphere.uniforms(recipe: rc, phase: phase, accessibility: a11y, pixelSize: 100, radius: 40, mapWidth: 128)
            }
            #expect(at(0) == at(600) && at(0) == at(1200))
            #expect(at(0) != at(6))
            #expect(at(6, ArtAccessibility(reduceMotion: true)) == at(0, ArtAccessibility(reduceMotion: true)))
            #expect(at(0).viewport == SIMD4<Float>(50, 50, 40, 0))
            #expect(at(0).ringColor.w == 0.45 && at(0, ArtAccessibility(reduceMotion: true)).ringColor.w == 0)
        }
        let l = PlanetSphere.lightDirection
        #expect(abs((l * l).sum() - 1) < 1e-6 && l.x < 0 && l.y > 0 && l.z > 0)
    }

    @Test("ART-078 the star glow sits towards the upper left, in line with the light; the hero backdrop is dense and deterministic")
    func starGlow() {
        let size = CGSize(width: 240, height: 240)
        let c = StarGlow.center(in: size)
        #expect(c.x < 60 && c.y < 60)
        let l = PlanetSphere.lightDirection
        #expect(abs((c.x - 120) / (120 - c.y) - Double(l.x / l.y)) < 1e-6, "the glow lies on the light's projection")
        let (a, b) = ArtSnapshot.twice(HeroBackdrop(seed: 7), size: size)
        #expect(a.fingerprint == b.fingerprint && a.isNonEmpty(lo: 0.9, hi: 1))
        func brightness(_ p: ArtPixels, _ xs: Range<Int>, _ ys: Range<Int>) -> Int {
            var s = 0
            for y in ys { for x in xs { for k in 0..<3 { s += Int(p.bytes[(y * p.width + x) * 4 + k]) } } }
            return s
        }
        let h = a.width / 2
        let quadrants = [brightness(a, 0..<h, 0..<h), brightness(a, h..<a.width, 0..<h), brightness(a, 0..<h, h..<a.height),
                         brightness(a, h..<a.width, h..<a.height)]
        #expect(quadrants[0] == quadrants.max())
        #expect(ArtSnapshot.render(HeroBackdrop(seed: 7, accessibility: ArtAccessibility(reduceTransparency: true)), size: size) != a)
        #expect(ArtSnapshot.render(HeroBackdrop(seed: 8), size: size) != a)
        let drawn = CGRect(x: 0, y: 0, width: size.width / HeroBackdrop.starScale, height: size.height / HeroBackdrop.starScale)
        let dense = (0..<3).reduce(0) { $0 + Starfield(seed: 7, density: 1).stars(in: drawn, layer: $1).count }
        let plain = (0..<3).reduce(0) { $0 + Starfield(seed: 7, density: 1).stars(in: CGRect(origin: .zero, size: size), layer: $1).count }
        #expect(dense > 2 * plain && plain > 0)
    }

    @Test("ART-079 pmart sheet has a planets page")
    func sheetPage() throws {
        let root = ArtSnapshot.packageRoot.appendingPathComponent("Sources/pmart")
        let main = try String(contentsOf: root.appendingPathComponent("main.swift"), encoding: .utf8)
        #expect(main.contains("value(\"--page\")"))
        let sheet = try String(contentsOf: root.appendingPathComponent("ContactSheet.swift"), encoding: .utf8)
        #expect(sheet.contains("case \"planets\": image = IconExport.render(PlanetSheet.sheet"))
        let page = try String(contentsOf: root.appendingPathComponent("PlanetSheet.swift"), encoding: .utf8)
        #expect(page.contains("PlanetClass.allCases") && page.contains("fills: true") && page.contains("(0...12)"))
    }

    @Test("ART-080 PlanetCache is a byte-bounded LRU")
    func cache() {
        let cache = PlanetCache(byteLimit: 1000)
        var made = 0
        func get(_ k: Int) -> [UInt8] {
            cache.value(k, bytes: { $0.count }, make: {
                made += 1
                return [UInt8](repeating: UInt8(k), count: 300)
            })
        }
        for k in 0..<3 { _ = get(k) }
        #expect(cache.count == 3 && cache.byteCount == 900 && made == 3)
        #expect(get(0) == [UInt8](repeating: 0, count: 300) && made == 3, "a hit does not recompute")
        _ = get(3)
        #expect(cache.byteCount <= 1000 && cache.count == 3)
        #expect(cache.peek(1, as: [UInt8].self) == nil, "the least recently used entry was evicted")
        #expect(cache.peek(0, as: [UInt8].self) != nil && cache.peek(3, as: [UInt8].self) != nil)
        cache.insert(99, [UInt8](repeating: 1, count: 2000), bytes: 2000)
        #expect(cache.peek(99, as: [UInt8].self) == nil && cache.byteCount <= 1000)
        #expect(PlanetCache.shared.byteLimit == 32 << 20)
    }
}
