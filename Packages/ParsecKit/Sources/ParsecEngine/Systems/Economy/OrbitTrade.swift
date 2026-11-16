// SPDX-License-Identifier: GPL-2.0-or-later
// Trade in orbit with traders (ECO-059…073, ECO-081).

/// Who sells to whom.
public enum OrbitTradeDirection: String, Codable, Sendable {
    /// The trader sells to the player (EncounterType.traderSell).
    case traderSells
    /// The trader buys from the player (EncounterType.traderBuy).
    case traderBuys
}

/// The pending trade-in-orbit decision (ECO-081).
public struct OrbitTradeOffer: Codable, Sendable, Equatable {
    public var direction: OrbitTradeDirection
    public var item: TradeItemType
    public var unitPrice: Int
    public var maxQuantity: Int
    public var unitsAvailable: Int
    public var costBasisPerUnit: Int
}

public enum OrbitTrade {
    /// C# `Math.Round`: round half to even (banker's rounding).
    static func roundHalfEven(_ x: Double) -> Int { Int(x.rounded(.toNearestOrEven)) }

    /// ECO-063/064: the in-orbit unit price after the adjustment roll.
    public static func price(item spec: TradeItemType, marketPrice: Int, direction: OrbitTradeDirection, ruleset: Ruleset,
                             rng: inout some RandomSource) -> Int {
        let t = ruleset.tables.item(spec)
        let rules = ruleset.flags.economy
        let illegal = spec.isIllegal
        let chance = illegal ? 45 : 10
        // RUL-038: Palm tests `GetRandom(100) <= 45 / <= 10`.
        let draw = rng.next(below: 100)
        let roll = rules.tradeInOrbitThresholdInclusive ? draw <= chance : draw < chance
        let adj: Double = switch direction {
        case .traderSells: roll ? 1.1 : (illegal ? 0.8 : 0.9)
        case .traderBuys: roll ? (illegal ? 0.8 : 0.9) : 1.1
        }
        let rounded: Int
        switch rules.tradeInOrbitRounding {
        case .bankers:
            rounded = roundHalfEven(Double(marketPrice) * adj / Double(t.roundOff)) * t.roundOff
        case .truncate:
            // RUL-039/ECO-066: Palm truncates `price × adj`; the trader buying rounds up to the next multiple.
            let p = Int(Double(marketPrice) * adj)
            rounded = direction == .traderSells ? p / t.roundOff * t.roundOff : (p / t.roundOff + 1) * t.roundOff
        }
        return min(t.maxTradePrice, max(t.minTradePrice, rounded))
    }
}

public extension GameState {
    /// ECO-060: items a ship could trade in orbit. `isTraderShip` selects the buy price (trader's goods) vs sell price.
    func tradeableItems(in ship: Ship, isTraderShip: Bool) -> [TradeItemType] {
        let criminal = commander.policeRecordScore < -5
        return TradeItemType.allCases.filter { item in
            let i = item.rawValue
            let price = isTraderShip ? buyPrices[i] : sellPrices[i]
            return ship.cargo[i] > 0 && (criminal == item.isIllegal) && price > 0
        }
    }

    /// ECO-059: a trader that would ignore you may offer a trade: `GetRandom(1000) < chanceOfTradeInOrbit`; then
    /// TraderSell if you have a free bay and the trader has tradeable goods, else TraderBuy if you have tradeable goods.
    mutating func tradeInOrbitRoll(trader: Ship) -> EncounterType? {
        guard rng.next(below: 1000) < chanceOfTradeInOrbit else { return nil }
        if freeCargoBays > 0, !tradeableItems(in: trader, isTraderShip: true).isEmpty { return .traderSell }
        if !tradeableItems(in: commander.ship, isTraderShip: false).isEmpty { return .traderBuy }
        return nil
    }

    /// ECO-061: picks the traded item: `idx = GetRandom(10)`, advancing until it qualifies.
    mutating func pickTradeItem(in ship: Ship, isTraderShip: Bool) -> TradeItemType? {
        let ok = Set(tradeableItems(in: ship, isTraderShip: isTraderShip).map(\.rawValue))
        guard !ok.isEmpty else { return nil }
        switch ruleset.flags.economy.tradeInOrbitItemPick {
        case .advanceFromRandom:
            var idx = rng.next(below: 10)
            while !ok.contains(idx) { idx = (idx + 1) % 10 }
            return TradeItemType(rawValue: idx)
        case .tenTriesThenScan:
            // ECO-062: Palm `GetRandomTradeableItem`.
            for _ in 0..<10 {
                let j = rng.next(below: 10)
                if ok.contains(j) { return TradeItemType(rawValue: j) }
            }
            return TradeItemType(rawValue: ok.min() ?? 0)
        }
    }

    /// ECO-065/068/071/069: builds the offer when the player chooses Trade (item pick, then price roll).
    mutating func makeOrbitTradeOffer(direction: OrbitTradeDirection, trader: Ship) -> OrbitTradeOffer? {
        let r = ruleset
        let rules = r.flags.economy
        switch direction {
        case .traderSells:
            guard let item = pickTradeItem(in: trader, isTraderShip: true) else { return nil }
            let i = item.rawValue
            let price = OrbitTrade.price(item: item, marketPrice: buyPrices[i], direction: .traderSells, ruleset: r, rng: &rng)
            // RUL-041/ECO-067: Palm keeps the in-orbit price in the market array until prices are next determined.
            if rules.tradeInOrbitMutatesMarketPrices { buyPrices[i] = price }
            let capPrice = r.flags.tradeInOrbitCashCapUsesOrbitPrice ? price : buyPrices[i]
            // ECO-070: Palm's typed amount is not capped by free bays; the engine keeps the hold-capacity invariant and
            // caps every purchase at the free bays (documented deviation).
            let maxQ = max(0, min(freeCargoBays, trader.cargo[i], commander.cash / max(1, capPrice)))
            return OrbitTradeOffer(direction: .traderSells, item: item, unitPrice: price, maxQuantity: maxQ,
                                   unitsAvailable: trader.cargo[i], costBasisPerUnit: 0)
        case .traderBuys:
            guard let item = pickTradeItem(in: commander.ship, isTraderShip: false) else { return nil }
            let i = item.rawValue
            let price = OrbitTrade.price(item: item, marketPrice: sellPrices[i], direction: .traderBuys, ruleset: r, rng: &rng)
            if rules.tradeInOrbitMutatesMarketPrices { sellPrices[i] = price }
            let held = commander.ship.cargo[i]
            // RUL-040/ECO-072: Palm caps by the trader ship type's base bays.
            let traderCap = switch rules.tradeInOrbitSellCap {
            case .traderFreeBays: trader.cargoBays(r) - trader.filledNormalCargoBays
            case .traderTypeBays: trader.spec(r).cargoBays
            }
            return OrbitTradeOffer(direction: .traderBuys, item: item, unitPrice: price,
                                   maxQuantity: max(0, min(held, traderCap)), unitsAvailable: held,
                                   costBasisPerUnit: held > 0 ? commander.priceCargo[i] / held : 0)
        }
    }

    /// Applies an accepted offer of `q` units (ECO-068/071/073). Returns the event, or nil for 0 units.
    mutating func resolveOrbitTrade(_ offer: OrbitTradeOffer, quantity q: Int, trader: inout Ship) -> GameEvent? {
        guard q > 0 else { return nil }
        let i = offer.item.rawValue
        let total = q * offer.unitPrice
        switch offer.direction {
        case .traderSells:
            commander.ship.cargo[i] += q
            trader.cargo[i] -= q
            commander.cash -= total
            commander.priceCargo[i] += total
        case .traderBuys:
            removeCargo(offer.item, q)
            commander.cash += total
            // ECO-072: Palm overwrites the trader's cargo of that item.
            if ruleset.flags.economy.tradeInOrbitSellCap == .traderTypeBays { trader.cargo[i] = q }
        }
        return .orbitTradeCompleted(direction: offer.direction, item: offer.item, quantity: q, total: total)
    }
}
