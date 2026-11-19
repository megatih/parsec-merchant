// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

// Pure view models of the Shipyard section (UI-SHELL-068…073). Built from a `GameState` during a render.

/// The ship statistics a card and the compare table show.
nonisolated enum ShipStatField: String, CaseIterable, Sendable {
    case cargoBays, fuelTanks, hullStrength, weaponSlots, shieldSlots, gadgetSlots, crewQuarters

    func value(_ spec: ShipSpec) -> Int {
        switch self {
        case .cargoBays: spec.cargoBays
        case .fuelTanks: spec.fuelTanks
        case .hullStrength: spec.hullStrength
        case .weaponSlots: spec.weaponSlots
        case .shieldSlots: spec.shieldSlots
        case .gadgetSlots: spec.gadgetSlots
        case .crewQuarters: spec.crewQuarters
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .cargoBays: "Cargo bays"
        case .fuelTanks: "Range"
        case .hullStrength: "Hull"
        case .weaponSlots: "Weapon slots"
        case .shieldSlots: "Shield slots"
        case .gadgetSlots: "Gadget slots"
        case .crewQuarters: "Crew quarters"
        }
    }
}

/// What a card says about the price after trade-in.
nonisolated enum ShipPriceLabel: Equatable, Sendable {
    /// The player pays this much.
    case pay(Int)
    /// The trade-in exceeds the price: "You get N cr.".
    case receive(Int)

    init(netPrice: Int) {
        self = netPrice < 0 ? .receive(-netPrice) : .pay(netPrice)
    }
}

/// One card of the ship grid (UI-SHELL-068).
nonisolated struct ShipCardModel: Identifiable, Equatable, Sendable {
    let type: ShipType
    let isYours: Bool
    let spec: ShipSpec
    /// Nil for the current ship.
    let price: ShipPriceLabel?
    /// Why buying would be rejected (`ShipQuote.blocker`), nil for the current ship.
    let blocker: CommandError?

    var id: ShipType { type }
    var canOpenPurchase: Bool { !isYours }
}

/// The escape pod and insurance strip (UI-SHELL-073).
nonisolated struct EscapePodStrip: Equatable, Sendable {
    static let price = 2_000
    let installed: Bool
    /// Why Buy Escape Pod is disabled (mirrors the engine's `buyEscapePod` rejection), nil when it is offered.
    let blocker: CommandError?
    let insured: Bool

    var canBuy: Bool { !installed && blocker == nil }

    static func make(state: GameState) -> EscapePodStrip {
        let ship = state.commander.ship
        let blocker: CommandError?
        if case .gameOver = state.phase {
            blocker = .gameOver
        } else if state.phase != .docked {
            blocker = .notAllowedInPhase
        } else if ship.escapePod {
            blocker = .alreadyHaveEscapePod
        } else if state.escapePodOffered {
            blocker = nil
        } else {
            blocker = state.commander.cash < price ? .insufficientFunds : .escapePodNotAvailable
        }
        return EscapePodStrip(installed: ship.escapePod, blocker: blocker, insured: state.commander.insurance)
    }
}

/// The Shipyard's ship list (UI-SHELL-068, UI-SHELL-039, UI-SHELL-069).
struct ShipyardModel: Equatable, Sendable {
    /// For-sale ships in table order, then the current ship marked "Yours".
    let cards: [ShipCardModel]
    let hasShipsForSale: Bool
    let escapePod: EscapePodStrip
    let designerAvailable: Bool
    let yard: ShipyardID?

    static func make(state: GameState) -> ShipyardModel {
        let forSale = state.shipsForSale.map { t in
            let q = state.shipQuote(t)
            return ShipCardModel(type: t, isYours: false, spec: state.ruleset.tables.ship(t),
                                 price: ShipPriceLabel(netPrice: q.netPrice), blocker: q.blocker)
        }
        let ship = state.commander.ship
        let yours = ShipCardModel(type: ship.type, isYours: true, spec: ship.spec(state.ruleset), price: nil, blocker: nil)
        let designer = SectionContext.make(state: state).designerAvailable
        return ShipyardModel(cards: forSale + [yours], hasShipsForSale: !forSale.isEmpty,
                             escapePod: .make(state: state), designerAvailable: designer,
                             yard: designer ? state.currentSystem.shipyard : nil)
    }
}

enum ShipCompare {
    /// The sign-plus-arrow delta label: "+5 ▲", "−3 ▼", "±0".
    static func deltaText(_ d: Int) -> String {
        if d > 0 { return "+\(d.formatted()) ▲" }
        if d < 0 { return "−\((-d).formatted()) ▼" }
        return "±0"
    }
}

// MARK: - Purchase review (UI-SHELL-071/072/075)

/// A transfer candidate in the purchase review checklist.
nonisolated struct TransferRow: Identifiable, Equatable, Sendable {
    let item: TransferItem
    let price: Int
    /// The player has not unticked it.
    let wanted: Bool
    /// False once the running total would exceed the cash to spend (the engine auto-declines it, ALR-143).
    let affordable: Bool
    var id: TransferItem { item }
    /// The item really moves to the new ship.
    var accepted: Bool { wanted && affordable }
}

/// What happens to the insurance policy.
nonisolated enum InsuranceEffect: Equatable, Sendable {
    case notInsured
    case kept
    /// The new ship has no escape pod: the policy ends and the no-claim bonus is lost.
    case ends
}

/// Everything the purchase review sheet shows, for a stock ship or a design.
struct ShipPurchaseModel: Equatable, Sendable {
    let request: ShipPurchaseRequest
    let newSpec: ShipSpec
    /// The price before the trade-in (for a design: adjusted price + penalty + fee).
    let listPrice: Int
    /// Palm's trader discount (RUL-052), 0 elsewhere.
    let discount: Int
    let tradeIn: Int
    let netPrice: Int
    let transfers: [TransferRow]
    let lost: [TransferItem]
    /// Crew ids (from slot index `newSpec.crewQuarters` on) that have no seat on the new ship.
    let crewWithoutSeat: [Int]
    /// Units of trade cargo that stay behind; their cost basis is part of the trade-in.
    let cargoUnits: Int
    let insurance: InsuranceEffect
    let blocker: CommandError?

    var transferTotal: Int { transfers.filter(\.accepted).reduce(0) { $0 + $1.price } }
    var finalCost: Int { netPrice + transferTotal }
    var accepted: [TransferItem] { transfers.filter(\.accepted).map(\.item) }
    var canBuy: Bool { blocker == nil }

    /// The command Buy Ship sends (with `acknowledging: [.buyShip]`, UI-SHELL-072).
    var command: Command {
        switch request {
        case let .ship(t): .buyShip(t, transfers: accepted)
        case let .design(d): .buildDesign(d, transfers: accepted)
        }
    }

    /// - Parameter declined: candidates the player unticked (every candidate starts ticked).
    static func make(request: ShipPurchaseRequest, state: GameState, declined: Set<TransferItem> = []) -> ShipPurchaseModel? {
        let spec: ShipSpec
        let quote: ShipQuote
        let listPrice: Int
        let tradeIn = state.shipWorth(forInsurance: false)
        let blocker: CommandError?
        switch request {
        case let .ship(t):
            spec = state.ruleset.tables.ship(t)
            quote = state.shipQuote(t)
            listPrice = spec.price
            blocker = quote.blocker
        case let .design(d):
            guard let dq = state.designQuote(d) else { return nil }
            spec = dq.spec
            quote = state.shipQuote(.custom, spec: dq.spec, netPrice: dq.totalCost)
            listPrice = dq.adjustedPrice + dq.adjustedPenalty + dq.adjustedFee
            blocker = dq.blocker
        }
        let palm = state.ruleset.flags.economy.shipTradeFlow == .palm
        // Mirrors the engine's TradeShip loop: an item is affordable iff net + accepted so far (+ its own price,
        // except in Palm, SHP-042) fits the cash to spend.
        var extra = 0
        var rows: [TransferRow] = []
        for (item, price) in quote.candidates {
            let wanted = !declined.contains(item)
            let affordable = quote.netPrice + extra + (palm ? 0 : price) <= state.cashToSpend
            if wanted, affordable { extra += price }
            rows.append(TransferRow(item: item, price: price, wanted: wanted, affordable: affordable))
        }
        let old = state.commander.ship
        let seatless = old.crew.indices.filter { $0 >= spec.crewQuarters }.compactMap { old.crew[$0] }
        let newPod = palm ? old.escapePod : rows.contains { $0.item == .escapePod && $0.accepted }
        let insurance: InsuranceEffect = !state.commander.insurance ? .notInsured : (newPod ? .kept : .ends)
        return ShipPurchaseModel(request: request, newSpec: spec, listPrice: listPrice,
                                 discount: max(0, listPrice - (quote.netPrice + tradeIn)), tradeIn: tradeIn,
                                 netPrice: quote.netPrice, transfers: rows, lost: quote.lost, crewWithoutSeat: seatless,
                                 cargoUnits: old.filledNormalCargoBays, insurance: insurance, blocker: blocker)
    }
}
