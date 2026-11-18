// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// ART-009: what a hull is built for, chosen from stat ratios.
public enum ShipArchetype: Int, CaseIterable, Sendable, Hashable {
    case hauler = 0, courier, interceptor, gunship, cruiser

    /// ART-009: the archetype rules, first match wins.
    public static func of(_ s: ShipArtStats) -> ShipArchetype {
        if s.cargoBays >= 40, s.weaponSlots <= 1 { return .hauler }
        if s.weaponSlots >= 3 { return .gunship }
        if s.sizeClass <= 1, s.weaponSlots >= 2 { return .interceptor }
        if s.sizeClass >= 3 { return .cruiser }
        return .courier
    }
}

/// ART-009…012: builds a ship design from its statistics. Statistics set the continuous parameters (beam, cargo modules,
/// hardpoints, plating, engines, sleekness) and the archetype; `variant` selects among planform, wing and nacelle families,
/// so ships with nearly equal statistics still differ. Nothing here knows a ship's name.
public enum ShipHullGenerator {
    private typealias PP = ProfilePoint

    public static let noseX = 0.93
    public static let tailX = 0.12
    static var length: Double { noseX - tailX }

    /// The families a variant picks from.
    public struct Families: Sendable, Hashable {
        public var planform: Int
        public var wing: Int
        public var nacelle: Int
        public var livery: Int

        public init(variant: UInt64) {
            planform = Int(variant % 4)
            wing = Int((variant >> 8) % 4)
            nacelle = Int((variant >> 16) % 3)
            livery = Int((variant >> 24) % 6)
        }
    }

    /// ART-009: 0 (cheap, low tech: blunt and boxy) … 1 (expensive, high tech: pointed and smooth).
    public static func sleekness(_ s: ShipArtStats) -> Double {
        min(1, max(0, 0.08 + 0.13 * Double(s.priceTier) + 0.04 * Double(s.techTier)))
    }

    /// ART-068 (ships): the armour level from the hull strength: 0 below 60, then one level per step.
    public static func plating(_ s: ShipArtStats) -> Int {
        [60, 120, 180, 260, 360].filter { s.hullStrength >= $0 }.count
    }

    /// ART-010: the largest haulers (55 bays and more) carry their containers outside a narrow spine; smaller ones have a
    /// boxy integral hold.
    public static func isSpineFreighter(_ s: ShipArtStats) -> Bool { ShipArchetype.of(s) == .hauler && s.cargoBays >= 55 }
    /// How far a spine freighter's containers reach from the centreline: a little past where an integral hold of the
    /// same beam would end, so a bigger load never looks smaller.
    public static func spineCargoReach(beam: Double) -> Double { min(0.44, beam + 0.056) }

    /// The number of cargo modules drawn: one per 10 bays, at most 6.
    public static func cargoModules(_ s: ShipArtStats) -> Int { min(6, max(0, s.cargoBays) / 10) }

    /// The widest half width of the hull.
    public static func beam(_ s: ShipArtStats, archetype: ShipArchetype) -> Double {
        let base: Double = switch archetype {
        case .hauler: 0.150
        case .courier: 0.100
        case .interceptor: 0.068
        case .gunship: 0.112
        case .cruiser: 0.105
        }
        let cargo = 0.0009 * Double(min(80, max(0, s.cargoBays)))
        // Larger hulls are relatively longer: the same length axis carries a narrower beam.
        return min(0.24, (base + cargo) * (1.08 - 0.22 * sleekness(s)) * (1.12 - 0.05 * Double(s.sizeClass)))
    }

    public static func make(_ s: ShipArtStats, variant: UInt64) -> ShipBlueprint {
        let archetype = ShipArchetype.of(s)
        let fam = Families(variant: variant)
        let sleek = sleekness(s)
        let beam = beam(s, archetype: archetype)
        let spine = isSpineFreighter(s)
        var bp = ShipBlueprint(hull: profile(archetype, planform: fam.planform, beam: beam, sleek: sleek, spine: spine),
                               livery: livery(archetype, fam.livery))
        if spine { bp.cargoReach = spineCargoReach(beam: beam) }
        bp.archetype = archetype
        bp.sleekness = sleek
        bp.plating = plating(s)
        bp.wings = wings(archetype, family: fam.wing, beam: beam, sleek: sleek, s: s)
        let engineLayout = engines(archetype, family: fam.nacelle, beam: beam, s: s, wings: bp.wings)
        bp.nacelles = engineLayout.nacelles
        bp.engines = engineLayout.engines
        bp.cockpit = cockpit(archetype, s: s, bp: bp)
        var features: [ShipFeature] = [.panelLines(2 + min(4, s.sizeClass) + min(2, s.gadgetSlots))]
        let modules = cargoModules(s)
        if modules > 0 { features.append(.cargoModules(modules)) }
        if bp.plating > 0 { features.append(.armour(bp.plating)) }
        let weapons = s.weapons ?? Array(repeating: -1, count: max(0, s.weaponSlots))
        if !weapons.isEmpty || s.weaponSlots > 0 { features.append(.hardpoints(slots: max(s.weaponSlots, weapons.count), installed: weapons)) }
        let shields = s.shields?.count ?? s.shieldSlots
        if s.shieldSlots > 0 || shields > 0 { features.append(.shieldEmitters(slots: max(s.shieldSlots, shields), installed: shields)) }
        let gadgets = s.gadgets?.count ?? s.gadgetSlots
        if gadgets > 0 { features.append(.sensors(min(4, gadgets))) }
        if s.fuelTanks >= 16 { features.append(.fuelTanks(min(3, (s.fuelTanks - 12) / 4))) }
        features.append(.liveryBands(1 + fam.livery % 2))
        features.append(.navigationLights)
        bp.features = features
        return bp
    }

    // MARK: Hull profile

    /// Relative stations from the nose (0) to the tail (1) with a relative half width (0…1) and a corner flag.
    private static func planformStations(_ archetype: ShipArchetype, planform: Int, sleek: Double,
                                         spine: Bool) -> [(t: Double, w: Double, sharp: Bool)] {
        // A blunt nose for cheap hulls, a point for sleek ones.
        let nose = max(0, 0.34 - 0.5 * sleek)
        let boxy = sleek < 0.45
        switch archetype {
        case .hauler where spine:
            // A cab, a long narrow spine for the containers and an engine block.
            return [(0, nose * 0.8, true), (0.05, 0.56, boxy), (0.14, 0.56, true), (0.17, 0.3, true), (0.8, 0.3, true), (0.83, 0.9, true),
                    (1, planform >= 2 ? 0.74 : 0.9, true)]
        case .hauler:
            // A small cab, a neck and a long cargo body.
            let cab = 0.42 + 0.1 * Double(planform % 2)
            return [(0, nose * 0.8, true), (0.05, cab, boxy), (0.15, cab, true), (0.18, 0.3, true), (0.23, 0.3, true), (0.26, 1, true),
                    (0.9, 1, true), (0.94, planform >= 2 ? 0.72 : 0.9, true), (1, planform >= 2 ? 0.72 : 0.9, true)]
        case .courier, .cruiser:
            switch planform {
            case 0: return [(0, nose, nose > 0), (0.16, 0.42, false), (0.45, 0.8, false), (0.78, 1, false), (0.94, 0.86, boxy), (1, 0.6, true)]
            case 1: return [(0, nose, nose > 0), (0.2, 0.62, false), (0.5, 1, false), (0.8, 0.82, false), (1, 0.5, true)]
            case 2: return [(0, max(nose, 0.2), true), (0.12, 0.6, boxy), (0.36, 1, boxy), (0.88, 1, boxy), (1, 0.8, true)]
            default: return [(0, nose, nose > 0), (0.16, 0.8, false), (0.4, 0.56, false), (0.68, 1, false), (0.92, 0.9, boxy), (1, 0.62, true)]
            }
        case .interceptor:
            switch planform {
            case 0, 2: return [(0, 0, true), (0.3, 0.5, false), (0.62, 1, false), (0.9, 0.9, false), (1, 0.55, true)]
            default: return [(0, 0, true), (0.22, 0.7, false), (0.5, 1, false), (0.82, 0.7, false), (1, 0.45, true)]
            }
        case .gunship:
            switch planform {
            case 0, 1: return [(0, nose * 0.6, nose > 0), (0.14, 0.5, false), (0.34, 1, boxy), (0.6, 0.92, false), (0.85, 0.7, false), (1, 0.55, true)]
            default: return [(0, max(nose, 0.16), true), (0.1, 0.7, true), (0.3, 1, boxy), (0.74, 1, boxy), (0.82, 0.74, true), (1, 0.74, true)]
            }
        }
    }

    static func profile(_ archetype: ShipArchetype, planform: Int, beam: Double, sleek: Double, spine: Bool = false) -> [ProfilePoint] {
        planformStations(archetype, planform: planform, sleek: sleek, spine: spine).map { PP(noseX - $0.t * length, $0.w * beam, sharp: $0.sharp) }
    }

    // MARK: Wings

    static func wings(_ archetype: ShipArchetype, family: Int, beam: Double, sleek: Double, s: ShipArtStats) -> [WingPair] {
        let room = 0.47 - beam // the span left to the edge of the unit square
        func span(_ f: Double) -> Double { min(room, beam * 0.4 + f) }
        switch archetype {
        case .hauler:
            // Stabilisers only: a freighter has no need of wings.
            return family % 2 == 0 ? [] : [WingPair(rootX: tailX + 0.16, rootChord: 0.12, span: span(0.03), sweep: 0.04, tipChord: 0.06)]
        case .courier:
            switch family {
            case 0: return [WingPair(rootX: tailX + 0.34, rootChord: 0.26, span: span(0.13), sweep: 0.16, tipChord: 0.06)]
            case 1: return [WingPair(rootX: tailX + 0.22, rootChord: 0.16, span: span(0.09), sweep: 0.07, tipChord: 0.08)]
            case 2: return [WingPair(rootX: tailX + 0.5, rootChord: 0.34, span: span(0.17), sweep: 0.3, tipChord: 0.03)]
            default: return [WingPair(rootX: tailX + 0.42, rootChord: 0.14, span: span(0.12), sweep: 0.02, tipChord: 0.1)]
            }
        case .interceptor:
            switch family {
            case 0, 2: return [WingPair(rootX: tailX + 0.5, rootChord: 0.4, span: span(0.24), sweep: 0.36, tipChord: 0.04)]
            default: return [WingPair(rootX: tailX + 0.34, rootChord: 0.2, span: span(0.27), sweep: -0.08, tipChord: 0.07)]
            }
        case .gunship:
            switch family {
            case 0, 3: return [WingPair(rootX: tailX + 0.46, rootChord: 0.26, span: span(0.2), sweep: 0.2, tipChord: 0.1)]
            case 1: return [WingPair(rootX: tailX + 0.36, rootChord: 0.2, span: span(0.22), sweep: -0.1, tipChord: 0.1)]
            default: return [WingPair(rootX: tailX + 0.56, rootChord: 0.42, span: span(0.16), sweep: 0.3, tipChord: 0.14)]
            }
        case .cruiser:
            switch family {
            case 0, 2: return [WingPair(rootX: tailX + 0.44, rootChord: 0.34, span: span(0.17), sweep: 0.26, tipChord: 0.08)]
            default:
                return [WingPair(rootX: tailX + 0.3, rootChord: 0.2, span: span(0.15), sweep: 0.1, tipChord: 0.08),
                        WingPair(rootX: noseX - 0.2, rootChord: 0.1, span: span(0.05), sweep: 0.05, tipChord: 0.04)]
            }
        }
    }

    // MARK: Engines

    /// More and larger engines for larger hulls; the nacelle family moves them out of the hull.
    static func engines(_ archetype: ShipArchetype, family: Int, beam: Double, s: ShipArtStats,
                        wings: [WingPair]) -> (nacelles: [Nacelle], engines: [EngineMount]) {
        let count = 1 + (s.sizeClass >= 2 ? 1 : 0) + (s.sizeClass >= 4 ? 1 : 0)
        let radius = min(beam * 0.42, 0.026 + 0.004 * Double(s.sizeClass) + (archetype == .interceptor ? 0.006 : 0))
        let x = tailX + 0.012
        var nacelles: [Nacelle] = []
        var mounts: [EngineMount] = []
        let outboard = min(0.44, beam + radius + 0.012)
        switch (family, count) {
        case (0, 1): mounts = [EngineMount(x: x, radius: radius * 1.15)]
        case (0, 2): mounts = [EngineMount(x: x, yOffset: beam * 0.42, radius: radius)]
        case (0, _): mounts = [EngineMount(x: x, radius: radius), EngineMount(x: x, yOffset: beam * 0.62, radius: radius * 0.85)]
        case (1, _):
            // Twin nacelles hugging the aft hull, plus a centre engine on large hulls.
            nacelles = [Nacelle(x: tailX + 0.26, yOffset: outboard, length: 0.3, radius: radius * 1.05)]
            mounts = [EngineMount(x: tailX - 0.02, yOffset: outboard, radius: radius)]
            if count >= 3 { mounts.append(EngineMount(x: x, radius: radius)) }
        default:
            // Outrigger pods at the wing tips (or on short pylons when there are no wings).
            let reach = min(0.44, max(outboard + 0.03, beam + (wings.first?.span ?? 0.06) * 0.8))
            nacelles = [Nacelle(x: tailX + 0.3, yOffset: reach, length: 0.24, radius: radius * 0.95)]
            mounts = [EngineMount(x: tailX + 0.08, yOffset: reach, radius: radius * 0.9)]
            if count >= 2 { mounts.append(EngineMount(x: x, radius: radius)) }
        }
        return (nacelles, mounts)
    }

    // MARK: Cockpit and livery

    static func cockpit(_ archetype: ShipArchetype, s: ShipArtStats, bp: ShipBlueprint) -> Cockpit {
        let crew = Double(min(5, max(0, s.crewQuarters)))
        let length = 0.07 + 0.018 * crew
        let x = archetype == .hauler ? noseX - 0.03 : noseX - 0.1 - 0.02 * Double(min(3, s.sizeClass))
        let width = min(0.11, max(0.03, bp.halfWidth(at: x - length / 2) * 1.1))
        // Small craft have a canopy; larger ones a bridge with a window band.
        let style: Cockpit.Style = s.sizeClass <= 1 && archetype != .hauler ? .bubble : .slit
        return Cockpit(x: x, length: style == .slit ? max(0.035, length * 0.5) : length, width: width, style: style)
    }

    static func livery(_ archetype: ShipArchetype, _ index: Int) -> Livery {
        let sets: [[Livery]] = [
            // hauler: workaday paint
            [Livery(primary: .cream, secondary: .rust, accent: .amber), Livery(primary: .sand, secondary: .landBrown, accent: .ivory),
             Livery(primary: .hullGrey, secondary: .rust, accent: .amber)],
            // courier
            [Livery(primary: .ivory, secondary: .slateBlue, accent: .danger), Livery(primary: .hullGrey, secondary: .slate, accent: .brass),
             Livery(primary: .slateBlue, secondary: .slate, accent: .ivory)],
            // interceptor
            [Livery(primary: .steel, secondary: .nightBlack, accent: .danger), Livery(primary: .ivory, secondary: .slate, accent: .iridescentBlue),
             Livery(primary: .olive, secondary: .nightBlack, accent: .amber)],
            // gunship
            [Livery(primary: .slate, secondary: .nightBlack, accent: .amber), Livery(primary: .olive, secondary: .nightBlack, accent: .ivory),
             Livery(primary: .steel, secondary: .crimson, accent: .ivory)],
            // cruiser
            [Livery(primary: .ivory, secondary: .slateBlue, accent: .brass), Livery(primary: .hullGrey, secondary: .crimson, accent: .ivory),
             Livery(primary: .steel, secondary: .teal, accent: .ivory)]
        ]
        let set = sets[archetype.rawValue]
        return set[index % set.count]
    }
}
