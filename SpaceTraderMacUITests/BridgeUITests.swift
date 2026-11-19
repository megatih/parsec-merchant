// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

/// UI-BRG-033, UI-BRG-036, UI-BRG-040: the Bridge in the real window: everything is on screen and clickable at the
/// minimum size and above, nothing scrolls, the window cannot be made smaller, and the core loop needs no other page.
final class BridgeUITests: ParsecUITestCase {
    override var launchSeed: UInt64 { UITestFixtures.mapFlowSeed }

    /// Every identified element below the main window: identifier → frame.
    private func frames() throws -> [String: CGRect] {
        var out: [String: CGRect] = [:]
        func visit(_ e: XCUIElementSnapshot) {
            if e.identifier.hasPrefix("bridge."), out[e.identifier] == nil { out[e.identifier] = e.frame }
            e.children.forEach(visit)
        }
        visit(try mainWindow.snapshot())
        return out
    }

    /// The assertions of UI-BRG-033 for the window as it is.
    private func assertBridgeFits(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws {
        waitFor(AXID.Bridge.root, file: file, line: line)
        let window = mainWindow.frame.insetBy(dx: -1, dy: -1)
        let found = try frames()
        for id in AXID.Bridge.manifest {
            guard let frame = found[id] else {
                XCTFail("\(name): \(id) is missing", file: file, line: line)
                continue
            }
            XCTAssertTrue(frame.width > 0 && frame.height > 0 && window.contains(frame), "\(name): \(id) \(frame) is inside the window \(window)",
                          file: file, line: line)
        }
        for id in AXID.Bridge.buttons {
            let button = element(id)
            // A disabled button is still in view: its frame is checked above; hit-testing needs it enabled.
            if button.isEnabled { XCTAssertTrue(button.isHittable, "\(name): \(id) can be clicked", file: file, line: line) }
        }
        XCTAssertEqual(mainWindow.scrollViews.count, 0, "\(name): nothing on the Bridge scrolls", file: file, line: line)
        let shot = XCTAttachment(screenshot: mainWindow.screenshot())
        shot.name = "bridge-fit-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func startGame(_ extra: [String]) {
        relaunch(UITestFixtures.launchArguments(seed: UITestFixtures.mapFlowSeed) + extra)
        click(AXID.Welcome.quickStart)
        expect("the Quick Start game runs") { self.subtitle.hasPrefix("Day 0") }
    }

    @MainActor
    func testTheBridgeFitsAtTheMinimumSizeAndAbove() throws {
        // covers: UI-BRG-033, UI-BRG-001, UI-BRG-031, UI-BRG-035, UI-DS-001
        startGame(["-PMWindowSize", "min"])
        let size = mainWindow.frame.size
        XCTAssertEqual(size.width, 1200, accuracy: 1, "-PMWindowSize min opens at the 1200 pt minimum (got \(size))")
        try assertBridgeFits("1200x680")
        let small = Set(try frames().keys)

        startGame(["-PMWindowPoints", "1728x1050"])
        XCTAssertEqual(mainWindow.frame.width, 1728, accuracy: 1)
        try assertBridgeFits("1728x1050")
        XCTAssertEqual(Set(try frames().keys), small, "UI-BRG-035: the same elements at both sizes")

        // Text Size Large: the minimum window grows to 1380 × 782 and the Bridge still fits.
        startGame(["-PMWindowSize", "min", "-settings.textSize", "xxLarge"])
        XCTAssertGreaterThanOrEqual(mainWindow.frame.width, 1379, "the minimum follows the Text Size (got \(mainWindow.frame.size))")
        try assertBridgeFits("large-text")
    }

    @MainActor
    func testTheWindowCannotBeMadeSmallerThanTheMinimum() throws {
        // covers: UI-BRG-036, UI-DS-001, UI-KEYS-035
        startGame(["-PMWindowPoints", "1400x800"])
        let before = mainWindow.frame
        XCTAssertEqual(before.width, 1400, accuracy: 1)
        // Drag the bottom-right corner far up and to the left (the resize area reaches a few points around the corner).
        let target = mainWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.2))
        for offset in [CGVector(dx: 1, dy: 1), CGVector(dx: -3, dy: -3), CGVector(dx: 3, dy: 3)] where mainWindow.frame.width > before.width - 50 {
            let corner = mainWindow.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(offset)
            corner.click(forDuration: 0.4, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        let after = mainWindow.frame
        XCTAssertLessThan(after.width, before.width - 50, "the drag resized the window (\(before.size) → \(after.size))")
        XCTAssertEqual(after.width, 1200, accuracy: 1, "the window stops at its 1200 pt minimum width")
        // The frame includes the title bar; the content is 680 pt high.
        XCTAssertGreaterThanOrEqual(after.height, 680)
        XCTAssertLessThanOrEqual(after.height, 680 + 60)
        try assertBridgeFits("after-resize")
    }

    /// The first enabled in-range system of the Short-Range Chart that is not the current target.
    private func chartSystem(excluding: String) -> XCUIElement? {
        let systems = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "bridge.miniChart.system."))
        // The state ("target, in range") is the element's value (MAP-080).
        for e in systems.allElementsBoundByIndex {
            let state = (e.value as? String) ?? ""
            if state.contains("in range"), !state.contains("out of range"), !e.label.hasPrefix(excluding) { return e }
        }
        return nil
    }

    @MainActor
    func testTheCoreLoopNeedsOnlyTheBridge() throws {
        // covers: UI-BRG-040, UI-BRG-004, UI-BRG-005, UI-BRG-011, UI-BRG-022, UI-NAV-004
        startGame([])
        // Setup (not counted): fill the hold and make one trip, so there is cargo to sell and fuel to buy.
        click(AXID.Cargo.max("water"))
        expect("the hold has water") { (Int(self.text(of: self.element(AXID.Cargo.held("water")))) ?? 0) > 0 }
        try XCTUnwrap(chartSystem(excluding: "~"), "an in-range system on the chart").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        click(AXID.Bridge.targetWarp)
        expect("the trip ends docked on day 1 (subtitle: \(subtitle))") { self.subtitle.hasPrefix("Day 1 · ") }
        waitFor(AXID.Bridge.root)

        // The loop: sell everything, buy, refuel, compare two destinations, leave. Six clicks, one page.
        var clicks = 0
        func bridgeClick(_ id: String) {
            XCTAssertTrue(element(AXID.Bridge.root).exists, "still on the Bridge before \(id)")
            click(id)
            clicks += 1
        }
        bridgeClick(AXID.Cargo.sellAll)
        expect("the hold is empty") { self.text(of: self.element(AXID.Cargo.held("water"))) == "0" }
        let item = try XCTUnwrap(AXID.Cargo.items.first { self.element(AXID.Cargo.max($0)).isEnabled }, "a good to buy")
        bridgeClick(AXID.Cargo.max(item))
        expect("the hold has \(item)") { (Int(self.text(of: self.element(AXID.Cargo.held(item)))) ?? 0) > 0 }
        bridgeClick(AXID.Bridge.fillTank)
        expect("the tank is full: Fill Tank is disabled") { !self.element(AXID.Bridge.fillTank).isEnabled }
        let first = try XCTUnwrap(chartSystem(excluding: "~"), "an in-range system on the chart")
        let firstName = first.label.components(separatedBy: ", ").first ?? ""
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        clicks += 1
        expect("the Target panel shows \(firstName)") { self.targetName == firstName }
        let firstQuote = text(of: element(AXID.Cargo.target(item)))
        XCTAssertFalse(firstQuote.isEmpty, "the Target cell of \(item) shows the target's price or a dash")
        let second = try XCTUnwrap(chartSystem(excluding: firstName), "a second in-range system")
        let secondName = second.label.components(separatedBy: ", ").first ?? ""
        second.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        clicks += 1
        expect("the Target panel shows \(secondName)") { self.targetName == secondName }
        XCTAssertTrue(element(AXID.Bridge.root).exists, "comparing destinations never left the Bridge")
        bridgeClick(AXID.Bridge.targetWarp)
        expect("the warp ends docked at \(secondName) on day 2 (subtitle: \(subtitle))") { self.subtitle.hasPrefix("Day 2 · \(secondName) · ") }
        XCTAssertLessThanOrEqual(clicks, 6, "the core loop takes at most six clicks")
        waitFor(AXID.Bridge.root)
    }
}
