// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

/// UI-ENC-096: the identifier walk over the M9 surfaces the flow-2 scenario reaches: the Encounter view, the arrival
/// card, the newspaper sheet, the retire sheet, the game-over card and the High Scores window; then the Debug fixture
/// scenarios (`encounter:<type>`, `specialEvent`, the ambush without fast travel) for the remaining sheets. SwiftUI builds
/// no accessibility tree for a window-hosted view in a unit test, so every walk runs here, under UI automation.
final class M9IdentifierWalkUITests: ParsecUITestCase {
    override var launchArguments: [String] { UITestFixtures.ambushLaunchArguments }

    @MainActor
    func testEveryInteractiveElementOfTheM9SurfacesHasASchemeIdentifier() throws {
        // covers: UI-ENC-096
        waitFor(AXID.Encounter.view)
        waitFor(AXID.Encounter.tactical)
        walk(element(AXID.Encounter.view), surface: "Encounter view before the first action")
        walk(mainWindow, surface: "main window in the encounter")

        let view = element(AXID.Encounter.view)
        var attacks = 0
        while view.exists, attacks < UITestFixtures.ambushMaxAttacks {
            let attack = element(AXID.Encounter.attack)
            if attack.exists, attack.isEnabled {
                if attacks == 1 { walk(element(AXID.Encounter.view), surface: "Encounter view with a combat log") }
                attack.click()
                attacks += 1
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        expect("the encounter ends") { !view.exists }

        waitFor(AXID.Arrival.card)
        openArrivalReport()
        waitFor(AXID.Arrival.encounter(0))
        walk(sheet(), surface: "arrival report sheet")
        closeArrivalReport()
        walk(mainWindow, surface: "Bridge with the arrival summary")

        type("n", [.command, .shift])
        if element(AXID.Dialog.confirmationConfirm).waitForExistence(timeout: 2) {
            walk(sheet(), surface: "newspaper price confirmation")
            click(AXID.Dialog.confirmationConfirm)
        }
        waitFor(AXID.Newspaper.sheet)
        walk(sheet(), surface: "newspaper sheet")
        click(AXID.Newspaper.close)
        expect("the newspaper closes") { !element(AXID.Newspaper.sheet).exists }

        // Window › High Scores (the Window menu can list the item twice, so the first match is taken).
        app.menuBars.menuBarItems["Window"].click()
        let highScores = menuItem("Window", "High Scores").firstMatch
        XCTAssertTrue(highScores.waitForExistence(timeout: timeout), "Window › High Scores exists")
        highScores.click()
        waitFor(AXID.Scores.window)
        walk(element(AXID.Scores.window), surface: "High Scores window (empty)")
        type("w")
        expect("the High Scores window closes") { !element(AXID.Scores.window).exists }

        chooseMenuItem("Game", "Retire…")
        waitFor(AXID.Dialog.retireSheet)
        walk(sheet(), surface: "retire sheet")
        click(AXID.Dialog.retireConfirm)
        let card = waitFor(AXID.GameOver.card)
        walk(card, surface: "game-over card")
        walk(mainWindow, surface: "main window with the game-over card")

        // The career card's M10 statistics rows (STAT-022) can push the actions below the fold.
        reveal(element(AXID.GameOver.highScores), in: card).click()
        waitFor(AXID.Scores.window)
        walk(element(AXID.Scores.window), surface: "High Scores window with the retired career")
    }

    /// The Debug fixture scenarios reach the Transit view, the plunder, trade-in-orbit and arrest-report sheets, and the
    /// special-event card and narrative sheet.
    @MainActor
    func testEveryInteractiveElementOfTheFixtureSheetsHasASchemeIdentifier() throws {
        // covers: UI-ENC-096
        // An uneventful warp of the flow seed without fast travel plays 20 clicks; -PMSlowTravel 20 stretches it from
        // 1.2 s to 24 s so the snapshot does not race the playback (CHEAT-050). Retry in case the launch is slow.
        var transit: XCUIElementSnapshot?
        for _ in 0..<3 where transit == nil {
            relaunch(UITestFixtures.playbackArguments + ["-PMSlowTravel", "20"])
            click(AXID.Welcome.quickStart)
            expect("the Quick Start game runs") { subtitle.hasPrefix("Day 0") }
            openPage("bridge")
            click(AXID.Bridge.targetNext)
            type("j")
            let view = element(AXID.Transit.view)
            if view.waitForExistence(timeout: 3) { transit = try? view.snapshot() }
        }
        let snapshot = try XCTUnwrap(transit, "a snapshot of transit.view during the playback")
        walk(snapshot, surface: "Transit view")

        relaunch(UITestFixtures.encounterFixtureArguments("pirateSurrender"))
        click(AXID.Encounter.plunder)
        waitFor(AXID.Decision.plunderSheet)
        walk(sheet(), surface: "plunder sheet")
        click(AXID.Decision.plunderDone)
        expect("the plunder sheet closes") { !element(AXID.Decision.plunderSheet).exists }

        relaunch(UITestFixtures.encounterFixtureArguments("traderSell"))
        click(AXID.Encounter.trade)
        waitFor(AXID.Decision.tradeSheet)
        walk(sheet(), surface: "trade-in-orbit sheet")
        click(AXID.Decision.tradeDecline)
        expect("the trade sheet closes") { !element(AXID.Decision.tradeSheet).exists }

        relaunch(UITestFixtures.encounterFixtureArguments("policeAttack"))
        click(AXID.Encounter.surrender)
        if element(AXID.Dialog.confirmationConfirm).waitForExistence(timeout: 2) {
            walk(sheet(), surface: "surrender confirmation")
            click(AXID.Dialog.confirmationConfirm)
        }
        waitFor(AXID.Report.sheet)
        walk(sheet(), surface: "arrest report sheet")
        click(AXID.Report.continueButton)
        expect("the report closes") { !element(AXID.Report.sheet).exists }

        relaunch(UITestFixtures.specialEventArguments)
        openPage("bridge")
        walk(mainWindow, surface: "Bridge with a special offer")
        waitFor(AXID.Narrative.bridgeCard)
        click(AXID.Narrative.bridgeAccept)
        waitFor(AXID.Narrative.sheet)
        walk(sheet(), surface: "narrative offer sheet")
    }
}
