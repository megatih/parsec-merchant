// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// The Find System sheet (UI-SHELL-085): search field with live suggestions, "Track this system", Select.
struct FindSystemSheet: View {
    @Environment(GameSession.self) private var session
    @State private var text = ""
    @State private var noMatch = false
    @State private var ironmanRefusal = false

    var body: some View {
        @Bindable var session = session
        VStack(alignment: .leading, spacing: 12) {
            Text("Find System").pmFont(.title).accessibilityAddTraits(.isHeader)
            TextField("System name", text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(select)
                .onChange(of: text) {
                    noMatch = false
                    ironmanRefusal = false
                }
                .accessibilityLabel(Text("System name"))  // A11Y-003
                .accessibilityIdentifier(AXID.FindSystem.field)
            if let state = session.state {
                let matches = FindSystemModel.matches(text, in: state)
                if !matches.isEmpty {
                    List(matches, id: \.self) { system in
                        Button {
                            pick(system)
                        } label: {
                            Text(verbatim: Names.system(system, in: state)).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(AXID.FindSystem.result(system))
                    }
                    .frame(height: 160)
                }
            }
            if noMatch {
                Text("No system found.").foregroundStyle(PMColor.loss)
            }
            if ironmanRefusal {
                Text("Loading a save isn't possible in an Ironman game.").foregroundStyle(PMColor.loss)
            }
            Toggle("Track this system", isOn: $session.findTrackSystem)
                .accessibilityIdentifier(AXID.FindSystem.track)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { session.dismissPresentation() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier(AXID.FindSystem.cancel)
                Button("Select", action: select)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(PMButtonStyle(kind: .primary))
                    .disabled(text.isEmpty)
                    .help(text.isEmpty ? Text("Type the name of a system.") : Text(verbatim: ""))  // UI-KEYS-035
                    .accessibilityIdentifier(AXID.FindSystem.select)
            }
        }
        .padding(PMSpace.xl)
        .frame(width: 400)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.FindSystem.sheet)
    }

    /// A suggestion was clicked: select exactly that system.
    private func pick(_ system: Int) {
        perform(.select(system: system, track: session.findTrackSystem))
    }

    private func select() {
        guard let state = session.state else { return }
        perform(FindSystemModel.resolve(text, track: session.findTrackSystem, state: state))
    }

    private func perform(_ outcome: FindSystemModel.Outcome) {
        guard !session.performFind(outcome) else { return }
        if outcome == .noMatch { noMatch = true }
        if outcome == .timewarp { ironmanRefusal = true }
    }
}
