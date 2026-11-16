// SPDX-License-Identifier: GPL-2.0-or-later
// Ruleset switches for warp, transit, arrival, news and score (RUL-062…069, 118, 144…151; also RUL-045 and RUL-103,
// which run inside the warp/IncDays pipeline, and RUL-006). docs/specs/RUL.md is normative.

/// RUL-062 `monsterRegeneration`.
public enum MonsterRegeneration: String, Codable, Sendable {
    /// C#: `hull × 1.05^n` per IncDays (double, truncated, capped).
    case compoundPerDay
    /// Palm: `hull × 105 / 100` once per warp, singularity jumps included (capped).
    case perWarp
}

/// RUL-063 `shieldRechargeTiming`.
public enum ShieldRechargeTiming: String, Codable, Sendable {
    case onArrival
    /// Palm: at departure (singularity jumps included), not on arrival.
    case atDeparture
}

/// RUL-066 `arrivalPipelineOrder`.
public enum ArrivalPipelineOrder: String, Codable, Sendable {
    /// reactor → tribbles → debt → repairs/shields/auto-buy → pressures and quantities → Og egg → prices → news.
    case windows
    /// debt → Arrival() (shuffle, quantities, prices) → reactor → tracking → tribbles → repair → auto-buy → egg → news flags.
    case palm
}

/// RUL-067 `warpCheckOrder`.
public enum WarpCheckOrder: String, Codable, Sendable {
    /// debt → wages → insurance → wormhole tax → Wild's laser.
    case wildLast
    /// Wild's laser first; an accepted Wild departure is committed even when a later check fails (TRV-015).
    case wildFirst
}

/// RUL-068 `singularitySideEffects`.
public enum SingularitySideEffects: String, Codable, Sendable {
    /// No day, fuel or fees; no monster heal; arrived-via-wormhole only for a real wormhole.
    case windows
    /// No fees, interest, day or no-claim; monster heal and departure recharge still run; arrived-via-wormhole = true.
    case palm
}

/// RUL-103 `policeRecordDecay` (MOD-003). Lives here because it runs inside the warp and IncDays pipeline.
public enum PoliceRecordDecay: String, Codable, Sendable {
    /// C#: `rec − n/3`, `rec + n/(D ≤ Normal ? 1 : D)` inside IncDays.
    case perDayDivision
    /// Palm: once per warp (singularity included) with `days % 3` and `days % D` tests.
    case perWarp
}

/// RUL-045 `noClaimTiming`. Lives here because it runs inside the warp and IncDays pipeline.
public enum NoClaimTiming: String, Codable, Sendable {
    /// C#: +n per IncDays (jail and escape-pod days included).
    case perDay
    /// Palm: +1 per normal (non-singularity) warp.
    case perWarp
}

/// RUL-151 `tribbleAlgorithm`.
public enum TribbleAlgorithm: String, Codable, Sendable {
    case csharp
    case palm
}

/// RUL-149 `scoreFormula`.
public enum ScoreFormula: String, Codable, Sendable {
    /// `(D+1) × mod × (dm × 1000 + W') / 250000` in Int32, shown `s/10 . s%10`.
    case csharp
    /// Palm `GetScore`, shown `a/50 . (a%50)/5`.
    case palm
}

/// RUL-150 `highScoreBlock`.
public enum HighScoreBlock: String, Codable, Sendable {
    /// Enabling cheats blocks the entry.
    case cheats
    /// Palm: reloading via "Timewarp" blocks the entry; cheats do not.
    case reload
}

/// RUL-145 `newsHeroRule`.
public enum NewsHeroRule: String, Codable, Sendable {
    /// record ≥ 75.
    case atLeast
    /// record == 75 exactly.
    case exactly
}

/// RUL-146 `newsDistantRange`.
public enum NewsDistantRange: String, Codable, Sendable {
    /// `destOk`; moon, tribble-buyer and shipyard stories always.
    case destinationOK
    /// Palm: distance ≤ ship type's base tanks or wormhole, and status > 0 for every story; no shipyard stories.
    case baseTanksWithStatus
}

/// RUL-147 `newsCannedBound`.
public enum NewsCannedBound: String, Codable, Sendable {
    case drawnOnce
    /// Palm `for (i = 0; i <= GetRandom2(4); i++)`: the bound is re-drawn on every test.
    case redrawnEachPass
}

/// NEWS-041 `newsEventOrdering`.
public enum NewsEventOrdering: String, Codable, Sendable {
    /// C#: the stored events in insertion order.
    case insertion
    /// Palm: fixed headline order, each event tested for membership only.
    case palmFixed
}

/// NEWS-040 `newsSeedSystem`.
public enum NewsSeedSystem: String, Codable, Sendable {
    /// C#: masthead and seed use the current system.
    case currentSystem
    /// Palm: `WarpSystem` (the selected target) for the masthead and `RandSeed`.
    case warpSystem
}

/// TRV-020 `singularityTargetSource`.
public enum SingularityTargetSource: String, Codable, Sendable {
    case warpTarget
    case trackedSystem
}

/// TRV-008 `nextTargetOrdering`.
public enum NextTargetOrdering: String, Codable, Sendable {
    /// C#: wrap through the `destinations` list.
    case destinationList
    /// Palm: scan system indices from the old target with wrap-around.
    case indexScan
}

/// TRV-005 `wormholeSelectionScope`.
public enum WormholeSelectionScope: String, Codable, Sendable {
    case anyWormhole
    case currentSystemOnly
}

/// TRV-062 `arrivalPipelineAfterArrest`.
public enum ArrivalPipelineAfterArrest: String, Codable, Sendable {
    /// C#: the full arrival pipeline.
    case full
    /// Palm: only `Arrival()` (market update), then the news flags.
    case marketOnly
}

/// Travel behaviour switches. Each case of every switch is selected by the ruleset presets below; engine code reads
/// these values and never branches on the ruleset id.
public struct TravelRules: Sendable, Equatable {
    public var monsterRegeneration: MonsterRegeneration = .compoundPerDay
    public var shieldRechargeTiming: ShieldRechargeTiming = .onArrival
    /// RUL-064: per-click engineer repair is `rand(Engineer) >> 1`.
    public var inFlightRepairHalved = false
    /// RUL-065: auto-fuel and auto-repair buy as much as cash allows; a fuel shortfall with auto-repair on skips repair.
    public var arrivalAutoBuyPartial = false
    public var arrivalPipelineOrder: ArrivalPipelineOrder = .windows
    public var warpCheckOrder: WarpCheckOrder = .wildLast
    public var singularitySideEffects: SingularitySideEffects = .windows
    /// RUL-069: encounter checks per trip (clicks 20…1). Palm's `Clicks = 21` is a pre-decremented sentinel.
    public var transitClicks = 20
    /// RUL-118 (MOD-018): the debt warning and the loan reminder can both fire.
    public var debtWarningAndReminder = false
    public var policeRecordDecay: PoliceRecordDecay = .perDayDivision
    public var noClaimTiming: NoClaimTiming = .perDay
    /// TRV-074/079: passenger impatience in IncDays (absent in Palm).
    public var passengerImpatience = true
    /// TRV-076: the Gemulon counter stops at 8 (Palm keeps counting).
    public var invasionStatusCapped = true
    /// TRV-035: the departure clears the news before the day advance (Palm).
    public var newsResetBeforeDayAdvance = false
    /// TRV-037: the fabric-rip percentage draw happens even when the probability is 25 (Palm).
    public var fabricRipDrawFirst = false
    /// TRV-066: the Og egg message appears even without a free shield slot (Palm).
    public var eggMessageWithoutSlot = false
    public var arrivalPipelineAfterArrest: ArrivalPipelineAfterArrest = .full
    public var singularityTargetSource: SingularityTargetSource = .warpTarget
    public var nextTargetOrdering: NextTargetOrdering = .destinationList
    public var wormholeSelectionScope: WormholeSelectionScope = .anyWormhole
    public var tribbleAlgorithm: TribbleAlgorithm = .csharp
    /// RUL-144: villain headline at record ≤ this value.
    public var newsVillainThreshold = -70
    public var newsHeroRule: NewsHeroRule = .atLeast
    public var newsDistantRange: NewsDistantRange = .destinationOK
    public var newsCannedBound: NewsCannedBound = .drawnOnce
    /// RUL-148: Palm drops headlines that do not fit the page (`Newspaper.applyingPageLimit`).
    public var newsPageLimit = false
    public var newsEventOrdering: NewsEventOrdering = .insertion
    public var newsSeedSystem: NewsSeedSystem = .currentSystem
    /// NEWS-035: maximum stored news flags (`nil` = unlimited; Palm 4, `MAXSPECIALNEWSEVENTS − 1`).
    public var newsEventCapacity: Int?
    /// NEWS-005: the newspaper price is checked against cash-to-spend (Palm `ToSpend()`), not cash.
    public var newspaperUsesCashToSpend = false
    /// NEWS-013: the "show newspaper on arrival" option exists (Palm has auto-pay only).
    public var newsAutoShowAvailable = true
    public var scoreFormula: ScoreFormula = .csharp
    public var highScoreBlock: HighScoreBlock = .cheats
    // SCORE-008 (RUL-006): the moon-girl ending flag lives in QuestRules (`flags.quest.moonGirlEnding`).

    /// Windows 2.01 (faithful C# port).
    public static let windows201 = TravelRules()

    /// Modern: Windows 2.01 with the PRD §4.3 fixes in this area (MOD-003 decay, MOD-018 debt notices).
    public static let modern: TravelRules = {
        var r = TravelRules()
        r.debtWarningAndReminder = true
        r.policeRecordDecay = .perWarp
        return r
    }()

    /// Original Palm 1.2.2.
    public static let palm122: TravelRules = {
        var r = TravelRules()
        r.monsterRegeneration = .perWarp
        r.shieldRechargeTiming = .atDeparture
        r.inFlightRepairHalved = true
        r.arrivalAutoBuyPartial = true
        r.arrivalPipelineOrder = .palm
        r.warpCheckOrder = .wildFirst
        r.singularitySideEffects = .palm
        r.debtWarningAndReminder = true
        r.policeRecordDecay = .perWarp
        r.noClaimTiming = .perWarp
        r.passengerImpatience = false
        r.invasionStatusCapped = false
        r.newsResetBeforeDayAdvance = true
        r.fabricRipDrawFirst = true
        r.eggMessageWithoutSlot = true
        r.arrivalPipelineAfterArrest = .marketOnly
        r.singularityTargetSource = .trackedSystem
        r.nextTargetOrdering = .indexScan
        r.wormholeSelectionScope = .currentSystemOnly
        r.tribbleAlgorithm = .palm
        r.newsVillainThreshold = -30
        r.newsHeroRule = .exactly
        r.newsDistantRange = .baseTanksWithStatus
        r.newsCannedBound = .redrawnEachPass
        r.newsPageLimit = true
        r.newsEventOrdering = .palmFixed
        r.newsSeedSystem = .warpSystem
        r.newsEventCapacity = 4
        r.newspaperUsesCashToSpend = true
        r.newsAutoShowAvailable = false
        r.scoreFormula = .palm
        r.highScoreBlock = .reload
        return r
    }()
}
