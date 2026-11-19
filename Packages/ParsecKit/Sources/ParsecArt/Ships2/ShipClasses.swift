// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// ART-SHIP-005: the ten classes of built ship. Each class has its own design: a hull plan and what flies with it
/// (wings, booms, pods). The statistics then shape it (cargo widens the mid-body, see `ShipBuilder.statistics`), and each
/// design carries a light nod to the class's name: the Flea's jumping-leg tank booms, the Mosquito's needle nose,
/// the Bumblebee's banded round body, the Beetle's wing-case seam, the Hornet's and the Wasp's narrow waist, the Wasp's
/// tail spike, the Grasshopper's hind-leg nacelles, the Termite's segments, the Firefly's lit tail.
enum ShipClasses {
    static func design(_ kind: ShipArtKind, _ b: inout ShipBuilder) {
        switch kind {
        case .flea: flea(&b)
        case .gnat: gnat(&b)
        case .firefly: firefly(&b)
        case .mosquito: mosquito(&b)
        case .bumblebee: bumblebee(&b)
        case .beetle: beetle(&b)
        case .hornet: hornet(&b)
        case .grasshopper: grasshopper(&b)
        case .termite: termite(&b)
        case .scorpion: scorpion(&b)
        default: wasp(&b)
        }
    }

    static func wingColor(_ b: ShipBuilder) -> ArtRGB { b.livery.base.shade(0.84) }
    static func podColor(_ b: ShipBuilder) -> ArtRGB { b.livery.secondary }

    /// A pod or boom running fore and aft on the upper side of the picture (mirrored by `addPair`).
    static func pod(_ x0: Double, _ x1: Double, y: Double, radius: Double) -> Path {
        ArtGeometry.closedSpline([SplinePoint(x0, 0.5 - y), SplinePoint(x0 + radius, 0.5 - y - radius), SplinePoint(x1 - radius * 2.2, 0.5 - y - radius * 0.9),
                                  SplinePoint(x1, 0.5 - y), SplinePoint(x1 - radius * 2.2, 0.5 - y + radius * 0.9), SplinePoint(x0 + radius, 0.5 - y + radius)])
    }

    static func strut(_ points: [(Double, Double)], width: Double) -> Path {
        ArtGeometry.stroke(ArtGeometry.openSpline(points.map { SplinePoint($0.0, $0.1) }), width: width)
    }

    // MARK: Flea — a tiny pod between two long tank booms

    static func flea(_ b: inout ShipBuilder) {
        let g = b.frame.girth
        b.plan = HullPlan([(0.30, 0.034), (0.36, 0.068 + 0.02 * g), (0.55, 0.084 + 0.03 * g), (0.74, 0.064), (0.88, 0.030), (0.95, 0)])
        let x0 = 0.62 - (0.24 + 0.30 * Double(min(20, b.stats.fuelTanks)) / 20)
        b.addPair(strut([(0.54, 0.5 - 0.05), (0.49, 0.5 - 0.115), (0.42, 0.5 - 0.152)], width: 0.018), .dark, color: ShipBuilder.steel.shade(1.3), tag: "strut")
        b.addPair(strut([(0.42, 0.5 - 0.04), (0.36, 0.5 - 0.105), (0.28, 0.5 - 0.152)], width: 0.018), .dark, color: ShipBuilder.steel.shade(1.3), tag: "strut")
        b.addPair(pod(x0, 0.62, y: 0.152, radius: 0.024), .secondary, color: b.livery.base.shade(1.08), tag: "boom")
        b.engines(at: 0.30, spread: 0, radius: 0.026)
        b.glows += [EngineMount(x: x0 + 0.004, yOffset: -0.152, radius: 0.014), EngineMount(x: x0 + 0.004, yOffset: 0.152, radius: 0.014)]
        b.deck = 0.76...0.88
        b.cabinRange = 0.56...0.74
        b.cargoRange = 0.38...0.60
        b.tankStart = 0.34
        b.weaponMounts = [CGPoint(x: 0.66, y: 0.5 - 0.075), CGPoint(x: 0.66, y: 0.5 + 0.075)]
        b.emitterRange = 0.40...0.60
        b.gadgetRange = 0.32...0.40
        b.radiatorRange = 0.33...0.40
        b.seams = [0.40, 0.55, 0.72]
    }

    // MARK: Gnat — a slender dart with straight, slim wings

    static func gnat(_ b: inout ShipBuilder) {
        let g = b.frame.girth
        b.plan = HullPlan([(0.07, 0.030), (0.14, 0.050), (0.30, 0.058), (0.55, 0.062 + 0.03 * g), (0.78, 0.042), (0.90, 0.020), (0.95, 0)])
        b.addPair(ShipBuilder.surface(rootFront: 0.58, rootBack: 0.36, tipFront: 0.42, tipBack: 0.33, span: 0.21, rootY: 0.04), .secondary, color: wingColor(b),
                  tag: "wing")
        b.addPair(ShipBuilder.surface(rootFront: 0.20, rootBack: 0.09, tipFront: 0.11, tipBack: 0.06, span: 0.105, rootY: 0.03), .secondary,
            color: wingColor(b),
                  tag: "tailplane")
        b.engines(at: 0.07, spread: 0.022, radius: 0.022)
        b.deck = 0.76...0.88
        b.cabinRange = 0.56...0.74
        b.cargoRange = 0.28...0.54
        b.tankStart = 0.12
        b.weaponMounts = [CGPoint(x: 0.50, y: 0.5 - 0.095), CGPoint(x: 0.50, y: 0.5 + 0.095), CGPoint(x: 0.70, y: 0.5 - 0.05)]
        b.emitterRange = 0.34...0.56
        b.gadgetRange = 0.12...0.26
        b.radiatorRange = 0.10...0.20
    }

    // MARK: Firefly — a lifting body with a lit tail

    static func firefly(_ b: inout ShipBuilder) {
        let g = b.frame.girth
        b.plan = HullPlan([(0.08, 0.060), (0.16, 0.090), (0.34, 0.100), (0.56, 0.105 + 0.03 * g), (0.76, 0.075), (0.90, 0.030), (0.95, 0)])
        b.addPair(ArtGeometry.closedSpline([SplinePoint(0.52, 0.5 - 0.08, sharp: true), SplinePoint(0.42, 0.5 - 0.17), SplinePoint(0.30, 0.5 - 0.20),
                                            SplinePoint(0.24, 0.5 - 0.17), SplinePoint(0.28, 0.5 - 0.08, sharp: true)]), .secondary, color: wingColor(b),
                                                tag: "wing")
        b.engines(at: 0.08, spread: 0.035, radius: 0.026)
        // The lantern: a lit band around the tail, and plumes of the same warm light.
        b.glow = ArtRGB(0.78, 0.95, 0.50)
        b.lantern = 0.115...0.150
        b.deck = 0.76...0.88
        b.cabinRange = 0.56...0.74
        b.cargoRange = 0.30...0.56
        b.tankStart = 0.19
        b.weaponMounts = [CGPoint(x: 0.66, y: 0.5 - 0.085), CGPoint(x: 0.66, y: 0.5 + 0.085)]
        b.emitterRange = 0.34...0.58
        b.gadgetRange = 0.19...0.30
        b.radiatorRange = 0.18...0.26
    }

    // MARK: Mosquito — a needle nose and long, narrow wings

    static func mosquito(_ b: inout ShipBuilder) {
        let g = b.frame.girth
        b.plan = HullPlan([(0.07, 0.028), (0.16, 0.050), (0.36, 0.060 + 0.02 * g), (0.52, 0.050), (0.64, 0.028), (0.80, 0.012), (0.95, 0.003)])
        b.addPair(ShipBuilder.surface(rootFront: 0.44, rootBack: 0.30, tipFront: 0.20, tipBack: 0.15, span: 0.265, rootY: 0.04), .secondary,
            color: wingColor(b),
                  tag: "wing")
        b.addPair(ShipBuilder.surface(rootFront: 0.20, rootBack: 0.10, tipFront: 0.09, tipBack: 0.06, span: 0.10, rootY: 0.03), .secondary, color: wingColor(b),
                  tag: "tailplane")
        b.engines(at: 0.07, spread: 0.022, radius: 0.022)
        b.deck = 0.48...0.60
        b.cabinRange = 0.30...0.46
        b.cargoRange = 0.16...0.40
        b.tankStart = 0.11
        b.weaponMounts = [CGPoint(x: 0.60, y: 0.5 - 0.034), CGPoint(x: 0.60, y: 0.5 + 0.034), CGPoint(x: 0.40, y: 0.5 - 0.10), CGPoint(x: 0.40, y: 0.5 + 0.10)]
        b.emitterRange = 0.22...0.44
        b.gadgetRange = 0.11...0.22
        b.radiatorRange = 0.10...0.18
        b.seams = [0.20, 0.34, 0.47, 0.62, 0.72]
    }

    // MARK: Bumblebee — a round, banded body with short wings

    static func bumblebee(_ b: inout ShipBuilder) {
        let g = b.frame.girth
        b.plan = HullPlan([(0.06, 0.050), (0.14, 0.110), (0.30, 0.145), (0.50, 0.150 + 0.03 * g), (0.70, 0.125), (0.84, 0.070), (0.92, 0.030), (0.95, 0)])
        b.addPair(ArtGeometry.closedSpline([SplinePoint(0.58, 0.5 - 0.12, sharp: true), SplinePoint(0.52, 0.5 - 0.215), SplinePoint(0.42, 0.5 - 0.245),
                                            SplinePoint(0.34, 0.5 - 0.215), SplinePoint(0.36, 0.5 - 0.12, sharp: true)]), .secondary, color: wingColor(b),
                                                tag: "wing")
        b.engines(at: 0.06, spread: 0.045, radius: 0.028)
        b.bands = [0.20, 0.34]
        b.deck = 0.80...0.90
        b.cabinRange = 0.58...0.78
        b.cargoRange = 0.22...0.56
        b.tankStart = 0.12
        b.weaponMounts = [CGPoint(x: 0.70, y: 0.5 - 0.125), CGPoint(x: 0.70, y: 0.5 + 0.125), CGPoint(x: 0.82, y: 0.5 - 0.06)]
        b.emitterRange = 0.30...0.60
        b.gadgetRange = 0.10...0.26
        b.radiatorRange = 0.09...0.20
    }

    // MARK: Beetle — a broad carapace with a wing-case seam and a small head

    static func beetle(_ b: inout ShipBuilder) {
        let g = b.frame.girth
        b.plan = HullPlan([(0.06, 0.080), (0.12, 0.150), (0.28, 0.185 + 0.03 * g), (0.50, 0.195 + 0.04 * g), (0.68, 0.175 + 0.02 * g), (0.76, 0.130),
            (0.80, 0.078),
                           (0.88, 0.062), (0.93, 0.030), (0.95, 0)])
        b.addPair(pod(0.10, 0.34, y: 0.215 + 0.03 * g, radius: 0.026), .secondary, color: podColor(b), tag: "pod")
        b.engines(at: 0.06, spread: 0.085, radius: 0.030)
        b.centreSeam = true
        b.seams = [0.20, 0.36, 0.52, 0.68, 0.78]
        b.deck = 0.84...0.92
        b.cabinRange = 0.62...0.80
        b.cargoRange = 0.16...0.64
        b.tankStart = 0.10
        b.weaponMounts = [CGPoint(x: 0.78, y: 0.5 - 0.11), CGPoint(x: 0.78, y: 0.5 + 0.11)]
        b.emitterRange = 0.30...0.60
        b.gadgetRange = 0.09...0.22
        b.radiatorRange = 0.08...0.20
    }

    // MARK: Hornet — a narrow-waisted gunship with delta wings

    static func hornet(_ b: inout ShipBuilder) {
        let g = b.frame.girth
        b.plan = HullPlan([(0.06, 0.040), (0.14, 0.075), (0.28, 0.085), (0.38, 0.060), (0.44, 0.036), (0.52, 0.070), (0.62, 0.088 + 0.02 * g), (0.76, 0.070),
                           (0.88, 0.035), (0.95, 0)])
        b.addPair(ShipBuilder.surface(rootFront: 0.68, rootBack: 0.46, tipFront: 0.42, tipBack: 0.35, span: 0.255, rootY: 0.05), .secondary,
            color: wingColor(b),
                  tag: "wing")
        b.addPair(ShipBuilder.surface(rootFront: 0.22, rootBack: 0.10, tipFront: 0.11, tipBack: 0.06, span: 0.135, rootY: 0.04), .secondary,
            color: wingColor(b),
                  tag: "tailplane")
        b.engines(at: 0.06, spread: 0.032, radius: 0.026)
        b.deck = 0.78...0.89
        b.cabinRange = 0.56...0.76
        b.cargoRange = 0.12...0.36
        b.tankStart = 0.12
        b.weaponMounts = [CGPoint(x: 0.74, y: 0.5 - 0.062), CGPoint(x: 0.74, y: 0.5 + 0.062), CGPoint(x: 0.56, y: 0.5 - 0.135), CGPoint(x: 0.56,
            y: 0.5 + 0.135)]
        b.emitterRange = 0.50...0.72
        b.gadgetRange = 0.12...0.30
        b.radiatorRange = 0.10...0.24
        b.seams = [0.16, 0.30, 0.44, 0.56, 0.70]
    }

    // MARK: Grasshopper — a long body with hind-leg engine nacelles

    static func grasshopper(_ b: inout ShipBuilder) {
        let g = b.frame.girth
        b.plan = HullPlan([(0.06, 0.035), (0.16, 0.060), (0.36, 0.072), (0.60, 0.078 + 0.03 * g), (0.80, 0.055), (0.90, 0.025), (0.95, 0)])
        b.addPair(strut([(0.30, 0.5 - 0.165), (0.47, 0.5 - 0.200), (0.55, 0.5 - 0.07)], width: 0.016), .dark, color: ShipBuilder.steel, tag: "strut")
        b.addPair(pod(0.07, 0.42, y: 0.175, radius: 0.030), .secondary, color: podColor(b), tag: "nacelle")
        b.addPair(ShipBuilder.surface(rootFront: 0.78, rootBack: 0.68, tipFront: 0.71, tipBack: 0.66, span: 0.125, rootY: 0.04), .secondary,
            color: wingColor(b),
                  tag: "foreplane")
        b.glows += [EngineMount(x: 0.075, yOffset: -0.175, radius: 0.026), EngineMount(x: 0.075, yOffset: 0.175, radius: 0.026)]
        if b.frame.nozzles >= 3 { b.glows.append(EngineMount(x: 0.06, radius: 0.022)) }
        b.deck = 0.78...0.89
        b.cabinRange = 0.56...0.76
        b.cargoRange = 0.24...0.56
        b.tankStart = 0.10
        b.weaponMounts = [CGPoint(x: 0.72, y: 0.5 - 0.07), CGPoint(x: 0.72, y: 0.5 + 0.07), CGPoint(x: 0.40, y: 0.5 - 0.20)]
        b.emitterRange = 0.34...0.58
        b.gadgetRange = 0.10...0.28
        b.radiatorRange = 0.09...0.20
    }

    // MARK: Termite — a heavy freighter in segments

    static func termite(_ b: inout ShipBuilder) {
        let k = 1 + 0.08 * b.frame.girth
        b.plan = HullPlan([(0.05, 0.090), (0.10, 0.150 * k), (0.20, 0.165 * k), (0.265, 0.130 * k), (0.33, 0.180 * k), (0.43, 0.185 * k), (0.49, 0.145 * k),
                           (0.56, 0.185 * k), (0.66, 0.180 * k), (0.72, 0.130 * k), (0.79, 0.120), (0.88, 0.065), (0.93, 0.030), (0.95, 0)])
        b.addPair(ShipBuilder.surface(rootFront: 0.17, rootBack: 0.08, tipFront: 0.09, tipBack: 0.05, span: 0.235, rootY: 0.13), .secondary,
            color: wingColor(b),
                  tag: "tailplane")
        b.engines(at: 0.05, spread: 0.095, radius: 0.032)
        b.seams = [0.265, 0.49, 0.72]
        b.deck = 0.84...0.92
        b.cabinRange = 0.74...0.84
        b.cargoRange = 0.09...0.70
        b.tankStart = 0.09
        b.weaponMounts = [CGPoint(x: 0.80, y: 0.5 - 0.105), CGPoint(x: 0.80, y: 0.5 + 0.105)]
        b.emitterRange = 0.20...0.66
        b.gadgetRange = 0.08...0.20
        b.radiatorRange = 0.08...0.22
    }

    // MARK: Wasp — a sleek, narrow-waisted warship with a tail spike and forward-swept wings

    static func wasp(_ b: inout ShipBuilder) {
        let g = b.frame.girth
        b.plan = HullPlan([(0.02, 0.005), (0.07, 0.018), (0.16, 0.052), (0.30, 0.070), (0.40, 0.046), (0.45, 0.032), (0.54, 0.075), (0.66, 0.090 + 0.02 * g),
                           (0.80, 0.065), (0.90, 0.030), (0.95, 0)])
        b.addPair(ShipBuilder.surface(rootFront: 0.64, rootBack: 0.46, tipFront: 0.72, tipBack: 0.64, span: 0.255, rootY: 0.05), .secondary,
            color: wingColor(b),
                  tag: "wing")
        b.addPair(pod(0.11, 0.34, y: 0.092, radius: 0.026), .secondary, color: podColor(b), tag: "nacelle")
        b.glows += [EngineMount(x: 0.115, yOffset: -0.092, radius: 0.026), EngineMount(x: 0.115, yOffset: 0.092, radius: 0.026)]
        if b.frame.nozzles >= 3 { b.glows.append(EngineMount(x: 0.16, radius: 0.016)) }
        b.deck = 0.80...0.90
        b.cabinRange = 0.58...0.78
        b.cargoRange = 0.16...0.38
        b.tankStart = 0.16
        b.weaponMounts = [CGPoint(x: 0.76, y: 0.5 - 0.058), CGPoint(x: 0.76, y: 0.5 + 0.058), CGPoint(x: 0.66, y: 0.5 - 0.16), CGPoint(x: 0.66, y: 0.5 + 0.16)]
        b.emitterRange = 0.52...0.74
        b.gadgetRange = 0.16...0.34
        b.radiatorRange = 0.14...0.26
        b.seams = [0.16, 0.30, 0.45, 0.58, 0.72]
    }

    // MARK: Scorpion — the kidnappers' warship: two forward claws and a long segmented tail

    static func scorpion(_ b: inout ShipBuilder) {
        let g = b.frame.girth
        b.plan = HullPlan([(0.04, 0.012), (0.12, 0.026), (0.20, 0.022), (0.28, 0.038), (0.34, 0.030), (0.44, 0.085), (0.58, 0.105 + 0.02 * g), (0.72, 0.085),
                           (0.84, 0.040), (0.92, 0.012), (0.95, 0)])
        // The claws: two heavy booms that reach forward past the nose.
        b.addPair(ArtGeometry.closedSpline([SplinePoint(0.56, 0.5 - 0.10, sharp: true), SplinePoint(0.72, 0.5 - 0.20), SplinePoint(0.90, 0.5 - 0.19),
                                            SplinePoint(0.96, 0.5 - 0.12), SplinePoint(0.90, 0.5 - 0.14), SplinePoint(0.74, 0.5 - 0.15),
                                            SplinePoint(0.64, 0.5 - 0.08, sharp: true)]), .secondary, color: wingColor(b), tag: "claw")
        b.addPair(pod(0.30, 0.52, y: 0.125, radius: 0.028), .secondary, color: podColor(b), tag: "nacelle")
        b.glows += [EngineMount(x: 0.305, yOffset: -0.125, radius: 0.026), EngineMount(x: 0.305, yOffset: 0.125, radius: 0.026)]
        if b.frame.nozzles >= 3 { b.glows.append(EngineMount(x: 0.05, radius: 0.012)) }
        b.seams = [0.12, 0.20, 0.28, 0.36, 0.50, 0.64, 0.78]
        b.deck = 0.76...0.86
        b.cabinRange = 0.54...0.74
        b.cargoRange = 0.42...0.60
        b.tankStart = 0.40
        b.weaponMounts = [CGPoint(x: 0.90, y: 0.5 - 0.165), CGPoint(x: 0.90, y: 0.5 + 0.165), CGPoint(x: 0.74, y: 0.5 - 0.06), CGPoint(x: 0.74, y: 0.5 + 0.06)]
        b.emitterRange = 0.46...0.70
        b.gadgetRange = 0.36...0.48
        b.radiatorRange = 0.36...0.46
    }
}
