// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// AUD-042: Settings › Sound. Every control writes its `UserDefaults` key; `AudioService` applies changes live.
struct SoundSettingsView: View {
    @Environment(GameSession.self) private var session
    @AppStorage(SoundSettingsKey.muted) private var muted = SoundSettings.standard.muted
    @AppStorage(SoundSettingsKey.overall) private var overall = SoundSettings.standard.overall
    @AppStorage(SoundSettingsKey.effects) private var effects = SoundSettings.standard.effects
    @AppStorage(SoundSettingsKey.musicEnabled) private var musicEnabled = SoundSettings.standard.musicEnabled
    @AppStorage(SoundSettingsKey.music) private var music = SoundSettings.standard.music
    @AppStorage(SoundSettingsKey.muteWhenInactive) private var muteWhenInactive = SoundSettings.standard.muteWhenInactive
    @AppStorage(SoundSettingsKey.hapticsEnabled) private var haptics = SoundSettings.standard.hapticsEnabled
    @State private var previewing = false

    private var status: AudioStatus { session.audio.status }
    private var offForLaunch: Bool { SoundSettingsModel.controlsDisabled(status: status) }

    var body: some View {
        Form {
            SwiftUI.Section {
                Toggle(isOn: $muted) { Text("Mute") }.accessibilityLabel(Text("Mute"))
                    .accessibilityIdentifier(AXID.Sound.mute)
                    .disabled(offForLaunch)
                volume(Text("Master volume"), value: $overall, id: AXID.Sound.overall)
                    .disabled(muted || offForLaunch)
                volume(Text("Effects volume"), value: $effects, id: AXID.Sound.effects)
                    .disabled(muted || offForLaunch)
            }
            SwiftUI.Section {
                Toggle(isOn: $musicEnabled) { Text("Ambient music") }.accessibilityLabel(Text("Ambient music"))
                    .accessibilityIdentifier(AXID.Sound.musicEnabled)
                    .disabled(offForLaunch)
                volume(Text("Music volume"), value: $music, id: AXID.Sound.music)
                    .disabled(muted || !musicEnabled || offForLaunch)
            } footer: {
                Text("Off by default").foregroundStyle(.readableSecondary)
            }
            SwiftUI.Section {
                Toggle(isOn: $muteWhenInactive) { Text("Mute when inactive") }.accessibilityLabel(Text("Mute when inactive"))
                    .accessibilityIdentifier(AXID.Sound.muteWhenInactive)
                    .disabled(offForLaunch)
                Toggle(isOn: $haptics) { Text("Haptics") }.accessibilityLabel(Text("Haptics"))
                    .accessibilityIdentifier(AXID.Sound.haptics)
                    .disabled(offForLaunch)
            } footer: {
                Text("Haptics work only on Force Touch trackpads.").foregroundStyle(.readableSecondary)
            }
            SwiftUI.Section {
                LabeledContent {
                    Button {
                        session.playTestSound()
                        previewing = true
                        Task {
                            try? await Task.sleep(for: .milliseconds(500))
                            previewing = false
                        }
                    } label: {
                        Label { Text("Play Test Sound") } icon: {
                            Image(systemName: previewing ? "speaker.wave.3.fill" : "speaker.wave.2")
                        }
                    }
                    .accessibilityIdentifier(AXID.Sound.preview)
                    .disabled(offForLaunch)
                } label: {
                    Text("Status: \(String(localized: status.title))")
                        .accessibilityIdentifier(AXID.Sound.status)
                }
            }
        }
        .formStyle(.grouped)
        // A11Y-029: only the controls are disabled when audio is off for this launch; the explanatory text keeps
        // full contrast (a disabled Form dims its text).
    }

    private func volume(_ title: Text, value: Binding<Double>, id: String) -> some View {
        LabeledContent {
            HStack {
                Slider(value: value, in: 0...1)
                    .frame(minWidth: 160)
                    .accessibilityLabel(title)
                    .accessibilityValue(Text(SoundSettingsModel.percent(value.wrappedValue)))
                    .accessibilityIdentifier(id)
                Text(SoundSettingsModel.percent(value.wrappedValue))
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
        } label: {
            title
        }
    }
}

/// AUD-042: the Sound tab's display logic.
enum SoundSettingsModel {
    /// "80%" for 0.8.
    static func percent(_ value: Double) -> String {
        (min(max(value, 0), 1)).formatted(.percent.precision(.fractionLength(0)))
    }

    /// Under `-PMAudio off` the controls are shown but disabled.
    static func controlsDisabled(status: AudioStatus) -> Bool {
        status == .offForLaunch
    }
}
