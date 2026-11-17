// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// ART-020: everything a planet portrait needs; no game state.
public struct PlanetArtInput: Sendable, Hashable {
    public var seed: UInt64
    /// `SystemSize` raw value, 0…5.
    public var sizeClass: Int
    /// `TechLevel` raw value, 0…7.
    public var tech: Int
    /// `PoliticalSystemType` raw value, 0…16.
    public var government: Int
    /// A `SpecialResource` raw value; nil = unknown.
    public var resource: Int?
    /// A `SystemPressure` raw value; nil = not shown.
    public var pressure: Int?
    public var phase: Double
    public var accessibility: ArtAccessibility

    public init(seed: UInt64, sizeClass: Int = 2, tech: Int = 4, government: Int = 6, resource: Int? = nil, pressure: Int? = nil,
                phase: Double = 0, accessibility: ArtAccessibility = .standard) {
        self.seed = seed
        self.sizeClass = min(5, max(0, sizeClass))
        self.tech = min(7, max(0, tech))
        self.government = min(16, max(0, government))
        self.resource = resource
        self.pressure = pressure
        self.phase = phase
        self.accessibility = accessibility
    }
}

/// ART-022: the style by tech level (8 cases in `TechLevel` order).
public enum PlanetStyle: Int, CaseIterable, Sendable, Hashable {
    case preAgricultural = 0, agricultural, medieval, renaissance, earlyIndustrial, industrial, postIndustrial, hiTech

    /// Settlement dots on the day side.
    var dayDots: Int { [0, 0, 7, 14, 16, 18, 10, 6][rawValue] }
    /// City lights on the night side.
    var nightLights: Int { [0, 0, 0, 0, 0, 8, 22, 48][rawValue] }
    var ring: PlanetRing { rawValue == 7 ? .full : (rawValue == 6 ? .partial : .none) }
    var satellites: Int { rawValue == 7 ? 2 : 0 }
}

public enum PlanetRing: Sendable, Hashable {
    case none, partial, full
}

/// ART-023: one motif per government (exhaustive table over the 17 governments in `PoliticalSystemType` order).
public enum GovernmentMotif: Int, CaseIterable, Sendable, Hashable {
    case none = 0, debrisField, defensePlatforms, beacons, grid, halo

    /// anarchy, capitalist, communist, confederacy, corporate, cybernetic, democracy, dictatorship, fascist, feudal,
    /// military, monarchy, pacifist, socialist, satori, technocracy, theocracy.
    public static let table: [GovernmentMotif] = [.debrisField, .beacons, .grid, .beacons, .beacons, .grid, .none, .defensePlatforms,
                                                   .defensePlatforms, .none, .defensePlatforms, .none, .halo, .grid, .halo, .grid, .halo]

    public static func motif(government: Int) -> GovernmentMotif {
        table.indices.contains(government) ? table[government] : .none
    }
}

/// ART-024: the known-resource looks (`SpecialResource` raw values 0…12).
public enum PlanetResourceLook: Int, CaseIterable, Sendable, Hashable {
    case nothing = 0, mineralRich, mineralPoor, desert, sweetOceans, richSoil, poorSoil, richFauna, lifeless, weirdMushrooms,
         specialHerbs, artistic, warlike
}

/// ART-025: pressure overlays (`SystemPressure` raw values 0…7).
public enum PlanetPressureLook: Int, CaseIterable, Sendable, Hashable {
    case none = 0, war, plague, drought, boredom, cold, cropFailure, employment
}

/// One continent outline (seeded Bézier blob on the unwrapped surface: `u` in 0…2 around the planet, `v` 0…1).
public struct ContinentBlob: Sendable, Hashable {
    public var u: Double
    public var v: Double
    public var radius: Double
    public var aspect: Double
    public var seed: UInt64
}

public struct CloudBand: Sendable, Hashable {
    public var v: Double
    public var thickness: Double
    public var wave: Double
    public var offset: Double
}

/// ART-021: a pure, deterministic description of a planet (vector shapes only).
public struct PlanetRecipe: Sendable, Hashable {
    public var style: PlanetStyle
    public var motif: GovernmentMotif
    public var look: PlanetResourceLook?
    public var pressure: PlanetPressureLook?
    public var radiusFraction: Double
    public var landRatio: Double
    public var continents: [ContinentBlob]
    public var clouds: [CloudBand]
    public var tilt: Double
    public var ocean: ArtToken
    public var land: ArtToken
    public var rim: ArtToken
    public var iceCap: Double
    public var craters: Int
    public var patches: ArtToken?
    /// Seeded points on the unit surface for dots, lights and marks.
    public var marks: [Double]

    public static func make(_ input: PlanetArtInput) -> PlanetRecipe {
        var rng = ArtRandom(seed: input.seed)
        let style = PlanetStyle(rawValue: input.tech) ?? .preAgricultural
        let look = input.resource.flatMap(PlanetResourceLook.init(rawValue:))
        let pressure = input.pressure.flatMap(PlanetPressureLook.init(rawValue:))
        var r = PlanetRecipe(style: style, motif: .motif(government: input.government), look: look, pressure: pressure,
                             radiusFraction: 0.55 + 0.08 * Double(input.sizeClass), landRatio: rng.range(0.25...0.55), continents: [],
                             clouds: [], tilt: rng.range(-25...25), ocean: .ocean, land: .landGreen, rim: .atmosphere,
                             iceCap: rng.range(0.06...0.12), craters: 0, patches: nil, marks: [])
        let earthy: [ArtToken] = [.landGreen, .landBrown, .landGreen, .olive, .landDark]
        r.land = earthy[Int(rng.next() % UInt64(earthy.count))]
        r.applyResource()
        if pressure == .drought { r.landRatio = min(0.85, r.landRatio * 1.35) }
        if pressure == .cold { r.iceCap = 0.26 }
        let count = rng.int(3...7)
        for _ in 0..<count {
            r.continents.append(ContinentBlob(u: rng.range(0...2), v: rng.range(0.18...0.82),
                                              radius: rng.range(0.12...0.22) * (0.6 + r.landRatio), aspect: rng.range(0.8...1.6),
                                              seed: rng.next()))
        }
        let bands = r.look == .lifeless ? 0 : rng.int(2...4)
        for _ in 0..<bands {
            r.clouds.append(CloudBand(v: rng.range(0.15...0.85), thickness: rng.range(0.03...0.07), wave: rng.range(0.01...0.04),
                                      offset: rng.range(0...2)))
        }
        r.marks = (0..<128).map { _ in rng.unit() }
        return r
    }

    private mutating func applyResource() {
        guard let look else { return }
        switch look {
        case .nothing: break
        case .mineralRich: patches = .metal
        case .mineralPoor: land = .landGrey
        case .desert:
            land = .landSand
            landRatio = 0.8
            iceCap = 0.03
        case .sweetOceans:
            landRatio = 0.18
            ocean = .visited
        case .richSoil: land = .landDark
        case .poorSoil: land = .landPale
        case .richFauna: land = .landLush
        case .lifeless:
            land = .landGrey
            ocean = .landGrey
            craters = 9
            iceCap = 0
        case .weirdMushrooms: patches = .mushroom
        case .specialHerbs: patches = .herb
        case .artistic: rim = .amber
        case .warlike: rim = .danger
        }
    }
}
