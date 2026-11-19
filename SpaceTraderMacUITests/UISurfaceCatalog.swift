// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

/// One surface of the catalog: a name, the identifier of its root and the launch group whose recipe reaches it.
struct UISurface: Hashable {
    let name: String
    let root: String
    let group: UISurfaceCatalog.Group
}

/// A11Y-028: the one list of surfaces walked by flows 6 and 7, the pseudo-localization run and the README export. Each
/// group is one launch configuration; its recipe (`ParsecUITestCase.walk(_:arguments:visit:)`) reaches the entries in
/// order and hands each surface's root to the visitor. Every recipe step waits for the entry's root, so a walk proves the
/// recipe reaches it.
enum UISurfaceCatalog {
    enum Group: String, CaseIterable {
        /// The flow seed: Welcome, the sections, windows, Settings and the docked sheets.
        case shell
        /// `-PMScenario pirateAmbush`: the Encounter view, arrival card, newspaper, feed and game-over card.
        case ambush
        /// The Debug fixtures: plunder, trade in orbit, arrest report, narrative sheets and the transit view.
        case fixtures
    }

    static let sections: [(key: String, name: String, root: String)] = [
        ("bridge", "bridge", "bridge.root"), ("shipyard", "shipyard", "shipyard.root"), ("outfitter", "outfitter", "outfitter.root"),
        ("crew", "crew", "crew.root"), ("bank", "bank", "bank.root"), ("status", "status", "inspector.root"),
        ("quests", "quests", "quests.root"), ("galaxy", "galaxy", "galaxy.root"), ("logbook", "logbook", "logbook.root"),
    ]

    static let entries: [UISurface] = {
        var e: [UISurface] = [UISurface(name: "welcome", root: AXID.A11y.welcomeRoot, group: .shell)]
        e += sections.map { UISurface(name: "section-\($0.name)", root: $0.root, group: .shell) }
        e += [
            UISurface(name: "logbook-statistics", root: AXID.A11y.logbookStats, group: .shell),
            UISurface(name: "logbook-achievements", root: AXID.A11y.logbookAchievements, group: .shell),
            UISurface(name: "galaxy-legend-route", root: AXID.Galaxy.section.routePanel, group: .shell),
            UISurface(name: "system-intel-sheet", root: AXID.A11y.systemIntelSheet, group: .shell),
            UISurface(name: "galaxy-window", root: AXID.Galaxy.windowRoot, group: .shell),
            UISurface(name: "high-scores-window", root: AXID.Scores.window, group: .shell),
            UISurface(name: "about-window", root: AXID.A11y.aboutWindow, group: .shell),
            UISurface(name: "about-license", root: AXID.A11y.aboutLicenseClose, group: .shell),
            UISurface(name: "help-window", root: AXID.A11y.helpWindow, group: .shell),
        ]
        e += AXID.A11y.settingsTabs.map { UISurface(name: "settings-\($0)", root: AXID.A11y.settingsTabProbe[$0] ?? "", group: .shell) }
        e += [
            UISurface(name: "options-sheet", root: AXID.Options.sheet, group: .shell),
            UISurface(name: "open-sheet", root: AXID.Files.list, group: .shell),
            UISurface(name: "delete-confirmation", root: AXID.A11y.appConfirmationCancel, group: .shell),
            UISurface(name: "find-system-sheet", root: AXID.A11y.findSystemSheet, group: .shell),
            UISurface(name: "ship-purchase-sheet", root: AXID.A11y.shipPurchaseSheet, group: .shell),
            UISurface(name: "retire-sheet", root: AXID.Dialog.retireSheet, group: .shell),
        ]
        e += (1...6).map { UISurface(name: "wizard-page-\($0)", root: AXID.NewGame.sheet, group: .shell) }
        e += [
            UISurface(name: "encounter-before-attack", root: AXID.Encounter.tactical, group: .ambush),
            UISurface(name: "encounter-after-attack", root: AXID.Encounter.logRow(1), group: .ambush),
            UISurface(name: "arrival-card", root: AXID.Report.sheet, group: .ambush),
            UISurface(name: "newspaper-sheet", root: AXID.Newspaper.sheet, group: .ambush),
            UISurface(name: "feed-overlay", root: AXID.A11y.feedList, group: .ambush),
            UISurface(name: "game-over-card", root: AXID.GameOver.card, group: .ambush),
            UISurface(name: "plunder-sheet", root: AXID.Decision.plunderSheet, group: .fixtures),
            UISurface(name: "trade-in-orbit-sheet", root: AXID.Decision.tradeSheet, group: .fixtures),
            UISurface(name: "arrest-report-sheet", root: AXID.Report.sheet, group: .fixtures),
            UISurface(name: "narrative-card", root: AXID.Narrative.bridgeCard, group: .fixtures),
            UISurface(name: "narrative-offer-sheet", root: AXID.Narrative.sheet, group: .fixtures),
            UISurface(name: "transit-view", root: AXID.Transit.view, group: .fixtures),
        ]
        return e
    }()

    static func entries(in group: Group) -> [UISurface] { entries.filter { $0.group == group } }
}

/// What a walk hands the visitor: the surface, its root element and a snapshot taken right away (the transit view
/// exists for about a second).
struct VisitedSurface {
    let surface: UISurface
    let root: XCUIElement
    let snapshot: XCUIElementSnapshot?
}

extension ParsecUITestCase {
    typealias SurfaceVisitor = (VisitedSurface) -> Void

    /// Walks one catalog group under `extra` launch arguments (dark appearance, Text Size, pseudo-languages) and returns
    /// the names visited, in order.
    @discardableResult
    func walk(_ group: UISurfaceCatalog.Group, extra requested: [String] = [], visit: SurfaceVisitor) -> [String] {
        // The light appearance unless the caller chose one (the machine may run in Dark mode, A11Y-023).
        let extra = requested.contains("-PMAppearance") ? requested : requested + ["-PMAppearance", "light"]
        var visited: [String] = []
        func reach(_ name: String, _ rootElement: XCUIElement? = nil, file: StaticString = #filePath, line: UInt = #line) {
            guard let surface = UISurfaceCatalog.entries.first(where: { $0.name == name }) else {
                return XCTFail("\(name) is not in the catalog", file: file, line: line)
            }
            let root = rootElement ?? waitFor(surface.root, file: file, line: line)
            guard root.exists else {
                return XCTFail("\(name): its recipe reaches \(surface.root)", file: file, line: line)
            }
            visited.append(name)
            visit(VisitedSurface(surface: surface, root: root, snapshot: try? root.snapshot()))
        }
        switch group {
        case .shell: walkShell(extra: extra, reach: reach)
        case .ambush: walkAmbush(extra: extra, reach: reach)
        case .fixtures: walkFixtures(extra: extra, reach: reach)
        }
        let expected = UISurfaceCatalog.entries(in: group).map(\.name)
        XCTAssertEqual(visited, expected, "A11Y-028: the \(group) recipe visits every catalog entry in order")
        return visited
    }

    typealias Reach = (String, XCUIElement?, StaticString, UInt) -> Void

    private func walkShell(extra: [String], reach: (String, XCUIElement?, StaticString, UInt) -> Void) {
        func at(_ name: String, _ e: XCUIElement? = nil, file: StaticString = #filePath, line: UInt = #line) {
            reach(name, e, file, line)
        }
        relaunch(UITestFixtures.launchArguments(seed: UITestFixtures.shellWalkSeed) + extra)
        at("welcome")
        click(AXID.Welcome.quickStart)
        expect("the Quick Start game runs") { quickStartRuns }
        type("s")  // a saved slot gives the Open sheet a row
                for s in UISurfaceCatalog.sections {
            goToSection(s.key, root: s.root)
            at("section-\(s.name)", element(s.root))
        }
        selectLogbookTab("Statistics")
        at("logbook-statistics")
        selectLogbookTab("Achievements")
        at("logbook-achievements")
        selectLogbookTab("Captain's Log")

        openPage("bridge")
        click(AXID.Bridge.targetNext)
        openPage("galaxy")
        waitFor(AXID.Galaxy.root)
        let g = AXID.Galaxy.section
        for _ in 0..<2 where !element(g.legend).waitForExistence(timeout: 2) { click(g.legendToggle) }
        waitFor(g.legend)
        chooseMenuItem("Game", "Plot Route…")
        at("galaxy-legend-route", waitFor(g.routePanel))
        // The hover card appears after a delay and re-renders the map, which would close an open context menu: let it
        // settle before the right click, and retry the menu once.
        let system = visibleSystem(in: g)
        if system.waitForExistence(timeout: timeout) {
            for _ in 0..<3 where !element(AXID.A11y.systemIntelSheet).exists {
                system.hover()
                RunLoop.current.run(until: Date().addingTimeInterval(1.2))
                system.rightClick()
                let item = element(AXID.A11y.galaxyFindPrices)
                if item.waitForExistence(timeout: 3) {
                    item.click()
                } else {
                    type(XCUIKeyboardKey.escape.rawValue, [])
                }
                _ = element(AXID.A11y.systemIntelSheet).waitForExistence(timeout: 3)
            }
        }
        at("system-intel-sheet")
        click(AXID.A11y.systemIntelDone)
        expect("the system intel sheet closes") { !element(AXID.A11y.systemIntelSheet).exists }
        click(g.routeClear)

        type("m", [.command, .shift])
        at("galaxy-window", waitFor(AXID.Galaxy.windowRoot))
        type("w")
        expect("the Galaxy Chart window closes") { !element(AXID.Galaxy.windowRoot).exists }

        menuBarItem("Window").click()
        let highScores = menuItem("Window", "High Scores").firstMatch
        XCTAssertTrue(highScores.waitForExistence(timeout: timeout), "Window › High Scores exists")
        highScores.click()
        at("high-scores-window", waitFor(AXID.Scores.window))
        type("w")
        expect("the High Scores window closes") { !element(AXID.Scores.window).exists }

        chooseMenuItem("Parsec Merchant", "About Parsec Merchant")
        at("about-window", waitFor(AXID.A11y.aboutWindow))
        click(AXID.A11y.aboutLicense)
        at("about-license", waitFor(AXID.A11y.aboutLicenseClose))
        click(AXID.A11y.aboutLicenseClose)
        expect("the license sheet closes") { !element(AXID.A11y.aboutLicenseClose).exists }
        type("w")
        expect("the About window closes") { !element(AXID.A11y.aboutWindow).exists }

        chooseMenuItem("Help", "Parsec Merchant Help")
        at("help-window", waitFor(AXID.A11y.helpWindow))
        type("w")
        expect("the Help window closes") { !element(AXID.A11y.helpWindow).exists }

        type(",")
        for tab in AXID.A11y.settingsTabs {
            selectSettingsTab(tab)
            at("settings-\(tab)", waitFor(AXID.A11y.settingsTabProbe[tab] ?? ""))
        }
        selectSettingsTab("general")
        type("w")
        expect("Settings closes") { !element(AXID.A11y.settingsTextSize).exists }

        type("o", [.command, .option])
        at("options-sheet", waitFor(AXID.Options.sheet))
        click(AXID.Options.cancel)
        expect("the options sheet closes") { !element(AXID.Options.sheet).exists }

        type("o")
        at("open-sheet", waitFor(AXID.Files.list))
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", AXID.Files.rowPrefix)).firstMatch
        if row.waitForExistence(timeout: timeout) { row.click() }
        click(AXID.A11y.openSavedDelete)
        at("delete-confirmation", waitFor(AXID.A11y.appConfirmationCancel))
        click(AXID.A11y.appConfirmationCancel)
        click(AXID.Files.cancel)
        expect("the Open sheet closes") { !element(AXID.Files.list).exists }

        type("f", [.command, .option])
        at("find-system-sheet", waitFor(AXID.A11y.findSystemSheet))
        click(AXID.A11y.findSystemCancel)
        expect("Find System closes") { !element(AXID.A11y.findSystemSheet).exists }

        openPage("shipyard")
        let buy = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'shipyard.ship.' AND identifier ENDSWITH '.buy'")).firstMatch
        if buy.waitForExistence(timeout: timeout) { buy.click() }
        at("ship-purchase-sheet", waitFor(AXID.A11y.shipPurchaseSheet))
        // Close it only when it opened, so a missed step fails once and the walk goes on.
        if element(AXID.A11y.shipPurchaseCancel).exists { click(AXID.A11y.shipPurchaseCancel) }
        expect("the purchase review closes") { !element(AXID.A11y.shipPurchaseSheet).exists }

        chooseMenuItem("Game", "Retire…")
        at("retire-sheet", waitFor(AXID.Dialog.retireSheet))
        click(AXID.A11y.retireCancel)
        expect("the retire sheet closes") { !element(AXID.Dialog.retireSheet).exists }

        type("n")
        if element(AXID.Dialog.appConfirmationConfirm).waitForExistence(timeout: 2) { click(AXID.Dialog.appConfirmationConfirm) }
        for page in 1...6 {
            at("wizard-page-\(page)", waitFor(AXID.NewGame.sheet))
            // The skills page lets Next through only once every point is spent.
            if page == 4 { click(AXID.NewGame.balanced) }
            if page < 6 { click(AXID.NewGame.next) }
        }
        click(AXID.NewGame.cancel)
        openPage("bridge")
    }

    private func walkAmbush(extra: [String], reach: (String, XCUIElement?, StaticString, UInt) -> Void) {
        func at(_ name: String, _ e: XCUIElement? = nil, file: StaticString = #filePath, line: UInt = #line) {
            reach(name, e, file, line)
        }
        relaunch(UITestFixtures.ambushLaunchArguments + extra)
        waitFor(AXID.Encounter.tactical)
        at("encounter-before-attack", waitFor(AXID.Encounter.view))
        attackOnce(waitFor(AXID.Encounter.attack))
        waitFor(AXID.Encounter.logRow(1))
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))  // let the combat effects and screen shake finish
        at("encounter-after-attack", waitFor(AXID.Encounter.view))
        let view = element(AXID.Encounter.view)
        var presses = 0
        // Attack until the arrival card shows (a click can be lost while the app is not frontmost).
        let deadline = Date().addingTimeInterval(60)
        while element(AXID.Encounter.view).exists, presses < UITestFixtures.ambushMaxAttacks * 2, Date() < deadline {
            let attack = element(AXID.Encounter.attack)
            if attack.exists, attack.isEnabled {
                attackOnce(attack)
                presses += 1
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        expect("the encounter ends") { !view.exists }
        // A trip ends on the Bridge with its summary in the status bar (UI-BRG-042); the report opens from it.
        waitFor(AXID.Arrival.card)
        at("arrival-card", openArrivalReport())
        closeArrivalReport()
        type("n", [.command, .shift])
        if element(AXID.Dialog.confirmationConfirm).waitForExistence(timeout: 2) { click(AXID.Dialog.confirmationConfirm) }
        at("newspaper-sheet", waitFor(AXID.Newspaper.sheet))
        click(AXID.Newspaper.close)
        expect("the newspaper closes") { !element(AXID.Newspaper.sheet).exists }
        click(AXID.Status.feed)
        at("feed-overlay", waitFor(AXID.A11y.feedList))
        click(AXID.A11y.feedClose)
        retireGame()
        at("game-over-card", waitFor(AXID.GameOver.card))
    }

    private func walkFixtures(extra: [String], reach: (String, XCUIElement?, StaticString, UInt) -> Void) {
        func at(_ name: String, _ e: XCUIElement? = nil, file: StaticString = #filePath, line: UInt = #line) {
            reach(name, e, file, line)
        }
        relaunch(UITestFixtures.encounterFixtureArguments("pirateSurrender") + extra)
        click(AXID.Encounter.plunder)
        at("plunder-sheet", waitFor(AXID.Decision.plunderSheet))
        click(AXID.Decision.plunderDone)

        relaunch(UITestFixtures.encounterFixtureArguments("traderSell") + extra)
        click(AXID.Encounter.trade)
        at("trade-in-orbit-sheet", waitFor(AXID.Decision.tradeSheet))
        click(AXID.Decision.tradeDecline)

        relaunch(UITestFixtures.encounterFixtureArguments("policeAttack") + extra)
        click(AXID.Encounter.surrender)
        if element(AXID.Dialog.confirmationConfirm).waitForExistence(timeout: 2) { click(AXID.Dialog.confirmationConfirm) }
        at("arrest-report-sheet", waitFor(AXID.Report.sheet))
        click(AXID.Report.continueButton)

        relaunch(UITestFixtures.specialEventArguments + extra)
        openPage("bridge")
        at("narrative-card", waitFor(AXID.Narrative.bridgeCard))
        click(AXID.Narrative.bridgeAccept)
        at("narrative-offer-sheet", waitFor(AXID.Narrative.sheet))
        click(AXID.Narrative.decline)

        // A played-back trip lasts 1.2 s, too short to walk reliably: the Transit view of a game resting in transit stays
        // up (the same view, frozen at its click, UI-ENC-013).
        relaunch(UITestFixtures.transitArguments + extra)
        at("transit-view", waitFor(AXID.Transit.view))
    }

    /// A system element of the map that lies inside the map's visible frame and outside its HUD corners (the window may
    /// open at another size, which moves systems out of view).
    func visibleSystem(in g: AXID.Map) -> XCUIElement {
        let map = waitFor(g.map)
        guard let snap = try? map.snapshot() else { return element(g.system(UITestFixtures.mapFlowTarget)) }
        let safe = snap.frame.insetBy(dx: snap.frame.width * 0.3, dy: snap.frame.height * 0.3)
        var found: String?
        func visit(_ e: XCUIElementSnapshot) {
            if found == nil, e.identifier.hasPrefix("\(g.p).system."), !e.label.contains("current system"),
               safe.contains(CGPoint(x: e.frame.midX, y: e.frame.midY)) {
                found = e.identifier
            }
            e.children.forEach(visit)
        }
        visit(snap)
        return element(found ?? g.system(UITestFixtures.mapFlowTarget))
    }

    /// Attack with its key (A, the Encounter menu): at a large Text Size the button can sit below the visible area.
    func attackOnce(_ attack: XCUIElement) {
        _ = attack
        type("a", [])
    }

    /// ⌘<key> until the section root shows (a key press can be lost while another app is frontmost).
    func goToSection(_ key: String, root: String, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<3 where !element(root).exists {
            app.activate()
            openPage(key)
            _ = element(root).waitForExistence(timeout: 4)
        }
        waitFor(root, file: file, line: line)
    }

    /// Game › Retire… and confirm, retried once.
    func retireGame(file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<2 where !element(AXID.Dialog.retireSheet).exists {
            chooseMenuItem("Game", "Retire…", file: file, line: line)
            _ = element(AXID.Dialog.retireSheet).waitForExistence(timeout: 4)
        }
        click(AXID.Dialog.retireConfirm, file: file, line: line)
    }

    /// Selects a Settings tab: by identifier, else by its toolbar title (SwiftUI may not expose the Tab identifier).
    func selectSettingsTab(_ tab: String) {
        let titles = ["general": "General", "sound": "Sound", "intelligence": "Intelligence", "advanced": "Advanced"]
        let byID = element(AXID.A11y.settingsTab(tab))
        if byID.waitForExistence(timeout: 2) {
            byID.click()
        } else if let title = titles[tab] {
            let inToolbar = pseudoLocalized ? app.toolbars.buttons.matching(titlePredicate(title)).firstMatch : app.toolbars.buttons[title]
            let anywhere = pseudoLocalized ? app.buttons.matching(titlePredicate(title)).firstMatch : app.buttons[title].firstMatch
            let button = inToolbar.exists ? inToolbar : anywhere
            if button.waitForExistence(timeout: timeout) { button.click() }
        }
    }

    /// Selects a Logbook tab by title (the tab control is a segmented picker).
    func selectLogbookTab(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let control = waitFor(AXID.Logbook.tab, file: file, line: line)
        let match = titlePredicate(title)
        let candidates = pseudoLocalized
            ? [control.radioButtons.matching(match).firstMatch, control.buttons.matching(match).firstMatch,
               control.descendants(matching: .any).matching(match).firstMatch]
            : [control.radioButtons[title], control.buttons[title], control.descendants(matching: .any)[title]]
        guard let segment = candidates.first(where: { $0.exists }) else { return XCTFail("tab \(title)", file: file, line: line) }
        // A click right after an audit can be dropped while the app is still busy: retry until the segment is selected.
        for _ in 0..<3 where !segment.isSelected {
            segment.click()
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
    }
}
