// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

/// UI flow 2 (PRD §8.2): `-PMScenario pirateAmbush`, attack until the pirate is destroyed (UI-ENC-094).
final class M9FlowUITests: ParsecUITestCase {
    override var launchArguments: [String] { UITestFixtures.ambushLaunchArguments }

    /// Flow 2, steps 1…7 of UI-ENC-094.
    @MainActor
    func testFlow2PirateAmbushAttackUntilResolved() throws {
        // covers: UI-ENC-094, UI-ENC-093, UI-ENC-090
        // 1. The scenario warps into the ambush on its own.
        let view = waitFor(AXID.Encounter.view)

        // 2. Header, panes, actions, tactical readout and the locked sidebar.
        let badge = waitFor(AXID.Encounter.badge)
        XCTAssertEqual(badge.label, "Pirate")
        expect("encounter.intro mentions the pirate (intro: \(text(of: element(AXID.Encounter.intro))))") {
            text(of: element(AXID.Encounter.intro)).lowercased().contains("pirate")
        }
        for id in [AXID.Encounter.playerHull, AXID.Encounter.opponentHull] {
            let hull = waitFor(id)
            XCTAssertTrue(text(of: hull).contains("%"), "\(id) shows a percentage: \(text(of: hull))")
        }
        for id in [AXID.Encounter.attack, AXID.Encounter.flee, AXID.Encounter.surrender, AXID.Encounter.resolve] {
            waitFor(id)
        }
        let tactical = waitFor(AXID.Encounter.tactical)
        XCTAssertTrue(descendantText(of: tactical).contains("Flee"), "the readout shows flee odds: \(descendantText(of: tactical))")
        expect("sidebar.phaseLabel reads In encounter") { text(of: element(AXID.Dock.phaseLabel)) == "In encounter" }
        XCTAssertFalse(sidebarRow(AXID.Dock.button("bank")).isEnabled, "the Bank page is locked during the encounter")

        // 3. Encounter › Attack is enabled.
        XCTAssertTrue(isMenuItemEnabled("Encounter", "Attack"), "menu.encounter.attack is enabled")

        // 4. The key A attacks: the first log row is round 1, and the readout goes away.
        type("a", [])
        let row0 = waitFor(AXID.Encounter.logRow(0))
        expect("encounter.log.row.0 starts with R1 (row: \(text(of: row0)))") { text(of: row0).hasPrefix("R1") }
        expect("encounter.tactical disappears after the first action") { !element(AXID.Encounter.tactical).exists }

        // 5. Attack until the encounter ends.
        var attacks = 1
        while view.exists, attacks < UITestFixtures.ambushMaxAttacks {
            let attack = element(AXID.Encounter.attack)
            if attack.exists, attack.isEnabled {
                attack.click()
                attacks += 1
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }

        // 6. Docked at the target with the arrival card.
        expect("encounter.view disappears within \(UITestFixtures.ambushMaxAttacks) attacks") { !view.exists }
        let card = waitFor(AXID.Arrival.card)
        openArrivalReport()
        let summary = waitFor(AXID.Arrival.encounter(0))
        expect("arrival.encounter.0 says the pirate was destroyed (row: \(descendantText(of: summary)))") {
            descendantText(of: summary).contains("destroyed")
        }
        closeArrivalReport()
        XCTAssertTrue(card.exists)
        expect("the subtitle shows day 1 (subtitle: \(subtitle))") { subtitle.hasPrefix("Day 1 · ") }
        let target = systemInSubtitle()
        XCTAssertFalse(target.isEmpty, subtitle)
        openPage("galaxy")
        let system = waitFor(AXID.Galaxy.section.system(UITestFixtures.ambushTarget))
        expect("system \(UITestFixtures.ambushTarget) is the current system \(target) (label: \(system.label))") {
            system.label.hasPrefix("\(target),") && system.label.contains("current system")
        }
        openPage("bridge")
        waitFor(AXID.Arrival.card)

        // 7. The encounter commands are gone and the sections unlock.
        XCTAssertFalse(menuItemExistsAndEnabled("Encounter", "Attack"), "menu.encounter.attack is disabled or absent")
        expect("dock.bank is enabled again") { sidebarRow(AXID.Dock.button("bank")).isEnabled }
    }

    // MARK: Helpers

    /// The title of the sidebar row `id`: SwiftUI reports a disabled row on its text (the identified group and the
    /// AppKit outline row do not follow `.disabled`).
    func sidebarRow(_ id: String) -> XCUIElement {
        element(id)
    }

    /// The label and value text of `e` and everything inside it (a `.contain` group reports none of its own).
    func descendantText(of e: XCUIElement) -> String {
        guard let snapshot = try? e.snapshot() else { return text(of: e) }
        var parts: [String] = []
        func visit(_ s: XCUIElementSnapshot) {
            for t in [s.label, s.value as? String ?? "", s.title] where !t.isEmpty { parts.append(t) }
            s.children.forEach(visit)
        }
        visit(snapshot)
        return parts.joined(separator: " ")
    }

    /// Whether `menu` has an enabled item `title` (false when the menu or the item is absent).
    func menuItemExistsAndEnabled(_ menu: String, _ title: String) -> Bool {
        let bar = app.menuBars.menuBarItems[menu]
        guard bar.exists else { return false }
        bar.click()
        let item = menuItem(menu, title)
        let enabled = item.waitForExistence(timeout: 2) && item.isEnabled
        type(XCUIKeyboardKey.escape.rawValue, [])
        return enabled
    }
}
