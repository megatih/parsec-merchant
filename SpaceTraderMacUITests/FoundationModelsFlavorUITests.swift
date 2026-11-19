// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

/// LLM-031 [manual]: generated log prose on a Mac with Apple Intelligence. Runs only when the runner sees `PM_LLM_QA=1`
/// (xcodebuild passes `TEST_RUNNER_PM_LLM_QA=1`), so `verify.sh --ui` skips it. It launches the flow-2 ambush without
/// `-PMFlavor template` and with Settings › Intelligence › "Write log entries with Apple Intelligence" on, wins the
/// encounter, waits for entries marked "Apple Intelligence", quits (autosave), relaunches, continues and checks the same
/// prose again. Screenshots: `qa-llm-*` (`.keepAlways`).
final class FoundationModelsFlavorUITests: ParsecUITestCase {
    /// The model answers in seconds; the first request may also load it.
    private let generationTimeout: TimeInterval = 120
    /// The Settings toggle, set through the argument domain (a property-list boolean).
    private static let flavorOn = ["-settings.flavor.useFoundationModels", "<true/>"]
    private static let common = ["-PMFastTravel", "-PMAudio", "off", "-PMAppearance", "light"] + flavorOn

    override func setUp() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PM_LLM_QA"] == "1",
                          "LLM-031 runs only with PM_LLM_QA=1 on a Mac with Apple Intelligence")
        try await super.setUp()
    }

    override var launchArguments: [String] { ["-PMResetState", "-PMScenario", "pirateAmbush"] + Self.common }

    @MainActor
    func testGeneratedProseSurvivesSaveAndReload() throws {
        // covers: LLM-031
        type(",")
        selectSettingsTab("intelligence")
        let status = waitFor("settings.flavor.status")
        XCTAssertEqual(text(of: status), "Available", "the status line reports the on-device model as available")
        XCTAssertTrue(isOn(element("settings.flavor.foundationModels")), "the flavor setting is on")
        shoot("qa-llm-settings", windowElement(containing: status))
        type("w")

        let view = waitFor(AXID.Encounter.view)
        for _ in 0..<UITestFixtures.ambushMaxAttacks * 2 where view.exists {
            type("a", [])
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        }
        expect("the encounter ends") { !view.exists }

        openPage("logbook")
        selectTab("Captain's Log")
        waitFor(AXID.Logbook.list)
        var generated: [String] = []
        let deadline = Date().addingTimeInterval(generationTimeout)
        while Date() < deadline {
            generated = generatedRows()
            if generated.count >= 2 { break }
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        XCTAssertFalse(generated.isEmpty, "LLM-031: an entry carries prose written by Apple Intelligence within \(Int(generationTimeout)) s")
        for row in generated {
            XCTAssertFalse(UITestFixtures.encounterWonFlavor.contains { row.contains($0) }, "generated, not template text: \(row)")
        }
        shoot("qa-llm-logbook-generated", mainWindow)

        // ⌘Q autosaves the game with its journal (SAV-038); Continue loads that autosave after the relaunch.
        type("q")
        XCTAssertTrue(app.wait(for: .notRunning, timeout: timeout), "the app quits")
        relaunch(Self.common)
        click("welcome.continue")
        openPage("logbook")
        selectTab("Captain's Log")
        waitFor(AXID.Logbook.list)
        var reloaded: [String] = []
        let reloadDeadline = Date().addingTimeInterval(timeout)
        while Date() < reloadDeadline {
            reloaded = generatedRows()
            if Set(generated).isSubset(of: Set(reloaded)) { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        shoot("qa-llm-logbook-reloaded", mainWindow)
        for row in generated { print("LLM-031 generated: \(row)") }
        for row in reloaded { print("LLM-031 reloaded: \(row)") }
        XCTAssertTrue(Set(generated).isSubset(of: Set(reloaded)), "LLM-031: the generated prose survives a save and reload")
        openPage("bridge")
    }

    /// The labels of the log rows marked "Apple Intelligence" (the row combines its texts and the symbol's label).
    private func generatedRows() -> [String] {
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", AXID.Logbook.entryPrefix))
        return rows.allElementsBoundByIndex.map(\.label).filter { $0.contains("Apple Intelligence") }
    }

    private func shoot(_ name: String, _ window: XCUIElement) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        let a = XCTAttachment(screenshot: window.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
