// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

/// A11Y-048 / UI-ENC-103: the README screenshots. Runs only when the runner sees `PM_EXPORT_SCREENSHOTS=1` (xcodebuild passes
/// `TEST_RUNNER_PM_EXPORT_SCREENSHOTS=1`); `verify.sh --ui` therefore skips it. `scripts/export-screenshots.sh` exports the
/// `readme-*` attachments to `docs/screenshots/` (A11Y-049).
final class ReadmeScreenshotUITests: ParsecUITestCase {
    override func setUp() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PM_EXPORT_SCREENSHOTS"] == "1",
                          "README screenshots are exported only with PM_EXPORT_SCREENSHOTS=1")
        try await super.setUp()
    }

    /// A fixed seed, template flavor, no audio, no tips, fast travel, the default window, light appearance.
    override var launchArguments: [String] { UITestFixtures.launchArguments + ["-PMAppearance", "light"] }

    @MainActor
    func testExportReadmeScreenshots() throws {
        // covers: A11Y-048, UI-ENC-103
        shoot("readme-welcome")
        click(AXID.Welcome.quickStart)
        expect("the Quick Start game runs") { subtitle.hasPrefix("Day 0") }
        openPage("bridge")
        click(AXID.Bridge.targetNext)
        shoot("readme-bridge")
        click(AXID.Cargo.buy("water"))
        shoot("readme-market")
        openPage("galaxy")
        let g = AXID.Galaxy.section
        if !element(g.legend).exists { click(g.legendToggle) }
        chooseMenuItem("Game", "Plot Route…")
        waitFor(g.routePanel)
        let heatmap = element("galaxy.heatmap")
        if heatmap.waitForExistence(timeout: 3) {
            heatmap.click()
            let water = app.menuItems["Water"].firstMatch
            if water.waitForExistence(timeout: 2) { water.click() } else { type(XCUIKeyboardKey.escape.rawValue, []) }
        }
        shoot("readme-galaxy")
        openPage("logbook")
        selectLogbookTab("Statistics")
        shoot("readme-logbook-statistics")
        selectLogbookTab("Achievements")
        shoot("readme-achievements")
        selectLogbookTab("Captain's Log")

        // The Shipyard picture needs a system that sells ships; the first Quick Start seed that has some is used.
        for seed in [UITestFixtures.mapFlowSeed, 1, 2, 3, 4, 5, 6] {
            relaunch(UITestFixtures.launchArguments(seed: seed) + ["-PMAppearance", "light"])
            click(AXID.Welcome.quickStart)
            expect("the Quick Start game runs") { subtitle.hasPrefix("Day 0") }
                        openPage("shipyard")
            waitFor("shipyard.root")
            let offers = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH 'shipyard.ship.' AND identifier ENDSWITH '.buy'"))
            if offers.count >= 3 { break }
        }
        let designer = element("shipyard.designer")
        if designer.waitForExistence(timeout: 3) { designer.click() }
        shoot("readme-shipyard-designer")

        relaunch(UITestFixtures.ambushLaunchArguments + ["-PMAppearance", "light"])
        waitFor(AXID.Encounter.view)
        click(AXID.Encounter.attack)
        waitFor(AXID.Encounter.logRow(1))
        shoot("readme-encounter")
        let view = element(AXID.Encounter.view)
        var presses = 0
        while view.exists, presses < UITestFixtures.ambushMaxAttacks {
            let attack = element(AXID.Encounter.attack)
            if attack.exists, attack.isEnabled {
                attack.click()
                presses += 1
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        waitFor(AXID.Arrival.card)
        openArrivalReport()
        shoot("readme-arrival")
        closeArrivalReport()
        type("n", [.command, .shift])
        if element(AXID.Dialog.confirmationConfirm).waitForExistence(timeout: 2) { click(AXID.Dialog.confirmationConfirm) }
        waitFor(AXID.Newspaper.sheet)
        shoot("readme-newspaper")
        click(AXID.Newspaper.close)
        retireGame()
        waitFor(AXID.GameOver.card)
        shoot("readme-gameover")

        relaunch(UITestFixtures.launchArguments + ["-PMAppearance", "dark"])
        click(AXID.Welcome.quickStart)
        expect("the Quick Start game runs") { subtitle.hasPrefix("Day 0") }
        openPage("bridge")
        click(AXID.Bridge.targetNext)
        shoot("readme-bridge-dark")
    }

    private func shoot(_ name: String) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))  // let springs settle
        let a = XCTAttachment(screenshot: mainWindow.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
