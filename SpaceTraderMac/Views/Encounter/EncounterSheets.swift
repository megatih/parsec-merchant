// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// UI-ENC-205: one good in a sheet: its name, a count, the Quantity field and the row's buttons, in the Cargo region's
/// vocabulary (Quantity, Max, All).
private struct SheetGoodRow<Buttons: View>: View {
    let item: TradeItemType
    let count: Text
    let identifier: String
    @ViewBuilder var buttons: () -> Buttons

    var body: some View {
        HStack(spacing: PMSpace.s) {
            Text(Names.item(item)).pmFont(.value).foregroundStyle(PMColor.textPrimary).frame(minWidth: 96, alignment: .leading)
            count.pmFont(.body).foregroundStyle(PMColor.textSecondary)
            Spacer(minLength: PMSpace.s)
            buttons()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

/// UI-ENC-045: plunder the victim's hold. Stays open after each Take; Done answers the decision. It can't be dismissed
/// without Done, so the engine's pending plunder is always resolved.
struct PlunderSheet: View {
    @Environment(GameSession.self) private var session
    let context: PlunderSheetContext
    @State private var amounts: [TradeItemType: Int] = [:]

    var body: some View {
        let model = session.state.map { PlunderSheetModel.make(context: context, state: $0) }
        PMSheet(title: Text(verbatim: model?.title ?? ""), width: 520, identifier: AXID.Decision.plunderSheet) {
            if let model {
                if model.isEmpty {
                    Text("The hold is empty.").pmFont(.body).foregroundStyle(PMColor.textSecondary)
                } else {
                    ForEach(model.rows, id: \.item) { row in
                        rowView(row, blocker: model.takeBlocker)
                    }
                    if let blocker = model.takeBlocker {
                        Text(ReasonText.text(for: blocker)).pmFont(.body).foregroundStyle(PMColor.caution)
                    }
                }
                PMDivider()
                Text("Free bays \(model.freeBays)")
                    .pmFont(.value)
                    .foregroundStyle(PMColor.textPrimary)
                    .accessibilityIdentifier(AXID.Decision.plunderFreeBays)
                if let reason = session.lastRejection {
                    Text(ReasonText.text(for: reason)).pmFont(.body).foregroundStyle(PMColor.caution)
                }
            }
        } buttons: {
            Button("Done", action: done)
                .pmDefaultAction()
                .accessibilityIdentifier(AXID.Decision.plunderDone)
        }
        .interactiveDismissDisabled()
        // UI-KEYS-021: Esc and ⌘. press the only button.
        .sheetEscape(done)
    }

    private func done() {
        session.dismissPresentation()
        session.send(PlunderSheetModel.doneCommand)
    }

    private func rowView(_ row: PlunderSheetModel.Row, blocker: CommandError?) -> some View {
        let item = row.item
        let value = Binding { row.clamp(amounts[item] ?? row.maxTake) } set: { amounts[item] = row.clamp($0) }
        let why = blocker.map { ReasonText.string(for: $0) }
        return SheetGoodRow(item: item, count: Text("\(row.available) aboard"), identifier: AXID.Decision.plunderRow(item)) {
            PMQuantityField(value: value, range: 1...max(1, row.maxTake), label: "Quantity of \(Names.item(item))",
                            identifier: AXID.Decision.plunderQuantity(item))
                .disabled(!row.canTake)
                .help(row.canTake ? Text("Type how many to take") : Text(verbatim: why ?? ""))
            PMButton(title: "Take", help: "Take the quantity you typed", disabledReason: row.canTake ? nil : why,
                     identifier: AXID.Decision.plunderTake(item)) {
                session.send(row.takeCommand(value.wrappedValue))
            }
            PMButton(title: "All", help: "Take as many as fit in your hold", disabledReason: row.canTake ? nil : why,
                     identifier: AXID.Decision.plunderTakeAll(item)) {
                session.send(row.takeAllCommand)
            }
        }
    }
}

/// UI-ENC-047: the compact trade-in-orbit offer. Trade is the default (disabled at 0); Decline (Esc) sends 0.
struct TradeInOrbitSheet: View {
    @Environment(GameSession.self) private var session
    let offer: OrbitTradeOffer
    @State private var quantity: Int?

    var body: some View {
        let model = session.state.map { TradeOfferModel.make(offer: offer, state: $0) }
        let q = model.map { $0.clamp(quantity ?? $0.initialQuantity) } ?? 0
        PMSheet(title: Text(verbatim: model?.title ?? ""), identifier: AXID.Decision.tradeSheet) {
            if let model {
                let value = Binding { q } set: { quantity = model.clamp($0) }
                SheetGoodRow(item: offer.item,
                             count: model.traderBuys ? Text("\(offer.unitsAvailable) in your hold") : Text("\(offer.unitsAvailable) offered"),
                             identifier: AXID.Decision.tradeRow) {
                    PMQuantityField(value: value, range: model.range, label: "Quantity", identifier: AXID.Decision.tradeQuantity)
                    PMButton(title: "Max", help: "The most you can trade: \(offer.maxQuantity.formatted())", identifier: AXID.Decision.tradeMax) {
                        quantity = model.range.upperBound
                    }
                }
                PMDivider()
                PMInfoRow(label: "Price per unit") { Text("\(offer.unitPrice.formatted()) cr.") }
                PMInfoRow(label: "Quantity") { Text("\(q.formatted()) of at most \(offer.maxQuantity.formatted())") }
                PMInfoRow(label: "Total") { Text("\(model.total(q).formatted()) cr.") }
                if let perUnit = model.profitPerUnit, let total = model.profitTotal(q) {
                    PMInfoRow(label: "Profit per unit") { Text(verbatim: TradeOfferModel.signed(perUnit)) }
                    PMInfoRow(label: "Profit") { Text(verbatim: TradeOfferModel.signed(total)) }
                }
                if let after = model.cashAfter(q) {
                    PMInfoRow(label: "Cash after the trade") { Text("\(after.formatted()) cr.") }
                }
            }
        } buttons: {
            Button("Decline") { answer(TradeOfferModel.declineCommand) }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier(AXID.Decision.tradeDecline)
            Button("Trade") { if let model { answer(model.acceptCommand(q)) } }
                .pmDefaultAction()
                .disabled(model?.canAccept(q) != true)
                .help(model?.canAccept(q) == true ? Text("Trade the quantity shown") : Text("Choose a quantity you can pay for and carry."))  // UI-KEYS-035
                .accessibilityIdentifier(AXID.Decision.tradeAccept)
        }
        .interactiveDismissDisabled()
    }

    private func answer(_ command: Command) {
        session.dismissPresentation()
        session.send(command)
    }
}

/// UI-ENC-049: Make Room — jettison cargo so the canister fits, one row per good aboard. The sheet states the littering
/// consequence, so Jettison is the consent; with a free bay the scoop dialog returns.
struct EncounterMakeRoomSheet: View {
    @Environment(GameSession.self) private var session
    let item: TradeItemType
    @State private var amounts: [TradeItemType: Int] = [:]

    var body: some View {
        PMSheet(title: Text("Make Room for \(Names.item(item))"), width: 520, identifier: AXID.Market.disposalSheet) {
            Text("Dumping cargo in space is littering. The police may fine you and your record suffers.")
                .pmFont(.body)
                .foregroundStyle(PMColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let state = session.state {
                ForEach(MakeRoomModel.make(state: state).rows, id: \.item) { row in
                    let held = max(1, row.held)
                    let value = Binding { min(max(1, amounts[row.item] ?? 1), held) } set: { amounts[row.item] = min(max(1, $0), held) }
                    SheetGoodRow(item: row.item, count: Text("\(row.held) aboard"), identifier: AXID.Decision.makeRoomRow(row.item)) {
                        PMQuantityField(value: value, range: 1...held, label: "Quantity of \(Names.item(row.item))",
                                        identifier: AXID.Decision.makeRoomQuantity(row.item))
                        PMButton(title: "Jettison", help: "Jettison the quantity you typed", identifier: AXID.Decision.makeRoomJettison(row.item)) {
                            session.makeRoomJettison(row.item, quantity: value.wrappedValue)
                        }
                        PMButton(title: "All", help: "Jettison every unit of this good", identifier: AXID.Decision.makeRoomAll(row.item)) {
                            session.makeRoomJettison(row.item, quantity: row.held)
                        }
                    }
                }
            }
        } buttons: {
            Button("Cancel") { session.endMakeRoom() }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier(AXID.Market.disposalCancel)
        }
    }
}
