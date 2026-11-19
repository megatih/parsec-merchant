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

    private func pause(_ seconds: TimeInterval = 0.6) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

    /// The identifier of the element with keyboard focus ("" when none reports it).
    /// Text fields whose focus is checked directly: while one is being edited, the focus query finds the enclosing section
    /// container (the field editor inside has no identifier), so the field itself is asked first.
    private let textFieldIDs = ["logbook.search"]

    private func focusedIdentifier() -> String {
        if let field = textFieldIDs.first(where: { hasFocus($0) }) { return field }
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
        for item in AXID.Cargo.items {
            let e = element(AXID.Cargo.held(item))
            if e.exists { out[item] = text(of: e) }
        }
        return out
    }

    /// The Bridge opens with its Cargo rows focused (UI-BRG-007), so ↓ selects the first row with no click.
    private func focusMarketTableByKeyboard(file: StaticString = #filePath, line: UInt = #line) {
        waitFor(AXID.Cargo.panel, file: file, line: line)
        pause()
        type(XCUIKeyboardKey.downArrow.rawValue, [])
        pause(0.3)
        expect("↓ selects the first Cargo row", file: file, line: line) { self.element(AXID.Cargo.row("water")).isSelected }
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
        expect("a target is selected") { !targetName.isEmpty && !targetName.hasPrefix("Choose") }
        type("j")
        expect("⌘J warps: the day advances (subtitle: \(subtitle))") { day == "Day 1" }
    }

    // MARK: §4 in-view keys

    /// ⌘= / ⌘− / ⌘+ / ⌘0 on the focused Galaxy map; ⌘= does nothing with the map unfocused.
    @MainActor
    func testMapZoomKeysIncludingTheCommandEqualsAlias() throws {
        // covers: UI-KEYS-013, MAP-015
        quickStart()
        openPage("galaxy")
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
        // covers: UI-KEYS-018, UI-KEYS-017, UI-PTR-020 (the Compare toggle is a new control beside each card)
        var cards: [XCUIElement] = []
        for seed in [UITestFixtures.flowSeed, UITestFixtures.mapFlowSeed, 1, 2, 3, 4, 5, 6] {
            if seed != UITestFixtures.flowSeed { relaunch(UITestFixtures.launchArguments(seed: seed)) }
            quickStart()
            openPage("shipyard")
            waitFor("shipyard.root")
            pause()
            cards = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'shipyard.ship.'"))
                .allElementsBoundByIndex.filter { !$0.identifier.hasSuffix(".buy") && !$0.identifier.hasSuffix(".compare") }
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
        openPage("bridge")
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
        openPage("bridge")
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
        openPage("bridge")
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
        // covers: UI-KEYS-022, UI-SHELL-062, UI-PTR-020
        quickStart()
        openPage("bridge")
        waitFor(AXID.Cargo.panel)
        let item = try XCTUnwrap(AXID.Cargo.items.first { element(AXID.Cargo.buy($0)).exists && element(AXID.Cargo.buy($0)).isEnabled })
        let field = waitFor(AXID.Cargo.quantity(item))
        field.click()
        field.typeText("2")
        type(ret, [])
        expect("Held of \(item) is 2 (held: \(text(of: element(AXID.Cargo.held(item)))))") {
            text(of: element(AXID.Cargo.held(item))) == "2"
        }
        XCTAssertEqual(day, "Day 0", "no other default action ran")
    }

    // MARK: §6 focus

    /// Market by keyboard (⌘2, ⌘F, ⇥, ↓, B) buys one unit with no click; ⌘7 focuses the map: ⌘= and → act on it.
    @MainActor
    func testDefaultFocusLetsMarketAndMapKeysWorkWithoutAClick() throws {
        // covers: UI-KEYS-027, UI-SHELL-064, MAP-015
        quickStart()
        openPage("bridge")
        focusMarketTableByKeyboard()
        type("b", [])
        expect("B bought one unit of the selected row (held: \(heldValues()))") { heldValues().values.contains("1") }
        openPage("galaxy")
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
        openPage("bridge")
        waitFor(AXID.Bridge.targetCard)
        // Choose a target so the card's Warp button is enabled (a disabled control is rightly outside the key loop).
        type("]")
        expect("⌘] chose a target") { self.element(AXID.Bridge.targetWarp).isEnabled }
        let bridgeOrder = tabCycle()
        try XCTSkipIf(bridgeOrder.count <= 1, """
            Full Keyboard Access is off on this Mac (Tab only reaches \(bridgeOrder)); turn on System Settings › Keyboard › \
            Keyboard navigation to run UI-KEYS-025/026 (QA-REPORT UI-KEYS-029).
            """)
        let attachment = XCTAttachment(string: bridgeOrder.joined(separator: "\n"))
        attachment.name = "bridge-tab-order"
        attachment.lifetime = .keepAlways
        add(attachment)
        let card = ["bridge.target.warp", "bridge.target.previous", "bridge.target.next"]
        let positions = card.compactMap { bridgeOrder.firstIndex(of: $0) }
        XCTAssertEqual(positions.count, card.count, "Tab reaches every target-card control (order: \(bridgeOrder))")
        XCTAssertEqual(positions, positions.sorted(), "the target-card controls follow their visual order")
        // Everything enabled and identified on the Bridge's target card is reachable.
        let reachable = Set(bridgeOrder)
        for e in element(AXID.Bridge.targetCard).buttons.allElementsBoundByIndex where e.isEnabled && !e.identifier.isEmpty {
            XCTAssertTrue(reachable.contains(e.identifier), "\(e.identifier) is reachable with Tab")
        }
        openPage("bridge")
        waitFor(AXID.Cargo.panel)
        let marketOrder = tabCycle()
        let m = XCTAttachment(string: marketOrder.joined(separator: "\n"))
        m.name = "market-tab-order"
        m.lifetime = .keepAlways
        add(m)
        let field = marketOrder.firstIndex(of: AXID.Cargo.quantity("water")), buy = marketOrder.firstIndex(of: AXID.Cargo.buy("water"))
        XCTAssertNotNil(field, "Tab reaches the first row's quantity field (order: \(marketOrder))")
        XCTAssertNotNil(buy, "Tab reaches the first row's Buy button (order: \(marketOrder))")
        if let field, let buy { XCTAssertLessThan(field, buy, "the quantity field comes before Buy") }
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
        openPage("bridge")
        focusMarketTableByKeyboard()
        type("b", [])
        expect("B bought one unit") { heldValues().values.contains("1") }
        openPage("bridge")
        waitFor(AXID.Bridge.targetCard)
        let before = targetName
        type("]")
        expect("⌘] changed the target (\(before) → \(targetName))") { targetName != before && !targetName.hasPrefix("Choose") }
        type("j")
        expect("⌘J warped to day 1") { day == "Day 1" }
        openPage("logbook")
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

    /// There is no toolbar: navigation is the dock bar and status is the status bar.
    @MainActor
    func testNoToolbarDockAndStatusBars() throws {
        // covers: UI-KEYS-031, UI-NAV-001, UI-SB-001
        quickStart()
        waitFor(AXID.Dock.bar)
        let toolbarIDs = mainWindow.toolbars.descendants(matching: .any).allElementsBoundByIndex.map(\.identifier)
            .filter { $0.contains(".") && !$0.hasPrefix("_") }
        XCTAssertEqual(toolbarIDs, [], "the window has no toolbar items of its own: \(toolbarIDs)")
        let dock = element(AXID.Dock.bar).frame, status = element(AXID.Status.bar).frame, window = mainWindow.frame
        XCTAssertLessThan(dock.minY, status.minY + 1, "the dock bar is above the status bar")
        XCTAssertLessThan(status.maxY, window.minY + window.height * 0.25, "both bars are at the top of the window")
        for page in ["bridge", "shipyard", "outfitter", "crew", "bank", "status", "quests", "galaxy", "logbook"] {
            XCTAssertTrue(element(AXID.Dock.button(page)).isHittable, "dock.\(page) is in view")
        }
        XCTAssertTrue(element(AXID.Status.cash).exists, "cash is always visible in the status bar")
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
        openPage("bridge")
        // Commander Status is a page (⌘6); Esc returns to the Bridge (UI-NAV-003).
        openPage("status")
        waitFor(AXID.Inspector.root)
        type(esc, [])
        waitFor("bridge.root")
        type("]")
        expect("⌘] selects a target") { !targetName.isEmpty && !targetName.hasPrefix("Choose") }
        let target = targetName
        type("]")
        expect("⌘] changes the target") { targetName != target }
        type("[")
        expect("⌘[ restores it") { targetName == target }
        type("f", [.command, .option])
        let find = waitFor("findSystem.sheet")
        type(esc, [])
        expect("Esc closes Find System") { !find.exists }
        openPage("bridge")
        waitFor(AXID.Cargo.panel)
        pause()
        type("f")
        let bridgeFind = waitFor("findSystem.sheet")  // ⌘F on the Bridge finds a system (the Target panel's Find…)
        type(esc, [])
        expect("Esc closes Find System") { !bridgeFind.exists }
        openPage("galaxy")
        waitFor(AXID.Galaxy.root)
        type("f")
        expect("⌘F on Galaxy focuses the map search") { hasFocus(AXID.Galaxy.section.searchField) }
        type(esc, [])
        openPage("logbook")
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
        openPage("bridge")
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
