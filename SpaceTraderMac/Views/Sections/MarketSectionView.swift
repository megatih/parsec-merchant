// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// Market section (⌘2). PLACEHOLDER: the section owner fills this view per docs/specs/UI-SHELL.md.
/// Read `session.state` during render, act with `session.send(_:)`, and give every control an identifier under
/// the `market.` scope (add constants to `AXID`).
struct MarketSectionView: View {
    @Environment(GameSession.self) private var session

    var body: some View {
        ContentUnavailableView {
            Label { Text(Section.market.title) } icon: { Image(systemName: Section.market.systemImage) }
        } description: {
            Text("This section is being built.")
        }
        .accessibilityIdentifier(AXID.SectionRoot.root(.market))
    }
}
