// SPDX-License-Identifier: GPL-2.0-or-later
// Ruleset switches for quest chains and special events (RUL-141…143 and the QST {M5} flags). docs/specs/RUL.md is normative.

/// Quest behaviour switches. Each case of every switch is selected by the ruleset presets below; engine code reads
/// these values and never branches on the ruleset id.
public struct QuestRules: Sendable, Equatable {
    /// Windows 2.01 (faithful C# port).
    public static let windows201 = QuestRules()
    /// Modern: Windows 2.01 with the PRD §4.3 fixes in this area.
    public static let modern = QuestRules()
    /// Original Palm 1.2.2.
    public static let palm122 = QuestRules()
}
