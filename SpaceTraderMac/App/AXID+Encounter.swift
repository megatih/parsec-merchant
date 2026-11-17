// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine

/// Encounter view identifiers (UI-ENC §17 "Encounter"). The M7 interim strings are kept unchanged.
nonisolated extension AXID {
    enum Encounter {
        static let view = "encounter.view"
        static let intro = "encounter.intro"
        static let badge = "encounter.badge"
        static let player = "encounter.player"
        static let playerHull = "encounter.player.hull"
        static let playerShields = "encounter.player.shields"
        static let opponent = "encounter.opponent"
        static let opponentHull = "encounter.opponent.hull"
        static let opponentShields = "encounter.opponent.shields"
        static let opponentDisabled = "encounter.opponent.disabled"
        static let log = "encounter.log"
        static func logRow(_ index: Int) -> String { "encounter.log.row.\(index)" }
        static let actions = "encounter.actions"
        /// `encounter.action.<EncounterAction>`, including `resolve` and `stop` (UI-ENC-027, -031, -032).
        static func action(_ a: EncounterAction) -> String { "encounter.action.\(a.rawValue)" }
        /// The session-only Auto-repeat toggle (UI-ENC-033).
        static let autoRepeat = "encounter.autoRepeat"
        static let resumeDecision = "encounter.resumeDecision"
        static let tactical = "encounter.tactical"
        static let tacticalClass = "encounter.tactical.class"
        static let tacticalEquipment = "encounter.tactical.equipment"
        static let tacticalFleeOdds = "encounter.tactical.fleeOdds"
        static func tribble(_ index: Int) -> String { "encounter.tribble.\(index)" }
        /// The M7 interim panel (UI-SHELL-010); retired together with `InterimEncounterPanel`.
        static let interimPanel = "encounter.panel"

        /// Actions that have a button (the `autoRepeat` engine tick has none, UI-ENC-028).
        static let buttonActions = EncounterAction.allCases.filter { $0 != .autoRepeat }
        static let all: [String] = [view, intro, badge, player, playerHull, playerShields, opponent, opponentHull,
                                    opponentShields, opponentDisabled, log, actions, autoRepeat, resumeDecision, tactical,
                                    tacticalClass, tacticalEquipment, tacticalFleeOdds, interimPanel]
            + buttonActions.map(action)
    }
}
