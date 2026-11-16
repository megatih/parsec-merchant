// SPDX-License-Identifier: GPL-2.0-or-later
// Docked market commands and previews (docs/specs/ECO.md §ECO-042…ECO-083).

/// Per-item market view (ECO-077).
public struct MarketRow: Sendable, Equatable {
    public var item: TradeItemType
    public var buyPrice: Int
    public var sellPrice: Int
    public var stock: Int
    public var held: Int
    /// Average price paid per unit held (0 when none held).
    public var costBasisPerUnit: Int
    public var maxBuy: Int
    public var maxSell: Int
    /// Docked sell mode: `.sell` at the market price or `.dump` at a disposal cost per unit.
    public var dumpCostPerUnit: Int?
}

public extension GameState {
    /// ECO-046: free bays for market buying, honouring "leave N bays empty".
    var marketFreeBays: Int { max(0, freeCargoBays - options.leaveEmpty) }

    /// ECO-052: disposal cost per unit.
    var dumpCostPerUnit: Int { 5 * (difficulty.rawValue + 1) }

    /// ECO-045/047: the first blocking error, or the maximum purchasable quantity.
    func marketBuyCheck(_ item: TradeItemType) -> Result<Int, CommandError> {
        let i = item.rawValue
        let price = buyPrices[i]
        let stock = currentSystem.tradeItems[i]
        if commander.debt > 100_000 { return .failure(.debtTooLargeToTrade) }
        if stock <= 0 || price <= 0 { return .failure(.cargoNoneAvailable) }
        if marketFreeBays == 0 { return .failure(.noEmptyBays) }
        if cashToSpend < price { return .failure(.insufficientFunds) }
        return .success(min(marketFreeBays, stock, cashToSpend / price))
    }

    /// ECO-049/050/053: the first blocking error, or the maximum sell (or dump) quantity.
    func marketSellCheck(_ item: TradeItemType, dump: Bool) -> Result<Int, CommandError> {
        let held = commander.ship.cargo[item.rawValue]
        if held == 0 { return .failure(.cargoNoneToSell) }
        let price = sellPrices[item.rawValue]
        if dump {
            if price > 0 { return .failure(.invalidArgument) }
            return .success(max(0, min(held, cashToSpend / dumpCostPerUnit)))
        }
        if price <= 0 { return .failure(.marketNotInterested) }
        return .success(held)
    }

    /// ECO-077: the market table.
    var marketRows: [MarketRow] {
        TradeItemType.allCases.map { item in
            let i = item.rawValue
            let held = commander.ship.cargo[i]
            let canSell = sellPrices[i] > 0
            return MarketRow(
                item: item, buyPrice: buyPrices[i], sellPrice: sellPrices[i], stock: currentSystem.tradeItems[i],
                held: held, costBasisPerUnit: held > 0 ? commander.priceCargo[i] / held : 0,
                maxBuy: (try? marketBuyCheck(item).get()) ?? 0,
                maxSell: (try? marketSellCheck(item, dump: !canSell).get()) ?? 0,
                dumpCostPerUnit: canSell ? nil : dumpCostPerUnit)
        }
    }

    /// ECO-051: removes `q` units, scaling the cost basis with the pre-sale quantity.
    internal mutating func removeCargo(_ item: TradeItemType, _ q: Int) {
        let i = item.rawValue
        let held = commander.ship.cargo[i]
        guard held > 0 else { return }
        commander.priceCargo[i] = commander.priceCargo[i] * (held - q) / held
        commander.ship.cargo[i] -= q
    }
}

extension GameEngine {
    mutating func buyCargo(_ item: TradeItemType, quantity q: Int) -> StepResult {
        guard case .docked = state.phase else { return .rejected(.notAllowedInPhase) }
        switch state.marketBuyCheck(item) {
        case let .failure(e): return .rejected(e)
        case let .success(maxQ):
            guard q >= 1, q <= maxQ else { return .rejected(.invalidQuantity) }
            let i = item.rawValue
            let total = q * state.buyPrices[i]
            state.commander.ship.cargo[i] += q
            state.galaxy.systems[state.commander.currentSystem].tradeItems[i] -= q
            state.commander.cash -= total
            state.commander.priceCargo[i] += total
            return StepResult(events: [.boughtCargo(item: item, quantity: q, total: total)])
        }
    }

    mutating func sellCargo(_ item: TradeItemType, quantity q: Int, dump: Bool) -> StepResult {
        guard case .docked = state.phase else { return .rejected(.notAllowedInPhase) }
        switch state.marketSellCheck(item, dump: dump) {
        case let .failure(e): return .rejected(e)
        case let .success(maxQ):
            guard q >= 1, q <= maxQ else { return .rejected(.invalidQuantity) }
            let i = item.rawValue
            let held = state.commander.ship.cargo[i]
            let basisSold = state.commander.priceCargo[i] - state.commander.priceCargo[i] * (held - q) / held
            state.removeCargo(item, q)
            if dump {
                let cost = q * state.dumpCostPerUnit
                state.commander.cash -= cost
                return StepResult(events: [.dumpedCargo(item: item, quantity: q, cost: cost)])
            }
            let total = q * state.sellPrices[i]
            state.commander.cash += total
            return StepResult(events: [.soldCargo(item: item, quantity: q, total: total, profit: total - basisSold)])
        }
    }

    /// ECO-055…057, ECO-080: jettison in space with the littering warning and the chance to be caught.
    mutating func jettisonCargo(_ item: TradeItemType, quantity q: Int, acknowledging ack: Set<WarningID>) -> StepResult {
        // ECO-055: jettisoning is only possible in space.
        if case .docked = state.phase { return .rejected(.notAllowedInPhase) }
        let held = state.commander.ship.cargo[item.rawValue]
        if held == 0 { return .rejected(.cargoNoneToSell) }
        guard q >= 1, q <= held else { return .rejected(.invalidQuantity) }
        if !state.litterWarning, state.commander.policeRecordScore > -5 {
            guard ack.contains(.litteringWarning) else { return .needsConfirmation(Confirmation(.litteringWarning)) }
            state.litterWarning = true
        }
        state.removeCargo(item, q)
        var events: [GameEvent] = [.jettisonedCargo(item: item, quantity: q)]
        if state.rng.next(below: 10) < state.difficulty.rawValue + 1 {
            if state.commander.policeRecordScore > -5 {
                state.commander.policeRecordScore = -5
            } else {
                state.commander.policeRecordScore -= 1
            }
            state.addNewsEvent(.caughtLittering)
            events.append(.caughtLittering(newRecord: state.commander.policeRecordScore))
        }
        return StepResult(events: events)
    }
}
