// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

extension OptionsDraft.Field {
    /// The control's label (Form_Options.cs:156-337).
    var label: LocalizedStringResource {
        switch self {
        case .autoFuel: "Get full fuel tanks on arrival"
        case .autoRepair: "Get full hull repairs on arrival"
        case .newsAutoPay: "Always pay for newspaper"
        case .newsAutoShow: "Show newspaper on arrival"
        case .showTrackedRange: "Show range to tracked system"
        case .trackAutoOff: "Stop tracking on arrival"
        case .remindLoans: "Remind about loans"
        case .reserveMoney: "Reserve money for warp costs"
        case .leaveEmpty: "Cargo bays to leave empty when buying goods in-system"
        case .alwaysIgnorePirates: "Pirates"
        case .alwaysIgnorePolice: "Police"
        case .alwaysIgnoreTraders: "Traders"
        case .alwaysIgnoreTradeInOrbit: "Ignore dealing traders"
        case .continuousAttack: "Continuous attack and flight"
        case .continuousAttackFleeing: "Continue attacking fleeing ship"
        case .disableOpponents: "Attempt to disable opponents when possible"
        }
    }
}

extension OptionsDraft.Group {
    var title: LocalizedStringResource {
        switch self {
        case .arrival: "On Arrival"
        case .newspaper: "Newspaper"
        case .tracking: "Tracking"
        case .money: "Money"
        case .ignore: "Always ignore when it is safe"
        case .combat: "Combat"
        }
    }
}

/// Game › Options… (OPT-025…027, UI-SHELL-098): OK sends `setOptions`, Cancel discards.
struct GameOptionsSheet: View {
    @Environment(GameSession.self) private var session
    @State private var draft: OptionsDraft?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Options")
                .scaledFont(.title2, weight: .bold)
            if let draft {
                Form {
                    ForEach(OptionsDraft.Group.allCases, id: \.self) { group in
                        SwiftUI.Section {
                            ForEach(group.fields.filter(draft.isVisible), id: \.self) { field in
                                control(field, draft: draft)
                            }
                        } header: {
                            Text(group.title)
                        }
                    }
                }
                .formStyle(.grouped)
                .frame(minHeight: 420)
            }
            HStack {
                Button("Save as Defaults") { draft?.saveAsDefaults(session.defaults) }
                    .accessibilityIdentifier(AXID.Options.saveDefaults)
                Button("Load from Defaults") { draft?.loadDefaults(session.defaults) }
                    .accessibilityIdentifier(AXID.Options.loadDefaults)
                Spacer()
                Button("Cancel", role: .cancel) { session.dismissPresentation() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier(AXID.Options.cancel)
                Button("OK") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier(AXID.Options.ok)
            }
        }
        .padding(20)
        .frame(width: 520)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Options.sheet)
        .onAppear {
            if draft == nil, let state = session.state {
                draft = OptionsDraft(options: state.options, ruleset: state.rulesetID)
            }
        }
    }

    @ViewBuilder
    private func control(_ field: OptionsDraft.Field, draft: OptionsDraft) -> some View {
        if field == .leaveEmpty {
            Stepper(value: leaveEmptyBinding, in: OptionsDraft.leaveEmptyRange) {
                HStack {
                    Text(field.label)
                    Spacer()
                    Text(verbatim: draft.leaveEmpty.formatted()).monospacedDigit()
                }
            }
            .accessibilityLabel(Text(field.label))  // A11Y-003
            .accessibilityValue(Text(verbatim: draft.leaveEmpty.formatted()))
            .accessibilityIdentifier(AXID.Options.field(field))
        } else {
            Toggle(isOn: binding(field)) { Text(field.label) }.accessibilityLabel(Text(field.label))
                .disabled(!draft.isEnabled(field))
                .help(optionHelp(field, draft: draft))  // UI-KEYS-035: a dependent option names its parent
                .accessibilityIdentifier(AXID.Options.field(field))
        }
    }

    private func optionHelp(_ field: OptionsDraft.Field, draft: OptionsDraft) -> Text {
        guard !draft.isEnabled(field), let parent = field.parent else { return Text(verbatim: "") }
        return Text("Turn on “\(String(localized: parent.label))” first.")
    }

    private func binding(_ field: OptionsDraft.Field) -> Binding<Bool> {
        Binding { draft?.value(field) ?? false } set: { draft?.set(field, $0) }
    }

    private var leaveEmptyBinding: Binding<Int> {
        Binding { draft?.leaveEmpty ?? 0 } set: { draft?.setLeaveEmpty($0) }
    }

    private func commit() {
        guard let draft else { return }
        session.dismissPresentation()
        session.send(draft.commit())
    }
}
