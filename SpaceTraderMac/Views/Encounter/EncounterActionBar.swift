// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// UI-ENC-027…033: one button per offered action (label plus key cap), then Resolve, Stop and the Auto-repeat toggle,
/// on the Liquid Glass action bar. The letter keys live in the Encounter menu; only the default action carries Return.
struct EncounterActionBar: View {
    @Environment(GameSession.self) private var session
    let model: EncounterActionBarModel

    var body: some View {
        // A11Y-025: the bar wraps at large Text Sizes instead of clipping.
        WrappingHStack(spacing: 10, lineSpacing: 8) {
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
            .accessibilityLabel(Text("Auto-repeat"))  // A11Y-003: no key cap in the label
            .accessibilityHint(Text(verbatim: model.autoRepeatHelp))  // A11Y-005
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
            // UI-PTR-014: the action name on a large button; the key is in the help tag.
            Text(verbatim: button.label).pointerTarget()
        }
        .disabled(!button.isEnabled)
        .help(Text(verbatim: button.help))
        .accessibilityLabel(Text(verbatim: button.label))
        .accessibilityHint(button.action == .resolve ? Text(AccessibilityHints.resolve) : Text(verbatim: ""))  // A11Y-005
        .accessibilityIdentifier(AXID.Encounter.action(button.action))
    }
}
