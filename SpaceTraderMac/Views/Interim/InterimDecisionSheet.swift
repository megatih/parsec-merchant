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
            case let .newspaper(paper):
                NewspaperSheet(paper: paper)
            // Trade, plunder and scoop have their UI-ENC views (UI-ENC-045…049); confirmations are dialogs.
            case .tradeInOrbit, .plunder, .scoop, .confirm:
                PlaceholderSheet(route: nil)
            }
        }
        .padding(24)
        .frame(minWidth: 420)
        .interactiveDismissDisabled()
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
