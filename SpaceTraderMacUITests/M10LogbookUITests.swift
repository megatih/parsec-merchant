// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

/// M10: the Logbook's identifier walk (LOG-036), the First Profit unlock (ACH-022) and template flavor in a flow-2 game
/// (LLM-029). Every launch passes `-PMFlavor template` (UITestFixtures).
final class M10LogbookUITests: ParsecUITestCase {
    override var launchSeed: UInt64 { UITestFixtures.achievementSeed }

    /// Selects a Logbook tab by its title (segmented controls expose their segments by label).
    func selectTab(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let control = waitFor(AXID.Logbook.tab, file: file, line: line)
        let candidates = [control.radioButtons[title], control.buttons[title], control.descendants(matching: .any)[title]]
        guard let segment = candidates.first(where: { $0.exists }) else { return XCTFail("tab \(title)", file: file, line: line) }
        segment.click()
    }

    @MainActor
    func testFirstProfitUnlocksAndTheLogbookTabsHaveIdentifiers() throws {
        // covers: ACH-022, LOG-036, LOG-029, LOG-030, LOG-031, LOG-032, LOG-033, STAT-017, ACH-019
        click(AXID.Welcome.quickStart)
        expect("the game starts on day 0") { subtitle.hasPrefix("Day 0") }
        let item = UITestFixtures.achievementItem
        type("2")
        click(AXID.Market.buy(item))
        expect("one \(item) is held") { text(of: element(AXID.Market.held(item))) == "1" }
        _ = warpToNextTarget()
        type("2")
        click(AXID.Market.sell(item))
        let feed = waitFor(AXID.Status.feed)
        expect("the feed shows the unlock (feed: \(text(of: feed)))") { text(of: feed) == "Achievement unlocked: First Profit" }

        type("9")
        waitFor(AXID.Logbook.root)
        waitFor(AXID.Logbook.list)
        waitFor(AXID.Logbook.search)
        waitFor(AXID.Logbook.filter)
        waitFor(AXID.Logbook.export)
        walk(element(AXID.Logbook.root), surface: "Captain's Log tab")

        selectTab("Statistics")
        waitFor(AXID.Logbook.stats)
        walk(element(AXID.Logbook.root), surface: "Statistics tab")

        selectTab("Achievements")
        let badge = waitFor(AXID.Logbook.badge("firstProfit"))
        expect("First Profit is marked unlocked (label: \(badge.label))") { badge.label.contains("Unlocked") }
        walk(element(AXID.Logbook.root), surface: "Achievements tab")
    }
}

/// LLM-029: a flow-2 game's log rows carry the localized template flavor.
final class M10FlavorUITests: ParsecUITestCase {
    override var launchArguments: [String] { UITestFixtures.ambushLaunchArguments }

    @MainActor
    func testFlowTwoLogRowsShowTemplateFlavor() throws {
        // covers: LLM-029, LOG-031
        waitFor(AXID.Encounter.view)
        let view = element(AXID.Encounter.view)
        var attacks = 0
        while view.exists, attacks < UITestFixtures.ambushMaxAttacks {
            let attack = element(AXID.Encounter.attack)
            if attack.exists, attack.isEnabled {
                attack.click()
                attacks += 1
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        expect("the encounter ends") { !view.exists }
        waitFor(AXID.Arrival.card)
        type("9")
        waitFor(AXID.Logbook.list)
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", AXID.Logbook.entryPrefix))
        expect("the log lists entries") { rows.count > 0 }
        let phrases = UITestFixtures.encounterWonFlavor
        expect("an encounter row shows its template flavor") {
            rows.allElementsBoundByIndex.contains { row in phrases.contains { row.label.contains($0) } }
        }
    }
}
