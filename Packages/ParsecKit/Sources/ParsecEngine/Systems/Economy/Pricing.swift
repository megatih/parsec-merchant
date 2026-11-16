// SPDX-License-Identifier: GPL-2.0-or-later
// Market pricing and stock (docs/specs/ECO.md). Integer arithmetic mirrors the source exactly.

public enum Pricing {
    /// C# `StarSystem.ItemTraded`: can be bought here.
    public static func itemTraded(_ item: TradeItemSpec, in system: StarSystem, ruleset: Ruleset) -> Bool {
        let pol = ruleset.tables.politics(system.politics)
        return (item.type != .narcotics || pol.drugsOK) && (item.type != .firearms || pol.firearmsOK)
            && system.techLevel >= item.techProduction
    }

    /// C# `StarSystem.ItemUsed`: can be sold here.
    public static func itemUsed(_ item: TradeItemSpec, in system: StarSystem, ruleset: Ruleset) -> Bool {
        let pol = ruleset.tables.politics(system.politics)
        return (item.type != .narcotics || pol.drugsOK) && (item.type != .firearms || pol.firearmsOK)
            && system.techLevel >= item.techUsage
    }

    /// The resource used by price/stock formulas: hidden until visited unless the ruleset says otherwise (MOD-006).
    static func effectiveResource(_ system: StarSystem, ruleset: Ruleset) -> SpecialResource {
        ruleset.flags.resourcesAffectUnvisitedSystems ? system.specialResource : system.knownResource
    }

    /// C# `TradeItem.StandardPrice` (TradeItem.cs:87). 0 when the item is not used in `system`.
    public static func standardPrice(_ item: TradeItemSpec, in system: StarSystem, ruleset: Ruleset) -> Int {
        guard itemUsed(item, in: system, ruleset: ruleset) else { return 0 }
        let pol = ruleset.tables.politics(system.politics)
        var price = item.priceLowTech + system.techLevel.rawValue * item.priceIncrease
        if pol.wanted == item.type { price = price * 4 / 3 }
        price = price * (100 - 2 * pol.activityTraders.rawValue) / 100
        price = price * (100 - system.size.rawValue) / 100
        let res = effectiveResource(system, ruleset: ruleset)
        if res == item.resourceLowPrice {
            price = price * 3 / 4
        } else if res == item.resourceHighPrice {
            price = price * 4 / 3
        }
        return price
    }

    /// C# `StarSystem.InitializeTradeItems` (StarSystem.cs:84). With `marketQuantitySizeSource == .systemAtItemIndex`
    /// (Palm `InitializeTradeitems`, RUL-032) item i is scaled by the size of system #i from `systemSizes`; an index
    /// not yet generated counts as size 0 (Palm's zero-initialised globals).
    public static func initialQuantities(for system: StarSystem, difficulty: Difficulty, ruleset: Ruleset,
                                         systemSizes: [SystemSize] = [], rng: inout some RandomSource) -> [Int] {
        var qty = Array(repeating: 0, count: ruleset.tables.tradeItems.count)
        let res = effectiveResource(system, ruleset: ruleset)
        let d = difficulty.rawValue
        for (i, item) in ruleset.tables.tradeItems.enumerated() {
            guard itemTraded(item, in: system, ruleset: ruleset) else { qty[i] = 0; continue }
            let size = switch ruleset.flags.economy.marketQuantitySizeSource {
            case .ownSystem: system.size.rawValue
            case .systemAtItemIndex: systemSizes.indices.contains(i) ? systemSizes[i].rawValue : 0
            }
            var q = (size + 1)
                * (rng.next(in: 9, 14) - abs(item.techTopProduction.rawValue - system.techLevel.rawValue))
            if i >= TradeItemType.narcotics.rawValue {
                q = ((q * (5 - d)) / (6 - d)) + 1
            }
            if res == item.resourceLowPrice { q = q * 4 / 3 }
            if res == item.resourceHighPrice { q = q * 3 / 4 }
            if system.pressure == item.pressurePriceHike { q /= 5 }
            q = q - rng.next(below: 10) + rng.next(below: 10)
            qty[i] = max(0, q)
        }
        return qty
    }

    /// C# `Game.CalculatePrices` sell-price part (Game.cs:534). `criminal` = police record < Dubious (−5).
    public static func sellPrices(in system: StarSystem, criminal: Bool, ruleset: Ruleset,
                                  rng: inout some RandomSource) -> [Int] {
        ruleset.tables.tradeItems.map { item in
            var price = standardPrice(item, in: system, ruleset: ruleset)
            if price > 0 {
                if item.pressurePriceHike == system.pressure { price = price * 3 / 2 }
                switch ruleset.flags.economy.priceVariance {
                case .clampedUniform:
                    let variance = min(item.variance, price - 1)
                    price += rng.next(in: -variance, variance + 1)
                case .twoRolls:
                    // RUL-036/ECO-013: Palm `+GetRandom(V) − GetRandom(V)`, left to right; ≤ 0 → not traded.
                    price += rng.next(below: item.variance)
                    price -= rng.next(below: item.variance)
                    if price <= 0 { return 0 }
                }
                if criminal { price = price * 90 / 100 }
            }
            return price
        }
    }

    /// C# `Game.RecalculateBuyPrices` (Game.cs:2960).
    public static func buyPrices(sell: [Int], in system: StarSystem, criminal: Bool, traderSkill: Int,
                                 ruleset: Ruleset) -> [Int] {
        ruleset.tables.tradeItems.enumerated().map { i, item in
            guard itemTraded(item, in: system, ruleset: ruleset) else { return 0 }
            var buy = sell[i]
            if criminal { buy = buy * 100 / 90 }
            buy = buy * (103 + 10 - traderSkill) / 100
            if buy <= sell[i] { buy = sell[i] + 1 }
            return buy
        }
    }
}
