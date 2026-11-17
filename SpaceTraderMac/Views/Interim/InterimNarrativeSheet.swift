// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// Temporary narrative sheet (replaced by the UI-ENC-075 narrative sheet). The offer page is the `acceptSpecialEvent`
/// consent: Accept dismisses, then sends `.specialEvent` acknowledging it (UI-ENC-076).
struct InterimNarrativeSheet: View {
    @Environment(GameSession.self) private var session
    let page: NarrativePage

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch page {
            case let .offer(type):
                Text(SpecialEventText.title(type)).font(.title2.bold())
                    .accessibilityIdentifier(AXID.Narrative.title)
                ScrollView {
                    Text(SpecialEventText.story(type)).frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 240)
                .accessibilityIdentifier(AXID.Narrative.story)
                let blocker = session.engine?.specialEventPreview?.blocker
                if let blocker {
                    Text(ReasonText.text(for: blocker)).foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button("Decline") { session.cancel() }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier(AXID.Narrative.decline)
                    Button("Accept") {
                        session.dismissPresentation()
                        session.send(.specialEvent, acknowledging: [.acceptSpecialEvent])
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(blocker != nil)
                    .accessibilityIdentifier(AXID.Narrative.accept)
                }
            case let .result(result):
                Text(verbatim: result.title).font(.title2.bold())
                    .accessibilityIdentifier(AXID.Narrative.title)
                Text(verbatim: result.message)
                HStack {
                    Spacer()
                    Button("Continue") { session.dismissPresentation() }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier(AXID.Narrative.continueButton)
                }
            }
        }
        .padding(24)
        .frame(width: 460)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Narrative.sheet)
    }
}
