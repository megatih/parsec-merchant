// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// The content of each `SheetRoute`. Routes whose screens belong to other specs show a placeholder until built.
struct SheetRouteView: View {
    @Environment(GameSession.self) private var session
    let route: SheetRoute

    var body: some View {
        switch route {
        case .newGame:
            NewGameWizard()
        case let .retire(pending):
            RetireSheet(pending: pending)
        case let .shipPurchase(request):
            ShipPurchaseSheet(request: request)
        case .findSystem:
            FindSystemSheet()
        case .openSavedGame:
            OpenSavedGameSheet()
        case .cheatConsole:
            CheatConsoleSheet()
        case let .tradeInOrbit(offer):
            TradeInOrbitSheet(offer: offer)
        case let .plunder(context):
            PlunderSheet(context: context)
        case let .newspaper(paper):
            NewspaperSheet(paper: paper)
        case let .narrative(page):
            NarrativeSheet(page: page)
        case let .report(sheet):
            ReportSheetView(sheet: sheet)
        case .developerTester:
            DeveloperTesterSheet()
        case let .priceDetails(item):
            PriceDetailsSheet(item: item)
        case let .cargoDisposal(disposal):
            CargoDisposalSheet(disposal: disposal)
        case let .serviceAmount(kind):
            ServiceAmountSheet(kind: kind)
        }
    }
}

/// Stand-in for sheets that their owners add (Open, Options, Find, Purchase review, Cheat console).
struct PlaceholderSheet: View {
    @Environment(GameSession.self) private var session
    let route: SheetRoute?

    var body: some View {
        VStack(spacing: 16) {
            Text("This screen isn't available yet.")
                .scaledFont(.headline)
            Button("Close") { session.dismissPresentation() }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier(AXID.Dialog.placeholderClose)
        }
        .padding(32)
        .frame(width: 420)
    }
}

/// The retire confirmation (ALR-104, UI-SHELL-096): Retire is destructive, Cancel is the default.
struct RetireSheet: View {
    @Environment(GameSession.self) private var session
    let pending: PendingConfirmation

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Retire?")
                .scaledFont(.title2, weight: .bold)
            if let state = session.state {
                Text(verbatim: ConfirmationText.content(for: pending.confirmation, state: state).message)
            }
            HStack {
                Spacer()
                Button("Retire", role: .destructive) { session.confirm(pending) }
                    .accessibilityIdentifier(AXID.Dialog.retireConfirm)
                Button("Cancel", role: .cancel) { session.cancel() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier(AXID.Dialog.retireCancel)
            }
        }
        .padding(24)
        .frame(width: 420)
        // UI-KEYS-020/021: Cancel is both the default and the Esc button.
        .sheetEscape { session.cancel() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Dialog.retireSheet)
    }
}
