// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// ART-011: the designs that are not generated from an archetype: the organic space monster, the bottle, and the four
/// quest warships. The warships are built machines with their own hull forms; their fittings still come from statistics.
public enum ShipSpecials {
    private typealias PP = ProfilePoint

    public static func blueprint(_ kind: ShipArtKind, stats s: ShipArtStats) -> ShipBlueprint? {
        switch kind {
        case .spaceMonster: return spaceMonster
        case .bottle: return bottle
        case .dragonfly: return fitted(ringScout, s)
        case .mantis: return fitted(swallowtail, s)
        case .scarab: return fitted(armouredDisc, s)
        case .scorpion: return fitted(dreadnought, s)
        case .flea, .gnat, .firefly, .mosquito, .bumblebee, .beetle, .hornet, .grasshopper, .termite, .wasp, .custom: return nil
        }
    }

    /// Adds the fittings the statistics call for to a special hull.
    static func fitted(_ base: ShipBlueprint, _ s: ShipArtStats) -> ShipBlueprint {
        var bp = base
        bp.plating = max(bp.plating, ShipHullGenerator.plating(s))
        let weapons = s.weapons ?? Array(repeating: -1, count: s.weaponSlots)
        if s.weaponSlots > 0 { bp.features.append(.hardpoints(slots: max(s.weaponSlots, weapons.count), installed: weapons)) }
        if s.shieldSlots > 0 { bp.features.append(.shieldEmitters(slots: s.shieldSlots, installed: s.shields?.count ?? s.shieldSlots)) }
        let gadgets = s.gadgets?.count ?? s.gadgetSlots
        if gadgets > 0 { bp.features.append(.sensors(min(4, gadgets))) }
        bp.features.append(.navigationLights)
        return bp
    }

    static let spaceMonster = ShipBlueprint(
        hull: [PP(0.86, 0), PP(0.6, 0.24), PP(0.38, 0)],
        features: [.tentacles(6), .eyes(3)],
        livery: Livery(primary: .violet, secondary: .teal, accent: .alienGlow, glow: .bioGlow),
        symmetric: false, organicSeed: ArtSeed.kind(.spaceMonster))

    static let bottle = ShipBlueprint(
        hull: [PP(0.9, 0.045, sharp: true), PP(0.76, 0.05), PP(0.68, 0.09), PP(0.6, 0.17), PP(0.5, 0.19), PP(0.18, 0.19), PP(0.12, 0.17),
               PP(0.1, 0.1, sharp: true)],
        features: [.bottle, .cork, .scroll],
        livery: Livery(primary: .glassTint, secondary: .glassTint, accent: .parchment))

    /// A needle-hulled alien scout that carries its field ring around the hull.
    static let ringScout = ShipBlueprint(
        hull: [PP(0.93, 0, sharp: true), PP(0.8, 0.034), PP(0.52, 0.046), PP(0.24, 0.034), PP(0.12, 0.022, sharp: true)],
        engines: [EngineMount(x: 0.13, radius: 0.022)],
        cockpit: Cockpit(x: 0.84, length: 0.09, width: 0.05, style: .bubble),
        features: [.panelLines(3), .shieldRing],
        livery: Livery(primary: .iridescentGreen, secondary: .iridescentBlue, accent: .teal, glow: .alienGlow))

    /// A broad alien delta with a notched stern and glowing bands.
    static let swallowtail = ShipBlueprint(
        hull: [PP(0.93, 0, sharp: true), PP(0.74, 0.085), PP(0.5, 0.2), PP(0.18, 0.31, sharp: true), PP(0.27, 0.13), PP(0.14, 0.075, sharp: true)],
        engines: [EngineMount(x: 0.15, yOffset: 0.04, radius: 0.03)],
        cockpit: Cockpit(x: 0.78, length: 0.04, width: 0.07, style: .slit),
        features: [.panelLines(4), .liveryBands(3)],
        livery: Livery(primary: .teal, secondary: .violet, accent: .alienGlow, glow: .alienGlow))

    /// A round, heavily plated hull.
    static let armouredDisc: ShipBlueprint = {
        var bp = ShipBlueprint(
            hull: [PP(0.86, 0), PP(0.82, 0.16), PP(0.7, 0.28), PP(0.52, 0.32), PP(0.34, 0.28), PP(0.22, 0.16), PP(0.18, 0)],
            engines: [EngineMount(x: 0.2, yOffset: 0.09, radius: 0.034)],
            cockpit: Cockpit(x: 0.78, length: 0.04, width: 0.1, style: .slit),
            features: [.panelLines(5), .armour(5), .liveryBands(1)],
            livery: Livery(primary: .nightBlack, secondary: .slate, accent: .iridescentBlue))
        bp.plating = 5
        return bp
    }()

    /// A long capital ship with a raised keel and gun sponsons.
    static let dreadnought = ShipBlueprint(
        hull: [PP(0.93, 0, sharp: true), PP(0.84, 0.055), PP(0.62, 0.1, sharp: true), PP(0.3, 0.1, sharp: true), PP(0.18, 0.075, sharp: true),
               PP(0.12, 0.075, sharp: true)],
        engines: [EngineMount(x: 0.13, radius: 0.03), EngineMount(x: 0.13, yOffset: 0.05, radius: 0.026)],
        cockpit: Cockpit(x: 0.8, length: 0.04, width: 0.07, style: .slit),
        features: [.panelLines(6), .spine(5), .broadsides(3), .armour(3)],
        livery: Livery(primary: .crimson, secondary: .nightBlack, accent: .nightBlack))
}
