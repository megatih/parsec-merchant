// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

/// UI-KEYS: keyboard shortcuts, Return/Esc routing, default focus and the keyboard-only scenario (M12).
final class M12KeysUITests: ParsecUITestCase {
    // MARK: Helpers

    private let esc = XCUIKeyboardKey.escape.rawValue
    private let ret = XCUIKeyboardKey.return.rawValue
    private let tab = XCUIKeyboardKey.tab.rawValue

    private func quickStart(file: StaticString = #filePath, line: UInt = #line) {
        click(AXID.Welcome.quickStart, file: file, line: line)
        expect("the Quick Start game runs", file: file, line: line) { subtitle.hasPrefix("Day 0") }
    }

    /// "Day 3" of the subtitle.
    private var day: String { subtitle.components(separatedBy: " · ").first ?? "" }

    private var toolbarTarget: String {
        let t = element(AXID.Toolbar.target)
        return t.title.isEmpty ? t.label : t.title
    }

    private func pause(_ seconds: TimeInterval = 0.6) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

    /// The identifier of the element with keyboard focus ("" when none reports it).
    private func focusedIdentifier() -> String {
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasKeyboardFocus == true")).firstMatch
        return focused.exists ? focused.identifier : ""
    }

    private func hasFocus(_ id: String) -> Bool {
        let e = element(id)
        return e.exists && ((e.value(forKey: "hasKeyboardFocus") as? Bool) ?? false)
    }

    /// Turns Full Keyboard Access on for this test (the global `AppleKeyboardUIMode` default, which AppKit reads at
    /// launch; a launch argument does not reach it) and restores the previous value afterwards, then relaunches.
    private func withFullKeyboardAccess(_ arguments: [String]) throws {
        func defaults(_ args: [String]) -> (Int32, String) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            p.arguments = args
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = Pipe()
            do { try p.run() } catch { return (-1, "") }
            p.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return (p.terminationStatus, out.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let (status, old) = defaults(["read", "-g", "AppleKeyboardUIMode"])
        let (written, _) = defaults(["write", "-g", "AppleKeyboardUIMode", "-int", "2"])
        guard written == 0 else {
            // The sandboxed runner cannot change the global default: run with the machine's own setting.
            relaunch(arguments)
            return
        }
        addTeardownBlock {
            if status == 0 { _ = defaults(["write", "-g", "AppleKeyboardUIMode", "-int", old]) } else {
                _ = defaults(["delete", "-g", "AppleKeyboardUIMode"])
            }
        }
        relaunch(arguments)
    }

    private func heldValues() -> [String: String] {
        var out: [String: String] = [:]
        for item in AXID.Market.items {
            let e = element(AXID.Market.held(item))
            if e.exists { out[item] = text(of: e) }
        }
        return out
    }

    /// ⌘F focuses the Market filter, ⇥ moves to the table (text fields and tables are in the key-view loop even without
    /// Full Keyboard Access) and ↓ selects the first row.
    private func focusMarketTableByKeyboard(file: StaticString = #filePath, line: UInt = #line) {
        waitFor(AXID.Market.table, file: file, line: line)
        pause()
        type("f")
        expect("⌘F focuses market.filter", file: file, line: line) { hasFocus("market.filter") }
        type(tab, [])
        pause(0.3)
        type(XCUIKeyboardKey.downArrow.rawValue, [])
        pause(0.3)
    }

    private func frame(_ id: String) -> CGRect { element(id).frame }

    private func moved(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.midX - b.midX) > 1 || abs(a.midY - b.midY) > 1 || abs(a.width - b.width) > 0.5
    }

    private func screenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: mainWindow.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: §3 menus

    /// Edit › Find holds only Find…, so ⌘J reaches Warp.
    @MainActor
    func testFindSubmenuHoldsOnlyFindAndCommandJWarps() throws {
        // covers: UI-KEYS-010, MENU-045
        quickStart()
        app.menuBars.menuBarItems["Edit"].click()
        let find = menuItem("Edit", "Find")
        XCTAssertTrue(find.waitForExistence(timeout: timeout), "Edit › Find exists")
        find.hover()
        let items = find.menus.menuItems.allElementsBoundByIndex.map(\.title).filter { !$0.isEmpty }
        type(esc, [])
        type(esc, [])
        XCTAssertEqual(items, ["Find…"], "the Find submenu holds only Find… (found \(items))")
        type("]")
        expect("a target is selected") { !toolbarTarget.isEmpty && !toolbarTarget.hasPrefix("Choose") }
        type("j")
        expect("⌘J warps: the day advances (subtitle: \(subtitle))") { day == "Day 1" }
    }

    // MARK: §4 in-view keys

    /// ⌘= / ⌘− / ⌘+ / ⌘0 on the focused Galaxy map; ⌘= does nothing with the map unfocused.
    @MainActor
    func testMapZoomKeysIncludingTheCommandEqualsAlias() throws {
        // covers: UI-KEYS-013, MAP-015
        quickStart()
        type("7")
        let g = AXID.Galaxy.section
        waitFor(g.map)
        let probe = g.system(UITestFixtures.mapFlowTarget)
        waitFor(probe)
        pause()
        var before = frame(probe)
        type("=")
        expect("⌘= zooms in (\(before) → \(frame(probe)))") { moved(before, frame(probe)) }
        pause()
        before = frame(probe)
        type("-")
        expect("⌘− zooms out") { moved(before, frame(probe)) }
        pause()
        before = frame(probe)
        type("+", [.command, .shift])
        expect("⌘+ zooms in") { moved(before, frame(probe)) }
        pause()
        before = frame(probe)
        type("0")
        expect("⌘0 fits the galaxy") { moved(before, frame(probe)) }
        XCTAssertTrue(element(g.zoomIn).isEnabled, "\(g.zoomIn) is enabled at Fit Galaxy")
        // With the search field focused the canvas has no focus: ⌘= does nothing.
        click(g.searchField)
        pause()
        before = frame(probe)
        type("=")
        pause()
        XCTAssertFalse(moved(before, frame(probe)), "⌘= does nothing while the map is unfocused")
    }

    /// The Encounter letters do nothing while a sheet is up.
    @MainActor
    func testEncounterLettersAreInactiveUnderASheet() throws {
        // covers: UI-KEYS-014
        relaunch(UITestFixtures.encounterFixtureArguments("pirateSurrender"))
        waitFor(AXID.Encounter.view)
        let rowsBefore = (0..<40).filter { element(AXID.Encounter.logRow($0)).exists }.count
        click(AXID.Encounter.plunder)
        let sheet = waitFor(AXID.Decision.plunderSheet)
        for key in ["a", "s", "f", "r"] { type(key, []) }
        pause()
        XCTAssertTrue(sheet.exists, "the plunder sheet stays open")
        let rowsAfter = (0..<40).filter { element(AXID.Encounter.logRow($0)).exists }.count
        XCTAssertEqual(rowsAfter, rowsBefore, "no encounter action ran under the sheet")
    }

    // MARK: §5 Return and Esc

    /// One Esc router: the feed overlay closes first, then the Shipyard comparison clears.
    @MainActor
    func testEscapeClosesTheFeedOverlayThenClearsTheComparison() throws {
        // covers: UI-KEYS-018, UI-KEYS-017
        var cards: [XCUIElement] = []
        for seed in [UITestFixtures.flowSeed, UITestFixtures.mapFlowSeed, 1, 2, 3, 4, 5, 6] {
            if seed != UITestFixtures.flowSeed { relaunch(UITestFixtures.launchArguments(seed: seed)) }
            quickStart()
            type("3")
            waitFor("shipyard.root")
            pause()
            cards = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'shipyard.ship.'"))
                .allElementsBoundByIndex.filter { !$0.identifier.hasSuffix(".buy") }
            if cards.count >= 2 { break }
        }
        XCTAssertGreaterThanOrEqual(cards.count, 2, "a Quick Start system with a ship for sale")
        cards[0].click()
        XCUIElement.perform(withKeyModifiers: .command) { cards[1].click() }
        let compare = waitFor("shipyard.compare")
        click(AXID.Status.feed)
        let feed = waitFor(AXID.Status.feedList)
        type(esc, [])
        expect("the first Esc closes the feed overlay") { !feed.exists }
        XCTAssertTrue(compare.exists, "the comparison stays after the first Esc")
        type(esc, [])
        expect("the second Esc clears the comparison") { !compare.exists }
        type(esc, [])
        pause()
        XCTAssertTrue(mainWindow.exists && element("shipyard.root").exists, "a third Esc does nothing")
    }

    /// Return on the Bridge never warps; ⌘J does.
    @MainActor
    func testReturnOnTheBridgeNeverWarps() throws {
        // covers: UI-KEYS-019
        quickStart()
        type("1")
        click(AXID.Bridge.targetNext)
        waitFor("bridge.target.warp")
        type(ret, [])
        pause(1)
        XCTAssertEqual(day, "Day 0", "Return does not warp")
        type("j")
        expect("⌘J warps (subtitle: \(subtitle))") { day == "Day 1" }
    }

    /// Esc closes every sheet a fixture reaches, with the §2.3 outcome.
    @MainActor
    func testEscapeClosesEverySheet() throws {
        // covers: UI-KEYS-021, UI-KEYS-020
        quickStart()
        // Options and Find System (Cancel).
        type("o", [.command, .option])
        let options = waitFor(AXID.Options.sheet)
        type(esc, [])
        expect("Esc closes Options") { !options.exists }
        type("f", [.command, .option])
        let find = waitFor("findSystem.sheet")
        type(esc, [])
        expect("Esc closes Find System") { !find.exists }
        // Retire: Esc is Cancel; the game goes on.
        chooseMenuItem("Game", "Retire…")
        let retire = waitFor(AXID.Dialog.retireSheet)
        type(esc, [])
        expect("Esc cancels Retire") { !retire.exists }
        XCTAssertTrue(day.hasPrefix("Day 0"))
        // Newspaper after a warp (Close).
        type("1")
        click(AXID.Bridge.targetNext)
        type("j")
        expect("warped") { day == "Day 1" }
        type("n", [.command, .shift])
        if element(AXID.Dialog.confirmationConfirm).waitForExistence(timeout: 2) { click(AXID.Dialog.confirmationConfirm) }
        let paper = waitFor(AXID.Newspaper.sheet)
        type(esc, [])
        expect("Esc closes the newspaper") { !paper.exists }

        // Plunder (Done).
        relaunch(UITestFixtures.encounterFixtureArguments("pirateSurrender"))
        click(AXID.Encounter.plunder)
        let plunder = waitFor(AXID.Decision.plunderSheet)
        type(esc, [])
        expect("Esc presses Done on the plunder sheet") { !plunder.exists }
        // Trade in orbit (Decline).
        relaunch(UITestFixtures.encounterFixtureArguments("traderSell"))
        click(AXID.Encounter.trade)
        let trade = waitFor(AXID.Decision.tradeSheet)
        type(esc, [])
        expect("Esc declines the trade") { !trade.exists }
        // Arrest report (Continue).
        relaunch(UITestFixtures.encounterFixtureArguments("policeAttack"))
        click(AXID.Encounter.surrender)
        if element(AXID.Dialog.confirmationConfirm).waitForExistence(timeout: 2) { click(AXID.Dialog.confirmationConfirm) }
        let report = waitFor(AXID.Report.sheet)
        type(esc, [])
        expect("Esc continues past the arrest report") { !report.exists }
        // Narrative offer (Decline: the offer stays on the Bridge).
        relaunch(UITestFixtures.specialEventArguments)
        type("1")
        waitFor(AXID.Narrative.bridgeCard)
        pause()
        click(AXID.Narrative.bridgeAccept)
        let narrative = waitFor(AXID.Narrative.sheet)
        type(esc, [])
        expect("Esc declines the offer") { !narrative.exists }
        XCTAssertTrue(element(AXID.Narrative.bridgeCard).exists, "the special event is still offered")
    }

    /// Return in the Market quantity field buys the typed quantity.
    @MainActor
    func testReturnInTheQuantityFieldBuysTheTypedQuantity() throws {
        // covers: UI-KEYS-022, UI-SHELL-062
        quickStart()
        type("2")
        waitFor(AXID.Market.table)
        let item = try XCTUnwrap(AXID.Market.items.first { element(AXID.Market.buy($0)).exists && element(AXID.Market.buy($0)).isEnabled })
        let field = waitFor("market.row.\(item).quantity")
        field.click()
        // An AppKit table takes the first click in an unselected row to select the row; the second edits the field.
        if (field.value(forKey: "hasKeyboardFocus") as? Bool) != true { field.click() }
        field.typeText("2")
        type(ret, [])
        expect("Held of \(item) is 2 (held: \(text(of: element(AXID.Market.held(item)))))") {
            text(of: element(AXID.Market.held(item))) == "2"
        }
        XCTAssertEqual(day, "Day 0", "no other default action ran")
    }

    // MARK: §6 focus

    /// Market by keyboard (⌘2, ⌘F, ⇥, ↓, B) buys one unit with no click; ⌘7 focuses the map: ⌘= and → act on it.
    @MainActor
    func testDefaultFocusLetsMarketAndMapKeysWorkWithoutAClick() throws {
        // covers: UI-KEYS-027, UI-SHELL-064, MAP-015
        quickStart()
        type("2")
        focusMarketTableByKeyboard()
        type("b", [])
        expect("B bought one unit of the selected row (held: \(heldValues()))") { heldValues().values.contains("1") }
        type("7")
        let probe = AXID.Galaxy.section.system(UITestFixtures.mapFlowTarget)
        waitFor(probe)
        pause()
        // At Fit Galaxy the whole galaxy is visible and panning is clamped: zoom in first (still no click).
        var before = frame(probe)
        type("=")
        expect("⌘= zooms the focused map") { moved(before, frame(probe)) }
        pause()
        before = frame(probe)
        type(XCUIKeyboardKey.rightArrow.rawValue, [])
        expect("→ pans the map") { moved(before, frame(probe)) }
    }

    /// Full Keyboard Access: Tab reaches the Bridge and Market controls; the target card's controls are consecutive.
    @MainActor
    func testFullKeyboardAccessTraversalAndFocusOrder() throws {
        // covers: UI-KEYS-025, UI-KEYS-026, UI-KEYS-028
        try withFullKeyboardAccess(UITestFixtures.launchArguments)
        quickStart()
        type("1")
        waitFor(AXID.Bridge.targetCard)
        let bridgeOrder = tabCycle()
        try XCTSkipIf(bridgeOrder.count <= 1, """
            Full Keyboard Access is off on this Mac (Tab only reaches \(bridgeOrder)); turn on System Settings › Keyboard › \
            Keyboard navigation to run UI-KEYS-025/026 (QA-REPORT UI-KEYS-029).
            """)
        let attachment = XCTAttachment(string: bridgeOrder.joined(separator: "\n"))
        attachment.name = "bridge-tab-order"
        attachment.lifetime = .keepAlways
        add(attachment)
        let card = ["bridge.target.previous", "bridge.target.next", "bridge.target.warp"]
        let positions = card.compactMap { bridgeOrder.firstIndex(of: $0) }
        XCTAssertEqual(positions.count, card.count, "Tab reaches every target-card control (order: \(bridgeOrder))")
        XCTAssertEqual(positions, positions.sorted(), "the target-card controls follow their visual order")
        // Everything enabled and identified on the Bridge's target card is reachable.
        let reachable = Set(bridgeOrder)
        for e in element(AXID.Bridge.targetCard).buttons.allElementsBoundByIndex where e.isEnabled && !e.identifier.isEmpty {
            XCTAssertTrue(reachable.contains(e.identifier), "\(e.identifier) is reachable with Tab")
        }
        type("2")
        waitFor(AXID.Market.table)
        let marketOrder = tabCycle()
        let m = XCTAttachment(string: marketOrder.joined(separator: "\n"))
        m.name = "market-tab-order"
        m.lifetime = .keepAlways
        add(m)
        let filter = marketOrder.firstIndex(of: "market.filter"), table = marketOrder.firstIndex(of: AXID.Market.table)
        XCTAssertNotNil(filter, "Tab reaches market.filter (order: \(marketOrder))")
        XCTAssertNotNil(table, "Tab reaches market.table (order: \(marketOrder))")
        if let filter, let table { XCTAssertLessThan(filter, table, "the filter comes before the table") }
        screenshot("market-focus-ring")
    }

    /// Presses Tab until the focus returns to where it started (at most 120 times); returns the identifiers in order.
    private func tabCycle() -> [String] {
        var order: [String] = []
        for _ in 0..<120 {
            type(tab, [])
            let id = focusedIdentifier()
            if !id.isEmpty, id == order.first { break }
            if !id.isEmpty, order.last != id { order.append(id) }
        }
        return order
    }

    /// The keyboard-only scenario (no click after launch).
    @MainActor
    func testKeyboardOnlyScenario() throws {
        // covers: UI-KEYS-030, UI-KEYS-027
        try withFullKeyboardAccess(UITestFixtures.launchArguments + ["-PMTips", "off"])
        waitFor(AXID.Welcome.quickStart)
        type(ret, [])
        expect("Return is Quick Start") { subtitle.hasPrefix("Day 0") }
        type("2")
        focusMarketTableByKeyboard()
        type("b", [])
        expect("B bought one unit") { heldValues().values.contains("1") }
        type("1")
        waitFor(AXID.Bridge.targetCard)
        let before = toolbarTarget
        type("]")
        expect("⌘] changed the target (\(before) → \(toolbarTarget))") { toolbarTarget != before && !toolbarTarget.hasPrefix("Choose") }
        type("j")
        expect("⌘J warped to day 1") { day == "Day 1" }
        type("9")
        waitFor("logbook.root")
        type("f")
        expect("⌘F focuses the Logbook search") { hasFocus("logbook.search") }
        app.typeText("Day")
        expect("the search shows the word") { (element("logbook.search").value as? String) == "Day" }
        type(esc, [])
        expect("Esc clears the search") { ((element("logbook.search").value as? String) ?? "").isEmpty }
        type(",")
        let textSize = element("settings.textSize")
        XCTAssertTrue(textSize.waitForExistence(timeout: timeout), "Settings opens with ⌘,")
        let sizeBefore = text(of: textSize)
        for _ in 0..<30 where !hasFocus("settings.textSize") { type(tab, []) }
        if hasFocus("settings.textSize") {
            type(" ", [])
            type(XCUIKeyboardKey.downArrow.rawValue, [])
            type(ret, [])
            expect("the Text Size changed (\(sizeBefore) → \(text(of: textSize)))") { text(of: textSize) != sizeBefore }
        } else {
            // Without Full Keyboard Access Tab does not reach pop-up buttons (QA-REPORT UI-KEYS-029 covers it by hand).
            XCTContext.runActivity(named: "Full Keyboard Access is off: Text Size step left to the manual pass") { _ in }
        }
        type("w")
        expect("⌘W closes Settings") { !element("settings.textSize").exists }
        type("s")
        pause()
        type("o")
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", AXID.Files.rowPrefix)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: timeout), "⌘S saved a slot that Open Saved Game lists")
        type(esc, [])
    }

    // MARK: §7 HIG

    /// The toolbar holds controls only.
    @MainActor
    func testToolbarHoldsControlsOnly() throws {
        // covers: UI-KEYS-031
        quickStart()
        let toolbar = mainWindow.toolbars.firstMatch
        XCTAssertTrue(toolbar.waitForExistence(timeout: timeout))
        let ids = Set(toolbar.descendants(matching: .any).allElementsBoundByIndex.map(\.identifier).filter { $0.contains(".") && !$0.hasPrefix("_") })
        XCTAssertEqual(ids, [AXID.Toolbar.target, AXID.Toolbar.warp, AXID.Toolbar.inspector], "toolbar identifiers: \(ids)")
        XCTAssertTrue(toolbar.staticTexts.allElementsBoundByIndex.allSatisfy { $0.identifier.isEmpty || ids.contains($0.identifier) },
                      "no status text in the toolbar")
    }

    // MARK: §8 sweeps

    /// Global shortcut sweep in one Quick Start game.
    @MainActor
    func testGlobalShortcutSweep() throws {
        // covers: UI-KEYS-036, MENU-020, MENU-027, MENU-029, MENU-035
        relaunch(UITestFixtures.launchArguments(seed: UITestFixtures.mapFlowSeed))
        quickStart()
        for (key, root) in AXID.sections + [("9", "logbook.root")] {
            type(key)
            waitFor(root)
        }
        type("1")
        let inspector = element(AXID.Inspector.root)
        let shownBefore = inspector.exists
        type("i", [.command, .control])
        expect("⌃⌘I toggles the inspector") { inspector.exists != shownBefore }
        type("i", [.command, .control])
        expect("⌃⌘I toggles it back") { inspector.exists == shownBefore }
        let sidebar = element(AXID.Sidebar.list)
        let sidebarBefore = sidebar.isHittable
        type("s", [.command, .control])
        expect("⌃⌘S toggles the sidebar") { sidebar.isHittable != sidebarBefore }
        type("s", [.command, .control])
        expect("⌃⌘S toggles it back") { sidebar.isHittable == sidebarBefore }
        type("]")
        expect("⌘] selects a target") { !toolbarTarget.isEmpty && !toolbarTarget.hasPrefix("Choose") }
        let target = toolbarTarget
        type("]")
        expect("⌘] changes the target") { toolbarTarget != target }
        type("[")
        expect("⌘[ restores it") { toolbarTarget == target }
        type("f", [.command, .option])
        let find = waitFor("findSystem.sheet")
        type(esc, [])
        expect("Esc closes Find System") { !find.exists }
        type("2")
        waitFor(AXID.Market.table)
        pause()
        type("f")
        expect("⌘F on Market focuses market.filter") { hasFocus("market.filter") }
        type(esc, [])
        type("7")
        waitFor(AXID.Galaxy.root)
        type("f")
        expect("⌘F on Galaxy focuses the map search") { hasFocus(AXID.Galaxy.section.searchField) }
        type(esc, [])
        type("9")
        waitFor("logbook.root")
        type("f")
        expect("⌘F on Logbook focuses logbook.search") { hasFocus("logbook.search") }
        type(esc, [])
        type("m", [.command, .shift])
        let chart = waitFor(AXID.Galaxy.windowRoot)
        type("w")
        expect("⌘W closes the Galaxy Chart window") { !chart.exists }
        // Closing the chart window leaves no key window until the main window is clicked.
        mainWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01)).click()
        type("o", [.command, .option])
        let options = waitFor(AXID.Options.sheet)
        pause()
        type(esc, [])
        expect("Esc closes Options") { !options.exists }
        type("1")
        click(AXID.Bridge.targetNext)
        type("j")
        expect("warped (subtitle: \(subtitle))") { day == "Day 1" }
        let fuel = element("status.fuel")
        let fuelBefore = text(of: fuel)
        if isMenuItemEnabled("Game", "Fill Fuel") {
            type("f", [.command, .shift])
            expect("⇧⌘F refuels (\(fuelBefore) → \(text(of: fuel)))") { text(of: fuel) != fuelBefore }
            XCTAssertFalse(isMenuItemEnabled("Game", "Fill Fuel"), "the tank is full after ⇧⌘F")
        } else {
            // The arrival refuelled already (auto-fuel); ⇧⌘F then changes nothing.
            type("f", [.command, .shift])
            pause()
            XCTAssertEqual(text(of: fuel), fuelBefore, "⇧⌘F with a full tank changes nothing")
        }
        app.menuBars.menuBarItems["Game"].click()
        let newspaperItem = menuItem("Game", "Newspaper")
        let newspaperOffered = newspaperItem.waitForExistence(timeout: 2) && newspaperItem.isEnabled
        type(esc, [])
        guard newspaperOffered else { return } // this system prints no paper (MENU-024); testEscapeClosesEverySheet covers ⇧⌘N
        type("n", [.command, .shift])
        if element(AXID.Dialog.confirmationConfirm).waitForExistence(timeout: 2) { click(AXID.Dialog.confirmationConfirm) }
        let paper = waitFor(AXID.Newspaper.sheet)
        type(esc, [])
        expect("Esc closes the newspaper") { !paper.exists }
    }

    /// Encounter key sweep with the pirate ambush.
    @MainActor
    func testEncounterKeySweep() throws {
        // covers: UI-KEYS-037, UI-ENC-028, UI-ENC-029, UI-ENC-032, UI-ENC-033
        relaunch(UITestFixtures.ambushLaunchArguments)
        waitFor(AXID.Encounter.view)
        type("u", [])
        pause()
        XCTAssertFalse(element(AXID.Encounter.logRow(0)).exists, "U (not offered) changes nothing")
        type(ret, [])
        let row0 = waitFor(AXID.Encounter.logRow(0))
        XCTAssertFalse(text(of: row0).isEmpty, "Return ran the default action (Flee): \(text(of: row0))")

        relaunch(UITestFixtures.ambushLaunchArguments)
        waitFor(AXID.Encounter.view)
        let auto = waitFor("encounter.autoRepeat")
        let autoBefore = isOn(auto)
        type("a", [.option])
        if auto.isEnabled {
            expect("⌥A toggles Auto-repeat") { isOn(auto) != autoBefore }
            type("a", [.option])
            expect("⌥A toggles it back") { isOn(auto) == autoBefore }
        }
        type("r", [])
        waitFor(AXID.Encounter.logRow(0))
        let stop = element("encounter.action.stop")
        type(esc, [])
        expect("Esc stops the repeat (Stop is no longer enabled)") { !stop.exists || !stop.isEnabled }
        let count = (0..<200).filter { element(AXID.Encounter.logRow($0)).exists }.count
        pause(1.5)
        let later = (0..<200).filter { element(AXID.Encounter.logRow($0)).exists }.count
        XCTAssertTrue(later == count || !element(AXID.Encounter.view).exists, "the log stops growing after Esc")
    }
}
