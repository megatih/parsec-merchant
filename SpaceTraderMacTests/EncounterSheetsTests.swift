// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import Foundation
import ParsecEngine
import SwiftUI
import Testing
@testable import ParsecMerchant

@MainActor
struct EncounterSheetsTests {
    private func emptyHold(_ st: inout GameState) {
        st.commander.ship.cargo = Array(repeating: 0, count: TradeItemType.allCases.count)
    }

    private func render(_ view: some View, session: GameSession) {
        let host = NSHostingView(rootView: view.environment(session))
        host.frame = NSRect(x: 0, y: 0, width: 520, height: 480)
        host.layoutSubtreeIfNeeded()
    }

    // MARK: Plunder (UI-ENC-045/046)

    @Test("UI-ENC-045 the plunder sheet stays open after each Take, updates from the state and Done answers")
    func plunderFlow() throws {
        let s = try EncFx.session(.pirateSurrender) { st in
            emptyHold(&st)
            if case var .encounter(e) = st.phase {
                e.opponent.cargo[TradeItemType.furs.rawValue] = 5
                e.opponent.cargo[TradeItemType.ore.rawValue] = 2
                st.phase = .encounter(e)
            }
        }
        s.performEncounterAction(.plunder)
        guard case let .sheet(.plunder(context)) = s.presentation else {
            Issue.record("plunder opens the plunder sheet")
            return
        }
        #expect(context.source == .opponent)
        render(PlunderSheet(context: context), session: s)
        var model = PlunderSheetModel.make(context: context, state: try #require(s.state))
        #expect(model.title == "Plunder the pirate ship" && model.rows.map(\.item) == [.furs, .ore])
        s.send(model.rows[0].takeCommand(2))
        #expect(s.presentation?.id == "sheet.plunder.opponent" && s.pendingPresentations.isEmpty)
        model = PlunderSheetModel.make(context: context, state: try #require(s.state))
        #expect(model.rows.first?.available == 3)
        s.send(model.rows[1].takeAllCommand)
        #expect(s.state?.commander.ship.cargo[TradeItemType.ore.rawValue] == 2)
        #expect(s.encounterUI.log.contains { $0.text.contains("Plundered") })
        s.dismissPresentation()
        s.send(PlunderSheetModel.doneCommand)
        #expect(s.state?.pendingPlunder == nil && s.presentation == nil)
        for id in [AXID.Decision.plunderSheet, AXID.Decision.plunderFreeBays, AXID.Decision.plunderDone,
                   AXID.Decision.plunderRow(.furs), AXID.Decision.plunderQuantity(.furs), AXID.Decision.plunderTakeAll(.furs)] {
            #expect(AXID.all.contains(id))
        }
    }

    @Test("UI-ENC-046 rows clamp to the free bays; a full hold blocks Take; the Marie Celeste sheet is titled for boarding")
    func plunderModel() throws {
        var st = try EncFx.state(.pirateSurrender)
        emptyHold(&st)
        let free = st.freeCargoBays
        let context = PlunderSheetContext(victimCargo: [0, free + 4, 0, 0, 0, 0, 0, 0, 0, 1], source: .opponent)
        let m = PlunderSheetModel.make(context: context, state: st)
        #expect(m.rows[0].maxTake == free && m.rows[1].maxTake == 1 && m.freeBays == free && m.takeBlocker == nil)
        #expect(m.rows[0].clamp(0) == 1 && m.rows[0].clamp(free + 9) == free)
        st.commander.ship.cargo[TradeItemType.water.rawValue] = free
        let full = PlunderSheetModel.make(context: context, state: st)
        #expect(full.freeBays == 0 && full.takeBlocker == .noEmptyBays && full.rows.allSatisfy { !$0.canTake })
        #expect(PlunderSheetModel.make(context: PlunderSheetContext(victimCargo: [0], source: .opponent), state: st).isEmpty)
        // ENC-161: boarding the Marie Celeste (Take Cargo consent) opens the sheet with source .marieCeleste.
        let s = try EncFx.session(.marieCeleste) { st in
            emptyHold(&st)
            if case var .encounter(e) = st.phase {
                e.opponent.cargo[TradeItemType.narcotics.rawValue] = 3
                st.phase = .encounter(e)
            }
        }
        s.performEncounterAction(.board)
        guard case let .confirmation(pending) = s.presentation else {
            Issue.record("boarding asks first")
            return
        }
        #expect(pending.confirmation.warning == .boardMarieCeleste)
        s.confirm(pending)
        guard case let .sheet(.plunder(mc)) = s.presentation else {
            Issue.record("boarding opens the plunder sheet")
            return
        }
        #expect(mc.source == .marieCeleste)
        let mm = PlunderSheetModel.make(context: mc, state: try #require(s.state))
        #expect(mm.title == "Marie Celeste" && mm.rows.map(\.item) == [.narcotics])
    }

    // MARK: Trade in orbit (UI-ENC-047/048)

    /// The engine's memberwise initializer is internal; the offer is Codable.
    private func offer(_ direction: OrbitTradeDirection, max: Int = 6, price: Int = 40, basis: Int = 30) throws -> OrbitTradeOffer {
        let json = "{\"direction\":\"\(direction.rawValue)\",\"item\":3,\"unitPrice\":\(price),\"maxQuantity\":\(max),"
            + "\"unitsAvailable\":9,\"costBasisPerUnit\":\(basis)}"
        return try JSONDecoder().decode(OrbitTradeOffer.self, from: Data(json.utf8))
    }

    @Test("UI-ENC-047 the offer sheet: title, total, profit (trader buys) or cash after (trader sells); Decline sends 0")
    func tradeSheet() throws {
        let s = try EncFx.session(.traderSell)
        let o = try offer(.traderSells)
        s.present(.sheet(.tradeInOrbit(o)))
        render(TradeInOrbitSheet(offer: o), session: s)
        let model = TradeOfferModel.make(offer: o, state: try #require(s.state))
        #expect(model.title == "The trader offers to sell Ore")
        #expect(model.total(6) == 240 && model.cashAfter(6) == (s.state?.commander.cash ?? 0) - 240 && model.profitPerUnit == nil)
        let buys = TradeOfferModel.make(offer: try offer(.traderBuys), state: try #require(s.state))
        #expect(buys.title == "The trader offers to buy Ore" && buys.profitPerUnit == 10 && buys.profitTotal(3) == 30 && buys.cashAfter(3) == nil)
        #expect(TradeOfferModel.signed(30) == "+30 cr. ▲" && TradeOfferModel.signed(-5) == "−5 cr. ▼" && TradeOfferModel.signed(0) == "0 cr.")
        for id in [AXID.Decision.tradeSheet, AXID.Decision.tradeQuantity, AXID.Decision.tradeMax, AXID.Decision.tradeAccept,
                   AXID.Decision.tradeDecline] {
            #expect(AXID.all.contains(id))
        }
    }

    @Test("UI-ENC-048 the trade model's range, initial quantity, zero maximum and profit sign")
    func tradeModel() throws {
        let m = TradeOfferModel(offer: try offer(.traderBuys, price: 20, basis: 35), cash: 100)
        #expect(m.range == 0...6 && m.initialQuantity == 6 && m.canAccept(6) && !m.canAccept(0) && !m.canAccept(7))
        #expect(m.profitPerUnit == -15 && m.profitTotal(2) == -30)
        #expect(m.acceptCommand(99) == .resolveTradeInOrbit(quantity: 6) && TradeOfferModel.declineCommand == .resolveTradeInOrbit(quantity: 0))
        let zero = TradeOfferModel(offer: try offer(.traderSells, max: 0), cash: 0)
        #expect(zero.range == 0...0 && zero.initialQuantity == 0 && !zero.canAccept(zero.initialQuantity))
    }

    // MARK: Scoop and Make Room (UI-ENC-049)

    @Test("UI-ENC-049 scoop: Pick It Up / Leave It; a full hold offers Make Room, the jettison sheet, then Pick It Up again")
    func scoop() throws {
        let s = try EncFx.session(.pirateAttack) { st in
            emptyHold(&st)
            st.pendingScoop = .water
            st.pendingEncounterResult = .normal
        }
        let normal = ScoopDialogModel.make(item: .water, state: s.state)
        #expect(!normal.holdIsFull && normal.content.title == "A canister of Water floats by." && normal.content.confirmLabel == "Pick It Up")
        #expect(normal.confirmIdentifier == AXID.Decision.scoopAccept)
        // Fill the hold: Make Room.
        let bays = try #require(s.state?.freeCargoBays)
        try TestSessions.edit(s) { $0.commander.ship.cargo[TradeItemType.ore.rawValue] = bays }
        let full = ScoopDialogModel.make(item: .water, state: s.state)
        #expect(full.holdIsFull && full.content.confirmLabel == "Make Room" && full.confirmIdentifier == AXID.Decision.scoopMakeRoom)
        s.present(.scoop(.water))
        s.beginMakeRoom(for: .water)
        #expect(s.presentation == nil && s.encounterUI.makeRoomItem == .water)
        #expect(s.encounterResumePresentation == nil)
        let room = MakeRoomModel.make(state: try #require(s.state))
        #expect(room.rows.map(\.item) == [.ore] && room.freeBays == 0)
        render(EncounterMakeRoomSheet(item: .water), session: s)
        s.makeRoomJettison(.ore, quantity: 1)
        #expect(s.state?.freeCargoBays == 1 && s.encounterUI.makeRoomItem == nil && s.presentation == .scoop(.water))
        #expect(!ScoopDialogModel.make(item: .water, state: s.state).holdIsFull)
        s.answerScoop(accept: true)
        #expect(s.state?.pendingScoop == nil)
        #expect(s.encounterUI.log.contains { $0.text.contains("Scooped") } || s.feed.contains { $0.event == .scooped(.water) })
        // Cancelling the Make Room sheet asks the scoop question again.
        let c = try EncFx.session(.pirateAttack) { st in st.pendingScoop = .food; st.pendingEncounterResult = .normal }
        c.beginMakeRoom(for: .food)
        c.endMakeRoom()
        #expect(c.presentation == .scoop(.food))
    }

    // MARK: Board, drink, meet (UI-ENC-050)

    @Test("UI-ENC-050 board/drink/meet dialogs use the ALR wording; the outcome reaches the combat log")
    func veryRareDialogs() throws {
        let st = try EncFx.state(.captainAhab, opponent: .wasp)
        #expect(ConfirmationText.content(for: Confirmation(.boardMarieCeleste), state: st).confirmLabel == "Take Cargo")
        #expect(ConfirmationText.cancelLabel(for: .boardMarieCeleste) == "Leave It")
        #expect(ConfirmationText.content(for: Confirmation(.drinkTonic), state: st).confirmLabel == "Drink")
        #expect(ConfirmationText.cancelLabel(for: .drinkTonic) == "Leave It")
        #expect(ConfirmationText.content(for: Confirmation(.meetCaptain), state: st).confirmLabel == "Trade Shield")
        let conrad = try EncFx.state(.captainConrad, opponent: .wasp)
        #expect(ConfirmationText.content(for: Confirmation(.meetCaptain), state: conrad).confirmLabel == "Trade Laser")
        #expect(ConfirmationText.cancelLabel(for: .meetCaptain) == "Decline" && ConfirmationText.cancelLabel(for: .bribe) == "Cancel")
        // Drink: consent, then the tonic line in the log.
        // One click from the destination, so the step ends in the arrival and no second encounter resets the log.
        let s = try EncFx.session(.bottleGood, opponent: .bottle, weapons: [], clicks: 1)
        s.performEncounterAction(.drink)
        guard case let .confirmation(pending) = s.presentation else {
            Issue.record("drinking asks first")
            return
        }
        s.confirm(pending)
        let tonic = String(localized: EventText.text(for: .tonicConsumed(good: true), state: try #require(s.state)))
        #expect(s.encounterUI.log.contains { $0.text == tonic })
    }
}
