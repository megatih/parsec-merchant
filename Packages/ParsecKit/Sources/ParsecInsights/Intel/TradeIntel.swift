// SPDX-License-Identifier: GPL-2.0-or-later
// Quotes, estimates and recommendations (docs/specs/INT.md §3 and §5, INT-012…016, INT-019…023, INT-028).
// Inputs are only the IntelBook and the IntelSnapshot (fairness rule). Integer math; ties end in the lower index.
import ParsecEngine

/// INT-012: where a quote's numbers come from.
public enum QuoteSource: Sendable, Equatable {
    /// The current market while docked.
    case live
    /// The newest observation, made on `day`.
    case observed(day: Int)
    /// The classic standard-price estimate (INT-013).
    case estimate
}

/// INT-014: how old a quote is.
public enum Staleness: String, Sendable, Equatable {
    case live, fresh, old, estimate
}

/// INT-012: a price quote for one item at one system. A price of 0 (not traded or not bought there) is nil.
public struct PriceQuote: Sendable, Equatable {
    public var item: TradeItemType
    public var system: Int
    public var sell: Int?
    public var buy: Int?
    public var stock: Int?
    public var source: QuoteSource
    public var age: Int?
    public var staleness: Staleness
    public var pressureHint: PressureHint?

    public init(item: TradeItemType, system: Int, sell: Int?, buy: Int?, stock: Int?, source: QuoteSource, age: Int?,
                staleness: Staleness, pressureHint: PressureHint?) {
        self.item = item
        self.system = system
        self.sell = sell
        self.buy = buy
        self.stock = stock
        self.source = source
        self.age = age
        self.staleness = staleness
        self.pressureHint = pressureHint
    }
}

/// INT-019: a buy recommendation for a target.
public struct TradeRecommendation: Sendable, Equatable {
    public var item: TradeItemType
    public var profitPerBay: Int
    public var units: Int
    public var projectedProfit: Int
    public var quoteSource: QuoteSource
    public var staleness: Staleness

    public init(item: TradeItemType, profitPerBay: Int, units: Int, projectedProfit: Int, quoteSource: QuoteSource, staleness: Staleness) {
        self.item = item
        self.profitPerBay = profitPerBay
        self.units = units
        self.projectedProfit = projectedProfit
        self.quoteSource = quoteSource
        self.staleness = staleness
    }
}

/// INT-020: the projected value of the hold at a system.
public struct HoldValue: Sendable, Equatable {
    public var revenue: Int
    public var costBasis: Int
    public var profit: Int
    public var unsellable: [TradeItemType]
    public var usesEstimates: Bool

    public init(revenue: Int, costBasis: Int, profit: Int, unsellable: [TradeItemType], usesEstimates: Bool) {
        self.revenue = revenue
        self.costBasis = costBasis
        self.profit = profit
        self.unsellable = unsellable
        self.usesEstimates = usesEstimates
    }
}

/// INT-021: a destination recommendation for the hold.
public struct DestinationRecommendation: Sendable, Equatable {
    public var system: Int
    public var profit: Int
    public var distance: Int
    public var usesEstimates: Bool

    public init(system: Int, profit: Int, distance: Int, usesEstimates: Bool) {
        self.system = system
        self.profit = profit
        self.distance = distance
        self.usesEstimates = usesEstimates
    }
}

/// INT-022: where to sell a held item.
public struct SellAdvice: Sendable, Equatable {
    public var item: TradeItemType
    /// Profit per unit if sold here now (`sellPrice − priceCargo / held`); nil when not sold here.
    public var herePerUnit: Int?
    /// The best other system in range by known or estimated sell price.
    public var bestSystem: Int?
    public var bestSell: Int?
    public var bestPerUnit: Int?
    public var bestSource: QuoteSource?
    public var bestAge: Int?

    public init(item: TradeItemType, herePerUnit: Int?, bestSystem: Int? = nil, bestSell: Int? = nil, bestPerUnit: Int? = nil,
                bestSource: QuoteSource? = nil, bestAge: Int? = nil) {
        self.item = item
        self.herePerUnit = herePerUnit
        self.bestSystem = bestSystem
        self.bestSell = bestSell
        self.bestPerUnit = bestPerUnit
        self.bestSource = bestSource
        self.bestAge = bestAge
    }
}

/// INT-028: why a system matches the "sells <item>" search filter.
public enum SellsMatch: Sendable, Equatable {
    /// The newest observation (or the live market) shows the item for sale with stock.
    case observed
    /// Never observed; the public tech/government rule says it is traded there.
    case estimate
}

/// INT-012…023: the pure trade-intelligence namespace.
public enum TradeIntel {
    /// INT-013: the classic standard price of `item` at `system` (Palm Average Price List / C# Target column), with the
    /// special resource counted only once visited, in every ruleset. 0 when the item is not sold there.
    public static func estimate(item: TradeItemType, system: Int, snapshot: IntelSnapshot) -> Int {
        let ruleset = snapshot.ruleset
        return Pricing.standardPrice(ruleset.tables.item(item), in: snapshot.publicSystem(system), ruleset: ruleset)
    }

    static func positive(_ v: Int) -> Int? { v > 0 ? v : nil }

    /// INT-012 / INT-014 / INT-016.
    public static func quote(item: TradeItemType, system: Int, book: IntelBook, snapshot: IntelSnapshot) -> PriceQuote {
        let i = item.rawValue
        if system == snapshot.currentSystem, snapshot.isDocked {
            return PriceQuote(item: item, system: system, sell: positive(snapshot.sellPrices[i]),
                              buy: positive(snapshot.buyPrices[i]), stock: snapshot.stock[i], source: .live, age: 0,
                              staleness: .live, pressureHint: nil)
        }
        let intel = book.intel(system)
        let hike = snapshot.ruleset.tables.item(item).pressurePriceHike
        let hint = intel.pressureHint.flatMap { $0.pressure == hike && $0.pressure != .none ? $0 : nil }
        if let obs = intel.latest {
            let age = snapshot.day - obs.day
            return PriceQuote(item: item, system: system, sell: positive(obs.sell[i]), buy: positive(obs.buy[i]),
                              stock: obs.stock[i], source: .observed(day: obs.day), age: age,
                              staleness: age <= IntelPolicy.recentDays ? .fresh : .old,
                              pressureHint: hint.flatMap { $0.day > obs.day ? $0 : nil })
        }
        return PriceQuote(item: item, system: system, sell: positive(estimate(item: item, system: system, snapshot: snapshot)),
                          buy: nil, stock: nil, source: .estimate, age: nil, staleness: .estimate, pressureHint: hint)
    }

    /// INT-015: target sell − here buy, when the item is bought here (docked) and the target quote has a sell price.
    public static func profitPerBay(item: TradeItemType, target: Int, book: IntelBook, snapshot: IntelSnapshot) -> Int? {
        let buy = snapshot.buyPrices[item.rawValue]
        guard snapshot.isDocked, buy > 0,
              let sell = quote(item: item, system: target, book: book, snapshot: snapshot).sell else { return nil }
        return sell - buy
    }

    /// INT-019: the best buys here for `target`, by profit per bay (then item).
    public static func bestBuys(for target: Int, book: IntelBook, snapshot: IntelSnapshot, limit: Int = 3) -> [TradeRecommendation] {
        guard target != snapshot.currentSystem, snapshot.systems.indices.contains(target) else { return [] }
        var out: [TradeRecommendation] = []
        for item in TradeItemType.allCases {
            let i = item.rawValue
            guard snapshot.buyPrices[i] > 0, snapshot.stock[i] > 0,
                  let profit = profitPerBay(item: item, target: target, book: book, snapshot: snapshot), profit > 0 else { continue }
            let q = quote(item: item, system: target, book: book, snapshot: snapshot)
            let units = snapshot.maxBuy[i]
            out.append(TradeRecommendation(item: item, profitPerBay: profit, units: units, projectedProfit: profit * units,
                                           quoteSource: q.source, staleness: q.staleness))
        }
        out.sort { $0.profitPerBay != $1.profitPerBay ? $0.profitPerBay > $1.profitPerBay : $0.item.rawValue < $1.item.rawValue }
        return Array(out.prefix(max(0, limit)))
    }

    /// INT-020: revenue, cost basis and profit of selling the hold at `system`.
    public static func holdValue(at system: Int, book: IntelBook, snapshot: IntelSnapshot) -> HoldValue {
        var value = HoldValue(revenue: 0, costBasis: 0, profit: 0, unsellable: [], usesEstimates: false)
        for item in TradeItemType.allCases where snapshot.cargo[item.rawValue] > 0 {
            let q = quote(item: item, system: system, book: book, snapshot: snapshot)
            guard let sell = q.sell else {
                value.unsellable.append(item)
                continue
            }
            value.revenue += snapshot.cargo[item.rawValue] * sell
            value.costBasis += snapshot.priceCargo[item.rawValue]
            if q.source == .estimate { value.usesEstimates = true }
        }
        value.profit = value.revenue - value.costBasis
        return value
    }

    /// INT-021: systems in range where the hold sells at a profit, by profit, then distance, then index.
    public static func bestDestinations(book: IntelBook, snapshot: IntelSnapshot, limit: Int = 3) -> [DestinationRecommendation] {
        guard snapshot.hasCargo else { return [] }
        var out: [DestinationRecommendation] = []
        for system in snapshot.destinations where system != snapshot.currentSystem {
            let v = holdValue(at: system, book: book, snapshot: snapshot)
            guard v.profit > 0 else { continue }
            out.append(DestinationRecommendation(system: system, profit: v.profit,
                                                 distance: snapshot.distance(snapshot.currentSystem, system),
                                                 usesEstimates: v.usesEstimates))
        }
        out.sort {
            if $0.profit != $1.profit { return $0.profit > $1.profit }
            if $0.distance != $1.distance { return $0.distance < $1.distance }
            return $0.system < $1.system
        }
        return Array(out.prefix(max(0, limit)))
    }

    /// INT-022: profit per unit here and the best other system in range for a held item; nil when not held.
    public static func sellAdvice(item: TradeItemType, book: IntelBook, snapshot: IntelSnapshot) -> SellAdvice? {
        let i = item.rawValue
        let held = snapshot.cargo[i]
        guard held > 0 else { return nil }
        let basis = snapshot.priceCargo[i] / held
        let here = snapshot.isDocked && snapshot.sellPrices[i] > 0 ? snapshot.sellPrices[i] - basis : nil
        var advice = SellAdvice(item: item, herePerUnit: here)
        var bestKey: (sell: Int, distance: Int, system: Int)?
        for system in snapshot.destinations where system != snapshot.currentSystem {
            let q = quote(item: item, system: system, book: book, snapshot: snapshot)
            guard let sell = q.sell else { continue }
            let d = snapshot.distance(snapshot.currentSystem, system)
            if let b = bestKey, !(sell > b.sell || (sell == b.sell && (d, system) < (b.distance, b.system))) { continue }
            bestKey = (sell, d, system)
            advice.bestSystem = system
            advice.bestSell = sell
            advice.bestPerUnit = sell - basis
            advice.bestSource = q.source
            advice.bestAge = q.age
        }
        return advice
    }

    /// INT-028: whether `system` matches "sells <item>"; nil when it does not.
    public static func sells(item: TradeItemType, system: Int, book: IntelBook, snapshot: IntelSnapshot) -> SellsMatch? {
        let i = item.rawValue
        if system == snapshot.currentSystem, snapshot.isDocked {
            return snapshot.buyPrices[i] > 0 && snapshot.stock[i] > 0 ? .observed : nil
        }
        if let obs = book.intel(system).latest { return obs.buy[i] > 0 && obs.stock[i] > 0 ? .observed : nil }
        let ruleset = snapshot.ruleset
        return Pricing.itemTraded(ruleset.tables.item(item), in: snapshot.publicSystem(system), ruleset: ruleset) ? .estimate : nil
    }
}
