// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

/// A11Y-040/041: the pseudo-localization run. Three launches walk the section, sheet and window entries of the surface
/// catalog (the shell group) under the Foundation pseudolanguage defaults Xcode's scheme options use. Menu items and
/// tab segments are found through the pseudo forms of their English titles (`ParsecUITestCase.titlePredicate`), every
/// other step by identifier. Each surface attaches `qa-pseudo-<mode>-<surface>` (`.keepAlways`).
final class PseudoLocalizationUITests: ParsecUITestCase {
    enum Mode: String {
        case double, bounded, rtl

        var arguments: [String] {
            switch self {
            case .double: ["-NSDoubleLocalizedStrings", "YES"]
            case .bounded: ["-NSAccentuateLocalizedStrings", "YES", "-NSSurroundLocalizedStrings", "YES"]
            // Xcode's Right-to-Left Pseudolanguage: right-to-left writing direction and a mirrored layout.
            case .rtl: ["-NSForceRightToLeftWritingDirection", "YES", "-AppleTextDirection", "YES"]
            }
        }
    }

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = true
    }

    @MainActor
    func testPseudoDoubleLength() throws {
        // covers: A11Y-040, LLM-030 (no clipping with doubled strings: the flow 7 check without the Text Size argument)
        run(.double)
    }

    @MainActor
    func testPseudoAccentedBounded() throws {
        // covers: A11Y-040, A11Y-041, LLM-030
        run(.bounded)
    }

    @MainActor
    func testPseudoRightToLeft() throws {
        // covers: A11Y-040
        run(.rtl)
    }

    private func run(_ mode: Mode) {
        pseudoLocalized = mode != .rtl
        var offenders: [String] = []
        walk(.shell, extra: mode.arguments) { visited in
            let window = windowElement(containing: visited.root)
            parkPointer(settle: 1.2)  // A11Y-042: no help tag over the reviewed screenshot
            let shot = XCTAttachment(screenshot: window.screenshot())
            shot.name = "qa-pseudo-\(mode.rawValue)-\(visited.surface.name)"
            shot.lifetime = .keepAlways
            add(shot)
            switch mode {
            case .double:
                if let snapshot = (try? window.snapshot()) ?? visited.snapshot {
                    checkClipping(snapshot, window: window.frame, surface: "\(visited.surface.name) (double length)")
                }
            case .bounded:
                checkKnownLabels(at: visited.surface.name)
                if let snapshot = visited.snapshot ?? (try? visited.root.snapshot()) {
                    offenders += Self.unlocalized(in: snapshot).map { "  \(visited.surface.name): \($0)" }
                }
            case .rtl:
                break
            }
        }
        if mode == .bounded {
            XCTAssertTrue(offenders.isEmpty, "A11Y-041 unlocalized (unbounded) labels:\n" + offenders.joined(separator: "\n"))
        }
    }

    // MARK: A11Y-041

    /// The bounded pseudolanguage wraps every localized string in "[# … #]".
    static func isMarked(_ text: String) -> Bool { text.contains("[#") || text.contains("#]") }

    /// Data: digits, punctuation and units only, once the fixture game's proper names are removed.
    static func isData(_ text: String) -> Bool {
        var rest = text
        for name in UITestFixtures.dataNames.sorted(by: { $0.count > $1.count }) {
            rest = rest.replacingOccurrences(of: name, with: " ")
        }
        // A galaxy code (UI-SHELL-103) is data whatever seed the walk uses: ruleset+difficulty, then two base-36 parts.
        rest = rest.replacingOccurrences(of: #"\b[A-Z]\d+-[A-Z0-9]+-[A-Z0-9]+\b"#, with: " ", options: .regularExpression)
        rest = rest.replacingOccurrences(of: #"\b(cr|pc|ly|d|x|M\d+|B|S)\b\.?"#, with: " ", options: .regularExpression)
        return !rest.contains { $0.isLetter }
    }

    /// Containers localized as whole files rather than strings: the Help pages are bundled `Help/<topic>.md` per
    /// language (A11Y-033 step 5), so the pseudolanguages do not reach them.
    static let fileLocalized: Set<String> = ["help.content"]

    /// Every static text and button label below `root` that is neither bounded nor data, with its identifier.
    static func unlocalized(in root: XCUIElementSnapshot) -> [String] {
        var out: [String] = []
        func visit(_ e: XCUIElementSnapshot) {
            if fileLocalized.contains(e.identifier) { return }
            if e.elementType == .staticText || e.elementType == .button {
                for text in [e.label, (e.value as? String) ?? "", e.title] where !text.isEmpty {
                    if !isMarked(text), !isData(text) {
                        out.append("id='\(e.identifier)' \(e.elementType == .button ? "button" : "text") '\(text)'")
                        break
                    }
                }
            }
            e.children.forEach(visit)
        }
        visit(root)
        return out
    }

    /// Known localized labels carry the bounds, which proves the pseudolanguage reaches string-catalog strings.
    private func checkKnownLabels(at surface: String) {
        func expectMarked(_ id: String) {
            let e = element(id)
            guard e.waitForExistence(timeout: 3) else { return XCTFail("A11Y-041 \(id) exists on \(surface)") }
            // The element's own text, else the first text below it (a sidebar row is a group around its label).
            var text = ""
            func find(_ s: XCUIElementSnapshot) {
                guard text.isEmpty else { return }
                text = [s.label, s.title, (s.value as? String) ?? ""].first { !$0.isEmpty } ?? ""
                s.children.forEach(find)
            }
            if let snapshot = try? e.snapshot() { find(snapshot) }
            XCTAssertTrue(Self.isMarked(text), "A11Y-041 \(id) on \(surface) is bounded (got '\(text)')")
        }
        switch surface {
        case "welcome":
            expectMarked(AXID.Welcome.quickStart)
        case "section-bridge":
            expectMarked(AXID.Bridge.targetWarp)
            for s in UISurfaceCatalog.sections { expectMarked("dock.\(s.name)") }
        case let name where name.hasPrefix("settings-"):
            let tab = String(name.dropFirst("settings-".count))
            let byID = element(AXID.A11y.settingsTab(tab))
            if byID.exists {
                expectMarked(AXID.A11y.settingsTab(tab))
            } else {
                // SwiftUI may not expose the Tab identifier: the toolbar shows every tab title, all bounded.
                let titles = app.toolbars.buttons.allElementsBoundByIndex.map(\.title).filter { !$0.isEmpty }
                XCTAssertTrue(!titles.isEmpty && titles.allSatisfy(Self.isMarked), "A11Y-041 Settings tab titles are bounded: \(titles)")
            }
        default:
            break
        }
    }
}
