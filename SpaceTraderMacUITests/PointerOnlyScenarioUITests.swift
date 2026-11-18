// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

/// UI-PTR-019: the game played with the pointer alone: clicks only, no key and no modifier after launch.
final class PointerOnlyScenarioUITests: ParsecUITestCase {
    override var launchSeed: UInt64 { UITestFixtures.mapFlowSeed }

    private let g = AXID.Galaxy.section

    /// The number in a Held cell ("5", or "5, avg 38 cr.").
    private func held(_ item: String) -> Int {
        let digits = text(of: element(AXID.Market.held(item))).prefix { $0.isNumber }
        return Int(digits) ?? -1
    }

    private func clickSidebar(_ id: String, root: String, file: StaticString = #filePath, line: UInt = #line) {
        element(id).staticTexts.firstMatch.click()
        waitFor(root, file: file, line: line)
    }

    @MainActor
    func testTradeTravelFightAndSellWithClicksOnly() throws {
        // covers: UI-PTR-019, UI-PTR-007, UI-PTR-011, UI-PTR-014, UI-PTR-001
        // 1. A new game.
        click(AXID.Welcome.quickStart)
        expect("the Quick Start game runs") { subtitle.hasPrefix("Day 0") }
        let origin = systemInSubtitle()

        // 2. Buy cargo with chips: 5 units of water in two clicks.
        clickSidebar(AXID.Sidebar.market, root: AXID.Market.table)
        click(AXID.Market.chip("water", "5"))
        click(AXID.Market.buy("water"))
        expect("5 units of water are held (held: \(held("water")))") { held("water") == 5 }
        // One more with the 1 chip.
        click(AXID.Market.chip("water", "1"))
        click(AXID.Market.buy("water"))
        expect("6 units of water are held (held: \(held("water")))") { held("water") == 6 }

        // 3. Pick a target on the map: a click pins the selection card, whose buttons need no modifier.
        clickSidebar(AXID.Galaxy.sidebarRow, root: AXID.Galaxy.root)
        let system = waitFor(g.system(UITestFixtures.mapFlowTarget))
        let target = system.label.components(separatedBy: ", ").first ?? ""
        XCTAssertFalse(target.isEmpty, system.label)
        system.click()
        waitFor(g.selectionCard)
        waitFor(g.selectionTrack)
        waitFor(g.selectionPlotRoute)
        expect("the click set the target to \(target)") {
            let t = element(AXID.Toolbar.target)
            return (t.title.isEmpty ? t.label : t.title).hasPrefix(target)
        }
        let shot = XCTAttachment(screenshot: mainWindow.screenshot())
        shot.name = "pointer-selection-card"
        shot.lifetime = .keepAlways
        add(shot)

        // 4. Warp with the map's own Warp button.
        click(g.warp)
        expect("the warp ends docked at \(target) on day 1 (subtitle: \(subtitle))") { subtitle.hasPrefix("Day 1 · \(target) · ") }
        XCTAssertNotEqual(target, origin)

        // 5. Sell everything: the Max chip, then Sell.
        clickSidebar(AXID.Sidebar.market, root: AXID.Market.table)
        expect("the cargo arrived (held: \(held("water")))") { held("water") == 6 }
        click(AXID.Market.chip("water", "max"))
        click(AXID.Market.sell("water"))
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
