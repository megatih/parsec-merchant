// SPDX-License-Identifier: GPL-2.0-or-later
// Game endings and score (docs/specs/SCORE.md). C# Game.Score, Form_SpaceTrader.mnuRetire_Click / GameEnd.

public extension GameState {
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
    /// SCORE: retire (C# mnuRetire_Click), two-phase with `WarningID.retire` carrying the score preview.
    mutating func retire(_ ack: Set<WarningID>) -> StepResult {
        if case .gameOver = state.phase { return .rejected(.gameOver) }
        guard ack.contains(.retire) else {
            return .needsConfirmation(Confirmation(.retire, amounts: [state.score(for: .retired)]))
        }
        state.phase = .gameOver(.retired)
        return StepResult(events: [.gameEnded(.retired)])
    }
}
