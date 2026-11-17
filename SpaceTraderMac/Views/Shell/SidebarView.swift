// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// Sidebar rows with shortcuts and badges (UI-SHELL-035/036); locked while not docked (UI-SHELL-037).
struct SidebarView: View {
    @Environment(GameSession.self) private var session

    var body: some View {
        let badges = SidebarBadges.make(state: session.state)
        let lock = SidebarLock.make(phase: session.state?.phase, transitPlaying: session.transitPlayback != nil)
        let context = session.sectionContext
        List(selection: selectionBinding(locked: lock != .none)) {
            if let label = lock.label {
                Text(label)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(AXID.Transit.sidebarPhaseLabel)
            }
            ForEach(Section.allCases) { section in
                SidebarRow(section: section, badge: badges.badge(for: section))
                    .tag(section)
                    .disabled(lock != .none || !section.isAvailable(in: context))
                    // `.contain` keeps the row's identifier from overwriting the badge's own (`sidebar.crew.badge`).
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(section.axID)
            }
        }
        .accessibilityIdentifier(AXID.Sidebar.list)
    }

    private func selectionBinding(locked: Bool) -> Binding<Section?> {
        Binding {
            session.selectedSection
        } set: { new in
            if let new, !locked { session.selectedSection = new }
        }
    }
}

private struct SidebarRow: View {
    let section: Section
    let badge: SidebarBadges.Badge?

    var body: some View {
        HStack {
            Label { Text(section.title) } icon: { Image(systemName: section.systemImage) }
            Spacer()
            if let badge {
                badgeView(badge)
                    .accessibilityLabel(Text(badge.accessibilityLabel))
            }
            Text(verbatim: "⌘\(section.shortcutDigit)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func badgeView(_ badge: SidebarBadges.Badge) -> some View {
        switch badge {
        case .special:
            Image(systemName: "sparkle")
                .foregroundStyle(.yellow)
                .accessibilityIdentifier(AXID.Sidebar.bridgeBadge)
        case let .count(n):
            Text(verbatim: "\(n)")
                .font(.caption.bold())
                .padding(.horizontal, 6)
                .background(Capsule().fill(.quaternary))
                .accessibilityIdentifier(AXID.Sidebar.crewBadge)
        case .debtWarning:
            HStack(spacing: 2) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Image(systemName: "exclamationmark").font(.caption.bold()).foregroundStyle(.red)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier(AXID.Sidebar.bankBadge)
        }
    }
}
