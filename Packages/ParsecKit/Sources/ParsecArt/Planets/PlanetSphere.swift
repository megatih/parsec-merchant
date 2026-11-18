// SPDX-License-Identifier: GPL-2.0-or-later
import CoreGraphics
import Dispatch
import Foundation

/// ART-072, ART-073: the sphere projection of baked planet maps. `uniforms(…)` is the only place that turns a recipe and
/// a phase into rendering parameters; `project(…)` is the CPU renderer, and the app's Metal shader is its twin.
public enum PlanetSphere {
    public typealias V3 = SIMD3<Float>
    public typealias V4 = SIMD4<Float>

    /// ART-026: seconds of phase per turn. All three divide `phaseWrap`.
    public static let surfacePeriod = 24.0
    public static let cloudPeriod = 20.0
    public static let bandPeriod = 15.0
    /// The app wraps its phase at this many seconds.
    public static let phaseWrap = 600.0

    /// ART-072: the direction to the light in view space (x right, y up, z towards the viewer): upper left, in front.
    public static let lightDirection: V3 = {
        let v = V3(-0.55, 0.50, 0.67)
        return v / (v * v).sum().squareRoot()
    }()

    /// ART-073: the layout of the shader's `Uniforms` struct (twelve `float4`, 192 bytes).
    public struct Uniforms: Sendable, Hashable {
        /// Centre x, centre y, disk radius (pixels), unused.
        public var viewport = V4(0, 0, 1, 0)
        /// Surface turn, cloud turn (0…1), flicker phase (radians), texel width (1 / map width).
        public var turn = V4(0, 0, 0, 1.0 / 128)
        /// cos tilt, sin tilt, cos inclination, sin inclination.
        public var axis = V4(1, 0, 1, 0)
        /// Direction to the light in view space, ambient.
        public var light = V4(0, 0, 1, 0.02)
        public var atmosphere = V4(0, 0, 0, 0)
        public var cloud = V4(1, 1, 1, 1)
        public var night = V4(1, 0.86, 0.45, 0)
        public var emissive = V4(1, 0.42, 0.10, 0)
        /// Specular, bump, limb darkening, cloud shadow offset.
        public var surface = V4(0, 0, 0.4, 0)
        public var haze = V4(0, 0, 0, 0)
        /// Inner radius, outer radius (planet radii), opacity, seed.
        public var ring = V4(0, 0, 0, 0)
        /// Ring colour, flicker amplitude.
        public var ringColor = V4(0.8, 0.76, 0.66, 0)

        public init() {}
    }

    @inline(__always)
    static func fraction(_ x: Double) -> Float { Float(x - x.rounded(.down)) }

    /// ART-073: rendering parameters of `recipe` at `phase` for an image of `pixelSize` whose disk has `radius` pixels.
    public static func uniforms(recipe rc: PlanetRecipe, phase rawPhase: Double, accessibility a11y: ArtAccessibility = .standard,
                                pixelSize: Int, radius: Double, mapWidth: Int, ring showRing: Bool = true) -> Uniforms {
        let phase = a11y.ambientPhase(rawPhase)
        var u = Uniforms()
        u.viewport = V4(Float(pixelSize) / 2, Float(pixelSize) / 2, Float(radius), 0)
        let period = rc.planetClass == .gasGiant ? bandPeriod : surfacePeriod
        u.turn = V4(fraction(phase / period), fraction(phase / cloudPeriod), 2 * Float.pi * fraction(phase * 1.1), 1 / Float(mapWidth))
        let tilt = Float(rc.tilt * .pi / 180), incl = Float(rc.inclination * .pi / 180)
        u.axis = V4(cos(tilt), sin(tilt), cos(incl), sin(incl))
        u.light = V4(lightDirection, 0.02)
        let look = ClassLook.of(rc)
        var air = look.atmosphere
        switch rc.accent {
        case .none: break
        case .artistic: air = V4(mix(V3(air.x, air.y, air.z), V3(1.0, 0.72, 0.30), 0.65), max(air.w, 0.55))
        case .warlike: air = V4(mix(V3(air.x, air.y, air.z), V3(1.0, 0.25, 0.18), 0.65), max(air.w, 0.55))
        }
        u.atmosphere = air
        u.cloud = V4(look.cloud, a11y.reduceTransparency ? 2.4 : 1)
        u.night = V4(1.0, 0.84, 0.50, rc.style.cityLights > 0 ? 1.5 : 0)
        u.emissive = V4(1.0, 0.40, 0.10, 1.25)
        let scale = Float(mapWidth) / 256
        u.surface = V4(look.specular, look.bump * scale, look.limb, rc.cloudCover > 0 ? 0.012 : 0)
        var haze = V4(0.50, 0.46, 0.42, Float(rc.style.smog) * 0.45)
        switch rc.pressure {
        case .plague: haze = V4(0.62, 0.75, 0.20, 0.30)
        case .drought: haze = V4(0.80, 0.70, 0.48, max(haze.w, 0.14))
        case .cropFailure: haze = V4(0.50, 0.40, 0.26, max(haze.w, 0.08))
        case .cold: haze = V4(0.80, 0.90, 1.0, max(haze.w, 0.10))
        case .war, .boredom, .employment, .some(.none), nil: break
        }
        if !rc.planetClass.hasAir { haze.w = 0 }
        u.haze = haze
        if showRing, let ring = rc.ring {
            u.ring = V4(Float(ring.inner), Float(ring.outer), Float(ring.opacity), Float(ring.seed))
        }
        let ringTints: [V3] = [V3(0.84, 0.78, 0.64), V3(0.74, 0.76, 0.82), V3(0.82, 0.68, 0.54)]
        u.ringColor = V4(ringTints[(rc.ring?.tint ?? 0) % 3], rc.pressure == .war && !a11y.reduceMotion ? 0.45 : 0)
        return u
    }

    /// The class constants of the projection.
    struct ClassLook {
        var atmosphere: V4
        var cloud: V3
        var specular: Float
        var bump: Float
        var limb: Float

        static func of(_ rc: PlanetRecipe) -> ClassLook {
            switch rc.planetClass {
            case .terran: ClassLook(atmosphere: V4(0.42, 0.66, 1.0, 0.85), cloud: V3(1, 1, 1), specular: 1, bump: 2.6, limb: 0.35)
            case .ocean: ClassLook(atmosphere: V4(0.38, 0.68, 1.0, 0.9), cloud: V3(1, 1, 1), specular: 1, bump: 2.2, limb: 0.35)
            case .desert: ClassLook(atmosphere: V4(0.96, 0.72, 0.50, 0.45), cloud: V3(0.95, 0.86, 0.70), specular: 0, bump: 2.8, limb: 0.45)
            case .ice: ClassLook(atmosphere: V4(0.70, 0.86, 1.0, 0.6), cloud: V3(1, 1, 1), specular: 0.7, bump: 2.2, limb: 0.4)
            case .jungle: ClassLook(atmosphere: V4(0.48, 0.86, 0.80, 0.9), cloud: V3(0.97, 1, 0.98), specular: 1, bump: 2.4, limb: 0.35)
            case .rocky:
                ClassLook(atmosphere: V4(0.76, 0.70, 0.64, 0.2), cloud: V3(0.86, 0.82, 0.78), specular: rc.tint == .ore ? 0.7 : 0, bump: 3.0,
                          limb: 0.65)
            case .barren: ClassLook(atmosphere: V4(0, 0, 0, 0), cloud: V3(1, 1, 1), specular: 0, bump: 5.5, limb: 0.75)
            case .volcanic: ClassLook(atmosphere: V4(1.0, 0.45, 0.25, 0.45), cloud: V3(0.26, 0.23, 0.23), specular: 0, bump: 3.2, limb: 0.6)
            case .toxic:
                ClassLook(atmosphere: V4(0.80, 0.90, 0.35, 0.95), cloud: rc.tint == .fungal ? V3(0.80, 0.72, 0.88) : V3(0.88, 0.84, 0.52),
                          specular: 0, bump: 0.6, limb: 0.4)
            case .gasGiant:
                {
                let tone = PlanetTextureBaker.Field.gasPalettes[rc.variant % 4][2]
                return ClassLook(atmosphere: V4(tone.x, tone.y, tone.z, 0.5), cloud: V3(1, 1, 1), specular: 0, bump: 0, limb: 0.6)
            }()
            }
        }
    }

    // MARK: CPU projection

    /// ART-072: a square premultiplied RGBA8 sRGB image of `pixelSize` pixels.
    public static func project(_ maps: PlanetMaps, uniforms: Uniforms, pixelSize: Int) -> CGImage? {
        project(maps, uniforms: uniforms, width: pixelSize, height: pixelSize)
    }

    /// A `width` × `height` window on the projection; `uniforms.viewport` places the disk, which may reach outside it
    /// (the limb views of the endings, ART-084/085).
    public static func project(_ maps: PlanetMaps, uniforms: Uniforms, width: Int, height: Int) -> CGImage? {
        let bytes = pixels(maps, uniforms: uniforms, width: width, height: height)
        guard width > 0, height > 0, let provider = CGDataProvider(data: Data(bytes) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil,
                       shouldInterpolate: true, intent: .defaultIntent)
    }

    /// The projection as premultiplied RGBA8 bytes, rows top to bottom.
    public static func pixels(_ maps: PlanetMaps, uniforms u: Uniforms, pixelSize n: Int) -> [UInt8] {
        pixels(maps, uniforms: u, width: n, height: n)
    }

    public static func pixels(_ maps: PlanetMaps, uniforms u: Uniforms, width w: Int, height h: Int) -> [UInt8] {
        guard w > 0, h > 0 else { return [] }
        var out = [UInt8](repeating: 0, count: w * h * 4)
        let sampler = Sampler(maps)
        out.withUnsafeMutableBufferPointer { buf in
            guard let address = buf.baseAddress else { return }
            let base = ParallelRows(address)
            DispatchQueue.concurrentPerform(iterations: h) { y in
                for x in 0..<w {
                    let c = shade(x: Float(x) + 0.5, y: Float(y) + 0.5, u: u, s: sampler)
                    let i = (y * w + x) * 4
                    base[i] = PlanetTextureBaker.byte(c.x)
                    base[i + 1] = PlanetTextureBaker.byte(c.y)
                    base[i + 2] = PlanetTextureBaker.byte(c.z)
                    base[i + 3] = PlanetTextureBaker.byte(c.w)
                }
            }
        }
        return out
    }

    /// Bilinear lookups that wrap in longitude and clamp in latitude (the shader's sampler).
    struct Sampler: Sendable {
        let maps: PlanetMaps

        init(_ maps: PlanetMaps) { self.maps = maps }

        @inline(__always)
        func fetch(_ data: [UInt8], _ ux: Float, _ uy: Float) -> V4 {
            let w = maps.width, h = maps.height
            let x = ux * Float(w) - 0.5, y = uy * Float(h) - 0.5
            let x0 = x.rounded(.down), y0 = y.rounded(.down)
            let fx = x - x0, fy = y - y0
            var ix0 = Int(x0) % w
            if ix0 < 0 { ix0 += w }
            let ix1 = (ix0 + 1) % w
            let iy0 = min(max(Int(y0), 0), h - 1), iy1 = min(max(Int(y0) + 1, 0), h - 1)
            func texel(_ ix: Int, _ iy: Int) -> V4 {
                let i = (iy * w + ix) * 4
                return V4(Float(data[i]), Float(data[i + 1]), Float(data[i + 2]), Float(data[i + 3]))
            }
            let top = texel(ix0, iy0) + (texel(ix1, iy0) - texel(ix0, iy0)) * fx
            let bottom = texel(ix0, iy1) + (texel(ix1, iy1) - texel(ix0, iy1)) * fx
            return (top + (bottom - top) * fy) * (1.0 / 255)
        }

        @inline(__always) func albedo(_ u: Float, _ v: Float) -> V4 { fetch(maps.albedo, u, v) }
        @inline(__always) func aux(_ u: Float, _ v: Float) -> V4 { fetch(maps.aux, u, v) }
    }

    @inline(__always) static func mix(_ a: V3, _ b: V3, _ t: Float) -> V3 { a + (b - a) * t }
    @inline(__always) static func dot(_ a: V3, _ b: V3) -> Float { (a * b).sum() }
    @inline(__always) static func clamp01(_ x: Float) -> Float { min(max(x, 0), 1) }
    @inline(__always) static func normalize(_ v: V3) -> V3 { v / dot(v, v).squareRoot() }
    @inline(__always)
    static func cross(_ a: V3, _ b: V3) -> V3 { V3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x) }
    @inline(__always)
    static func smoothstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float { PlanetNoise.smoothstep(e0, e1, x) }

    /// View space to the planet's object space: tilt in the picture plane, inclination towards the viewer, then the spin.
    @inline(__always)
    static func toObject(_ v: V3, _ u: Uniforms) -> V3 {
        let ct = u.axis.x, st = u.axis.y, ci = u.axis.z, si = u.axis.w
        let a = V3(ct * v.x + st * v.y, ct * v.y - st * v.x, v.z)
        let b = V3(a.x, ci * a.y + si * a.z, ci * a.z - si * a.y)
        let ang = u.turn.x * 2 * Float.pi
        let cy = cos(ang), sy = sin(ang)
        return V3(cy * b.x - sy * b.z, b.y, sy * b.x + cy * b.z)
    }

    /// The ring's premultiplied colour at `q` (planet radii from the centre, y up) and whether it is in front of the disk.
    @inline(__always)
    static func ring(_ q: SIMD2<Float>, u: Uniforms) -> (color: V4, front: Bool) {
        guard u.ring.z > 0 else { return (V4(repeating: 0), false) }
        let n = V3(-u.axis.z * u.axis.y, u.axis.z * u.axis.x, u.axis.w)
        let zp = -(n.x * q.x + n.y * q.y) / n.z
        let p = V3(q.x, q.y, zp)
        let rho = dot(p, p).squareRoot()
        let span = u.ring.y - u.ring.x
        let t = (rho - u.ring.x) / span
        if t <= 0 || t >= 1 { return (V4(repeating: 0), false) }
        let w = 1.5 / (u.viewport.z * span) + 0.02
        let edge = smoothstep(0, w, t) * (1 - smoothstep(1 - w, 1, t))
        let s = u.ring.w
        let bands = 0.62 + 0.22 * sin(t * 41 + s) + 0.16 * sin(t * 97 + s * 1.7)
        let gap = 1 - 0.85 * (smoothstep(0.52, 0.56, t) - smoothstep(0.60, 0.64, t))
        let a = u.ring.z * edge * bands * gap
        let l = V3(u.light.x, u.light.y, u.light.z)
        let pl = dot(p, l)
        let d = p - l * pl
        let shadow: Float = pl < 0 ? 1 - smoothstep(0.90, 1.0, dot(d, d)) : 0
        let shade = 1 + (0.12 - 1) * shadow
        let c = V3(u.ringColor.x, u.ringColor.y, u.ringColor.z) * ((0.80 + 0.20 * sin(t * 23 + s * 0.6)) * shade)
        return (V4(c * a, a), zp > 0)
    }

    /// One pixel, premultiplied RGBA in 0…1. `x`, `y` are pixel-centre coordinates with the origin at the top left.
    @inline(__always)
    static func shade(x: Float, y: Float, u: Uniforms, s: Sampler) -> V4 {
        let radius = u.viewport.z
        let q = SIMD2<Float>(x - u.viewport.x, u.viewport.y - y) / radius
        let r2 = (q * q).sum()
        let r = r2.squareRoot()
        let l = V3(u.light.x, u.light.y, u.light.z)
        let ringC = ring(q, u: u)
        var result = ringC.front ? V4(repeating: 0) : ringC.color
        let cov = clamp01((1 - r) * radius + 0.5)
        if u.atmosphere.w > 0, r < 1.25 {
            let inv = 1 / max(r, 1e-4)
            let dayH = smoothstep(-0.30, 0.40, q.x * inv * l.x + q.y * inv * l.y)
            let fall = exp(-max(r - 1, 0) / 0.045) * (1 - smoothstep(1.15, 1.25, r))
            let ha = clamp01(0.55 * u.atmosphere.w * fall * (0.05 + 0.95 * dayH))
            result = V4(u.atmosphere.x * ha, u.atmosphere.y * ha, u.atmosphere.z * ha, ha) + result * (1 - ha)
        }
        if cov > 0 {
            let z = max(1 - r2, 0).squareRoot()
            let n = r > 1 ? V3(q.x / r, q.y / r, 0) : V3(q.x, q.y, z)
            let o = toObject(n, u)
            let lo = toObject(l, u)
            let lat = asin(min(max(o.y, -1), 1))
            let lon = atan2(o.x, o.z)
            let ux = lon / (2 * Float.pi) + 0.5, uy = 0.5 - lat / Float.pi
            let cosLat = max(1 - o.y * o.y, 0).squareRoot()
            let east = V3(o.z, 0, -o.x) / max(cosLat, 1e-3)
            let north = cross(o, east)
            let alb = s.albedo(ux, uy)
            let aux = s.aux(ux, uy)
            let du = u.turn.w
            let hE = s.aux(ux + du, uy).w - s.aux(ux - du, uy).w
            let hN = s.aux(ux, uy - 2 * du).w - s.aux(ux, uy + 2 * du).w
            let nb = normalize(o - (east * (hE / max(cosLat, 0.25)) + north * hN) * u.surface.y)
            let cux = ux - (u.turn.y - u.turn.x)
            let cl = min(s.aux(cux, uy).x * u.cloud.w, 1)
            let shx = u.surface.w * 0.5 * dot(lo, east) / max(cosLat, 0.3), shy = -u.surface.w * dot(lo, north)
            let cs = min(s.aux(cux + shx, uy + shy).x * u.cloud.w, 1)
            let ndlG = dot(o, lo)
            let ndl = dot(nb, lo)
            let soft = smoothstep(-0.10, 0.22, ndlG)
            let diff = soft * min(max(0.10 + 1.05 * max(ndl, 0), 0), 1.15)
            var col = V3(alb.x, alb.y, alb.z) * (diff * (1 - 0.5 * cs) + u.light.w)
            let vo = toObject(V3(0, 0, 1), u)
            let nh = max(dot(o, normalize(lo + vo)), 0)
            let spec = (pow(nh, 90) * 0.55 + pow(nh, 10) * 0.07) * alb.w * u.surface.x * soft * (1 - cl)
            col += V3(1.0, 0.96, 0.88) * spec
            let cd = soft * min(max(0.18 + max(ndlG, 0), 0), 1.1) + u.light.w
            col = mix(col, V3(u.cloud.x, u.cloud.y, u.cloud.z) * cd, cl)
            let nightF = (1 - soft) * (1 - soft)
            col += V3(u.night.x, u.night.y, u.night.z) * (aux.y * u.night.w * nightF * (1 - 0.7 * cl))
            let fl = 1 + u.ringColor.w * sin(u.turn.z + ux * 251 + uy * 173)
            col += V3(u.emissive.x, u.emissive.y, u.emissive.z) * (aux.z * u.emissive.w * fl * (1 - 0.5 * cl))
            col = mix(col, V3(u.haze.x, u.haze.y, u.haze.z) * (diff + u.light.w), u.haze.w)
            let zc = clamp01(z)
            col *= 1 + (pow(zc, 0.45) - 1) * u.surface.z
            let fres = pow(1 - zc, 3)
            let dayRim = smoothstep(-0.30, 0.40, ndlG)
            col += V3(u.atmosphere.x, u.atmosphere.y, u.atmosphere.z) * (u.atmosphere.w * fres * (0.06 + 0.94 * dayRim))
            col = V3(clamp01(col.x), clamp01(col.y), clamp01(col.z))
            result = V4(col * cov, cov) + result * (1 - cov)
        }
        if ringC.front { result = ringC.color + result * (1 - ringC.color.w) }
        return result
    }
}
