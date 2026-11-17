// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import SwiftUI

/// UI-ENC-028: the encounter keys. Plain letters for the actions, R for Resolve, Esc for Stop and ⌥A for the
/// Auto-repeat toggle. The engine's `autoRepeat` tick has no key. The Encounter menu registers them (UI-ENC-034);
/// the action bar only shows the key caps.
nonisolated enum EncounterKeys {
    /// The Escape key as a shortcut key string.
    static let escapeKey = "\u{1B}"

    /// The shortcut of an action's button and menu item (nil for the engine tick).
    static func shortcut(for action: EncounterAction) -> MenuShortcut? {
        let letter: String? = switch action {
        case .attack: "a"
        case .flee: "f"
        case .surrender: "s"
        case .ignore: "i"
        case .bribe: "b"
        case .submit: "u"
        case .trade: "t"
        case .plunder: "p"
        case .board: "o"
        case .drink: "d"
        case .meet: "m"
        case .yield: "y"
        case .resolve: "r"
        case .stop: escapeKey
        case .autoRepeat: nil
        }
        return letter.map { MenuShortcut($0, []) }
    }

    /// The Auto-repeat toggle (⌥A).
    static let autoRepeatToggle = MenuShortcut("a", [.option])

    /// The key cap shown next to a label: "A", "R", "Esc".
    static func keyCap(for action: EncounterAction) -> String? {
        guard let s = shortcut(for: action) else { return nil }
        return s.key == escapeKey ? "Esc" : s.key.uppercased()
    }

    @MainActor
    static func key(for action: EncounterAction) -> KeyEquivalent? {
        shortcut(for: action).map { $0.keyboardShortcut.key }
    }

    @MainActor
    static func modifiers(for action: EncounterAction) -> EventModifiers {
        shortcut(for: action)?.keyboardShortcut.modifiers ?? []
    }
}

/// UI-ENC-034: the Encounter menu's view of the current encounter, built from `EncounterPreview` by `MenuContext.make`.
nonisolated struct EncounterMenuState: Sendable, Equatable {
    var actions: [EncounterActionPreview]
    var canStop: Bool
    /// UI-ENC-033: the engine sets a continue flag only with Continuous attack or after Resolve.
    var autoRepeatAvailable: Bool
    /// The session-only Auto-repeat switch.
    var autoRepeatOn: Bool

    static func make(engine: GameEngine, autoRepeatOn: Bool) -> EncounterMenuState? {
        guard let preview = engine.encounterPreview, case let .encounter(enc) = engine.state.phase else { return nil }
        return EncounterMenuState(actions: preview.actions, canStop: preview.canStop,
                                  autoRepeatAvailable: engine.state.options.continuousAttack || enc.forceContinuous,
                                  autoRepeatOn: autoRepeatOn)
    }

    func preview(_ action: EncounterAction) -> EncounterActionPreview? { actions.first { $0.action == action } }

    /// UI-ENC-031: Resolve is shown iff Attack is offered and enabled iff Attack has no rejection.
    var resolveShown: Bool { preview(.attack) != nil }
    var resolveRejection: CommandError? { preview(.attack)?.rejection }
}

/// The Encounter menu items that mirror an `EncounterAction` (UI-ENC-034).
nonisolated extension MenuItemID {
    static let encounterItems: [MenuItemID] = [
        .encounterAttack, .encounterFlee, .encounterSurrender, .encounterIgnore, .encounterBribe, .encounterSubmit, .encounterTrade,
        .encounterPlunder, .encounterBoard, .encounterDrink, .encounterMeet, .encounterYield, .encounterAutoRepeat,
        .encounterResolve, .encounterStop,
    ]

    /// The engine action of an Encounter item (nil for the Auto-repeat toggle and every non-encounter item).
    var encounterAction: EncounterAction? {
        switch self {
        case .encounterAttack: .attack
        case .encounterFlee: .flee
        case .encounterSurrender: .surrender
        case .encounterIgnore: .ignore
        case .encounterBribe: .bribe
        case .encounterSubmit: .submit
        case .encounterTrade: .trade
        case .encounterPlunder: .plunder
        case .encounterBoard: .board
        case .encounterDrink: .drink
        case .encounterMeet: .meet
        case .encounterYield: .yield
        case .encounterResolve: .resolve
        case .encounterStop: .stop
        default: nil
        }
    }
}
