// SPDX-License-Identifier: GPL-2.0-or-later
// Markets over time: restock countdowns, drift, pressure shuffle, price recalculation (ECO-016, ECO-032…037).

public extension GameState {
    /// ECO-032: `CountDownStart = difficulty + 3`.
    var countDownStart: Int { difficulty.rawValue + 3 }

    /// ECO-033: the system being left gets a fresh countdown.
    mutating func setDepartureCountdown() {
        galaxy.systems[commander.currentSystem].countDown = countDownStart
    }

    /// ECO-011…015: recomputes the market price arrays for `systemID` (C# `CalculatePrices`).
    mutating func calculatePrices(for systemID: Int) {
        let system = galaxy.systems[systemID]
        let criminal = commander.policeRecordScore < -5
        sellPrices = Pricing.sellPrices(in: system, criminal: criminal, ruleset: ruleset, rng: &rng)
        buyPrices = Pricing.buyPrices(sell: sellPrices, in: system, criminal: criminal, traderSkill: skill(.trader),
                                      ruleset: ruleset)
    }

    /// ECO-023: multiplies every sell price by 100/90 without touching buy prices (C# `RecalculateSellPrices`).
    mutating func recalculateSellPrices() {
        sellPrices = sellPrices.map { $0 * 100 / 90 }
    }

    /// ECO-041: the market part of the arrival pipeline — pressures and quantities, then prices for the arrival system.
    mutating func arrivalMarketUpdate(arrival: Int) {
        updatePressuresAndQuantities(arrival: arrival)
        calculatePrices(for: arrival)
    }

    /// ECO-034…037: per-system pressure shuffle and countdown/restock on arrival, in index order (Windows 2.01 order).
    /// `arrival` is the system being arrived at (C# `WarpSystem`), used by the drift port bug (ECO-037).
    mutating func updatePressuresAndQuantities(arrival: Int) {
        let r = ruleset
        let arrivalSystem = galaxy.systems[arrival]
        for i in galaxy.systems.indices {
            // ECO-034 pressure shuffle
            if rng.next(below: 100) < 15 {
                if galaxy.systems[i].pressure == .none {
                    galaxy.systems[i].pressure = SystemPressure(rawValue: rng.next(in: SystemPressure.war.rawValue,
                                                                                   SystemPressure.employment.rawValue + 1)) ?? .none
                } else {
                    galaxy.systems[i].pressure = .none
                }
            }
            // ECO-036 countdown step
            guard galaxy.systems[i].countDown > 0 else { continue }
            galaxy.systems[i].countDown -= 1
            if galaxy.systems[i].countDown > countDownStart {
                galaxy.systems[i].countDown = countDownStart
            } else if galaxy.systems[i].countDown <= 0 {
                galaxy.systems[i].tradeItems = Pricing.initialQuantities(for: galaxy.systems[i], difficulty: difficulty,
                                                                         ruleset: r, rng: &rng)
            } else {
                for (j, item) in r.tables.tradeItems.enumerated() {
                    let tradedHere = r.flags.restockUsesOwnSystemItemTraded
                        ? Pricing.itemTraded(item, in: galaxy.systems[i], ruleset: r)
                        : Pricing.itemTraded(item, in: arrivalSystem, ruleset: r)
                    if tradedHere {
                        galaxy.systems[i].tradeItems[j] = max(0, galaxy.systems[i].tradeItems[j] + rng.next(in: -4, 5))
                    }
                }
            }
        }
    }
}

/// ECO-082: the explainable parts of a sell price.
public struct PriceBreakdown: Sendable, Equatable {
    public var item: TradeItemType
    /// `priceLowTech + tech × priceIncrease`.
    public var base: Int
    /// Price after the government's "wanted" bonus (×4/3), or `base` if not wanted.
    public var afterWanted: Int
    /// After trader activity: × (100 − 2·activity)/100.
    public var afterTraderActivity: Int
    /// After system size: × (100 − size)/100.
    public var afterSize: Int
    /// After the special resource the player knows about (visited systems only).
    public var afterResource: Int
    /// After a pressure (status) price hike ×3/2.
    public var afterPressure: Int
    /// After the 90% criminal factor.
    public var afterCriminal: Int
    /// Actual sell price − `afterCriminal`: the random market fluctuation (and any hidden factor).
    public var fluctuation: Int
    /// Buy price − sell price: the trader-skill (and criminal) markup.
    public var buyMarkup: Int
}

public extension GameState {
    /// ECO-082, using only information visible to the player (known resource; current pressure).
    func priceBreakdown(_ item: TradeItemType) -> PriceBreakdown {
        let spec = ruleset.tables.item(item)
        let sys = currentSystem
        let pol = ruleset.tables.politics(sys.politics)
        let used = Pricing.itemUsed(spec, in: sys, ruleset: ruleset)
        let base = used ? spec.priceLowTech + sys.techLevel.rawValue * spec.priceIncrease : 0
        let wanted = pol.wanted == item ? base * 4 / 3 : base
        let traders = wanted * (100 - 2 * pol.activityTraders.rawValue) / 100
        let size = traders * (100 - sys.size.rawValue) / 100
        let res = sys.knownResource
        let resource = res == spec.resourceLowPrice ? size * 3 / 4 : (res == spec.resourceHighPrice ? size * 4 / 3 : size)
        let pressure = resource > 0 && spec.pressurePriceHike == sys.pressure ? resource * 3 / 2 : resource
        let criminal = commander.policeRecordScore < -5 ? pressure * 90 / 100 : pressure
        let sell = sellPrices[item.rawValue]
        return PriceBreakdown(item: item, base: base, afterWanted: wanted, afterTraderActivity: traders, afterSize: size,
                              afterResource: resource, afterPressure: pressure, afterCriminal: criminal,
                              fluctuation: sell - criminal, buyMarkup: buyPrices[item.rawValue] - sell)
    }
}
