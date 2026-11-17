// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// MENU-036 / UI-ENC-034: the Encounter menu mirrors the action bar. Items, shortcuts and identifiers come from
/// `MenuCatalog` (shortcuts from `EncounterKeys`); visibility and enablement from `MenuRules` over `MenuContext.encounter`.
struct EncounterMenuItems: View {
    let session: GameSession

    var body: some View {
        let ctx = MenuContext.make(session: session)
        ForEach(MenuCatalog.items(in: .encounter).filter { $0 != .encounterAutoRepeat && MenuRules.isShown($0, in: ctx) },
                id: \.self) { id in
            if id == .encounterResolve { Divider() }
            MenuItemButton(id: id, availability: MenuRules.availability(of: id, in: ctx)) { perform(id) }
        }
        Divider()
        let entry = MenuCatalog.entry(for: .encounterAutoRepeat)
        Toggle(isOn: Binding { session.encounterUI.autoRepeatEnabled } set: { session.setAutoRepeat($0) }) {
            Text(entry.titleKey)
        }
        .modifier(OptionalShortcut(shortcut: entry.shortcut))
        .disabled(!MenuRules.availability(of: .encounterAutoRepeat, in: ctx).isEnabled)
        .accessibilityIdentifier(entry.identifier)
    }

    private func perform(_ id: MenuItemID) {
        switch id.encounterAction {
        case .stop?: session.stopEncounter()
        case let action?: session.performEncounterAction(action)
        case nil: break
        }
    }
}
