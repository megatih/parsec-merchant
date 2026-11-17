// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// UI-ENC-045: plunder the victim's hold. Stays open after each Take; Done answers the decision. It can't be dismissed
/// without Done, so the engine's pending plunder is always resolved.
struct PlunderSheet: View {
    @Environment(GameSession.self) private var session
    let context: PlunderSheetContext
    @State private var amounts: [TradeItemType: Int] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let state = session.state {
                let model = PlunderSheetModel.make(context: context, state: state)
                Text(verbatim: model.title).font(.title2.bold())
                if model.isEmpty {
                    Text("The hold is empty.").foregroundStyle(.secondary)
                } else {
                    ForEach(model.rows, id: \.item) { row in
                        rowView(row, blocker: model.takeBlocker)
                    }
                    if let blocker = model.takeBlocker {
                        Text(ReasonText.text(for: blocker)).foregroundStyle(.secondary)
                    }
                }
                Text("Free bays \(model.freeBays)")
                    .monospacedDigit()
                    .accessibilityIdentifier(AXID.Decision.plunderFreeBays)
                if let reason = session.lastRejection {
                    Text(ReasonText.text(for: reason)).foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Done") {
                    session.dismissPresentation()
                    session.send(PlunderSheetModel.doneCommand)
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier(AXID.Decision.plunderDone)
            }
        }
        .padding(24)
        .frame(minWidth: 460)
        .interactiveDismissDisabled()
        // UI-KEYS-021: Esc and ⌘. press the only button.
        .sheetEscape {
            session.dismissPresentation()
            session.send(PlunderSheetModel.doneCommand)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Decision.plunderSheet)
    }

    private func rowView(_ row: PlunderSheetModel.Row, blocker: CommandError?) -> some View {
        let item = row.item
        let value = Binding { row.clamp(amounts[item] ?? row.maxTake) } set: { amounts[item] = row.clamp($0) }
        return HStack {
            Text(Names.item(item)).frame(minWidth: 90, alignment: .leading)
            Text(verbatim: "\(row.available)").monospacedDigit().foregroundStyle(.secondary)
            Spacer()
            Stepper(value: value, in: 1...max(1, row.maxTake)) {
                Text(verbatim: "\(value.wrappedValue)").monospacedDigit()
            }
            .disabled(!row.canTake)
            .accessibilityIdentifier(AXID.Decision.plunderQuantity(item))
            Button("Take") { session.send(row.takeCommand(value.wrappedValue)) }
                .disabled(!row.canTake)
                .help(blocker.map { Text(ReasonText.text(for: $0)) } ?? Text("Take the chosen amount."))
                .accessibilityIdentifier(AXID.Decision.plunderTake(item))
            Button("Take All") { session.send(row.takeAllCommand) }
                .disabled(!row.canTake)
                .accessibilityIdentifier(AXID.Decision.plunderTakeAll(item))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Decision.plunderRow(item))
    }
}

/// UI-ENC-047: the compact trade-in-orbit offer. Trade is the default (disabled at 0); Decline (Esc) sends 0.
struct TradeInOrbitSheet: View {
    @Environment(GameSession.self) private var session
    let offer: OrbitTradeOffer
    @State private var quantity: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let state = session.state {
                let model = TradeOfferModel.make(offer: offer, state: state)
                let q = model.clamp(quantity ?? model.initialQuantity)
                Text(verbatim: model.title).font(.title2.bold())
                LabeledContent("Price per unit") { Text(verbatim: "\(offer.unitPrice.formatted()) cr.").monospacedDigit() }
                LabeledContent(model.traderBuys ? "You hold" : "Available") {
                    Text(verbatim: offer.unitsAvailable.formatted()).monospacedDigit()
                }
                HStack {
                    Stepper(value: Binding { q } set: { quantity = model.clamp($0) }, in: model.range) {
                        Text("Quantity: \(q) of at most \(offer.maxQuantity)").monospacedDigit()
                    }
                    .accessibilityIdentifier(AXID.Decision.tradeQuantity)
                    Button("Max") { quantity = model.range.upperBound }
                        .accessibilityIdentifier(AXID.Decision.tradeMax)
                }
                LabeledContent("Total") { Text(verbatim: "\(model.total(q).formatted()) cr.").monospacedDigit() }
                if let perUnit = model.profitPerUnit, let total = model.profitTotal(q) {
                    LabeledContent("Profit per unit") { Text(verbatim: TradeOfferModel.signed(perUnit)).monospacedDigit() }
                    LabeledContent("Profit") { Text(verbatim: TradeOfferModel.signed(total)).monospacedDigit() }
                }
                if let after = model.cashAfter(q) {
                    LabeledContent("Cash after the trade") { Text(verbatim: "\(after.formatted()) cr.").monospacedDigit() }
                }
                HStack {
                    Spacer()
                    Button("Decline") { answer(TradeOfferModel.declineCommand) }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier(AXID.Decision.tradeDecline)
                    Button("Trade") { answer(model.acceptCommand(q)) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.canAccept(q))
                        .accessibilityIdentifier(AXID.Decision.tradeAccept)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 420)
        .interactiveDismissDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Decision.tradeSheet)
    }

    private func answer(_ command: Command) {
        session.dismissPresentation()
        session.send(command)
    }
}

/// UI-ENC-049: Make Room — jettison cargo so the canister fits (the Market disposal sheet's identifiers). The sheet states
/// the littering consequence, so Jettison is the consent; with a free bay the scoop dialog returns.
struct EncounterMakeRoomSheet: View {
    @Environment(GameSession.self) private var session
    let item: TradeItemType
    @State private var selected: TradeItemType?
    @State private var quantity = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Make Room for \(Names.item(item))").font(.title2.bold())
            Text("Dumping cargo in space is littering. The police may fine you and your record suffers.")
                .foregroundStyle(.secondary)
            if let state = session.state {
                let model = MakeRoomModel.make(state: state)
                let current = selected ?? model.rows.first?.item
                Picker("Cargo", selection: Binding { current } set: { selected = $0; quantity = 1 }) {
                    ForEach(model.rows, id: \.item) { row in
                        Text("\(Names.item(row.item)) (\(row.held))").tag(Optional(row.item))
                    }
                }
                if let current, let held = model.rows.first(where: { $0.item == current })?.held {
                    Stepper(value: $quantity, in: 1...max(1, held)) {
                        Text("Quantity: \(min(quantity, held)) of at most \(held)").monospacedDigit()
                    }
                    .accessibilityIdentifier(AXID.Market.disposalQuantity)
                    HStack {
                        Spacer()
                        Button("Cancel") { session.endMakeRoom() }
                            .keyboardShortcut(.cancelAction)
                            .accessibilityIdentifier(AXID.Market.disposalCancel)
                        Button("Jettison") { session.makeRoomJettison(current, quantity: min(quantity, held)) }
                            .keyboardShortcut(.defaultAction)
                            .accessibilityIdentifier(AXID.Market.disposalConfirm)
                    }
                } else {
                    Button("Cancel") { session.endMakeRoom() }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier(AXID.Market.disposalCancel)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 420)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Market.disposalSheet)
    }
}
