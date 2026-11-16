// SPDX-License-Identifier: GPL-2.0-or-later
// Ruleset switches for galaxy generation, content placement and start system (RUL-020…031). docs/specs/RUL.md is normative.
// RUL-020 (`distanceRounding`) is the flat `RuleFlags.distance` flag.

/// RUL-021: how a candidate system is rejected for lying too close to an earlier one.
public enum MinDistanceTest: Sendable, Equatable {
    /// C#: reject if `floor(d) < minDistance` (Game.cs:2226).
    case flooredBelowMinimum
    /// Palm: reject if `d² <= (minDistance + 1)²` (`SQR(MINDISTANCE+1)`, Traveler.c:StartNewGame).
    case squaredAtMostNextSquare
}

/// RUL-022: how the six central (wormhole) systems are offset from their grid centres.
public enum CentreOffsetRoll: Sendable, Equatable {
    /// C#: `centre − r(−offset+1, offset)` → ±(offset−1).
    case symmetricRange
    /// Palm: `(offset − r(2·offset+1)) + centre` → ±offset (`CLOSEDISTANCE>>1 − GetRandom(CLOSEDISTANCE)`).
    case subtractFromHalf
}

/// RUL-023: how a system's government and tech level are chosen.
public enum SystemGenerationMethod: Sendable, Equatable {
    /// C#: government uniform, then tech uniform inside its range.
    case governmentThenTech
    /// Palm: `TL = r(8)`, `gov = r(17)`; a pair outside the government's range rejects the whole attempt.
    case rejectionSampled
}

/// RUL-024: RNG call order per system and for new-game construction.
public enum GenerationRollOrder: Sendable, Equatable {
    /// C#: size, government, TL, pressure, resource, coordinates; universe → (events, shipyards) → start → crew.
    case csharp
    /// Palm: coordinates, distance test, TL, government, resource, size, status; universe → mercenaries → events → start.
    case palm
}

/// RUL-026: where the Scarab end-point goes.
public enum ScarabEndpointPlacement: Sendable, Equatable {
    /// C#: the first wormhole system (ring order) without an event; none → placement fails.
    case firstFreeWormhole
    /// Palm: a random wormhole, re-drawn while occupied and not Gemulon/Daled/Nix, at most `retries` times; failure →
    /// no Scarab quest.
    case randomWormhole(retries: Int)
}

/// RUL-028: where the artifact delivery goes.
public enum ArtifactDeliveryPlacement: Sendable, Equatable {
    /// C#: the lowest-index Hi-Tech system without an event; none → placement fails.
    case lowestIndexHiTech
    /// Palm: up to `tries` random systems (TL ≥ Hi-Tech, free, not Gemulon/Daled); failure → Alien Artifact occurrence 0.
    case randomTries(Int)
}

/// RUL-027: the exclusion test a distant placement applies when `distantPlacementExclusionBug` is on.
public enum DistantExclusion: Sendable, Equatable {
    case none
    /// Palm Reactor: `d != GEMULON && d != DALED` where `d` is the running best *distance* (never excludes).
    case bestDistanceNotGemulonDaled
    /// Palm Invasion: `k != DALED && k != GEMULON` where `k` is the running best *index* (Daled, once best, sticks).
    case bestIndexNotDaledGemulon
}

/// One step of special-event placement, in ruleset order.
public enum EventPlacementStep: Sendable, Equatable {
    case scarabEndpoint
    case artifactDelivery
    /// The closest free system ≥ 70 parsecs from `base` gets `event`; Palm also sets `baseEvent` on the base system.
    /// Skipped when the content pack has no `event`.
    case distant(base: Int, event: SpecialEventType, baseEvent: SpecialEventType?, exclusion: DistantExclusion)
    /// Random events in table order, `occurrence` times each.
    case randomEvents
}

/// Galaxy behaviour switches. Each case of every switch is selected by the ruleset presets below; engine code reads
/// these values and never branches on the ruleset id.
public struct GalaxyRules: Sendable, Equatable {
    /// RUL-021.
    public var minDistanceTest: MinDistanceTest = .flooredBelowMinimum
    /// RUL-022.
    public var centreOffsetRoll: CentreOffsetRoll = .symmetricRange
    /// RUL-023.
    public var systemGenerationMethod: SystemGenerationMethod = .governmentThenTech
    /// RUL-024.
    public var generationRollOrder: GenerationRollOrder = .csharp
    /// RUL-025: regenerate the whole universe when a placement fails (RNG continues).
    public var regenerateGalaxyOnPlacementFailure = true
    /// RUL-026.
    public var scarabEndpointPlacement: ScarabEndpointPlacement = .firstFreeWormhole
    /// RUL-027: apply each distant step's (buggy Palm) exclusion test.
    public var distantPlacementExclusionBug = false
    /// RUL-028.
    public var artifactDeliveryPlacement: ArtifactDeliveryPlacement = .lowestIndexHiTech
    /// RUL-029: lowest system id eligible for random events (C# 0, Palm 1); the upper bound is the system count.
    public var randomEventFirstSystem = 0
    /// RUL-030: maximum start-system tries (`nil` = unbounded); after a bounded search fails, the last draw is used.
    public var startSystemMaxTries: Int?
    /// RUL-030: tries (from 0) during which the start tech must lie in `startSystemTechRange`.
    public var startSystemStrictTechTries = Int.max
    /// RUL-030: allowed start tech levels during the strict tries (C# 1…6, Palm 1…5).
    public var startSystemTechRange: ClosedRange<TechLevel> = .agricultural ... .postIndustrial
    /// RUL-031: true = the "3 reachable systems" test uses `d² ≤ tanks²` (Palm); false = `distance ≤ tanks` (C#).
    public var startReachUsesSquaredDistance = false
    /// GAL-061: the Lottery is placed only if the start system still has no event (Palm); C# overwrites (GAL-060).
    public var lotteryRequiresFreeStart = false
    /// RUL-012/024-028: special-event placement steps after the fixed events, in order.
    public var eventPlacement: [EventPlacementStep] = [
        .scarabEndpoint, .artifactDelivery,
        .distant(base: SystemID.nix, event: .reactor, baseEvent: nil, exclusion: .none),
        .distant(base: SystemID.gemulon, event: .gemulon, baseEvent: nil, exclusion: .none),
        .distant(base: SystemID.daled, event: .experiment, baseEvent: nil, exclusion: .none),
        .distant(base: SystemID.endor, event: .sculpture, baseEvent: nil, exclusion: .none),
        .randomEvents,
    ]

    /// Windows 2.01 (faithful C# port).
    public static let windows201 = GalaxyRules()
    /// Modern: Windows 2.01 (MOD-006 and MOD-013 are flat flags); no galaxy row differs (RUL-003).
    public static let modern = GalaxyRules()
    /// Original Palm 1.2.2 (Src/Traveler.c:StartNewGame).
    public static let palm122: GalaxyRules = {
        var g = GalaxyRules()
        g.minDistanceTest = .squaredAtMostNextSquare
        g.centreOffsetRoll = .subtractFromHalf
        g.systemGenerationMethod = .rejectionSampled
        g.generationRollOrder = .palm
        g.regenerateGalaxyOnPlacementFailure = false
        g.scarabEndpointPlacement = .randomWormhole(retries: 20)
        g.distantPlacementExclusionBug = true
        g.artifactDeliveryPlacement = .randomTries(120)
        g.randomEventFirstSystem = 1
        g.startSystemMaxTries = 200
        g.startSystemStrictTechTries = 100
        g.startSystemTechRange = .agricultural ... .industrial
        g.startReachUsesSquaredDistance = true
        g.lotteryRequiresFreeStart = true
        g.eventPlacement = [
            .scarabEndpoint,
            .distant(base: SystemID.nix, event: .reactor, baseEvent: .reactorDelivered,
                     exclusion: .bestDistanceNotGemulonDaled),
            .artifactDelivery,
            .distant(base: SystemID.gemulon, event: .gemulon, baseEvent: .gemulonRescued,
                     exclusion: .bestIndexNotDaledGemulon),
            .distant(base: SystemID.daled, event: .experiment, baseEvent: .experimentStopped, exclusion: .none),
            .randomEvents,
        ]
        return g
    }()
}
