// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

/// UI-SHELL-127: every interactive element of every M7 surface carries an identifier of the Conventions scheme.
final class IdentifierWalkUITests: ParsecUITestCase {
    @MainActor
    func testEveryInteractiveElementHasASchemeIdentifier() throws {
        // covers: UI-SHELL-127
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

    // MARK: Walk

    private static let interactive: Set<XCUIElement.ElementType> = [
        .button, .checkBox, .switch, .toggle, .radioButton, .textField, .secureTextField, .textView, .searchField,
        .comboBox, .slider, .stepper, .incrementArrow, .decrementArrow, .popUpButton, .menuButton, .segmentedControl,
        .tableRow, .outlineRow, .link,
    ]

    private func sheet() -> XCUIElement { mainWindow.sheets.firstMatch }

    /// Asserts every interactive element under `root` has an identifier matching the scheme.
    private func walk(_ root: XCUIElement, surface: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let snapshot = try? root.snapshot() else { return XCTFail("snapshot of \(surface)", file: file, line: line) }
        var offenders: [String] = []
        var checked = 0
        visit(snapshot, ancestors: [], offenders: &offenders, checked: &checked)
        XCTAssertGreaterThan(checked, 0, "\(surface) has interactive elements", file: file, line: line)
        XCTAssertTrue(offenders.isEmpty, "\(surface): elements without a scheme identifier:\n" + offenders.joined(separator: "\n"),
                      file: file, line: line)
    }

    private func visit(_ e: XCUIElementSnapshot, ancestors: [XCUIElementSnapshot], offenders: inout [String], checked: inout Int) {
        if isSystemChrome(e, ancestors: ancestors) { return }
        // Stepper arrows belong to their stepper, whose identifier is checked.
        if Self.interactive.contains(e.elementType), e.elementType != .incrementArrow, e.elementType != .decrementArrow {
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
    private func hasSchemeIdentifier(_ e: XCUIElementSnapshot) -> Bool {
        if matchesScheme(e.identifier) { return true }
        guard e.elementType == .tableRow || e.elementType == .outlineRow else { return false }
        return containsSchemeIdentifier(e)
    }

    private func containsSchemeIdentifier(_ e: XCUIElementSnapshot) -> Bool {
        e.children.contains { matchesScheme($0.identifier) || containsSchemeIdentifier($0) }
    }

    private func matchesScheme(_ id: String) -> Bool {
        !id.isEmpty && id.range(of: AXID.pattern, options: .regularExpression) != nil
    }

    /// Controls AppKit adds on its own: window buttons, scroll bars, table column headers and the split view's
    /// sidebar toggle. None of them is app content.
    private func isSystemChrome(_ e: XCUIElementSnapshot, ancestors: [XCUIElementSnapshot]) -> Bool {
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
    private func isTableHeader(_ group: XCUIElementSnapshot) -> Bool {
        !group.children.isEmpty && group.children.allSatisfy { $0.elementType == .button && !$0.title.isEmpty }
    }
}
