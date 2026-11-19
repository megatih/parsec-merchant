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

/// Options (⌥⌘O, PRD §4.10): the per-game options as panels. A change applies at once through `.setOptions`; there is
/// no OK or Cancel. App-wide settings stay in the Settings window (⌘,).
struct OptionsPage: View {
    @Environment(GameSession.self) private var session
    @Environment(\.pmScale) private var scale

    var body: some View {
        GamePage(section: .options) {
            PMButton(title: "Save as Defaults", help: "Use these options for new games", identifier: AXID.Options.saveDefaults) {
                draft?.saveAsDefaults(session.defaults)
            }
            .fixedSize()
            PMButton(title: "Load Defaults", help: "Replace these options with your saved defaults", identifier: AXID.Options.loadDefaults) {
                guard var d = draft else { return }
                d.loadDefaults(session.defaults)
                session.send(d.commit())
            }
            .fixedSize()
        } content: {
            if let draft {
                PMFitScroll {
                    // Two columns of panels: the six groups in the C# dialog's order (OPT-025).
                    let groups = OptionsDraft.Group.allCases
                    HStack(alignment: .top, spacing: PMSpace.s * scale) {
                        VStack(spacing: PMSpace.s * scale) { ForEach(groups.prefix(3), id: \.self) { panel($0, draft: draft) } }
                        VStack(spacing: PMSpace.s * scale) { ForEach(groups.suffix(3), id: \.self) { panel($0, draft: draft) } }
                    }
                }
            }
        }
    }

    /// The options of the running game, normalized for its ruleset (UI-PG-050).
    private var draft: OptionsDraft? {
        session.state.map { OptionsDraft(options: $0.options, ruleset: $0.rulesetID) }
    }

    private func panel(_ group: OptionsDraft.Group, draft: OptionsDraft) -> some View {
        PMPanel(group.title, identifier: "options.group.\(group)") {
            // OPT-009: an option the ruleset does not have is not shown.
            ForEach(group.fields.filter(draft.isVisible), id: \.self) { field in control(field, draft: draft) }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func control(_ field: OptionsDraft.Field, draft: OptionsDraft) -> some View {
        if field == .leaveEmpty {
            Stepper(value: Binding { draft.leaveEmpty } set: { n in apply { $0.setLeaveEmpty(n) } }, in: OptionsDraft.leaveEmptyRange) {
                HStack {
                    Text(field.label)
                    Spacer()
                    Text(verbatim: draft.leaveEmpty.formatted()).monospacedDigit()
                }
            }
            .pmFont(.body)
            .foregroundStyle(PMColor.textPrimary)
            .accessibilityLabel(Text(field.label))  // A11Y-003
            .accessibilityValue(Text(verbatim: draft.leaveEmpty.formatted()))
            .accessibilityIdentifier(AXID.Options.field(field))
        } else {
            Toggle(isOn: Binding { draft.value(field) } set: { on in apply { $0.set(field, on) } }) { Text(field.label) }
                .toggleStyle(.switch)
                .pmFont(.body)
                .foregroundStyle(PMColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(Text(field.label))
                .disabled(!draft.isEnabled(field))
                .help(optionHelp(field, draft: draft))  // UI-KEYS-035: a dependent option names its parent
                .accessibilityIdentifier(AXID.Options.field(field))
        }
    }

    private func optionHelp(_ field: OptionsDraft.Field, draft: OptionsDraft) -> Text {
        guard !draft.isEnabled(field), let parent = field.parent else { return Text(field.label) }
        return Text("Turn on “\(String(localized: parent.label))” first.")
    }

    /// Changes the options and sends them at once.
    private func apply(_ change: (inout OptionsDraft) -> Void) {
        guard var d = draft else { return }
        change(&d)
        session.send(d.commit())
    }
}
