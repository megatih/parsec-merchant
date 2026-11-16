// SPDX-License-Identifier: GPL-2.0-or-later
// Ruleset switches for galaxy generation, content placement and start system (RUL-020…031). docs/specs/RUL.md is normative.

/// Galaxy behaviour switches. Each case of every switch is selected by the ruleset presets below; engine code reads
/// these values and never branches on the ruleset id.
public struct GalaxyRules: Sendable, Equatable {
    /// Windows 2.01 (faithful C# port).
    public static let windows201 = GalaxyRules()
    /// Modern: Windows 2.01 with the PRD §4.3 fixes in this area.
    public static let modern = GalaxyRules()
    /// Original Palm 1.2.2.
    public static let palm122 = GalaxyRules()
}
