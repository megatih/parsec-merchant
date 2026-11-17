// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import SwiftUI

/// What a key does on the focused map canvas (MAP-015, UI-KEYS-013).
nonisolated enum MapKeyAction: Equatable, Sendable {
    case pan(dx: Int, dy: Int)
    case zoomIn
    case zoomOut
    case fit
    case dismiss
}

/// UI-KEYS-001 / UI-KEYS-013: the galaxy map's own keys. The canvas handler looks keys up here.
nonisolated enum MapKeys {
    static let canvasKeys: [(KeyActionID, MenuShortcut, MapKeyAction, LocalizedStringResource)] = [
        (.mapPanLeft, MenuShortcut(MenuShortcut.leftArrowKey, []), .pan(dx: -1, dy: 0), "Galaxy map: pan left"),
        (.mapPanRight, MenuShortcut(MenuShortcut.rightArrowKey, []), .pan(dx: 1, dy: 0), "Galaxy map: pan right"),
        (.mapPanUp, MenuShortcut(MenuShortcut.upArrowKey, []), .pan(dx: 0, dy: -1), "Galaxy map: pan up"),
        (.mapPanDown, MenuShortcut(MenuShortcut.downArrowKey, []), .pan(dx: 0, dy: 1), "Galaxy map: pan down"),
        // ⌘= is the unshifted key of ⌘+, which the catalog's "+" does not match on a US keyboard.
        (.menu(.zoomIn), MenuShortcut("=", [.command]), .zoomIn, "Zoom In"),
        // The focused canvas also answers ⌘− and ⌘0 itself, so they work even when the View menu has not caught up with
        // the focus change (same actions as the menu items: not a conflict).
        (.menu(.zoomOut), MenuShortcut("-", [.command]), .zoomOut, "Zoom Out"),
        (.menu(.zoomFit), MenuShortcut("0", [.command]), .fit, "Fit"),
        (.escape, MenuShortcut(EncounterKeys.escapeKey, []), .dismiss, "Galaxy map: close the hover card, legend and suggestions"),
    ]

    static let searchKeys: [(KeyActionID, MenuShortcut, LocalizedStringResource)] = [
        (.searchPrevious, MenuShortcut(MenuShortcut.upArrowKey, []), "Map search: previous suggestion"),
        (.searchNext, MenuShortcut(MenuShortcut.downArrowKey, []), "Map search: next suggestion"),
        (.searchChoose, MenuShortcut(MenuShortcut.returnKey, []), "Map search: choose the suggestion"),
    ]

    static var bindings: [KeyBinding] {
        canvasKeys.map {
            KeyBinding(action: $0.0, shortcut: $0.1, context: .mapCanvas, owner: .view(.mapCanvas), titleKey: $0.3,
                       isAlias: $0.1.modifiers == [.command])
        }
            + searchKeys.map { KeyBinding(action: $0.0, shortcut: $0.1, context: .searchField, owner: .view(.mapSearch), titleKey: $0.2) }
            + SearchFieldKeys.bindings
    }

    /// The canvas action of a pressed key (nil: not a map key, let it through).
    static func action(for pressed: MenuShortcut) -> MapKeyAction? {
        let n = NormalizedShortcut(physical: pressed)
        return canvasKeys.first { NormalizedShortcut(physical: $0.1) == n }?.2
    }
}

/// Esc in a search field clears it (Market filter UI-SHELL-067, map search MAP-073, Logbook search LOG-032); the main
/// window's router runs it (level 3, UI-KEYS-017).
nonisolated enum SearchFieldKeys {
    static var bindings: [KeyBinding] {
        let sites: [(ViewKeySite, LocalizedStringResource)] = [
            (.marketFilter, "Market filter: clear"), (.mapSearch, "Map search: clear"), (.logbookSearch, "Logbook search: clear"),
        ]
        return sites.map {
            KeyBinding(action: .escape, shortcut: WindowKeys.escapeKey, context: .searchField, owner: .view($0.0), titleKey: $0.1)
        }
    }
}
