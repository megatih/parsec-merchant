// SPDX-License-Identifier: GPL-2.0-or-later
import Dispatch
import Foundation

/// ART-070: the map sizes. `cinema` is for the endings' limb views, where the surface is magnified many times.
public enum PlanetLOD: Int, CaseIterable, Sendable, Hashable {
    case mini = 0, still, hero, cinema

    public var width: Int { [64, 128, 512, 1024][rawValue] }
    public var height: Int { width / 2 }

    /// The LOD for a disk of `pixels` across.
    public static func forDiameter(_ pixels: Int) -> PlanetLOD {
        pixels >= 140 ? .hero : (pixels >= 36 ? .still : .mini)
    }
}

/// ART-070: two equirectangular RGBA8 maps. `albedo`: sRGB colour, alpha = water and specular mask. `aux`: r = cloud
/// density, g = city lights, b = emissive (lava, war fires), a = height.
public struct PlanetMaps: Sendable, Hashable {
    public let width: Int
    public let height: Int
    public let albedo: [UInt8]
    public let aux: [UInt8]

    public var byteCount: Int { albedo.count + aux.count }
}

/// A buffer whose rows are written by different threads; every index is written by exactly one of them.
struct ParallelRows<T>: @unchecked Sendable {
    let base: UnsafeMutablePointer<T>

    init(_ base: UnsafeMutablePointer<T>) { self.base = base }

    @inline(__always)
    subscript(i: Int) -> T {
        get { base[i] }
        nonmutating set { base[i] = newValue }
    }
}

/// ART-070: bakes a recipe into maps from seeded 3D noise on the unit sphere. Pure and deterministic; rows run in
/// parallel, which never changes the bytes (each texel depends only on its own position).
public enum PlanetTextureBaker {
    typealias V3 = PlanetNoise.V3

    public static func bake(_ recipe: PlanetRecipe, lod: PlanetLOD) -> PlanetMaps {
        let w = lod.width, h = lod.height
        let field = Field(recipe, shoreBand: min(0.05, 6 / Float(w)))
        var heights = [Float](repeating: 0, count: w * h)
        heights.withUnsafeMutableBufferPointer { buf in
            guard let address = buf.baseAddress else { return }
            let base = ParallelRows(address)
            DispatchQueue.concurrentPerform(iterations: h) { y in
                let (sinLat, cosLat) = latitude(y, h)
                for x in 0..<w { base[y * w + x] = field.height(point(x, w, sinLat, cosLat)) }
            }
        }
        let sea = seaLevel(heights, width: w, height: h, waterShare: Float(1 - recipe.landRatio))
        var albedo = [UInt8](repeating: 0, count: w * h * 4)
        var aux = [UInt8](repeating: 0, count: w * h * 4)
        heights.withUnsafeBufferPointer { hbuf in
            albedo.withUnsafeMutableBufferPointer { abuf in
                aux.withUnsafeMutableBufferPointer { xbuf in
                    guard let aAddress = abuf.baseAddress, let xAddress = xbuf.baseAddress else { return }
                    let hs = ParallelRows(UnsafeMutablePointer(mutating: hbuf.baseAddress.unsafelyUnwrapped))
                    let a = ParallelRows(aAddress), x2 = ParallelRows(xAddress)
                    DispatchQueue.concurrentPerform(iterations: h) { y in
                        let (sinLat, cosLat) = latitude(y, h)
                        for x in 0..<w {
                            let i = y * w + x
                            let t = field.texel(point(x, w, sinLat, cosLat), sinLat: sinLat, height: hs[i], sea: sea)
                            a[i * 4] = byte(t.color.x)
                            a[i * 4 + 1] = byte(t.color.y)
                            a[i * 4 + 2] = byte(t.color.z)
                            a[i * 4 + 3] = byte(t.water)
                            x2[i * 4] = byte(t.cloud)
                            x2[i * 4 + 1] = byte(t.lights)
                            x2[i * 4 + 2] = byte(t.emissive)
                            x2[i * 4 + 3] = byte(hs[i])
                        }
                    }
                }
            }
        }
        return PlanetMaps(width: w, height: h, albedo: albedo, aux: aux)
    }

    @inline(__always)
    static func byte(_ v: Float) -> UInt8 { UInt8(min(max(v, 0), 1) * 255 + 0.5) }

    @inline(__always)
    static func latitude(_ y: Int, _ h: Int) -> (sin: Float, cos: Float) {
        let lat = (0.5 - (Float(y) + 0.5) / Float(h)) * Float.pi
        return (sin(lat), cos(lat))
    }

    /// The unit-sphere point of a texel; the projector's inverse (`lon = atan2(x, z)`, `lat = asin(y)`).
    @inline(__always)
    static func point(_ x: Int, _ w: Int, _ sinLat: Float, _ cosLat: Float) -> V3 {
        let lon = ((Float(x) + 0.5) / Float(w) - 0.5) * 2 * Float.pi
        return V3(cosLat * sin(lon), sinLat, cosLat * cos(lon))
    }

    /// The height below which `waterShare` of the sphere's area lies (area-weighted histogram quantile).
    static func seaLevel(_ heights: [Float], width w: Int, height h: Int, waterShare: Float) -> Float {
        guard waterShare > 0 else { return -1 }
        var bins = [Float](repeating: 0, count: 1024)
        var total: Float = 0
        for y in 0..<h {
            let weight = latitude(y, h).cos
            for x in 0..<w {
                let b = min(1023, max(0, Int(heights[y * w + x] * 1024)))
                bins[b] += weight
                total += weight
            }
        }
        var acc: Float = 0
        for (i, v) in bins.enumerated() {
            acc += v
            if acc >= waterShare * total { return (Float(i) + 1) / 1024 }
        }
        return 1
    }
}

extension PlanetTextureBaker {
    struct Texel {
        var color: V3
        var water: Float = 0
        var cloud: Float = 0
        var lights: Float = 0
        var emissive: Float = 0
    }

    struct Crater {
        var center: V3
        var radius: Float
        var depth: Float
    }

    struct Storm {
        var center: V3
        var east: V3
        var north: V3
        var ra: Float
        var rb: Float
        var bright: Bool
    }

    /// Everything a texel needs from the recipe, precomputed once per bake.
    struct Field: Sendable {
        let rc: PlanetRecipe
        let cls: PlanetClass
        let seeds: [UInt32]
        let craters: [Crater]
        let fires: [V3]
        let storms: [Storm]
        /// Half the height range over which sea blends into land: about one texel of slope at this map size.
        let shoreBand: Float
        let landStops: [V3]

        init(_ rc: PlanetRecipe, shoreBand: Float) {
            self.rc = rc
            self.shoreBand = shoreBand
            landStops = Self.landStops(rc)
            cls = rc.planetClass
            var rng = ArtRandom(seed: ArtSeed.mix(rc.noiseSeed, 0x504C_414E))
            seeds = (0..<16).map { _ in UInt32(truncatingIfNeeded: rng.next()) }
            func unit(_ rng: inout ArtRandom) -> V3 {
                let y = Float(rng.range(-1...1)), a = Float(rng.range(0...(2 * Double.pi)))
                let c = (1 - y * y).squareRoot()
                return V3(c * sin(a), y, c * cos(a))
            }
            var cr: [Crater] = []
            let count = cls == .barren ? 110 : (cls == .rocky ? 34 : 0)
            for k in 0..<count {
                let big = k < count / 8
                let radius = Float(big ? rng.range(0.10...0.22) : rng.range(0.018...0.075))
                cr.append(Crater(center: unit(&rng), radius: radius, depth: min(0.22, 0.05 + radius * 0.9)))
            }
            craters = cr
            fires = rc.pressure == .war ? (0..<16).map { _ in unit(&rng) } : []
            var st: [Storm] = []
            if cls == .gasGiant {
                for k in 0..<rng.int(1...3) {
                    let lat = Float(rng.range(-0.6...0.6)), lon = Float(rng.range(0...(2 * Double.pi)))
                    let c = (1 - lat * lat).squareRoot()
                    let center = V3(c * sin(lon), lat, c * cos(lon))
                    let east = V3(cos(lon), 0, -sin(lon))
                    let north = V3(-lat * sin(lon), c, -lat * cos(lon))
                    let ra = Float(k == 0 ? rng.range(0.14...0.24) : rng.range(0.08...0.12))
                    st.append(Storm(center: center, east: east, north: north, ra: ra, rb: ra * Float(rng.range(0.45...0.65)), bright: k != 0))
                }
            }
            storms = st
        }

        // MARK: Height

        func craterDelta(_ p: V3) -> Float {
            var d: Float = 0
            for c in craters {
                let v = p - c.center
                let d2 = (v * v).sum()
                let limit = c.radius * 1.6
                if d2 >= limit * limit { continue }
                let t = d2.squareRoot() / c.radius
                let bowl = -c.depth * (1 - PlanetNoise.smoothstep(0.5, 1.0, t))
                let rim = c.depth * 0.4 * exp(-(t - 1) * (t - 1) / 0.02)
                d += bowl + rim
            }
            return d
        }

        func height(_ p: V3) -> Float {
            switch cls {
            case .terran, .ocean, .jungle:
                let wv = PlanetNoise.warp(p * 1.4, octaves: 3, seed: seeds[1])
                let base = PlanetNoise.fbm(p * 1.8 + wv * 0.45, octaves: 6, seed: seeds[0])
                let ridge = PlanetNoise.ridged(p * 3.1 + wv * 0.3, octaves: 4, seed: seeds[2])
                return base + 0.10 * (ridge - 0.45) * PlanetNoise.smoothstep(0.45, 0.6, base)
            case .desert:
                let wv = PlanetNoise.warp(p * 1.5, octaves: 3, seed: seeds[1])
                return 0.6 * PlanetNoise.fbm(p * 2.0 + wv * 0.4, octaves: 6, seed: seeds[0])
                    + 0.4 * PlanetNoise.ridged(p * 2.6, octaves: 5, seed: seeds[2])
            case .ice:
                let wv = PlanetNoise.warp(p * 1.7, octaves: 3, seed: seeds[1])
                return PlanetNoise.fbm(p * 2.2 + wv * 0.5, octaves: 5, seed: seeds[0])
            case .rocky:
                let wv = PlanetNoise.warp(p * 1.6, octaves: 3, seed: seeds[1])
                return 0.5 * PlanetNoise.fbm(p * 2.1, octaves: 6, seed: seeds[0])
                    + 0.5 * PlanetNoise.ridged(p * 2.4 + wv * 0.3, octaves: 5, seed: seeds[2]) + craterDelta(p)
            case .barren:
                return 0.25 + 0.5 * PlanetNoise.fbm(p * 1.6, octaves: 6, seed: seeds[0]) + craterDelta(p)
            case .volcanic:
                let wv = PlanetNoise.warp(p * 1.6, octaves: 3, seed: seeds[1])
                return 0.55 * PlanetNoise.fbm(p * 1.9 + wv * 0.4, octaves: 6, seed: seeds[0])
                    + 0.45 * PlanetNoise.ridged(p * 2.2, octaves: 4, seed: seeds[2])
            case .toxic:
                let wv = PlanetNoise.warp(p * 1.3, octaves: 3, seed: seeds[1])
                return PlanetNoise.fbm(p * 1.5 + wv * 0.8, octaves: 5, seed: seeds[0])
            case .gasGiant:
                return 0.5
            }
        }

        // MARK: Colour

        func texel(_ p: V3, sinLat: Float, height h: Float, sea: Float) -> Texel {
            var t: Texel
            switch cls {
            case .terran, .ocean, .jungle: t = living(p, sinLat: sinLat, h: h, sea: sea)
            case .desert: t = desert(p, sinLat: sinLat, h: h)
            case .ice: t = ice(p, h: h, sea: sea)
            case .rocky: t = rocky(p, sinLat: sinLat, h: h)
            case .barren: t = barren(p, h: h)
            case .volcanic: t = volcanic(p, h: h)
            case .toxic: t = toxic(p, h: h)
            case .gasGiant: t = gas(p, sinLat: sinLat)
            }
            if rc.pressure == .drought, t.water < 0.5 {
                let grey = 0.299 * t.color.x + 0.587 * t.color.y + 0.114 * t.color.z
                t.color = PlanetNoise.mix(V3(repeating: grey), t.color, 0.45) * 1.08
            }
            t.cloud = clouds(p)
            t.lights = lights(p, texel: t, sinLat: sinLat)
            if !fires.isEmpty {
                var glow: Float = 0, smoke: Float = 0
                for f in fires {
                    let v = p - f
                    let d2 = (v * v).sum()
                    if d2 < 0.09 {
                        glow += exp(-d2 / 0.0022)
                        smoke += exp(-d2 / 0.02)
                    }
                }
                t.color *= 1 - 0.55 * min(smoke, 1)
                t.emissive = max(t.emissive, min(glow, 1))
            }
            return t
        }

        /// Terran, ocean and jungle worlds: seas, biomes by latitude, height and moisture, ice caps, farmland.
        func living(_ p: V3, sinLat: Float, h: Float, sea: Float) -> Texel {
            let absLat = abs(sinLat)
            let detail = PlanetNoise.fbm(p * 7.3, octaves: 3, seed: seeds[3])
            let e = h - sea
            var t = Texel(color: V3(repeating: 0))
            let jungle = cls == .jungle, ocean = cls == .ocean
            // Sea and land are both evaluated near the shore and blended over a thin band, so the coast stays smooth when
            // the map is magnified.
            let shore = PlanetNoise.smoothstep(-shoreBand, shoreBand, e)
            var sea3 = V3(repeating: 0), land3 = V3(repeating: 0)
            if shore < 1 {
                let depth = min(max(-e, 0) / (ocean ? 0.30 : 0.20), 1)
                let shallow = jungle ? V3(0.10, 0.46, 0.44) : (ocean ? V3(0.10, 0.52, 0.66) : V3(0.10, 0.40, 0.60))
                let deep = jungle ? V3(0.02, 0.16, 0.24) : V3(0.02, 0.09, 0.28)
                sea3 = PlanetNoise.mix(shallow, deep, depth.squareRoot()) * (0.92 + 0.16 * detail)
            }
            if shore > 0 {
                let le = max(e, 0)
                let elev = min(le / max(1 - sea, 0.05) * 1.7, 1)
                let moist = PlanetNoise.fbm(p * 2.6 + V3(3, 7, 1), octaves: 4, seed: seeds[4])
                let temp = 1 - pow(absLat, 1.5) - elev * 0.35 + (detail - 0.5) * 0.15
                let belt = exp(-(absLat - 0.45) * (absLat - 0.45) / 0.02)
                var wet = moist * 1.35 - 0.18 - belt * 0.22
                if jungle { wet = moist * 0.7 + 0.5 }
                if rc.tint == .fertile { wet += 0.22 }
                if rc.tint == .pale { wet -= 0.30 }
                wet = min(max(wet, 0), 1)
                var c = PlanetNoise.ramp(landStops, wet)
                c = PlanetNoise.mix(c, V3(0.42, 0.37, 0.33), PlanetNoise.smoothstep(0.45, 0.8, elev))
                if !jungle {
                    c = PlanetNoise.mix(c, V3(0.46, 0.45, 0.37), PlanetNoise.smoothstep(0.42, 0.24, temp))
                    c = PlanetNoise.mix(c, V3(0.93, 0.95, 0.98), PlanetNoise.smoothstep(0.20, 0.08, temp))
                }
                c = PlanetNoise.mix(c, V3(0.93, 0.95, 0.98), PlanetNoise.smoothstep(0.80, 0.95, elev + (0.5 - temp) * 0.3))
                c = PlanetNoise.mix(V3(0.80, 0.74, 0.54), c, PlanetNoise.smoothstep(0, 0.012, le))
                let fertile = (1 - PlanetNoise.smoothstep(0.25, 0.45, elev)) * PlanetNoise.smoothstep(0.25, 0.4, wet)
                    * PlanetNoise.smoothstep(0.35, 0.5, temp)
                if rc.tint == .herbal {
                    let herb = PlanetNoise.smoothstep(0.50, 0.58, PlanetNoise.fbm(p * 5, octaves: 3, seed: seeds[5]))
                    c = PlanetNoise.mix(c, V3(0.16, 0.62, 0.58), herb * 0.8)
                }
                let farm = Float(rc.style.farmland)
                if farm > 0 {
                    let cell = PlanetNoise.value(p * 38, seed: seeds[6])
                    let tone = PlanetNoise.mix(V3(0.70, 0.66, 0.34), V3(0.44, 0.58, 0.24), PlanetNoise.smoothstep(0.42, 0.58, cell))
                    c = PlanetNoise.mix(c, tone, farm * 0.6 * fertile * abs(cell * 2 - 1))
                }
                if rc.pressure == .cropFailure {
                    let patch = PlanetNoise.smoothstep(0.46, 0.54, PlanetNoise.fbm(p * 4.2, octaves: 3, seed: seeds[7]))
                    c = PlanetNoise.mix(c, V3(0.42, 0.30, 0.18), patch * 0.75 * max(fertile, 0.35))
                }
                land3 = c * (0.86 + 0.28 * detail)
            }
            t.color = PlanetNoise.mix(sea3, land3, shore)
            t.water = 1 - shore
            if rc.iceCap > 0 {
                let start = Float(1 - rc.iceCap)
                let polar = absLat + (h - 0.5) * 0.35 + (detail - 0.5) * 0.08
                let k = PlanetNoise.smoothstep(start, start + 0.03, polar)
                t.color = PlanetNoise.mix(t.color, V3(0.93, 0.96, 1.0) * (0.92 + 0.1 * detail), k)
                t.water += (0.3 - t.water) * k
            }
            return t
        }

        func desert(_ p: V3, sinLat: Float, h: Float) -> Texel {
            let wv = PlanetNoise.warp(p * 2.1, octaves: 2, seed: seeds[5])
            let dune = PlanetNoise.ridged(p * 5.5 + wv * 0.6, octaves: 3, seed: seeds[3])
            var c = PlanetNoise.ramp(Self.desertPalettes[rc.variant % 4], h * 1.6 - 0.32 + (dune - 0.5) * 0.14)
            let rock = PlanetNoise.smoothstep(0.56, 0.66, PlanetNoise.fbm(p * 3.7, octaves: 4, seed: seeds[4]))
            c = PlanetNoise.mix(c, V3(0.26, 0.18, 0.14), rock * 0.6)
            c = PlanetNoise.mix(c, V3(0.95, 0.95, 0.96), PlanetNoise.smoothstep(0.93, 0.98, abs(sinLat) + (h - 0.5) * 0.1) * 0.7)
            return Texel(color: c)
        }

        func ice(_ p: V3, h: Float, sea: Float) -> Texel {
            let wv = PlanetNoise.warp(p * 2.3, octaves: 2, seed: seeds[5])
            var c = PlanetNoise.mix(V3(0.80, 0.88, 0.96), V3(0.97, 0.98, 1.0), PlanetNoise.fbm(p * 3, octaves: 5, seed: seeds[3]))
            c = PlanetNoise.mix(c, V3(0.64, 0.80, 0.94), PlanetNoise.smoothstep(0.52, 0.34, h) * 0.5)
            let crack = PlanetNoise.ridged(p * 4.5 + wv * 0.7, octaves: 4, seed: seeds[2])
            c = PlanetNoise.mix(c, V3(0.44, 0.62, 0.82), PlanetNoise.smoothstep(0.62, 0.80, crack) * 0.7)
            let lead = PlanetNoise.smoothstep(sea + shoreBand, sea - shoreBand, h)
            return Texel(color: PlanetNoise.mix(c, V3(0.05, 0.16, 0.30), lead), water: 0.3 + 0.7 * lead)
        }

        func rocky(_ p: V3, sinLat: Float, h: Float) -> Texel {
            let detail = PlanetNoise.fbm(p * 8.1, octaves: 3, seed: seeds[3])
            var c = PlanetNoise.ramp(Self.rockStops, h * 1.7 - 0.35)
            c *= Self.rockTints[rc.variant % 4]
            var t = Texel(color: c)
            switch rc.tint {
            case .ore:
                let vein = PlanetNoise.smoothstep(0.42, 0.58, PlanetNoise.fbm(p * 2.7, octaves: 4, seed: seeds[4]))
                t.color = PlanetNoise.mix(c, V3(0.52, 0.25, 0.14), vein * 0.75)
                let glint = PlanetNoise.smoothstep(0.78, 0.90, PlanetNoise.value(p * 42, seed: seeds[5]))
                    * PlanetNoise.smoothstep(0.46, 0.56, PlanetNoise.fbm(p * 3.1, octaves: 3, seed: seeds[6]))
                t.color = PlanetNoise.mix(t.color, V3(0.88, 0.86, 0.80), glint)
                t.water = glint * 0.9
            case .dull:
                let grey = 0.299 * c.x + 0.587 * c.y + 0.114 * c.z
                t.color = PlanetNoise.mix(V3(repeating: grey), c, 0.2) * 0.88
            case .none, .fertile, .pale, .fungal, .herbal:
                break
            }
            t.color *= 0.84 + 0.32 * detail
            let frost = PlanetNoise.smoothstep(Float(1 - rc.iceCap), Float(1 - rc.iceCap) + 0.03, abs(sinLat) + (h - 0.5) * 0.2)
            t.color = PlanetNoise.mix(t.color, V3(0.92, 0.94, 0.97), frost * 0.8)
            return t
        }

        func barren(_ p: V3, h: Float) -> Texel {
            let detail = PlanetNoise.fbm(p * 9.3, octaves: 3, seed: seeds[3])
            let mw = PlanetNoise.warp(p * 2.2, octaves: 3, seed: seeds[5])
            let maria = PlanetNoise.smoothstep(0.44, 0.58, PlanetNoise.fbm(p * 1.3 + mw * 0.5 + V3(4, 4, 4), octaves: 5, seed: seeds[4]))
            var c = PlanetNoise.mix(V3(0.56, 0.55, 0.54), V3(0.30, 0.30, 0.32), maria)
            c *= Self.moonTints[rc.variant % 4]
            c *= 0.72 + 0.9 * min(max(h, 0), 1) * (0.8 + 0.4 * detail)
            return Texel(color: c)
        }

        func volcanic(_ p: V3, h: Float) -> Texel {
            let wv = PlanetNoise.warp(p * 1.8, octaves: 2, seed: seeds[5])
            let detail = PlanetNoise.fbm(p * 8.7, octaves: 3, seed: seeds[3])
            let crest = PlanetNoise.ridged(p * 3.2 + wv * 0.5, octaves: 4, seed: seeds[4])
            let crack = PlanetNoise.smoothstep(0.70, 0.80, crest)
            let lake = PlanetNoise.smoothstep(0.36, 0.31, h) * PlanetNoise.smoothstep(0.46, 0.58, PlanetNoise.fbm(p * 5, octaves: 3, seed: seeds[6]))
            let lava = max(crack, lake)
            var c = PlanetNoise.ramp(Self.basaltStops, h * 1.5 - 0.25) * (0.82 + 0.36 * detail)
            let glow = PlanetNoise.smoothstep(0.55, 0.72, crest) * 0.35
            c = PlanetNoise.mix(c, V3(0.45, 0.08, 0.02), max(lava * 0.9, glow))
            return Texel(color: c, emissive: lava * (0.55 + 0.45 * PlanetNoise.value(p * 31, seed: seeds[7])))
        }

        func toxic(_ p: V3, h: Float) -> Texel {
            let swirl = PlanetNoise.ridged(p * 2.4 + PlanetNoise.warp(p * 1.1, octaves: 2, seed: seeds[6]) * 0.9, octaves: 3, seed: seeds[4])
            var c = PlanetNoise.ramp(Self.toxicStops, h * 1.9 - 0.45)
            c = PlanetNoise.mix(c, V3(0.20, 0.24, 0.08), PlanetNoise.smoothstep(0.55, 0.8, swirl) * 0.5)
            if rc.tint == .fungal {
                let patch = PlanetNoise.smoothstep(0.47, 0.55, PlanetNoise.fbm(p * 3.3, octaves: 4, seed: seeds[5]))
                c = PlanetNoise.mix(c, V3(0.50, 0.26, 0.62), patch * 0.85)
            }
            return Texel(color: c)
        }

        static let desertPalettes: [[V3]] = [
            [V3(0.42, 0.26, 0.16), V3(0.66, 0.42, 0.24), V3(0.80, 0.60, 0.36), V3(0.90, 0.78, 0.56)],
            [V3(0.30, 0.14, 0.10), V3(0.55, 0.26, 0.16), V3(0.72, 0.40, 0.24), V3(0.84, 0.60, 0.42)],
            [V3(0.50, 0.40, 0.28), V3(0.72, 0.60, 0.42), V3(0.86, 0.76, 0.58), V3(0.94, 0.88, 0.72)],
            [V3(0.36, 0.20, 0.14), V3(0.62, 0.34, 0.18), V3(0.80, 0.54, 0.28), V3(0.92, 0.74, 0.46)]
        ]
        static let rockStops: [V3] = [V3(0.20, 0.18, 0.17), V3(0.38, 0.33, 0.29), V3(0.52, 0.46, 0.40), V3(0.66, 0.61, 0.55)]
        static let rockTints: [V3] = [V3(1, 1, 1), V3(1.08, 0.98, 0.88), V3(0.92, 0.98, 1.06), V3(1.05, 1.0, 0.92)]
        static let moonTints: [V3] = [V3(1, 1, 1), V3(1.04, 1.0, 0.95), V3(0.96, 0.99, 1.04), V3(1.03, 0.99, 0.97)]
        static let basaltStops: [V3] = [V3(0.07, 0.06, 0.07), V3(0.20, 0.17, 0.16), V3(0.34, 0.29, 0.26)]
        static let toxicStops: [V3] = [V3(0.26, 0.30, 0.10), V3(0.50, 0.50, 0.16), V3(0.70, 0.62, 0.26), V3(0.40, 0.46, 0.18)]

        /// The dry-to-wet land ramp of a living world.
        static func landStops(_ rc: PlanetRecipe) -> [V3] {
            if rc.planetClass == .jungle { return [V3(0.30, 0.42, 0.14), V3(0.16, 0.40, 0.12), V3(0.08, 0.32, 0.10), V3(0.04, 0.24, 0.09)] }
            switch rc.tint {
            case .fertile: return [V3(0.46, 0.40, 0.22), V3(0.30, 0.42, 0.16), V3(0.14, 0.36, 0.12), V3(0.06, 0.24, 0.09)]
            case .pale: return [V3(0.78, 0.68, 0.50), V3(0.68, 0.60, 0.40), V3(0.52, 0.54, 0.32), V3(0.36, 0.44, 0.24)]
            case .none, .ore, .dull, .fungal, .herbal:
                return [V3(0.74, 0.62, 0.40), V3(0.56, 0.52, 0.28), V3(0.28, 0.46, 0.18), V3(0.10, 0.30, 0.12)]
            }
        }

        static let gasPalettes: [[V3]] = [
            [V3(0.45, 0.28, 0.18), V3(0.72, 0.52, 0.34), V3(0.90, 0.80, 0.64), V3(0.78, 0.58, 0.40), V3(0.95, 0.90, 0.80)],
            [V3(0.62, 0.52, 0.36), V3(0.82, 0.72, 0.50), V3(0.93, 0.86, 0.66), V3(0.76, 0.66, 0.46), V3(0.96, 0.92, 0.78)],
            [V3(0.10, 0.22, 0.55), V3(0.18, 0.38, 0.75), V3(0.35, 0.58, 0.88), V3(0.16, 0.32, 0.68), V3(0.55, 0.75, 0.95)],
            [V3(0.40, 0.20, 0.38), V3(0.66, 0.36, 0.50), V3(0.88, 0.62, 0.62), V3(0.56, 0.30, 0.52), V3(0.95, 0.80, 0.78)]
        ]

        func gas(_ p: V3, sinLat: Float) -> Texel {
            let wv = PlanetNoise.fbm(V3(p.x * 2.2, p.y * 5, p.z * 2.2), octaves: 4, seed: seeds[1]) - 0.5
            let y = sinLat + 0.06 * wv
            let coord = (y * 0.5 + 0.5) * Float(rc.bands)
            let b1 = PlanetNoise.value(V3(3.3, coord, 1.7), seed: seeds[2])
            let b2 = PlanetNoise.value(V3(8.1, coord * 2.7, 4.2), seed: seeds[3])
            let streak = PlanetNoise.fbm(V3(p.x * 3, y * 26, p.z * 3), octaves: 4, seed: seeds[4]) - 0.5
            let palette = Self.gasPalettes[rc.variant % 4]
            var c = PlanetNoise.ramp(palette, (0.65 * b1 + 0.35 * b2) * 1.5 - 0.25 + 0.25 * streak)
            for s in storms {
                let v = p - s.center
                let a = (v * s.east).sum() / s.ra, b = (v * s.north).sum() / s.rb
                let e2 = a * a + b * b
                if e2 < 1 {
                    let k = 1 - e2
                    let tone = s.bright ? palette[4] : PlanetNoise.mix(palette[0], V3(0.70, 0.25, 0.15), 0.5)
                    c = PlanetNoise.mix(c, tone, PlanetNoise.smoothstep(0, 0.7, k) * 0.8)
                }
            }
            c *= 1 - 0.22 * abs(sinLat) * sinLat * sinLat
            return Texel(color: c)
        }

        // MARK: Clouds and lights

        func clouds(_ p: V3) -> Float {
            let cover = Float(rc.cloudCover)
            guard cover > 0 else { return 0 }
            let cw = PlanetNoise.warp(p * 1.6 + V3(11, 5, 3), octaves: 3, seed: seeds[10])
            let n = PlanetNoise.fbm(V3(p.x * 2.4, p.y * 3.4, p.z * 2.4) + cw * 0.9, octaves: 5, seed: seeds[11])
            let thr = 0.64 - 0.32 * cover
            let fine = PlanetNoise.fbm(p * 9 + cw, octaves: 2, seed: seeds[12])
            let streaks = cls == .toxic ? 0.7 + 0.3 * PlanetNoise.ridged(V3(p.x * 2, p.y * 7, p.z * 2) + cw * 0.6, octaves: 3, seed: seeds[14]) : 1
            return min(PlanetNoise.smoothstep(thr, thr + 0.2, n) * (0.7 + 0.6 * fine) * streaks * (cls == .toxic ? 1.3 : 1), 1)
        }

        func lights(_ p: V3, texel t: Texel, sinLat: Float) -> Float {
            let density = Float(rc.style.cityLights)
            guard density > 0, cls != .gasGiant else { return 0 }
            if cls.hasWater, t.water > 0.2 { return 0 }
            let cluster = PlanetNoise.fbm(p * 4.5 + V3(9, 2, 5), octaves: 3, seed: seeds[8])
            let thr = 0.76 - 0.40 * pow(density, 0.6)
            let inside = PlanetNoise.smoothstep(thr, thr + 0.07, cluster)
            guard inside > 0 else { return 0 }
            let sparkle = PlanetNoise.smoothstep(0.42, 0.75, PlanetNoise.value(p * 70, seed: seeds[9]))
            return inside * sparkle * (0.6 + 0.4 * PlanetNoise.value(p * 23, seed: seeds[13]))
        }
    }
}
