// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// ART-SHIP-004: the slots of a ship and what is installed in them. Every slot has a mount; an installed item adds its
/// own, distinct shape; an empty slot shows a capped mount, a bare socket or a blank plate. Raw values are the engine's:
/// weapons 0 pulse, 1 beam, 2 military, 3 Morgan's, 4 photon disruptor, 5 quantum disruptor; shields 0 energy,
/// 1 reflective, 2 lightning; gadgets 0 extra bays, 1 auto-repair, 2 navigating, 3 targeting, 4 cloaking, 5 fuel compactor,
/// 6 hidden bays (which show nothing, because they are hidden).
enum ShipFittings {
    static let metal = ArtRGB(0.30, 0.32, 0.36)
    static let gunmetal = ArtRGB(0.16, 0.17, 0.20)
    static let hiddenBays = 6

    static func apply(_ b: inout ShipBuilder) {
        weapons(&b)
        shields(&b)
        gadgets(&b)
    }

    /// Where the slots sit (unit space): the class's own mount points first, then further mounts along the flanks.
    static func hardpoints(_ b: ShipBuilder, slots: Int) -> [CGPoint] {
        (0..<slots).map { i in
            if i < b.weaponMounts.count { return b.weaponMounts[i] }
            let side: Double = i % 2 == 0 ? -1 : 1, x = b.cabinRange.lowerBound - Double((i - b.weaponMounts.count) / 2) * 0.06
            return CGPoint(x: x, y: 0.5 + side * (b.plan.half(at: x) + 0.004))
        }
    }

    static func emitters(_ b: ShipBuilder, slots: Int) -> [CGPoint] {
        let r = b.emitterRange
        return (0..<slots).map { CGPoint(x: r.lowerBound + (r.upperBound - r.lowerBound) * (Double($0) + 0.5) / Double(slots), y: 0.5) }
    }

    static func gadgetMounts(_ b: ShipBuilder, slots: Int) -> [CGPoint] {
        let r = b.gadgetRange
        return (0..<slots).map { i in
            let x = r.lowerBound + (r.upperBound - r.lowerBound) * (Double(i) + 0.5) / Double(slots)
            return CGPoint(x: x, y: 0.5 + b.plan.half(at: x) * 0.42)
        }
    }

    static func circle(_ c: CGPoint, _ r: Double) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)) }

    static func barrel(from c: CGPoint, length: Double, width: Double, dy: Double = 0) -> Path {
        Path(roundedRect: CGRect(x: c.x, y: c.y + dy - width / 2, width: length, height: width), cornerRadius: width * 0.3)
    }

    static func weapons(_ b: inout ShipBuilder) {
        let installed = b.stats.weapons ?? []
        for (i, c) in hardpoints(b, slots: b.stats.weaponSlots).enumerated() {
            b.add(circle(c, 0.011), .dark, color: gunmetal, tag: "hardpoint")
            guard i < installed.count else {
                b.add(Path(roundedRect: CGRect(x: c.x - 0.006, y: c.y - 0.006, width: 0.012, height: 0.012), cornerRadius: 0.003), .dark, solid: false,
                      color: metal.shade(1.5), flat: true, tag: "emptyHardpoint")
                continue
            }
            let tag = "weapon:\(installed[i])"
            switch installed[i] {
            case 0: b.add(barrel(from: c, length: 0.050, width: 0.009), .dark, color: metal, tag: tag)
            case 1: b.add(barrel(from: c, length: 0.100, width: 0.007), .dark, color: metal, tag: tag)
            case 2:
                b.add(circle(c, 0.019), .dark, color: metal.shade(0.8), tag: tag)
                b.add(barrel(from: c, length: 0.078, width: 0.006, dy: -0.007).union(barrel(from: c, length: 0.078, width: 0.006, dy: 0.007)), .dark,
                      color: metal, tag: tag)
            case 3:
                b.add(barrel(from: c, length: 0.125, width: 0.016), .dark, color: metal.shade(0.85), tag: tag)
                for k in 0..<3 {
                    b.add(Path(CGRect(x: c.x + 0.030 + Double(k) * 0.026, y: c.y - 0.012, width: 0.007, height: 0.024)), .accent, solid: true,
                          color: ArtRGB(0.80, 0.45, 0.20), flat: true, tag: tag)
                }
            case 4:
                b.add(barrel(from: c, length: 0.030, width: 0.006), .dark, color: metal, tag: tag)
                var dish = Path()
                dish.addArc(center: CGPoint(x: c.x + 0.052, y: c.y), radius: 0.024, startAngle: .degrees(100), endAngle: .degrees(260), clockwise: false)
                b.add(ArtGeometry.stroke(dish, width: 0.008), .secondary, color: ArtRGB(0.70, 0.78, 0.86), tag: tag)
            default:
                b.add(barrel(from: c, length: 0.034, width: 0.006), .dark, color: metal, tag: tag)
                let centre = CGPoint(x: c.x + 0.052, y: c.y)
                b.add(circle(centre, 0.024).subtracting(circle(centre, 0.014)), .secondary, color: ArtRGB(0.62, 0.50, 0.86), tag: tag)
            }
        }
    }

    static func shields(_ b: inout ShipBuilder) {
        let installed = b.stats.shields ?? []
        for (i, c) in emitters(b, slots: b.stats.shieldSlots).enumerated() {
            b.add(circle(c, 0.016).subtracting(circle(c, 0.010)), .dark, solid: false, color: gunmetal, flat: true, tag: "emitter")
            guard i < installed.count else {
                b.add(circle(c, 0.010), .dark, solid: false, color: ArtRGB(0.05, 0.05, 0.06), flat: true, tag: "emptyEmitter")
                continue
            }
            let tag = "shield:\(installed[i])"
            switch installed[i] {
            case 0: b.add(circle(c, 0.013), .glow, solid: false, color: ArtRGB(0.35, 0.75, 1.0), tag: tag)
            case 1:
                b.add(ArtGeometry.polygon([CGPoint(x: c.x + 0.017, y: c.y), CGPoint(x: c.x, y: c.y - 0.017), CGPoint(x: c.x - 0.017, y: c.y),
                                           CGPoint(x: c.x, y: c.y + 0.017)]), .secondary, solid: false, color: ArtRGB(0.88, 0.90, 0.94), tag: tag)
            default:
                b.add(ArtGeometry.star(center: c, points: 6, outer: 0.021, inner: 0.009), .glow, solid: false, color: ArtRGB(1.0, 0.90, 0.40), tag: tag)
            }
        }
    }

    static func gadgets(_ b: inout ShipBuilder) {
        let installed = b.stats.gadgets ?? [], plan = b.plan
        for (i, c) in gadgetMounts(b, slots: b.stats.gadgetSlots).enumerated() {
            b.add(Path(roundedRect: CGRect(x: c.x - 0.011, y: c.y - 0.009, width: 0.022, height: 0.018), cornerRadius: 0.003), .dark, solid: false,
                  color: metal.shade(1.25), flat: true, tag: "gadgetMount")
            guard i < installed.count, installed[i] != hiddenBays else { continue }
            let tag = "gadget:\(installed[i])"
            switch installed[i] {
            case 0: // Extra cargo bays: one more pod, slung outboard aft, in a contrasting colour.
                let x = b.cargoRange.lowerBound + 0.02, y = plan.half(at: x + 0.04)
                b.add(Path(roundedRect: CGRect(x: x, y: 0.5 + y - 0.006, width: 0.085, height: 0.040), cornerRadius: 0.012),
                      .accent, color: b.livery.accent.mix(ArtRGB(0.9, 0.9, 0.9), 0.25), tag: tag)
            case 1: // Auto-repair system: a folded manipulator arm on its cradle.
                b.add(ArtGeometry.capsule(from: c, to: CGPoint(x: c.x + 0.030, y: c.y - 0.022), radius: 0.005)
                    .union(ArtGeometry.capsule(from: CGPoint(x: c.x + 0.030, y: c.y - 0.022), to: CGPoint(x: c.x + 0.006, y: c.y - 0.034), radius: 0.004)),
                      .dark, solid: false, color: ArtRGB(0.90, 0.66, 0.18), tag: tag)
            case 2: // Navigating system: a communications dish.
                b.add(circle(c, 0.017), .secondary, solid: false, color: ArtRGB(0.88, 0.89, 0.90), tag: tag)
                b.add(circle(c, 0.005), .dark, solid: false, color: gunmetal, flat: true, tag: tag)
            case 3: // Targeting system: a sensor mast with a lens.
                let tip = CGPoint(x: c.x + 0.014, y: 0.5 + plan.half(at: c.x) + 0.050)
                b.add(ArtGeometry.capsule(from: c, to: tip, radius: 0.0035), .dark, color: metal, tag: tag)
                b.add(circle(tip, 0.009), .glow, color: ArtRGB(1.0, 0.30, 0.25), tag: tag)
            case 4: // Cloaking device: four dark vanes fore and aft of the cabins.
                for sx in [b.cabinRange.lowerBound + 0.01, b.cabinRange.upperBound - 0.01] {
                    for side in [-1.0, 1.0] {
                        let y = 0.5 + side * plan.half(at: sx) * 0.96
                        b.add(ArtGeometry.polygon([CGPoint(x: sx - 0.008, y: y), CGPoint(x: sx + 0.008, y: y), CGPoint(x: sx - 0.004, y: y + side * 0.050),
                                                   CGPoint(x: sx - 0.020, y: y + side * 0.050)]), .dark, color: ArtRGB(0.20, 0.18, 0.36), flat: true, tag: tag)
                    }
                }
            default: // Fuel compactor: a band clamped around the hull over the propellant blisters.
                let x = b.tankStart + 0.05, reach = plan.half(at: x) + 0.008
                let outer = Path(roundedRect: CGRect(x: x - 0.016, y: 0.5 - reach, width: 0.032, height: reach * 2), cornerRadius: 0.012)
                let inner = Path(roundedRect: CGRect(x: x - 0.007, y: 0.5 - reach + 0.010, width: 0.014, height: max(0.002, reach * 2 - 0.020)),
                    cornerRadius: 0.006)
                b.add(outer.subtracting(inner), .secondary, color: ArtRGB(0.80, 0.56, 0.24), tag: tag)
            }
        }
    }
}
