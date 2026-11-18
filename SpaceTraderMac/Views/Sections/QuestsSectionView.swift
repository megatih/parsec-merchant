// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// Quests section (⌘8): open quests as cards and the collapsible completed group (UI-SHELL-086/087).
struct QuestsSectionView: View {
    @Environment(GameSession.self) private var session
    @State private var showCompleted = false
    @Namespace private var rotorNamespace

    var body: some View {
        ScrollView {
            if let state = session.state {
                let model = QuestsModel.make(state: state)
                VStack(alignment: .leading, spacing: 16) {
                    if model.cards.isEmpty {
                        Text(QuestText.none).foregroundStyle(.readableSecondary)
                    }
                    ForEach(model.cards) { card in
                        QuestCardView(card: card, state: state) { system in session.selectQuestSystem(system) }
                            .accessibilityRotorEntry(id: card.index, in: rotorNamespace)
                    }
                    if !model.finished.isEmpty {
                        DisclosureGroup(isExpanded: $showCompleted) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(model.finished) { f in
                                    LabeledContent {
                                        Text(f.outcome).foregroundStyle(f.failed ? .signalRed : .signalGreen)
                                    } label: {
                                        Text(f.chain.title)
                                    }
                                }
                            }
                            .padding(.top, 6)
                        } label: {
                            Text("Completed (\(model.finished.count))").scaledFont(.headline)
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier(AXID.Quests.completed)
                    }
                }
                .padding(20)
                .frame(maxWidth: 720, alignment: .leading)
                // A11Y-014: the "Deadlines" rotor, soonest first.
                .accessibilityRotor(Text("Deadlines")) {
                    ForEach(QuestRotors.deadlineCards(model.cards)) { card in
                        AccessibilityRotorEntry(Text(QuestText.title(for: card.entry.kind, state: state)), id: card.index,
                                                in: rotorNamespace)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.SectionRoot.root(.quests))
    }
}

/// One open quest.
private struct QuestCardView: View {
    @Environment(GameSession.self) private var session
    @Environment(\.openWindow) private var openWindow
    let card: QuestsModel.Card
    let state: GameState
    let select: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(QuestText.title(for: card.entry.kind, state: state))
                .scaledFont(.headline)
                .fixedSize(horizontal: false, vertical: true)
            if let steps = card.steps { stepsView(steps) }
            if let days = card.entry.daysLeft, let span = card.deadlineSpan {
                Gauge(value: Double(days), in: 0...Double(span)) {
                    Text("Deadline")
                } currentValueLabel: {
                    Text(days == 1 ? "1 day left" : "\(days) days left").monospacedDigit()
                }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(days <= 2 ? .red : .orange)
                .frame(maxWidth: 260)
                .accessibilityRepresentation {
                    ProgressView(value: Double(days), total: Double(span)) { Text("Deadline") }
                        .accessibilityValue(Text(verbatim: AccessibilityText.deadline(daysLeft: days)))  // A11Y-004
                }
            }
            if !card.entry.systems.isEmpty {
                HStack(spacing: 12) {
                    ForEach(card.entry.systems, id: \.self) { system in
                        Button {
                            select(system)
                        } label: {
                            Label { Text(verbatim: Names.system(system, in: state)) } icon: { Image(systemName: "scope") }
                        }
                        .buttonStyle(.link)
                        .help(Text("Select \(Names.system(system, in: state)) as your target."))
                        .accessibilityIdentifier(AXID.Quests.system(entry: card.index, system: system))
                    }
                    if let first = card.entry.systems.first {
                        Button("Show on Map") {
                            if session.map.galaxyWindowOpen { openWindow(id: GalaxyWindowMetrics.id) }
                            session.showOnMap(first)
                        }
                        .buttonStyle(.link)
                        .help(Text("Centre the galaxy chart on \(Names.system(first, in: state))."))
                        .accessibilityIdentifier(AXID.Galaxy.questShowOnMap(card.index))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background.secondary, in: .rect(cornerRadius: 10))
        .contextMenu {
            // UI-PTR-005: the entry's visible action.
            if let first = card.entry.systems.first {
                Button("Show on Map") {
                    if session.map.galaxyWindowOpen { openWindow(id: GalaxyWindowMetrics.id) }
                    session.showOnMap(first)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(QuestText.title(for: card.entry.kind, state: state)))
        .accessibilityIdentifier(AXID.Quests.entry(card.index))
    }

    private func stepsView(_ steps: [QuestsModel.Step]) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                if i > 0 { Image(systemName: "arrow.forward").foregroundStyle(.readableSecondary).accessibilityHidden(true) }
                Label {
                    Text(verbatim: Names.system(step.system, in: state))
                } icon: {
                    Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(step.done ? AnyShapeStyle(.signalGreen) : AnyShapeStyle(.secondary))
                }
                .accessibilityLabel(step.done ? Text("\(Names.system(step.system, in: state)), done")
                                              : Text(verbatim: Names.system(step.system, in: state)))
            }
        }
        .scaledFont(.callout)
    }
}
