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

/// ART-022: the tech layers (8 cases in `TechLevel` order).
public enum PlanetStyle: Int, CaseIterable, Sendable, Hashable {
    case preAgricultural = 0, agricultural, medieval, renaissance, earlyIndustrial, industrial, postIndustrial, hiTech

    /// The strength of the farmland tint on fertile lowland.
    public var farmland: Double { [0, 0.5, 0.7, 0.8, 0.6, 0.5, 0.3, 0.2][rawValue] }
    /// The density of the city-light channel.
    public var cityLights: Double { [0, 0.012, 0.03, 0.07, 0.15, 0.30, 0.55, 0.90][rawValue] }
    /// The strength of the smog haze.
    public var smog: Double { [0, 0, 0, 0, 0.25, 0.40, 0.15, 0][rawValue] }
    public var ring: PlanetRing { rawValue == 7 ? .full : (rawValue == 6 ? .partial : .none) }
    public var satellites: Int { rawValue == 7 ? 2 : 0 }
}

/// The orbital (built) ring of the tech layers.
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

    /// How far the motif reaches from the planet's centre, in planet radii.
    var extent: Double {
        switch self {
        case .none, .grid: 1
        case .halo: 1.25
        case .debrisField: 1.34
        case .defensePlatforms: 1.32
        case .beacons: 1.16
        }
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

/// ART-021: a pure, deterministic description of a planet. It does no pixel work: the baker (ART-070) and the projector
/// (ART-072) turn it into maps and images.
public struct PlanetRecipe: Sendable, Hashable {
    public var planetClass: PlanetClass
    public var tint: PlanetTint
    public var accent: PlanetAccent
    public var style: PlanetStyle
    public var motif: GovernmentMotif
    public var look: PlanetResourceLook?
    public var pressure: PlanetPressureLook?
    public var radiusFraction: Double
    /// The share of the surface above sea level (classes with water).
    public var landRatio: Double
    /// The polar ice extent as a share of the pole-to-equator range.
    public var iceCap: Double
    public var cloudCover: Double
    /// Axial tilt in the picture plane, degrees (−25…25).
    public var tilt: Double
    /// How far the north pole tips towards the viewer, degrees.
    public var inclination: Double
    /// A palette variant within the class, 0…3.
    public var variant: Int
    /// The number of latitude bands of a gas giant.
    public var bands: Int
    public var ring: PlanetNaturalRing?
    public var noiseSeed: UInt64
    /// Seeded points for the vector overlays (satellites, motifs).
    public var marks: [Double]

    public static func make(_ input: PlanetArtInput) -> PlanetRecipe {
        var rng = ArtRandom(seed: input.seed)
        let style = PlanetStyle(rawValue: input.tech) ?? .preAgricultural
        let look = input.resource.flatMap(PlanetResourceLook.init(rawValue:))
        let pressure = input.pressure.flatMap(PlanetPressureLook.init(rawValue:))
        let forced = look.map(PlanetClass.forResource) ?? (nil, .none, .none)
        let seeded = PlanetClass.seeded(roll: rng.unit(), sizeClass: input.sizeClass)
        let cls = forced.planetClass ?? seeded
        var r = PlanetRecipe(planetClass: cls, tint: forced.tint, accent: forced.accent, style: style,
                             motif: .motif(government: input.government), look: look, pressure: pressure,
                             radiusFraction: 0.55 + 0.08 * Double(input.sizeClass), landRatio: rng.range(0.25...0.55),
                             iceCap: rng.range(0.06...0.14), cloudCover: rng.range(0.30...0.50), tilt: rng.range(-25...25),
                             inclination: rng.range(6...16), variant: rng.int(0...3), bands: rng.int(7...13), ring: nil,
                             noiseSeed: rng.next(), marks: [])
        let ringRoll = rng.unit()
        let ring = PlanetNaturalRing(inner: rng.range(1.28...1.45), outer: rng.range(1.85...2.25), opacity: rng.range(0.55...0.85),
                                     seed: rng.range(0...6.28), tint: rng.int(0...2))
        if ringRoll < cls.ringChance {
            r.ring = ring
            r.inclination = rng.range(14...26)
        }
        r.applyClass()
        if pressure == .drought { r.landRatio = min(0.9, r.landRatio * 1.35) }
        if pressure == .cold { r.iceCap = min(0.5, r.iceCap + 0.2) }
        r.marks = (0..<128).map { _ in rng.unit() }
        return r
    }

    private mutating func applyClass() {
        switch planetClass {
        case .terran:
            landRatio = 0.25 + (landRatio - 0.25) * 0.8
        case .ocean:
            landRatio = 0.03 + landRatio * 0.16
            iceCap *= 0.4
            cloudCover += 0.05
        case .desert:
            landRatio = 1
            iceCap = 0.02
            cloudCover *= 0.3
        case .ice:
            landRatio = 0.93 + landRatio * 0.1
            iceCap = 1
            cloudCover *= 0.6
        case .jungle:
            landRatio = 0.5 + landRatio * 0.45
            iceCap = 0
            cloudCover = min(0.62, cloudCover + 0.15)
        case .rocky:
            landRatio = 1
            iceCap *= 0.4
            cloudCover *= 0.12
        case .barren:
            landRatio = 1
            iceCap = 0
            cloudCover = 0
        case .volcanic:
            landRatio = 1
            iceCap = 0
            cloudCover *= 0.45
        case .toxic:
            landRatio = 1
            iceCap = 0
            cloudCover = 1
        case .gasGiant:
            landRatio = 1
            iceCap = 0
            cloudCover = 0
        }
    }

    /// How far anything drawn with the planet reaches from its centre, in planet radii (ART-023).
    public var extent: Double {
        var e = motif.extent
        if style.ring != .none { e = max(e, 1.26) }
        if style.satellites > 0 { e = max(e, 1.4) }
        if let ring { e = max(e, ring.outer) }
        return e
    }
}
