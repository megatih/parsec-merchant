// SPDX-License-Identifier: GPL-2.0-or-later

/// Every sound the game can make. All of them are synthesised by `SynthCore` from the recipes in `CueRecipes`; no
/// sample file is shipped or loaded. The case order is the catalog order and is part of the recipe table layout.
public enum SoundCue: UInt8, CaseIterable, Sendable, BitwiseCopyable {
    case uiTick, uiConfirm, rejected
    case coinIn, coinOut, coinLoss
    case jettison, fuelFill, repair, equip, shipPurchase
    case warpDeparture, arrival, encounterStinger
    case laser, shieldHit, hullHit, explosion, powerDown, escape
    case lowHullAlarm, arrestSiren
    case notice, questChime, pickup, drink
    case gameEndFanfare
    case newspaperRustle, achievementChime, tribbleSqueak

    /// Number of variants of this cue (variant 0 is the default).
    public var variantCount: Int {
        switch self {
        case .encounterStinger: StingerVariant.allCases.count
        case .laser: LaserVariant.allCases.count
        case .warpDeparture: WarpVariant.allCases.count
        case .gameEndFanfare: FanfareVariant.allCases.count
        case .uiTick, .uiConfirm, .rejected, .coinIn, .coinOut, .coinLoss, .jettison, .fuelFill, .repair, .equip,
             .shipPurchase, .arrival, .shieldHit, .hullHit, .explosion, .powerDown, .escape, .lowHullAlarm, .arrestSiren,
             .notice, .questChime, .pickup, .drink, .newspaperRustle, .achievementChime, .tribbleSqueak:
            1
        }
    }

    /// Voice priority (AUD-005): 3 = explosion, alarm, siren, fanfare; 2 = combat and encounter stingers;
    /// 1 = economy, travel, quest, notice and app cues; 0 = UI cues.
    public var priority: UInt8 {
        switch self {
        case .explosion, .lowHullAlarm, .arrestSiren, .gameEndFanfare: 3
        case .laser, .shieldHit, .hullHit, .powerDown, .escape, .encounterStinger: 2
        case .coinIn, .coinOut, .coinLoss, .jettison, .fuelFill, .repair, .equip, .shipPurchase, .warpDeparture,
             .arrival, .notice, .questChime, .pickup, .drink, .newspaperRustle, .achievementChime:
            1
        case .uiTick, .uiConfirm, .rejected, .tribbleSqueak: 0
        }
    }

    // Nominal duration in seconds of `variant` (AUD-013…030), tested within ±10% (AUD-047). One line per cue and
    // variant, so the case count is the complexity.
    // swiftlint:disable:next cyclomatic_complexity
    public func nominalDuration(variant: UInt8 = 0) -> Double {
        switch self {
        case .uiTick: 0.025
        case .uiConfirm: 0.12
        case .rejected: 0.09
        case .coinIn: 0.45
        case .coinOut: 0.30
        case .coinLoss: 0.40
        case .jettison: 0.35
        case .fuelFill: 0.40
        case .repair: 0.21
        case .equip: 0.25
        case .shipPurchase: 0.90
        case .warpDeparture: 1.4
        case .arrival: 0.60
        case .encounterStinger:
            switch StingerVariant(rawValue: variant) ?? .pirate {
            case .pirate: 0.50
            case .police: 0.40
            case .trader: 0.35
            case .alien: 0.70
            case .special: 0.40
            }
        case .laser:
            switch LaserVariant(rawValue: variant) ?? .pulse {
            case .pulse: 0.12
            case .beam: 0.22
            case .military: 0.20
            case .morgans: 0.26
            case .photonDisruptor: 0.18
            case .quantumDisruptor: 0.24
            }
        case .shieldHit: 0.25
        case .hullHit: 0.15
        case .explosion: 1.2
        case .powerDown: 0.60
        case .escape: 0.50
        case .lowHullAlarm: 0.93
        case .arrestSiren: 1.6
        case .notice: 0.30
        case .questChime: 0.80
        case .pickup: 0.12
        case .drink: 0.50
        case .gameEndFanfare: 2.0
        case .newspaperRustle: 0.45
        case .achievementChime: 0.90
        case .tribbleSqueak: 0.18
        }
    }
}

/// `encounterStinger` variants (AUD-022), one per encounter badge, in the spec's order.
public enum StingerVariant: UInt8, CaseIterable, Sendable {
    case pirate, police, trader, alien, special
}

/// `laser` variants (AUD-023), in the engine's weapon order.
public enum LaserVariant: UInt8, CaseIterable, Sendable {
    case pulse, beam, military, morgans, photonDisruptor, quantumDisruptor
}

/// `warpDeparture` variants (AUD-020).
public enum WarpVariant: UInt8, CaseIterable, Sendable {
    case normal, wormhole
}

/// `gameEndFanfare` variants (AUD-029).
public enum FanfareVariant: UInt8, CaseIterable, Sendable {
    case standard, moon
}

/// The generative music's mood (AUD-038).
public enum MusicMood: UInt8, CaseIterable, Sendable {
    /// Welcome and docked: a major seventh progression I–vi–IV–V.
    case calm
    /// Transit: suspended and Lydian chords with a brighter filter.
    case travel
    /// Encounter: a minor progression over a low 1 Hz pulse drone.
    case tension
    /// Game over: the music fades out.
    case silent
}

/// AUD-016: the coin cues transpose by `min(12, 2 × ⌊log10(max(1, |total|))⌋)` semitones.
public func amountPitch(_ total: Int) -> Float {
    var magnitude = total.magnitude
    var digits = 0
    while magnitude >= 10 {
        magnitude /= 10
        digits += 1
    }
    return Float(min(12, 2 * digits))
}
