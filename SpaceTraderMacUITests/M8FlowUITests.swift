// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

/// UI flow 5 and the M8 galaxy scenarios (MAP-101…103).
final class M8FlowUITests: ParsecUITestCase {
    override var launchSeed: UInt64 { UITestFixtures.mapFlowSeed }

    private let g = AXID.Galaxy.section

    /// Quick Start, then ⌘7.
    private func openGalaxy(file: StaticString = #filePath, line: UInt = #line) {
        click(AXID.Welcome.quickStart, file: file, line: line)
        expect("the Quick Start game runs", file: file, line: line) { subtitle.hasPrefix("Day 0") }
        openPage("galaxy")
        waitFor(AXID.Galaxy.root, file: file, line: line)
        waitFor(g.map, file: file, line: line)
    }

    /// "Rhymus, visited, 8 parsecs, …" → "Rhymus".
    private func name(of system: XCUIElement) -> String {
        system.label.components(separatedBy: ", ").first ?? ""
    }

    private func value(_ e: XCUIElement) -> String { (e.value as? String) ?? "" }

    /// Flow 5, Galaxy: hover, select, set target, warp with ⌘J.
    @MainActor
    func testFlow5GalaxyHoverSelectWarp() throws {
        // covers: MAP-101, MAP-044, MAP-081, MAP-075, UI-ENC-095
        openGalaxy()
        let row = element(AXID.Galaxy.sidebarRow)
        expect("sidebar.galaxy is selected") {
            row.isSelected || app.outlineRows.containing(.any, identifier: AXID.Galaxy.sidebarRow).firstMatch.isSelected
        }

        let system = waitFor(g.system(UITestFixtures.mapFlowTarget))
        let target = name(of: system)
        XCTAssertFalse(target.isEmpty, system.label)
        system.hover()
        let card = waitFor(g.hoverCard)
        let shot = XCTAttachment(screenshot: mainWindow.screenshot())
        shot.name = "galaxy-hover"
        shot.lifetime = .keepAlways
        add(shot)
        expect("the hover card names \(target) with a distance (card: \(card.label))") {
            let text = card.label + " " + value(card)
            return text.contains(target) && text.contains("parsecs")
        }

        // UI-PG-060: a click selects the system into the panel; its button sets the target.
        system.click()
        waitFor(g.selectionCard)
        click(g.selectionSetTarget)
        expect("the toolbar target shows \(target) (toolbar: \(targetName))") { targetName.hasPrefix(target) }
        expect("the system's value says target and in range (value: \(value(system)))") {
            value(system).contains("target") && value(system).contains("in range")
        }

        type("j")
        expect("the warp ends docked at \(target) on day 1 (subtitle: \(subtitle))") {
            subtitle.hasPrefix("Day 1 · \(target) · ")
        }
        // UI-NAV-004: a trip always ends on the Bridge, with its summary in the status bar (UI-BRG-042).
        XCTAssertFalse(element(AXID.Transit.view).exists, "no transit playback with -PMFastTravel")
        waitFor(AXID.Bridge.root)
        waitFor(AXID.Arrival.card)
        openPage("galaxy")
        expect("the system is now the current system") {
            element(g.system(UITestFixtures.mapFlowTarget)).label.contains("current system")
        }
    }

    /// Scenario: tracking and routes.
    @MainActor
    func testTrackingAndRoutes() throws {
        // covers: MAP-102, MAP-052, MAP-053, MAP-067, MAP-068, MAP-040
        openGalaxy()
        let far = waitFor(g.system(UITestFixtures.mapRouteDestination))
        let farName = name(of: far)
        far.hover()
        XCUIElement.perform(withKeyModifiers: .option) { far.click() }
        expect("the system is tracked (value: \(value(far)))") { value(far).contains("tracked") }
        expect("the tracked range shows") { text(of: element(g.trackedRange)).contains("parsecs to") }

        far.hover()
        far.rightClick()
        let byID = element(g.plotRoute)
        let item = byID.waitForExistence(timeout: 2) ? byID : app.menuItems["Plot Route to \(farName)"]
        XCTAssertTrue(item.waitForExistence(timeout: timeout), "the context menu offers Plot Route")
        item.click()
        waitFor(g.routePanel)
        expect("the route has at least two hops") { element(g.routeHop(2)).exists }
        let hop1 = text(of: element(g.routeHop(1)))
        let hop1Destination = destination(ofHopRow: hop1)
        expect("the toolbar target is hop 1's destination \(hop1Destination) (toolbar: \(targetName))") {
            !hop1Destination.isEmpty && targetName.hasPrefix(hop1Destination)
        }
        let hop2Destination = destination(ofHopRow: text(of: element(g.routeHop(2))))

        type("j")
        expect("arrived at \(hop1Destination) (subtitle: \(subtitle))") { subtitle.contains(" \(hop1Destination) ") }
        expect("the toolbar target is hop 2's destination \(hop2Destination) (toolbar: \(targetName))") {
            targetName.hasPrefix(hop2Destination)
        }
        openPage("galaxy")  // the trip ended on the Bridge (UI-NAV-004)
        click(g.routeClear)
        expect("the route panel disappears") { !element(g.routePanel).exists }
    }

    /// "1. Castor → Rhymus …" → "Rhymus".
    private func destination(ofHopRow text: String) -> String {
        guard let r = text.range(of: " → ") else { return "" }
        let rest = text[r.upperBound...]
        return String(rest.prefix { $0 != "," && $0 != "\n" }).trimmingCharacters(in: .whitespaces)
            .components(separatedBy: "  ").first ?? ""
    }

    /// Scenario: the Galaxy Chart window and its search.
    @MainActor
    func testWindowAndSearch() throws {
        // covers: MAP-103, MAP-070, MAP-073, MAP-076, MAP-077, MAP-016
        click(AXID.Welcome.quickStart)
        expect("the Quick Start game runs") { subtitle.hasPrefix("Day 0") }
        type("m", [.command, .shift])
        waitFor(AXID.Galaxy.windowRoot)
        let w = AXID.Galaxy.window
        let known = name(of: waitFor(w.system(UITestFixtures.mapFlowTarget)))
        let prefix = String(known.prefix(3))

        // UI-PG-061: ⌘F opens Find System, the one search.
        type("f")
        let field = waitFor("findSystem.field")
        field.click()
        field.typeText(prefix)
        field.typeText("\r")
        expect("the main window's target is a system matching \(prefix) (toolbar: \(targetName))") {
            let t = targetName.lowercased()
            return t != "choose target" && (t.components(separatedBy: " · ").first ?? "").contains(prefix.lowercased())
        }

        // The filters dim what does not match (MAP-074); the switch reports its state.
        func isOn(_ id: String) -> Bool {
            let value = element(id).value
            if let text = value as? String { return text == "On" || text == "1" }
            return (value as? NSNumber)?.boolValue ?? false
        }
        type("m", [.command, .shift])  // Find System belongs to the main window, which came forward: back to the chart's window
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        func settles(_ on: Bool) -> Bool {
            for _ in 0..<15 where isOn(w.filterInRange) != on { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
            return isOn(w.filterInRange) == on
        }
        click(w.filterInRange)
        if !settles(true) { click(w.filterInRange) }  // the first click may only bring the chart's window forward
        expect("the In range filter is on") { isOn(w.filterInRange) }
        click(w.filterInRange)
        expect("the In range filter is off") { !isOn(w.filterInRange) }

        click(w.zoomIn)
        click(w.zoomIn)
        expect("Zoom Out is enabled after zooming in") { element(w.zoomOut).isEnabled }
        click(w.fitGalaxy)
        expect("Zoom Out is disabled at Fit Galaxy") { !element(w.zoomOut).isEnabled }
    }
}
