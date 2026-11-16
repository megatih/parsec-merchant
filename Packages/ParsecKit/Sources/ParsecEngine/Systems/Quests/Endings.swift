// SPDX-License-Identifier: GPL-2.0-or-later
// Game endings and score (docs/specs/SCORE.md). C# Game.Score, Form_SpaceTrader.mnuRetire_Click / GameEnd.

public extension GameState {
    /// SCORE-002/012: ends the game and returns the final `gameEnded` event (score on the committed state).
    mutating func endGame(_ end: GameEndType) -> GameEvent {
        phase = .gameOver(end)
        return .gameEnded(end, score: score(for: end))
    }

    /// SCORE: C# `Game.Score` for an end type, in tenths of a percent. 32-bit arithmetic wraps like the C# source.
    func score(for end: GameEndType) -> Int {
        let w = worth
        let scaled = Int32(truncatingIfNeeded: w < 1_000_000 ? w : 1_000_000 + (w - 1_000_000) / 10)
        let d = Int32(difficulty.rawValue + 1)
        var daysMoon: Int32 = 0
        let modifier: Int32
        switch end {
        case .killed: modifier = 90
        case .retired: modifier = 95
        case .boughtMoon, .boughtMoonGirl:
            daysMoon = max(0, d &* 100 &- Int32(truncatingIfNeeded: commander.days))
            modifier = 100
        }
        return Int(d &* modifier &* (daysMoon &* 1_000 &+ scaled) / 250_000)
    }
}

extension GameEngine {
    /// SCORE-016/017: retire (C# mnuRetire_Click), docked only, two-phase with `WarningID.retire` carrying the score preview.
    mutating func retire(_ ack: Set<WarningID>) -> StepResult {
        if case .gameOver = state.phase { return .rejected(.gameOver) }
        guard case .docked = state.phase else { return .rejected(.notAllowedInPhase) }
        guard ack.contains(.retire) else {
            return .needsConfirmation(Confirmation(.retire, amounts: [state.score(for: .retired)]))
        }
        return StepResult(events: [state.endGame(.retired)])
    }
}
