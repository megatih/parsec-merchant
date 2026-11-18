// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// ART-009: geometry of each `ShipFeature`, placed from the blueprint's hull profile. Every feature is a piece of built
/// machinery (or, for the two oddities, a sea creature's limb and a bottle's cork); none is insect anatomy.
enum ShipFeatures {
    typealias Parts = (solid: [ShipPart], detail: [ShipPart])

    static func parts(_ f: ShipFeature, bp: ShipBlueprint, hull: Path) -> Parts {
        switch f {
        case let .panelLines(n): return ([], [ShipPart(panelLines(n, bp: bp), .dark, solid: false, lineWidth: 0.004)])
        case let .cargoModules(n): return cargoModules(n, bp: bp)
        case let .armour(level): return armour(level, bp: bp)
        case let .hardpoints(slots, installed): return (hardpoints(slots: slots, installed: installed, bp: bp), [])
        case let .shieldEmitters(slots, installed): return ([], shieldEmitters(slots: slots, installed: installed, bp: bp))
        case let .sensors(n): return ([], sensors(n, bp: bp))
        case let .fuelTanks(n): return (fuelTanks(n, bp: bp), [])
        case .navigationLights: return ([], [])
        case let .liveryBands(n): return ([], [ShipPart(bands(n, bp: bp).intersection(hull), .accent, solid: false)])
        case let .spine(n): return ([], spine(n, bp: bp))
        case let .broadsides(n): return (broadsides(n, bp: bp), [])
        case .shieldRing: return (shieldRing(bp), [])
        case let .tentacles(n): return (tentacles(n, bp: bp), [])
        case let .eyes(n): return ([], [ShipPart(eyes(n, bp: bp), .glow, solid: false)])
        case .bottle: return ([], [])
        case .cork:
            let w = bp.halfWidth(at: bp.noseX) * 0.95
            return ([ShipPart(Path(roundedRect: CGRect(x: bp.noseX - 0.01, y: 0.5 - w, width: 0.07, height: 2 * w), cornerRadius: 0.01), .cork)], [])
        case .scroll:
            let rect = CGRect(x: bp.tailX + 0.12, y: 0.42, width: (bp.noseX - bp.tailX) * 0.42, height: 0.16)
            return ([], [ShipPart(Path(roundedRect: rect, cornerRadius: 0.03), .parchment, solid: false)])
        }
    }

    /// Extra glow emitters (the monster's bioluminescence).
    static func glows(_ bp: ShipBlueprint) -> [EngineMount] {
        bp.organicSeed != nil ? [EngineMount(x: 0.62, radius: 0.2)] : []
    }

    /// ART-016: the red (port) and green (starboard) navigation lights at the widest station, and a white one at the tail.
    static func navigationLights(_ bp: ShipBlueprint, bounds: CGRect) -> [ShipLight] {
        guard bp.features.contains(.navigationLights) else { return [] }
        let widest = bp.hull.max { $0.halfWidth < $1.halfWidth } ?? ProfilePoint(0.5, 0.1)
        // On the wing tips when there are wings, else at the hull's widest station.
        let tip = bp.wings.first
        let x: Double = tip.map { $0.rootX - $0.sweep - $0.tipChord / 2 } ?? widest.x
        let off: Double = (tip != nil ? 0.5 - Double(bounds.minY) : widest.halfWidth) - 0.008
        return [ShipLight(position: CGPoint(x: x, y: 0.5 - off), kind: .port), ShipLight(position: CGPoint(x: x, y: 0.5 + off), kind: .starboard),
                ShipLight(position: CGPoint(x: bp.tailX + 0.03, y: 0.5), kind: .tail)]
    }

    private static func mirrored(_ path: Path, role: ShipPart.Role = .dark, solid: Bool = true) -> [ShipPart] {
        [ShipPart(path, role, solid: solid), ShipPart(ArtGeometry.mirrorY(path), role, solid: solid)]
    }

    // MARK: Plating and panels

    /// Transverse seams at `n` stations and one seam along the keel.
    static func panelLines(_ n: Int, bp: ShipBlueprint) -> Path {
        var p = Path()
        let len = bp.noseX - bp.tailX
        for i in 1...max(1, n) {
            let x = bp.tailX + len * Double(i) / Double(n + 1)
            let w = bp.halfWidth(at: x) * 0.96
            guard w > 0.01 else { continue }
            p.move(to: CGPoint(x: x, y: 0.5 - w))
            p.addLine(to: CGPoint(x: x, y: 0.5 + w))
        }
        p.move(to: CGPoint(x: bp.tailX + len * 0.08, y: 0.5))
        p.addLine(to: CGPoint(x: bp.tailX + len * 0.62, y: 0.5))
        return p
    }

    /// The armour belt of one side: a plate over the hull's edge amidships, thicker and longer with the level.
    static func armourPlate(_ level: Int, bp: ShipBlueprint) -> CGRect {
        let len = bp.noseX - bp.tailX
        let x0 = bp.tailX + len * (0.34 - 0.03 * Double(level)), x1 = bp.tailX + len * (0.58 + 0.05 * Double(level))
        let w = max(bp.halfWidth(at: x0), bp.halfWidth(at: x1), bp.halfWidth(at: (x0 + x1) / 2))
        let thickness = 0.008 + 0.006 * Double(level)
        return CGRect(x: x0, y: 0.5 - w - thickness, width: x1 - x0, height: thickness + 0.024)
    }

    static func armour(_ level: Int, bp: ShipBlueprint) -> Parts {
        guard level > 0 else { return ([], []) }
        let rect = armourPlate(level, bp: bp)
        let plate = Path(roundedRect: rect, cornerRadius: 0.006)
        var seams = Path()
        for k in 1...level {
            let x = rect.minX + rect.width * Double(k) / Double(level + 1)
            seams.move(to: CGPoint(x: x, y: rect.minY))
            seams.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        return (mirrored(plate, role: .secondary), mirrored(seams, role: .dark, solid: false).map {
            ShipPart($0.path, .dark, solid: false, lineWidth: 0.004)
        })
    }

    // MARK: Cargo

    /// The cargo containers: rows from the stern forward, each row a pair outside the hull; an odd module rides on the keel.
    static func cargoRects(_ n: Int, bp: ShipBlueprint) -> (pairs: [CGRect], keel: CGRect?) {
        guard n > 0 else { return ([], nil) }
        let len = bp.noseX - bp.tailX
        let rowLength = len * 0.17, gap = len * 0.015
        var pairs: [CGRect] = []
        for row in 0..<(n / 2) {
            let x = bp.tailX + len * 0.1 + Double(row) * (rowLength + gap)
            let off = max(bp.halfWidth(at: x), bp.halfWidth(at: x + rowLength)) - 0.012
            let outer = max(off + 0.062, bp.cargoReach)
            pairs.append(CGRect(x: x, y: 0.5 - outer, width: rowLength, height: outer - off))
        }
        var keel: CGRect?
        if n % 2 == 1 {
            let x = bp.tailX + len * 0.1 + Double(n / 2) * (rowLength + gap)
            keel = CGRect(x: x, y: 0.5 - 0.036, width: rowLength, height: 0.072)
        }
        return (pairs, keel)
    }

    static func cargoModules(_ n: Int, bp: ShipBlueprint) -> Parts {
        let rects = cargoRects(n, bp: bp)
        var solid: [ShipPart] = [], detail: [ShipPart] = []
        for r in rects.pairs {
            solid += mirrored(Path(roundedRect: r, cornerRadius: 0.008), role: .secondary)
            var ribs = Path()
            for k in 1...3 {
                let x = r.minX + r.width * Double(k) / 4
                ribs.move(to: CGPoint(x: x, y: r.minY + 0.006))
                ribs.addLine(to: CGPoint(x: x, y: r.maxY - 0.006))
            }
            detail += mirrored(ribs, solid: false).map { ShipPart($0.path, .dark, solid: false, lineWidth: 0.004) }
        }
        if let k = rects.keel {
            detail.append(ShipPart(Path(roundedRect: k, cornerRadius: 0.008), .secondary, solid: false))
            var ribs = Path()
            for i in 1...3 {
                let x = k.minX + k.width * Double(i) / 4
                ribs.move(to: CGPoint(x: x, y: k.minY + 0.006))
                ribs.addLine(to: CGPoint(x: x, y: k.maxY - 0.006))
            }
            detail.append(ShipPart(ribs, .dark, solid: false, lineWidth: 0.004))
        }
        return (solid, detail)
    }

    // MARK: Weapons, shields, sensors, tanks

    /// The mount positions of `slots` hardpoints: pairs outboard from the nose aft, and a centreline mount when odd.
    static func hardpointMounts(_ slots: Int, bp: ShipBlueprint) -> [CGPoint] {
        var out: [CGPoint] = []
        let lead = bp.noseX - 0.2
        for tier in 0..<(slots / 2) {
            let x = lead - Double(tier) * 0.11
            let off = min(0.44, bp.halfWidth(at: x) + 0.02 + Double(tier) * 0.028)
            out.append(CGPoint(x: x, y: 0.5 - off))
            out.append(CGPoint(x: x, y: 0.5 + off))
        }
        if slots % 2 == 1 { out.append(CGPoint(x: bp.noseX - 0.1, y: 0.5)) }
        return out
    }

    /// One block per slot; a barrel on each slot that holds a weapon, longer and thicker for the heavier types.
    static func hardpoints(slots: Int, installed: [Int], bp: ShipBlueprint) -> [ShipPart] {
        var parts: [ShipPart] = []
        for (i, m) in hardpointMounts(min(6, max(0, slots)), bp: bp).enumerated() {
            parts.append(ShipPart(Path(roundedRect: CGRect(x: m.x - 0.035, y: m.y - 0.014, width: 0.07, height: 0.028), cornerRadius: 0.006),
                                  .secondary))
            guard i < installed.count else { continue }
            let weight = Double(min(5, max(0, installed[i])))
            let tip = min(0.985, m.x + 0.07 + 0.012 * weight)
            parts.append(ShipPart(ArtGeometry.capsule(from: CGPoint(x: m.x, y: m.y), to: CGPoint(x: tip, y: m.y), radius: 0.007 + 0.0012 * weight),
                                  .dark))
        }
        return parts
    }

    static func shieldEmitters(slots: Int, installed: Int, bp: ShipBlueprint) -> [ShipPart] {
        var parts: [ShipPart] = []
        let len = bp.noseX - bp.tailX
        for i in 0..<min(4, max(0, slots)) {
            let x = bp.tailX + len * (0.3 + 0.13 * Double(i))
            let r = min(0.02, bp.halfWidth(at: x) * 0.3)
            guard r > 0.004 else { continue }
            let ring = Path(ellipseIn: CGRect(x: x - r, y: 0.5 - r, width: 2 * r, height: 2 * r))
            parts.append(ShipPart(ring, .dark, solid: false))
            let core = Path(ellipseIn: CGRect(x: x - r * 0.55, y: 0.5 - r * 0.55, width: r * 1.1, height: r * 1.1))
            parts.append(ShipPart(core, i < installed ? .glow : .secondary, solid: false))
        }
        return parts
    }

    /// Sensor dishes set into the forward hull.
    static func sensors(_ n: Int, bp: ShipBlueprint) -> [ShipPart] {
        var parts: [ShipPart] = []
        for i in 0..<max(0, n) {
            let x = bp.noseX - 0.24 - 0.07 * Double(i / 2)
            let side: Double = i.isMultiple(of: 2) ? -1 : 1
            let off = bp.halfWidth(at: x) * 0.55
            let r = min(0.014, off * 0.5)
            guard r > 0.004 else { continue }
            let c = CGPoint(x: x, y: 0.5 + side * off)
            parts.append(ShipPart(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), .accent, solid: false))
            parts.append(ShipPart(Path(ellipseIn: CGRect(x: c.x - r * 0.3, y: c.y - r * 0.3, width: r * 0.6, height: r * 0.6)), .dark, solid: false))
        }
        return parts
    }

    /// Spherical tanks along the aft flanks.
    static func fuelTanks(_ n: Int, bp: ShipBlueprint) -> [ShipPart] {
        var parts: [ShipPart] = []
        let len = bp.noseX - bp.tailX
        for i in 0..<max(0, n) {
            let x = bp.tailX + len * (0.66 + 0.075 * Double(i))
            let r = 0.022
            let off = bp.halfWidth(at: x) + r * 0.35
            parts += mirrored(Path(ellipseIn: CGRect(x: x - r, y: 0.5 - off - r, width: 2 * r, height: 2 * r)), role: .accent)
        }
        return parts
    }

    private static func bands(_ n: Int, bp: ShipBlueprint) -> Path {
        var p = Path()
        let len = bp.noseX - bp.tailX
        for i in 0..<max(1, n) {
            let x = bp.tailX + len * (0.24 + 0.2 * Double(i))
            p.addRect(CGRect(x: x, y: 0, width: len * 0.035, height: 1))
        }
        return p
    }

    // MARK: Capital-ship fittings (special designs)

    /// A raised keel of `n` blocks along the centreline.
    static func spine(_ n: Int, bp: ShipBlueprint) -> [ShipPart] {
        var parts: [ShipPart] = []
        let len = bp.noseX - bp.tailX
        for i in 0..<max(1, n) {
            let w = len * 0.6 / Double(max(1, n))
            let x = bp.tailX + len * 0.14 + Double(i) * w
            parts.append(ShipPart(Path(roundedRect: CGRect(x: x, y: 0.5 - 0.02, width: w * 0.86, height: 0.04), cornerRadius: 0.006), .secondary,
                                  solid: false))
        }
        return parts
    }

    /// Gun sponsons along both flanks.
    static func broadsides(_ n: Int, bp: ShipBlueprint) -> [ShipPart] {
        var parts: [ShipPart] = []
        let len = bp.noseX - bp.tailX
        for i in 0..<max(1, n) {
            let x = bp.tailX + len * (0.22 + 0.5 * Double(i) / Double(max(1, n)))
            let off = bp.halfWidth(at: x + 0.03) - 0.008
            parts += mirrored(Path(roundedRect: CGRect(x: x, y: 0.5 - off - 0.04, width: 0.075, height: 0.04), cornerRadius: 0.008), role: .secondary)
            parts += mirrored(ArtGeometry.capsule(from: CGPoint(x: x + 0.04, y: 0.5 - off - 0.028), to: CGPoint(x: x + 0.11, y: 0.5 - off - 0.028),
                                                  radius: 0.006))
        }
        return parts
    }

    /// A field ring carried around the hull on four struts.
    static func shieldRing(_ bp: ShipBlueprint) -> [ShipPart] {
        let c = CGPoint(x: bp.tailX + (bp.noseX - bp.tailX) * 0.46, y: 0.5)
        let outer = 0.3, inner = 0.262
        let ring = Path(ellipseIn: CGRect(x: c.x - outer * 0.62, y: c.y - outer, width: outer * 1.24, height: outer * 2))
            .subtracting(Path(ellipseIn: CGRect(x: c.x - inner * 0.62, y: c.y - inner, width: inner * 1.24, height: inner * 2)))
        var parts = [ShipPart(ring, .accent)]
        for (dx, dy) in [(0.07, 1.0), (-0.07, 1.0), (0.07, -1.0), (-0.07, -1.0)] {
            parts.append(ShipPart(ArtGeometry.capsule(from: CGPoint(x: c.x + dx * 0.4, y: c.y + dy * 0.02),
                                                      to: CGPoint(x: c.x + dx, y: c.y + dy * (inner + 0.01)), radius: 0.007), .dark))
        }
        return parts
    }

    // MARK: The space monster

    private static func tentacles(_ n: Int, bp: ShipBlueprint) -> [ShipPart] {
        var rng = ArtRandom(seed: ArtSeed.mix(bp.organicSeed ?? 1, 0x5445_4E54))
        var parts: [ShipPart] = []
        for i in 0..<max(1, n) {
            let spread = (Double(i) + 0.5) / Double(max(1, n))
            let y0 = 0.36 + 0.28 * spread
            let curl = rng.range(-0.14...0.14)
            let pts = [SplinePoint(0.5, y0), SplinePoint(0.32, y0 + (spread - 0.5) * 0.25 + curl * 0.5),
                       SplinePoint(0.16, y0 + (spread - 0.5) * 0.55 - curl), SplinePoint(0.04, y0 + (spread - 0.5) * 0.7 + curl * 1.2)]
            parts.append(ShipPart(ArtGeometry.stroke(ArtGeometry.openSpline(pts), width: 0.032 - 0.004 * Double(i % 3)), .secondary))
        }
        return parts
    }

    private static func eyes(_ n: Int, bp: ShipBlueprint) -> Path {
        var p = Path()
        let cx = bp.organicSeed != nil ? 0.74 : bp.noseX - 0.08
        for i in 0..<max(1, n) {
            let y = 0.5 + (Double(i) - Double(n - 1) / 2) * 0.07
            let x = cx + (i == n / 2 ? 0.03 : 0)
            p.addEllipse(in: CGRect(x: x - 0.022, y: y - 0.022, width: 0.044, height: 0.044))
        }
        return p
    }
}
