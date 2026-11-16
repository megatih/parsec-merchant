// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// Quests section (⌘8). PLACEHOLDER: the section owner fills this view per docs/specs/UI-SHELL.md.
/// Read `session.state` during render, act with `session.send(_:)`, and give every control an identifier under
/// the `quests.` scope (add constants to `AXID`).
struct QuestsSectionView: View {
    @Environment(GameSession.self) private var session

    var body: some View {
        ContentUnavailableView {
            Label { Text(Section.quests.title) } icon: { Image(systemName: Section.quests.systemImage) }
        } description: {
            Text("This section is being built.")
        }
        .accessibilityIdentifier(AXID.SectionRoot.root(.quests))
    }
}
