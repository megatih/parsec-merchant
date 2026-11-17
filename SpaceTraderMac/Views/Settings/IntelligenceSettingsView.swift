// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// Settings › Intelligence (OPT-028): trade recommendations (INT-038) and log flavor (LLM-025…027). No setting reaches
/// the engine or a save.
struct IntelligenceSettingsView: View {
    @Environment(GameSession.self) private var session
    @AppStorage(AppSettingsKey.showRecommendations) private var showRecommendations = true
    @AppStorage(AppSettingsKey.useFoundationModels) private var useFoundationModels = false
    @AppStorage(AppSettingsKey.showFlavor) private var showFlavor = true
    @State private var availability = FlavorAvailability.unsupportedBuild

    var body: some View {
        let model = FlavorSettingsModel.make(launch: session.launchOptions, availability: availability)
        Form {
            SwiftUI.Section {
                Toggle(isOn: $showRecommendations) { Text("Show trade recommendations") }.accessibilityLabel(Text("Show trade recommendations"))
                    .help(Text("Show the best buys and destinations above the Market table."))
                    .accessibilityIdentifier(AXID.IntelSettings.recommendations)
            } header: {
                Text("Trade Intelligence")
            }
            SwiftUI.Section {
                Toggle(isOn: $useFoundationModels) { Text("Write log entries with Apple Intelligence") }
                    .accessibilityLabel(Text("Write log entries with Apple Intelligence"))
                    .disabled(!model.toggleEnabled)
                    .accessibilityIdentifier(AXID.IntelSettings.foundationModels)
                Text(verbatim: model.status)
                    .scaledFont(.caption)
                    .foregroundStyle(.readableSecondary)
                    .accessibilityIdentifier(AXID.IntelSettings.flavorStatus)
                Toggle(isOn: $showFlavor) { Text("Show flavor text in the Captain's Log") }.accessibilityLabel(Text("Show flavor text in the Captain's Log"))
                    .accessibilityIdentifier(AXID.IntelSettings.showFlavor)
            } header: {
                Text("Captain's Log")
            } footer: {
                Text("Apple Intelligence runs on this Mac only. Flavor text never changes the game.")
                    .foregroundStyle(.readableSecondary)
                    .lineSpacing(3)  // A11Y-029: wrapped lines with room between them
            }
        }
        .formStyle(.grouped)
        .labeledContentStyle(ReadableLabeledContentStyle())  // A11Y-029: values at full contrast
        .onAppear {
            // LLM-024: no availability check runs when templates are forced.
            if !session.launchOptions.flavorTemplate { availability = FlavorAvailability.current }
        }
        .onChange(of: useFoundationModels) { _, on in session.flavorSettingChanged(useFoundationModels: on) }
    }
}
