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
        case .sound, .intelligence: LaterSettingsView(tab: tab)
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

/// Advanced: Clear High Scores per ruleset (UI-SHELL-101). Reset Tips (M12) and Reset Achievements (M10) come later.
struct AdvancedSettingsView: View {
    @Environment(GameSession.self) private var session
    @State private var pendingClear: RulesetID?

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
            } footer: {
                Text("Reset Tips arrives in a later update, and Reset Achievements with achievements.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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

    private var content: ConfirmationContent? {
        pendingClear.map { AppConfirmationText.content(for: .clearHighScores($0), session: session) }
    }

    private var clearBinding: Binding<Bool> {
        Binding { pendingClear != nil } set: { if !$0 { pendingClear = nil } }
    }
}

/// Sound (M11) and Intelligence (M10): say which milestone brings them.
struct LaterSettingsView: View {
    let tab: SettingsTab

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: tab.systemImage).font(.largeTitle).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            switch tab {
            case .sound: Text("Sound settings arrive with the sound update (milestone 11).")
            case .intelligence: Text("Intelligence settings arrive with the trade intelligence update (milestone 10).")
            case .general, .advanced: EmptyView()
            }
        }
        .foregroundStyle(.secondary)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
