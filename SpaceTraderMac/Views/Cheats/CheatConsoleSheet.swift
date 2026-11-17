// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// The cheat console (CHEAT-013, UI-SHELL-105): states that the save is flagged and offers every code of the ruleset's
/// set as a labelled form. Classic "Cheater!" and plain-text readouts become console content.
struct CheatConsoleSheet: View {
    @Environment(GameSession.self) private var session
    @State private var form: CheatForm?
    @State private var lastFeedID: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Cheat Console").scaledFont(.title2, weight: .bold).accessibilityAddTraits(.isHeader)
            Label {
                Text("Cheats are on. This game is flagged and stays off the high-score table.")
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .foregroundStyle(.signalOrange)
            .accessibilityIdentifier(AXID.CheatConsole.flaggedNotice)
            if let state = session.state, form != nil {
                Form {
                    Picker(selection: codeBinding(state)) {
                        ForEach(CheatForm.codes(for: state.ruleset.content.cheatSet), id: \.self) { code in
                            Text(verbatim: code.rawValue).tag(code)
                        }
                    } label: {
                        Text("Code")
                    }
                    .accessibilityIdentifier(AXID.CheatConsole.code)
                    fields(state)
                }
                .formStyle(.grouped)
            }
            readout
            HStack {
                Spacer()
                Button("Close", role: .cancel) { session.dismissPresentation() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier(AXID.CheatConsole.close)
                Button("Run") { run() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(session.state?.phase != .docked)
                    .help(session.state?.phase == .docked ? Text(verbatim: "") : Text("Cheats run only while docked."))  // UI-KEYS-035
                    .accessibilityIdentifier(AXID.CheatConsole.run)
            }
        }
        .padding(20)
        .frame(width: 520)
        .frame(minHeight: 420)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.CheatConsole.sheet)
        .onAppear {
            guard form == nil, let state = session.state, let first = CheatForm.codes(for: state.ruleset.content.cheatSet).first else { return }
            form = CheatForm.prefilled(first, state: state)
            lastFeedID = session.feed.last?.id
        }
    }

    private func codeBinding(_ state: GameState) -> Binding<CheatForm.Code> {
        Binding { form?.code ?? .scratch } set: { form = CheatForm.prefilled($0, state: state) }
    }

    @ViewBuilder
    private func fields(_ state: GameState) -> some View {
        switch form?.code.shape ?? .none {
        case .none:
            EmptyView()
        case .number:
            numberField("Value", \.number, id: "number")
        case .twoNumbers:
            numberField(form?.code == .swag ? "Item (0–9)" : "Slot", \.number, id: "number")
            numberField(secondLabel, \.second, id: "second")
        case .kill:
            Picker(selection: binding(\.kill)) {
                ForEach(KillKind.allCases, id: \.self) { Text(verbatim: $0.rawValue.capitalized).tag($0) }
            } label: { Text("Kills of") }
                .accessibilityIdentifier(AXID.CheatConsole.field("kill"))
            numberField("Count", \.number, id: "number")
        case .quest:
            Picker(selection: binding(\.quest)) {
                ForEach(QuestKey.allCases, id: \.self) { Text(verbatim: $0.codeWord).tag($0) }
            } label: { Text("Quest") }
                .accessibilityIdentifier(AXID.CheatConsole.field("quest"))
            numberField("Status", \.number, id: "number")
        case .knack:
            numberField("Mercenary", \.number, id: "number")
            ForEach(SkillType.allCases, id: \.self) { skill in
                Stepper(value: skillBinding(skill.rawValue), in: 1...10) {
                    Text("\(String(localized: Names.skill(skill))): \(form?.skills[skill.rawValue] ?? 1)")
                }
                .accessibilityIdentifier(AXID.CheatConsole.field("skills"))
            }
        case .text:
            TextField(text: binding(\.text)) { Text("System name") }
                .accessibilityIdentifier(AXID.CheatConsole.field("text"))
        case .palmForm:
            PalmCheatFields(palm: binding(\.palm))
        }
    }

    private var secondLabel: LocalizedStringResource {
        switch form?.code {
        case .cover: "Shield type"
        case .iron: "Weapon type"
        case .tool: "Gadget type"
        case .posse: "Mercenary"
        default: "Quantity"
        }
    }

    private func numberField(_ label: LocalizedStringResource, _ kp: WritableKeyPath<CheatForm, Int>, id: String) -> some View {
        TextField(value: binding(kp), format: .number) { Text(label) }
            .accessibilityIdentifier(AXID.CheatConsole.field(id))
    }

    private func binding<T>(_ kp: WritableKeyPath<CheatForm, T>) -> Binding<T> {
        Binding {
            guard let form else { return CheatForm(code: .scratch)[keyPath: kp] }
            return form[keyPath: kp]
        } set: { form?[keyPath: kp] = $0 }
    }

    private func skillBinding(_ i: Int) -> Binding<Int> {
        Binding { form?.skills[i] ?? 1 } set: { form?.skills[i] = $0 }
    }

    /// Readouts and results of the codes run in this console (from the feed).
    private var readout: some View {
        let items = session.feed.filter { item in lastFeedID.map { item.id > $0 } ?? true }
        return ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if let state = session.state {
                    ForEach(items) { item in
                        if let event = item.event, event != .cheatUsed {
                            Text(EventText.text(for: event, state: state)).scaledFont(.callout)
                        }
                    }
                }
                if let reason = session.lastRejection {
                    Text(verbatim: ReasonText.string(for: reason)).scaledFont(.callout).foregroundStyle(.signalRed)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 90)
        .accessibilityIdentifier(AXID.CheatConsole.readout)
    }

    private func run() {
        guard let form else { return }
        session.send(.cheat(form.cheatCode()))
        if let state = session.state { self.form = CheatForm.prefilled(form.code, state: state) }
    }
}

/// The Palm Cheat form (CHEAT-042/043).
private struct PalmCheatFields: View {
    @Binding var palm: PalmCheatForm

    var body: some View {
        optionalNumber("Credits", \.credits, id: "credits")
        optionalNumber("Debt", \.debt, id: "debt")
        optionalNumber("Reputation", \.reputation, id: "reputation")
        optionalNumber("Police record", \.policeRecordMagnitude, id: "policeRecord")
        toggle("Police record is negative", \.policeRecordNegative, id: "policeNegative")
        toggle("Moon bought", \.moon, id: "moon")
        toggle("Lightning shield", \.lightningShield, id: "lightningShield")
        toggle("Fuel compactor", \.fuelCompactor, id: "fuelCompactor")
        toggle("Morgan's laser", \.morgansLaser, id: "morgansLaser")
        toggle("Singularity", \.singularity, id: "singularity")
    }

    private func optionalNumber(_ label: LocalizedStringResource, _ kp: WritableKeyPath<PalmCheatForm, Int?>, id: String) -> some View {
        TextField(value: Binding { palm[keyPath: kp] } set: { palm[keyPath: kp] = $0 }, format: .number) { Text(label) }
            .accessibilityIdentifier(AXID.CheatConsole.field(id))
    }

    private func toggle(_ label: LocalizedStringResource, _ kp: WritableKeyPath<PalmCheatForm, Bool>, id: String) -> some View {
        Toggle(isOn: Binding { palm[keyPath: kp] } set: { palm[keyPath: kp] = $0 }) { Text(label) }
            .accessibilityIdentifier(AXID.CheatConsole.field(id))
    }
}
