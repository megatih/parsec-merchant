// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import ParsecEngine
import SwiftUI

/// Settings (⌘,): the tabs of OPT-028 (UI-SHELL-100, -101, -104).
struct SettingsView: View {
    var body: some View {
        TabView {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                Tab {
                    content(tab)
                        .frame(width: 520)
                        .frame(minHeight: 260)
                } label: {
                    Label { Text(tab.title) } icon: { Image(systemName: tab.systemImage) }
                }
                .accessibilityIdentifier(AXID.Settings.tab(tab))
            }
        }
        .modifier(AppTextSize())
    }

    @ViewBuilder
    private func content(_ tab: SettingsTab) -> some View {
        switch tab {
        case .general: GeneralSettingsView()
        case .advanced: AdvancedSettingsView()
        case .intelligence: IntelligenceSettingsView()
        case .sound: LaterSettingsView(tab: tab)
        }
    }
}

/// General: Text Size, Fast travel, arrival report style, tactical readout and the galaxy code.
struct GeneralSettingsView: View {
    @Environment(GameSession.self) private var session
    @AppStorage(AppSettingsKey.textSize) private var textSize = TextSizeSetting.standard.rawValue
    @AppStorage(AppSettingsKey.fastTravel) private var fastTravel = false
    @AppStorage(AppSettingsKey.arrivalReportStyle) private var arrivalStyle = ArrivalReportStyle.card.rawValue
    @AppStorage(AppSettingsKey.tacticalReadout) private var tacticalReadout = true

    var body: some View {
        Form {
            Picker(selection: $textSize) {
                ForEach(TextSizeSetting.allCases, id: \.self) { size in
                    Text(size.title).tag(size.rawValue)
                }
            } label: {
                Text("Text Size")
            }
            .accessibilityIdentifier(AXID.Settings.textSize)
            Toggle(isOn: $fastTravel) { Text("Fast travel") }
                .help(Text("Skip the transit animation."))
                .accessibilityIdentifier(AXID.Settings.fastTravel)
            Picker(selection: $arrivalStyle) {
                ForEach(ArrivalReportStyle.allCases, id: \.self) { style in
                    Text(style.title).tag(style.rawValue)
                }
            } label: {
                Text("Arrival report")
            }
            .accessibilityIdentifier(AXID.Settings.arrivalReportStyle)
            Toggle(isOn: $tacticalReadout) { Text("Tactical readout in encounters") }
                .accessibilityIdentifier(AXID.Settings.tacticalReadout)
            LabeledContent {
                if let code = SettingsGalaxyCode.text(state: session.state) {
                    HStack {
                        Text(verbatim: code).monospaced().textSelection(.enabled)
                            .accessibilityIdentifier(AXID.Settings.galaxyCode)
                        Button("Copy") { SettingsGalaxyCode.copy(code) }
                            .accessibilityIdentifier(AXID.Settings.galaxyCodeCopy)
                    }
                } else {
                    Text("No game loaded")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(AXID.Settings.galaxyCode)
                }
            } label: {
                Text("Galaxy code")
            }
        }
        .formStyle(.grouped)
    }
}

/// UI-SHELL-104: the galaxy code of the loaded game.
enum SettingsGalaxyCode {
    static func text(state: GameState?) -> String? {
        state.map { GalaxyCode($0).string }
    }

    static func copy(_ code: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)
    }
}

/// Advanced: Clear High Scores per ruleset (UI-SHELL-101) and Reset Achievements (ACH-021). Reset Tips is M12.
struct AdvancedSettingsView: View {
    @Environment(GameSession.self) private var session
    @State private var pendingClear: RulesetID?
    @State private var pendingReset = false

    var body: some View {
        Form {
            SwiftUI.Section {
                ForEach(RulesetID.allCases, id: \.self) { r in
                    LabeledContent {
                        Button("Clear…", role: .destructive) { pendingClear = r }
                            .accessibilityIdentifier(AXID.Settings.clearHighScores(r))
                    } label: {
                        Text("\(String(localized: Names.ruleset(r))) high scores")
                    }
                }
            } header: {
                Text("High Scores")
            }
            SwiftUI.Section {
                LabeledContent {
                    Button("Reset Achievements…", role: .destructive) { pendingReset = true }
                        .accessibilityIdentifier(AXID.IntelSettings.resetAchievements)
                } label: {
                    Text("Achievements")
                }
            } header: {
                Text("Achievements")
            } footer: {
                Text("Reset Tips arrives in a later update.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(Text(verbatim: resetContent.title), isPresented: $pendingReset, titleVisibility: .visible) {
            Button(resetContent.confirmLabel, role: .destructive) { session.confirm(.resetAchievements) }
                .accessibilityIdentifier(AXID.Dialog.appConfirmationConfirm)
            Button("Cancel", role: .cancel) { pendingReset = false }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier(AXID.Dialog.appConfirmationCancel)
        } message: {
            Text(verbatim: resetContent.message)
        }
        .confirmationDialog(Text(verbatim: content?.title ?? ""), isPresented: clearBinding, titleVisibility: .visible) {
            Button(content?.confirmLabel ?? "", role: .destructive) {
                if let r = pendingClear { session.clearHighScores(r) }
                pendingClear = nil
            }
            .accessibilityIdentifier(AXID.Dialog.appConfirmationConfirm)
            Button("Cancel", role: .cancel) { pendingClear = nil }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier(AXID.Dialog.appConfirmationCancel)
        } message: {
            Text(verbatim: content?.message ?? "")
        }
    }

    private var resetContent: ConfirmationContent {
        AppConfirmationText.content(for: .resetAchievements, session: session)
    }

    private var content: ConfirmationContent? {
        pendingClear.map { AppConfirmationText.content(for: .clearHighScores($0), session: session) }
    }

    private var clearBinding: Binding<Bool> {
        Binding { pendingClear != nil } set: { if !$0 { pendingClear = nil } }
    }
}

/// Sound (M11): says which milestone brings it.
struct LaterSettingsView: View {
    let tab: SettingsTab

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: tab.systemImage).font(.largeTitle).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            switch tab {
            case .sound: Text("Sound settings arrive with the sound update (milestone 11).")
            case .general, .advanced, .intelligence: EmptyView()
            }
        }
        .foregroundStyle(.secondary)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
