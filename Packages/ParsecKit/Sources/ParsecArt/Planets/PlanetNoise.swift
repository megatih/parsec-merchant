// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// A plain three-component vector for the baker's positions and colours. Scalar fields on purpose: generic SIMD
/// arithmetic is slow in unoptimised builds, and the bake budget (ART-006) is checked in one.
public struct PlanetVec: Sendable, Hashable {
    public var x: Float
    public var y: Float
    public var z: Float

    @inline(__always)
    public init(_ x: Float, _ y: Float, _ z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }

    @inline(__always)
    public init(repeating v: Float) { self.init(v, v, v) }

    @inline(__always) public static func + (a: PlanetVec, b: PlanetVec) -> PlanetVec { PlanetVec(a.x + b.x, a.y + b.y, a.z + b.z) }
    @inline(__always) public static func - (a: PlanetVec, b: PlanetVec) -> PlanetVec { PlanetVec(a.x - b.x, a.y - b.y, a.z - b.z) }
    @inline(__always) public static func * (a: PlanetVec, b: PlanetVec) -> PlanetVec { PlanetVec(a.x * b.x, a.y * b.y, a.z * b.z) }
    @inline(__always) public static func * (a: PlanetVec, k: Float) -> PlanetVec { PlanetVec(a.x * k, a.y * k, a.z * k) }
    @inline(__always) public static func *= (a: inout PlanetVec, k: Float) { a = a * k }
    @inline(__always) public static func *= (a: inout PlanetVec, b: PlanetVec) { a = a * b }
    @inline(__always) public func sum() -> Float { x + y + z }
}

/// ART-070: seeded 3D value noise on an integer-hashed lattice. Pure arithmetic: no tables, no clock, no process state.
public enum PlanetNoise {
    public typealias V3 = PlanetVec

    /// The lattice value at an integer point, in `[0, 1)`.
    @inline(__always)
    static func lattice(_ x: Int32, _ y: Int32, _ z: Int32, _ seed: UInt32) -> Float {
        var h = (UInt32(bitPattern: x) &* 0x8DA6_B343) ^ (UInt32(bitPattern: y) &* 0xD816_3841) ^ (UInt32(bitPattern: z) &* 0xCB1A_B31F) ^ seed
        h ^= h >> 13
        h = h &* 0x5BD1_E995
        h ^= h >> 15
        h = h &* 0x27D4_EB2D
        h ^= h >> 15
        return Float(h >> 8) * (1.0 / 16_777_216.0)
    }

    /// Smooth value noise in `[0, 1)` (quintic interpolation).
    @inline(__always)
    static func value(_ px: Float, _ py: Float, _ pz: Float, _ seed: UInt32) -> Float {
        let fx = px.rounded(.down), fy = py.rounded(.down), fz = pz.rounded(.down)
        let ix = Int32(truncatingIfNeeded: Int(fx)), iy = Int32(truncatingIfNeeded: Int(fy)), iz = Int32(truncatingIfNeeded: Int(fz))
        var tx = px - fx, ty = py - fy, tz = pz - fz
        tx = tx * tx * tx * (tx * (tx * 6 - 15) + 10)
        ty = ty * ty * ty * (ty * (ty * 6 - 15) + 10)
        tz = tz * tz * tz * (tz * (tz * 6 - 15) + 10)
        let c000 = lattice(ix, iy, iz, seed), c100 = lattice(ix &+ 1, iy, iz, seed)
        let c010 = lattice(ix, iy &+ 1, iz, seed), c110 = lattice(ix &+ 1, iy &+ 1, iz, seed)
        let c001 = lattice(ix, iy, iz &+ 1, seed), c101 = lattice(ix &+ 1, iy, iz &+ 1, seed)
        let c011 = lattice(ix, iy &+ 1, iz &+ 1, seed), c111 = lattice(ix &+ 1, iy &+ 1, iz &+ 1, seed)
        let x00 = c000 + (c100 - c000) * tx, x10 = c010 + (c110 - c010) * tx
        let x01 = c001 + (c101 - c001) * tx, x11 = c011 + (c111 - c011) * tx
        let y0 = x00 + (x10 - x00) * ty, y1 = x01 + (x11 - x01) * ty
        return y0 + (y1 - y0) * tz
    }

    @inline(__always)
    public static func value(_ p: V3, seed: UInt32) -> Float { value(p.x, p.y, p.z, seed) }

    /// Fractal Brownian motion, normalised to `[0, 1)` (lacunarity 2.03, gain 0.5).
    @inline(__always)
    static func fbm(_ px: Float, _ py: Float, _ pz: Float, octaves: Int, seed: UInt32) -> Float {
        var sum: Float = 0, amp: Float = 0.5, total: Float = 0
        var x = px, y = py, z = pz
        for o in 0..<octaves {
            sum += amp * value(x, y, z, seed &+ UInt32(o) &* 0x9E37_79B9)
            total += amp
            amp *= 0.5
            x = x * 2.03 + 17.3
            y = y * 2.03 + 9.1
            z = z * 2.03 + 31.7
        }
        return sum / total
    }

    @inline(__always)
    public static func fbm(_ p: V3, octaves: Int, seed: UInt32) -> Float { fbm(p.x, p.y, p.z, octaves: octaves, seed: seed) }

    /// Ridged fBm in `[0, 1]`: sharp crests where the octaves cross their mid value.
    @inline(__always)
    public static func ridged(_ p: V3, octaves: Int, seed: UInt32) -> Float {
        var sum: Float = 0, amp: Float = 0.5, total: Float = 0
        var x = p.x, y = p.y, z = p.z
        for o in 0..<octaves {
            let v = 1 - abs(2 * value(x, y, z, seed &+ UInt32(o) &* 0x85EB_CA6B) - 1)
            sum += amp * v * v
            total += amp
            amp *= 0.5
            x = x * 2.07 + 5.2
            y = y * 2.07 + 41.9
            z = z * 2.07 + 13.3
        }
        return sum / total
    }

    /// A three-component warp vector in `[-1, 1]`.
    @inline(__always)
    public static func warp(_ p: V3, octaves: Int, seed: UInt32) -> V3 {
        let x = p.x, y = p.y, z = p.z
        return V3(fbm(x, y, z, octaves: octaves, seed: seed) * 2 - 1,
                  fbm(x + 31.4, y + 15.9, z + 26.5, octaves: octaves, seed: seed &+ 0x1234_5677) * 2 - 1,
                  fbm(x + 58.9, y + 79.3, z + 23.8, octaves: octaves, seed: seed &+ 0x7654_3211) * 2 - 1)
    }

    @inline(__always)
    public static func smoothstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
        let t = min(max((x - e0) / (e1 - e0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    @inline(__always)
    public static func mix(_ a: V3, _ b: V3, _ t: Float) -> V3 {
        V3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t)
    }

    /// A piecewise-linear colour ramp over evenly spaced stops; `t` is clamped to 0…1.
    @inline(__always)
    public static func ramp(_ stops: [V3], _ t: Float) -> V3 {
        let x = min(max(t, 0), 1) * Float(stops.count - 1)
        let i = min(Int(x), stops.count - 2)
        return mix(stops[i], stops[i + 1], x - Float(i))
    }
}
