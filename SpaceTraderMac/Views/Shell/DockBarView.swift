// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// UI-NAV-002: the dock bar: one button per page, always all of them, at the top of the window. During transit and
/// encounters every button is disabled and says why (UI-NAV-005).
struct DockBarView: View {
    @Environment(GameSession.self) private var session
    @Environment(\.pmScale) private var scale

    var body: some View {
        let badges = SidebarBadges.make(state: session.state)
        let lock = SidebarLock.make(phase: session.state?.phase, transitPlaying: session.transitPlayback != nil)
        let context = session.sectionContext
        HStack(spacing: 2 * scale) {
            ForEach(Section.allCases) { section in
                let badge = badges.badge(for: section)
                PMDockButton(title: section.title, symbol: section.systemImage, key: section.keyCap, current: session.selectedSection == section,
                             badge: badge.map(Self.text), badgeLabel: badge?.accessibilityLabel, badgeIdentifier: badge.map(Self.identifier),
                             disabledReason: Self.reason(section: section, lock: lock, context: context), identifier: section.axID) {
                    session.selectedSection = section
                }
            }
            if let label = lock.label {
                // The reason in words, not only on the disabled buttons.
                Text(label)
                    .pmFont(.caption)
                    .foregroundStyle(PMColor.caution)
                    .fixedSize()
                    .probed(AXID.Dock.phaseLabel)
            }
        }
        .pmPadding(.horizontal, PMSpace.xs)
        .frame(maxWidth: .infinity, minHeight: 44 * scale)
        .background(PMColor.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(PMColor.hairline).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .probed(AXID.Dock.bar)
    }

    static func text(_ badge: SidebarBadges.Badge) -> String {
        switch badge {
        case .special: "★"
        case let .count(n): "\(n)"
        case .debtWarning: "!"
        }
    }

    static func identifier(_ badge: SidebarBadges.Badge) -> String {
        switch badge {
        case .special: AXID.Dock.bridgeBadge
        case .count: AXID.Dock.crewBadge
        case .debtWarning: AXID.Dock.bankBadge
        }
    }

    /// Why a page cannot be opened now; nil when it can.
    static func reason(section: Section, lock: SidebarLock, context: SectionContext) -> String? {
        switch lock {
        case .inTransit: return String(localized: "Unavailable in transit")
        case .inEncounter: return String(localized: "Unavailable during an encounter")
        case .none: break
        }
        return section.isAvailable(in: context) ? nil : String(localized: "Unavailable after the game has ended")
    }
}
