// SPDX-License-Identifier: GPL-2.0-or-later

/// Constants shared by the UI flows (UI-SHELL-124/125). The app unit test FlowSeedTests checks the seed (UI-SHELL-129)
/// and the galaxy code (the UI-test target cannot import the engine).
enum UITestFixtures {
    /// Modern, Normal, 5/5/5/5: buying one unit, next target and warp docks at the target after an uneventful trip.
    static let flowSeed: UInt64 = 11
    /// `GalaxyCode(ruleset: .modern, difficulty: .normal, seed: flowSeed).string`.
    static let flowGalaxyCode = "M2-B-S"
    /// Flow 5 (MAP-100, checked by the app test MapSessionTests): its seed, the in-range system nearest the Quick Start
    /// system (an uneventful warp), and the nearest out-of-range system for the route scenario (MAP-102).
    static let mapFlowSeed: UInt64 = 13
    static let mapFlowTarget = 113
    static let mapRouteDestination = 124
    /// The commander name typed in the wizard.
    static let commanderName = "Flow"

    /// Every flow starts from a wiped Debug container (CHEAT-051) with the flow seed, instant travel and no audio.
    static var launchArguments: [String] { launchArguments(seed: flowSeed) }

    static func launchArguments(seed: UInt64) -> [String] {
        ["-PMResetState", "-PMSeed", String(seed), "-PMFastTravel", "-PMAudio", "off"]
    }
}
