// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// Market (⌘2, UI-SHELL §8): one merged trade table (buy and sell), the item filter and the footer.
struct MarketSectionView: View {
    @Environment(GameSession.self) private var session
    @State private var filter = ""
    @State private var quantities: [TradeItemType: String] = [:]
    @State private var disposal: CargoDisposal?
    @FocusState private var focusedField: Field?

    enum Field: Hashable {
        case filter
        case quantity(TradeItemType)
    }

    var body: some View {
        @Bindable var session = session
        if let state = session.state {
            let rows = MarketFilter.filtered(MarketRowModel.rows(state: state), filter: filter)
            VStack(spacing: 0) {
                filterBar
                Table(rows, selection: $session.marketSelection) {
                    TableColumn("Item") { (r: MarketRowModel) in ItemCell(row: r) }
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
                    TableColumn("Target") { (r: MarketRowModel) in TargetCell(quote: r.target) }
                        .width(min: 110, ideal: 140)
                    TableColumn("Actions") { (r: MarketRowModel) in actionsCell(r) }
                        .width(min: 280, ideal: 300)
                }
                .onKeyPress(phases: .down) { press in handleKey(press, rows: rows) }
                .accessibilityIdentifier(AXID.Market.table)
                Divider()
                footer(MarketFooterModel.make(state: state))
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
            Image(systemName: "line.3.horizontal.decrease.circle").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField(text: $filter) { Text("Filter items") }
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
                .focused($focusedField, equals: .filter)
                .onExitCommand { filter = "" }
                .help(Text("Show only items whose name contains this text. Esc clears it."))
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
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: r.row.held.formatted()).monospacedDigit()
                .accessibilityIdentifier(AXID.Market.held(r.item))
            if r.row.held > 0 {
                Text("avg \(r.row.costBasisPerUnit.formatted()) cr.").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
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
                if let c = r.sellCommand(modifiers: TradeQuantity.current) { session.send(c) }
            } label: {
                if r.isDumpMode { Text("Dump") } else { Image(systemName: "minus") }
            }
            .disabled(r.sellBlocker != nil)
            .help(sellReason ?? String(localized: r.isDumpMode
                ? "Dump 1 (⇧ 5, ⌘ 20, ⇧⌘ 100, ⌥ all)" : "Sell 1 (⇧ 5, ⌘ 20, ⇧⌘ 100, ⌥ all)"))
            .accessibilityLabel(Text(r.isDumpMode ? "Dump" : "Sell"))
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
                .accessibilityIdentifier(AXID.Market.quantity(r.item))
            Button {
                if let c = r.buyCommand(modifiers: TradeQuantity.current) { session.send(c) }
            } label: {
                Image(systemName: "plus")
            }
            .disabled(r.buyBlocker != nil)
            .help(buyReason ?? String(localized: "Buy 1 (⇧ 5, ⌘ 20, ⇧⌘ 100, ⌥ max)"))
            .accessibilityLabel(Text("Buy"))
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

    private func quantityBinding(_ item: TradeItemType) -> Binding<String> {
        Binding { quantities[item] ?? "" } set: { quantities[item] = $0 }
    }

    private func submitField(_ r: MarketRowModel, sell: Bool) {
        guard let c = r.fieldCommand(text: quantities[r.item] ?? "", sell: sell) else { return }
        session.send(c)
        quantities[r.item] = ""
    }

    // MARK: Footer (UI-SHELL-066)

    private func footer(_ f: MarketFooterModel) -> some View {
        HStack(spacing: 24) {
            Text("Bays: \(f.usedBays)/\(f.totalBays), \(f.freeForBuying) free for buying").monospacedDigit()
            Text("Cash available: \(f.cashAvailable.formatted()) cr.").monospacedDigit()
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AXID.Market.footer)
    }
}

// MARK: - Cells

private struct ItemCell: View {
    let row: MarketRowModel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "shippingbox").foregroundStyle(.secondary).accessibilityHidden(true)
            Text(Names.item(row.item))
            if row.isIllegal {
                Text("Illegal")
                    .font(.caption2.bold())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.red.opacity(0.2)))
                    .help(Text("Trading this is illegal; police may confiscate it."))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AXID.Market.row(row.item))
    }
}

private struct PriceCell: View {
    let price: Int?

    var body: some View {
        if let price {
            Text(verbatim: price.formatted()).monospacedDigit()
        } else {
            Text(verbatim: "—").foregroundStyle(.secondary).accessibilityLabel(Text("Not available"))
        }
    }
}

private struct SellCell: View {
    let row: MarketRowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PriceCell(price: row.sellPrice)
            if let dump = row.dumpCostShown {
                Text("Dump \(dump.formatted()) cr.").font(.caption).foregroundStyle(.secondary).monospacedDigit()
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
                .foregroundStyle(value > 0 ? Color.green : value < 0 ? Color.red : Color.primary)
                .accessibilityLabel(value >= 0 ? Text("Profit \(value) credits per unit") : Text("Loss \(-value) credits per unit"))
        } else {
            Text(verbatim: "—").foregroundStyle(.secondary).accessibilityLabel(Text("Not available"))
        }
    }
}

/// The target's price and the difference per bay (C# target columns).
private struct TargetCell: View {
    let quote: TargetQuote?

    var body: some View {
        if let quote {
            HStack(spacing: 6) {
                Text(verbatim: quote.price.formatted()).monospacedDigit()
                if let diff = quote.difference, let pct = quote.percent {
                    let sign = diff > 0 ? "+" : ""
                    Text(verbatim: "\(diff > 0 ? "▲" : diff < 0 ? "▼" : "") \(sign)\(diff.formatted()) (\(sign)\(pct)%)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(diff > 0 ? Color.green : diff < 0 ? Color.red : Color.secondary)
                        .help(Text("Profit per bay if bought here and sold at the target."))
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            Text(verbatim: "—").foregroundStyle(.secondary).accessibilityLabel(Text("No target price"))
        }
    }
}

// MARK: - Jettison / Dump sheet (UI-SHELL-065)

private struct DisposalSheet: View {
    let disposal: CargoDisposal
    let finish: (Command?) -> Void
    @State private var quantity = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(disposal.kind == .jettison ? "Jettison \(Names.item(disposal.item))" : "Dump \(Names.item(disposal.item))")
                .font(.title3.bold())
            Stepper(value: $quantity, in: 1...max(1, disposal.maximum)) {
                Text("Quantity: \(quantity) of at most \(disposal.maximum)").monospacedDigit()
            }
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
