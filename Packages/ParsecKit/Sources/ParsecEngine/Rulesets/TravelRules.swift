// SPDX-License-Identifier: GPL-2.0-or-later
// Ruleset switches for warp, transit, arrival, news and score (RUL-062…069, 118, 144…151). docs/specs/RUL.md is normative.

/// Travel behaviour switches. Each case of every switch is selected by the ruleset presets below; engine code reads
/// these values and never branches on the ruleset id.
public struct TravelRules: Sendable, Equatable {
    /// Windows 2.01 (faithful C# port).
    public static let windows201 = TravelRules()
    /// Modern: Windows 2.01 with the PRD §4.3 fixes in this area.
    public static let modern = TravelRules()
    /// Original Palm 1.2.2.
    public static let palm122 = TravelRules()
}
