// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// UI-KEYS-002: the groups of Help › Keyboard Shortcuts, in the order of UI-KEYS §2. "Window" holds the main window's
/// own Return and Esc keys (Welcome, Transit, game over, the Esc router).
nonisolated enum ShortcutGroup: String, CaseIterable, Sendable {
    case menus, market, galaxyMap, encounter, window, sheets, textFields

    var title: LocalizedStringResource {
        switch self {
        case .menus: "Menus"
        case .market: "Market"
        case .galaxyMap: "Galaxy map"
        case .encounter: "Encounter"
        case .window: "Window"
        case .sheets: "Sheets and dialogs"
        case .textFields: "Text fields"
        }
    }

    init(_ context: KeyContext) {
        switch context {
        case .global: self = .menus
        case .marketTable, .marketField: self = .market
        case .mapCanvas: self = .galaxyMap
        case .encounter: self = .encounter
        case .mainWindow, .transit: self = .window
        case .sheet, .dialog: self = .sheets
        case .searchField, .textField: self = .textFields
        }
    }
}

/// One row: "<display>  <title>".
nonisolated struct ShortcutRow: Equatable, Sendable {
    var display: String
    var title: String
    var action: KeyActionID
    var isAlias: Bool
}

/// UI-KEYS-002: the page model, generated from `KeyBindingTable.all` (menu items of later milestones left out).
nonisolated enum KeyboardShortcutsPage {
    static func make(milestone: Int = MenuCatalog.currentMilestone) -> [(group: ShortcutGroup, rows: [ShortcutRow])] {
        let bindings = KeyBindingTable.all.filter { b in
            if case let .menu(id) = b.owner { return MenuCatalog.entry(for: id).milestone <= milestone }
            return true
        }
        return ShortcutGroup.allCases.compactMap { group in
            let inGroup = bindings.filter { ShortcutGroup($0.context) == group }
            var rows: [ShortcutRow] = []
            for b in inGroup where !b.isAlias {
                rows.append(row(b))
                // A hidden alias follows its primary key (⌘= after ⌘+).
                rows += bindings.filter { $0.isAlias && $0.action == b.action }.map(row)
            }
            // Aliases whose primary is in another group stay in their own group.
            for b in inGroup where b.isAlias && !rows.contains(where: { $0.action == b.action && $0.display == b.shortcut.display }) {
                rows.append(row(b))
            }
            return rows.isEmpty ? nil : (group, rows)
        }
    }

    private static func row(_ b: KeyBinding) -> ShortcutRow {
        ShortcutRow(display: b.shortcut.display, title: String(localized: b.titleKey), action: b.action, isAlias: b.isAlias)
    }

    /// The Markdown appended to the Keyboard Shortcuts topic.
    static func markdown(milestone: Int = MenuCatalog.currentMilestone) -> String {
        make(milestone: milestone).map { section in
            (["## " + String(localized: section.group.title)] + section.rows.map { "- **\($0.display)**  \($0.title)" })
                .joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }
}
