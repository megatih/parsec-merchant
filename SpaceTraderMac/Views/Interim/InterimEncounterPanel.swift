// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// The interim encounter panel (UI-SHELL-010; replaced by UI-ENC in M9). Any encounter can be finished from here.
struct InterimEncounterPanel: View {
    @Environment(GameSession.self) private var session

    var body: some View {
        VStack(spacing: 20) {
            if let engine = session.engine, let model = InterimEncounterModel.make(engine: engine) {
                Text(EncounterText.intro(preview: model.preview, clicks: model.clicks, destination: model.destination,
                                         state: engine.state))
                    .font(.title3)
                    .multilineTextAlignment(.center)
                HStack(spacing: 40) {
                    shipStatus(title: "Your ship", hull: model.preview.playerHullPercent, shields: model.preview.playerShieldPercent)
                    shipStatus(title: "Opponent", hull: model.preview.opponentHullPercent,
                               shields: model.preview.opponentShieldPercent)
                }
                if let resume = resumeDecision(engine.state) {
                    Button("Continue Decision") { session.present(resume) }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier(AXID.Encounter.resumeDecision)
                } else {
                    HStack {
                        ForEach(model.preview.actions, id: \.action) { a in
                            Button { session.send(.encounter(a.action)) } label: { Text(Names.encounterAction(a.action)) }
                                .disabled(!a.enabled || session.isInputLocked)
                                .help(a.rejection.map { Text(ReasonText.text(for: $0)) } ?? Text(Names.encounterAction(a.action)))
                                .accessibilityIdentifier(AXID.Encounter.action(a.action))
                        }
                    }
                    .controlSize(.large)
                    if let command = model.returnCommand {
                        Button("Default Action") { session.send(command) }
                            .keyboardShortcut(.defaultAction)
                            .disabled(session.isInputLocked)
                            .hidden()
                            .accessibilityHidden(true)
                    }
                }
            } else {
                Text("In transit…").font(.title3)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Encounter.interimPanel)
    }

    private func shipStatus(title: LocalizedStringResource, hull: Int, shields: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text("Hull \(hull)%").monospacedDigit()
            Text("Shields \(shields)%").monospacedDigit()
        }
    }

    /// A pending engine decision whose sheet was closed: offer it again so the game can't get stuck.
    private func resumeDecision(_ s: GameState) -> Presentation? {
        guard !session.isModal else { return nil }
        if let offer = s.pendingOrbitTrade { return .sheet(.tradeInOrbit(offer)) }
        if let plunder = s.pendingPlunder {
            return .sheet(.plunder(PlunderSheetContext(victimCargo: plunder.victimCargo, source: .opponent)))
        }
        if let item = s.pendingScoop { return .scoop(item) }
        return nil
    }
}
