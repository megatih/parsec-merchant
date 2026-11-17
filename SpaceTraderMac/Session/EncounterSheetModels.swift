// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// UI-ENC-046: the plunder sheet's content. Pure; replaces the interim plunder model.
struct PlunderSheetModel: Equatable, Sendable {
    struct Row: Equatable, Sendable {
        var item: TradeItemType
        var available: Int
        /// `min(available, freeBays)`.
        var maxTake: Int

        /// The stepper value clamped to `1…maxTake` (1 when nothing fits).
        func clamp(_ quantity: Int) -> Int { min(max(1, quantity), max(1, maxTake)) }
        var canTake: Bool { maxTake > 0 }
        func takeCommand(_ quantity: Int) -> Command { .plunderTake(item, quantity: clamp(quantity)) }
        var takeAllCommand: Command { .plunderTake(item, quantity: max(1, maxTake)) }
    }

    var title: String
    var rows: [Row]
    var freeBays: Int
    var isEmpty: Bool { rows.isEmpty }
    /// UI-ENC-045: Take is disabled with this reason when no bay is free.
    var takeBlocker: CommandError? { freeBays > 0 ? nil : .noEmptyBays }
    static let doneCommand = Command.plunderDone

    /// The victim's cargo is read from the state's pending plunder (so the sheet updates after each Take), else the context.
    static func make(context: PlunderSheetContext, state: GameState) -> PlunderSheetModel {
        let cargo = state.pendingPlunder?.victimCargo ?? context.victimCargo
        let free = max(0, state.freeCargoBays)
        let rows = TradeItemType.allCases.compactMap { item -> Row? in
            let i = item.rawValue
            guard cargo.indices.contains(i), cargo[i] > 0 else { return nil }
            return Row(item: item, available: cargo[i], maxTake: min(cargo[i], free))
        }
        let title: String
        switch context.source {
        case .marieCeleste:
            title = String(localized: "Marie Celeste")
        case .opponent:
            if case let .encounter(enc) = state.phase {
                title = String(localized: "Plunder the \(CombatLog.shipText(type: enc.type, opponent: enc.opponent.type))")
            } else {
                title = String(localized: "Plunder")
            }
        }
        return PlunderSheetModel(title: title, rows: rows, freeBays: free)
    }
}

/// UI-ENC-048: the trade-in-orbit offer sheet's content. Pure; replaces the interim trade model.
struct TradeOfferModel: Equatable, Sendable {
    var offer: OrbitTradeOffer
    var cash: Int

    static func make(offer: OrbitTradeOffer, state: GameState) -> TradeOfferModel {
        TradeOfferModel(offer: offer, cash: state.commander.cash)
    }

    var range: ClosedRange<Int> { 0...max(0, offer.maxQuantity) }
    var initialQuantity: Int { max(0, offer.maxQuantity) }
    var traderBuys: Bool { offer.direction == .traderBuys }
    func clamp(_ q: Int) -> Int { min(max(0, q), range.upperBound) }
    func canAccept(_ q: Int) -> Bool { clamp(q) > 0 && q == clamp(q) }
    func total(_ q: Int) -> Int { clamp(q) * offer.unitPrice }
    /// Profit per unit against the cost basis (trader buys only).
    var profitPerUnit: Int? { traderBuys ? offer.unitPrice - offer.costBasisPerUnit : nil }
    func profitTotal(_ q: Int) -> Int? { profitPerUnit.map { $0 * clamp(q) } }
    /// Cash after buying (trader sells only).
    func cashAfter(_ q: Int) -> Int? { traderBuys ? nil : cash - total(q) }
    func acceptCommand(_ q: Int) -> Command { .resolveTradeInOrbit(quantity: clamp(q)) }
    static let declineCommand = Command.resolveTradeInOrbit(quantity: 0)

    /// "The trader offers to sell Furs" / "… to buy Furs".
    var title: String {
        let item = String(localized: Names.item(offer.item))
        return traderBuys ? String(localized: "The trader offers to buy \(item)") : String(localized: "The trader offers to sell \(item)")
    }

    /// "+12 cr. ▲" / "−5 cr. ▼" / "0 cr.".
    static func signed(_ v: Int) -> String {
        if v > 0 { return "+\(v.formatted()) cr. ▲" }
        if v < 0 { return "−\(abs(v).formatted()) cr. ▼" }
        return "0 cr."
    }
}

/// UI-ENC-049: the scoop dialog (ALR-070) or, with a full hold, the Make Room dialog (ALR-071).
struct ScoopDialogModel: Equatable, Sendable {
    var item: TradeItemType
    var holdIsFull: Bool

    static func make(item: TradeItemType, state: GameState?) -> ScoopDialogModel {
        ScoopDialogModel(item: item, holdIsFull: (state?.freeCargoBays ?? 1) <= 0)
    }

    var content: ConfirmationContent {
        let title = String(localized: "A canister of \(String(localized: Names.item(item))) floats by.")
        if holdIsFull {
            return ConfirmationContent(title: title, message: String(localized: "Your hold is full. Make room to pick it up?"),
                                       confirmLabel: String(localized: "Make Room"), isDestructive: false)
        }
        return ConfirmationContent(title: title, message: String(localized: "Pick it up?"),
                                   confirmLabel: String(localized: "Pick It Up"), isDestructive: false)
    }

    var confirmIdentifier: String { holdIsFull ? AXID.Decision.scoopMakeRoom : AXID.Decision.scoopAccept }
}

/// UI-ENC-049: the Make Room jettison sheet: the player's cargo rows with what they hold.
struct MakeRoomModel: Equatable, Sendable {
    struct Row: Equatable, Sendable {
        var item: TradeItemType
        var held: Int
    }

    var rows: [Row]
    var freeBays: Int

    static func make(state: GameState) -> MakeRoomModel {
        let cargo = state.commander.ship.cargo
        let rows = TradeItemType.allCases.compactMap { item in cargo[item.rawValue] > 0 ? Row(item: item, held: cargo[item.rawValue]) : nil }
        return MakeRoomModel(rows: rows, freeBays: max(0, state.freeCargoBays))
    }
}

/// UI-ENC-030: what an inspection would find (C# `EncounterVerifySubmit` list).
struct InspectionFindings: Equatable, Sendable {
    /// Firearms and narcotics units beyond the hidden bays.
    var illegalUnits: Int
    var wild: Bool
    var reactor: Bool
    var sculpture: Bool

    static func make(state: GameState) -> InspectionFindings {
        let ship = state.commander.ship
        return InspectionFindings(illegalUnits: max(0, ship.illegalCargoUnits - ship.hiddenCargoBays), wild: state.wildOnBoard,
                                  reactor: state.reactorOnBoard, sculpture: state.sculptureOnBoard)
    }

    /// ENC-155: Wild, the reactor or the sculpture mean arrest.
    var willArrest: Bool { wild || reactor || sculpture }

    var items: [String] {
        var list: [String] = []
        if illegalUnits > 0 { list.append(String(localized: "\(illegalUnits) units of illegal goods")) }
        if wild { list.append(String(localized: "Jonathan Wild")) }
        if reactor { list.append(String(localized: "an illegal Ion Reactor")) }
        if sculpture { list.append(String(localized: "a stolen sculpture")) }
        return list
    }

    /// The submit confirmation's message.
    var message: String {
        let found = items
        var text = found.isEmpty ? String(localized: "The police will search your ship. They will find nothing illegal.")
            : String(localized: "The police will search your ship and find \(found.formatted(.list(type: .and))).")
        if willArrest { text += " " + String(localized: "You will be arrested.") }
        return text
    }
}
