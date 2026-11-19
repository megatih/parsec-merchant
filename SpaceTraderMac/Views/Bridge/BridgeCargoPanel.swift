// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import ParsecInsights
import SwiftUI

/// The widths of the Cargo table's columns, in design points (PRD §4.2). The Good column takes what is left.
nonisolated enum CargoColumns {
    static let hold: CGFloat = 32
    static let paid: CGFloat = 44
    static let sell: CGFloat = 52
    static let buy: CGFloat = 44
    static let stock: CGFloat = 36
    static let target: CGFloat = 52
    static let delta: CGFloat = 56
    static let quantity: CGFloat = 40
    static let buyButton: CGFloat = 42
    static let maxButton: CGFloat = 44
    static let sellButton: CGFloat = 50
    static let allButton: CGFloat = 40
    static let gap: CGFloat = 6
    static let actionGap: CGFloat = 4
    static let leading: CGFloat = 8
}

/// Region B, Cargo (UI-BRG-001…009): the two summary lines, the column headers and ten rows, one per good.
struct BridgeCargoPanel: View {
    @Environment(GameSession.self) private var session
    @Environment(\.pmScale) private var scale
    let model: BridgeCargoModel
    let rowHeight: CGFloat
    @FocusState private var rowsFocused: Bool
    @Namespace private var rotorNamespace

    var body: some View {
        BridgePanel(identifier: BridgeID.cargo) {
            VStack(alignment: .leading, spacing: 0) {
                summary.frame(height: 40 * scale)
                header.frame(height: 20 * scale)
                rows
            }
        }
    }

    // MARK: Summary

    private var summary: some View {
        HStack(spacing: PMSpace.s * scale) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: PMSpace.s * scale) {
                    BridgeTitle(title: "Cargo")
                    Text("Bays \(model.usedBays)/\(model.totalBays) · \(model.freeBays) free · Cash to spend \(model.cashToSpend.formatted()) cr.")
                        .pmFont(.body).foregroundStyle(PMColor.textPrimary).fixedSize()
                        .help(Text("Free bays and cash after the amounts you chose to keep in reserve"))
                        .probed(BridgeID.Cargo.bays)
                }
                .frame(height: 20 * scale)
                holdLine.frame(height: 20 * scale)
            }
            Spacer(minLength: 0)
            PMButton(title: model.sellAll.commands.isEmpty ? "Sell All Cargo" : "Sell All Cargo \(model.sellAll.proceeds.formatted()) cr.",
                     help: "Sell every good in the hold that this system buys", disabledReason: sellAllReason, identifier: BridgeID.Cargo.sellAll) {
                session.sellAllCargo()
            }
            .fixedSize()
        }
    }

    private var sellAllReason: String? {
        if session.isInputLocked { return String(localized: ReasonText.text(for: .pendingDecisionFirst)) }
        return model.sellAll.blocker.map { String(localized: ReasonText.text(for: $0)) }
    }

    private var holdLine: some View {
        HStack(spacing: PMSpace.xs * scale) {
            if let target = model.targetName, let there = model.holdAtTarget {
                let difference = there.revenue - model.holdHere.revenue
                Text("Hold: here \(model.holdHere.revenue.formatted()) cr. · at \(target) \(there.revenue.formatted()) cr.")
                if there.usesEstimates { Text("est.").foregroundStyle(PMColor.textSecondary) }
                Text(verbatim: BridgeNumbers.signed(difference)).foregroundStyle(BridgeNumbers.tone(difference))
            } else {
                Text("Hold: here \(model.holdHere.revenue.formatted()) cr. · no target selected")
            }
        }
        .pmFont(.body)
        .foregroundStyle(PMColor.textPrimary)
        .fixedSize()
        .accessibilityElement(children: .combine)
        .help(Text("Compare the hold's value here and at the target (estimates, no guarantee)"))
        .probed(BridgeID.Cargo.hold)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: CargoColumns.gap * scale) {
            title("Good").frame(maxWidth: .infinity, alignment: .leading)
            title("Hold").frame(width: CargoColumns.hold * scale, alignment: .trailing)
            title("Paid").frame(width: CargoColumns.paid * scale, alignment: .trailing)
            title("Sell").frame(width: CargoColumns.sell * scale, alignment: .trailing)
            title("Buy").frame(width: CargoColumns.buy * scale, alignment: .trailing)
            title("Stock").frame(width: CargoColumns.stock * scale, alignment: .trailing)
            title("Target")
                .help(Text("Average price at the target. Estimates carry no guarantee"))
                .frame(width: CargoColumns.target * scale, alignment: .trailing)
            title("±")
                .help(Text("The target's price less the price here"))
                .frame(width: CargoColumns.delta * scale, alignment: .trailing)
            title("Quantity").frame(width: Self.actionsWidth * scale, alignment: .leading)
        }
        .padding(.leading, CargoColumns.leading * scale)
        .overlay(alignment: .bottom) { Rectangle().fill(PMColor.strongLine).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .probed(BridgeID.Cargo.header)
    }

    static let actionsWidth = CargoColumns.quantity + CargoColumns.buyButton + CargoColumns.maxButton + CargoColumns.sellButton
        + CargoColumns.allButton + 4 * CargoColumns.actionGap

    private func title(_ text: LocalizedStringResource) -> some View {
        Text(text).pmFont(.caption).foregroundStyle(PMColor.textSecondary).fixedSize()
    }

    // MARK: Rows

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(model.rows) { row in
                BridgeCargoRow(row: row, selected: session.marketSelection == row.item, height: rowHeight, quantity: binding(row.item))
                    .accessibilityRotorEntry(id: row.item, in: rotorNamespace)
            }
        }
        // `.edit` interactions: the rows take the keyboard focus by Tab even without Full Keyboard Access.
        .focusable(true, interactions: .edit)
        .focused($rowsFocused)
        // UI-BRG-007: the Bridge opens with the rows focused, so ↑/↓, B and S work without a click.
        .task {
            try? await Task.sleep(for: .milliseconds(150))
            if !session.isInputLocked { rowsFocused = true }
        }
        .onKeyPress(phases: .down) { press in handleKey(press) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Cargo"))
        // A11Y-014: the "In Hold" and "Profitable at Target" rotors.
        .accessibilityRotor(Text("Cargo Rows")) {
            ForEach(model.rows.map(\.item), id: \.self) { item in
                AccessibilityRotorEntry(Text(Names.item(item)), id: item, in: rotorNamespace)
            }
        }
        .accessibilityRotor(Text("In Hold")) {
            ForEach(MarketRotors.inHold(model.rows.map(\.market)), id: \.self) { item in
                AccessibilityRotorEntry(Text(Names.item(item)), id: item, in: rotorNamespace)
            }
        }
        .accessibilityRotor(Text("Profitable at Target")) {
            ForEach(MarketRotors.profitableAtTarget(model.rows.map(\.market)) { model.row($0)?.targetPrice }, id: \.self) { item in
                AccessibilityRotorEntry(Text(Names.item(item)), id: item, in: rotorNamespace)
            }
        }
        .probed(BridgeID.Cargo.rows)
    }

    private func binding(_ item: TradeItemType) -> Binding<String> {
        Binding { session.cargoQuantities[item] ?? "" } set: { session.cargoQuantities[item] = String($0.filter(\.isNumber).prefix(4)) }
    }

    /// UI-BRG-007: ↑/↓ move the selection; B, ⇧B, S and ⇧S act on the selected row; digits edit its quantity.
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        let items = model.rows.map(\.item)
        switch press.key {
        case .upArrow, .downArrow:
            let current = session.marketSelection.flatMap(items.firstIndex) ?? (press.key == .downArrow ? -1 : items.count)
            let next = min(max(current + (press.key == .downArrow ? 1 : -1), 0), items.count - 1)
            session.marketSelection = items[next]
            return .handled
        default:
            break
        }
        guard let item = session.marketSelection, model.row(item) != nil else { return .ignored }
        let quantities = session.cargoQuantities
        if press.modifiers.isEmpty, press.characters.count == 1, let digit = press.characters.first, digit.isNumber {
            binding(item).wrappedValue = (quantities[item] ?? "") + String(digit)
            return .handled
        }
        if press.key == .delete, !(quantities[item] ?? "").isEmpty {
            session.cargoQuantities[item] = String((quantities[item] ?? "").dropLast())
            return .handled
        }
        guard let action = MarketKeyAction.make(characters: press.characters, modifiers: press.modifiers) else { return .ignored }
        session.performTrade(action)
        return .handled
    }
}

/// One good: eight values and five controls (UI-BRG-002).
struct BridgeCargoRow: View {
    @Environment(GameSession.self) private var session
    @Environment(\.pmScale) private var scale
    let row: BridgeCargoModel.Row
    let selected: Bool
    let height: CGFloat
    @Binding var quantity: String
    @State private var hovering = false

    private var item: TradeItemType { row.item }
    private var market: MarketRowModel { row.market }

    var body: some View {
        HStack(spacing: CargoColumns.gap * scale) {
            good.frame(maxWidth: .infinity, alignment: .leading)
            number(market.row.held, dimZero: true, id: BridgeID.Cargo.hold(item)).frame(width: CargoColumns.hold * scale, alignment: .trailing)
            paid.frame(width: CargoColumns.paid * scale, alignment: .trailing)
            sell.frame(width: CargoColumns.sell * scale, alignment: .trailing)
            buy.frame(width: CargoColumns.buy * scale, alignment: .trailing)
            number(market.row.stock, dimZero: true, id: BridgeID.Cargo.stock(item)).frame(width: CargoColumns.stock * scale, alignment: .trailing)
            target.frame(width: CargoColumns.target * scale, alignment: .trailing)
            delta.frame(width: CargoColumns.delta * scale, alignment: .trailing)
            actions
        }
        .padding(.leading, CargoColumns.leading * scale)
        .frame(height: height)
        .background(selected ? PMColor.panelRaised : (hovering ? PMColor.panelRaised.opacity(0.5) : .clear))
        .overlay(alignment: .leading) {
            if selected { Rectangle().fill(PMColor.accent).frame(width: 3 * scale) }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(PMColor.hairline).frame(height: 1) }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .hoverHighlight(cornerRadius: PMRadius.control)
        .onTapGesture { session.marketSelection = item }
        .contextMenu { menu }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(Names.item(item)))
        // UI-HIG-005: the row reads as one sentence and offers the four trades as actions.
        .accessibilityValue(Text(verbatim: MarketRowAccessibility.make(market, target: row.targetPrice).value))
        .accessibilityAction(named: Text("Buy")) { trade(.buy) }
        .accessibilityAction(named: Text("Buy Maximum")) { trade(.buyMax) }
        .accessibilityAction(named: Text("Sell")) { trade(.sell) }
        .accessibilityAction(named: Text("Sell All")) { trade(.sellAll) }
        // UI-HIG-003: one Tab stop for the table (the arrow keys move inside it); the rows are not stops of their own.
        .accessibilityRespondsToUserInteraction(false)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .probed(BridgeID.Cargo.row(item))
    }

    private func trade(_ action: MarketKeyAction) {
        session.marketSelection = item
        session.performTrade(action)
    }

    // MARK: Values

    private var good: some View {
        HStack(spacing: PMSpace.xs * scale) {
            Text(Names.item(item)).pmFont(.body).foregroundStyle(PMColor.textPrimary)
            if market.isIllegal {
                // UI-BRG-009: the symbol and the word, never colour alone.
                Label { Text("Illegal") } icon: { Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true) }
                    .labelStyle(.titleAndIcon)
                    .pmFont(.caption)
                    .foregroundStyle(PMColor.caution)
                    .help(Text("The police confiscate this good and fine you when they find it"))
            }
            if row.bestBuy {
                Image(systemName: "star.fill").pmFont(.caption).foregroundStyle(PMColor.accent)
                    .help(Text("Best buy for the target"))
                    .accessibilityLabel(Text("Best buy"))
            }
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
        .probed(BridgeID.Cargo.good(item))
    }

    private func number(_ value: Int, dimZero: Bool, id: String) -> some View {
        Text(verbatim: value.formatted()).pmFont(.value)
            .foregroundStyle(dimZero && value == 0 ? PMColor.textSecondary : PMColor.textPrimary)
            .fixedSize()
            .probed(id)
    }

    private var paid: some View {
        Group {
            if market.row.held > 0 {
                Text(verbatim: market.row.costBasisPerUnit.formatted()).pmFont(.value).foregroundStyle(PMColor.textPrimary)
            } else {
                dash(label: "Not held")
            }
        }
        .fixedSize()
        .probed(BridgeID.Cargo.paid(item))
    }

    private var sell: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if let price = market.sellPrice {
                Text(verbatim: price.formatted()).pmFont(.value).foregroundStyle(PMColor.textPrimary)
                if let gain = row.gainPerUnit {
                    Text(verbatim: BridgeNumbers.signed(gain)).pmFont(.caption).foregroundStyle(BridgeNumbers.tone(gain))
                        .help(Text("The sell price here less the price you paid"))
                }
            } else {
                Text("no trade").pmFont(.caption).foregroundStyle(PMColor.textSecondary).help(Text(ReasonText.text(for: .marketNotInterested)))
            }
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
        .probed(BridgeID.Cargo.sellPrice(item))
    }

    private var buy: some View {
        Group {
            if let price = market.buyPrice {
                Text(verbatim: price.formatted()).pmFont(.value).foregroundStyle(PMColor.textPrimary)
            } else {
                Text("not sold").pmFont(.caption).foregroundStyle(PMColor.textSecondary).help(Text(ReasonText.text(for: .notSoldHere)))
            }
        }
        .fixedSize()
        .probed(BridgeID.Cargo.buyPrice(item))
    }

    /// UI-BRG-005: the target's price always carries its tag ("est." or its age); "—" without a quote.
    private var target: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if let quote = row.quote, let price = quote.sell {
                Text(verbatim: price.formatted()).pmFont(.value).foregroundStyle(PMColor.textPrimary)
                Text(verbatim: IntelText.age(quote)).pmFont(.caption).foregroundStyle(PMColor.textSecondary)
            } else {
                dash(label: "No target price")
            }
        }
        .fixedSize()
        .opacity(row.quote?.staleness == .old ? 0.7 : 1)
        .help(row.quote.map { Text(verbatim: IntelText.help($0)) } ?? Text("Select a target system on the chart"))
        .accessibilityElement(children: .combine)
        .probed(BridgeID.Cargo.target(item))
    }

    private var delta: some View {
        Group {
            if let delta = row.delta {
                Text(verbatim: BridgeNumbers.signed(delta)).pmFont(.value).fontWeight(row.deltaIsBold ? .bold : .regular)
                    .foregroundStyle(BridgeNumbers.tone(delta))
            } else {
                dash(label: "No difference")
            }
        }
        .fixedSize()
        .probed(BridgeID.Cargo.delta(item))
    }

    private func dash(label: LocalizedStringResource) -> some View {
        // A11Y-029: a symbol, not a dash glyph too thin for the contrast audit to measure.
        Image(systemName: "minus").pmFont(.value).foregroundStyle(PMColor.textSecondary).accessibilityLabel(Text(label))
    }

    // MARK: Controls

    private var actions: some View {
        HStack(spacing: CargoColumns.actionGap * scale) {
            PMField(text: $quantity, prompt: "1", label: "Quantity of \(Names.item(item))", invalid: BridgeCargoModel.Row.quantity(quantity) == nil,
                    identifier: BridgeID.Cargo.quantity(item))
                .onFocusChange { session.textEntryFocused = $0 }
                .frame(width: CargoColumns.quantity * scale)
                // UI-KEYS-022: Return in the field buys the typed quantity.
                .onSubmit { send(row.buyCommand(text: quantity)) }
            button("Buy", width: CargoColumns.buyButton, reason: market.buyBlocker, help: "Buy the quantity", id: BridgeID.Cargo.buy(item)) {
                send(row.buyCommand(text: quantity))
            }
            button("Max", width: CargoColumns.maxButton, reason: market.buyBlocker, help: "Buy as many as you can afford and carry",
                   id: BridgeID.Cargo.max(item)) {
                send(row.maxCommand)
            }
            if market.isDumpMode {
                button("Dump", width: CargoColumns.sellButton, reason: row.sellBlocker, help: "Pay to have this good taken away",
                       id: BridgeID.Cargo.sell(item)) {
                    if let disposal = CargoDisposal.dump(market) { session.showCargoDisposal(disposal) }
                }
            } else {
                button("Sell", width: CargoColumns.sellButton, reason: row.sellBlocker, help: "Sell the quantity", id: BridgeID.Cargo.sell(item)) {
                    send(row.sellCommand(text: quantity))
                }
            }
            button("All", width: CargoColumns.allButton, reason: row.allBlocker, help: "Sell every unit you hold", id: BridgeID.Cargo.all(item)) {
                send(row.allCommand)
            }
        }
    }

    private func button(_ title: LocalizedStringResource, width: CGFloat, reason: CommandError?, help: LocalizedStringResource, id: String,
                        action: @escaping () -> Void) -> some View {
        PMButton(title: title, compact: true, help: help, disabledReason: reason.map { String(localized: ReasonText.text(for: $0)) }, identifier: id) {
            session.marketSelection = item
            action()
        }
        .fixedSize()
        .frame(width: width * scale)
    }

    private func send(_ command: Command?) {
        guard let command else {
            // A quantity that is not a number: the field shows its error ring.
            return
        }
        session.send(command)
        quantity = ""
    }

    /// UI-BRG-008: every item is also a button of the row or a menu-bar command.
    @ViewBuilder
    private var menu: some View {
        Button("Buy") { send(row.buyCommand(text: quantity)) }.disabled(market.buyBlocker != nil)
        Button("Buy Maximum") { send(row.maxCommand) }.disabled(market.buyBlocker != nil)
        Button("Sell") { send(row.sellCommand(text: quantity)) }.disabled(market.isDumpMode || row.sellBlocker != nil)
        Button("Sell All") { send(row.allCommand) }.disabled(row.allBlocker != nil)
        Button("Dump…") {
            if let disposal = CargoDisposal.dump(market) { session.showCargoDisposal(disposal) }
        }
        .disabled(CargoDisposal.dump(market) == nil)
        Divider()
        Button("Price Details…") { session.showPriceDetails(item) }
    }
}
