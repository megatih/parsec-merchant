// SPDX-License-Identifier: GPL-2.0-or-later
// Ruleset switches for markets, trade in orbit, insurance, ships, equipment, crew and bank (RUL-032…061, 101, 105…108, 113, 115…119). docs/specs/RUL.md is normative.

/// Economy behaviour switches. Each case of every switch is selected by the ruleset presets below; engine code reads
/// these values and never branches on the ruleset id. Defaults are the Windows 2.01 values.
public struct EconomyRules: Sendable, Equatable {
    // MARK: Markets (RUL-032…036)

    /// RUL-032: which system's size scales the initial quantity.
    public enum QuantitySizeSource: Sendable, Equatable {
        /// The system's own size.
        case ownSystem
        /// Palm bug: the size of the system whose index equals the trade-item index.
        case systemAtItemIndex
    }
    public var marketQuantitySizeSource = QuantitySizeSource.ownSystem

    /// RUL-033: restock drift per traded item.
    public enum DriftDistribution: Sendable, Equatable {
        /// `GetRandom(-4, 5)`.
        case uniform
        /// `GetRandom(5) - GetRandom(5)`.
        case triangular
    }
    public var quantityDriftDistribution = DriftDistribution.uniform

    /// RUL-034: during drift, items the system cannot trade are set to 0 (Palm) instead of left unchanged.
    public var zeroUntradeableOnDrift = false

    /// RUL-035: order of the pressure shuffle and the quantity pass on arrival.
    public enum StatusShuffleOrder: Sendable, Equatable {
        /// Per system: pressure, then countdown/quantities.
        case interleaved
        /// Palm `ShuffleStatus` over all systems, then `ChangeQuantities` over all systems.
        case statusesFirst
    }
    public var statusShuffleOrder = StatusShuffleOrder.interleaved

    /// RUL-036: random sell-price variance.
    public enum PriceVariance: Sendable, Equatable {
        /// Uniform in [−v, v] with v = min(V, price − 1).
        case clampedUniform
        /// Palm: `+GetRandom(V) − GetRandom(V)`; a result ≤ 0 means the item is not traded.
        case twoRolls
    }
    public var priceVariance = PriceVariance.clampedUniform

    /// ECO-043/BNK-055: how money available to spend is computed.
    public enum CashToSpendRule: Sendable, Equatable {
        /// C#: cash − all current costs when reserving (may be negative).
        case reserveAllCosts
        /// Palm: max(0, cash − mercenaries − insurance) when reserving.
        case reserveCrewAndInsurance
    }
    public var cashToSpend = CashToSpendRule.reserveAllCosts

    /// RUL-043: dock-dump quantity cap.
    public enum DumpCap: Sendable, Equatable {
        /// `cashToSpend / (5(D+1))`.
        case divided
        /// Palm precedence bug: `toSpend / 5 × (D+1)`.
        case precedenceBug
    }
    public var dumpQuantityCap = DumpCap.divided

    /// ECO-058: jettisoning a whole holding first asks for a confirmation showing its cost basis (Palm).
    public var dumpAllConfirmShowsCostBasis = false

    // MARK: Trade in orbit (RUL-038…042, RUL-108)

    /// RUL-038: the favourable roll is `rand(100) ≤ threshold` (Palm) instead of `<`.
    public var tradeInOrbitThresholdInclusive = false

    /// RUL-039: rounding of the in-orbit price.
    public enum OrbitRounding: Sendable, Equatable {
        /// `Math.Round(p × adj / r) × r` with banker's rounding.
        case bankers
        /// Palm: truncate `p × adj`; trader sells `/r×r`, trader buys `(/r + 1)×r`.
        case truncate
    }
    public var tradeInOrbitRounding = OrbitRounding.bankers

    /// RUL-040: the cap on units sold to a trader.
    public enum OrbitSellCap: Sendable, Equatable {
        /// The trader's free bays; the trader's cargo is unchanged.
        case traderFreeBays
        /// Palm: the trader ship type's base bays; the trader's cargo of that item is overwritten.
        case traderTypeBays
    }
    public var tradeInOrbitSellCap = OrbitSellCap.traderFreeBays

    /// RUL-041: the in-orbit price is written back into the market price arrays (Palm).
    public var tradeInOrbitMutatesMarketPrices = false

    /// RUL-042: a cloaked player still gets the trade-in-orbit roll (Palm TRADERIGNORE path).
    public var tradeInOrbitWhileCloaked = false

    /// ECO-062: item pick for trade in orbit.
    public enum OrbitItemPick: Sendable, Equatable {
        /// C#: one `GetRandom(10)`, then advance cyclically.
        case advanceFromRandom
        /// Palm: up to 10 `GetRandom(10)` tries, then a sequential scan from 0.
        case tenTriesThenScan
    }
    public var tradeInOrbitItemPick = OrbitItemPick.advanceFromRandom

    // MARK: Insurance (RUL-044…046)

    /// RUL-044: daily insurance formula.
    public enum InsuranceFormula: Sendable, Equatable {
        /// `(int)max(1, value × 0.0025 × (100 − NoClaim)/100)` in double precision.
        case doublePrecision
        /// Palm: `max(1, ((value × 5)/2000) × (100 − min(NoClaim, 90))/100)` in integers.
        case integer
    }
    public var insuranceFormula = InsuranceFormula.doublePrecision

    // RUL-045 `noClaimTiming` lives in TravelRules (it runs in the warp and IncDays pipeline).

    /// RUL-046: buying insurance resets no-claim.
    public var buyInsuranceResetsNoClaim = true

    /// BNK-019: the "pay back everything" amount is additionally capped (Palm `PayBack(99999)`).
    public var repayAllCap: Int?

    // MARK: Ships and equipment (RUL-047…056, RUL-117, RUL-119)

    /// RUL-047: fuel compactor effect.
    public enum FuelCompactorRule: Sendable, Equatable {
        /// Tanks + 3.
        case addsThree
        /// Palm: tanks = 18.
        case setsEighteen
    }
    public var fuelCompactorRule = FuelCompactorRule.addsThree

    /// RUL-117 (MOD-017): read the ship table's fuel and repair cost columns swapped (Modern restores Palm values from
    /// the C# table). Custom designs keep their designer costs.
    public var swapFuelAndRepairColumns = false

    /// RUL-056: fuel deduction in the trade-in value.
    public enum TradeInFuelTerm: Sendable, Equatable {
        /// (tanks incl. compactor − fuel) × fuel cost.
        case actualTanks
        /// Palm: (type base tanks − min(fuel, tanks)) × fuel cost.
        case baseTanks
    }
    public var tradeInFuelTerm = TradeInFuelTerm.actualTanks

    /// RUL-119 (MOD-019): worth is the trade-in value plus cargo cost basis (Palm `CurrentWorth`), not the list price.
    public var worthUsesTradeInValue = false

    /// RUL-052: ship prices get the trader discount `Price × (100 − Trader)/100` (Palm; 0 becomes 1).
    public var shipTraderDiscount = false

    /// RUL-053/054/055, SHP-037: ship trade flow.
    public enum ShipTradeFlow: Sendable, Equatable {
        /// C# `TradeShip`: transfer prices SellPrice×110/90, escape pod optional at 200, Lightning keeps its charge.
        case windows
        /// Palm: Lightning 30000, Compactor 20000, Morgan's 33333; pod and insurance kept free; Lightning uncharged;
        /// reactor checked before quarters.
        case palm
    }
    public var shipTradeFlow = ShipTradeFlow.windows

    /// SHP-050: the escape-pod offer tests money to spend instead of cash.
    public var escapePodPurchaseUsesToSpend = false

    // MARK: Skills (RUL-048…051, RUL-105)

    /// RUL-048: cloaking device pilot bonus.
    public var cloakPilotBonus = 3

    /// RUL-049: effective-skill computation.
    public enum SkillComputation: Sendable, Equatable {
        /// C# `Ship.Skills`: max(1, adjust(best)) + 3 per boosting gadget (+1 trader after Jarek, after adjustment).
        case adjustThenGadgets
        /// Palm: adjust(best of crew slots up to the first vacancy + gadget bonus once per type (+1 trader after Jarek)).
        case gadgetsThenAdjust
    }
    public var skillComputation = SkillComputation.adjustThenGadgets

    /// RUL-050: skill adjustment on Hard (kept as designed: −1; Palm 0).
    public var hardSkillAdjustment = -1

    /// CRW-054/055: random skill change algorithm.
    public enum RandomSkillChange: Sendable, Equatable {
        /// C# `ChangeRandomSkill`: pick from the eligible list (cap from `randomSkillIncreaseReachesTen`).
        case eligibleList
        /// Palm `IncreaseRandomSkill`/`DecreaseRandomSkill`: re-draw `GetRandom(4)` until eligible; no-op when all ≥ 10
        /// (and, a documented deviation, when no skill is eligible).
        case redraw
    }
    public var randomSkillChange = RandomSkillChange.eligibleList

    // MARK: Crew (RUL-057…061, RUL-116)

    /// RUL-057: Jarek and Wild aboard contribute skills (C#) or are skill-less passengers (Palm). In every ruleset they
    /// take one quarter each.
    public var passengersAsCrew = true

    /// RUL-059: Zeethibal is paid the normal wage (Palm).
    public var zeethibalPaid = false

    /// CRW-033: the mercenary cost skips vacant slots (Palm) instead of stopping at the first vacancy.
    public var mercenaryCostSkipsVacancies = false

    /// CRW-028: at most this many mercenaries are offered per system (Palm 1; nil = all).
    public var mercenariesOfferedPerSystem: Int?

    /// RUL-060: a fired mercenary relocates to a random system within range (C#) or stays (Palm).
    public var firedMercenaryRelocates = true

    /// RUL-116 (MOD-016): mercenaries lost to arrest or the escape pod relocate like fired ones.
    public var lostMercenariesRelocate = false

    /// CRW-048: on arrest, mercenaries leave when any is aboard (Palm) instead of only when more than one is.
    public var arrestClearsAnyMercenary = false

    // RUL-061 `passengerImpatience` lives in TravelRules (IncDays).

    /// CRW-061: Palm recalculates buy prices after Captain Huie's training (C# does not: CRW-060).
    public var recalculateBuyPricesAfterHuie = false

    /// CRW-005: maximum commander name length (Palm `NAMELEN` 20; nil = unlimited).
    public var commanderNameMaxLength: Int?

    // RUL-037 `wildDeliveredRecord` and RUL-115 `sellPriceRecalc` live in QuestRules; RUL-118 debt notices are
    // `travel.debtWarningAndReminder` (+ `travel.arrivalPipelineAfterArrest`); BNK-048's pod order is
    // `encounter.escapePodPalmSequence`; BNK-058's Wild-first check is `travel.warpCheckOrder`.

    public init() {}

    /// Windows 2.01 (faithful C# port).
    public static let windows201 = EconomyRules()

    /// Modern: Windows 2.01 with the PRD §4.3 fixes in this area (MOD-015…019).
    public static let modern: EconomyRules = {
        var r = EconomyRules()
        r.lostMercenariesRelocate = true
        r.swapFuelAndRepairColumns = true
        r.worthUsesTradeInValue = true
        return r
    }()

    /// Original Palm 1.2.2. Palm tables (Palm122Tables) carry Palm-native fuel/repair columns, so no swap.
    public static let palm122: EconomyRules = {
        var r = EconomyRules()
        r.marketQuantitySizeSource = .systemAtItemIndex
        r.quantityDriftDistribution = .triangular
        r.zeroUntradeableOnDrift = true
        r.statusShuffleOrder = .statusesFirst
        r.priceVariance = .twoRolls
        r.cashToSpend = .reserveCrewAndInsurance
        r.dumpQuantityCap = .precedenceBug
        r.dumpAllConfirmShowsCostBasis = true
        r.tradeInOrbitThresholdInclusive = true
        r.tradeInOrbitRounding = .truncate
        r.tradeInOrbitSellCap = .traderTypeBays
        r.tradeInOrbitMutatesMarketPrices = true
        r.tradeInOrbitWhileCloaked = true
        r.tradeInOrbitItemPick = .tenTriesThenScan
        r.insuranceFormula = .integer
        r.buyInsuranceResetsNoClaim = false
        r.repayAllCap = 99_999
        r.fuelCompactorRule = .setsEighteen
        r.tradeInFuelTerm = .baseTanks
        r.worthUsesTradeInValue = true
        r.shipTraderDiscount = true
        r.shipTradeFlow = .palm
        r.escapePodPurchaseUsesToSpend = true
        r.cloakPilotBonus = 2
        r.skillComputation = .gadgetsThenAdjust
        r.hardSkillAdjustment = 0
        r.randomSkillChange = .redraw
        r.passengersAsCrew = false
        r.zeethibalPaid = true
        r.mercenaryCostSkipsVacancies = true
        r.mercenariesOfferedPerSystem = 1
        r.firedMercenaryRelocates = false
        r.arrestClearsAnyMercenary = true
        r.commanderNameMaxLength = 20
        r.recalculateBuyPricesAfterHuie = true
        return r
    }()
}
