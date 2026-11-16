// SPDX-License-Identifier: GPL-2.0-or-later
// Ruleset switches for markets, trade in orbit, insurance, ships, equipment, crew and bank (RUL-032…061, 101, 105…108, 113, 115…119). docs/specs/RUL.md is normative.

/// Economy behaviour switches. Each case of every switch is selected by the ruleset presets below; engine code reads
/// these values and never branches on the ruleset id.
public struct EconomyRules: Sendable, Equatable {
    /// Windows 2.01 (faithful C# port).
    public static let windows201 = EconomyRules()
    /// Modern: Windows 2.01 with the PRD §4.3 fixes in this area.
    public static let modern = EconomyRules()
    /// Original Palm 1.2.2.
    public static let palm122 = EconomyRules()
}
