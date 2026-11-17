// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

/// Flow 6 (A11Y-029): every catalog surface (A11Y-028) passes the label checks of A11Y-003 and
/// `performAccessibilityAudit(for: .all)` under the known-issue policy (A11Y-030); the dark appearance reruns the contrast
/// audit (A11Y-023). One test per catalog group, so a failure names its group and the other groups still run.
final class AccessibilityAuditUITests: ParsecUITestCase {
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = true
    }

    @MainActor
    func testFlow6ShellSurfaces() throws {
        // covers: A11Y-029, A11Y-028, A11Y-003, A11Y-006, A11Y-008, A11Y-030, MAP-087, INT-043, STAT-023, ACH-024, LOG-039
        try audit(.shell)
    }

    @MainActor
    func testFlow6EncounterSurfaces() throws {
        // covers: A11Y-029, A11Y-028, A11Y-003, A11Y-006, A11Y-030, UI-ENC-102
        try audit(.ambush)
    }

    @MainActor
    func testFlow6FixtureSurfaces() throws {
        // covers: A11Y-029, A11Y-028, A11Y-003, A11Y-030, UI-ENC-102
        try audit(.fixtures)
    }

    @MainActor
    func testFlow6DarkAppearanceContrast() throws {
        // covers: A11Y-023, A11Y-029
        let recorder = AuditRecorder()
        let dark = ["-AppleInterfaceStyle", "Dark"]
        relaunch(UITestFixtures.launchArguments + dark)
        click(AXID.Welcome.quickStart)
        expect("the Quick Start game runs") { subtitle.hasPrefix("Day 0") }
        for s in UISurfaceCatalog.sections {
            goToSection(s.key, root: s.root)
            attachScreenshot("qa-dark-section-\(s.name)")
            auditSurface(recorder, "dark-section-\(s.name)", types: .contrast, root: element(s.root))
        }
        relaunch(UITestFixtures.ambushLaunchArguments + dark)
        waitFor(AXID.Encounter.view)
        attachScreenshot("qa-dark-encounter")
        auditSurface(recorder, "dark-encounter", types: .contrast, root: element(AXID.Encounter.view))
        retireGame()
        waitFor(AXID.GameOver.card)
        attachScreenshot("qa-dark-game-over")
        auditSurface(recorder, "dark-game-over", types: .contrast, root: element(AXID.GameOver.card))
        reportStale(recorder)
    }

    // MARK: Flow

    private func audit(_ group: UISurfaceCatalog.Group) throws {
        let recorder = AuditRecorder()
        let surfaces = Set(UISurfaceCatalog.entries(in: group).map(\.name))
        // The stale-allowlist check runs even when a recipe step stops the test.
        addTeardownBlock { @MainActor [weak self] in self?.reportStale(recorder, surfaces: surfaces) }
        walk(group) { visited in
            let name = visited.surface.name
            if let snapshot = visited.snapshot {
                checkLabels(snapshot, surface: name)
            }
            if name == "section-market" { checkMarketColumnHeaders() }
            auditSurface(recorder, name, types: .all, root: visited.root)
        }
    }

    /// Audits one surface (A11Y-029) and fails with its issues. A surface with failures is audited once more after
    /// bringing the app to the front: another app's window passing over this one during the first audit would otherwise
    /// fail every text it covers. Real failures fail both times.
    private func auditSurface(_ recorder: AuditRecorder, _ name: String, types: XCUIAccessibilityAuditType, root: XCUIElement) {
        prepareForAudit()
        recorder.audit(app, surface: name, types: types, windowFrame: windowFrame(of: root),
                       scope: AuditScope.make(app: app, root: root))
        if !recorder.lastCallFailures.isEmpty {
            recorder.discardLastCall()
            RunLoop.current.run(until: Date().addingTimeInterval(1))
            prepareForAudit()
            recorder.audit(app, surface: name, types: types, windowFrame: windowFrame(of: root),
                           scope: AuditScope.make(app: app, root: root))
        }
        XCTAssertTrue(recorder.lastCallFailures.isEmpty, "A11Y-029 \(name): accessibility audit failures:\n"
                      + recorder.lastCallFailures.joined(separator: "\n"))
        if let a = recorder.ignoredAttachment(surface: name) { add(a) }
    }

    /// A11Y-030: an allowlist entry for a surface of this run that matched nothing is stale.
    private func reportStale(_ recorder: AuditRecorder, surfaces: Set<String>? = nil) {
        let stale = KnownAuditIssues.allowlist.filter { entry in
            (surfaces?.contains(entry.surface) ?? true) && !recorder.usedAllowlist.contains(entry)
        }
        XCTAssertTrue(stale.isEmpty, "stale AuditAllowlist entries: \(stale.map(\.feedback))")
    }

    private func windowFrame(of root: XCUIElement) -> CGRect? {
        guard root.exists else { return mainWindow.exists ? mainWindow.frame : nil }
        let windows = app.windows.allElementsBoundByIndex.filter { $0.exists }
        let rootFrame = root.frame
        return windows.first { $0.frame.contains(CGPoint(x: rootFrame.midX, y: rootFrame.midY)) }?.frame ?? mainWindow.frame
    }

    func attachScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: mainWindow.exists ? mainWindow.screenshot() : app.windows.firstMatch.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: A11Y-003 labels

    /// An SF Symbol name such as `chevron.right` or `plus.circle.fill`.
    static let symbolNamePattern = #"^[a-z0-9]+(\.[a-z0-9]+)+$"#

    func checkLabels(_ root: XCUIElementSnapshot, surface: String, file: StaticString = #filePath, line: UInt = #line) {
        var offenders: [String] = []
        func visit(_ e: XCUIElementSnapshot, ancestors: [XCUIElementSnapshot]) {
            if Self.labelledTypes.contains(e.elementType), !e.identifier.hasPrefix("_XCUI:"), !isChromeButton(e, ancestors: ancestors),
               !ancestors.contains(where: { $0.elementType == .scrollBar }) {
                let label = e.label.isEmpty ? e.title : e.label
                if let problem = Self.labelProblem(label: label, identifier: e.identifier) {
                    let path = ancestors.suffix(3).map { "\($0.elementType.rawValue):\($0.identifier)" }.joined(separator: ">")
                    offenders.append("  \(e.elementType.rawValue) id='\(e.identifier)' label='\(label)' frame=\(e.frame) in \(path): \(problem)")
                }
            }
            for child in e.children { visit(child, ancestors: ancestors + [e]) }
        }
        visit(root, ancestors: [])
        XCTAssertTrue(offenders.isEmpty, "A11Y-003 \(surface): interactive elements without a proper label:\n"
                      + offenders.joined(separator: "\n"), file: file, line: line)
    }

    static let labelledTypes: Set<XCUIElement.ElementType> = [
        .button, .checkBox, .switch, .toggle, .radioButton, .textField, .searchField, .comboBox, .slider, .stepper,
        .popUpButton, .menuButton, .link,
    ]

    /// A11Y-003: non-empty, not the identifier, not an SF Symbol name, no key cap.
    static func labelProblem(label: String, identifier: String) -> String? {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "empty label" }
        if trimmed == identifier { return "the label is the identifier" }
        if trimmed.range(of: symbolNamePattern, options: .regularExpression) != nil { return "the label is an SF Symbol name" }
        if trimmed.contains(where: { "⌘⌥⇧⌃".contains($0) }) { return "the label contains a key cap" }
        if identifier.hasPrefix("encounter.action."), trimmed.range(of: #" [A-Z]$"#, options: .regularExpression) != nil {
            return "the encounter button label ends with its key cap"
        }
        return nil
    }

    /// AppKit's own unlabelled buttons: table column headers belong to the header row, window buttons to the title bar.
    private func isChromeButton(_ e: XCUIElementSnapshot, ancestors: [XCUIElementSnapshot]) -> Bool {
        guard e.identifier.isEmpty else { return false }
        return ancestors.last?.elementType == .window
    }

    // MARK: A11Y-008 column headers

    private func checkMarketColumnHeaders() {
        let table = element(AXID.Market.table)
        guard let snap = try? table.snapshot() else { return XCTFail("snapshot of the Market table") }
        var titles: [String] = []
        func visit(_ e: XCUIElementSnapshot) {
            if e.elementType == .button, !e.title.isEmpty, e.identifier.isEmpty { titles.append(e.title) }
            if e.elementType == .tableColumn || e.elementType == .group { e.children.forEach(visit) }
        }
        snap.children.forEach(visit)
        for header in ["Item", "Buy", "Sell", "Held", "Target", "History", "Actions"] {
            XCTAssertTrue(titles.contains(header), "A11Y-008: the Market table exposes the column header \(header) (got \(titles))")
        }
    }
}
