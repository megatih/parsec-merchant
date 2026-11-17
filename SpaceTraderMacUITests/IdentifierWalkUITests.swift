// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

/// UI-SHELL-127: every interactive element of every M7 surface carries an identifier of the Conventions scheme.
final class IdentifierWalkUITests: ParsecUITestCase {
    @MainActor
    func testEveryInteractiveElementHasASchemeIdentifier() throws {
        // covers: UI-SHELL-127, MAP-104, MAP-086, MAP-032, MAP-027
        click(AXID.Welcome.quickStart)
        expect("the Quick Start game runs") { subtitle.hasPrefix("Day 0") }
        type("s")                                         // a saved slot gives the Open sheet a row to walk

        if !element(AXID.Inspector.root).exists { click(AXID.Toolbar.inspector) }
        waitFor(AXID.Inspector.root)
        for section in AXID.sections {
            type(section.key)
            waitFor(section.root)
            walk(mainWindow, surface: "section \(section.root) with the inspector")
        }

        // MAP-104: the Galaxy section with the legend and a planned route, and the Galaxy Chart window.
        type("1")
        click(AXID.Bridge.targetNext)
        type("7")
        waitFor(AXID.Galaxy.root)
        click(AXID.Galaxy.section.legendToggle)
        waitFor(AXID.Galaxy.section.legend)
        chooseMenuItem("Game", "Plot Route…")
        waitFor(AXID.Galaxy.section.routePanel)
        walk(mainWindow, surface: "Galaxy section with legend and route")
        XCTAssertTrue(element(AXID.Galaxy.section.system(0)).exists, "system accessibility children carry identifiers")
        type("m", [.command, .shift])
        let galaxyWindow = app.windows.matching(identifier: "galaxy").firstMatch
        waitFor(AXID.Galaxy.windowRoot)
        walk(galaxyWindow.exists ? galaxyWindow : app.windows.firstMatch, surface: "Galaxy Chart window")
        type("w")
        expect("the Galaxy Chart window closes") { !element(AXID.Galaxy.windowRoot).exists }

        type("o", [.command, .option])
        waitFor(AXID.Options.sheet)
        walk(sheet(), surface: "options sheet")
        click(AXID.Options.cancel)
        expect("the options sheet closes") { !element(AXID.Options.sheet).exists }

        type("o")
        waitFor(AXID.Files.list)
        walk(sheet(), surface: "Open sheet")
        click(AXID.Files.cancel)
        expect("the Open sheet closes") { !element(AXID.Files.list).exists }

        type("n")
        if element(AXID.Dialog.appConfirmationConfirm).waitForExistence(timeout: 2) {
            click(AXID.Dialog.appConfirmationConfirm)
        }
        waitFor(AXID.NewGame.sheet)
        for page in 1...6 {
            walk(sheet(), surface: "wizard page \(page)")
            if page < 6 { click(AXID.NewGame.next) }
        }
        click(AXID.NewGame.cancel)
    }
}

// MARK: Walk

/// The identifier walk shared by the M7/M8 surfaces and the M9 surfaces (UI-SHELL-127, UI-ENC-096).
extension ParsecUITestCase {

    static let interactiveTypes: Set<XCUIElement.ElementType> = [
        .button, .checkBox, .switch, .toggle, .radioButton, .textField, .secureTextField, .textView, .searchField,
        .comboBox, .slider, .stepper, .incrementArrow, .decrementArrow, .popUpButton, .menuButton, .segmentedControl,
        .tableRow, .outlineRow, .link,
    ]

    func sheet() -> XCUIElement { mainWindow.sheets.firstMatch }

    /// Asserts every interactive element under `root` has an identifier matching the scheme.
    func walk(_ root: XCUIElement, surface: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let snapshot = try? root.snapshot() else { return XCTFail("snapshot of \(surface)", file: file, line: line) }
        walk(snapshot, surface: surface, file: file, line: line)
    }

    /// The walk over a snapshot already taken (for surfaces that exist only briefly, such as the transit playback).
    func walk(_ snapshot: XCUIElementSnapshot, surface: String, file: StaticString = #filePath, line: UInt = #line) {
        var offenders: [String] = []
        var checked = 0
        visit(snapshot, ancestors: [], offenders: &offenders, checked: &checked)
        XCTAssertGreaterThan(checked, 0, "\(surface) has interactive elements", file: file, line: line)
        XCTAssertTrue(offenders.isEmpty, "\(surface): elements without a scheme identifier:\n" + offenders.joined(separator: "\n"),
                      file: file, line: line)
    }

    fileprivate func visit(_ e: XCUIElementSnapshot, ancestors: [XCUIElementSnapshot], offenders: inout [String], checked: inout Int) {
        if isSystemChrome(e, ancestors: ancestors) { return }
        // Stepper arrows belong to their stepper, whose identifier is checked.
        if Self.interactiveTypes.contains(e.elementType), e.elementType != .incrementArrow, e.elementType != .decrementArrow {
            checked += 1
            if !hasSchemeIdentifier(e) {
                offenders.append("  \(e.elementType.rawValue) label='\(e.label)' title='\(e.title)' id='\(e.identifier)'")
            }
        }
        for child in e.children {
            visit(child, ancestors: ancestors + [e], offenders: &offenders, checked: &checked)
        }
    }

    /// Table and outline rows are drawn by AppKit and take no SwiftUI identifier: their content carries it
    /// (`market.row.<item>`, `sidebar.<section>`, `openSaved.row.<slot>`).
    fileprivate func hasSchemeIdentifier(_ e: XCUIElementSnapshot) -> Bool {
        if matchesScheme(e.identifier) { return true }
        guard e.elementType == .tableRow || e.elementType == .outlineRow else { return false }
        return containsSchemeIdentifier(e)
    }

    fileprivate func containsSchemeIdentifier(_ e: XCUIElementSnapshot) -> Bool {
        e.children.contains { matchesScheme($0.identifier) || containsSchemeIdentifier($0) }
    }

    fileprivate func matchesScheme(_ id: String) -> Bool {
        !id.isEmpty && id.range(of: AXID.pattern, options: .regularExpression) != nil
    }

    /// Controls AppKit adds on its own: window buttons, scroll bars, table column headers and the split view's
    /// sidebar toggle. None of them is app content.
    fileprivate func isSystemChrome(_ e: XCUIElementSnapshot, ancestors: [XCUIElementSnapshot]) -> Bool {
        if e.identifier.hasPrefix("_XCUI:") || e.elementType == .scrollBar { return true }
        if e.elementType == .button, e.identifier.isEmpty, ancestors.count >= 2 {
            let header = ancestors[ancestors.count - 1], table = ancestors[ancestors.count - 2]
            if header.elementType == .group, [.table, .outline].contains(table.elementType), isTableHeader(header) { return true }
        }
        if e.elementType == .button, e.identifier.isEmpty, ["Hide Sidebar", "Show Sidebar"].contains(e.label) {
            return true
        }
        return false
    }

    /// A table's header row: a group, directly in the table, of titled column buttons.
    fileprivate func isTableHeader(_ group: XCUIElementSnapshot) -> Bool {
        !group.children.isEmpty && group.children.allSatisfy { $0.elementType == .button && !$0.title.isEmpty }
    }
}
