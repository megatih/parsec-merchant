// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// UI-ENC-057/058: the arrival, arrest, escape-pod and reactor report sheet. The critical sections come first, then the
/// arrival sections; Continue (the default) dismisses it.
struct ReportSheetView: View {
    @Environment(GameSession.self) private var session
    let sheet: ReportSheet

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text(ReportSheetText.title(sheet.kind)).font(.title2.bold())
            } icon: {
                Image(systemName: ReportSheetText.symbol(sheet.kind))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(sheet.criticalSections.enumerated()), id: \.offset) { _, section in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: section.title).font(.headline)
                            ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                                Text(verbatim: line).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    if let arrival = sheet.arrival {
                        if !sheet.criticalSections.isEmpty { Divider() }
                        Text(verbatim: arrival.summary).font(.headline)
                        ArrivalSectionsView(report: arrival)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 160, maxHeight: 420)
            HStack {
                Spacer()
                Button("Continue") { session.dismissPresentation() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier(AXID.Report.continueButton)
            }
        }
        .padding(24)
        .frame(width: 520)
        .interactiveDismissDisabled()
        // UI-KEYS-021: Esc and ⌘. press the only button.
        .sheetEscape { session.dismissPresentation() }
        .accessibilityElement(children: .contain)
        .accessibilityValue(Text(verbatim: sheet.kind.rawValue))
        .accessibilityIdentifier(AXID.Report.sheet)
    }
}

/// The report sheet's title and symbol per kind (UI-ENC-058).
enum ReportSheetText {
    static func title(_ kind: ReportSheet.Kind) -> LocalizedStringResource {
        switch kind {
        case .arrival: "Arrival Report"
        case .arrest: "Arrested"
        case .escapePod: "Escape Pod"
        case .reactorMeltdown: "Reactor Meltdown"
        }
    }

    static func symbol(_ kind: ReportSheet.Kind) -> String {
        switch kind {
        case .arrival: "flag.checkered"
        case .arrest: "exclamationmark.shield"
        case .escapePod: "lifepreserver"
        case .reactorMeltdown: "exclamationmark.octagon.fill"
        }
    }
}
