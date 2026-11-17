// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// Interim decision sheets (UI-SHELL-011; replaced by UI-ENC in M9). They can't be dismissed without an answer, so
/// the engine's pending decision is always resolved.
struct InterimDecisionSheet: View {
    @Environment(GameSession.self) private var session
    let decision: PendingDecision

    var body: some View {
        Group {
            switch decision {
            case let .tradeInOrbit(offer):
                TradeInOrbitSheet(offer: offer)
            case .plunder:
                PlunderSheet()
            case let .scoop(item):
                ScoopSheet(item: item)
            case let .newspaper(paper):
                NewspaperSheet(paper: paper)
            case .confirm:
                PlaceholderSheet(route: nil)
            }
        }
        .padding(24)
        .frame(minWidth: 420)
        .interactiveDismissDisabled()
    }
}

private struct TradeInOrbitSheet: View {
    @Environment(GameSession.self) private var session
    let offer: OrbitTradeOffer
    @State private var quantity = 0
    private var model: InterimDecisionModel.Trade { InterimDecisionModel.Trade(offer: offer) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(offer.direction == .traderSells ? "The trader offers to sell" : "The trader offers to buy")
                .font(.title3.bold())
            LabeledContent("Item") { Text(Names.item(offer.item)) }
            LabeledContent("Price per unit") { Text(verbatim: "\(offer.unitPrice.formatted()) cr.").monospacedDigit() }
            LabeledContent("Available") { Text(verbatim: offer.unitsAvailable.formatted()).monospacedDigit() }
            Stepper(value: $quantity, in: model.range) {
                Text("Quantity: \(quantity) of at most \(offer.maxQuantity)")
            }
            .accessibilityIdentifier(AXID.Decision.tradeQuantity)
            HStack {
                Spacer()
                Button("Decline") { answer(model.declineCommand) }
                    .accessibilityIdentifier(AXID.Decision.tradeDecline)
                Button("Trade") { answer(model.acceptCommand(quantity)) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canAccept(quantity))
                    .accessibilityIdentifier(AXID.Decision.tradeAccept)
            }
        }
        .onAppear { quantity = model.initialQuantity }
    }

    private func answer(_ command: Command) {
        session.dismissPresentation()
        session.send(command)
    }
}

private struct PlunderSheet: View {
    @Environment(GameSession.self) private var session
    @State private var amounts: [TradeItemType: Int] = [:]

    var body: some View {
        let cargo = session.state?.pendingPlunder?.victimCargo ?? []
        VStack(alignment: .leading, spacing: 12) {
            Text("Plunder")
                .font(.title3.bold())
            ForEach(InterimDecisionModel.Plunder.rows(cargo: cargo), id: \.item) { row in
                let item = row.item
                let available = row.available
                HStack {
                    Text(Names.item(item))
                    Spacer()
                    Stepper(value: binding(item, max: available), in: 1...available) {
                        Text(verbatim: "\(min(amounts[item] ?? available, available)) / \(available)").monospacedDigit()
                    }
                    Button("Take") {
                        session.send(InterimDecisionModel.Plunder.takeCommand(item, amount: amounts[item], available: available))
                    }
                        .accessibilityIdentifier(AXID.Decision.plunderTake(item))
                }
            }
            if session.lastRejection != nil, let reason = session.lastRejection {
                Text(ReasonText.text(for: reason)).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Done") {
                    session.dismissPresentation()
                    session.send(InterimDecisionModel.Plunder.doneCommand)
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier(AXID.Decision.plunderDone)
            }
        }
    }

    private func binding(_ item: TradeItemType, max available: Int) -> Binding<Int> {
        Binding { min(amounts[item] ?? available, available) } set: { amounts[item] = $0 }
    }
}

private struct ScoopSheet: View {
    @Environment(GameSession.self) private var session
    let item: TradeItemType

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("A canister of \(String(localized: Names.item(item))) floats by.")
                .font(.title3.bold())
            HStack {
                Spacer()
                Button("Leave It") { answer(false) }
                    .accessibilityIdentifier(AXID.Decision.scoopDecline)
                Button("Pick It Up") { answer(true) }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier(AXID.Decision.scoopAccept)
            }
        }
    }

    private func answer(_ accept: Bool) {
        session.dismissPresentation()
        session.send(InterimDecisionModel.scoopCommand(accept: accept))
    }
}

private struct NewspaperSheet: View {
    @Environment(GameSession.self) private var session
    let paper: Newspaper

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let state = session.state {
                Text("The \(Names.system(paper.system, in: state)) News")
                    .font(.title3.bold())
                ForEach(Array(InterimDecisionModel.newspaperLines(paper, state: state).enumerated()), id: \.offset) { _, line in
                    Text(line)
                }
            }
            HStack {
                Spacer()
                Button("Close") { session.dismissPresentation() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier(AXID.Decision.newspaperClose)
            }
        }
    }
}

/// Plain interim headline lines (the classic string tables arrive with the M9 newspaper).
enum NewspaperText {
    static func interimLine(_ h: Headline, state: GameState) -> LocalizedStringResource {
        switch h {
        case .event: "Local news of recent events."
        case .internalPressure: "Troubles in this system."
        case .villain: "A notorious criminal is at large."
        case .hero: "A local hero is celebrated."
        case let .moonForSale(system): "A moon is for sale at \(Names.system(system, in: state))."
        case let .tribbleBuyer(system): "A collector at \(Names.system(system, in: state)) buys tribbles."
        case let .shipyard(system): "A shipyard at \(Names.system(system, in: state)) builds custom ships."
        case let .externalPressure(_, _, system): "News from \(Names.system(system, in: state))."
        case .canned: "Local headlines."
        }
    }
}
