// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// One control point of a spline; a `sharp` point is a corner (zero tangent).
public struct SplinePoint: Sendable, Hashable {
    public var x: Double
    public var y: Double
    public var sharp: Bool

    public init(_ x: Double, _ y: Double, sharp: Bool = false) {
        self.x = x
        self.y = y
        self.sharp = sharp
    }

    var point: CGPoint { CGPoint(x: x, y: y) }
}

/// ART-005: Catmull-Rom splines as cubic Béziers with a fixed tension of 0.5, and other pure path helpers.
public enum ArtGeometry {
    /// The Catmull-Rom tension (0.5 is the uniform, "standard" spline).
    public static let tension = 0.5

    /// A closed spline through `points`.
    public static func closedSpline(_ points: [SplinePoint]) -> Path {
        var path = Path()
        let n = points.count
        guard n >= 3 else { return path }
        path.move(to: points[0].point)
        for i in 0..<n {
            let p0 = points[(i - 1 + n) % n], p1 = points[i], p2 = points[(i + 1) % n], p3 = points[(i + 2) % n]
            let (c1, c2) = controls(p0, p1, p2, p3)
            path.addCurve(to: p2.point, control1: c1, control2: c2)
        }
        path.closeSubpath()
        return path
    }

    /// An open spline through `points` (end tangents point along the first and last segment).
    public static func openSpline(_ points: [SplinePoint]) -> Path {
        var path = Path()
        let n = points.count
        guard n >= 2 else { return path }
        path.move(to: points[0].point)
        for i in 0..<(n - 1) {
            let p0 = points[max(0, i - 1)], p1 = points[i], p2 = points[i + 1], p3 = points[min(n - 1, i + 2)]
            let (c1, c2) = controls(p0, p1, p2, p3)
            path.addCurve(to: p2.point, control1: c1, control2: c2)
        }
        return path
    }

    private static func controls(_ p0: SplinePoint, _ p1: SplinePoint, _ p2: SplinePoint, _ p3: SplinePoint) -> (CGPoint, CGPoint) {
        // Tension 0.5 ⇒ tangent (p2 − p0) / 2; the Bézier control is a third of the tangent away.
        let k = tension / 3
        let c1 = p1.sharp ? p1.point : CGPoint(x: p1.x + (p2.x - p0.x) * k, y: p1.y + (p2.y - p0.y) * k)
        let c2 = p2.sharp ? p2.point : CGPoint(x: p2.x - (p3.x - p1.x) * k, y: p2.y - (p3.y - p1.y) * k)
        return (c1, c2)
    }

    /// A closed polygon.
    public static func polygon(_ points: [CGPoint]) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        for q in points.dropFirst() { p.addLine(to: q) }
        p.closeSubpath()
        return p
    }

    /// A seeded blob: `lobes` points around `center` with radii jittered by `jitter`.
    public static func blob(center: CGPoint, radius: Double, lobes: Int, jitter: Double, rng: inout ArtRandom,
                            aspect: Double = 1) -> Path {
        let start = rng.unit() * 2 * .pi
        let points = (0..<lobes).map { i -> SplinePoint in
            let a = start + Double(i) / Double(lobes) * 2 * .pi
            let r = radius * (1 - jitter + 2 * jitter * rng.unit())
            return SplinePoint(center.x + cos(a) * r * aspect, center.y + sin(a) * r)
        }
        return closedSpline(points)
    }

    /// A capsule from `a` to `b` with radius `r`.
    public static func capsule(from a: CGPoint, to b: CGPoint, radius r: Double) -> Path {
        var p = Path()
        p.move(to: a)
        p.addLine(to: b)
        return p.strokedPath(StrokeStyle(lineWidth: 2 * r, lineCap: .round))
    }

    /// A stroked line turned into a filled area.
    public static func stroke(_ path: Path, width: Double, round: Bool = true) -> Path {
        path.strokedPath(StrokeStyle(lineWidth: width, lineCap: round ? .round : .butt, lineJoin: .round))
    }

    /// Mirror about the vertical line `x = 0.5` (unit space).
    public static func mirrorX(_ path: Path) -> Path {
        path.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 1, ty: 0))
    }

    /// Mirror about the centreline `y = 0.5` (unit space).
    public static func mirrorY(_ path: Path) -> Path {
        path.applying(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 1))
    }

    /// Whether every subpath of `path` is closed.
    public static func isClosed(_ path: Path) -> Bool {
        var open = false, any = false, closed = true
        path.forEach { element in
            switch element {
            case .move:
                if open { closed = false }
                open = true
                any = true
            case .closeSubpath: open = false
            default: break
            }
        }
        return any && closed && !open
    }

    /// The fraction of the bounding box covered by `path` (non-zero fill), sampled on an `n × n` grid.
    public static func coverage(_ path: Path, in rect: CGRect, samples n: Int = 64) -> Double {
        guard rect.width > 0, rect.height > 0 else { return 0 }
        var inside = 0
        for j in 0..<n {
            for i in 0..<n {
                let p = CGPoint(x: rect.minX + (Double(i) + 0.5) / Double(n) * rect.width,
                                y: rect.minY + (Double(j) + 0.5) / Double(n) * rect.height)
                if path.contains(p) { inside += 1 }
            }
        }
        return Double(inside) / Double(n * n)
    }

    /// The approximate area of `path` (sampled within its bounding box).
    public static func area(_ path: Path, samples n: Int = 96) -> Double {
        let box = path.boundingRect
        return coverage(path, in: box, samples: n) * box.width * box.height
    }

    /// Maps the unit square to `rect`.
    public static func transform(unitTo rect: CGRect) -> CGAffineTransform {
        CGAffineTransform(a: rect.width, b: 0, c: 0, d: rect.height, tx: rect.minX, ty: rect.minY)
    }

    /// A point on a circle.
    public static func polar(_ c: CGPoint, _ r: Double, _ angle: Double) -> CGPoint {
        CGPoint(x: c.x + cos(angle) * r, y: c.y + sin(angle) * r)
    }

    /// A regular star or polygon (`inner == outer` gives a polygon).
    public static func star(center c: CGPoint, points n: Int, outer: Double, inner: Double, rotation: Double = -.pi / 2) -> Path {
        let pts = (0..<(2 * n)).map { i in
            polar(c, i.isMultiple(of: 2) ? outer : inner, rotation + Double(i) * .pi / Double(n))
        }
        return polygon(pts)
    }
}

/// ART-006: a bounded LRU of 512 computed art values (recipes and paths), keyed by input value.
@MainActor
public final class ArtCache {
    public static let shared = ArtCache()
    public static let capacity = 512

    private var store: [AnyHashable: (value: Any, tick: UInt64)] = [:]
    private var tick: UInt64 = 0

    public init() {}

    public var count: Int { store.count }

    /// The cached value for `key`, computing and storing it on a miss.
    public func value<K: Hashable, V>(_ key: K, make: () -> V) -> V {
        tick &+= 1
        let k = AnyHashable(key)
        if let hit = store[k], let v = hit.value as? V {
            store[k] = (hit.value, tick)
            return v
        }
        let v = make()
        if store.count >= Self.capacity, let oldest = store.min(by: { $0.value.tick < $1.value.tick })?.key {
            store[oldest] = nil
        }
        store[k] = (v, tick)
        return v
    }
}
