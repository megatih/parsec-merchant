// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

extension AXID {
    /// Settings › Sound (AUD-042), mirrored from the app's `AXID.Sound`.
    enum Sound {
        static let tab = "settings.tab.sound"
        static let mute = "settings.sound.mute"
        static let overall = "settings.sound.master"
        static let effects = "settings.sound.effects"
        static let musicEnabled = "settings.sound.musicEnabled"
        static let music = "settings.sound.music"
        static let muteWhenInactive = "settings.sound.muteWhenInactive"
        static let haptics = "settings.sound.haptics"
        static let preview = "settings.sound.preview"
        static let status = "settings.sound.status"
        static let controls = [mute, overall, effects, musicEnabled, music, muteWhenInactive, haptics, preview, status]
    }
}

/// The M11 exit check (AUD-051): the app runs with audio on (silenced by the argument domain, AUD-043), plays a whole
/// encounter and still reports the output as running.
final class M11AudioUITests: ParsecUITestCase {
    override var launchArguments: [String] {
        ["-PMResetState", "-PMScenario", "pirateAmbush", "-PMFastTravel", "-PMFlavor", "template",
         "-settings.sound.master", "0"]
    }

    @MainActor
    func testAudioOnLaunchResolvesEncounterAndReportsRunning() throws {
        // covers: AUD-051, AUD-042
        let view = waitFor(AXID.Encounter.view)
        waitFor(AXID.Encounter.resolve)
        // Press Resolve (its key, R, so a button that vanishes mid-query cannot fail the click) until the encounter ends.
        var presses = 0
        while view.exists, presses < UITestFixtures.ambushMaxAttacks {
            type("r", [])
            presses += 1
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        }
        expect("the encounter ends within \(UITestFixtures.ambushMaxAttacks) Resolve presses") { !view.exists }

        type(",")
        let tab = element(AXID.Sound.tab)
        if tab.waitForExistence(timeout: timeout) {
            tab.click()
        } else {
            app.buttons["Sound"].firstMatch.click()
        }
        for id in AXID.Sound.controls { waitFor(id) }
        let status = waitFor(AXID.Sound.status)
        expect("settings.sound.status reads Running (status: \(text(of: status)))") {
            text(of: element(AXID.Sound.status)).contains("Running")
        }
        XCTAssertEqual(app.state, .runningForeground, "the app is still running")
        type("w")
    }
}
