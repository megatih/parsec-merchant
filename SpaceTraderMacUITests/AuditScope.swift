// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import XCTest

/// The surface an audit is about (A11Y-029): the sheet showing it, else its window. `performAccessibilityAudit` runs over
/// the whole app, so the flow classifies each issue against a snapshot of this container: elements outside it (the window
/// dimmed behind a sheet, other windows, rows scrolled out of view) belong to other surfaces, and the containers AppKit
/// builds for table cells are recognised as chrome (A11Y-030 rule 1).
@MainActor
struct AuditScope {
    /// The on-screen frame of the sheet or window.
    var visible: CGRect
    /// Every element of the container, keyed by role and frame.
    var keys: Set<String>
    /// Unlabelled groups AppKit puts around table and outline cells and header cells.
    var tableContainers: Set<String>

    nonisolated static func key(_ type: XCUIElement.ElementType, _ f: CGRect) -> String {
        "\(type.rawValue)|\(Int(f.minX.rounded()))|\(Int(f.minY.rounded()))|\(Int(f.width.rounded()))|\(Int(f.height.rounded()))"
    }

    static let rowTypes: Set<XCUIElement.ElementType> = [.tableRow, .outlineRow, .cell, .tableColumn]
    static let tableTypes: Set<XCUIElement.ElementType> = [.table, .outline]
    /// Containers that scroll their content (rows outside their frame are not drawn).
    static let clippingTypes: Set<XCUIElement.ElementType> = [.scrollView, .table, .outline, .collectionView]

    /// The screen area windows can use (without the menu bar and the Dock), in the top-left coordinates of XCUIElement.
    /// A part of a window under the Dock is not visible, so its text cannot be measured.
    static var screenVisibleFrame: CGRect {
        guard let screen = NSScreen.screens.first else { return .infinite }
        let v = screen.visibleFrame
        return CGRect(x: v.minX, y: screen.frame.maxY - v.maxY, width: v.width, height: v.height)
    }

    /// The scope of the sheet or window that shows `root`.
    @MainActor
    static func make(app: XCUIApplication, root: XCUIElement) -> AuditScope? {
        guard root.exists else { return nil }
        let f = root.frame
        let center = CGPoint(x: f.midX, y: f.midY)
        let sheet = app.sheets.allElementsBoundByIndex.first { $0.exists && $0.frame.contains(center) }
        let window = app.windows.allElementsBoundByIndex.first { $0.exists && $0.frame.contains(center) }
        guard let container = sheet ?? window, let snapshot = try? container.snapshot() else { return nil }
        var scope = AuditScope(visible: container.frame, keys: [], tableContainers: [])
        scope.collect(snapshot, parent: nil, grandparent: nil, clip: container.frame.intersection(screenVisibleFrame))
        return scope
    }

    /// `clip`: the visible area so far (the container, narrowed by each enclosing scroll view).
    private mutating func collect(_ e: XCUIElementSnapshot, parent: XCUIElementSnapshot?, grandparent: XCUIElementSnapshot?,
                                  clip: CGRect) {
        let inner = Self.clippingTypes.contains(e.elementType) ? clip.intersection(e.frame) : clip
        let k = Self.key(e.elementType, e.frame)
        // Only elements on screen count as the surface (rows scrolled out of a scroll view are not drawn).
        if e.frame.intersects(inner) { keys.insert(k) }
        if e.elementType == .group, e.identifier.isEmpty, let parent {
            let inRow = Self.rowTypes.contains(parent.elementType)
            // The header row is a group directly in the table; its cells are groups in that row.
            let inHeader = parent.elementType == .group && grandparent.map { Self.tableTypes.contains($0.elementType) } == true
            let isHeaderRow = Self.tableTypes.contains(parent.elementType)
            if inRow || inHeader || isHeaderRow { tableContainers.insert(k) }
        }
        for child in e.children { collect(child, parent: e, grandparent: parent, clip: inner) }
    }

    /// Marks whether the issue's element is in this scope and on screen, and whether it is a table container.
    func classify(_ facts: inout KnownAuditIssues.IssueFacts) {
        guard facts.hasElement, facts.frame != .zero else { return }
        let k = Self.key(facts.elementType, facts.frame)
        facts.inScope = keys.contains(k)
        facts.isTableContainer = tableContainers.contains(k)
    }
}

extension ParsecUITestCase {
    /// Before an audit: bring the app to the front (an inactive window draws dimmed titles and selections) and park the
    /// pointer outside the window, so no help tag covers the content being measured.
    func prepareForAudit() {
        app.activate()
        let window = mainWindow.exists ? mainWindow : app.windows.firstMatch
        if window.exists {
            // Just outside the window's top-left corner: over the desktop, where nothing shows a help tag.
            window.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(CGVector(dx: -12, dy: -12)).hover()
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    }
}
