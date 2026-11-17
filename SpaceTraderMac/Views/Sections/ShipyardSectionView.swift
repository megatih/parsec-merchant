// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import ParsecArt
import ParsecEngine
import SwiftUI

/// Shipyard section (⌘3): ship grid, compare, escape pod and insurance strip, and the Designer tab (UI-SHELL-068…076).
struct ShipyardSectionView: View {
    @Environment(GameSession.self) private var session
    @State private var showDesigner = false
    @State private var selection = ShipSelection()

    var body: some View {
        Group {
            if let state = session.state {
                let model = ShipyardModel.make(state: state)
                VStack(spacing: 0) {
                    if model.designerAvailable { tabs }
                    if showDesigner, model.designerAvailable, let yard = model.yard {
                        DesignerView(yard: yard)
                            .id(yard)
                    } else {
                        shipList(model)
                    }
                }
                .onChange(of: model.cards.map(\.type)) { _, types in selection.prune(to: types) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.SectionRoot.root(.shipyard))
    }

    // MARK: Tabs (UI-SHELL-069)

    private var tabs: some View {
        HStack(spacing: 8) {
            tabButton("Ships", selected: !showDesigner, id: AXID.Shipyard.ships) { showDesigner = false }
            tabButton("Designer", selected: showDesigner, id: AXID.Shipyard.designer) { showDesigner = true }
            Spacer()
        }
        .padding([.horizontal, .top])
    }

    private func tabButton(_ title: LocalizedStringResource, selected: Bool, id: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).frame(minWidth: 80) }
            .buttonStyle(.bordered)
            .tint(selected ? .accentColor : .secondary)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier(id)
    }

    // MARK: Ship list (UI-SHELL-068/070/073)

    private func shipList(_ model: ShipyardModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                EscapePodStripView(strip: model.escapePod)
                if !model.hasShipsForSale {
                    Text("No ships for sale here.")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                if selection.isComparing {
                    ShipCompareView(rows: ShipCompare.rows(model, selection: selection)) { selection.clear() }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                    ForEach(model.cards) { card in
                        ShipCardView(card: card, selected: selection.contains(card.type)) {
                            session.present(.sheet(.shipPurchase(.ship(card.type))))
                        }
                        .onTapGesture {
                            selection.click(card.type, command: NSEvent.modifierFlags.contains(.command))
                        }
                    }
                }
                if !model.cards.isEmpty {
                    Text("Click a ship to select it; ⌘-click two or more to compare them.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }
}

/// One ship card (UI-SHELL-068).
private struct ShipCardView: View {
    let card: ShipCardModel
    let selected: Bool
    let onBuy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ShipPortrait(input: ArtAdapters.specInput(card.type, spec: card.spec))
                    .frame(width: 66, height: 44)
                VStack(alignment: .leading) {
                    Text(Names.ship(card.type)).font(.headline)
                    Text(Names.size(card.spec.size)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if card.isYours {
                    Text("Yours")
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.2), in: Capsule())
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
                ForEach(ShipStatField.allCases, id: \.self) { f in
                    GridRow {
                        Text(f.title).foregroundStyle(.secondary)
                        Text(verbatim: f.value(card.spec).formatted()).monospacedDigit()
                    }
                }
            }
            .font(.callout)
            price
            if let blocker = card.blocker {
                Text(ReasonText.text(for: blocker))
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if card.canOpenPurchase {
                Button("Buy…", action: onBuy)
                    .help(card.blocker.map { Text(ReasonText.text(for: $0)) } ?? Text("Review the purchase."))
                    .accessibilityIdentifier(AXID.Shipyard.buy(card.type))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(AXID.Shipyard.ship(card.type))
    }

    @ViewBuilder private var price: some View {
        switch card.price {
        case let .pay(n)?:
            Text("\(n.formatted()) cr.").font(.headline).monospacedDigit()
        case let .receive(n)?:
            Text("You get \(n.formatted()) cr.").font(.headline).monospacedDigit()
        case nil:
            Text("Your current ship").foregroundStyle(.secondary)
        }
    }
}

/// The side-by-side compare table (UI-SHELL-070).
private struct ShipCompareView: View {
    let rows: [ShipCompareRow]
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Compare").font(.headline)
                Spacer()
                Button("Clear Selection", action: onClear)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier(AXID.Shipyard.compareClear)
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Text(verbatim: "")
                    Text("Yours").bold()
                    ForEach(rows.first?.cells ?? [], id: \.type) { Text(Names.ship($0.type)).bold() }
                }
                ForEach(rows) { row in
                    GridRow {
                        Text(row.field.title).foregroundStyle(.secondary)
                        Text(verbatim: row.current.formatted()).monospacedDigit()
                        ForEach(row.cells, id: \.type) { cell in
                            HStack(spacing: 4) {
                                Text(verbatim: cell.value.formatted()).monospacedDigit()
                                Text(verbatim: ShipCompare.deltaText(cell.delta))
                                    .font(.caption)
                                    .foregroundStyle(cell.delta > 0 ? .green : (cell.delta < 0 ? .red : .secondary))
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Shipyard.compare)
    }
}

/// Escape pod and insurance strip (UI-SHELL-073).
private struct EscapePodStripView: View {
    @Environment(GameSession.self) private var session
    let strip: EscapePodStrip

    var body: some View {
        HStack(spacing: 16) {
            if strip.installed {
                Label("Escape pod installed", systemImage: "lifepreserver")
            } else {
                Button("Buy Escape Pod (\(EscapePodStrip.price.formatted()) cr.)") { session.send(.buyEscapePod) }
                    .disabled(!strip.canBuy)
                    .help(strip.blocker.map { Text(ReasonText.text(for: $0)) } ?? Text("Ejects you safely when your ship is destroyed."))
                    .accessibilityIdentifier(AXID.Shipyard.escapePodBuy)
                if let blocker = strip.blocker {
                    Text(ReasonText.text(for: blocker)).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Divider().frame(height: 20)
            Text(strip.insured ? "Insured" : "Not insured")
                .foregroundStyle(.secondary)
            Button("Insurance in Bank…") { session.selectedSection = .bank }
                .buttonStyle(.link)
                .accessibilityIdentifier(AXID.Shipyard.insuranceBank)
            Spacer()
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}
