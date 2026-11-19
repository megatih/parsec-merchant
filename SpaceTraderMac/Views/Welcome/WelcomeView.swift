// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecArt
import ParsecEngine
import ParsecPersistence
import SwiftUI

/// The Welcome view (UI-SHELL-017/018, UI-PG-070): the console palette, like the game it opens.
struct WelcomeView: View {
    @Environment(GameSession.self) private var session
    @State private var slots: [SlotInfo] = []
    @State private var selection: String?

    var body: some View {
        HStack(spacing: 0) {
            actions
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { WelcomeBackdrop() }
            Rectangle().fill(PMColor.hairline).frame(width: 1).accessibilityHidden(true)
            recentList
                .frame(width: 420)
                .background(PMColor.panel)
        }
        .foregroundStyle(PMColor.textPrimary)
        .environment(\.colorScheme, .dark)
        .background(PMColor.space)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Welcome.root)
        .onAppear(perform: reload)
        .onChange(of: session.presentation) { reload() }
    }

    private var actions: some View {
        VStack(spacing: PMSpace.m) {
            ArtAccessibilityReader { a11y in
                Wordmark(size: 34, increaseContrast: a11y.increaseContrast)
                    .artAccessibility(.wordmark)  // A11Y-006, A11Y-009
            }
            Text("Based on Space Trader by Pieter Spronck.")
                .pmFont(.body)
                .foregroundStyle(PMColor.textPrimary)
                .padding(.horizontal, PMSpace.s)
                .padding(.vertical, PMSpace.xs)
                .background(PMColor.panelInset, in: Capsule())  // A11Y-029: legible over the starfield
            VStack(spacing: PMSpace.xs) {
                Button("Quick Start") { session.requestQuickStart() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(PMButtonStyle(kind: .primary, fillsWidth: true))
                    .accessibilityIdentifier(AXID.Welcome.quickStart)
                if session.continueCandidate != nil {
                    Button("Continue") { session.continueGame() }
                        .accessibilityIdentifier(AXID.Welcome.continueGame)
                }
                Button("New Game…") { session.requestNewGame() }
                    .accessibilityIdentifier(AXID.Welcome.newGame)
                Button("Open Saved Game…") { session.present(.sheet(.openSavedGame)) }
                    .accessibilityIdentifier(AXID.Welcome.open)
                Button("Import…") { session.requestImport() }
                    .accessibilityIdentifier(AXID.Welcome.importSave)
            }
            .frame(width: 240)
            // UI-PTR-002: the component's 36 pt targets.
            .buttonStyle(PMButtonStyle(fillsWidth: true))
            .padding(.top, PMSpace.m)
        }
        .padding(PMSpace.xl)
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: PMSpace.s) {
            Text("Recent Games")
                .pmFont(.panelTitle)
                .foregroundStyle(PMColor.textSecondary)
                .accessibilityAddTraits(.isHeader)
                .padding([.top, .horizontal], PMSpace.l)
            if slots.isEmpty {
                Text("No saved games yet.")
                    .foregroundStyle(PMColor.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(slots, id: \.id, selection: $selection) { slot in
                    RecentSlotRow(slot: slot)
                        .listRowBackground(Color.clear)
                        .accessibilityIdentifier(AXID.Welcome.recent(slot.id))
                }
                .scrollContentBackground(.hidden)
                .contextMenu(forSelectionType: String.self) { _ in
                    EmptyView()
                } primaryAction: { ids in
                    if let id = ids.first { session.requestOpen(slotID: id) }
                }
            }
        }
    }

    private func reload() {
        slots = session.recentSlots()
    }
}

/// One recent save: commander, day, worth, system, ruleset, Ironman, cheat and ended marks (SAV-042).
struct RecentSlotRow: View {
    let slot: SlotInfo

    var body: some View {
        let s = slot.summary
        let system = Ruleset.named(slot.rulesetID).tables.systemNames
        let systemName = system.indices.contains(s.system) ? system[s.system] : ""
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: PMSpace.s) {
                Text(verbatim: s.commander).pmFont(.value).foregroundStyle(PMColor.textPrimary)
                if s.ironman { Text("Ironman").pmFont(.caption).foregroundStyle(PMColor.caution) }
                if s.cheatsUsed { Text("Cheats").pmFont(.caption).foregroundStyle(PMColor.textSecondary) }
                if s.ended { Text("Ended").pmFont(.caption).foregroundStyle(PMColor.textSecondary) }
                if slot.isAutosave { Text("Autosave").pmFont(.caption).foregroundStyle(PMColor.textSecondary) }
            }
            Text("Day \(s.day) · \(systemName) · Worth \(s.worth.formatted()) cr. · \(String(localized: Names.ruleset(slot.rulesetID)))")
                .pmFont(.caption)
                // A11Y-029: full contrast, also on the list's selection highlight.
                .foregroundStyle(PMColor.textPrimary)
                .monospacedDigit()
        }
        .padding(.vertical, PMSpace.xs)
    }
}
