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
            let model = WarpButtonModel.make(state: session.state, isModal: session.isInputLocked)
            Button {
                session.send(.warp)
            } label: {
                Label("Warp", systemImage: "arrow.up.forward.circle")
            }
            .disabled(!model.isEnabled)
            .help(model.help)
            .accessibilityHint(Text(AccessibilityHints.warp(to: session.state.map { Names.system($0.warpSystem, in: $0) } ?? "")))
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
            // A11Y-029: an AppKit pull-down (SwiftUI's Menu has no press action for VoiceOver on macOS 27).
            PopUpMenuButton(title: title(state), items: items(state), accessibilityLabel: String(localized: "Target"),
                            identifier: AXID.Toolbar.target, help: String(localized: "Choose the system to warp to."),
                            isEnabled: state.phase == .docked && !session.isInputLocked)
        }
    }

    private func title(_ state: GameState) -> String {
        if state.warpSystem == state.commander.currentSystem { return String(localized: "Choose Target") }
        return String(localized: "\(Names.system(state.warpSystem, in: state)) · \(state.warpTargetPreview(state.warpSystem).distance) parsecs")
    }

    private func items(_ state: GameState) -> [PopUpMenuButton.Item] {
        var items = TargetPickerModel.entries(state: state).map { d in
            PopUpMenuButton.Item(title: String(localized: "\(d.name) · \(d.distance) parsecs")) { session.send(.selectTarget(d.index)) }
        }
        if let w = TargetPickerModel.wormhole(state: state) {
            items.append(.separator)
            items.append(PopUpMenuButton.Item(title: String(localized: "Wormhole to \(Names.system(w.destination, in: state))")) {
                session.send(w.command)
            })
        }
        items.append(.separator)
        items.append(PopUpMenuButton.Item(title: String(localized: "Find System…")) { session.present(.sheet(.findSystem)) })
        return items
    }
}
