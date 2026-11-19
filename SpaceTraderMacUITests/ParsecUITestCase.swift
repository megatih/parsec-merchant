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
    /// The launch arguments of this test class (flow 2 launches a `-PMScenario` instead of a seed).
    var launchArguments: [String] { UITestFixtures.launchArguments(seed: launchSeed) }

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = Self.withTipsOff(launchArguments)
        app.launch()
        XCTAssertTrue(mainWindow.waitForExistence(timeout: timeout), "the main window opens at launch")
    }

    /// Terminates the app and launches it again with `arguments` (for tests that walk several scenarios).
    func relaunch(_ arguments: [String], file: StaticString = #filePath, line: UInt = #line) {
        app.terminate()
        app.launchArguments = Self.withTipsOff(arguments)
        app.launch()
        XCTAssertTrue(mainWindow.waitForExistence(timeout: timeout), "the main window opens at launch", file: file, line: line)
    }

    /// A11Y-047: every launch hides all tips (`-PMTips off`) unless the arguments choose a tips mode themselves; and it
    /// ignores saved window state, so a window or frame restored from another run never covers or moves the main window.
    static func withTipsOff(_ arguments: [String]) -> [String] {
        var a = arguments.contains("-PMTips") ? arguments : arguments + ["-PMTips", "off"]
        // No restored windows (a Galaxy Chart or High Scores window left open by another run would cover the main window).
        if !a.contains("-ApplePersistenceIgnoreState") { a += ["-ApplePersistenceIgnoreState", "YES"] }
        return a
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

    /// The window title as Accessibility reports it: "<title> – <subtitle>" (UI-SHELL-042, UI-NAV-007).
    var windowTitle: String { mainWindow.title }

    /// The game's status line, read from the status bar ("Day 0 · Castor · Credits 1,000 · Debt 0" docked, "Day 0 · In
    /// transit to Rhymus" under way). Until release 2.0 this was the window's subtitle; the name stays for the tests.
    var subtitle: String {
        let location = element("status.location")
        guard location.exists else { return "" }
        let parts = text(of: location).components(separatedBy: " · ")  // "Castor · Day 0", "To Rhymus, 7 clicks · Day 0"
        guard parts.count == 2 else { return "" }
        func amount(_ id: String) -> String {
            let e = element(id)
            return e.exists ? text(of: e).replacingOccurrences(of: " cr.", with: "") : "0"
        }
        if element("transit.view").exists || element("encounter.view").exists {
            let destination = parts[0].components(separatedBy: ", ").first.map { $0.hasPrefix("To ") ? String($0.dropFirst(3)) : $0 } ?? ""
            return "\(parts[1]) · In transit to \(destination)"
        }
        return "\(parts[1]) · \(parts[0]) · Credits \(amount("status.cash")) · Debt \(amount("status.debt"))"
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

    /// The ⌘-digit of each page in dock order (release 2.0). The 1.x Market page has no shortcut until the Bridge's
    /// Cargo region replaces it.
    /// ⌥⌘O opens the Options page.
    func openOptionsPage(file: StaticString = #filePath, line: UInt = #line) {
        type("o", [.command, .option])
        waitFor(AXID.Options.root, file: file, line: line)
    }

    static let pageKeys = ["bridge": "1", "shipyard": "2", "outfitter": "3", "crew": "4", "bank": "5", "status": "6", "quests": "7", "galaxy": "8",
                           "logbook": "9"]

    /// Opens a page by its shortcut, or by its dock button when it has none.
    func openPage(_ name: String) {
        if let key = Self.pageKeys[name] {
            type(key)
        } else {
            element(AXID.Dock.button(name)).click()
        }
    }

    /// The selected target's name: from the Galaxy page's target strip ("Target: Rhymus · 8 parsecs") or from the
    /// Bridge's target card; empty when there is none or neither is on screen.
    var targetName: String {
        let strip = element("galaxy.target")
        if strip.exists {
            let t = text(of: strip)
            return t.hasPrefix("Target: ") ? String(t.dropFirst(8)) : ""
        }
        let name = element(AXID.Bridge.targetName)
        return name.exists ? text(of: name) : ""
    }

    // MARK: Menus (MENU-008: SwiftUI menu items expose no identifier on macOS, so items are found by English title)

    /// A11Y-040: set while a pseudolanguage runs. English titles then also match their pseudo forms (doubled
    /// "Game Game", or accented and bounded "[# G̈a̧m̧ë #]", matched diacritic-insensitively), since menu items and
    /// segments have no identifier.
    var pseudoLocalized = false

    /// The title predicate of an English title: exact, plus its pseudo forms under `pseudoLocalized`.
    func titlePredicate(_ english: String) -> NSPredicate {
        guard pseudoLocalized else { return NSPredicate(format: "title == %@ OR label == %@", english, english) }
        let forms = [english, "\(english) \(english)", "[# \(english) #]"]
        return NSCompoundPredicate(orPredicateWithSubpredicates: forms.flatMap {
            [NSPredicate(format: "title ==[d] %@", $0), NSPredicate(format: "label ==[d] %@", $0)]
        })
    }

    /// Text with the pseudolanguage decoration removed: diacritics folded, the "[# … #]" bounds dropped.
    static func plainText(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: nil).replacingOccurrences(of: "[# ", with: "")
            .replacingOccurrences(of: " #]", with: "")
    }

    /// Whether the Quick Start game runs (the subtitle starts "Day 0"; doubled or accented under a pseudolanguage).
    var quickStartRuns: Bool {
        // Under a pseudolanguage the words are doubled, accented or reordered: the game runs when its Bridge is on screen.
        pseudoLocalized ? element("bridge.root").exists : subtitle.hasPrefix("Day 0")
    }

    func menuBarItem(_ menu: String) -> XCUIElement {
        pseudoLocalized ? app.menuBars.menuBarItems.matching(titlePredicate(menu)).firstMatch : app.menuBars.menuBarItems[menu]
    }

    func menuItem(_ menu: String, _ title: String) -> XCUIElement {
        pseudoLocalized ? menuBarItem(menu).menus.menuItems.matching(titlePredicate(title)).firstMatch
            : app.menuBars.menuBarItems[menu].menus.menuItems[title]
    }

    /// Opens `menu`, reads whether `title` is enabled, and closes the menu again.
    func isMenuItemEnabled(_ menu: String, _ title: String) -> Bool {
        menuBarItem(menu).click()
        let item = menuItem(menu, title)
        XCTAssertTrue(item.waitForExistence(timeout: timeout), "\(menu) › \(title) exists")
        let enabled = item.isEnabled
        type(XCUIKeyboardKey.escape.rawValue, [])
        return enabled
    }

    func chooseMenuItem(_ menu: String, _ title: String, file: StaticString = #filePath, line: UInt = #line) {
        menuBarItem(menu).click()
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
        openPage("bridge")
        click(AXID.Bridge.targetNext, file: file, line: line)
        var name = ""
        expect("a target is selected", file: file, line: line) {
            name = targetName
            return !name.isEmpty
        }
        type("j")
        expect("the warp ends docked at \(name) on day 1 (subtitle: \(subtitle))", file: file, line: line) {
            subtitle.hasPrefix("Day 1 · \(name) · ")
        }
        // UI-ENC-095: the playback is instant with -PMFastTravel, and the uneventful arrival shows its summary in the
        // status bar; a trip always ends on the Bridge (UI-NAV-004).
        XCTAssertFalse(element(AXID.Transit.view).exists, "no transit playback with -PMFastTravel", file: file, line: line)
        waitFor(AXID.Arrival.card, file: file, line: line)
        XCTAssertTrue(element("bridge.root").exists, "the arrival keeps the Bridge selected", file: file, line: line)
        return name
    }

    /// UI-BRG-042: opens the arrival report from the summary in the status bar's message slot.
    @discardableResult
    func openArrivalReport(file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        if !element(AXID.Report.sheet).exists { click(AXID.Arrival.card, file: file, line: line) }
        return waitFor(AXID.Report.sheet, file: file, line: line)
    }

    func closeArrivalReport(file: StaticString = #filePath, line: UInt = #line) {
        click(AXID.Report.continueButton, file: file, line: line)
        expect("the report closes", file: file, line: line) { !self.element(AXID.Report.sheet).exists }
    }

    /// "Day 0 · Castor · Credits 1,000 · Debt 0" → "Castor".
    func systemInSubtitle() -> String {
        let parts = subtitle.components(separatedBy: " · ")
        return parts.count > 1 ? parts[1] : ""
    }
}
