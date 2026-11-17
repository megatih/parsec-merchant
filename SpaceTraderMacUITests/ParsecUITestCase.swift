// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

/// Shared launch and lookup helpers for the M7 flows (UI-SHELL §17). Every test launches a fresh process with
/// `-PMResetState`, so no test sees another test's saves or settings.
@MainActor
class ParsecUITestCase: XCTestCase {
    var app: XCUIApplication!
    let timeout: TimeInterval = 10
    /// The `-PMSeed` of this test class (flow 5 uses its own seed).
    var launchSeed: UInt64 { UITestFixtures.flowSeed }

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = UITestFixtures.launchArguments(seed: launchSeed)
        app.launch()
        XCTAssertTrue(mainWindow.waitForExistence(timeout: timeout), "the main window opens at launch")
    }

    override func tearDown() async throws {
        app?.terminate()
        app = nil
    }

    // MARK: Lookup

    var mainWindow: XCUIElement { app.windows.matching(identifier: "main").firstMatch }

    /// The element whose accessibility identifier is exactly `id` (labels and titles never match).
    func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", id)).firstMatch
    }

    /// Waits for the element with `id` and returns it.
    @discardableResult
    func waitFor(_ id: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let e = element(id)
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "\(id) appears", file: file, line: line)
        return e
    }

    func click(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        waitFor(id, file: file, line: line).click()
    }

    /// Waits until `condition` holds (polling the UI); fails with `message` otherwise.
    func expect(_ message: @autoclosure () -> String, file: StaticString = #filePath, line: UInt = #line,
                _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertTrue(condition(), message(), file: file, line: line)
    }

    /// The window title as Accessibility reports it: "<title> – <subtitle>" (UI-SHELL-042).
    var windowTitle: String { mainWindow.title }

    /// The subtitle part of the title ("Day 0 · Castor · Credits 1,000 · Debt 0").
    var subtitle: String {
        let t = windowTitle
        guard let r = t.range(of: " – ") else { return "" }
        return String(t[r.upperBound...])
    }

    /// Text of a static text or button: its value when it has one, otherwise its label.
    func text(of e: XCUIElement) -> String {
        if let v = e.value as? String, !v.isEmpty { return v }
        return e.label
    }

    /// A checkbox/switch value as a Bool.
    func isOn(_ e: XCUIElement) -> Bool {
        if let n = e.value as? NSNumber { return n.boolValue }
        if let s = e.value as? String { return s == "1" || s.lowercased() == "on" }
        return false
    }

    /// Scrolls the scroll view around `e` until `e` can be clicked (macOS UI tests do not scroll on their own).
    @discardableResult
    func reveal(_ e: XCUIElement, in scrollView: XCUIElement, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        // Rows of a grouped Form that are scrolled out report an infinite frame until they are shown.
        func visible() -> Bool { scrollView.frame.contains(e.frame) }
        for _ in 0..<20 where !visible() {
            scrollView.scroll(byDeltaX: 0, deltaY: -120)
        }
        XCTAssertTrue(visible(), "\(e.identifier) is scrolled into view", file: file, line: line)
        return e
    }

    func type(_ key: String, _ modifiers: XCUIElement.KeyModifierFlags = .command) {
        app.typeKey(key, modifierFlags: modifiers)
    }

    // MARK: Menus (MENU-008: SwiftUI menu items expose no identifier on macOS, so items are found by English title)

    func menuItem(_ menu: String, _ title: String) -> XCUIElement {
        app.menuBars.menuBarItems[menu].menus.menuItems[title]
    }

    /// Opens `menu`, reads whether `title` is enabled, and closes the menu again.
    func isMenuItemEnabled(_ menu: String, _ title: String) -> Bool {
        app.menuBars.menuBarItems[menu].click()
        let item = menuItem(menu, title)
        XCTAssertTrue(item.waitForExistence(timeout: timeout), "\(menu) › \(title) exists")
        let enabled = item.isEnabled
        type(XCUIKeyboardKey.escape.rawValue, [])
        return enabled
    }

    func chooseMenuItem(_ menu: String, _ title: String, file: StaticString = #filePath, line: UInt = #line) {
        app.menuBars.menuBarItems[menu].click()
        let item = menuItem(menu, title)
        XCTAssertTrue(item.waitForExistence(timeout: timeout), "\(menu) › \(title) exists", file: file, line: line)
        item.click()
    }

    // MARK: Flows

    /// UI-SHELL-124 steps up to Start: name, Normal, Modern, Balanced, galaxy code check, Start.
    func startFlowGame(file: StaticString = #filePath, line: UInt = #line) {
        click(AXID.Welcome.newGame, file: file, line: line)
        let name = waitFor(AXID.NewGame.name, file: file, line: line)
        name.click()
        type("a")
        name.typeText(UITestFixtures.commanderName)
        click(AXID.NewGame.next, file: file, line: line)
        let normal = waitFor(AXID.NewGame.difficultyNormal, file: file, line: line)
        XCTAssertTrue(normal.isSelected, "Normal is the default difficulty", file: file, line: line)
        click(AXID.NewGame.next, file: file, line: line)
        let modern = waitFor(AXID.NewGame.rulesetModern, file: file, line: line)
        XCTAssertTrue(modern.isSelected, "Modern is the default ruleset", file: file, line: line)
        click(AXID.NewGame.next, file: file, line: line)
        click(AXID.NewGame.balanced, file: file, line: line)
        click(AXID.NewGame.next, file: file, line: line)
        let code = waitFor(AXID.NewGame.galaxyCode, file: file, line: line)
        XCTAssertEqual(code.value as? String, UITestFixtures.flowGalaxyCode, "the galaxy code of the flow seed",
                       file: file, line: line)
        click(AXID.NewGame.next, file: file, line: line)
        click(AXID.NewGame.start, file: file, line: line)
        expect("the game starts on day 0", file: file, line: line) { subtitle.hasPrefix("Day 0") }
    }

    /// Selects the next target on the Bridge and warps with ⌘J; returns the target's name.
    func warpToNextTarget(file: StaticString = #filePath, line: UInt = #line) -> String {
        type("1")
        click(AXID.Bridge.targetNext, file: file, line: line)
        let target = waitFor(AXID.Toolbar.target, file: file, line: line)
        var name = ""
        expect("a target is selected", file: file, line: line) {
            name = target.title.components(separatedBy: " · ").first ?? ""
            return !name.isEmpty && name != "Choose Target"
        }
        type("j")
        expect("the warp ends docked at \(name) on day 1 (subtitle: \(subtitle))", file: file, line: line) {
            subtitle.hasPrefix("Day 1 · \(name) · ")
        }
        return name
    }

    /// "Day 0 · Castor · Credits 1,000 · Debt 0" → "Castor".
    func systemInSubtitle() -> String {
        let parts = subtitle.components(separatedBy: " · ")
        return parts.count > 1 ? parts[1] : ""
    }
}
