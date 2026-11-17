// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// ART-009: geometry of each `ShipFeature`, placed from the blueprint's hull profile.
enum ShipFeatures {
    typealias Parts = (solid: [ShipPart], detail: [ShipPart])

    static func parts(_ f: ShipFeature, bp: ShipBlueprint, hull: Path) -> Parts {
        let nose = bp.noseX, tail = bp.tailX
        switch f {
        case .antennae: return (mirrored(antenna(nose: nose, bp: bp)), [])
        case .proboscis:
            return ([ShipPart(ArtGeometry.capsule(from: CGPoint(x: nose - 0.04, y: 0.5), to: CGPoint(x: min(0.99, nose + 0.17), y: 0.5),
                                                  radius: 0.009), .dark)], [])
        case .abdomenLight: return ([], [ShipPart(abdomen(bp), .glow, solid: false)])
        case let .stripes(n): return ([], [ShipPart(stripes(n, bp: bp).intersection(hull), .accent, solid: false)])
        case .elytraSeam:
            var p = Path()
            p.move(to: CGPoint(x: tail + 0.04, y: 0.5))
            p.addLine(to: CGPoint(x: nose - (nose - tail) * 0.25, y: 0.5))
            return ([], [ShipPart(p, .dark, solid: false, lineWidth: 0.012)])
        case let .segments(n): return ([], [ShipPart(segmentLines(n, bp: bp), .dark, solid: false, lineWidth: 0.01)])
        case .mandibles: return (mirrored(mandible(nose: nose, bp: bp)), [])
        case .stinger:
            let w = max(0.02, bp.halfWidth(at: tail + 0.02))
            let tip = max(0.005, tail - 0.1)
            return ([ShipPart(ArtGeometry.polygon([CGPoint(x: tail + 0.04, y: 0.5 - w * 0.6), CGPoint(x: tip, y: 0.5),
                                                   CGPoint(x: tail + 0.04, y: 0.5 + w * 0.6)]), .dark)], [])
        case .waist:
            let x = bp.waistX, w = bp.halfWidth(at: x) + 0.012
            return ([], [ShipPart(Path(CGRect(x: x - 0.012, y: 0.5 - w, width: 0.024, height: 2 * w)), .accent, solid: false)])
        case .rearLegs: return (mirrored(rearLeg(bp)), [])
        case .pincers: return (mirrored(pincer(nose: nose, bp: bp)), [])
        case let .curledTail(n): return (curledTail(n, bp: bp), [])
        case .hornRam:
            return ([ShipPart(ArtGeometry.closedSpline([SplinePoint(nose - 0.06, 0.5 - 0.045, sharp: true), SplinePoint(nose + 0.06, 0.5 - 0.02),
                                                        SplinePoint(min(0.99, nose + 0.15), 0.5, sharp: true), SplinePoint(nose + 0.06, 0.5 + 0.02),
                                                        SplinePoint(nose - 0.06, 0.5 + 0.045, sharp: true)]), .dark)], [])
        case .raptorialArms: return (mirrored(raptorialArm(bp)), [])
        case let .tentacles(n): return (tentacles(n, bp: bp), [])
        case let .eyes(n): return ([], [ShipPart(eyes(n, bp: bp), .glow, solid: false)])
        case .bottle: return ([], [])
        case .cork:
            let w = bp.halfWidth(at: nose) * 0.95
            return ([ShipPart(Path(roundedRect: CGRect(x: nose - 0.01, y: 0.5 - w, width: 0.07, height: 2 * w), cornerRadius: 0.01), .cork)], [])
        case .scroll:
            let rect = CGRect(x: tail + 0.12, y: 0.42, width: (nose - tail) * 0.42, height: 0.16)
            return ([], [ShipPart(Path(roundedRect: rect, cornerRadius: 0.03), .parchment, solid: false)])
        case .skids: return (mirrored(skid(bp)), [])
        case let .hardpoints(n): return (hardpoints(n, bp: bp), [])
        case let .cargoPods(n): return (cargoPods(n, bp: bp), [])
        case let .shieldFins(n): return (shieldFins(n, bp: bp), [])
        }
    }

    /// Extra glow emitters (the Firefly's abdomen light, the monster's bioluminescence).
    static func glows(_ bp: ShipBlueprint) -> [EngineMount] {
        var out: [EngineMount] = []
        if bp.features.contains(.abdomenLight) {
            out.append(EngineMount(x: bp.tailX + 0.08, radius: 0.12))
        }
        if bp.organicSeed != nil { out.append(EngineMount(x: 0.62, radius: 0.2)) }
        return out
    }

    private static func mirrored(_ path: Path, role: ShipPart.Role = .dark) -> [ShipPart] {
        [ShipPart(path, role), ShipPart(ArtGeometry.mirrorY(path), role)]
    }

    private static func antenna(nose: Double, bp: ShipBlueprint) -> Path {
        let w = bp.halfWidth(at: nose - 0.04)
        let curve = ArtGeometry.openSpline([SplinePoint(nose - 0.05, 0.5 - w * 0.5), SplinePoint(nose + 0.04, 0.5 - w - 0.06),
                                            SplinePoint(min(0.99, nose + 0.11), 0.5 - w - 0.16)])
        return ArtGeometry.stroke(curve, width: 0.012)
    }

    private static func abdomen(_ bp: ShipBlueprint) -> Path {
        let x = bp.tailX + 0.02, w = bp.halfWidth(at: bp.tailX + 0.1) * 0.8
        return Path(ellipseIn: CGRect(x: x, y: 0.5 - w, width: 0.16, height: 2 * w))
    }

    private static func stripes(_ n: Int, bp: ShipBlueprint) -> Path {
        var p = Path()
        let len = bp.noseX - bp.tailX
        for i in 0..<max(1, n) {
            let x = bp.tailX + len * (0.22 + 0.16 * Double(i))
            p.addRect(CGRect(x: x, y: 0, width: len * 0.07, height: 1))
        }
        return p
    }

    private static func segmentLines(_ n: Int, bp: ShipBlueprint) -> Path {
        var p = Path()
        let len = bp.noseX - bp.tailX
        for i in 1..<max(2, n) {
            let x = bp.tailX + len * Double(i) / Double(n)
            let w = bp.halfWidth(at: x)
            p.move(to: CGPoint(x: x, y: 0.5 - w))
            p.addLine(to: CGPoint(x: x, y: 0.5 + w))
        }
        return p
    }

    private static func mandible(nose: Double, bp: ShipBlueprint) -> Path {
        let w = bp.halfWidth(at: nose - 0.01)
        let curve = ArtGeometry.openSpline([SplinePoint(nose - 0.03, 0.5 - w * 0.8), SplinePoint(nose + 0.06, 0.5 - w - 0.02),
                                            SplinePoint(min(0.99, nose + 0.11), 0.5 - w * 0.25)])
        return ArtGeometry.stroke(curve, width: 0.028)
    }

    private static func rearLeg(_ bp: ShipBlueprint) -> Path {
        let hip = CGPoint(x: 0.6, y: 0.5 - bp.halfWidth(at: 0.6) * 0.6)
        var p = Path()
        p.move(to: hip)
        p.addLine(to: CGPoint(x: 0.72, y: 0.22))
        p.addLine(to: CGPoint(x: 0.03, y: 0.15))
        var leg = ArtGeometry.stroke(p, width: 0.03)
        leg.addPath(ArtGeometry.capsule(from: CGPoint(x: 0.03, y: 0.15), to: CGPoint(x: 0.12, y: 0.15), radius: 0.025))
        return leg
    }

    private static func pincer(nose: Double, bp: ShipBlueprint) -> Path {
        let w = bp.halfWidth(at: nose - 0.12)
        var arm = Path()
        arm.move(to: CGPoint(x: nose - 0.14, y: 0.5 - w * 0.7))
        arm.addLine(to: CGPoint(x: nose - 0.02, y: 0.24))
        var p = ArtGeometry.stroke(arm, width: 0.035)
        let claw = ArtGeometry.closedSpline([SplinePoint(nose - 0.04, 0.27, sharp: true), SplinePoint(nose + 0.04, 0.14),
                                             SplinePoint(min(0.99, nose + 0.13), 0.2, sharp: true), SplinePoint(nose + 0.05, 0.21),
                                             SplinePoint(min(0.97, nose + 0.11), 0.27, sharp: true), SplinePoint(nose + 0.03, 0.31)])
        p.addPath(claw)
        return p
    }

    private static func curledTail(_ n: Int, bp: ShipBlueprint) -> [ShipPart] {
        let tail = bp.tailX
        // Plan view: the tail leaves the hull aft, sweeps out to one side and curls forward over the hull.
        var parts: [ShipPart] = []
        let count = max(3, n)
        var last = CGPoint(x: tail, y: 0.5)
        for i in 0..<count {
            let t = Double(i + 1) / Double(count)
            let a = Double.pi * (1.05 + 1.0 * t)
            let c = CGPoint(x: tail + 0.2 + cos(a) * 0.2, y: 0.42 + sin(a) * 0.34 * t)
            let r = 0.05 - 0.022 * t
            parts.append(ShipPart(ArtGeometry.capsule(from: last, to: c, radius: r * 0.7), .dark))
            parts.append(ShipPart(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), .primary))
            last = c
        }
        let sting = ArtGeometry.polygon([CGPoint(x: last.x - 0.02, y: last.y - 0.015), CGPoint(x: last.x + 0.1, y: last.y + 0.03),
                                         CGPoint(x: last.x - 0.01, y: last.y + 0.025)])
        parts.append(ShipPart(sting, .accent))
        return parts
    }

    private static func raptorialArm(_ bp: ShipBlueprint) -> Path {
        let shoulder = CGPoint(x: 0.62, y: 0.5 - bp.halfWidth(at: 0.62) * 0.7)
        var p = Path()
        p.move(to: shoulder)
        p.addLine(to: CGPoint(x: 0.8, y: 0.25))
        p.addLine(to: CGPoint(x: 0.97, y: 0.4))
        return ArtGeometry.stroke(p, width: 0.03)
    }

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

    private static func skid(_ bp: ShipBlueprint) -> Path {
        let x0 = bp.tailX + 0.05, x1 = bp.tailX + 0.3
        let w = bp.halfWidth(at: (x0 + x1) / 2) + 0.06
        var p = ArtGeometry.capsule(from: CGPoint(x: x0, y: 0.5 - w), to: CGPoint(x: x1, y: 0.5 - w), radius: 0.016)
        p.addPath(ArtGeometry.capsule(from: CGPoint(x: (x0 + x1) / 2, y: 0.5 - w), to: CGPoint(x: (x0 + x1) / 2, y: 0.5 - w + 0.08),
                                      radius: 0.01))
        return p
    }

    private static func hardpoints(_ n: Int, bp: ShipBlueprint) -> [ShipPart] {
        var parts: [ShipPart] = []
        guard n > 0 else { return parts }
        let x = min(0.97, bp.noseX - 0.06)
        for tier in 0..<(n / 2) {
            let along = x - 0.12 - Double(tier) * 0.1
            let off = bp.halfWidth(at: along) + 0.025 + Double(tier) * 0.03
            let barrel = ArtGeometry.capsule(from: CGPoint(x: along - 0.08, y: 0.5 - off), to: CGPoint(x: min(0.99, along + 0.1), y: 0.5 - off),
                                             radius: 0.012)
            parts += mirrored(barrel)
        }
        if n % 2 == 1 {
            parts.append(ShipPart(ArtGeometry.capsule(from: CGPoint(x: bp.noseX - 0.06, y: 0.5), to: CGPoint(x: min(0.99, bp.noseX + 0.07), y: 0.5),
                                                      radius: 0.011), .dark))
        }
        return parts
    }

    private static func cargoPods(_ n: Int, bp: ShipBlueprint) -> [ShipPart] {
        var parts: [ShipPart] = []
        guard n > 0 else { return parts }
        let len = bp.noseX - bp.tailX
        let pairs = max(1, n / 2)
        for slot in 0..<(n / 2) {
            let x = bp.tailX + len * (0.16 + 0.62 * Double(slot) / Double(pairs))
            let w = len * 0.58 / Double(pairs)
            let off = bp.halfWidth(at: x + w / 2) + 0.005
            let pod = Path(roundedRect: CGRect(x: x, y: 0.5 - off - 0.07, width: w * 0.88, height: 0.07), cornerRadius: 0.015)
            parts += mirrored(pod, role: .secondary)
        }
        if n % 2 == 1 {
            let w = len * 0.3
            parts.append(ShipPart(Path(roundedRect: CGRect(x: bp.tailX - 0.01, y: 0.465, width: w, height: 0.07), cornerRadius: 0.02),
                                  .secondary))
        }
        return parts
    }

    private static func shieldFins(_ n: Int, bp: ShipBlueprint) -> [ShipPart] {
        var parts: [ShipPart] = []
        guard n > 0 else { return parts }
        for i in 0..<n {
            let x = bp.tailX + 0.06 + 0.07 * Double(i)
            let w = bp.halfWidth(at: x + 0.03)
            let fin = ArtGeometry.polygon([CGPoint(x: x, y: 0.5 - w), CGPoint(x: x + 0.05, y: 0.5 - w),
                                           CGPoint(x: x - 0.02, y: 0.5 - w - 0.07 - 0.01 * Double(i))])
            parts += mirrored(fin, role: .accent)
        }
        return parts
    }
}
