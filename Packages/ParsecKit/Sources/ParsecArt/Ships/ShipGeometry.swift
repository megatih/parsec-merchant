// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

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

    public init(_ path: Path, _ role: Role, solid: Bool = true, lineWidth: Double? = nil) {
        self.path = path
        self.role = role
        self.solid = solid
        self.lineWidth = lineWidth
    }
}

/// ART-005/009: pure geometry of a blueprint.
public struct ShipGeometry: Sendable {
    public var parts: [ShipPart]
    /// The union of every solid part.
    public var silhouette: Path
    /// The main hull outline.
    public var hull: Path
    /// Glow emitters: centre and radius in unit space.
    public var glows: [EngineMount]
    /// ART-016: navigation lights.
    public var lights: [ShipLight]
    public var bounds: CGRect

    /// Builds the parts in composition order: wings, nacelles, hull, features, cockpit, then livery details.
    public static func make(_ bp: ShipBlueprint) -> ShipGeometry {
        var parts: [ShipPart] = []
        parts += wingParts(bp)
        for n in bp.nacelles {
            for side in sides(n.yOffset) {
                let y = 0.5 + side * n.yOffset
                // A pylon ties the nacelle to the hull, so no pod floats beside the ship.
                let mid = n.x - n.length / 2, edge = bp.halfWidth(at: mid) * 0.6
                if n.yOffset > edge {
                    parts.append(ShipPart(ArtGeometry.polygon([CGPoint(x: mid + 0.05, y: 0.5 + side * edge), CGPoint(x: mid + 0.03, y: y),
                                                               CGPoint(x: mid - 0.04, y: y), CGPoint(x: mid - 0.06, y: 0.5 + side * edge)]),
                                          .dark))
                }
                parts.append(ShipPart(ArtGeometry.capsule(from: CGPoint(x: n.x - n.radius, y: y),
                                                          to: CGPoint(x: n.x - n.length + n.radius, y: y), radius: n.radius),
                                      .secondary))
            }
        }
        let hull = hullPath(bp)
        parts.append(ShipPart(hull, bp.isGlassHull ? .glass : .primary))
        var details: [ShipPart] = []
        for f in bp.features {
            let (solid, detail) = ShipFeatures.parts(f, bp: bp, hull: hull)
            parts += solid
            details += detail
        }
        parts += cockpitParts(bp.cockpit)
        parts += details
        var silhouette = Path()
        for p in parts where p.solid { silhouette = silhouette.isEmpty ? p.path : silhouette.union(p.path) }
        var glows = bp.engines.flatMap { e in sides(e.yOffset).map { EngineMount(x: e.x, yOffset: $0 * e.yOffset, radius: e.radius) } }
        glows += ShipFeatures.glows(bp)
        let bounds = silhouette.boundingRect
        return ShipGeometry(parts: parts, silhouette: silhouette, hull: hull, glows: glows,
                            lights: ShipFeatures.navigationLights(bp, bounds: bounds), bounds: bounds)
    }

    static func sides(_ offset: Double) -> [Double] { offset > 0 ? [-1, 1] : [1] }

    /// ART-009: the profile mirrored about the centreline into one closed spline (nose → tail on top, back underneath).
    static func hullPath(_ bp: ShipBlueprint) -> Path {
        if let seed = bp.organicSeed {
            var rng = ArtRandom(seed: seed)
            return ArtGeometry.blob(center: CGPoint(x: 0.62, y: 0.5), radius: 0.24, lobes: 9, jitter: 0.18, rng: &rng, aspect: 1.15)
        }
        var pts: [SplinePoint] = []
        for p in bp.hull { pts.append(SplinePoint(p.x, 0.5 - p.halfWidth, sharp: p.sharp)) }
        for p in bp.hull.reversed() where p.halfWidth > 0 { pts.append(SplinePoint(p.x, 1 - (0.5 - p.halfWidth), sharp: p.sharp)) }
        return ArtGeometry.closedSpline(pts)
    }

    static func wingParts(_ bp: ShipBlueprint) -> [ShipPart] {
        var parts: [ShipPart] = []
        for w in bp.wings {
            for k in 0..<max(1, min(2, w.count)) {
                let shift = Double(k) * w.rootChord * 1.15
                let span = w.span * (k == 0 ? 1 : 0.82)
                let top = wingPath(rootX: w.rootX - shift, w: w, span: span)
                let role: ShipPart.Role = w.glass ? .glass : .secondary
                parts.append(ShipPart(top, role))
                parts.append(ShipPart(ArtGeometry.mirrorY(top), role))
            }
        }
        return parts
    }

    static func wingPath(rootX: Double, w: WingPair, span: Double) -> Path {
        let rootLead = CGPoint(x: rootX, y: 0.5), rootTrail = CGPoint(x: rootX - w.rootChord, y: 0.5)
        let tipLead = CGPoint(x: rootX - w.sweep, y: 0.5 - span)
        let tipTrail = CGPoint(x: rootX - w.sweep - w.tipChord, y: 0.5 - span)
        if w.rounded {
            return ArtGeometry.closedSpline([SplinePoint(rootLead.x, rootLead.y, sharp: true),
                                             SplinePoint(tipLead.x, tipLead.y + span * 0.08),
                                             SplinePoint((tipLead.x + tipTrail.x) / 2, tipLead.y),
                                             SplinePoint(tipTrail.x, tipTrail.y + span * 0.1),
                                             SplinePoint(rootTrail.x, rootTrail.y, sharp: true)])
        }
        return ArtGeometry.polygon([rootLead, tipLead, tipTrail, rootTrail])
    }

    static func cockpitParts(_ c: Cockpit) -> [ShipPart] {
        switch c.style {
        case .none:
            return []
        case .bubble:
            return [ShipPart(Path(ellipseIn: CGRect(x: c.x - c.length, y: 0.5 - c.width / 2, width: c.length, height: c.width)),
                             .cockpit, solid: false)]
        case .slit:
            // A bridge: a window band across the beam.
            return [ShipPart(Path(roundedRect: CGRect(x: c.x - c.length, y: 0.5 - c.width / 2, width: c.length, height: c.width),
                                  cornerRadius: min(c.length, c.width) * 0.35), .cockpit, solid: false)]
        }
    }
}
