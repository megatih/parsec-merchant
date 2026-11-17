// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import ParsecInsights
import SwiftUI

/// Market (⌘2, UI-SHELL §8): one merged trade table (buy and sell), the item filter and the footer, with the M10 trade
/// intelligence (INT §7): Target and History columns, the recommendations strip, "Why this price?" and the projection.
struct MarketSectionView: View {
    @Environment(GameSession.self) private var session
    @AppStorage(AppSettingsKey.showRecommendations) private var showRecommendations = true
    @State private var intel: MarketIntelModel?
    @State private var filter = ""
    @State private var quantities: [TradeItemType: String] = [:]
    @State private var disposal: CargoDisposal?
    @FocusState private var focusedField: Field?
    @Namespace private var rotorNamespace

    enum Field: Hashable {
        case filter
        case quantity(TradeItemType)
    }

    var body: some View {
        @Bindable var session = session
        if let state = session.state {
            let rows = MarketFilter.filtered(MarketRowModel.rows(state: state), filter: filter)
            VStack(spacing: 0) {
                InlineTipView(tip: MarketTip(), id: .market, margin: 12)  // A11Y-043, INT-044
                filterBar
                if showRecommendations, let intel {
                    RecommendationStripView(intel: intel, state: state) { self.session.marketSelection = $0 }
                    Divider()
                }
                Table(rows, selection: $session.marketSelection) {
                    TableColumn("Item") { (r: MarketRowModel) in
                        ItemCell(row: r) { kind in performRowAction(kind, r) }
                            .accessibilityRotorEntry(id: r.item, in: rotorNamespace)
                    }
                        .width(min: 130, ideal: 160)
                    TableColumn("Buy") { (r: MarketRowModel) in
                        PriceCell(price: r.buyPrice).accessibilityIdentifier(AXID.Market.buyPrice(r.item))
                    }
                        .width(min: 60, ideal: 70)
                    TableColumn("Sell") { (r: MarketRowModel) in SellCell(row: r) }
                        .width(min: 70, ideal: 90)
                    TableColumn("Stock") { (r: MarketRowModel) in
                        Text(verbatim: r.row.stock.formatted()).monospacedDigit()
                    }
                    .width(min: 44, ideal: 50)
                    TableColumn("Held") { (r: MarketRowModel) in heldCell(r) }
                        .width(min: 80, ideal: 100)
                    TableColumn("P/L") { (r: MarketRowModel) in ProfitCell(value: r.profitPerUnit) }
                        .width(min: 60, ideal: 70)
                    TableColumn("Target") { (r: MarketRowModel) in
                        let i = intel?.row(r.item)
                        IntelTargetCell(item: r.item, quote: i?.targetQuote, buyHere: r.buyPrice, profitPerBay: i?.profitPerBay)
                    }
                    .width(min: 130, ideal: 170)
                    TableColumn("History") { (r: MarketRowModel) in
                        PriceSparkline(item: r.item, series: intel?.row(r.item)?.history ?? [])
                    }
                    .width(min: 70, ideal: 80)
                    TableColumn("Actions") { (r: MarketRowModel) in actionsCell(r) }
                        .width(min: 280, ideal: 300)
                }
                .onKeyPress(phases: .down) { press in handleKey(press, rows: rows) }
                .accessibilityLabel(Text("Market"))
                .modifier(MarketRotorsModifier(rows: rows, intel: intel, namespace: rotorNamespace))
                .accessibilityIdentifier(AXID.Market.table)
                Divider()
                PriceExplanationPanel(item: session.marketSelection,
                                      explanation: session.marketSelection.flatMap { intel?.row($0)?.explanation })
                Divider()
                footer(MarketFooterModel.make(state: state), state: state)
            }
            .task(id: IntelBuildKey(generation: session.stateGeneration, journal: session.journalRevision)) {
                // INT-029: rebuilt once per state generation or journal change, off the main actor.
                let inputs = MarketIntelModel.Inputs.make(state: state, journal: session.journal)
                let built = await MarketIntelModel.build(inputs)
                if !Task.isCancelled { intel = built }
            }
            .focusedSceneValue(\.marketFilterFocus, MarketFilterFocusAction { focusedField = .filter })
            .sheet(item: $disposal) { d in
                DisposalSheet(disposal: d) { command in
                    disposal = nil
                    if let command { self.session.send(command) }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AXID.SectionRoot.root(.market))
        }
    }

    // MARK: Filter (UI-SHELL-067)

    private var filterBar: some View {
        HStack {
            Image(systemName: "line.3.horizontal.decrease.circle").foregroundStyle(.readableSecondary).accessibilityHidden(true)
            TextField(text: $filter) { Text("Filter items") }
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
                .focused($focusedField, equals: .filter)
                .onExitCommand { filter = "" }
                .help(Text("Show only items whose name contains this text. Esc clears it."))
                .accessibilityLabel(Text("Filter items"))  // A11Y-003
                .accessibilityIdentifier(AXID.Market.filter)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: Keyboard (UI-SHELL-064)

    private func handleKey(_ press: KeyPress, rows: [MarketRowModel]) -> KeyPress.Result {
        guard focusedField == nil,
              let action = MarketKeyAction.make(characters: press.characters, modifiers: press.modifiers),
              let selected = session.marketSelection,
              let row = rows.first(where: { $0.item == selected }) else { return .ignored }
        if let command = action.command(for: row) { session.send(command) }
        return .handled
    }

    // MARK: Cells

    private func heldCell(_ r: MarketRowModel) -> some View {
        let advice = intel?.row(r.item)?.sellAdvice
        return VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: r.row.held.formatted()).monospacedDigit()
                .accessibilityIdentifier(AXID.Market.held(r.item))
            if r.row.held > 0 {
                Text("avg \(r.row.costBasisPerUnit.formatted()) cr.").scaledFont(.caption).foregroundStyle(.readableSecondary).monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        // INT-035: the sell advice.
        .help(advice.flatMap { a in
            session.state.map { st in IntelText.sellAdvice(a, systemName: { Names.system($0, in: st) }, today: st.commander.days) }
        } ?? "")
        .contextMenu {
            if let j = CargoDisposal.jettison(r) {
                Button("Jettison…") { disposal = j }
                    .accessibilityIdentifier(AXID.Market.jettison(r.item))
            }
            if let d = CargoDisposal.dump(r) {
                Button("Dump…") { disposal = d }
                    .accessibilityIdentifier(AXID.Market.dump(r.item))
            }
        }
    }

    private func actionsCell(_ r: MarketRowModel) -> some View {
        let buyReason = r.buyBlocker.map { ReasonText.string(for: $0) }
        let sellReason = r.sellBlocker.map { ReasonText.string(for: $0) }
        return HStack(spacing: 6) {
            Button {
                let modifiers = TradeQuantity.current
                if TradeQuantity.snaps(modifiers: modifiers, maximum: r.row.maxSell) { session.performHaptic(.quantitySnap) }
                if let c = r.sellCommand(modifiers: modifiers) { session.send(c) }
            } label: {
                if r.isDumpMode { Text("Dump") } else { Image(systemName: "minus") }
            }
            .disabled(r.sellBlocker != nil)
            .help(sellReason ?? String(localized: r.isDumpMode
                ? "Dump 1 (⇧ 5, ⌘ 20, ⇧⌘ 100, ⌥ all)" : "Sell 1 (⇧ 5, ⌘ 20, ⇧⌘ 100, ⌥ all)"))
            .accessibilityLabel(Text(r.isDumpMode ? "Dump" : "Sell"))
            .accessibilityHint(Text(AccessibilityHints.tradeModifiers))  // A11Y-005
            .accessibilityIdentifier(AXID.Market.sell(r.item))
            TextField(text: quantityBinding(r.item)) { Text("Qty") }
                .frame(width: 48)
                .monospacedDigit()
                .focused($focusedField, equals: .quantity(r.item))
                .onSubmit { submitField(r, sell: false) }
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.shift) else { return .ignored }
                    submitField(r, sell: true)
                    return .handled
                }
                .help(Text("Return buys this many, ⇧Return sells them."))
                .accessibilityLabel(Text("Quantity of \(Names.item(r.item))"))  // A11Y-003
                .accessibilityIdentifier(AXID.Market.quantity(r.item))
            Button {
                let modifiers = TradeQuantity.current
                if TradeQuantity.snaps(modifiers: modifiers, maximum: r.row.maxBuy) { session.performHaptic(.quantitySnap) }
                if let c = r.buyCommand(modifiers: modifiers) { session.send(c) }
            } label: {
                Image(systemName: "plus")
            }
            .disabled(r.buyBlocker != nil)
            .help(buyReason ?? String(localized: "Buy 1 (⇧ 5, ⌘ 20, ⇧⌘ 100, ⌥ max)"))
            .accessibilityLabel(Text("Buy"))
            .accessibilityHint(Text(AccessibilityHints.tradeModifiers))  // A11Y-005
            .accessibilityIdentifier(AXID.Market.buy(r.item))
            Button("Max") {
                if let c = r.buyMaxCommand { session.send(c) }
            }
            .disabled(r.buyBlocker != nil)
            .help(buyReason ?? String(localized: "Buy as many as you can (\(r.row.maxBuy))"))
            .accessibilityLabel(Text("Buy Max"))
            .accessibilityIdentifier(AXID.Market.buyMax(r.item))
            Button(r.isDumpMode ? "Dump All" : "All") {
                if let c = r.sellAllCommand { session.send(c) }
            }
            .disabled(r.sellBlocker != nil)
            .help(sellReason ?? String(localized: r.isDumpMode ? "Dump all \(r.row.maxSell)" : "Sell all \(r.row.maxSell)"))
            .accessibilityLabel(Text(r.isDumpMode ? "Dump All" : "Sell All"))
            .accessibilityIdentifier(AXID.Market.sellAll(r.item))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    /// A11Y-007: a row's custom action. Trades from assistive actions announce their result (A11Y-012).
    private func performRowAction(_ kind: RowAction.Kind, _ r: MarketRowModel) {
        if kind == .whyThisPrice {
            session.marketSelection = r.item
        } else if let c = MarketRowAccessibility.command(kind, row: r) {
            session.sendFromKeyboard(c)
        }
    }

    private func quantityBinding(_ item: TradeItemType) -> Binding<String> {
        Binding { quantities[item] ?? "" } set: { quantities[item] = $0 }
    }

    private func submitField(_ r: MarketRowModel, sell: Bool) {
        guard let c = r.fieldCommand(text: quantities[r.item] ?? "", sell: sell) else { return }
        session.send(c)
        quantities[r.item] = ""
    }

    // MARK: Footer (UI-SHELL-066)

    private func footer(_ f: MarketFooterModel, state: GameState) -> some View {
        HStack(spacing: 24) {
            Text("Bays: \(f.usedBays)/\(f.totalBays), \(f.freeForBuying) free for buying").monospacedDigit()
            Text("Cash available: \(f.cashAvailable.formatted()) cr.").monospacedDigit()
            if let hold = intel?.holdAtTarget, let target = intel?.target {
                // INT-034: the projected profit of the hold at the target.
                Text(verbatim: IntelText.holdProjection(hold, target: Names.system(target, in: state)))
                    .monospacedDigit()
                    .accessibilityIdentifier(AXID.MarketIntel.footerProjected)
            }
            Spacer()
        }
        .scaledFont(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Market.footer)
    }
}

// MARK: - Cells

private struct ItemCell: View {
    let row: MarketRowModel
    /// A11Y-007: the row's custom actions.
    var perform: (RowAction.Kind) -> Void = { _ in }

    var body: some View {
        let a11y = MarketRowAccessibility.make(row)
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: a11y.label))
            .accessibilityAddTraits(.isStaticText)
            .accessibilityValue(Text(verbatim: row.isIllegal ? String(localized: "Illegal. \(a11y.value)") : a11y.value))
            .accessibilityActions {
                ForEach(a11y.actions) { action in
                    Button(action.name) { perform(action.kind) }
                }
            }
            .accessibilityIdentifier(AXID.Market.row(row.item))
    }

    private var content: some View {
        HStack(spacing: 6) {
            Image(systemName: "shippingbox").foregroundStyle(.readableSecondary).accessibilityHidden(true)
            Text(Names.item(row.item))
            if row.isIllegal {
                Text("Illegal")
                    .scaledFont(.caption2, weight: .bold)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.red.opacity(0.2)))
                    .help(Text("Trading this is illegal; police may confiscate it."))
            }
        }
    }
}

private struct PriceCell: View {
    let price: Int?

    var body: some View {
        if let price {
            Text(verbatim: price.formatted()).monospacedDigit()
        } else {
            Image(systemName: "minus").accessibilityLabel(Text("Not available"))  // A11Y-029: a dash glyph is too thin to measure
        }
    }
}

private struct SellCell: View {
    let row: MarketRowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PriceCell(price: row.sellPrice)
            if let dump = row.dumpCostShown {
                Text("Dump \(dump.formatted()) cr.").scaledFont(.caption).foregroundStyle(.readableSecondary).monospacedDigit()
            }
        }
    }
}

/// A signed amount with ▲/▼ and green/red (never color alone).
private struct ProfitCell: View {
    let value: Int?

    var body: some View {
        if let value {
            let text = (value > 0 ? "▲ +" : value < 0 ? "▼ " : "") + value.formatted()
            Text(verbatim: text)
                .monospacedDigit()
                .foregroundStyle(value > 0 ? Color.signalGreen : value < 0 ? Color.signalRed : Color.primary)
                .accessibilityLabel(value >= 0 ? Text("Profit \(value) credits per unit") : Text("Loss \(-value) credits per unit"))
        } else {
            Image(systemName: "minus").accessibilityLabel(Text("Not available"))  // A11Y-029: a dash glyph is too thin to measure
        }
    }
}

/// INT-029: the Market's intel is rebuilt when either key changes.
private struct IntelBuildKey: Equatable {
    var generation: Int
    var journal: Int
}

// MARK: - Jettison / Dump sheet (UI-SHELL-065)

private struct DisposalSheet: View {
    let disposal: CargoDisposal
    let finish: (Command?) -> Void
    @State private var quantity = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(disposal.kind == .jettison ? "Jettison \(Names.item(disposal.item))" : "Dump \(Names.item(disposal.item))")
                .scaledFont(.title3, weight: .bold)
            Stepper(value: $quantity, in: 1...max(1, disposal.maximum)) {
                Text("Quantity: \(quantity) of at most \(disposal.maximum)").monospacedDigit()
            }
            .accessibilityLabel(Text("Quantity"))
            .accessibilityValue(Text(verbatim: AccessibilityText.units(quantity)))
            .accessibilityIdentifier(AXID.Market.disposalQuantity)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { finish(nil) }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier(AXID.Market.disposalCancel)
                Button(disposal.kind == .jettison ? "Jettison" : "Dump") { finish(disposal.command(quantity: quantity)) }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier(AXID.Market.disposalConfirm)
            }
        }
        .padding(24)
        .frame(width: 360)
        .onAppear { quantity = max(1, disposal.maximum) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Market.disposalSheet)
    }
}

/// A11Y-014: the Market's "In Hold" and "Profitable at Target" rotors over the item cells.
private struct MarketRotorsModifier: ViewModifier {
    let rows: [MarketRowModel]
    let intel: MarketIntelModel?
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        let inHold = MarketRotors.inHold(rows)
        let profitable = MarketRotors.profitableAtTarget(rows) { item in intel?.row(item)?.targetQuote?.sell }
        content
            .accessibilityRotor(Text("In Hold")) {
                ForEach(inHold, id: \.self) { item in
                    AccessibilityRotorEntry(Text(Names.item(item)), id: item, in: namespace)
                }
            }
            .accessibilityRotor(Text("Profitable at Target")) {
                ForEach(profitable, id: \.self) { item in
                    AccessibilityRotorEntry(Text(Names.item(item)), id: item, in: namespace)
                }
            }
    }
}
