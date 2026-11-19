// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import ParsecInsights
import SwiftUI

/// UI-BRG-008: Price Details…: the "Why this price?" breakdown and the remembered sell prices of one good here.
struct PriceDetailsSheet: View {
    @Environment(GameSession.self) private var session
    let item: TradeItemType

    var body: some View {
        let row = session.bridgeIntel?.intel.row(item)
        VStack(alignment: .leading, spacing: 14) {
            Text("Price Details: \(Text(Names.item(item)))").pmFont(.title).accessibilityAddTraits(.isHeader)
            PriceExplanationPanel(item: item, explanation: row?.explanation)
            HStack(spacing: 12) {
                Text("Sell prices on your visits here").foregroundStyle(PMColor.textSecondary)
                PriceSparkline(item: item, series: row?.history ?? [])
                Spacer()
            }
            if let advice = row?.sellAdvice, let state = session.state {
                Text(verbatim: IntelText.sellAdvice(advice, systemName: { Names.system($0, in: state) }, today: state.commander.days))
                    .pmFont(.body)
                    .accessibilityIdentifier(AXID.Market.priceDetailsAdvice)
            }
            HStack {
                Spacer()
                Button("Done") { session.dismissPresentation() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(PMButtonStyle(kind: .primary))
                    .accessibilityIdentifier(AXID.Market.priceDetailsDone)
            }
        }
        .padding(PMSpace.xl)
        .frame(width: 460)
        .sheetEscape { session.dismissPresentation() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Market.priceDetailsSheet)
    }
}

/// UI-SHELL-065: the quantity to dump (docked) or jettison (in space).
struct CargoDisposalSheet: View {
    @Environment(GameSession.self) private var session
    let disposal: CargoDisposal
    @State private var quantity = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(disposal.kind == .jettison ? "Jettison \(Names.item(disposal.item))" : "Dump \(Names.item(disposal.item))")
                .pmFont(.title)
            Stepper(value: $quantity, in: 1...max(1, disposal.maximum)) {
                Text("Quantity: \(quantity) of at most \(disposal.maximum)").monospacedDigit()
            }
            .accessibilityLabel(Text("Quantity"))
            .accessibilityValue(Text(verbatim: AccessibilityText.units(quantity)))
            QuantityChips(value: $quantity, range: 1...max(1, disposal.maximum), idPrefix: AXID.Market.disposalQuantity)
                .accessibilityIdentifier(AXID.Market.disposalQuantity)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { session.dismissPresentation() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier(AXID.Market.disposalCancel)
                Button(disposal.kind == .jettison ? "Jettison" : "Dump") {
                    let command = disposal.command(quantity: quantity)
                    session.dismissPresentation()
                    if let command { session.send(command) }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(PMButtonStyle(kind: .primary))
                .accessibilityIdentifier(AXID.Market.disposalConfirm)
            }
        }
        .padding(PMSpace.xl)
        .frame(width: 360)
        .onAppear { quantity = max(1, disposal.maximum) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Market.disposalSheet)
    }
}

/// PRD §4.2: a partial fuel or repair purchase, in credits (Trade › Buy Fuel…, Repair…).
struct ServiceAmountSheet: View {
    @Environment(GameSession.self) private var session
    let kind: DockServiceModel.Kind
    @State private var amount = 0

    private var isFuel: Bool { kind == .fuel }

    var body: some View {
        let model = session.state.map { isFuel ? DockServiceModel.fuel(state: $0) : DockServiceModel.hull(state: $0) }
        VStack(alignment: .leading, spacing: 14) {
            Text(isFuel ? "Buy Fuel" : "Repair Hull").pmFont(.title).accessibilityAddTraits(.isHeader)
            if let model {
                Text(isFuel ? "Fuel \(model.current)/\(model.maximum) parsecs · \(model.unitCost.formatted()) cr. per parsec"
                         : "Hull \(model.percent)% · \(model.unitCost.formatted()) cr. per point")
                    .foregroundStyle(PMColor.textSecondary)
                if let range = model.amountRange {
                    HStack {
                        if range.lowerBound < range.upperBound {
                            Slider(value: Binding { Double(min(max(amount, range.lowerBound), range.upperBound)) } set: { amount = Int($0.rounded()) },
                                   in: Double(range.lowerBound)...Double(range.upperBound))
                                .accessibilityLabel(Text(isFuel ? "Fuel amount in credits" : "Repair amount in credits"))
                                .accessibilityIdentifier(isFuel ? AXID.Bridge.fuelSlider : AXID.Bridge.repairSlider)
                        }
                        TextField(value: $amount, format: .number) { Text("Credits") }
                            .frame(width: 90)
                            .monospacedDigit()
                            .accessibilityIdentifier(isFuel ? AXID.Bridge.fuelAmount : AXID.Bridge.repairAmount)
                        Text("cr.")
                    }
                } else if let blocker = model.blocker {
                    Text(ReasonText.text(for: blocker)).foregroundStyle(PMColor.textSecondary)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { session.dismissPresentation() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier(AXID.Bridge.serviceCancel)
                Button(isFuel ? "Buy Fuel" : "Repair") {
                    let command = model?.partialCommand(credits: amount)
                    session.dismissPresentation()
                    if let command { session.send(command) }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(PMButtonStyle(kind: .primary))
                .disabled(model?.partialCommand(credits: amount) == nil)
                .help(Text(isFuel ? "Buy fuel for this many credits" : "Repair the hull for this many credits"))
                .accessibilityIdentifier(isFuel ? AXID.Bridge.fuelBuy : AXID.Bridge.repairBuy)
            }
        }
        .padding(PMSpace.xl)
        .frame(width: 400)
        .onAppear { amount = model?.defaultAmount ?? 0 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Bridge.serviceSheet)
    }
}
