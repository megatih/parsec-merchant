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
        .modifier(SceneAccessibility())
    }

    @ViewBuilder
    private func content(_ tab: SettingsTab) -> some View {
        switch tab {
        case .general: GeneralSettingsView()
        case .advanced: AdvancedSettingsView()
        case .intelligence: IntelligenceSettingsView()
        case .sound: SoundSettingsView()
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
            // A11Y-029: AppKit pop-ups (a SwiftUI Picker exposes no press action to VoiceOver on macOS 27).
            LabeledContent {
                PopUpMenuButton(title: "", items: TextSizeSetting.allCases.map { size in
                    PopUpMenuButton.Item(title: String(localized: size.title)) { textSize = size.rawValue }
                }, pullsDown: false, selectedIndex: TextSizeSetting.allCases.firstIndex { $0.rawValue == textSize } ?? 2,
                accessibilityLabel: String(localized: "Text Size"), identifier: AXID.Settings.textSize)
            } label: {
                Text("Text Size")
            }
            Toggle(isOn: $fastTravel) { Text("Fast travel") }.accessibilityLabel(Text("Fast travel"))
                .help(Text("Skip the transit animation."))
                .accessibilityIdentifier(AXID.Settings.fastTravel)
            LabeledContent {
                PopUpMenuButton(title: "", items: ArrivalReportStyle.allCases.map { style in
                    PopUpMenuButton.Item(title: String(localized: style.title)) { arrivalStyle = style.rawValue }
                }, pullsDown: false, selectedIndex: ArrivalReportStyle.allCases.firstIndex { $0.rawValue == arrivalStyle } ?? 0,
                accessibilityLabel: String(localized: "Arrival report"), identifier: AXID.Settings.arrivalReportStyle)
            } label: {
                Text("Arrival report")
            }
            Toggle(isOn: $tacticalReadout) { Text("Tactical readout in encounters") }.accessibilityLabel(Text("Tactical readout in encounters"))
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
                        .foregroundStyle(.readableSecondary)
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

/// Advanced: Clear High Scores per ruleset (UI-SHELL-101), Reset Achievements (ACH-021) and Reset Tips (A11Y-046).
struct AdvancedSettingsView: View {
    @Environment(GameSession.self) private var session
    @State private var pendingClear: RulesetID?
    @State private var pendingReset = false
    @State private var tipsResetRequested = false

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
            }
            SwiftUI.Section {
                // A11Y-046: not destructive, no confirmation; applied at the next launch, before TipKit is configured.
                LabeledContent {
                    Button("Reset Tips") {
                        TipTriggers.requestReset(defaults: session.defaults)
                        tipsResetRequested = true
                    }
                    .accessibilityIdentifier(AXID.Tips.resetTips)
                } label: {
                    Text("Tips")
                }
                if tipsResetRequested {
                    Text("Tips will appear again the next time you open Parsec Merchant.")
                        .accessibilityIdentifier(AXID.Tips.resetTipsStatus)
                }
            } header: {
                Text("Tips")
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
