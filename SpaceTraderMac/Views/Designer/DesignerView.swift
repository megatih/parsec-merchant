// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecArt
import ParsecEngine
import ParsecPersistence
import SwiftUI

/// The custom ship Designer (UI-SHELL-074…076): allocation on the left, preview and costs on the right.
struct DesignerView: View {
    @Environment(GameSession.self) private var session
    let yard: ShipyardID
    @State private var draft: DesignerDraft?
    @State private var saved: [ShipDesign] = []
    @State private var saveMessage: LocalizedStringResource?

    private var store: DesignTemplateStore { DesignTemplateStore(root: session.slotStore.root) }

    var body: some View {
        Group {
            if let state = session.state, let draft {
                let quote = state.designQuote(draft.design)
                HStack(alignment: .top, spacing: 16) {
                    allocation(draft, quote: quote, state: state)
                        .frame(minWidth: 340, maxWidth: 420)
                    summary(draft, quote: quote)
                }
                .padding()
            } else {
                ProgressView()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.ShipDesigner.root)
        .task(id: yard) { load() }
    }

    private func load() {
        saved = store.load()
        guard let state = session.state else { return }
        let current = DesignTemplates.list(state: state, yard: yard, saved: []).first?.design
            ?? Designer.minimumDesign(size: Designer.sizes(for: yard).first ?? .small, yard: yard)
        let ship = state.commander.ship.type
        draft = DesignerDraft(yard: yard, design: current, silhouette: ship)
    }

    // MARK: Left: allocation

    private func allocation(_ draft: DesignerDraft, quote: DesignQuote?, state: GameState) -> some View {
        Form {
            SwiftUI.Section {
                templatePicker(state: state)
                TextField("Ship name", text: binding(\.name))
                    .accessibilityIdentifier(AXID.ShipDesigner.name)
                Picker("Size", selection: binding(\.size)) {
                    ForEach(draft.sizes, id: \.self) { s in
                        Text("\(String(localized: Names.size(s))) (\(DesignerTables.maxUnits[s.rawValue]) units)").tag(s)
                    }
                }
                .accessibilityIdentifier(AXID.ShipDesigner.size)
                Picker("Silhouette", selection: binding(\.silhouette)) {
                    ForEach(ShipType.buyable, id: \.self) { Text(Names.ship($0)).tag($0) }
                }
                .accessibilityIdentifier(AXID.ShipDesigner.silhouette)
            }
            SwiftUI.Section("Allocation") {
                ForEach(DesignerField.allCases, id: \.self) { f in stepper(f, draft: draft) }
            }
            SwiftUI.Section {
                if let quote { unitsBar(quote) }
            }
        }
        .formStyle(.grouped)
    }

    private func templatePicker(state: GameState) -> some View {
        Menu("Templates") {
            ForEach(DesignTemplates.list(state: state, yard: yard, saved: saved)) { t in
                Button { self.draft?.apply(t.design) } label: { Text(templateTitle(t)) }
            }
        }
        .accessibilityIdentifier(AXID.ShipDesigner.template)
    }

    private func templateTitle(_ t: DesignTemplate) -> String {
        switch t.kind {
        case .currentShip: String(localized: "Current ship")
        case let .minimum(s): String(localized: "\(String(localized: Names.size(s))) (minimum)")
        case let .stock(type): String(localized: "\(String(localized: Names.ship(type))) (default)")
        case let .saved(name): name
        }
    }

    private func stepper(_ f: DesignerField, draft: DesignerDraft) -> some View {
        LabeledContent {
            HStack(spacing: 6) {
                Button { self.draft?.decrement(f) } label: { Image(systemName: "minus") }
                    .disabled(!draft.canDecrement(f))
                    .accessibilityLabel(Text("Decrease \(String(localized: f.title))"))
                    .accessibilityIdentifier(AXID.ShipDesigner.decrement(f))
                Text(verbatim: draft.value(f).formatted())
                    .monospacedDigit()
                    .frame(minWidth: 44)
                    .accessibilityIdentifier(AXID.ShipDesigner.value(f))
                Button { self.draft?.increment(f) } label: { Image(systemName: "plus") }
                    .disabled(!draft.canIncrement(f))
                    .accessibilityLabel(Text("Increase \(String(localized: f.title))"))
                    .accessibilityIdentifier(AXID.ShipDesigner.increment(f))
            }
        } label: {
            Text(f.title)
        }
    }

    private func unitsBar(_ quote: DesignQuote) -> some View {
        let level = UnitsLevel(percent: quote.percentOfMax)
        let tint: Color = switch level {
        case .normal: .accentColor
        case .caution: .yellow
        case .warning: .orange
        case .over: .red
        }
        return VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: Double(min(quote.percentOfMax, 100)), total: 100)
                .tint(tint)
            Text("Units used: \(quote.unitsUsed) of \(quote.maxUnits) (\(quote.percentOfMax)%)")
                .monospacedDigit()
                .foregroundStyle(level == .over ? .red : .primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AXID.ShipDesigner.units)
    }

    // MARK: Right: preview, costs, actions

    private func summary(_ draft: DesignerDraft, quote: DesignQuote?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack {
                ShipPortrait(input: ShipArtInput(kind: .custom, sizeClass: draft.size.rawValue,
                                                 custom: ArtAdapters.customParams(design: draft.design, base: draft.silhouette)))
                    .frame(width: 220, height: 120)
                Text(Names.ship(draft.silhouette)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 160)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
            if let quote {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    costRow("Base price", quote.adjustedPrice)
                    costRow("Design fee", quote.adjustedFee)
                    costRow("Crowding penalty", quote.adjustedPenalty)
                    costRow("Trade-in", -quote.tradeIn)
                    Divider().gridCellUnsizedAxes(.horizontal)
                    costRow("Total", quote.totalCost).bold()
                }
                if let blocker = quote.blocker {
                    Text(ReasonText.text(for: blocker)).foregroundStyle(.orange)
                }
                HStack {
                    Button("Save Template") { save(draft.design) }
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .help(Text("Save this design to your templates."))
                        .accessibilityIdentifier(AXID.ShipDesigner.saveTemplate)
                    Spacer()
                    Button("Construct…") { session.present(.sheet(.shipPurchase(.design(quote.design)))) }
                        .buttonStyle(.borderedProminent)
                        .disabled(!quote.canBuild)
                        .help(quote.blocker.map { Text(ReasonText.text(for: $0)) } ?? Text("Review and build this ship."))
                        .accessibilityIdentifier(AXID.ShipDesigner.construct)
                }
                if let saveMessage {
                    Text(saveMessage).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private func costRow(_ title: LocalizedStringResource, _ amount: Int) -> some View {
        GridRow {
            Text(title)
            Text("\(amount.formatted()) cr.")
                .monospacedDigit()
                .gridColumnAlignment(.trailing)
        }
    }

    private func save(_ design: ShipDesign) {
        do {
            try store.save(design)
            saved = store.load()
            saveMessage = "Template saved."
        } catch {
            saveMessage = "The template couldn't be saved."
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<DesignerDraft, T>) -> Binding<T> where T: Sendable {
        Binding {
            // The draft exists whenever the controls are shown.
            draft.map { $0[keyPath: keyPath] } ?? DesignerDraft(yard: yard, design: Designer.minimumDesign(size: .small, yard: yard))[keyPath: keyPath]
        } set: { newValue in
            draft?[keyPath: keyPath] = newValue
        }
    }
}
