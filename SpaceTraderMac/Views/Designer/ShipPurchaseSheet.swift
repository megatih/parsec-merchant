// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// The purchase review sheet (UI-SHELL-071/072/075): the presentation of the `.buyShip` confirmation (ALR-137) for a
/// stock ship or a design, with the transfer checklist (ALR-146), lost items (ALR-141) and the final cost.
struct ShipPurchaseSheet: View {
    @Environment(GameSession.self) private var session
    let request: ShipPurchaseRequest
    @State private var declined: Set<TransferItem> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let state = session.state, let model = ShipPurchaseModel.make(request: request, state: state, declined: declined) {
                header(model)
                // UI-DS-023: a plain stack on the inset fill, not a system form.
                VStack(alignment: .leading, spacing: PMSpace.s) {
                    prices(model)
                    transfers(model)
                    consequences(model, state: state)
                    SwiftUI.Section {
                        LabeledContent("Final cost") { credits(model.finalCost).bold() }
                    }
                }
                .padding(PMSpace.m)
                .background(PMColor.panelInset, in: RoundedRectangle(cornerRadius: PMRadius.panel))
                .labeledContentStyle(ReadableLabeledContentStyle())  // A11Y-029: values at full contrast
                footer(model)
            } else {
                Text("This ship can't be built here.")
                footer(nil)
            }
        }
        .padding(PMSpace.xl)
        .frame(width: 520)
        .frame(minHeight: 420)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.ShipPurchase.sheet)
    }

    private func header(_ model: ShipPurchaseModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // D7: the ship being bought, drawn from the statistics of the offer.
            ShipPortrait(input: ArtAdapters.specInput(model.newSpec.type, spec: model.newSpec))
                .frame(maxWidth: .infinity)
                .frame(height: ShipPanelSize.purchaseHero)
            switch request {
            case let .ship(t):
                Text("Buy a \(String(localized: Names.ship(t)))?").pmFont(.title).accessibilityAddTraits(.isHeader)
            case let .design(d):
                Text("Build “\(d.name)”?").pmFont(.title).accessibilityAddTraits(.isHeader)
            }
            Text("\(String(localized: Names.size(model.newSpec.size))) · \(model.newSpec.cargoBays) bays · \(model.newSpec.hullStrength) hull")
                .foregroundStyle(PMColor.textSecondary)
        }
    }

    private func prices(_ model: ShipPurchaseModel) -> some View {
        SwiftUI.Section("Price") {
            LabeledContent("List price") { credits(model.listPrice) }
            if model.discount > 0 {
                LabeledContent("Trader discount") { credits(-model.discount) }
            }
            LabeledContent("Trade-in value") { credits(-model.tradeIn) }
                .help(Text("What your current ship, its equipment and its cargo are worth"))
            LabeledContent("Net price") { credits(model.netPrice) }
        }
    }

    @ViewBuilder private func transfers(_ model: ShipPurchaseModel) -> some View {
        if !model.transfers.isEmpty || !model.lost.isEmpty {
            SwiftUI.Section("Transfer to the new ship") {
                ForEach(model.transfers) { row in
                    Toggle(isOn: binding(for: row)) {
                        HStack {
                            Text(Names.transfer(row.item))
                            Spacer()
                            if row.affordable {
                                credits(row.price)
                            } else {
                                Text("Can't afford").foregroundStyle(PMColor.textSecondary)
                            }
                        }
                    }
                    .disabled(!row.affordable)
                    .help(row.affordable ? Text("Transfer for \(row.price.formatted()) cr.") : Text("Can't afford"))
                    .accessibilityIdentifier(AXID.ShipPurchase.transfer(row.item))
                }
                ForEach(model.lost, id: \.self) { item in
                    LabeledContent {
                        Text("No slot: lost").foregroundStyle(PMColor.caution)
                    } label: {
                        Text(Names.transfer(item))
                    }
                }
            }
        }
    }

    @ViewBuilder private func consequences(_ model: ShipPurchaseModel, state: GameState) -> some View {
        SwiftUI.Section("What changes") {
            if !model.crewWithoutSeat.isEmpty {
                let names = model.crewWithoutSeat.map { Names.crew($0, in: state) }.formatted(.list(type: .and))
                Text("No quarters for: \(names)").foregroundStyle(PMColor.caution)
            }
            if model.cargoUnits > 0 {
                Text("Your \(model.cargoUnits) units of cargo stay behind; their cost is part of the trade-in.")
            }
            switch model.insurance {
            case .notInsured: Text("You have no insurance.").foregroundStyle(PMColor.textSecondary)
            case .kept: Text("Your insurance stays active.")
            case .ends: Text("Without an escape pod your insurance ends and the no-claim discount is lost.").foregroundStyle(PMColor.caution)
            }
        }
    }

    private func footer(_ model: ShipPurchaseModel?) -> some View {
        HStack {
            if let blocker = model?.blocker {
                Text(ReasonText.text(for: blocker)).foregroundStyle(PMColor.caution)
            }
            Spacer()
            Button("Cancel", role: .cancel) { session.cancel() }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier(AXID.ShipPurchase.cancel)
            Button(buyTitle) {
                guard let model else { return }
                session.dismissPresentation()
                session.send(model.command, acknowledging: [.buyShip])
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(PMButtonStyle(kind: .primary))
            .disabled(model?.canBuy != true)
            .help(model?.blocker.map { Text(ReasonText.text(for: $0)) } ?? Text("Complete the purchase."))
            .accessibilityIdentifier(AXID.ShipPurchase.buy)
        }
    }

    private var buyTitle: LocalizedStringResource {
        if case .design = request { return "Build Ship" }
        return "Buy Ship"
    }

    /// Shows whether the item really moves (an unaffordable one shows unticked); toggling records the choice.
    private func binding(for row: TransferRow) -> Binding<Bool> {
        Binding {
            row.accepted
        } set: { on in
            if on { declined.remove(row.item) } else { declined.insert(row.item) }
        }
    }

    private func credits(_ n: Int) -> some View {
        Text("\(n.formatted()) cr.").fontWeight(.medium).monospacedDigit()
    }
}
