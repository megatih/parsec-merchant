// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// UI-ENC-075/077: the narrative sheet. The offer page is the `acceptSpecialEvent` consent (UI-ENC-076); the result
/// page closes with Continue.
struct NarrativeSheet: View {
    @Environment(GameSession.self) private var session
    let page: NarrativePage

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch page {
            case let .offer(type):
                if let state = session.state {
                    offer(NarrativeModel.offer(type: type, state: state, preview: session.engine?.specialEventPreview))
                }
            case let .result(result):
                Text(verbatim: result.title).scaledFont(.title2, weight: .bold).accessibilityAddTraits(.isHeader)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(AXID.Narrative.title)
                ScrollView {
                    Text(verbatim: result.message).frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 260)
                .accessibilityIdentifier(AXID.Narrative.story)
                HStack {
                    Spacer()
                    Button("Continue") { session.dismissPresentation() }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier(AXID.Narrative.continueButton)
                }
            }
        }
        .padding(24)
        .frame(width: 480)
        .interactiveDismissDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Narrative.sheet)
    }

    @ViewBuilder
    private func offer(_ model: NarrativeOffer) -> some View {
        HStack(alignment: .center, spacing: 14) {
            if let state = session.state {
                NarrativeVignetteView(type: model.type, state: state)
                    .accessibilityIdentifier(AXID.Narrative.vignette)
            }
            Text(verbatim: model.title).scaledFont(.title2, weight: .bold).accessibilityAddTraits(.isHeader)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(AXID.Narrative.title)
        }
        ScrollView {
            Text(verbatim: model.story).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 240)
        .accessibilityIdentifier(AXID.Narrative.story)
        if let price = model.priceLine {
            Text(verbatim: price).monospacedDigit().scaledFont(.headline)
        }
        if let blocker = model.blocker {
            Label {
                Text(ReasonText.text(for: blocker))
            } icon: {
                Image(systemName: "exclamationmark.circle")
            }
            .foregroundStyle(.readableSecondary)
        }
        HStack {
            Spacer()
            if model.messageOnly {
                Button("Continue") { session.acceptSpecialEvent(messageOnly: true) }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier(AXID.Narrative.continueButton)
            } else {
                Button("Decline") { session.cancel() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier(AXID.Narrative.decline)
                Button("Accept") { session.acceptSpecialEvent(messageOnly: false) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canAccept)
                    .help(model.blocker.map { Text(ReasonText.text(for: $0)) } ?? Text("Accept the offer."))
                    .accessibilityIdentifier(AXID.Narrative.accept)
            }
        }
    }
}

/// UI-ENC-073: the Bridge special-event card: title, excerpt and price; Read…/Accept… opens the narrative sheet,
/// Decline hides the card until the next arrival.
struct SpecialEventCardView: View {
    @Environment(GameSession.self) private var session
    let model: SpecialEventCardModel
    let decline: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text(SpecialEventText.title(model.type)).scaledFont(.headline)
                Text(verbatim: NarrativeModel.excerpt(String(localized: SpecialEventText.story(model.type))))
                    .fixedSize(horizontal: false, vertical: true)
                if let price = NarrativeModel.priceLine(model.price) {
                    Text(verbatim: price).monospacedDigit()
                }
                HStack {
                    Spacer()
                    if !model.messageOnly {
                        Button("Decline", action: decline)
                            .help(Text("Hide this offer until your next arrival."))
                            .accessibilityIdentifier(AXID.Bridge.specialDecline)
                    }
                    Button(model.messageOnly ? "Read…" : "Accept…") { session.openSpecialEvent() }
                        .help(Text("Open the full story."))
                        .accessibilityIdentifier(AXID.Bridge.specialAccept)
                }
            }
        } label: {
            Label("Special", systemImage: "sparkles")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Bridge.special)
    }
}
