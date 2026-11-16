// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

/// The M7 UI flows of PRD §8.2 (UI-SHELL-124…126).
final class M7FlowUITests: ParsecUITestCase {
    /// Flow 1, New Game → buy → warp → arrive.
    @MainActor
    func testFlow1NewGameBuyWarpArrive() throws {
        // covers: UI-SHELL-124
        startFlowGame()
        XCTAssertTrue(subtitle.contains("Day 0"), subtitle)
        XCTAssertTrue(subtitle.contains("Credits \(1_000.formatted())"), subtitle)

        type("2")
        waitFor(AXID.Market.table)
        guard let item = AXID.Market.items.first(where: { element(AXID.Market.buy($0)).exists && element(AXID.Market.buy($0)).isEnabled })
        else { return XCTFail("a market row has stock to buy") }
        let price = try XCTUnwrap(Int(text(of: element(AXID.Market.buyPrice(item))).filter(\.isNumber)), "the buy price of \(item)")
        XCTAssertEqual(text(of: element(AXID.Market.held(item))), "0")
        click(AXID.Market.buy(item))
        expect("Held shows 1 for \(item)") { text(of: element(AXID.Market.held(item))) == "1" }
        expect("the credits drop by the buy price \(price) (subtitle: \(subtitle))") {
            subtitle.contains("Credits \((1_000 - price).formatted()) ")
        }

        let target = warpToNextTarget()
        XCTAssertTrue(subtitle.contains("Day 1"), subtitle)
        XCTAssertTrue(subtitle.contains(target), subtitle)
        let feed = waitFor(AXID.Status.feed)
        expect("status.feed shows the arrival at \(target) (feed: \(text(of: feed)))") {
            text(of: feed) == "Arrived at \(target)."
        }
    }

    /// Flow 3, Save → load.
    @MainActor
    func testFlow3SaveLoad() throws {
        // covers: UI-SHELL-125
        startFlowGame()
        let startSystem = systemInSubtitle()
        XCTAssertFalse(startSystem.isEmpty, subtitle)
        type("s")                                        // ⌘S writes a new slot (SAV-041)
        _ = warpToNextTarget()                           // day 1, autosaved on arrival

        type("o")
        let day0 = try openSheetRow(containing: "Day 0 ")
        day0.click()
        click(AXID.Files.open)
        click(AXID.Dialog.appConfirmationConfirm)        // the day changed since the save: discard dialog
        expect("the day-0 save is loaded (subtitle: \(subtitle))") {
            subtitle.hasPrefix("Day 0 · \(startSystem) · ")
        }

        XCTAssertTrue(isMenuItemEnabled("File", "Revert to Autosave"), "the autosave of this game is from day 1")
        chooseMenuItem("File", "Save As…")
        type("o")
        waitFor(AXID.Files.list)
        expect("the Open sheet lists the first save and the Save As copy") { slotRows(containing: "Day 0 ").count == 2 }
        click(AXID.Files.cancel)
    }

    /// Flow 4, Settings and Game › Options.
    @MainActor
    func testFlow4SettingsAndOptions() throws {
        // covers: UI-SHELL-126
        XCTAssertFalse(isMenuItemEnabled("Game", "Options…"), "Game › Options… is disabled without a game")

        type(",")
        let fast = waitFor(AXID.Settings.fastTravel)
        let wasFast = isOn(fast)
        fast.click()
        expect("Fast travel toggles") { isOn(element(AXID.Settings.fastTravel)) != wasFast }
        type("w")
        expect("Settings closes") { !element(AXID.Settings.fastTravel).exists }
        type(",")
        expect("Fast travel kept its new value") { isOn(waitFor(AXID.Settings.fastTravel)) != wasFast }
        type("w")
        expect("Settings closes") { !element(AXID.Settings.fastTravel).exists }

        click(AXID.Welcome.quickStart)
        expect("the Quick Start game runs") { subtitle.hasPrefix("Day 0") }

        openOptions()
        let autoFuel = isOn(element(AXID.Options.autoFuel))
        element(AXID.Options.autoFuel).click()
        expect("Get full fuel toggles") { isOn(element(AXID.Options.autoFuel)) != autoFuel }
        setLeaveEmpty(3)
        click(AXID.Options.ok)
        expect("the sheet closes") { !element(AXID.Options.sheet).exists }

        openOptions()
        XCTAssertEqual(isOn(element(AXID.Options.autoFuel)), !autoFuel, "OK kept the fuel option")
        XCTAssertEqual(leaveEmpty(), 3, "OK kept the empty bays")
        let autoRepair = isOn(element(AXID.Options.autoRepair))
        element(AXID.Options.autoRepair).click()
        expect("Get full repairs toggles") { isOn(element(AXID.Options.autoRepair)) != autoRepair }
        click(AXID.Options.cancel)
        expect("the sheet closes") { !element(AXID.Options.sheet).exists }

        openOptions()
        XCTAssertEqual(isOn(element(AXID.Options.autoRepair)), autoRepair, "Cancel discarded the repair option")
        XCTAssertEqual(isOn(element(AXID.Options.autoFuel)), !autoFuel)
        XCTAssertEqual(leaveEmpty(), 3)
        let traders = reveal(element(AXID.Options.alwaysIgnoreTraders), in: optionsScrollView)
        if isOn(traders) { traders.click() }
        expect("Ignore traders is off") { !isOn(element(AXID.Options.alwaysIgnoreTraders)) }
        expect("Ignore dealing traders is disabled under Modern") { !element(AXID.Options.alwaysIgnoreTradeInOrbit).isEnabled }
        click(AXID.Options.cancel)
    }

    // MARK: Helpers

    private func openOptions() {
        type("o", [.command, .option])
        waitFor(AXID.Options.sheet)
        waitFor(AXID.Options.autoFuel)
    }

    private var optionsScrollView: XCUIElement { element(AXID.Options.sheet).scrollViews.firstMatch }

    private func leaveEmpty() -> Int? {
        let stepper = element(AXID.Options.leaveEmpty)
        if let n = stepper.value as? NSNumber { return n.intValue }
        return (stepper.value as? String).flatMap { Int($0.filter(\.isNumber)) }
    }

    private func setLeaveEmpty(_ target: Int) {
        let stepper = waitFor(AXID.Options.leaveEmpty)
        for _ in 0..<20 {
            guard let v = leaveEmpty(), v != target else { break }
            if v < target { stepper.incrementArrows.firstMatch.click() } else { stepper.decrementArrows.firstMatch.click() }
        }
        expect("Cargo bays to leave empty is \(target)") { leaveEmpty() == target }
    }

    /// The distinct slot rows of the Open sheet whose text contains `text`, keyed by row identifier.
    private func slotRows(containing text: String) -> [String: XCUIElement] {
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", AXID.Files.rowPrefix))
        var found: [String: XCUIElement] = [:]
        for e in rows.allElementsBoundByIndex where self.text(of: e).contains(text) {
            found[e.identifier] = e
        }
        return found
    }

    private func openSheetRow(containing text: String) throws -> XCUIElement {
        waitFor(AXID.Files.list)
        var rows: [String: XCUIElement] = [:]
        expect("the Open sheet lists one row containing “\(text)”") {
            rows = slotRows(containing: text)
            return rows.count == 1
        }
        return try XCTUnwrap(rows.values.first)
    }
}
