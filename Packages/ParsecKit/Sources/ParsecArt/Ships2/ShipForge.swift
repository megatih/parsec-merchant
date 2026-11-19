// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// ART-SHIP-003: what the statistics ask for, the same for every class of ship.
public struct ShipFrame: Sendable, Hashable {
    public static let tailX = 0.05, noseX = 0.95

    /// Cargo bay doors on the hull: one per five bays, at most twelve.
    public var cargoDoors: Int
    /// 0…1: how far the cargo widens the mid-body.
    public var girth: Double
    /// Rows of cabin windows: one per crew quarter, at most three.
    public var cabins: Int
    /// Armour strakes along the flanks: one per 25 points of hull strength, at most twelve.
    public var plates: Int
    /// Pairs of radiator fins: one, plus one per shield slot (at most four).
    public var radiatorPairs: Int
    public var nozzles: Int
    /// The length of the dorsal propellant blisters, in unit space.
    public var tankLength: Double

    public static func doorCount(bays: Int) -> Int { bays <= 0 ? 0 : min(12, (bays + 4) / 5) }
    public static func plateCount(hull: Int) -> Int { min(12, max(1, hull / 25)) }
    public static func nozzleCount(sizeClass: Int) -> Int { [1, 1, 2, 2, 3, 3][min(5, max(0, sizeClass))] }

    public init(_ s: ShipArtStats) {
        cargoDoors = Self.doorCount(bays: s.cargoBays)
        girth = min(1, Double(s.cargoBays) / 60)
        cabins = min(3, max(1, s.crewQuarters))
        plates = Self.plateCount(hull: s.hullStrength)
        radiatorPairs = 1 + min(3, s.shieldSlots)
        nozzles = Self.nozzleCount(sizeClass: s.sizeClass)
        tankLength = 0.05 + 0.20 * Double(min(20, max(1, s.fuelTanks))) / 20
    }
}

/// The outline of a fuselage seen from above: half widths at stations along the length axis (tail x = 0.05, nose 0.95).
public struct HullPlan: Sendable, Hashable {
    public var stations: [ProfilePoint]

    public init(_ points: [(Double, Double)]) { stations = points.map { ProfilePoint($0.0, $0.1) } }

    /// The half width at `x`, linear between stations.
    public func half(at x: Double) -> Double {
        guard let first = stations.first, let last = stations.last else { return 0 }
        if x <= first.x { return first.halfWidth }
        if x >= last.x { return last.halfWidth }
        for (a, b) in zip(stations, stations.dropFirst()) where x >= a.x && x <= b.x {
            return a.halfWidth + (b.halfWidth - a.halfWidth) * (b.x == a.x ? 0 : (x - a.x) / (b.x - a.x))
        }
        return 0
    }

    public var tailX: Double { stations.first?.x ?? 0 }
    public var noseX: Double { stations.last?.x ?? 1 }
    public var maxHalf: Double { stations.map(\.halfWidth).max() ?? 0 }

    /// A smooth closed outline, mirrored about the centreline.
    public var path: Path {
        var points = stations.map { SplinePoint($0.x, 0.5 - $0.halfWidth) }
        points += stations.reversed().filter { $0.halfWidth > 0 }.map { SplinePoint($0.x, 0.5 + $0.halfWidth) }
        return ArtGeometry.closedSpline(points)
    }
}

/// One station of a hull plan.
public struct ProfilePoint: Sendable, Hashable {
    public var x: Double
    public var halfWidth: Double

    public init(_ x: Double, _ halfWidth: Double) {
        self.x = x
        self.halfWidth = halfWidth
    }
}

/// ART-SHIP: builds the geometry of a ship from its class, statistics, installed equipment and livery.
public enum ShipForge {
    /// The designs that are not built ships of the ten classes.
    public static func isSpecial(_ kind: ShipArtKind) -> Bool {
        [.spaceMonster, .dragonfly, .mantis, .scarab, .bottle, .scorpion].contains(kind)
    }

    /// The class whose design a ship is built to. A designed (custom) ship uses its chosen style, or, without one, the
    /// class that suits its statistics.
    public static func designClass(_ input: ShipArtInput) -> ShipArtKind {
        if input.kind.isBuyable { return input.kind }
        if let style = input.style, style.isBuyable { return style }
        let s = input.stats
        if input.kind == .scorpion { return .scorpion }
        if s.cargoBays >= 45 { return s.sizeClass >= 4 ? .termite : .beetle }
        if s.weaponSlots >= 3 { return s.sizeClass >= 4 ? .wasp : .hornet }
        if s.sizeClass == 0 { return .flea }
        if s.gadgetSlots >= 3 { return .grasshopper }
        if s.sizeClass == 1 { return s.weaponSlots >= 2 ? .mosquito : (s.shieldSlots >= 1 ? .firefly : .gnat) }
        return .bumblebee
    }

    public static func geometry(_ input: ShipArtInput) -> ShipGeometry {
        switch input.kind {
        case .spaceMonster: return ShipSpecialForge.monster(input)
        case .bottle: return ShipSpecialForge.bottle(input)
        case .mantis: return ShipSpecialForge.mantis(input)
        case .dragonfly: return ShipSpecialForge.dragonfly(input)
        case .scarab: return ShipSpecialForge.scarab(input)
        case .scorpion:
            // The kidnappers' warship: a built hull in a fixed black-and-red pirate livery.
            var livery = ShipLivery.make(role: .pirate, seed: 0x5343_4F52)
            livery.base = ArtRGB(0.11, 0.11, 0.12)
            livery.secondary = ArtRGB(0.06, 0.06, 0.07)
            livery.accent = ArtRGB(0.85, 0.12, 0.10)
            livery.pattern = .tailChevron
            return built(input, livery: livery)
        default:
            return built(input, livery: input.livery)
        }
    }

    /// ART-SHIP-002…004: a built ship: the class's hull, shaped by the statistics, with paint and fittings.
    static func built(_ input: ShipArtInput, livery: ShipLivery) -> ShipGeometry {
        var b = ShipBuilder(stats: input.stats, livery: livery)
        ShipClasses.design(designClass(input), &b)
        b.fuselage()
        b.statistics()
        ShipPaint.apply(&b)
        ShipFittings.apply(&b)
        if input.derelict {
            let x = b.plan.tailX + (b.plan.noseX - b.plan.tailX) * 0.5
            b.add(Path(roundedRect: CGRect(x: x - 0.04, y: 0.5 - 0.016, width: 0.08, height: 0.032), cornerRadius: 0.004), .dark, solid: false,
                  color: ArtRGB(0.02, 0.02, 0.03), flat: true, tag: "hatch")
        }
        var g = b.finish()
        g.derelict = input.derelict
        return g
    }
}

/// Collects the parts of one ship. A class design sets the hull plan, adds what sits under the fuselage (wings,
/// booms, nacelles) and says where the engines and the mounts are; the common steps add the rest.
struct ShipBuilder {
    let stats: ShipArtStats
    let livery: ShipLivery
    let frame: ShipFrame
    var plan = HullPlan([(0.05, 0.05), (0.5, 0.08), (0.95, 0)])
    var parts: [ShipPart] = []
    var glows: [EngineMount] = []
    var lights: [ShipLight] = []
    /// The fuselage outline: paint is clipped to it.
    var painted = Path()
    /// Where the flight deck's glass starts and ends, and where the cabins sit.
    var deck: ClosedRange<Double> = 0.78...0.90
    var cabinRange: ClosedRange<Double> = 0.55...0.76
    /// The stretch of the hull that carries cargo doors, and the one that carries the propellant blisters.
    var cargoRange: ClosedRange<Double> = 0.30...0.62
    var tankStart = 0.14
    /// Mount points for weapons, in order of use; shield emitters and gadget mounts sit on these centreline stretches.
    var weaponMounts: [CGPoint] = []
    var emitterRange: ClosedRange<Double> = 0.35...0.60
    var gadgetRange: ClosedRange<Double> = 0.14...0.30
    /// Where the radiator fins are rooted: stations along the aft hull.
    var radiatorRange: ClosedRange<Double> = 0.10...0.26
    /// A seam along the centreline (the Beetle's wing-case line) or across the hull at these stations (segments).
    var seams: [Double] = []
    var centreSeam = false
    /// Class marks: dark bands across the body (the Bumblebee), a lit band around the tail (the Firefly's lantern).
    var bands: [Double] = []
    var lantern: ClosedRange<Double>?
    /// The colour of the plumes; nil is the usual blue-white.
    var glow: ArtRGB?

    init(stats: ShipArtStats, livery: ShipLivery) {
        self.stats = stats
        self.livery = livery
        frame = ShipFrame(stats)
    }

    static let steel = ArtRGB(0.36, 0.38, 0.42)
    static let line = ArtRGB(0.03, 0.04, 0.06, 0.42)

    mutating func add(_ path: Path, _ role: ShipPart.Role, solid: Bool = true, lineWidth: Double? = nil, color: ArtRGB? = nil, flat: Bool = false,
                      tag: String) {
        parts.append(ShipPart(path, role, solid: solid, lineWidth: lineWidth, color: color, flat: flat, tag: tag))
    }

    /// Adds a part and its mirror image about the centreline.
    mutating func addPair(_ path: Path, _ role: ShipPart.Role, solid: Bool = true, color: ArtRGB? = nil, flat: Bool = false, tag: String) {
        add(path, role, solid: solid, color: color, flat: flat, tag: tag)
        add(ArtGeometry.mirrorY(path), role, solid: solid, color: color, flat: flat, tag: tag)
    }

    static func poly(_ points: [(Double, Double)]) -> Path { ArtGeometry.polygon(points.map { CGPoint(x: $0.0, y: $0.1) }) }

    static func smooth(_ points: [(Double, Double)]) -> Path { ArtGeometry.closedSpline(points.map { SplinePoint($0.0, $0.1) }) }

    /// A lifting surface on the upper side of the picture (mirrored by `addPair`): root chord on the hull, swept tip.
    static func surface(rootFront: Double, rootBack: Double, tipFront: Double, tipBack: Double, span: Double, rootY: Double = 0.02) -> Path {
        ArtGeometry.closedSpline([
            SplinePoint(rootFront, 0.5 - rootY, sharp: true), SplinePoint((rootFront + tipFront) / 2 + 0.01, 0.5 - (rootY + span) / 2),
            SplinePoint(tipFront, 0.5 - span, sharp: true), SplinePoint(tipBack, 0.5 - span, sharp: true),
            SplinePoint((rootBack + tipBack) / 2, 0.5 - (rootY + span) / 2), SplinePoint(rootBack, 0.5 - rootY, sharp: true),
        ])
    }

    /// Engines at the tail: `count` nozzles spread over `spread` of the half beam there.
    mutating func engines(at x: Double, spread: Double, radius: Double) {
        let n = frame.nozzles
        let offsets: [Double] = n == 1 ? [0] : (n == 2 ? [-1, 1] : [-1, 0, 1])
        glows += offsets.map { EngineMount(x: x, yOffset: $0 * spread, radius: n == 1 ? radius * 1.25 : radius) }
    }

    /// The fuselage itself, its panel seams, the flight deck and the cabin windows.
    mutating func fuselage() {
        let hull = plan.path
        painted = hull
        add(hull, .primary, color: livery.base, tag: "hull")
        // Chines: two inner contours that follow the outline, so the hull reads as a lofted, panelled body.
        for k in [0.48, 0.80] {
            let inner = hull.applying(CGAffineTransform(a: 1, b: 0, c: 0, d: k, tx: 0, ty: 0.5 * (1 - k)))
            add(inner.strokedPath(StrokeStyle(lineWidth: 0.0018)).intersection(hull), .dark, solid: false, color: ArtRGB(0.03, 0.04, 0.06, 0.22), flat: true,
                tag: "chine")
        }
        // Seams: frames across the hull, and a centreline seam where the class has one.
        var stations = seams
        if stations.isEmpty {
            var x = plan.tailX + 0.09
            while x < plan.noseX - 0.10 {
                stations.append(x)
                x += 0.11
            }
        }
        for x in stations {
            let h = plan.half(at: x) * 0.96
            add(Path(CGRect(x: x - 0.0012, y: 0.5 - h, width: 0.0024, height: h * 2)).intersection(hull), .dark, solid: false, color: Self.line,
                flat: true, tag: "seam")
        }
        if centreSeam {
            add(Path(CGRect(x: plan.tailX + 0.02, y: 0.5 - 0.0015, width: cabinRange.lowerBound - plan.tailX - 0.03, height: 0.003)), .dark, solid: false,
                color: Self.line, flat: true, tag: "seam")
        }
        for x in bands {
            add(Path(CGRect(x: x, y: 0, width: 0.055, height: 1)).intersection(hull), .dark, solid: false, color: ArtRGB(0.06, 0.06, 0.07, 0.62), flat: true,
                tag: "classBand")
        }
        if let lantern {
            add(Path(CGRect(x: lantern.lowerBound, y: 0, width: lantern.upperBound - lantern.lowerBound, height: 1)).intersection(hull), .glow, solid: false,
                color: glow ?? ArtRGB(0.8, 1, 0.45), tag: "lantern")
        }
        // The flight deck: a wrap-around canopy at the nose.
        let d0 = deck.lowerBound, d1 = deck.upperBound, h0 = plan.half(at: d0) * 0.62, h1 = plan.half(at: d1) * 0.55
        add(ArtGeometry.closedSpline([SplinePoint(d0, 0.5 - h0, sharp: true), SplinePoint((d0 + d1) / 2, 0.5 - (h0 + h1) / 2 * 1.06), SplinePoint(d1, 0.5 - h1),
                                      SplinePoint(d1 + 0.012, 0.5), SplinePoint(d1, 0.5 + h1), SplinePoint((d0 + d1) / 2, 0.5 + (h0 + h1) / 2 * 1.06),
                                      SplinePoint(d0, 0.5 + h0, sharp: true)]), .cockpit, solid: false, tag: "flightDeck")
        // Cabins: one lit row of ports per crew quarter, along both flanks.
        let length = cabinRange.upperBound - cabinRange.lowerBound
        for i in 0..<frame.cabins {
            let x = cabinRange.upperBound - (Double(i) + 0.5) * length / 3
            let y = plan.half(at: x) * 0.58
            for side in [-1.0, 1.0] {
                add(Path(roundedRect: CGRect(x: x - length / 3 * 0.34, y: 0.5 + side * y - 0.004, width: length / 3 * 0.68, height: 0.008),
                    cornerRadius: 0.004),
                    .glow, solid: false, color: ArtRGB(0.78, 0.90, 1.0, 0.85), flat: true, tag: side < 0 ? "cabin" : "cabinPort")
            }
        }
        // Navigation lights at the widest beam, and at the tail.
        let widest = plan.stations.max { $0.halfWidth < $1.halfWidth }?.x ?? 0.5
        lights += [ShipLight(position: CGPoint(x: widest, y: 0.5 - plan.half(at: widest)), kind: .port),
                   ShipLight(position: CGPoint(x: widest, y: 0.5 + plan.half(at: widest)), kind: .starboard),
                   ShipLight(position: CGPoint(x: plan.tailX + 0.01, y: 0.5), kind: .tail)]
    }

    /// What the statistics add to any class: cargo doors, propellant blisters, armour strakes and radiator fins.
    mutating func statistics() {
        let hull = painted
        // Cargo doors: paired hatches along the cargo stretch, one per five bays.
        let pairs = (frame.cargoDoors + 1) / 2
        let length = cargoRange.upperBound - cargoRange.lowerBound
        let pitch = pairs > 0 ? min(0.075, length / Double(pairs)) : 0
        for i in 0..<frame.cargoDoors {
            let column = i / 2, side: Double = i % 2 == 0 ? -1 : 1
            let x = cargoRange.lowerBound + (length - pitch * Double(pairs)) / 2 + Double(column) * pitch
            let h = plan.half(at: x + pitch / 2)
            let door = Path(roundedRect: CGRect(x: x + pitch * 0.08, y: 0.5 + (side < 0 ? -h * 0.50 : h * 0.10), width: pitch * 0.84, height: h * 0.40),
                cornerRadius: 0.004)
                .intersection(hull)
            let tint = livery.containers.isEmpty ? livery.secondary : livery.containers[i % livery.containers.count]
            add(door, .secondary, solid: false, color: livery.base.mix(tint, livery.role == .trader ? 0.55 : 0.30).shade(0.92), flat: true, tag: "cargoDoor")
            add(door.strokedPath(StrokeStyle(lineWidth: 0.0022)), .dark, solid: false, color: Self.line, flat: true, tag: "cargoDoorFrame")
        }
        // Propellant: two dorsal blisters whose length follows the fuel capacity.
        let t0 = tankStart, t1 = min(plan.noseX - 0.2, tankStart + frame.tankLength)
        let ty = max(0.012, plan.half(at: (t0 + t1) / 2) * 0.34), tr = max(0.008, plan.half(at: (t0 + t1) / 2) * 0.20)
        addPair(ArtGeometry.capsule(from: CGPoint(x: t0 + tr, y: 0.5 - ty), to: CGPoint(x: max(t0 + tr + 0.001, t1 - tr), y: 0.5 - ty), radius: tr),
                .secondary, solid: false, color: livery.base.shade(1.12), tag: "tank")
        // Armour: strakes that stand a little proud of the flanks.
        for i in 0..<frame.plates {
            let side: Double = i % 2 == 0 ? -1 : 1, slot = Double(i / 2)
            let x0 = plan.tailX + 0.10 + slot * (plan.noseX - plan.tailX - 0.30) / 6, x1 = x0 + (plan.noseX - plan.tailX - 0.30) / 6 * 0.86
            let strake = ArtGeometry.closedSpline([
                SplinePoint(x0, 0.5 + side * plan.half(at: x0) * 0.90, sharp: true), SplinePoint((x0 + x1) / 2,
                    0.5 + side * (plan.half(at: (x0 + x1) / 2) + 0.010)),
                SplinePoint(x1, 0.5 + side * plan.half(at: x1) * 0.90, sharp: true), SplinePoint((x0 + x1) / 2,
                    0.5 + side * plan.half(at: (x0 + x1) / 2) * 0.80),
            ])
            add(strake, .primary, color: livery.base.shade(0.80), tag: "plate")
        }
        // Radiators: thin swept fins near the engines, dark with a hot edge.
        let n = frame.radiatorPairs
        for i in 0..<n {
            let x = n == 1 ? (radiatorRange.lowerBound + radiatorRange.upperBound) / 2
                : radiatorRange.lowerBound + (radiatorRange.upperBound - radiatorRange.lowerBound) * Double(i) / Double(n - 1)
            let root = plan.half(at: x) * 0.9, span = 0.045 + 0.008 * Double(stats.sizeClass)
            let fin = Self.poly([(x + 0.012, 0.5 - root), (x - 0.022, 0.5 - root - span), (x - 0.034, 0.5 - root - span), (x - 0.012, 0.5 - root)])
            addPair(fin, .dark, color: ArtRGB(0.10, 0.11, 0.14), flat: true, tag: "radiator")
            addPair(Self.poly([(x + 0.012, 0.5 - root), (x - 0.022, 0.5 - root - span), (x - 0.025, 0.5 - root - span), (x + 0.008, 0.5 - root)]), .glow,
                solid: false,
                    color: ArtRGB(0.95, 0.42, 0.16, 0.55), flat: true, tag: "radiatorEdge")
        }
    }

    /// Fine detail of one kind and colour is drawn as one path (fewer fills per frame, ART-SHIP-011).
    static let merged: Set<String> = ["seam", "chine", "cargoDoorFrame", "radiatorEdge", "tally", "cabinPort"]

    func finish() -> ShipGeometry {
        var out: [ShipPart] = []
        var index: [String: Int] = [:]
        for part in parts {
            if Self.merged.contains(part.tag), let i = index[part.tag], out[i].color == part.color {
                out[i].path.addPath(part.path)
            } else {
                if Self.merged.contains(part.tag) { index[part.tag] = out.count }
                out.append(part)
            }
        }
        var g = ShipGeometry(parts: out, hull: painted, glows: glows, lights: lights)
        g.paint = livery.base
        g.checkerCells = checkerCells
        if let glow { g.glow = glow }
        return g
    }

    var checkerCells: [(rect: CGRect, blue: Bool)] = []
}
