// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

/// The M7 UI flows of PRD §8.2 (UI-SHELL-124…126).
final class M7FlowUITests: ParsecUITestCase {
    /// Flow 1, New Game → buy → warp → arrive.
    @MainActor
    func testFlow1NewGameBuyWarpArrive() throws {
        // covers: UI-SHELL-124, UI-ENC-095
        startFlowGame()
        XCTAssertTrue(subtitle.contains("Day 0"), subtitle)
        XCTAssertTrue(subtitle.contains("Credits \(1_000.formatted())"), subtitle)

        openPage("bridge")
        waitFor(AXID.Cargo.panel)
        guard let item = AXID.Cargo.items.first(where: { element(AXID.Cargo.buy($0)).exists && element(AXID.Cargo.buy($0)).isEnabled })
        else { return XCTFail("a market row has stock to buy") }
        let price = try XCTUnwrap(Int(text(of: element(AXID.Cargo.buyPrice(item))).filter(\.isNumber)), "the buy price of \(item)")
        XCTAssertEqual(text(of: element(AXID.Cargo.held(item))), "0")
        click(AXID.Cargo.buy(item))
        expect("Held shows 1 for \(item)") { text(of: element(AXID.Cargo.held(item))) == "1" }
        expect("the credits drop by the buy price \(price) (subtitle: \(subtitle))") {
            subtitle.contains("Credits \((1_000 - price).formatted()) ")
        }

        let target = warpToNextTarget()
        XCTAssertTrue(subtitle.contains("Day 1"), subtitle)
        XCTAssertTrue(subtitle.contains(target), subtitle)
        // UI-BRG-042: the message slot holds the arrival summary.
        let feed = waitFor(AXID.Arrival.card)
        expect("status.feed shows the arrival at \(target) (feed: \(text(of: feed)))") {
            text(of: feed).hasPrefix("Arrived at \(target)")
        }
    }

    /// Flow 3, Save → load.
    @MainActor
    func testFlow3SaveLoad() throws {
        // covers: UI-SHELL-125, UI-ENC-095
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
        XCTAssertFalse(isMenuItemEnabled("View", "Options"), "View › Options is disabled without a game")

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

        // Options is a page; a change applies at once (no OK or Cancel) and is still there after leaving the page.
        openOptions()
        let autoFuel = isOn(element(AXID.Options.autoFuel))
        element(AXID.Options.autoFuel).click()
        expect("Get full fuel toggles") { self.isOn(self.element(AXID.Options.autoFuel)) != autoFuel }
        setLeaveEmpty(3)
        openPage("bridge")
        expect("the page closes") { !self.element(AXID.Options.root).exists }

        openOptions()
        XCTAssertEqual(isOn(element(AXID.Options.autoFuel)), !autoFuel, "the fuel option was kept")
        XCTAssertEqual(leaveEmpty(), 3, "the empty bays were kept")
        let traders = element(AXID.Options.alwaysIgnoreTraders)
        if isOn(traders) { traders.click() }
        expect("Ignore traders is off") { !self.isOn(self.element(AXID.Options.alwaysIgnoreTraders)) }
        expect("Ignore dealing traders is disabled under Modern") { !self.element(AXID.Options.alwaysIgnoreTradeInOrbit).isEnabled }
        openPage("bridge")
    }

    // MARK: Helpers

    private func openOptions() {
        openOptionsPage()
        waitFor(AXID.Options.autoFuel)
    }

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
