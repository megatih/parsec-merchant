// SPDX-License-Identifier: GPL-2.0-or-later
// Ruleset switches for encounters, opponents, combat and police (RUL-070…099, 102…104, 109…112, 114, 120, 130…140). docs/specs/RUL.md is normative.

/// Encounter behaviour switches. Each case of every switch is selected by the ruleset presets below; engine code reads
/// these values and never branches on the ruleset id.
public struct EncounterRules: Sendable, Equatable {
    /// Windows 2.01 (faithful C# port).
    public static let windows201 = EncounterRules()
    /// Modern: Windows 2.01 with the PRD §4.3 fixes in this area.
    public static let modern = EncounterRules()
    /// Original Palm 1.2.2.
    public static let palm122 = EncounterRules()
}
