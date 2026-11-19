// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecArt
import ParsecEngine
import SwiftUI

/// Shipyard (⌘2, PRD §4.5): the ships for sale with a standing comparison against the current ship, the escape pod,
/// and the Designer where a yard is present.
struct ShipyardPage: View {
    @Environment(GameSession.self) private var session
    @Environment(\.pmScale) private var scale
    @State private var showDesigner = false
    /// UI-PG-002: the selected ship, kept for the session.
    @SceneStorage("shipyard.selected") private var selectedRaw = ""

    var body: some View {
        GamePage(section: .shipyard) {
            // UI-SHELL-069: the Designer tab exists only where a yard is present.
            if let state = session.state, ShipyardModel.make(state: state).designerAvailable {
                PMSegmented(options: [(false, "Ships", AXID.Shipyard.ships), (true, "Designer", AXID.Shipyard.designer)], selection: $showDesigner,
                            identifier: "shipyard.tabs")
            }
        } content: {
            if let state = session.state {
                let model = ShipyardModel.make(state: state)
                if showDesigner, model.designerAvailable, let yard = model.yard {
                    DesignerView(yard: yard).id(yard)
                } else {
                    ships(model, state: state)
                }
            }
        }
    }

    private func selected(_ model: ShipyardModel) -> ShipCardModel? {
        model.cards.first { "\($0.type)" == selectedRaw && !$0.isYours } ?? model.cards.first { !$0.isYours }
    }

    // MARK: Ships

    private func ships(_ model: ShipyardModel, state: GameState) -> some View {
        let current = model.cards.first(where: \.isYours)
        let choice = selected(model)
        return VStack(alignment: .leading, spacing: PMSpace.s * scale) {
            HStack(alignment: .top, spacing: PMSpace.s * scale) {
                list(model, selected: choice, state: state).frame(width: 380 * scale)
                detail(choice, current: current, state: state)
            }
            services(model.escapePod)
        }
    }

    private func list(_ model: ShipyardModel, selected: ShipCardModel?, state: GameState) -> some View {
        PMPanel("Ships for Sale", identifier: "shipyard.list") {
            if !model.hasShipsForSale {
                PMEmptyState(symbol: "airplane", message: "No ships for sale here.", identifier: "shipyard.none")
            }
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(model.cards.filter { !$0.isYours }) { card in
                        ShipRow(card: card, selected: card.type == selected?.type, state: state) {
                            selectedRaw = "\(card.type)"
                        } onBuy: {
                            session.present(.sheet(.shipPurchase(.ship(card.type))))
                        }
                    }
                }
            }
        }
    }

    private func detail(_ card: ShipCardModel?, current: ShipCardModel?, state: GameState) -> some View {
        PMPanel(card.map { Names.ship($0.type) } ?? "Your Ship", identifier: "shipyard.detail") {
            if let shown = card ?? current {
                ShipPortrait(input: ArtAdapters.specInput(shown.type, spec: shown.spec, liverySeed: ArtAdapters.playerLiverySeed(state)))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 120 * scale, maxHeight: .infinity)
                if let current { comparison(current: current, selected: card) }
                if let card {
                    price(card)
                    if let blocker = card.blocker { PMNote(text: ReasonText.text(for: blocker)) }
                    PMButton(title: "Buy Ship…", kind: .primary, fillsWidth: true, help: "Review the purchase: trade-in, transfers and what is lost",
                             identifier: AXID.Shipyard.buy(card.type)) {
                        session.present(.sheet(.shipPurchase(.ship(card.type))))
                    }
                }
            }
        }
    }

    /// "Current ship | Selected", one line per statistic, with ▲/▼ for the difference (UI-PG-010: always shown).
    private func comparison(current: ShipCardModel, selected: ShipCardModel?) -> some View {
        Grid(alignment: .leading, horizontalSpacing: PMSpace.l * scale, verticalSpacing: PMSpace.xs * scale) {
            GridRow {
                Text(verbatim: "")
                Text("Current: \(String(localized: Names.ship(current.type)))")
                if let selected { Text("Selected: \(String(localized: Names.ship(selected.type)))") }
            }
            .pmFont(.caption)
            .foregroundStyle(PMColor.textSecondary)
            ForEach(ShipStatField.allCases, id: \.self) { field in
                GridRow {
                    Text(field.title).pmFont(.body).foregroundStyle(PMColor.textSecondary)
                    Text(verbatim: field.value(current.spec).formatted()).pmFont(.value).foregroundStyle(PMColor.textPrimary)
                    if let selected {
                        let delta = field.value(selected.spec) - field.value(current.spec)
                        HStack(spacing: PMSpace.s * scale) {
                            Text(verbatim: field.value(selected.spec).formatted()).pmFont(.value).foregroundStyle(PMColor.textPrimary)
                            Text(verbatim: ShipCompare.deltaText(delta)).pmFont(.caption)
                                .foregroundStyle(delta > 0 ? PMColor.profit : (delta < 0 ? PMColor.loss : PMColor.textSecondary))
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Shipyard.compare)
    }

    @ViewBuilder
    private func price(_ card: ShipCardModel) -> some View {
        switch card.price {
        case let .pay(n)?: PMInfoRow("Price after trade-in", credits: n)
        case let .receive(n)?: PMInfoRow(label: "Price after trade-in") { Text("You get \(n.formatted()) cr.") }
        case nil: EmptyView()
        }
    }

    // MARK: Services (UI-SHELL-073)

    private func services(_ strip: EscapePodStrip) -> some View {
        PMPanel("Services", identifier: "shipyard.services") {
            HStack(spacing: PMSpace.m * scale) {
                if strip.installed {
                    Label("Escape pod installed", systemImage: "lifepreserver").pmFont(.body).foregroundStyle(PMColor.textPrimary)
                } else {
                    PMButton(title: "Buy Escape Pod \(EscapePodStrip.price.formatted()) cr.", help: "Ejects you safely when your ship is destroyed",
                             disabledReason: strip.canBuy ? nil : (strip.blocker ?? .notAllowedInPhase).reason,
                             identifier: AXID.Shipyard.escapePodBuy) {
                        session.send(.buyEscapePod)
                    }
                    .fixedSize()
                    if let blocker = strip.blocker { PMNote(text: ReasonText.text(for: blocker), tone: .neutral) }
                }
                Spacer(minLength: 0)
                Text(strip.insured ? "Insured" : "Not insured").pmFont(.body).foregroundStyle(PMColor.textSecondary)
                PMButton(title: "Insurance in Bank…", systemImage: "arrow.right", kind: .quiet, help: "Open the Bank page",
                         identifier: AXID.Shipyard.insuranceBank) {
                    session.selectedSection = .bank
                }
                .fixedSize()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// One ship for sale: a small portrait in the player's livery, the name, the price after trade-in and the blocker.
private struct ShipRow: View {
    let card: ShipCardModel
    let selected: Bool
    let state: GameState
    let onSelect: () -> Void
    let onBuy: () -> Void
    @Environment(\.pmScale) private var scale

    var body: some View {
        PMRow(selected: selected, identifier: AXID.Shipyard.ship(card.type)) {
            HStack(spacing: PMSpace.s * scale) {
                ShipPortrait(input: ArtAdapters.specInput(card.type, spec: card.spec, liverySeed: ArtAdapters.playerLiverySeed(state)))
                    .frame(width: 84 * scale, height: 48 * scale)
                VStack(alignment: .leading, spacing: 0) {
                    Text(Names.ship(card.type)).pmFont(.body).foregroundStyle(PMColor.textPrimary)
                    if let blocker = card.blocker {
                        Text(ReasonText.text(for: blocker)).pmFont(.caption).foregroundStyle(PMColor.caution)
                    } else {
                        Text(Names.size(card.spec.size)).pmFont(.caption).foregroundStyle(PMColor.textSecondary)
                    }
                }
                Spacer(minLength: PMSpace.xs * scale)
                price.pmFont(.value).foregroundStyle(PMColor.textPrimary).fixedSize()
            }
            .padding(.vertical, PMSpace.xs * scale)
            .padding(.trailing, PMSpace.s * scale)
        }
        .hoverHighlight(cornerRadius: 0)  // UI-PTR-003
        // UI-PG-010: one click selects; double-click is only an accelerator for Buy Ship….
        .onTapGesture(perform: onSelect)
        .simultaneousGesture(TapGesture(count: 2).onEnded { onBuy() })
        .contextMenu {
            // UI-PTR-005: the row's visible action.
            Button("Buy Ship…", action: onBuy)
        }
        .modifier(RowAccessibilityModifier(row: ShipCardAccessibility.make(card)) { _ in onBuy() })  // A11Y-007
    }

    @ViewBuilder private var price: some View {
        switch card.price {
        case let .pay(n)?: Text("\(n.formatted()) cr.")
        case let .receive(n)?: Text("You get \(n.formatted()) cr.")
        case nil: EmptyView()
        }
    }
}
