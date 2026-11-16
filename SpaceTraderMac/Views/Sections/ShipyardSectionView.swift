// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// Shipyard section (⌘3). PLACEHOLDER: the section owner fills this view per docs/specs/UI-SHELL.md.
/// Read `session.state` during render, act with `session.send(_:)`, and give every control an identifier under
/// the `shipyard.` scope (add constants to `AXID`).
struct ShipyardSectionView: View {
    @Environment(GameSession.self) private var session

    var body: some View {
        ContentUnavailableView {
            Label { Text(Section.shipyard.title) } icon: { Image(systemName: Section.shipyard.systemImage) }
        } description: {
            Text("This section is being built.")
        }
        .accessibilityIdentifier(AXID.SectionRoot.root(.shipyard))
    }
}
