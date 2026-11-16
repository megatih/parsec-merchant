// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// The toolbar: target picker, Warp and the inspector toggle; controls only, no status text (UI-SHELL-040/041).
struct ShellToolbar: ToolbarContent {
    let session: GameSession
    @Binding var inspectorVisible: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            TargetPicker()
        }
        ToolbarItem(placement: .primaryAction) {
            let model = WarpButtonModel.make(state: session.state, isModal: session.isModal)
            Button {
                session.send(.warp)
            } label: {
                Label("Warp", systemImage: "arrow.up.forward.circle")
            }
            .disabled(!model.isEnabled)
            .help(model.help)
            .accessibilityIdentifier(AXID.Toolbar.warp)
        }
        .visibilityPriority(.high)
        ToolbarItem(placement: .primaryAction) {
            Button {
                inspectorVisible.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }
            .help(Text("Show or hide the ship status."))
            .accessibilityIdentifier(AXID.Toolbar.inspector)
        }
    }
}

/// Warp's enablement and help tag: the cost breakdown, or the blocking reason.
struct WarpButtonModel: Equatable {
    var isEnabled: Bool
    var help: String

    /// Enablement comes from `MenuRules.warp` (MENU-004/030), shared with Game › Warp and the Bridge.
    static func make(state: GameState?, isModal: Bool) -> WarpButtonModel {
        let availability = MenuRules.warp(MenuContext.make(state: state, isModal: isModal))
        guard availability.isEnabled, let state else {
            return WarpButtonModel(isEnabled: false, help: availability.reason?.text ?? DisabledReason.notDocked.text)
        }
        let c = state.warpTargetPreview(state.warpSystem).costs
        let help = String(localized: """
            Mercenaries \(c.mercenaries.formatted()) cr., insurance \(c.insurance.formatted()) cr., \
            interest \(c.interest.formatted()) cr., wormhole tax \(c.wormholeTax.formatted()) cr. Total \(c.total.formatted()) cr.
            """)
        return WarpButtonModel(isEnabled: true, help: help)
    }
}

/// The target picker: destinations by distance, the wormhole, and Find System… (UI-SHELL-041).
struct TargetPicker: View {
    @Environment(GameSession.self) private var session

    var body: some View {
        if let state = session.state {
            let cur = state.commander.currentSystem
            Menu {
                ForEach(TargetPickerModel.entries(state: state), id: \.index) { d in
                    Button {
                        session.send(.selectTarget(d.index))
                    } label: {
                        Text("\(d.name) · \(d.distance) parsecs")
                    }
                }
                if let w = TargetPickerModel.wormhole(state: state) {
                    Divider()
                    Button {
                        session.send(w.command)
                    } label: {
                        Text("Wormhole to \(Names.system(w.destination, in: state))")
                    }
                }
                Divider()
                Button("Find System…") { session.present(.sheet(.findSystem)) }
            } label: {
                if state.warpSystem == cur {
                    Text("Choose Target")
                } else {
                    Text("\(Names.system(state.warpSystem, in: state)) · \(state.warpTargetPreview(state.warpSystem).distance) parsecs")
                }
            }
            .disabled(state.phase != .docked || session.isModal)
            .help(Text("Choose the system to warp to."))
            .accessibilityIdentifier(AXID.Toolbar.target)
        }
    }
}
