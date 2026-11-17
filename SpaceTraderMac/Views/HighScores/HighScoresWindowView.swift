// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import ParsecPersistence
import SwiftUI

/// UI-ENC-087…089: the top 10 per ruleset. Works with no game loaded; reloads from `HighScoreStore` when it opens,
/// after each recording and after Clear High Scores.
struct HighScoresWindowView: View {
    static let windowID = "scores"
    static let defaultSize = CGSize(width: 560, height: 520)

    @Environment(GameSession.self) private var session
    @State private var selected: RulesetID = .modern
    @State private var table = HighScoreTable()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            rulesetPicker
            ScrollView {
                VStack(spacing: 0) {
                    let highlighted = HighScoreRowModel.highlightedRank(recorded: session.recordedScore,
                                                                        gameRuleset: session.state?.rulesetID, shown: selected)
                    ForEach(HighScoreRowModel.rows(table: table, ruleset: Ruleset.named(selected))) { row in
                        HighScoreRowView(row: row, isNew: row.rank == highlighted)
                        Divider()
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 400)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Scores.window)
        .onAppear {
            selected = HighScoresSelection.initial(gameRuleset: session.state?.rulesetID,
                                                   stored: session.defaults.string(forKey: HighScoresSelection.defaultsKey))
            reload()
        }
        .onChange(of: session.highScoresRevision) {
            selected = HighScoresSelection.initial(gameRuleset: session.state?.rulesetID,
                                                   stored: session.defaults.string(forKey: HighScoresSelection.defaultsKey))
            reload()
        }
        .onChange(of: selected) {
            session.defaults.set(selected.rawValue, forKey: HighScoresSelection.defaultsKey)
            reload()
        }
    }

    /// A segmented control built from buttons, so each segment carries its own identifier.
    private var rulesetPicker: some View {
        HStack(spacing: 0) {
            ForEach(RulesetID.allCases, id: \.self) { r in
                Button {
                    selected = r
                } label: {
                    Text(Names.ruleset(r)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
                .padding(.vertical, 5)
                .background(r == selected ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: 6))
                .accessibilityAddTraits(r == selected ? .isSelected : [])
                .accessibilityIdentifier(AXID.Scores.ruleset(r))
            }
        }
        .padding(2)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func reload() {
        table = (try? session.highScoreStore.table(for: selected)) ?? HighScoreTable()
    }
}

/// UI-ENC-089: one rank: rank, name, score and the SCORE-039 line, with the Ironman badge and ↺ marker.
struct HighScoreRowView: View {
    let row: HighScoreRow
    let isNew: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: "\(row.rank).")
                .monospacedDigit()
                .frame(width: 28, alignment: .trailing)
                .foregroundStyle(.secondary)
            if let e = row.entry {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(verbatim: e.name).bold()
                        if e.ironman {
                            Label("Ironman", systemImage: "shield.lefthalf.filled")
                                .font(.caption.bold())
                                .accessibilityIdentifier(AXID.Scores.rowIronman(row.rank))
                        }
                        if e.reloaded {
                            Label("↺ reloaded", systemImage: "arrow.counterclockwise")
                                .labelStyle(.titleOnly)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(verbatim: e.scoreText).monospacedDigit().bold()
                    }
                    Text(verbatim: e.line)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Empty").foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(isNew ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .contain)
        .accessibilityValue(isNew ? Text("new") : Text(verbatim: ""))
        .accessibilityIdentifier(AXID.Scores.row(row.rank))
    }
}
