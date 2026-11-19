// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// ART-SHIP-009: the designs that are not human-built ships from statistics: the Space Monster (a creature), the
/// Mantis (alien), the Dragonfly (a stolen prototype), the Scarab (a hull-hardened raider) and the drifting bottle.
/// Warships still show their slots and what is installed in them.
enum ShipSpecialForge {
    static func poly(_ points: [(Double, Double)]) -> Path { ArtGeometry.polygon(points.map { CGPoint(x: $0.0, y: $0.1) }) }

    static func spline(_ points: [(Double, Double)]) -> Path { ArtGeometry.closedSpline(points.map { SplinePoint($0.0, $0.1) }) }

    static func circle(_ x: Double, _ y: Double, _ r: Double) -> Path { Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)) }

    // MARK: Space Monster

    /// A creature, not a vessel: a segmented body, tendrils and bioluminescent nodes. It has no modules.
    static func monster(_ input: ShipArtInput) -> ShipGeometry {
        var rng = ArtRandom(seed: ArtSeed.kind(.spaceMonster))
        var parts: [ShipPart] = []
        let flesh = ArtRGB(0.30, 0.16, 0.34), belly = ArtRGB(0.46, 0.24, 0.40), glow = ArtRGB(0.45, 1.0, 0.80)
        // Tendrils trail aft.
        for i in 0..<7 {
            let y = 0.5 + (Double(i) - 3) * 0.045, wave = rng.range(-0.05...0.05)
            let path = ArtGeometry.openSpline([SplinePoint(0.50, y), SplinePoint(0.34, y + wave), SplinePoint(0.20, y - wave * 0.8),
                                               SplinePoint(0.06 + rng.range(0...0.05), y + wave * 1.4)])
            parts.append(ShipPart(ArtGeometry.stroke(path, width: 0.022 - Double(abs(i - 3)) * 0.003), .secondary, color: flesh.shade(0.8), tag: "tendril"))
        }
        let body = ArtGeometry.blob(center: CGPoint(x: 0.66, y: 0.5), radius: 0.22, lobes: 9, jitter: 0.16, rng: &rng, aspect: 1.25)
        parts.append(ShipPart(body, .primary, color: flesh, tag: "body"))
        for i in 0..<4 {
            let x = 0.50 + Double(i) * 0.085
            let band = Path(CGRect(x: x, y: 0, width: 0.016, height: 1)).intersection(body)
            parts.append(ShipPart(band, .secondary, solid: false, color: belly.opacity(0.55), flat: true, tag: "segment"))
        }
        for i in 0..<6 {
            let a = Double(i) / 6 * 2 * .pi + 0.4
            parts.append(ShipPart(circle(0.68 + cos(a) * 0.13, 0.5 + sin(a) * 0.10, 0.014), .glow, solid: false, color: glow, tag: "node"))
        }
        parts.append(ShipPart(circle(0.84, 0.5, 0.030), .glow, solid: false, color: glow.shade(1.2), tag: "maw"))
        var g = ShipGeometry(parts: parts, hull: body, glows: [EngineMount(x: 0.66, radius: 0.16)], lights: [])
        g.organic = true
        g.glow = glow
        g.paint = flesh
        return g
    }

    // MARK: Bottle

    /// A sealed bottle with a rolled note, drifting.
    static func bottle(_ input: ShipArtInput) -> ShipGeometry {
        let body = spline([(0.20, 0.40), (0.56, 0.38), (0.66, 0.44), (0.80, 0.46), (0.80, 0.54), (0.66, 0.56), (0.56, 0.62), (0.20, 0.60), (0.16, 0.50)])
        let parts = [
            ShipPart(body, .glass, tag: "bottle"),
            ShipPart(Path(roundedRect: CGRect(x: 0.78, y: 0.455, width: 0.06, height: 0.09), cornerRadius: 0.01), .cork, tag: "cork"),
            ShipPart(Path(roundedRect: CGRect(x: 0.28, y: 0.455, width: 0.22, height: 0.09), cornerRadius: 0.03), .parchment, solid: false, tag: "note"),
        ]
        var g = ShipGeometry(parts: parts, hull: body, glows: [], lights: [])
        g.glass = true
        g.paint = ArtRGB(0.55, 0.75, 0.70)
        return g
    }

    // MARK: Mantis

    /// Not a human ship: asymmetric, crystalline segments in iridescent green and violet, no containers and no markings.
    /// Its fittings are shown in alien form: spines for weapons, glowing nodes for shields, fins for gadgets.
    static func mantis(_ input: ShipArtInput) -> ShipGeometry {
        let l = ShipLivery.make(role: .alien, seed: input.liverySeed ?? ArtSeed.kind(.mantis)), s = input.stats
        var parts: [ShipPart] = []
        // A grown, not built, hull: one long blade with a kink, and three blades of different length and angle.
        let spear = spline([(0.05, 0.52), (0.22, 0.455), (0.46, 0.415), (0.70, 0.43), (0.95, 0.475), (0.74, 0.545), (0.48, 0.585), (0.24, 0.575)])
        parts.append(ShipPart(spline([(0.24, 0.47), (0.36, 0.30), (0.52, 0.17), (0.60, 0.20), (0.52, 0.34), (0.44, 0.45)]), .secondary, color: l.secondary,
            tag: "shard"))
        parts.append(ShipPart(spline([(0.16, 0.56), (0.24, 0.70), (0.36, 0.80), (0.50, 0.76), (0.42, 0.66), (0.38, 0.58)]), .secondary,
            color: l.secondary.shade(0.8),
                              tag: "shard"))
        parts.append(ShipPart(spline([(0.52, 0.57), (0.62, 0.66), (0.76, 0.69), (0.82, 0.63), (0.72, 0.58), (0.66, 0.54)]), .secondary,
            color: l.base.shade(0.75),
                              tag: "shard"))
        parts.append(ShipPart(spear, .primary, color: l.base, tag: "spear"))
        parts.append(ShipPart(spline([(0.10, 0.515), (0.40, 0.46), (0.70, 0.455), (0.93, 0.477), (0.70, 0.49), (0.40, 0.505)]), .accent, solid: false,
                              color: l.accent.opacity(0.50), flat: true, tag: "vein"))
        let weapons = s.weapons ?? []
        for i in 0..<s.weaponSlots {
            let y = 0.43 + Double(i) * 0.045, x = 0.74 - Double(i) * 0.05
            let long = i < weapons.count
            parts.append(ShipPart(poly([(x, y - 0.010), (x + (long ? 0.16 : 0.05), y), (x, y + 0.010)]), .dark,
                color: long ? l.accent.shade(0.8) : l.secondary.shade(0.6),
                                  tag: long ? "weapon:\(weapons[i])" : "emptyHardpoint"))
            parts.append(ShipPart(circle(x, y, 0.010), .dark, solid: false, color: l.secondary.shade(0.5), flat: true, tag: "hardpoint"))
        }
        let shields = s.shields ?? []
        for i in 0..<s.shieldSlots {
            let x = 0.36 + Double(i) * 0.10
            parts.append(ShipPart(circle(x, 0.50, 0.016), .dark, solid: false, color: l.secondary.shade(0.5), flat: true, tag: "emitter"))
            if i < shields.count { parts.append(ShipPart(circle(x, 0.50, 0.011), .glow, solid: false, color: l.accent, tag: "shield:\(shields[i])")) }
        }
        let gadgets = s.gadgets ?? []
        for i in 0..<s.gadgetSlots {
            let x = 0.16 + Double(i) * 0.06
            parts.append(ShipPart(circle(x, 0.535, 0.009), .dark, solid: false, color: l.secondary.shade(0.5), flat: true, tag: "gadgetMount"))
            if i < gadgets.count, gadgets[i] != ShipFittings.hiddenBays {
                parts.append(ShipPart(poly([(x - 0.012, 0.54), (x + 0.012, 0.54), (x - 0.02, 0.66 + Double(i) * 0.02)]), .secondary, color: l.base.shade(1.2),
                                      tag: "gadget:\(gadgets[i])"))
            }
        }
        var g = ShipGeometry(parts: parts, hull: spear, glows: [EngineMount(x: 0.10, yOffset: 0.02, radius: 0.030)], lights: [])
        g.glow = l.accent
        g.paint = l.base
        return g
    }

    // MARK: Dragonfly

    /// A stolen prototype: a needle hull in test-flight orange and white with three oversized shield emitters.
    static func dragonfly(_ input: ShipArtInput) -> ShipGeometry {
        let s = input.stats
        let white = ArtRGB(0.92, 0.92, 0.90), orange = ArtRGB(0.95, 0.48, 0.12)
        var parts: [ShipPart] = []
        let needle = spline([(0.08, 0.47), (0.30, 0.455), (0.70, 0.468), (0.95, 0.50), (0.70, 0.532), (0.30, 0.545), (0.08, 0.53)])
        for side in [-1.0, 1.0] {
            let y = 0.5 + side * 0.10
            parts.append(ShipPart(poly([(0.26, 0.5 + side * 0.04), (0.36, 0.5 + side * 0.04), (0.30, y), (0.22, y)]), .dark, color: ArtRGB(0.30, 0.32,
                0.36), tag: "pylon"))
            parts.append(ShipPart(ArtGeometry.capsule(from: CGPoint(x: 0.14, y: y), to: CGPoint(x: 0.40, y: y), radius: 0.022), .secondary,
                color: white.shade(0.9),
                                  tag: "pod"))
        }
        parts.append(ShipPart(needle, .primary, color: white, tag: "needle"))
        for i in 0..<4 {
            let x = 0.14 + Double(i) * 0.20
            parts.append(ShipPart(Path(CGRect(x: x, y: 0, width: 0.07, height: 1)).intersection(needle), .accent, solid: false, color: orange, flat: true,
                tag: "panel"))
        }
        parts.append(ShipPart(poly([(0.80, 0.482), (0.90, 0.495), (0.90, 0.505), (0.80, 0.518)]), .cockpit, solid: false, tag: "flightDeck"))
        let shields = s.shields ?? []
        for i in 0..<s.shieldSlots {
            let x = 0.36 + Double(i) * 0.15
            parts.append(ShipPart(circle(x, 0.5, 0.034).subtracting(circle(x, 0.5, 0.022)), .dark, color: ArtRGB(0.20, 0.22, 0.26), tag: "emitter"))
            if i < shields.count { parts.append(ShipPart(circle(x, 0.5, 0.020), .glow, solid: false, color: ArtRGB(0.40, 0.80, 1.0),
                tag: "shield:\(shields[i])")) }
        }
        let weapons = s.weapons ?? []
        for i in 0..<s.weaponSlots {
            let side: Double = i % 2 == 0 ? -1 : 1, c = CGPoint(x: 0.40, y: 0.5 + side * 0.10)
            parts.append(ShipPart(ShipFittings.circle(c, 0.012), .dark, solid: false, color: ShipFittings.gunmetal, flat: true, tag: "hardpoint"))
            if i < weapons.count { parts.append(ShipPart(ShipFittings.barrel(from: c, length: 0.09, width: 0.008), .dark, color: ShipFittings.metal,
                tag: "weapon:\(weapons[i])")) }
        }
        for i in 0..<s.gadgetSlots {
            parts.append(ShipPart(Path(CGRect(x: 0.16 + Double(i) * 0.04, y: 0.492, width: 0.020, height: 0.016)), .dark, solid: false,
                color: ShipFittings.metal.shade(1.3),
                                  flat: true, tag: "gadgetMount"))
        }
        var g = ShipGeometry(parts: parts, hull: needle, glows: [EngineMount(x: 0.09, radius: 0.026), EngineMount(x: 0.13, yOffset: -0.10, radius: 0.018),
                                                                 EngineMount(x: 0.13, yOffset: 0.10, radius: 0.018)],
                             lights: [ShipLight(position: CGPoint(x: 0.30, y: 0.38), kind: .port), ShipLight(position: CGPoint(x: 0.30, y: 0.62),
                                 kind: .starboard)])
        g.paint = white
        return g
    }

    // MARK: Scarab

    /// A hull-hardened raider: a heavy, faceted dark shell that covers most of the ship.
    static func scarab(_ input: ShipArtInput) -> ShipGeometry {
        let s = input.stats
        let shellDark = ArtRGB(0.16, 0.17, 0.20), shellLight = ArtRGB(0.26, 0.27, 0.31)
        var parts: [ShipPart] = []
        parts.append(ShipPart(Path(roundedRect: CGRect(x: 0.07, y: 0.42, width: 0.12, height: 0.16), cornerRadius: 0.02), .secondary, color: ArtRGB(0.22,
            0.23, 0.26),
                              tag: "engine"))
        parts.append(ShipPart(poly([(0.80, 0.44), (0.95, 0.48), (0.95, 0.52), (0.80, 0.56)]), .primary, color: shellLight, tag: "nose"))
        let shell = poly([(0.14, 0.40), (0.28, 0.27), (0.62, 0.25), (0.84, 0.38), (0.88, 0.50), (0.84, 0.62), (0.62, 0.75), (0.28, 0.73), (0.14, 0.60)])
        parts.append(ShipPart(shell, .primary, color: shellDark, tag: "shell"))
        // Facets: the plates of the hardened hull.
        let ridge = [(0.20, 0.50), (0.40, 0.50), (0.62, 0.50), (0.82, 0.50)]
        let rim = [(0.28, 0.27), (0.62, 0.25), (0.84, 0.38)]
        for i in 0..<3 {
            for side in [-1.0, 1.0] {
                let a = ridge[i], b = ridge[i + 1], c = rim[min(i, 2)]
                parts.append(ShipPart(poly([a, b, (c.0, 0.5 + side * (c.1 - 0.5))]), .primary, solid: false,
                                      color: (side < 0 ? shellLight : shellDark.shade(0.8)).opacity(0.9), flat: true, tag: "plate"))
            }
        }
        parts.append(ShipPart(poly([(0.84, 0.47), (0.92, 0.49), (0.92, 0.51), (0.84, 0.53)]), .cockpit, solid: false, tag: "flightDeck"))
        let weapons = s.weapons ?? []
        for i in 0..<s.weaponSlots {
            let side: Double = i % 2 == 0 ? -1 : 1, c = CGPoint(x: 0.78, y: 0.5 + side * 0.09)
            parts.append(ShipPart(ShipFittings.circle(c, 0.014), .dark, solid: false, color: ShipFittings.gunmetal, flat: true, tag: "hardpoint"))
            if i < weapons.count { parts.append(ShipPart(ShipFittings.barrel(from: c, length: 0.12, width: 0.010), .dark, color: ShipFittings.metal,
                tag: "weapon:\(weapons[i])")) }
        }
        var g = ShipGeometry(parts: parts, hull: shell, glows: [EngineMount(x: 0.08, yOffset: -0.04, radius: 0.030), EngineMount(x: 0.08, yOffset: 0.04,
            radius: 0.030)],
                             lights: [ShipLight(position: CGPoint(x: 0.08, y: 0.5), kind: .tail)])
        g.paint = shellDark
        return g
    }
}
