// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// UI-ENC-027…033: one button per offered action (label plus key cap), then Resolve, Stop and the Auto-repeat toggle,
/// on the Liquid Glass action bar. The letter keys live in the Encounter menu; only the default action carries Return.
struct EncounterActionBar: View {
    @Environment(GameSession.self) private var session
    let model: EncounterActionBarModel

    var body: some View {
        HStack(spacing: 10) {
            ForEach(model.buttons, id: \.action) { button in
                ActionButton(button: button) { session.performEncounterAction(button.action) }
            }
            if let resolve = model.resolve {
                Divider().frame(height: 22)
                ActionButton(button: resolve) { session.performEncounterAction(.resolve) }
            }
            ActionButton(button: model.stop) { session.stopEncounter() }
            Toggle(isOn: Binding { session.encounterUI.autoRepeatEnabled } set: { session.setAutoRepeat($0) }) {
                Text("Auto-repeat ⌥A")
            }
            .toggleStyle(.checkbox)
            .disabled(!model.autoRepeatAvailable)
            .help(Text(verbatim: model.autoRepeatHelp))
            .accessibilityIdentifier(AXID.Encounter.autoRepeat)
        }
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Encounter.actions)
    }
}

private struct ActionButton: View {
    let button: EncounterActionBarModel.Button
    let action: () -> Void

    var body: some View {
        if button.isDefault {
            base.keyboardShortcut(.defaultAction)
        } else {
            base
        }
    }

    private var base: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(verbatim: button.label)
                if let cap = button.keyCap {
                    Text(verbatim: cap)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(!button.isEnabled)
        .help(Text(verbatim: button.help))
        .accessibilityLabel(Text(verbatim: button.label))
        .accessibilityIdentifier(AXID.Encounter.action(button.action))
    }
}
