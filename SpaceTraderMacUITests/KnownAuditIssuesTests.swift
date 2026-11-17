// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

/// A11Y-030: the known-issue policy as a pure function (no app launch), plus the A11Y-003 label rules.
final class KnownAuditIssuesTests: XCTestCase {
    typealias Facts = KnownAuditIssues.IssueFacts
    let window = CGRect(x: 100, y: 100, width: 1320, height: 860)

    @MainActor
    func testOnlySystemChromeAndDisabledControlContrastAreIgnored() {
        // covers: A11Y-030
        // Rule 1: chrome without an identifier or text.
        XCTAssertNotNil(KnownAuditIssues.verdict(Facts(auditType: .parentChild, hasElement: false, elementType: .any), surface: "s"))
        XCTAssertNotNil(KnownAuditIssues.verdict(Facts(auditType: .sufficientElementDescription, elementType: .scrollBar,
                                                       frame: CGRect(x: 1, y: 1, width: 10, height: 100)), surface: "s"))
        XCTAssertNotNil(KnownAuditIssues.verdict(Facts(auditType: .sufficientElementDescription, elementType: .group,
                                                       frame: CGRect(x: 100, y: 100, width: 200, height: 860), windowFrame: window),
                                                 surface: "s"), "a full-height split-view pane")
        // Never for an element the app identifies or labels.
        XCTAssertNil(KnownAuditIssues.verdict(Facts(auditType: .sufficientElementDescription, elementType: .group, identifier: "bridge.root",
                                                    frame: CGRect(x: 100, y: 100, width: 200, height: 860), windowFrame: window),
                                              surface: "s"))
        XCTAssertNil(KnownAuditIssues.verdict(Facts(auditType: .contrast, hasElement: false, elementType: .staticText, value: "Cash"),
                                              surface: "s"))
        XCTAssertNil(KnownAuditIssues.verdict(Facts(auditType: .sufficientElementDescription, elementType: .group,
                                                    frame: CGRect(x: 300, y: 300, width: 200, height: 80), windowFrame: window),
                                              surface: "s"), "an unlabelled app card is a real failure")
        // Rule 2: contrast on a disabled control only.
        XCTAssertNotNil(KnownAuditIssues.verdict(Facts(auditType: .contrast, elementType: .button, identifier: "market.row.water.buy",
                                                       label: "Buy", frame: CGRect(x: 1, y: 1, width: 20, height: 20), isEnabled: false),
                                                 surface: "s"))
        XCTAssertNil(KnownAuditIssues.verdict(Facts(auditType: .contrast, elementType: .button, identifier: "market.row.water.buy",
                                                    label: "Buy", frame: CGRect(x: 1, y: 1, width: 20, height: 20), isEnabled: true),
                                              surface: "s"))
        XCTAssertNil(KnownAuditIssues.verdict(Facts(auditType: .contrast, elementType: .staticText, value: "1,000 cr.",
                                                    frame: CGRect(x: 1, y: 1, width: 20, height: 20), isEnabled: false), surface: "s"))
        // Rule 3: every allowlist entry carries a Feedback number and a reproduction.
        for e in KnownAuditIssues.allowlist {
            XCTAssertTrue(e.feedback.hasPrefix("FB") && !e.reproducedIn.isEmpty && !e.reason.isEmpty, "allowlist entry \(e)")
        }
    }

    @MainActor
    func testLabelRules() {
        // covers: A11Y-003
        XCTAssertNil(AccessibilityAuditUITests.labelProblem(label: "Buy", identifier: "market.row.water.buy"))
        XCTAssertNotNil(AccessibilityAuditUITests.labelProblem(label: "", identifier: "x.y"))
        XCTAssertNotNil(AccessibilityAuditUITests.labelProblem(label: "x.y", identifier: "x.y"))
        XCTAssertNotNil(AccessibilityAuditUITests.labelProblem(label: "chevron.right", identifier: "bridge.target.next"))
        XCTAssertNotNil(AccessibilityAuditUITests.labelProblem(label: "Warp ⌘J", identifier: "toolbar.warp"))
        XCTAssertNotNil(AccessibilityAuditUITests.labelProblem(label: "Attack A", identifier: "encounter.action.attack"))
        XCTAssertNil(AccessibilityAuditUITests.labelProblem(label: "Attack", identifier: "encounter.action.attack"))
    }
}
