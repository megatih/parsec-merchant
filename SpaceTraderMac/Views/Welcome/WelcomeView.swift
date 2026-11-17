// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecArt
import ParsecEngine
import ParsecPersistence
import SwiftUI

/// The Welcome view (UI-SHELL-017/018): no sidebar, toolbar or inspector.
struct WelcomeView: View {
    @Environment(GameSession.self) private var session
    @State private var slots: [SlotInfo] = []
    @State private var selection: String?

    var body: some View {
        HStack(spacing: 0) {
            actions
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { WelcomeBackdrop() }
                .environment(\.colorScheme, .dark)
            Divider()
            recentList
                .frame(width: 420)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Welcome.root)
        .onAppear(perform: reload)
        .onChange(of: session.presentation) { reload() }
    }

    private var actions: some View {
        VStack(spacing: 14) {
            ArtAccessibilityReader { a11y in
                Wordmark(size: 34, increaseContrast: a11y.increaseContrast)
                    .artAccessibility(.wordmark)  // A11Y-006, A11Y-009
            }
            Text("Based on Space Trader by Pieter Spronck.")
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.black.opacity(0.45), in: Capsule())  // A11Y-029: legible over the starfield
            VStack(spacing: 8) {
                Button("Quick Start") { session.requestQuickStart() }
                    .keyboardShortcut(.defaultAction)
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
            .controlSize(.large)
            .frame(width: 240)
            .buttonStyle(.bordered)
            .padding(.top, 12)
        }
        .padding(40)
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Games")
                .scaledFont(.headline)
                .padding([.top, .horizontal])
            if slots.isEmpty {
                Text("No saved games yet.")
                    .foregroundStyle(.readableSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(slots, id: \.id, selection: $selection) { slot in
                    RecentSlotRow(slot: slot)
                        .accessibilityIdentifier(AXID.Welcome.recent(slot.id))
                }
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
            HStack(spacing: 6) {
                Text(verbatim: s.commander).scaledFont(.body, weight: .bold)
                if s.ironman { Text("Ironman").scaledFont(.caption).foregroundStyle(.signalOrange) }
                if s.cheatsUsed { Text("Cheats").scaledFont(.caption).foregroundStyle(.readableSecondary) }
                if s.ended { Text("Ended").scaledFont(.caption).foregroundStyle(.readableSecondary) }
                if slot.isAutosave { Text("Autosave").scaledFont(.caption).foregroundStyle(.readableSecondary) }
            }
            Text("Day \(s.day) · \(systemName) · Worth \(s.worth.formatted()) cr. · \(String(localized: Names.ruleset(slot.rulesetID)))")
                .scaledFont(.caption)
                .foregroundStyle(.readableSecondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}
