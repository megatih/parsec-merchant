// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// ART-010…012: one blueprint per ship kind. Insect motifs are abstract and drawn from the shape grammar only.
public enum ShipBlueprints {
    private typealias PP = ProfilePoint

    /// The blueprint of a non-custom kind (custom kinds use `custom(_:)`).
    public static func blueprint(_ kind: ShipArtKind) -> ShipBlueprint {
        if kind.isBuyable { return standard[kind.rawValue] }
        switch kind {
        case .spaceMonster: return spaceMonster
        case .dragonfly: return dragonfly
        case .mantis: return mantis
        case .scarab: return scarab
        case .bottle: return bottle
        case .scorpion: return scorpion
        default: return custom(.standard)
        }
    }

    /// ART-010: the ten buyable ships in `ShipArtKind` order.
    public static let standard: [ShipBlueprint] = [flea, gnat, firefly, mosquito, bumblebee, beetle, hornet, grasshopper, termite, wasp]

    /// ART-011: the six special ships.
    public static let special: [ShipArtKind: ShipBlueprint] = [.spaceMonster: spaceMonster, .dragonfly: dragonfly, .mantis: mantis,
                                                               .scarab: scarab, .bottle: bottle, .scorpion: scorpion]

    static let flea = ShipBlueprint(
        hull: [PP(0.9, 0), PP(0.84, 0.13), PP(0.7, 0.19), PP(0.52, 0.17), PP(0.36, 0.1), PP(0.2, 0, sharp: true)],
        engines: [EngineMount(x: 0.22, radius: 0.05)],
        cockpit: Cockpit(x: 0.86, length: 0.16, width: 0.14, style: .bubble),
        features: [.skids],
        livery: Livery(primary: .slateBlue, secondary: .hullGrey, accent: .ivory))

    static let gnat = ShipBlueprint(
        hull: [PP(0.86, 0, sharp: true), PP(0.74, 0.05), PP(0.5, 0.07), PP(0.24, 0.065), PP(0.16, 0.045, sharp: true), PP(0.16, 0, sharp: true)],
        wings: [WingPair(rootX: 0.52, rootChord: 0.2, span: 0.2, sweep: 0.13, tipChord: 0.06)],
        engines: [EngineMount(x: 0.16, radius: 0.045)],
        cockpit: Cockpit(x: 0.74, length: 0.13, width: 0.07, style: .bubble),
        features: [.antennae],
        livery: Livery(primary: .brass, secondary: .slate, accent: .ivory))

    static let firefly = ShipBlueprint(
        hull: [PP(0.92, 0), PP(0.86, 0.065), PP(0.72, 0.075), PP(0.6, 0.07), PP(0.48, 0.14), PP(0.32, 0.2), PP(0.18, 0.15), PP(0.1, 0)],
        wings: [WingPair(rootX: 0.68, rootChord: 0.18, span: 0.2, sweep: 0.15, tipChord: 0.02)],
        cockpit: Cockpit(x: 0.88, length: 0.12, width: 0.07, style: .bubble),
        features: [.abdomenLight],
        livery: Livery(primary: .olive, secondary: .slate, accent: .yellowGreen, glow: .yellowGreen))

    static let mosquito = ShipBlueprint(
        hull: [PP(0.8, 0, sharp: true), PP(0.7, 0.032), PP(0.4, 0.042), PP(0.15, 0.03), PP(0.1, 0, sharp: true)],
        wings: [WingPair(rootX: 0.56, rootChord: 0.1, span: 0.46, sweep: 0, tipChord: 0.08)],
        engines: [EngineMount(x: 0.11, yOffset: 0.02, radius: 0.025)],
        cockpit: Cockpit(x: 0.72, length: 0.1, width: 0.05, style: .bubble),
        features: [.proboscis, .hardpoints(2)],
        livery: Livery(primary: .steel, secondary: .slate, accent: .danger))

    static let bumblebee = ShipBlueprint(
        hull: [PP(0.86, 0), PP(0.8, 0.14), PP(0.62, 0.21), PP(0.42, 0.21), PP(0.27, 0.15), PP(0.2, 0)],
        wings: [WingPair(rootX: 0.62, rootChord: 0.26, span: 0.4, sweep: 0.06, tipChord: 0.2, rounded: true)],
        engines: [EngineMount(x: 0.24, yOffset: 0.06, radius: 0.04)],
        cockpit: Cockpit(x: 0.82, length: 0.12, width: 0.12, style: .bubble),
        features: [.stripes(3)],
        livery: Livery(primary: .amber, secondary: .nightBlack, accent: .nightBlack))

    static let beetle = ShipBlueprint(
        hull: [PP(0.93, 0), PP(0.9, 0.06), PP(0.84, 0.08), PP(0.8, 0.13), PP(0.7, 0.24), PP(0.46, 0.27), PP(0.22, 0.24), PP(0.11, 0.12), PP(0.08, 0)],
        engines: [EngineMount(x: 0.1, yOffset: 0.05, radius: 0.03), EngineMount(x: 0.14, yOffset: 0.14, radius: 0.03)],
        cockpit: Cockpit(x: 0.92, length: 0.08, width: 0.08, style: .bubble),
        features: [.elytraSeam],
        livery: Livery(primary: .rust, secondary: .cream, accent: .cream))

    static let hornet = ShipBlueprint(
        hull: [PP(0.95, 0, sharp: true), PP(0.62, 0.12), PP(0.38, 0.1), PP(0.3, 0.06), PP(0.2, 0.045), PP(0.16, 0, sharp: true)],
        wings: [WingPair(rootX: 0.42, rootChord: 0.15, span: 0.38, sweep: -0.14, tipChord: 0.08)],
        engines: [EngineMount(x: 0.2, radius: 0.04)],
        cockpit: Cockpit(x: 0.8, length: 0.14, width: 0.07, style: .bubble),
        features: [.stripes(2), .stinger, .hardpoints(3)],
        livery: Livery(primary: .amber, secondary: .nightBlack, accent: .nightBlack))

    static let grasshopper = ShipBlueprint(
        hull: [PP(0.95, 0), PP(0.9, 0.05), PP(0.7, 0.07), PP(0.32, 0.06), PP(0.12, 0.035), PP(0.07, 0)],
        wings: [WingPair(rootX: 0.86, rootChord: 0.06, span: 0.13, sweep: 0.03, tipChord: 0.03)],
        engines: [EngineMount(x: 0.08, radius: 0.03)],
        cockpit: Cockpit(x: 0.9, length: 0.2, width: 0.04, style: .slit),
        features: [.rearLegs],
        livery: Livery(primary: .iridescentGreen, secondary: .olive, accent: .yellowGreen))

    static let termite = ShipBlueprint(
        hull: [PP(0.86, 0.09, sharp: true), PP(0.66, 0.11, sharp: true), PP(0.645, 0.075, sharp: true), PP(0.625, 0.075, sharp: true),
               PP(0.61, 0.11, sharp: true), PP(0.4, 0.11, sharp: true), PP(0.385, 0.075, sharp: true), PP(0.365, 0.075, sharp: true),
               PP(0.35, 0.11, sharp: true), PP(0.14, 0.11, sharp: true), PP(0.12, 0.07, sharp: true)],
        engines: [EngineMount(x: 0.12, radius: 0.035), EngineMount(x: 0.13, yOffset: 0.065, radius: 0.03)],
        cockpit: Cockpit(x: 0.85, length: 0.06, width: 0.12, style: .slit),
        features: [.segments(3), .mandibles],
        livery: Livery(primary: .ivory, secondary: .landBrown, accent: .rust))

    static let wasp = ShipBlueprint(
        hull: [PP(0.92, 0, sharp: true), PP(0.85, 0.07), PP(0.7, 0.09), PP(0.6, 0.05), PP(0.55, 0.025), PP(0.5, 0.05), PP(0.38, 0.12),
               PP(0.22, 0.1), PP(0.15, 0.04), PP(0.14, 0)],
        wings: [WingPair(rootX: 0.64, rootChord: 0.16, span: 0.45, sweep: 0.26, tipChord: 0.07)],
        engines: [EngineMount(x: 0.16, yOffset: 0.045, radius: 0.045)],
        cockpit: Cockpit(x: 0.86, length: 0.13, width: 0.08, style: .bubble),
        features: [.waist, .stinger, .hardpoints(3)],
        livery: Livery(primary: .nightBlack, secondary: .nightBlack, accent: .amber))

    static let spaceMonster = ShipBlueprint(
        hull: [PP(0.86, 0), PP(0.6, 0.24), PP(0.38, 0)],
        features: [.tentacles(6), .eyes(3)],
        livery: Livery(primary: .violet, secondary: .teal, accent: .alienGlow, glow: .bioGlow),
        symmetric: false, organicSeed: ArtSeed.kind(.spaceMonster))

    static let dragonfly = ShipBlueprint(
        hull: [PP(0.93, 0), PP(0.89, 0.055), PP(0.76, 0.055), PP(0.69, 0.03), PP(0.12, 0.014), PP(0.05, 0)],
        wings: [WingPair(rootX: 0.76, rootChord: 0.07, span: 0.46, sweep: 0.03, tipChord: 0.065, count: 2, glass: true)],
        engines: [EngineMount(x: 0.07, radius: 0.02)],
        cockpit: Cockpit(x: 0.92, length: 0.08, width: 0.09, style: .compound),
        livery: Livery(primary: .iridescentGreen, secondary: .iridescentBlue, accent: .teal, glow: .alienGlow))

    static let mantis = ShipBlueprint(
        hull: [PP(0.95, 0, sharp: true), PP(0.88, 0.1, sharp: true), PP(0.84, 0.03), PP(0.7, 0.04), PP(0.55, 0.05), PP(0.35, 0.09),
               PP(0.15, 0.06), PP(0.07, 0)],
        engines: [EngineMount(x: 0.08, radius: 0.03)],
        cockpit: Cockpit(x: 0.93, length: 0.06, width: 0.1, style: .compound),
        features: [.raptorialArms],
        livery: Livery(primary: .teal, secondary: .violet, accent: .alienGlow, glow: .alienGlow))

    static let scarab = ShipBlueprint(
        hull: [PP(0.8, 0), PP(0.77, 0.19), PP(0.64, 0.33), PP(0.46, 0.37), PP(0.3, 0.33), PP(0.2, 0.2), PP(0.16, 0)],
        engines: [EngineMount(x: 0.18, yOffset: 0.08, radius: 0.035)],
        features: [.hornRam, .stripes(1)],
        livery: Livery(primary: .nightBlack, secondary: .slate, accent: .iridescentBlue))

    static let bottle = ShipBlueprint(
        hull: [PP(0.9, 0.045, sharp: true), PP(0.76, 0.05), PP(0.68, 0.09), PP(0.6, 0.17), PP(0.5, 0.19), PP(0.18, 0.19), PP(0.12, 0.17),
               PP(0.1, 0.1, sharp: true)],
        features: [.bottle, .cork, .scroll],
        livery: Livery(primary: .glassTint, secondary: .glassTint, accent: .parchment))

    static let scorpion = ShipBlueprint(
        hull: [PP(0.8, 0), PP(0.75, 0.08), PP(0.6, 0.12), PP(0.42, 0.11), PP(0.28, 0.06), PP(0.22, 0)],
        engines: [EngineMount(x: 0.24, yOffset: 0.04, radius: 0.035)],
        cockpit: Cockpit(x: 0.76, length: 0.1, width: 0.07, style: .bubble),
        features: [.pincers, .curledTail(5)],
        livery: Livery(primary: .crimson, secondary: .nightBlack, accent: .nightBlack),
        symmetric: false)

    /// ART-012: the neutral yard frame of a custom ship.
    static let yardFrame: [ProfilePoint] = [PP(0.88, 0.04, sharp: true), PP(0.74, 0.13, sharp: true), PP(0.32, 0.13, sharp: true),
                                            PP(0.2, 0.085, sharp: true), PP(0.2, 0, sharp: true)]

    /// ART-012: a modular, deterministic custom ship. Equal params give equal paths.
    public static func custom(_ c: CustomShipParams) -> ShipBlueprint {
        let baseHull = c.base.flatMap { $0.isBuyable ? standard[$0.rawValue].hull : nil } ?? yardFrame
        var bp = ShipBlueprint(hull: baseHull, livery: Livery(primary: .brass, secondary: .slate, accent: .ivory))
        let nose = bp.noseX, tail = bp.tailX
        let quarters = Double(min(5, max(0, c.crewQuarters)))
        let cockpitLength = 0.08 + 0.025 * quarters
        bp.cockpit = Cockpit(x: nose - 0.03, length: cockpitLength, width: min(0.1, 0.05 + bp.halfWidth(at: nose - 0.1) * 0.5),
                             style: .bubble)
        let engines = 1 + min(2, c.fuelTanks / 15)
        bp.engines = engines == 2 ? [EngineMount(x: tail + 0.01, yOffset: 0.04, radius: 0.035)]
            : [EngineMount(x: tail + 0.01, radius: 0.04)] + (engines == 3 ? [EngineMount(x: tail + 0.02, yOffset: 0.07, radius: 0.03)] : [])
        bp.features = [.hardpoints(min(6, max(0, c.weaponSlots))), .shieldFins(min(4, max(0, c.shieldSlots))),
                       .cargoPods(min(6, max(0, c.cargoBays) / 10)), .segments(1 + min(4, max(0, c.gadgetSlots)))]
        if c.hullStrength >= 150 { bp.features.append(.stripes(c.hullStrength >= 300 ? 2 : 1)) }
        return bp
    }
}
