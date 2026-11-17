// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// UI-ENC-071: the styled broadsheet: masthead in New York serif with a rule and date line, serif headlines in one or
/// two balanced columns, Close as the default button and Esc. It reads only the `Newspaper` it was given.
struct NewspaperSheet: View {
    @Environment(GameSession.self) private var session
    let paper: Newspaper

    var body: some View {
        VStack(spacing: 14) {
            if let state = session.state {
                let model = NewspaperSheetModel.make(paper: paper, state: state)
                VStack(spacing: 6) {
                    Text(verbatim: model.masthead)
                        .font(.system(size: 34, weight: .black, design: .serif))
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier(AXID.Newspaper.masthead)
                    Rectangle().frame(height: 2)
                    Text(verbatim: model.dateLine)
                        .font(.system(.caption, design: .serif).smallCaps())
                        .foregroundStyle(.secondary)
                    Rectangle().frame(height: 1)
                }
                ScrollView {
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(Array(model.columns.enumerated()), id: \.offset) { column, lines in
                            if column > 0 { Divider() }
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(Array(lines.enumerated()), id: \.offset) { row, line in
                                    let index = column == 0 ? row : model.columns[0].count + row
                                    Text(verbatim: line)
                                        .font(.system(.title3, design: .serif).weight(.semibold))
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .accessibilityIdentifier(AXID.Newspaper.headline(index))
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 380)
            }
            HStack {
                Spacer()
                Button("Close") { session.dismissPresentation() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier(AXID.Decision.newspaperClose)
            }
        }
        .padding(28)
        .frame(width: 560)
        // UI-KEYS-021: Esc and ⌘. press the only button.
        .sheetEscape { session.dismissPresentation() }
        .background(Color(nsColor: .textBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Newspaper.sheet)
    }
}

/// UI-ENC-072: the Bridge newspaper card (masthead when paid, else "Local newspaper" and the price).
struct NewspaperCardView: View {
    @Environment(GameSession.self) private var session
    let model: NewspaperCardModel

    var body: some View {
        GroupBox {
            HStack {
                if let masthead = model.masthead {
                    Text(verbatim: masthead).font(.system(.headline, design: .serif))
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Local newspaper")
                        Text("Price: \(model.cost.formatted()) cr.").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Read") { session.readNewspaper() }
                    .disabled(model.blocker != nil)
                    .help(model.blocker.map { Text(ReasonText.text(for: $0)) } ?? Text("Read the local newspaper."))
                    .accessibilityIdentifier(AXID.Bridge.newspaperRead)
            }
            if let blocker = model.blocker {
                Text(ReasonText.text(for: blocker)).font(.caption).foregroundStyle(.secondary)
            }
        } label: {
            Label("Newspaper", systemImage: "newspaper")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Newspaper.bridgeCard)
    }
}
