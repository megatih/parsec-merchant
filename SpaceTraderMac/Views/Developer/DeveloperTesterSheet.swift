// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// UI-ENC-092 / CHEAT-038: lists every ALR row and every special-event narrative page; choosing one previews that
/// presentation with fixture values. Nothing here sends a command.
struct DeveloperTesterSheet: View {
    @Environment(GameSession.self) private var session
    @State private var selection: DeveloperTester.Item?

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                list
                    .frame(minWidth: 260, idealWidth: 280)
                preview
                    .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack {
                Text("Previews only: the game is not changed.")
                    .scaledFont(.caption)
                    .foregroundStyle(.readableSecondary)
                Spacer()
                Button("Close") { session.dismissPresentation() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier(AXID.DevTester.close)
            }
            .padding(12)
        }
        .frame(width: 720, height: 520)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.DevTester.sheet)
    }

    private var list: some View {
        List(selection: $selection) {
            SwiftUI.Section("Alerts (ALR)") {
                ForEach(ALRCatalog.rows, id: \.number) { row in
                    HStack {
                        Text(verbatim: "\(row.number)").monospacedDigit().foregroundStyle(.readableSecondary)
                        Text(verbatim: row.alertType)
                    }
                    .tag(DeveloperTester.Item.alr(row.number))
                    .accessibilityIdentifier(AXID.DevTester.alr(row.number))
                }
            }
            SwiftUI.Section("Special events") {
                ForEach(SpecialEventType.allCases, id: \.self) { type in
                    Text(SpecialEventText.title(type))
                        .tag(DeveloperTester.Item.narrative(type))
                        .accessibilityIdentifier(AXID.DevTester.narrative(type))
                }
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let sample = currentSample {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: sample.surface)
                    .font(.caption.smallCaps())
                    .foregroundStyle(.readableSecondary)
                Text(verbatim: sample.title)
                    .scaledFont(.title3, weight: .bold)
                ScrollView {
                    Text(verbatim: sample.message)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !sample.buttons.isEmpty {
                    HStack {
                        Spacer()
                        ForEach(Array(sample.buttons.enumerated()), id: \.offset) { index, label in
                            Text(verbatim: label)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(.quaternary, in: Capsule())
                                .foregroundStyle(index == 0 && sample.isDestructive ? Color.signalRed : Color.primary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ContentUnavailableView("Choose an alert or a special event", systemImage: "rectangle.on.rectangle")
        }
    }

    private var currentSample: TesterSample? {
        guard let selection, let state = session.state else { return nil }
        switch selection {
        case let .alr(number):
            guard let row = ALRCatalog.rows.first(where: { $0.number == number }) else { return nil }
            return ALRCatalog.sample(for: row, state: state, session: session)
        case let .narrative(type):
            return ALRCatalog.narrativeSample(type)
        }
    }
}
