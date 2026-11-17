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
    /// Flow 2 (UI-ENC-090/091, checked by the app test PirateAmbushScenarioTests against `PirateAmbushScenario`):
    /// `-PMScenario pirateAmbush` warps from seed 292 to system 46 into a pirate attack that Attack alone destroys in
    /// exactly `ambushExpectedAttacks` commands, then docks at the target.
    static let ambushSeed: UInt64 = 292
    static let ambushTarget = 46
    static let ambushExpectedAttacks = 6
    static let ambushMaxAttacks = 12
    /// UI-ENC-094 step 1.
    static let ambushLaunchArguments = ["-PMResetState", "-PMScenario", "pirateAmbush", "-PMFastTravel", "-PMAudio", "off", "-PMFlavor", "template"]
    /// UI-ENC-096: `-PMScenario encounter:<EncounterType>` (the app's `EncounterFixtureScenario`), for the sheets no
    /// played scenario reaches.
    static func encounterFixtureArguments(_ type: String) -> [String] {
        ["-PMResetState", "-PMScenario", "encounter:\(type)", "-PMFastTravel", "-PMAudio", "off", "-PMFlavor", "template"]
    }
    /// `-PMScenario specialEvent`: docked at a system offering an available special event.
    static let specialEventArguments = ["-PMResetState", "-PMScenario", "specialEvent", "-PMFastTravel", "-PMAudio", "off", "-PMFlavor", "template"]
    /// The flow seed with the transit playback shown (no `-PMFastTravel`), for the walk of the Transit view.
    static let playbackArguments = ["-PMResetState", "-PMSeed", String(flowSeed), "-PMAudio", "off", "-PMFlavor", "template"]
    /// ACH-022 (checked by the app test JournalSessionTests.achievementSeed): Quick Start with this seed, buy one unit of
    /// `achievementItem`, warp to the next target (uneventful) and sell it at a profit.
    static let achievementSeed: UInt64 = 11
    static let achievementItem = "games"
    /// LLM-029: the localized template lines of the `flavor.encounter.won` group (`FlavorCatalogText`), with the ship
    /// name left out.
    static let encounterWonFlavor = ["learned to leave us alone", "Our guns had the last word", "drifted dark behind us"]
    /// The commander name typed in the wizard.
    static let commanderName = "Flow"

    /// Every flow starts from a wiped Debug container (CHEAT-051) with the flow seed, instant travel, no audio and
    /// template flavor (LLM-024, LLM-029).
    static var launchArguments: [String] { launchArguments(seed: flowSeed) }

    static func launchArguments(seed: UInt64) -> [String] {
        ["-PMResetState", "-PMSeed", String(seed), "-PMFastTravel", "-PMAudio", "off", "-PMFlavor", "template"]
    }
}
