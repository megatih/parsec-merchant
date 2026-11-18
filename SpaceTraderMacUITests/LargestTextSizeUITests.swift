// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

/// Flow 7 (A11Y-026): every catalog surface at the largest Text Size (`accessibility3`) in the 1100×720 minimum window.
/// macOS has no `.textClipped` audit type, so the test uses the spec's fallback: every static text outside a scrolling
/// container has a non-empty frame inside its window, and no label ends in "…" unless its value or title carries the full
/// text. Each surface attaches `qa-textsize-<surface>` (`.keepAlways`) for the screenshot review (A11Y-027).
final class LargestTextSizeUITests: ParsecUITestCase {
    static let arguments = ["-settings.textSize", "accessibility3", "-PMWindowSize", "min"]

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = true
    }

    @MainActor
    func testFlow7ShellSurfaces() throws {
        // covers: A11Y-026, A11Y-024, A11Y-025, UI-SHELL-102, MAP-087, LOG-039
        check(.shell)
    }

    @MainActor
    func testFlow7EncounterSurfaces() throws {
        // covers: A11Y-026, A11Y-025, UI-ENC-102
        check(.ambush)
    }

    @MainActor
    func testFlow7FixtureSurfaces() throws {
        // covers: A11Y-026, A11Y-025, UI-ENC-102
        check(.fixtures)
    }

    private func check(_ group: UISurfaceCatalog.Group) {
        var checkedMinimum = false
        walk(group, extra: Self.arguments) { visited in
            if !checkedMinimum, mainWindow.exists {
                checkedMinimum = true
                let size = mainWindow.frame.size
                XCTAssertLessThanOrEqual(size.width, 1101, "-PMWindowSize min opens the main window at 1100 wide (got \(size))")
            }
            let window = windowElement(containing: visited.root)
            parkPointer(settle: 1.2)  // A11Y-027: no help tag over the reviewed screenshot
            let shot = XCTAttachment(screenshot: window.screenshot())
            shot.name = "qa-textsize-\(visited.surface.name)"
            shot.lifetime = .keepAlways
            add(shot)
            // The whole window, so the check knows which texts sit in a scroll view (those may scroll out of view).
            if let snapshot = (try? window.snapshot()) ?? visited.snapshot {
                checkClipping(snapshot, window: window.frame, surface: visited.surface.name)
            }
        }
    }
}

/// The clipping check of flow 7 (A11Y-026), shared so the pseudo-localization run can reuse it.
extension ParsecUITestCase {
    /// The window that shows `root`.
    func windowElement(containing root: XCUIElement) -> XCUIElement {
        let f = root.frame
        let center = CGPoint(x: f.midX, y: f.midY)
        return app.windows.allElementsBoundByIndex.first { $0.exists && $0.frame.contains(center) } ?? mainWindow
    }

    static let scrollingTypes: Set<XCUIElement.ElementType> = [.scrollView, .table, .outline, .collectionView, .textView]

    /// The fallback clipping check of A11Y-026.
    func checkClipping(_ root: XCUIElementSnapshot, window: CGRect, surface: String,
                       file: StaticString = #filePath, line: UInt = #line) {
        var offenders: [String] = []
        let bounds = window.insetBy(dx: -1, dy: -1)
        func visit(_ e: XCUIElementSnapshot, inScroller: Bool) {
            let scrolling = inScroller || Self.scrollingTypes.contains(e.elementType)
            if e.elementType == .staticText {
                let text = (e.value as? String) ?? e.label
                if !text.isEmpty {
                    if e.frame.width <= 0 || e.frame.height <= 0 {
                        offenders.append("  '\(text)' id='\(e.identifier)' has an empty frame \(e.frame)")
                    } else if !scrolling, !bounds.contains(e.frame) {
                        offenders.append("  '\(text)' id='\(e.identifier)' frame \(e.frame) is outside the window \(window)")
                    }
                    if e.label.hasSuffix("…"), !((e.value as? String)?.count ?? 0 > e.label.count || e.title.count > e.label.count) {
                        offenders.append("  '\(e.label)' id='\(e.identifier)' is truncated without the full text")
                    }
                }
            }
            for child in e.children { visit(child, inScroller: scrolling) }
        }
        visit(root, inScroller: false)
        XCTAssertTrue(offenders.isEmpty, "A11Y-026 \(surface) at the largest Text Size clips text:\n" + offenders.joined(separator: "\n"),
                      file: file, line: line)
    }
}
