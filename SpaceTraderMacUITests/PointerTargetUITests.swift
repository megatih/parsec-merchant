// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

/// UI-PTR-002: every hittable button-type element with an app identifier is at least a 36 pt target on its short side.
final class PointerTargetUITests: ParsecUITestCase {
    static let minimum: CGFloat = 36

    /// Standard controls the system already expands for touch, exempt by element type.
    static let exemptTypes: Set<XCUIElement.ElementType> = [.stepper, .incrementArrow, .decrementArrow, .slider, .checkBox, .popUpButton, .menuItem,
                                                            .menuButton, .menuBarItem, .tableRow, .cell, .toolbarButton, .segmentedControl,
                                                            .radioButton, .disclosureTriangle, .link]

    @MainActor
    func testShellSurfacesHave36PointTargets() throws {
        // covers: UI-PTR-002, UI-PTR-013, UI-PTR-015
        check(.shell)
    }

    @MainActor
    func testEncounterSurfacesHave36PointTargets() throws {
        // covers: UI-PTR-002, UI-PTR-014
        check(.ambush)
    }

    @MainActor
    func testFixtureSurfacesHave36PointTargets() throws {
        // covers: UI-PTR-002, UI-PTR-007, UI-PTR-009
        check(.fixtures)
    }

    private func check(_ group: UISurfaceCatalog.Group) {
        var offenders: [String] = []
        var measured = 0
        walk(group) { visited in
            let window = windowElement(containing: visited.root)
            guard let snapshot = (try? window.snapshot()) ?? visited.snapshot else { return }
            visit(snapshot, window: window.frame, insideExempt: false) { e in
                measured += 1
                let short = min(e.frame.width, e.frame.height)
                if short < Self.minimum - 0.5 {
                    offenders.append("\(visited.surface.name): \(e.identifier) is \(Int(e.frame.width))×\(Int(e.frame.height))")
                }
            }
        }
        XCTAssertGreaterThan(measured, 10, "the walk measured buttons")
        let unique = Array(Set(offenders)).sorted()
        XCTAssertTrue(unique.isEmpty, "UI-PTR-002: \(unique.count) targets under 36 pt:\n" + unique.joined(separator: "\n"))
    }

    /// Calls `body` for every button with an app identifier that is on screen, skipping exempt controls and their parts
    /// (a toolbar's items, a stepper's arrows, a table's cells are measured as the system lays them out).
    private func visit(_ e: XCUIElementSnapshot, window: CGRect, insideExempt: Bool, body: (XCUIElementSnapshot) -> Void) {
        let exempt = insideExempt || Self.exemptTypes.contains(e.elementType) || e.elementType == .toolbar || e.elementType == .menuBar
            || e.elementType == .menu
        if !exempt, e.elementType == .button, Self.isAppIdentifier(e.identifier), e.isEnabled, e.frame.width > 0, e.frame.height > 0,
           window.contains(CGPoint(x: e.frame.midX, y: e.frame.midY)) {
            body(e)
        }
        for child in e.children { visit(child, window: window, insideExempt: exempt, body: body) }
    }

    /// App identifiers are dotted lower-camel names ("market.row.water.buy"); system ones start with an underscore.
    static func isAppIdentifier(_ id: String) -> Bool {
        // `appConfirmation.*` are the buttons of the system's confirmation dialog: the system lays them out and sizes
        // their touch targets, like the window controls.
        !id.isEmpty && !id.hasPrefix("_") && id.contains(".") && !id.hasPrefix("com.apple") && !id.hasPrefix("appConfirmation.")
    }
}
