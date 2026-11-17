// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecArt
import ParsecEngine
import ParsecInsights
import SwiftUI

/// ACH-010 / ACH-019 / ACH-020: the grid of badges for the current ruleset.
struct AchievementsView: View {
    @Environment(GameSession.self) private var session
    @State private var showUnavailable = false

    var body: some View {
        if let state = session.state {
            let m = model(state)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(verbatim: m.headerText).scaledFont(.headline)
                    if let banner = m.disabledBanner {
                        Label { Text(verbatim: banner) } icon: { Image(systemName: "nosign") }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier(AXID.Logbook.achievementsDisabled)
                    }
                    grid(m.badges)
                    if !m.unavailable.isEmpty {
                        DisclosureGroup(isExpanded: $showUnavailable) {
                            grid(m.unavailable).saturation(0)  // A11Y-029: greyed without lowering text contrast
                        } label: {
                            Text("Not available in this ruleset")
                        }
                        .accessibilityIdentifier(AXID.Logbook.achievementsUnavailable)
                    }
                }
                .padding(16)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AXID.Logbook.achievements)
        }
    }

    /// Reads `achievementsRevision` so the grid refreshes after an unlock or a reset.
    private func model(_ state: GameState) -> AchievementsModel {
        _ = session.achievementsRevision
        return AchievementsModel.make(stats: session.careerStats, ruleset: state.ruleset, records: session.achievements.records,
                                      journal: session.journal, cheatsUsed: state.cheatsUsed)
    }

    private func grid(_ badges: [AchievementsModel.Badge]) -> some View {
        AccessibleLazyVGrid(label: "Achievements", columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
            ForEach(badges) { BadgeView(badge: $0) }
        }
    }
}

private struct BadgeView: View {
    let badge: AchievementsModel.Badge

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AchievementBadgeView(id: badge.id, unlocked: badge.unlocked)
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(verbatim: badge.name).scaledFont(.headline)
                    if badge.unlocked {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.signalGreen).accessibilityLabel(Text("Unlocked"))
                    }
                }
                Text(verbatim: badge.description).scaledFont(.caption).foregroundStyle(.readableSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let p = badge.progress, !badge.unlocked {
                    ProgressView(value: Double(p.current), total: Double(max(1, p.target)))
                    Text(verbatim: "\(p.current.formatted()) / \(p.target.formatted())").scaledFont(.caption2).monospacedDigit()
                }
                if let text = badge.unlockedText {
                    Text(verbatim: [text, badge.inGameText].compactMap(\.self).joined(separator: ", "))
                        .scaledFont(.caption2)
                        .foregroundStyle(.readableSecondary)
                } else if !badge.unlocked {
                    Text("Locked").scaledFont(.caption2).foregroundStyle(.readableSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        // A11Y-029: a labelled container; its texts keep their own (readable) colours for the contrast audit.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: badge.accessibilityText))
        .accessibilityIdentifier(AXID.Logbook.badge(badge.id))
    }
}
