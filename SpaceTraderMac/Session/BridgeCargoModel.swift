// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import ParsecInsights

/// UI-BRG-001…009: the Bridge's Cargo region: ten rows and the two summary lines. Pure over the state and the intel
/// model; every number about another system comes from `ParsecInsights` (UI-BRG-006).
struct BridgeCargoModel: Equatable, Sendable {
    struct Row: Identifiable, Equatable, Sendable {
        var market: MarketRowModel
        /// The Target System's quote; nil while the target is the current system.
        var quote: PriceQuote?
        /// `TradeIntel.bestBuys` names this good for the target.
        var bestBuy: Bool

        var id: TradeItemType { market.item }
        var item: TradeItemType { market.item }
        /// The price at the target, nil when there is no target or the good is not traded there ("—").
        var targetPrice: Int? { quote?.sell }
        /// The price here that the target is compared with: Buy if the good is sold here, else Sell.
        var reference: Int? { market.buyPrice ?? market.sellPrice }
        /// Target minus the reference; nil when either is missing.
        var delta: Int? {
            guard let targetPrice, let reference else { return nil }
            return targetPrice - reference
        }
        /// The original's rule for its Average Price List: bold when profitable and in stock here.
        var deltaIsBold: Bool { (delta ?? 0) > 0 && market.row.stock > 0 }
        /// Held and sold here: the sell price minus the price paid, per unit.
        var gainPerUnit: Int? { market.profitPerUnit }

        /// The quantity a typed text asks for: empty means 1; nil when it is not a positive number.
        static func quantity(_ text: String) -> Int? {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return 1 }
            guard let n = Int(trimmed), n > 0 else { return nil }
            return n
        }

        /// UI-BRG-003: Buy sends the quantity as typed; the engine clamps or rejects it.
        func buyCommand(text: String) -> Command? {
            guard market.buyBlocker == nil, let q = Self.quantity(text) else { return nil }
            return .buyCargo(item, quantity: q)
        }

        /// UI-BRG-003: Sell sends the quantity as typed (never in dump mode: Dump opens its own sheet).
        func sellCommand(text: String) -> Command? {
            guard !market.isDumpMode, market.sellBlocker == nil, let q = Self.quantity(text) else { return nil }
            return .sellCargo(item, quantity: q)
        }

        /// Max: the engine's maximum.
        var maxCommand: Command? { market.buyMaxCommand }
        /// All: every unit the engine lets the player sell; never a dump.
        var allCommand: Command? { market.isDumpMode ? nil : market.sellAllCommand }
        /// Why Sell and All cannot act.
        var sellBlocker: CommandError? { market.isDumpMode ? (market.canDump ? nil : .cargoNoneToSell) : market.sellBlocker }
        /// Why All cannot act: nobody buys the good here, or the sell blocker.
        var allBlocker: CommandError? { market.isDumpMode ? .marketNotInterested : market.sellBlocker }
    }

    var rows: [Row]
    var usedBays: Int
    var totalBays: Int
    /// Free bays for buying, honouring "leave N bays empty".
    var freeBays: Int
    var cashToSpend: Int
    /// What the hold fetches here (`TradeIntel.holdValue` at the current system).
    var holdHere: HoldValue
    /// The same at the Target System; nil while the target is the current system.
    var holdAtTarget: HoldValue?
    var targetName: String?
    /// UI-BRG-004.
    var sellAll: SellAllCargo

    func row(_ item: TradeItemType) -> Row? { rows.first { $0.item == item } }

    static func make(state: GameState, intel: MarketIntelModel, book: IntelBook) -> BridgeCargoModel {
        let snapshot = IntelSnapshot(state)
        let best = Set(intel.bestBuys.map(\.item))
        let rows = MarketRowModel.rows(state: state).map { market in
            Row(market: market, quote: intel.row(market.item)?.targetQuote, bestBuy: best.contains(market.item))
        }
        return BridgeCargoModel(rows: rows, usedBays: state.filledCargoBays, totalBays: state.commander.ship.cargoBays(state.ruleset),
                                freeBays: state.marketFreeBays, cashToSpend: state.cashToSpend,
                                holdHere: TradeIntel.holdValue(at: snapshot.currentSystem, book: book, snapshot: snapshot),
                                holdAtTarget: intel.holdAtTarget,
                                targetName: intel.targetIsHere ? nil : Names.system(intel.target, in: state),
                                sellAll: .make(state: state))
    }
}

/// UI-BRG-004: Sell All Cargo: one `.sellCargo` for each held good that has a sell price here, in table order. It
/// adds no rule; it is the commands the player would send one by one.
nonisolated struct SellAllCargo: Equatable, Sendable {
    var commands: [Command]
    /// The credits the sales bring (quantity × the sell price here).
    var proceeds: Int
    /// Why nothing can be sold; nil when there is something to sell.
    var blocker: CommandError?

    static func make(state: GameState) -> SellAllCargo {
        guard state.phase == .docked else { return SellAllCargo(commands: [], proceeds: 0, blocker: .notAllowedInPhase) }
        var commands: [Command] = [], proceeds = 0, firstError: CommandError?
        for row in state.marketRows where row.held > 0 && row.sellPrice > 0 && row.dumpCostPerUnit == nil {
            switch state.marketSellCheck(row.item, dump: false) {
            case let .success(quantity) where quantity > 0:
                commands.append(.sellCargo(row.item, quantity: quantity))
                proceeds += quantity * row.sellPrice
            case .success:
                break
            case let .failure(error):
                firstError = firstError ?? error
            }
        }
        let held = state.marketRows.contains { $0.held > 0 }
        return SellAllCargo(commands: commands, proceeds: proceeds,
                            blocker: commands.isEmpty ? (firstError ?? (held ? .marketNotInterested : .cargoNoneToSell)) : nil)
    }
}

/// The four notices of the System Information region (PRD §4.2): each keeps its place and says why when empty.
struct BridgeNoticesModel: Equatable, Sendable {
    struct News: Equatable, Sendable {
        var cost: Int
        var paid: Bool
        var blocker: CommandError?
    }

    var news: News
    /// The special offer here, nil when there is none.
    var special: SpecialEventCardModel?
    var mercenaries: MercenaryCardModel?
    /// Days to the nearest quest deadline, nil when no quest counts days.
    var nearestDeadline: Int?

    static func make(state: GameState) -> BridgeNoticesModel {
        let paper = NewspaperCardModel.make(state: state)
        return BridgeNoticesModel(news: News(cost: paper.cost, paid: paper.paid, blocker: paper.blocker),
                                  special: SpecialEventCardModel.make(state: state),
                                  mercenaries: MercenaryCardModel.make(state: state),
                                  nearestDeadline: state.questLog.compactMap(\.daysLeft).min())
    }
}

/// The Target System panel (UI-BRG-020…023): never empty; after arrival it shows the current system.
struct BridgeTargetModel: Equatable, Sendable {
    enum Status: Equatable, Sendable { case current, inRange, outOfRange, viaWormhole }

    /// The costs of the next warp; all zero while there is no target.
    struct Costs: Equatable, Sendable {
        var mercenaries = 0
        var insurance = 0
        var interest = 0
        var wormholeTax = 0
        var total: Int { mercenaries + insurance + interest + wormholeTax }
    }

    var system: SystemCardModel
    var status: Status
    var distance: Int
    var costs: Costs
    /// Fuel left after the warp; the fuel now when there is no target.
    var fuelAfter: Int
    var warp: WarpButtonModel
    var isTracked: Bool
    var canCycle: Bool
    var jump: TargetCardModel.Jump?

    static func make(state: GameState, isModal: Bool) -> BridgeTargetModel {
        let target = state.warpSystem, here = target == state.commander.currentSystem
        let preview = state.warpTargetPreview(target)
        let status: Status = here ? .current : preview.viaWormhole ? .viaWormhole : preview.inRange ? .inRange : .outOfRange
        let jump: TargetCardModel.Jump? = state.quests.canSuperWarp ? {
            let j = state.jumpPreview
            return TargetCardModel.Jump(destination: j.destination, enabled: j.available, blocking: j.blocking, rejection: j.rejection)
        }() : nil
        return BridgeTargetModel(system: .make(state: state, system: target), status: status, distance: here ? 0 : preview.distance,
                                 costs: here ? Costs() : Costs(mercenaries: preview.costs.mercenaries, insurance: preview.costs.insurance,
                                                               interest: preview.costs.interest, wormholeTax: preview.costs.wormholeTax),
                                 fuelAfter: here || !preview.inRange ? state.commander.ship.fuel : preview.fuelAfter,
                                 warp: WarpButtonModel.make(state: state, isModal: isModal), isTracked: !here && state.trackedSystem == target,
                                 canCycle: !state.destinations.isEmpty, jump: jump)
    }

    var isCurrent: Bool { status == .current }
    /// MENU-034: track the target, or stop tracking it.
    var trackCommand: Command { .track(isTracked ? nil : system.index) }
}
