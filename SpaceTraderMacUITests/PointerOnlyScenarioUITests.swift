// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

/// UI-PTR-019: the game played with the pointer alone: clicks only, no key and no modifier after launch.
final class PointerOnlyScenarioUITests: ParsecUITestCase {
    override var launchSeed: UInt64 { UITestFixtures.mapFlowSeed }

    private let g = AXID.Galaxy.section

    /// The number in a Held cell ("5", or "5, avg 38 cr.").
    private func held(_ item: String) -> Int {
        let digits = text(of: element(AXID.Cargo.held(item))).prefix { $0.isNumber }
        return Int(digits) ?? -1
    }

    private func clickSidebar(_ id: String, root: String, file: StaticString = #filePath, line: UInt = #line) {
        element(id).click()
        waitFor(root, file: file, line: line)
    }

    @MainActor
    func testTradeTravelFightAndSellWithClicksOnly() throws {
        // covers: UI-PTR-019, UI-PTR-007, UI-PTR-011, UI-PTR-014, UI-PTR-001
        // 1. A new game.
        click(AXID.Welcome.quickStart)
        expect("the Quick Start game runs") { subtitle.hasPrefix("Day 0") }
        let origin = systemInSubtitle()

        // 2. Buy cargo on the Bridge: each click on Buy buys the row's quantity (1 while the field is empty).
        waitFor(AXID.Cargo.panel)
        for n in 1...6 {
            click(AXID.Cargo.buy("water"))
            expect("\(n) units of water are held (held: \(held("water")))") { held("water") == n }
        }
        // UI-PTR-007: the whole row of actions is on screen inside the Cargo panel.
        let all = element(AXID.Cargo.all("water")), table = element(AXID.Cargo.panel)
        expect("the row's last button fits inside the panel (\(all.frame) in \(table.frame))") {
            all.frame.minX >= table.frame.minX && all.frame.maxX <= table.frame.maxX
        }

        // 3. Pick a target on the map: a click selects into the panel, whose buttons need no modifier.
        clickSidebar(AXID.Galaxy.sidebarRow, root: AXID.Galaxy.root)
        let system = waitFor(g.system(UITestFixtures.mapFlowTarget))
        let target = system.label.components(separatedBy: ", ").first ?? ""
        XCTAssertFalse(target.isEmpty, system.label)
        system.click()
        waitFor(g.selectionCard)
        waitFor(g.selectionTrack)
        waitFor(g.selectionPlotRoute)
        click(g.selectionSetTarget)
        expect("the click set the target to \(target)") {
            targetName.hasPrefix(target)
        }
        let shot = XCTAttachment(screenshot: mainWindow.screenshot())
        shot.name = "pointer-selection-card"
        shot.lifetime = .keepAlways
        add(shot)

        // 4. Warp with the map's own Warp button.
        click(g.warp)
        expect("the warp ends docked at \(target) on day 1 (subtitle: \(subtitle))") { subtitle.hasPrefix("Day 1 · \(target) · ") }
        XCTAssertNotEqual(target, origin)

        // 5. Sell everything with one click on All (the trip ended on the Bridge, UI-NAV-004).
        waitFor(AXID.Cargo.panel)
        expect("the cargo arrived (held: \(held("water")))") { held("water") == 6 }
        click(AXID.Cargo.all("water"))
        expect("the hold is empty again (held: \(held("water")))") { held("water") == 0 }

        // 6. An encounter, resolved with its buttons alone.
        relaunch(UITestFixtures.ambushLaunchArguments)
        let view = waitFor(AXID.Encounter.view)
        var attacks = 0
        while view.exists, attacks < UITestFixtures.ambushMaxAttacks {
            let attack = element(AXID.Encounter.attack)
            if attack.exists, attack.isEnabled {
                attack.click()
                attacks += 1
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        expect("the encounter ends within \(UITestFixtures.ambushMaxAttacks) clicks on Attack") { !view.exists }
        waitFor(AXID.Arrival.card)
        expect("docked on day 1 (subtitle: \(subtitle))") { subtitle.hasPrefix("Day 1 · ") }
    }

    /// The scenario is pointer-only by construction: this file sends no key.
    func testThisScenarioSendsNoKeys() throws {
        // covers: UI-PTR-019
        let source = try String(contentsOfFile: #filePath, encoding: .utf8)
        let body = source.components(separatedBy: "func testThisScenarioSendsNoKeys").first ?? ""
        for banned in ["typeKey(", "typeText(", "type(\"", ".keyModifiers", "XCUIElement.perform(withKeyModifiers"] {
            XCTAssertFalse(body.contains(banned), "the pointer-only scenario uses \(banned)")
        }
    }
}
