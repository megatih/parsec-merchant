// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// UI-KEYS-007: a shortcut as the keyboard sees it (US layout), for the conflict and reserved-key audits.
nonisolated struct NormalizedShortcut: Hashable, Sendable, CustomStringConvertible {
    var key: String
    var modifiers: Set<MenuShortcut.Modifier>

    /// The unshifted key of each shifted US symbol (`?` = ⇧`/`). `+` is left out: ⌘+ and ⌘= are one physical key.
    static let shiftedSymbols: [Character: String] = [
        "?": "/", "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8", "(": "9", ")": "0",
        "_": "-", "{": "[", "}": "]", "|": "\\", ":": ";", "\"": "'", "<": ",", ">": ".", "~": "`",
    ]

    /// The physical key: letters lowercased (an uppercase letter implies ⇧), shifted symbols as ⇧ plus their base key,
    /// and `+` as `=` (UI-KEYS-013's alias). Esc stays Esc.
    init(physical s: MenuShortcut) {
        var mods = s.modifiers
        var key = s.key
        if key.count == 1, let c = key.first {
            if c.isLetter, c.isUppercase {
                mods.insert(.shift)
                key = key.lowercased()
            } else if let base = Self.shiftedSymbols[c] {
                mods.insert(.shift)
                key = base
            } else if c == "+" {
                // Typed as ⇧= on a US keyboard; the catalog writes it without ⇧. Both are the ⌘= key.
                key = "="
                mods.remove(.shift)
            }
        }
        self.key = key
        modifiers = mods
    }

    /// The conflict key: the physical key, with Esc and ⌘. both meaning "cancel" (UI-KEYS-007).
    init(_ s: MenuShortcut) {
        let p = NormalizedShortcut(physical: s)
        let isCancel = (p.key == EncounterKeys.escapeKey && p.modifiers.isEmpty) || (p.key == "." && p.modifiers == [.command])
        self = isCancel ? NormalizedShortcut(key: "cancel", modifiers: []) : p
    }

    private init(key: String, modifiers: Set<MenuShortcut.Modifier>) {
        self.key = key
        self.modifiers = modifiers
    }

    var description: String { MenuShortcut(key, modifiers).display }
}

/// UI-KEYS-008: the macOS 27 system and accessibility shortcuts that no custom binding may use (re-checked against
/// Apple's "Mac keyboard shortcuts" page). Function keys are written "F1"…"F12".
nonisolated enum SystemShortcuts {
    private static func s(_ key: String, _ m: Set<MenuShortcut.Modifier>) -> NormalizedShortcut {
        NormalizedShortcut(physical: MenuShortcut(key, m))
    }

    static let systemWide: Set<NormalizedShortcut> = {
        var out: Set<NormalizedShortcut> = [
            s(" ", [.command]), s(" ", [.option, .command]), s(" ", [.control]), s(" ", [.control, .option]),
            s(MenuShortcut.tabKey, [.command]), s(MenuShortcut.tabKey, [.shift, .command]), s(EncounterKeys.escapeKey, [.option, .command]),
            s("q", [.control, .command]), s("q", [.shift, .command]), s("q", [.option, .shift, .command]),
            s("3", [.shift, .command]), s("4", [.shift, .command]), s("5", [.shift, .command]), s("6", [.shift, .command]),
            s("3", [.control, .shift, .command]), s("4", [.control, .shift, .command]), s("d", [.option, .command]),
            s(" ", [.control, .command]),
            s(MenuShortcut.upArrowKey, [.control]), s(MenuShortcut.downArrowKey, [.control]),
            s(MenuShortcut.leftArrowKey, [.control]), s(MenuShortcut.rightArrowKey, [.control]), s("F11", []),
        ]
        for n in 1...9 { out.insert(s(String(n), [.control])) }
        return out
    }()

    static let accessibility: Set<NormalizedShortcut> = {
        var out: Set<NormalizedShortcut> = [
            s("F5", [.command]), s("F5", [.option, .command]), s("8", [.option, .command]), s("=", [.option, .command]),
            s("-", [.option, .command]), s("8", [.control, .option, .command]), s(",", [.control, .option, .command]),
            s(".", [.control, .option, .command]),
            s(MenuShortcut.tabKey, []), s(MenuShortcut.tabKey, [.shift]), s(MenuShortcut.tabKey, [.control]),
            s(MenuShortcut.tabKey, [.control, .shift]), s(" ", []),
        ]
        for n in 1...8 { out.insert(s("F\(n)", [.control])) }
        return out
    }()

    /// Standard app shortcuts kept by their standard items only (Help ⌘? is the catalog's standard-role item).
    static let standardItems: Set<NormalizedShortcut> = [
        s(",", [.command]), s("h", [.command]), s("h", [.option, .command]), s("q", [.command]), s("w", [.command]),
        s("w", [.option, .command]), s("m", [.command]), s("m", [.option, .command]), s("z", [.command]), s("z", [.shift, .command]),
        s("x", [.command]), s("c", [.command]), s("v", [.command]), s("v", [.option, .shift, .command]), s("a", [.command]),
        s("?", [.command]), s("`", [.command]), s("`", [.shift, .command]), s("f", [.control, .command]), s("s", [.control, .command]),
        s("i", [.control, .command]), s(".", [.command]),
    ]

    /// Standard text-view meanings kept free (no app item).
    static let keptFree: Set<NormalizedShortcut> = [
        s("g", [.command]), s("g", [.shift, .command]), s("e", [.command]), s("p", [.command]), s("p", [.shift, .command]),
        s("t", [.command]), s("b", [.command]), s("i", [.command]), s("u", [.command]),
    ]

    static var reserved: Set<NormalizedShortcut> { systemWide.union(accessibility).union(standardItems).union(keptFree) }

    /// Whether a shortcut is reserved: listed, or in a reserved family (⌃ with ⌥ is the VoiceOver modifier).
    static func isReserved(_ shortcut: MenuShortcut) -> Bool {
        let n = NormalizedShortcut(physical: shortcut)
        if n.modifiers.isSuperset(of: [.control, .option]) { return true }
        return reserved.contains(n)
    }
}

/// UI-KEYS-006: the conflict audit over `KeyBindingTable.all`.
nonisolated enum KeyAudit {
    struct Conflict: Sendable, CustomStringConvertible {
        var shortcut: NormalizedShortcut
        var first: KeyBinding
        var second: KeyBinding
        var description: String {
            "\(shortcut): \(first.owner) \(first.action) [\(first.context)] vs \(second.owner) \(second.action) [\(second.context)]"
        }
    }

    /// Pairs with an equal conflict key, contexts that can coexist and different actions.
    static func staticConflicts(_ bindings: [KeyBinding]) -> [Conflict] {
        var out: [Conflict] = []
        for (i, a) in bindings.enumerated() {
            for b in bindings[(i + 1)...] where a.action != b.action && KeyContext.canCoexist(a.context, b.context) {
                let n = NormalizedShortcut(a.shortcut)
                if n == NormalizedShortcut(b.shortcut) { out.append(Conflict(shortcut: n, first: a, second: b)) }
            }
        }
        return out
    }

    /// The bindings live in a situation: `active` contexts, and for menu items also `menuEnabled` (MENU-004: a key
    /// equivalent fires only while its item is enabled).
    static func live(_ bindings: [KeyBinding], active: Set<KeyContext>, menuEnabled: (MenuItemID) -> Bool) -> [KeyBinding] {
        bindings.filter { b in
            guard b.context == .global || active.contains(b.context) else { return false }
            if case let .menu(id) = b.owner { return menuEnabled(id) }
            return true
        }
    }

    /// Conflicts among the bindings live at the same time.
    static func liveConflicts(_ bindings: [KeyBinding], active: Set<KeyContext>, menuEnabled: (MenuItemID) -> Bool) -> [Conflict] {
        let l = live(bindings, active: active, menuEnabled: menuEnabled)
        var out: [Conflict] = []
        for (i, a) in l.enumerated() {
            for b in l[(i + 1)...] where a.action != b.action {
                let n = NormalizedShortcut(a.shortcut)
                if n == NormalizedShortcut(b.shortcut) { out.append(Conflict(shortcut: n, first: a, second: b)) }
            }
        }
        return out
    }
}
