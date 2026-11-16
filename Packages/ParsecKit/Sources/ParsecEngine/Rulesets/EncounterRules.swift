// SPDX-License-Identifier: GPL-2.0-or-later
// Ruleset switches for encounters, opponents, combat and police (RUL-070…099, 102…104, 109…112, 114, 120, 130…140). docs/specs/RUL.md is normative.

/// RUL-130 `policeConstantFamily`: the values behind the code constants named criminal / villain / psychopath.
/// Displayed record thresholds (POL-002) never change; only rules written with these names do.
public struct PoliceConstants: Sendable, Equatable {
    public var criminal: Int
    public var villain: Int
    public var psychopath: Int
    /// C# `Consts.PoliceRecordScoreCriminal/Villain/Psychopath`.
    public static let windows = PoliceConstants(criminal: -30, villain: -70, psychopath: -100)
    /// Palm `CRIMINALSCORE` / `VILLAINSCORE` / `PSYCHOPATHSCORE` (Src/spacetrader.h).
    public static let palm = PoliceConstants(criminal: -10, villain: -30, psychopath: -70)
}

/// RUL-073 `veryRareSelection`.
public enum VeryRareSelection: String, Sendable, Equatable {
    /// C#: uniform over the not-yet-done list.
    case uniformRemaining
    /// Palm: `rand(6)` over all six; a done or ineligible pick yields nothing (ENC-046).
    case allSix
}

/// RUL-075 `policeTries`.
public enum PoliceTriesRule: String, Sendable, Equatable {
    /// C#: psychopath or Wild → 5, else villain → 3, else 1.
    case psychopathFirst
    /// Palm: villain without Wild → 3, else psychopath or Wild → 5, else 1.
    case villainFirst
}

/// RUL-076 `opponentShipRoll`.
public enum OpponentShipRoll: String, Sendable, Equatable {
    /// C#: `rand(total weight of allowed types)`, walk allowed types.
    case allowedWeights
    /// Palm: `rand(100)` over all types' cumulative occurrence; a disallowed result is redrawn (ENC-067).
    case cumulativeRedraw
}

/// RUL-083 `opponentHullRoll`.
public enum OpponentHullRoll: String, Sendable, Equatable {
    /// C#: best of 5 if no shields or `rand(5) == 0`, else full.
    case bestOfFiveUnlessShielded
    /// Palm: full if shielded and `rand(10) ≤ 7`, else best of 5; Mantis forced full after the draws.
    case fullIfShieldedSeventyPercent
}

/// RUL-084 `opponentGenerationOrder`.
public enum OpponentGenerationOrder: String, Sendable, Equatable {
    /// C#: type, crew, gadgets, shields, weapons, hull, cargo.
    case typeCrewGadgetsShieldsWeaponsHullCargo
    /// Palm: type, gadgets, cargo, (fuel), weapons, shields, hull, crew.
    case typeGadgetsCargoWeaponsShieldsHullCrew
}

/// RUL-085 `opponentExtraCrew`.
public enum OpponentExtraCrew: String, Sendable, Equatable {
    /// C#: random non-special mercenaries.
    case nonSpecialMercenaries
    /// Palm: `rand(31)`, any slot.
    case anySlot
}

/// RUL-097 `scoopSource`.
public enum ScoopSource: String, Sendable, Equatable {
    /// C#: D < Normal or `rand(D) == 0`; a unit from the victim's cargo (none if empty).
    case victimCargo
    /// Palm: D < Normal or `rand(D) == 1`; `rand(10)`, re-drawn once if ≥ 5.
    case cheapRandom
}

/// RUL-098 `pirateStealPolicy`.
public enum PirateStealPolicy: String, Sendable, Equatable {
    /// C#: highest trade index first until the pirate's bays are full; added to the pirate.
    case highestIndexFirst
    /// Palm: everything if it fits, else random units; not added to the pirate (POL-083).
    case allOrRandom
}

/// RUL-137 `arrestSequence`.
public enum ArrestSequence: String, Sendable, Equatable {
    /// C#: confiscate → fine or ship sale → debt → interest × term → rec = −5 → IncDays(term).
    case windows
    /// Palm: confiscate → short Arrival → IncDays(term) → fine or ship sale → rec = −5 → debt → interest × term (POL-098).
    case palm
}

/// RUL-140 `bribeComputation`.
public enum BribeComputation: String, Sendable, Equatable {
    /// C#: `ceil(W/BL/diffMod/100) × 100 × k` (Wild, reactor or sculpture), clamped.
    case realCeiling
    /// Palm: `W/(diffMod×BL)` integer, rounded up to 100 by `%`, ×k only with Wild or the reactor, clamped (POL-067).
    case integerModulo
}

/// CMB-069 `continuousAttackRule`.
public enum ContinuousAttackRule: String, Sendable, Equatable {
    /// C#: continuation recomputed every round from the two options; the tick does not re-verify.
    case windows
    /// Palm: Attack/Flee set the flag; a type change keeps AutoAttack only for a flee type; every tick re-verifies.
    case palm
}

// RUL-103 policeRecordDecay lives in TravelRules, RUL-111 wildRequiresRealLaser and ENC-013 special-ship damage in
// QuestRules (one flag per behaviour).

/// Encounter behaviour switches. Each case of every switch is selected by the ruleset presets below; engine code reads
/// these values and never branches on the ruleset id. Defaults are the Windows 2.01 values.
public struct EncounterRules: Sendable, Equatable {
    /// RUL-130 (also RUL-074, 075, 089, 131, 132, 133).
    public var policeConstants = PoliceConstants.windows
    /// RUL-070: post-Marie customs appear after the click loop (one extra click, ENC-004) instead of at click 1.
    public var postMarieCustomsAfterLoop = false
    /// RUL-071: a pirate-band roll while raided becomes a police encounter.
    public var raidedPirateRollBecomesPolice = false
    /// RUL-072: the artifact Mantis roll runs whenever no pirate/police/trader flag is set (also after a failed Kravat roll).
    public var artifactMantisWhenNoBand = false
    /// RUL-073.
    public var veryRareSelection = VeryRareSelection.uniformRemaining
    /// RUL-075.
    public var policeTries = PoliceTriesRule.psychopathFirst
    /// RUL-076.
    public var opponentShipRoll = OpponentShipRoll.allowedWeights
    /// RUL-077: the backwards cumulative equipment walk (`k < sum`).
    public var opponentEquipmentRollBug = false
    /// RUL-078: opponent weapons and shields may repeat (gadgets still skip owned types).
    public var opponentWeaponsShieldsMayRepeat = false
    /// RUL-079: the extra weapon also depends on difficulty ≥ Hard.
    public var opponentWeaponCountDifficulty = false
    /// RUL-080: opponents get cargo only when bays (incl. extra bays) exceed this value.
    public var opponentCargoMinBays = 0
    /// RUL-081: every cargo-carrying opponent (police included) gets at least 1 unit.
    public var policeCargoMinimum = false
    /// RUL-082: famous captains' reflective shield count (nil = the Wasp's slot count).
    public var famousCaptainShieldCount: Int?
    /// RUL-083.
    public var opponentHullRoll = OpponentHullRoll.bestOfFiveUnlessShielded
    /// RUL-084.
    public var opponentGenerationOrder = OpponentGenerationOrder.typeCrewGadgetsShieldsWeaponsHullCargo
    /// RUL-085.
    public var opponentExtraCrew = OpponentExtraCrew.nonSpecialMercenaries
    /// RUL-086: police that would attack demand surrender when villain ≤ rec < −5.
    public var policeSurrenderState = true
    /// RUL-087: police without weapons still attack criminals.
    public var unarmedPoliceAttack = false
    /// RUL-088: a lawful commander is inspected on `rand(40) == lawfulInspectionRoll`.
    public var lawfulInspectionRoll = 0
    /// ENC-106: the clean / lawful inspection draw is made even when already inspected.
    public var inspectionDrawWhenInspected = false
    /// ENC-103 / ENC-106: the "opponent outclasses the player" check turns a flee into attack after the reaction (Palm draws first).
    public var outclassCheckAfterReaction = false
    /// RUL-090: the skill boosting weapon damage.
    public var damageSkill = SkillType.fighter
    /// RUL-091 (kept as designed #14): weapons that can hurt the Scarab.
    public var scarabVulnerableWeapons: [WeaponType] = [.pulseLaser, .morgansLaser, .quantumDisruptor]
    /// RUL-092: shots at a surrendering ship use the fleeing to-hit modifier.
    public var surrenderingTargetShotAsFleeing = true
    /// RUL-094: bounty equipment uses base prices instead of the trader-discounted local price.
    public var bountyEquipmentBasePrice = false
    /// RUL-093 / CMB-072: the bounty event (dialog) is shown only at record ≥ −5 even when credited regardless.
    public var bountyEventRequiresRecord = false
    /// RUL-095.
    public var famousCaptainKillCountsTrader = true
    /// RUL-096: Palm applies −2/−1 when Plunder is pressed; no reputation, kill count or bounty.
    public var plunderPenaltyOnPress = false
    /// RUL-097.
    public var scoopSource = ScoopSource.victimCargo
    /// RUL-098.
    public var pirateStealPolicy = PirateStealPolicy.highestIndexFirst
    /// RUL-099: the escape pod resets a finished Scarab hull upgrade (status 3 → 0).
    public var escapePodLosesHullUpgrade = false
    /// RUL-104: whether the hardened hull halves damage at all (scope: flat flag `hardenedHullProtectsPlayerOnly`).
    public var hardenedHullHalvesDamage = true
    /// CMB-030: the damage cap divides the defender's base hull (the upgraded hull only for the player with Scarab 3).
    public var hullDamageCapUsesBaseHull = false
    /// RUL-110: whether the Marie Celeste has a click and system restriction at all (which system: flat flag).
    public var marieCelesteRestricted = true
    /// CMB-051: the opponent escape check runs only when the player is not fleeing.
    public var opponentEscapeOnlyWhenPlayerStays = false
    /// CMB-059: the stance update draws `rand(10)` only where needed (C# draws `rand(100)` every round).
    public var stanceUpdateDrawsOnDemand = false
    /// CMB-069.
    public var continuousAttackRule = ContinuousAttackRule.windows
    /// ENC-147 `attackReverification`: every police type confirms and pays the clamp on every attack click; every
    /// trader type except flee re-rolls; captains pay the clamp on every click; nothing-illegal tests goods only.
    public var attackReverification = false
    /// POL-054: the nothing-illegal confirmation differs per action (attack: goods; flee: + Wild and reactor; bribe: + Wild).
    public var nothingIllegalPerAction = false
    /// RUL-131…135 Palm style flee penalties (RUL-134, RUL-135).
    public var palmFleePenalties = false
    /// RUL-136: Palm arrest fine `(1 + (W×m/100)/500) × 500`.
    public var arrestFineDividesInSteps = false
    /// RUL-137.
    public var arrestSequence = ArrestSequence.windows
    /// POL-107 / POL-110: Palm's escape-pod order (short Arrival first; reactor and artifact simply lost; IncDays(3) then Flea).
    public var escapePodPalmSequence = false
    /// RUL-138: arrest and yield keep the impounded goods' cost basis (submit still clears it).
    public var impoundedGoodsKeepCostBasis = false
    /// RUL-139: submitting with only the reactor (no Wild) aboard confiscates it without arrest; the warning tests status > 1.
    public var reactorConfiscatedOnSubmit = false
    /// POL-061: the inspection fine is integer-divided and rounded up to 50 by `%`.
    public var inspectionFineIntegerRounding = false
    /// RUL-140.
    public var bribeComputation = BribeComputation.realCeiling
    /// POL-073: yielding without Wild or the reactor needs no confirmation.
    public var yieldWithoutConfirmation = false

    /// Windows 2.01 (faithful C# port).
    public static let windows201 = EncounterRules()

    /// Modern: Windows 2.01 with the PRD §4.3 fixes in this area (MOD-003, MOD-011; the other MODs are flat flags).
    public static let modern: EncounterRules = {
        var r = EncounterRules()
        return r
    }()

    /// Original Palm 1.2.2.
    public static let palm122: EncounterRules = {
        var r = EncounterRules()
        r.policeConstants = .palm
        r.postMarieCustomsAfterLoop = true
        r.raidedPirateRollBecomesPolice = true
        r.artifactMantisWhenNoBand = true
        r.veryRareSelection = .allSix
        r.policeTries = .villainFirst
        r.opponentShipRoll = .cumulativeRedraw
        r.opponentEquipmentRollBug = true
        r.opponentWeaponsShieldsMayRepeat = true
        r.opponentWeaponCountDifficulty = true
        r.opponentCargoMinBays = 5
        r.policeCargoMinimum = true
        r.famousCaptainShieldCount = 3
        r.opponentHullRoll = .fullIfShieldedSeventyPercent
        r.opponentGenerationOrder = .typeGadgetsCargoWeaponsShieldsHullCrew
        r.opponentExtraCrew = .anySlot
        r.policeSurrenderState = false
        r.unarmedPoliceAttack = true
        r.lawfulInspectionRoll = 1
        r.inspectionDrawWhenInspected = true
        r.outclassCheckAfterReaction = true
        r.damageSkill = .engineer
        r.scarabVulnerableWeapons = [.pulseLaser, .morgansLaser]
        r.surrenderingTargetShotAsFleeing = false
        r.bountyEquipmentBasePrice = true
        r.bountyEventRequiresRecord = true
        r.famousCaptainKillCountsTrader = false
        r.plunderPenaltyOnPress = true
        r.scoopSource = .cheapRandom
        r.pirateStealPolicy = .allOrRandom
        r.escapePodLosesHullUpgrade = true
        r.hardenedHullHalvesDamage = false
        r.hullDamageCapUsesBaseHull = true
        r.marieCelesteRestricted = false
        r.opponentEscapeOnlyWhenPlayerStays = true
        r.stanceUpdateDrawsOnDemand = true
        r.continuousAttackRule = .palm
        r.attackReverification = true
        r.nothingIllegalPerAction = true
        r.palmFleePenalties = true
        r.arrestFineDividesInSteps = true
        r.arrestSequence = .palm
        r.escapePodPalmSequence = true
        r.impoundedGoodsKeepCostBasis = true
        r.reactorConfiscatedOnSubmit = true
        r.inspectionFineIntegerRounding = true
        r.bribeComputation = .integerModulo
        r.yieldWithoutConfirmation = true
        return r
    }()
}
