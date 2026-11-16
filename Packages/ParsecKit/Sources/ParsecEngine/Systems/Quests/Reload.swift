// SPDX-License-Identifier: GPL-2.0-or-later
// Resuming a loaded game (docs/specs/SAV.md §8): reload accounting and the Palm per-session chances. Pure.

public extension GameState {
    /// Palm's start-of-session values of the cheat-adjustable chances.
    static let sessionChanceOfVeryRareEncounter = 5
    static let sessionChanceOfTradeInOrbit = 100

    /// SAV-036/037: the state as resumed for play after a load. A load that counts as a reload (SAV-035) adds one to
    /// `reloadCount`; rulesets whose cheat chances do not persist (Palm) restore their session defaults. Draws no
    /// random numbers and changes nothing else.
    func resumedAfterLoad(countsAsReload: Bool) -> GameState {
        var s = self
        if countsAsReload { s.reloadCount += 1 }
        if !ruleset.flags.travel.cheatChancesPersist {
            s.chanceOfVeryRareEncounter = Self.sessionChanceOfVeryRareEncounter
            s.chanceOfTradeInOrbit = Self.sessionChanceOfTradeInOrbit
        }
        return s
    }
}
