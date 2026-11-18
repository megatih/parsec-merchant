// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

/// M13 QA evidence for the review rows that used to be hand checks (QA-REPORT): the menu bar (UI-KEYS-011), Liquid Glass
/// and the window (UI-KEYS-032, UI-KEYS-035 "window"), the display settings (A11Y-020) and colour independence (A11Y-022).
/// Each step asserts what it can and attaches a `qa-manual-*` screenshot for the review. Runs only with
/// `PM_EXPORT_SCREENSHOTS=1` (`scripts/export-screenshots.sh --manual`), so `verify.sh --ui` skips it.
final class ManualQAUITests: ParsecUITestCase {
    override func setUp() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PM_EXPORT_SCREENSHOTS"] == "1",
                          "QA review screenshots are exported only with PM_EXPORT_SCREENSHOTS=1")
        try await super.setUp()
    }

    override var launchArguments: [String] { UITestFixtures.launchArguments + ["-PMAppearance", "light"] }

    // MARK: UI-KEYS-011

    /// Every menu of the menu bar, docked and in an encounter, as drawn by AppKit (titles and key equivalents).
    @MainActor
    func testMenuBarScreenshots() throws {
        startQuickStart()
        shootMenus(suffix: "docked")
        relaunch(UITestFixtures.ambushLaunchArguments + ["-PMAppearance", "light"])
        waitFor(AXID.Encounter.view)
        shootMenus(suffix: "encounter")
    }

    // MARK: UI-KEYS-032, UI-KEYS-035 window

    @MainActor
    func testGlassAndWindow() throws {
        for appearance in ["light", "dark"] {
            relaunch(UITestFixtures.launchArguments + ["-PMAppearance", appearance])
            startQuickStart()
            if !element(AXID.Inspector.root).exists { click(AXID.Toolbar.inspector) }
            shoot("qa-manual-glass-main-\(appearance)", mainWindow)
            type("7")
            waitFor(AXID.Galaxy.section.map)
            shoot("qa-manual-glass-galaxy-hud-\(appearance)", mainWindow)
            relaunch(UITestFixtures.ambushLaunchArguments + ["-PMAppearance", appearance])
            waitFor(AXID.Encounter.view)
            shoot("qa-manual-glass-encounter-bar-\(appearance)", mainWindow)
        }

        // The minimum size holds when the window is dragged smaller, and Warp stays in the narrowest toolbar.
        relaunch(UITestFixtures.launchArguments + ["-PMAppearance", "light", "-PMWindowSize", "min"])
        startQuickStart()
        if !element(AXID.Inspector.root).exists { click(AXID.Toolbar.inspector) }
        let corner = mainWindow.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: -3, dy: -3))
        corner.press(forDuration: 0.3, thenDragTo: corner.withOffset(CGVector(dx: -400, dy: -300)))
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        let frame = mainWindow.frame
        XCTAssertGreaterThanOrEqual(frame.width, 1100, "UI-KEYS-035: the window keeps its 1100 pt minimum width")
        XCTAssertGreaterThanOrEqual(frame.height, 720, "UI-KEYS-035: the window keeps its 720 pt minimum height")
        XCTAssertTrue(element(AXID.Toolbar.warp).isHittable, "UI-KEYS-032: Warp stays in the toolbar at the minimum width")
        shoot("qa-manual-window-minimum", mainWindow)

        // Full Screen keeps the sidebar, the toolbar and the inspector.
        // The window's green button (⌃⌘F is not delivered to the app by XCUITest's synthesized keys).
        let fullScreenButton = mainWindow.buttons[XCUIIdentifierFullScreenWindow]
        XCTAssertTrue(fullScreenButton.waitForExistence(timeout: timeout), "the window has a full-screen button")
        fullScreenButton.click()
        expect("the window enters Full Screen") { self.mainWindow.frame.width > frame.width + 50 }
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        XCTAssertTrue(element(AXID.Sidebar.list).exists, "Full Screen keeps the sidebar")
        XCTAssertTrue(element(AXID.Toolbar.warp).exists, "Full Screen keeps the toolbar")
        XCTAssertTrue(element(AXID.Inspector.root).exists, "Full Screen keeps the inspector")
        shoot("qa-manual-window-fullscreen", nil)

        // ⌘W closes the window (still in Full Screen) and the app keeps running (UI-SHELL-015).
        type("w")
        expect("⌘W closes the main window") { !self.mainWindow.exists }
        XCTAssertNotEqual(app.state, .notRunning, "UI-SHELL-015: the app keeps running after ⌘W")
        XCTAssertTrue(app.menuBars.firstMatch.exists, "the menu bar stays")
    }

    // MARK: A11Y-020, A11Y-022

    @MainActor
    func testDisplaySettingsAndColourIndependence() throws {
        let modes: [(name: String, list: String)] = [
            ("a11y020", "reduceTransparency,increaseContrast"),
            ("dwc", "differentiateWithoutColor"),
        ]
        for mode in modes {
            for appearance in ["light", "dark"] {
                let extra = ["-PMAppearance", appearance, "-PMA11y", mode.list]
                relaunch(UITestFixtures.launchArguments + extra)
                startQuickStart()
                if !element(AXID.Inspector.root).exists { click(AXID.Toolbar.inspector) }
                let tag = "qa-manual-\(mode.name)-\(appearance)"
                type("1")
                click(AXID.Bridge.targetNext)
                shoot("\(tag)-bridge", mainWindow)
                type("2")
                waitFor(AXID.Market.table)
                element(AXID.Market.row("water")).click()
                shoot("\(tag)-market", mainWindow)
                type("7")
                let g = AXID.Galaxy.section
                waitFor(g.map)
                if !element(g.legend).exists { click(g.legendToggle) }
                chooseMenuItem("Game", "Plot Route…")
                waitFor(g.routePanel)
                shoot("\(tag)-galaxy", mainWindow)
                relaunch(UITestFixtures.ambushLaunchArguments + extra)
                waitFor(AXID.Encounter.view)
                click(AXID.Encounter.attack)
                waitFor(AXID.Encounter.logRow(1))
                shoot("\(tag)-encounter", mainWindow)
            }
        }
    }

    // MARK: Helpers

    private func startQuickStart() {
        click(AXID.Welcome.quickStart)
        expect("the Quick Start game runs") { self.subtitle.hasPrefix("Day 0") }
    }

    private func shootMenus(suffix: String) {
        let bar = app.menuBars.firstMatch
        let items = bar.menuBarItems.allElementsBoundByIndex
        // Index 0 is the Apple menu, which the app does not own.
        for item in items.dropFirst() {
            let title = item.title
            guard !title.isEmpty else { continue }
            item.click()
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            // Only the open menu, so the capture holds no other app or desktop content.
            let menu = item.menus.firstMatch
            if menu.waitForExistence(timeout: 2) {
                shoot("qa-manual-menu-\(suffix)-\(Self.slug(title))", menu)
            } else {
                XCTFail("UI-KEYS-011: the \(title) menu opens")
            }
            type(XCUIKeyboardKey.escape.rawValue, [])
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
    }

    private static func slug(_ s: String) -> String {
        s.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }.reduce(into: "") { $0.append($1) }
    }

    /// A screenshot of `element`, or of the whole screen (Full Screen, where only the app shows) when nil.
    private func shoot(_ name: String, _ element: XCUIElement?) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        let shot = element?.screenshot() ?? XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: shot)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
