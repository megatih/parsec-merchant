// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// The arrival sections, shared by the card and the arrival sheet (UI-ENC-054, -057).
struct ArrivalSectionsView: View {
    @Environment(GameSession.self) private var session
    let report: ArrivalReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let rip = report.fabricRip {
                Label {
                    Text(verbatim: rip)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .scaledFont(.callout, weight: .bold)
            }
            ForEach(report.sections, id: \.title) { section in
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: section.title).scaledFont(.subheadline, weight: .bold).foregroundStyle(.readableSecondary)
                    switch section.kind {
                    case .encounters? where !report.encounters.isEmpty:
                        ForEach(Array(report.encounters.enumerated()), id: \.offset) { index, encounter in
                            EncounterSummaryRow(encounter: encounter, index: index)
                        }
                    case .news?:
                        NewsTeaserRow()
                    default:
                        ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                            Text(verbatim: line).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(section.kind.map(AXID.Arrival.section) ?? "")
            }
        }
    }
}

/// One encounter of the trip; expands to its frozen combat log (UI-ENC-055).
private struct EncounterSummaryRow: View {
    let encounter: EncounterSummary
    let index: Int
    @State private var expanded = false
    @Environment(\.accessibilityPreferences) private var a11yPrefs

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            if encounter.log.isEmpty {
                Text("No combat.").foregroundStyle(.readableSecondary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(encounter.log.enumerated()), id: \.offset) { _, line in
                        Text(verbatim: line).scaledFont(.callout, design: .monospaced)
                    }
                }
                .textSelection(.enabled)
            }
        } label: {
            Text(verbatim: ArrivalText.encounterLine(encounter))
        }
        .accessibilityIdentifier(AXID.Arrival.encounter(index))
    }
}

/// UI-ENC-063: the news teaser (live: it reveals a headline only once this visit's paper is paid).
private struct NewsTeaserRow: View {
    @Environment(GameSession.self) private var session

    var body: some View {
        if let state = session.state {
            let teaser = NewsTeaser.make(state: state)
            let blocker = NewspaperCardModel.blocker(state: state)
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: teaser.text)
                    .scaledFont(.body, design: teaser.headline == nil ? .default : .serif)
                Spacer()
                Button("Read") { session.readNewspaper() }
                    .disabled(blocker != nil || session.isInputLocked)
                    .help(blocker.map { Text(ReasonText.text(for: $0)) } ?? Text("Read the local newspaper."))
                    .accessibilityIdentifier(AXID.Arrival.newsRead)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AXID.Arrival.news)
        }
    }
}
