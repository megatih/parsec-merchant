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
        // UI-KEYS-018: the window's Esc router clears the comparison (level 8).
        .escapeHandler(.clearCompare, active: selection.isComparing) { selection.clear() }
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
                        .scaledFont(.headline)
                        .foregroundStyle(.readableSecondary)
                }
                if selection.isComparing {
                    ShipCompareView(rows: ShipCompare.rows(model, selection: selection),
                                    specs: Dictionary(model.cards.map { ($0.type, $0.spec) }, uniquingKeysWith: { a, _ in a })) { selection.clear() }
                }
                AccessibleLazyVGrid(label: "Ships", columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                    ForEach(model.cards) { card in
                        ShipCardView(card: card, selected: selection.contains(card.type), onBuy: {
                            session.present(.sheet(.shipPurchase(.ship(card.type))))
                        }, onCompare: { selection.click(card.type, command: true) }, onTap: {
                            selection.click(card.type, command: NSEvent.modifierFlags.contains(.command))
                        })
                    }
                }
                if !model.cards.isEmpty {
                    Text("Use Compare on two or more ships to see them side by side. Double-click a ship to review its purchase.")
                        .scaledFont(.footnote)
                        .foregroundStyle(.readableSecondary)
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
    var onCompare: () -> Void = {}
    /// Click selects, ⌘-click adds to the comparison (applied inside, so the card stays one labelled element).
    var onTap: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // D7: a full-width portrait banner.
            ShipPortrait(input: ArtAdapters.specInput(card.type, spec: card.spec))
                .frame(maxWidth: .infinity)
                .frame(height: ShipPanelSize.cardBanner)
            HStack {
                VStack(alignment: .leading) {
                    Text(Names.ship(card.type)).scaledFont(.headline)
                    Text(Names.size(card.spec.size)).scaledFont(.callout).foregroundStyle(.readableSecondary)
                }
                Spacer()
                if card.isYours {
                    Text("Yours")
                        .scaledFont(.caption, weight: .bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.2), in: Capsule())
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
                ForEach(ShipStatField.allCases, id: \.self) { f in
                    GridRow {
                        Text(f.title).foregroundStyle(.readableSecondary)
                        Text(verbatim: f.value(card.spec).formatted()).fontWeight(.medium).monospacedDigit()  // A11Y-029
                    }
                }
            }
            .scaledFont(.callout)
            price
            if let blocker = card.blocker {
                Text(ReasonText.text(for: blocker))
                    .scaledFont(.footnote)
                    .foregroundStyle(.signalOrange)
            }
            HStack {
                if card.canOpenPurchase {
                    Button(action: onBuy) { Text("Buy…").pointerTarget() }
                        .help(card.blocker.map { Text(ReasonText.text(for: $0)) } ?? Text("Review the purchase."))
                        .accessibilityIdentifier(AXID.Shipyard.buy(card.type))
                }
                Spacer(minLength: 0)
                // UI-PTR-009: comparing needs no modifier key.
                Toggle(isOn: Binding(get: { selected }, set: { _ in onCompare() })) {
                    Text("Compare").pointerTarget()
                }
                .toggleStyle(.button)
                .help(Text(selected ? "Remove this ship from the comparison." : "Add this ship to the comparison."))
                .accessibilityIdentifier(AXID.Shipyard.compareToggle(card.type))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2)
        }
        .hoverHighlight(cornerRadius: 10)  // UI-PTR-003
        .contentShape(Rectangle())
        // UI-PTR-006: double-click opens the purchase review; a click selects.
        .onTapGesture(count: 2) { if card.canOpenPurchase { onBuy() } }
        .onTapGesture(perform: onTap)
        .contextMenu {
            // UI-PTR-005: the card's visible actions.
            if card.canOpenPurchase {
                Button("Buy…", action: onBuy)
            }
            Button(selected ? "Remove from Compare" : "Compare", action: onCompare)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .modifier(RowAccessibilityModifier(row: ShipCardAccessibility.make(card)) { kind in
            kind == .buy ? onBuy() : onCompare()
        })  // A11Y-007
        .accessibilityIdentifier(AXID.Shipyard.ship(card.type))
    }

    @ViewBuilder private var price: some View {
        switch card.price {
        case let .pay(n)?:
            Text("\(n.formatted()) cr.").scaledFont(.headline).monospacedDigit()
        case let .receive(n)?:
            Text("You get \(n.formatted()) cr.").scaledFont(.headline).monospacedDigit()
        case nil:
            Text("Your current ship").foregroundStyle(.readableSecondary)
        }
    }
}

/// The side-by-side compare table (UI-SHELL-070).
private struct ShipCompareView: View {
    let rows: [ShipCompareRow]
    /// The compared types' specs, for the header portraits.
    var specs: [ShipType: ShipSpec] = [:]
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Compare").scaledFont(.headline)
                Spacer()
                Button("Clear Selection", action: onClear)
                    .help(Text("Esc clears the selection."))
                    .accessibilityIdentifier(AXID.Shipyard.compareClear)
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Text(verbatim: "")
                    Text("Yours").bold()
                    ForEach(rows.first?.cells ?? [], id: \.type) { cell in
                        VStack(alignment: .leading, spacing: 2) {
                            if let spec = specs[cell.type] {
                                ShipPortrait(input: ArtAdapters.specInput(cell.type, spec: spec))
                                    .frame(width: ShipPanelSize.compare.width, height: ShipPanelSize.compare.height)
                            }
                            Text(Names.ship(cell.type)).bold()
                        }
                    }
                }
                ForEach(rows) { row in
                    GridRow {
                        Text(row.field.title).foregroundStyle(.readableSecondary)
                        Text(verbatim: row.current.formatted()).fontWeight(.medium).monospacedDigit()
                        ForEach(row.cells, id: \.type) { cell in
                            HStack(spacing: 4) {
                                Text(verbatim: cell.value.formatted()).fontWeight(.medium).monospacedDigit()
                                Text(verbatim: ShipCompare.deltaText(cell.delta))
                                    .scaledFont(.caption)
                                    .foregroundStyle(cell.delta > 0 ? .signalGreen : (cell.delta < 0 ? .signalRed : .secondary))
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
        // A11Y-026: the strip wraps at large Text Sizes, so the button keeps its whole title.
        WrappingHStack(spacing: 16, lineSpacing: 8, leading: true) {
            if strip.installed {
                Label("Escape pod installed", systemImage: "lifepreserver")
            } else {
                Button("Buy Escape Pod (\(EscapePodStrip.price.formatted()) cr.)") { session.send(.buyEscapePod) }
                    .disabled(!strip.canBuy)
                    .help(strip.blocker.map { Text(ReasonText.text(for: $0)) } ?? Text("Ejects you safely when your ship is destroyed."))
                    .accessibilityIdentifier(AXID.Shipyard.escapePodBuy)
                if let blocker = strip.blocker {
                    Text(ReasonText.text(for: blocker)).scaledFont(.footnote).foregroundStyle(.readableSecondary)
                }
            }
            Rectangle().fill(.separator).frame(width: 1, height: 20).accessibilityHidden(true)
            Text(strip.insured ? "Insured" : "Not insured")
                .foregroundStyle(.readableSecondary)
            Button("Insurance in Bank…") { session.selectedSection = .bank }
                .buttonStyle(.link)
                .accessibilityIdentifier(AXID.Shipyard.insuranceBank)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}
