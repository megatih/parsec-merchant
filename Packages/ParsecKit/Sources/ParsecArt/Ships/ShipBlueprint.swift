// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// ART-009: one hull profile point: `x` on the length axis (tail 0 … nose 1), the half width at that station.
public struct ProfilePoint: Sendable, Hashable {
    public var x: Double
    public var halfWidth: Double
    public var sharp: Bool

    public init(_ x: Double, _ halfWidth: Double, sharp: Bool = false) {
        self.x = x
        self.halfWidth = halfWidth
        self.sharp = sharp
    }
}

/// ART-009: a mirrored wing pair (or two pairs when `count == 2`).
public struct WingPair: Sendable, Hashable {
    public var rootX: Double
    public var rootChord: Double
    public var span: Double
    /// Aft offset of the tip's leading edge (negative = forward-swept).
    public var sweep: Double
    public var tipChord: Double
    public var count: Int
    public var glass: Bool
    public var rounded: Bool

    public init(rootX: Double, rootChord: Double, span: Double, sweep: Double, tipChord: Double, count: Int = 1,
                glass: Bool = false, rounded: Bool = false) {
        self.rootX = rootX
        self.rootChord = rootChord
        self.span = span
        self.sweep = sweep
        self.tipChord = tipChord
        self.count = count
        self.glass = glass
        self.rounded = rounded
    }
}

/// ART-009: a mirrored engine nacelle running aft from `x`.
public struct Nacelle: Sendable, Hashable {
    public var x: Double
    public var yOffset: Double
    public var length: Double
    public var radius: Double

    public init(x: Double, yOffset: Double, length: Double, radius: Double) {
        self.x = x
        self.yOffset = yOffset
        self.length = length
        self.radius = radius
    }
}

/// ART-009: an engine glow position (mirrored when `yOffset > 0`).
public struct EngineMount: Sendable, Hashable {
    public var x: Double
    public var yOffset: Double
    public var radius: Double

    public init(x: Double, yOffset: Double = 0, radius: Double) {
        self.x = x
        self.yOffset = yOffset
        self.radius = radius
    }
}

/// ART-009: the cockpit canopy.
public struct Cockpit: Sendable, Hashable {
    public enum Style: Sendable, Hashable {
        case bubble, slit, compound, none
    }

    /// The front of the canopy.
    public var x: Double
    public var length: Double
    public var width: Double
    public var style: Style

    public init(x: Double, length: Double, width: Double, style: Style) {
        self.x = x
        self.length = length
        self.width = width
        self.style = style
    }

    public static let none = Cockpit(x: 0, length: 0, width: 0, style: .none)
}

/// ART-009: the closed set of ship features.
public enum ShipFeature: Sendable, Hashable {
    case antennae, proboscis, abdomenLight, stripes(Int), elytraSeam, segments(Int), mandibles, stinger, waist, rearLegs,
         pincers, curledTail(Int), hornRam, raptorialArms, tentacles(Int), eyes(Int), bottle, cork, scroll, skids,
         hardpoints(Int), cargoPods(Int), shieldFins(Int)
}

/// ART-009: palette tokens of a livery.
public struct Livery: Sendable, Hashable {
    public var primary: ArtToken
    public var secondary: ArtToken
    public var accent: ArtToken
    public var glow: ArtToken

    public init(primary: ArtToken, secondary: ArtToken, accent: ArtToken, glow: ArtToken = .engineGlow) {
        self.primary = primary
        self.secondary = secondary
        self.accent = accent
        self.glow = glow
    }
}

/// ART-009: a ship design as a value. Geometry is built by `ShipGeometry.make`.
public struct ShipBlueprint: Sendable, Hashable {
    public var hull: [ProfilePoint]
    public var wings: [WingPair]
    public var nacelles: [Nacelle]
    public var engines: [EngineMount]
    public var cockpit: Cockpit
    public var features: [ShipFeature]
    public var livery: Livery
    public var symmetric: Bool
    /// Space monster: the hull is a seeded organic outline instead of the profile.
    public var organicSeed: UInt64?

    public init(hull: [ProfilePoint], wings: [WingPair] = [], nacelles: [Nacelle] = [], engines: [EngineMount] = [],
                cockpit: Cockpit = .none, features: [ShipFeature] = [], livery: Livery, symmetric: Bool = true,
                organicSeed: UInt64? = nil) {
        self.hull = hull
        self.wings = wings
        self.nacelles = nacelles
        self.engines = engines
        self.cockpit = cockpit
        self.features = features
        self.livery = livery
        self.symmetric = symmetric
        self.organicSeed = organicSeed
    }

    /// The front-most and aft-most hull stations.
    public var noseX: Double { hull.map(\.x).max() ?? 1 }
    public var tailX: Double { hull.map(\.x).min() ?? 0 }

    /// The hull half width at `x` (linear between profile points).
    public func halfWidth(at x: Double) -> Double {
        let pts = hull.sorted { $0.x < $1.x }
        guard let first = pts.first, let last = pts.last else { return 0 }
        if x <= first.x { return first.halfWidth }
        if x >= last.x { return last.halfWidth }
        for (a, b) in zip(pts, pts.dropFirst()) where x >= a.x && x <= b.x {
            let t = b.x == a.x ? 0 : (x - a.x) / (b.x - a.x)
            return a.halfWidth + (b.halfWidth - a.halfWidth) * t
        }
        return 0
    }

    /// The narrowest interior station (the waist).
    public var waistX: Double {
        let inner = hull.filter { $0.x > tailX + 0.05 && $0.x < noseX - 0.05 }
        return inner.min { $0.halfWidth < $1.halfWidth }?.x ?? (noseX + tailX) / 2
    }

    public var isGlassHull: Bool { features.contains(.bottle) }
}
