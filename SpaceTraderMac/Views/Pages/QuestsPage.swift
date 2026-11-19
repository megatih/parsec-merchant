// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// Quests (⌘7, PRD §4.10): one panel per open quest, then the completed chains, always in view.
struct QuestsPage: View {
    @Environment(GameSession.self) private var session
    @Environment(\.pmScale) private var scale
    @Namespace private var rotorNamespace

    var body: some View {
        GamePage(section: .quests) {
            if let state = session.state {
                let model = QuestsModel.make(state: state)
                PMFitScroll {
                    VStack(alignment: .leading, spacing: PMSpace.s * scale) {
                        if model.cards.isEmpty {
                            PMPanel(identifier: "quests.none") {
                                PMEmptyState(symbol: "list.star", message: QuestText.none, identifier: "quests.none.text").frame(minHeight: 100 * scale)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(model.cards) { card in
                            QuestPanel(card: card, state: state)
                                .accessibilityRotorEntry(id: card.index, in: rotorNamespace)
                        }
                        if !model.finished.isEmpty { completed(model.finished) }
                    }
                    // A11Y-014: the "Deadlines" rotor, soonest first.
                    .accessibilityRotor(Text("Deadlines")) {
                        ForEach(QuestRotors.deadlineCards(model.cards)) { card in
                            AccessibilityRotorEntry(Text(QuestText.title(for: card.entry.kind, state: state)), id: card.index, in: rotorNamespace)
                        }
                    }
                }
            }
        }
    }

    private func completed(_ finished: [QuestsModel.Finished]) -> some View {
        PMPanel("Completed", identifier: AXID.Quests.completed) {
            ForEach(finished) { f in
                PMInfoRow(label: f.chain.title) {
                    Label { Text(f.outcome) } icon: { Image(systemName: f.failed ? "xmark.circle" : "checkmark.circle").accessibilityHidden(true) }
                        .foregroundStyle(f.failed ? PMColor.loss : PMColor.profit)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// One open quest: its title, the stops of a chain, the deadline and its systems.
private struct QuestPanel: View {
    @Environment(GameSession.self) private var session
    @Environment(\.openWindow) private var openWindow
    @Environment(\.pmScale) private var scale
    let card: QuestsModel.Card
    let state: GameState

    var body: some View {
        PMPanel(identifier: AXID.Quests.entry(card.index)) {
            Text(QuestText.title(for: card.entry.kind, state: state))
                .pmFont(.valueLarge)
                .foregroundStyle(PMColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let steps = card.steps { stepsView(steps) }
            if let days = card.entry.daysLeft, let span = card.deadlineSpan {
                PMGauge(label: "Deadline", fraction: Double(days) / Double(max(1, span)),
                        valueText: days == 1 ? String(localized: "1 day left") : String(localized: "\(days) days left"),
                        tone: days <= 2 ? .loss : (days <= 5 ? .caution : .neutral), identifier: "quests.entry.\(card.index).deadline")
                    .frame(maxWidth: 360 * scale)
                    .accessibilityValue(Text(verbatim: AccessibilityText.deadline(daysLeft: days)))  // A11Y-004
            }
            if !card.entry.systems.isEmpty { links }
        }
        .fixedSize(horizontal: false, vertical: true)
        .contextMenu {
            // UI-PTR-005: the entry's visible action.
            if let first = card.entry.systems.first {
                Button("Show on Galactic Chart") { showOnChart(first) }
            }
        }
        .accessibilityLabel(Text(QuestText.title(for: card.entry.kind, state: state)))
    }

    private var links: some View {
        HStack(spacing: PMSpace.s * scale) {
            ForEach(card.entry.systems, id: \.self) { system in
                // UI-NAV-006: setting the target keeps the page; only the chart link leaves it.
                PMButton(title: "Target \(Names.system(system, in: state))", systemImage: "scope",
                         help: "Select \(Names.system(system, in: state)) as your target",
                         disabledReason: session.isInputLocked ? String(localized: ReasonText.text(for: .pendingDecisionFirst)) : nil,
                         identifier: AXID.Quests.system(entry: card.index, system: system)) {
                    session.selectQuestSystem(system)
                }
                .fixedSize()
            }
            if let first = card.entry.systems.first {
                PMButton(title: "Show on Galactic Chart", systemImage: "arrow.right", kind: .quiet,
                         help: "Open the Galactic Chart on \(Names.system(first, in: state))", identifier: AXID.Galaxy.questShowOnMap(card.index)) {
                    showOnChart(first)
                }
                .fixedSize()
            }
        }
    }

    private func showOnChart(_ system: Int) {
        if session.map.galaxyWindowOpen { openWindow(id: GalaxyWindowMetrics.id) }
        session.showOnMap(system)
    }

    private func stepsView(_ steps: [QuestsModel.Step]) -> some View {
        HStack(spacing: 6 * scale) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                if i > 0 { Image(systemName: "arrow.forward").foregroundStyle(PMColor.textSecondary).accessibilityHidden(true) }
                Label {
                    Text(verbatim: Names.system(step.system, in: state))
                } icon: {
                    Image(systemName: step.done ? "checkmark.circle.fill" : "circle").foregroundStyle(step.done ? PMColor.profit : PMColor.textSecondary)
                }
                .foregroundStyle(PMColor.textPrimary)
                .accessibilityLabel(step.done ? Text("\(Names.system(step.system, in: state)), done")
                                              : Text(verbatim: Names.system(step.system, in: state)))
            }
        }
        .pmFont(.body)
    }
}
