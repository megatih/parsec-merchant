// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// UI-ENC-005: the last accepted step, with the state before and after it. A value, replaced on each accepted step and
/// cleared on load, new game and close. Builders that need "before and after" read this, never a stored `GameState`.
struct StepRecord: Equatable, Sendable {
    var command: Command
    var acknowledged: Set<WarningID>
    var before: GameState
    var result: StepResult
    var after: GameState

    var events: [GameEvent] { result.events }

    /// The step's first `encounterStarted`, if any.
    var encounterStarted: (type: EncounterType, opponent: ShipType, clicks: Int, playerCloaked: Bool)? {
        for e in events {
            if case let .encounterStarted(type, opponent, clicks, cloaked) = e { return (type, opponent, clicks, cloaked) }
        }
        return nil
    }

    func contains(_ test: (GameEvent) -> Bool) -> Bool { events.contains(where: test) }
}
