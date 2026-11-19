// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// An engine glow position in unit space: the nozzle's centre at the tail, and its radius.
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

/// ART-016: a light on the hull, in unit space.
public struct ShipLight: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case port, starboard, tail
        /// A police beacon: blue, blinking (steady under Reduce Motion).
        case beacon
    }

    public var position: CGPoint
    public var kind: Kind
}

/// One drawable piece of a ship, in unit space (tail x = 0, nose x = 1, centreline y = 0.5).
public struct ShipPart: Sendable {
    public enum Role: Sendable, Hashable {
        case primary, secondary, accent, glass, cockpit, glow, cork, parchment, dark
    }

    public var path: Path
    public var role: Role
    /// Part of the solid silhouette (mask, scorch, shield size).
    public var solid: Bool
    /// When set, the part is a detail line of this width (unit space) rather than a fill.
    public var lineWidth: Double?
    /// The paint of this part; nil uses the role's default.
    public var color: ArtRGB?
    /// Painted markings are flat colour; plating is lit across its depth.
    public var flat: Bool
    /// What the part is ("habitat", "container", "weapon:2", …), for the statistics tests of ART-SHIP-003 and 004.
    public var tag: String

    public init(_ path: Path, _ role: Role, solid: Bool = true, lineWidth: Double? = nil, color: ArtRGB? = nil, flat: Bool = false,
                tag: String = "") {
        self.path = path
        self.role = role
        self.solid = solid
        self.lineWidth = lineWidth
        self.color = color
        self.flat = flat
        self.tag = tag
    }
}

/// ART-SHIP: the pure geometry of a ship: its parts in drawing order and what the renderer needs to know about them.
public struct ShipGeometry: Sendable {
    public var parts: [ShipPart]
    /// The union of every solid part.
    public var silhouette: Path
    /// The main hull outline (the specular strip follows it).
    public var hull: Path
    /// Glow emitters: centre and radius in unit space.
    public var glows: [EngineMount]
    public var lights: [ShipLight]
    public var bounds: CGRect
    /// The colour of engine plumes and body glows.
    public var glow = ArtRGB(0.45, 0.75, 1.0)
    /// A creature, not a vessel: no nozzles.
    public var organic = false
    /// A glass hull (the bottle): no plating shade.
    public var glass = false
    /// A derelict: no plumes and no lights.
    public var derelict = false
    /// The hull's main paint (debris in the ending scenes).
    public var paint = ArtRGB(0.6, 0.62, 0.66)
    /// ART-SHIP-008: the cells of a police checker band with their colours; empty on every other ship.
    public var checkerCells: [(rect: CGRect, blue: Bool)] = []

    public init(parts: [ShipPart], hull: Path, glows: [EngineMount], lights: [ShipLight]) {
        self.parts = parts
        var silhouette = Path()
        for p in parts where p.solid { silhouette = silhouette.isEmpty ? p.path : silhouette.union(p.path) }
        self.silhouette = silhouette
        self.hull = hull
        self.glows = glows
        self.lights = lights
        bounds = silhouette.boundingRect
    }

    /// How many parts carry a tag (or a tag with this prefix when it ends in ":").
    public func count(_ tag: String) -> Int {
        parts.filter { tag.hasSuffix(":") ? $0.tag.hasPrefix(tag) : $0.tag == tag }.count
    }

    /// Every part's tag and outline, as text: two geometries are equal when their descriptions are.
    public var description: String {
        parts.map { "\($0.tag)=\($0.path.description)" }.joined(separator: "|")
    }
}
