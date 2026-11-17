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
                    .scaledFont(.caption, weight: .bold)
                    .foregroundStyle(.readableSecondary)
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
            // A11Y-029: the icon is its own (hidden) image, so the title is measured on its own for contrast.
            Image(systemName: section.systemImage).foregroundStyle(.tint).frame(width: 20).accessibilityHidden(true)
            Text(section.title)
            Spacer()
            if let badge {
                badgeView(badge)
                    .accessibilityLabel(Text(badge.accessibilityLabel))
            }
            Text(verbatim: "⌘\(section.shortcutDigit)")
                .scaledFont(.caption)
                .foregroundStyle(.readableSecondary)
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
                .scaledFont(.caption, weight: .bold)
                .padding(.horizontal, 6)
                .background(Capsule().fill(.quaternary))
                .accessibilityIdentifier(AXID.Sidebar.crewBadge)
        case .debtWarning:
            HStack(spacing: 2) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Image(systemName: "exclamationmark").scaledFont(.caption, weight: .bold).foregroundStyle(.signalRed)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: AccessibilityText.bankDebtBadge))  // A11Y-004
            .accessibilityIdentifier(AXID.Sidebar.bankBadge)
        }
    }
}
