// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

/// A framework defect reproduced outside the app (A11Y-030). Every entry needs a Feedback number and a minimal sample.
struct AuditAllowlistEntry: Hashable {
    let auditType: XCUIAccessibilityAuditType.RawValue
    /// The element's identifier, or its role (`XCUIElement.ElementType` raw value as text) when it has none.
    let elementIdentifierOrRole: String
    let surface: String
    let reason: String
    let feedback: String
    let reproducedIn: String
    let date: String
}

/// A11Y-030: the known-issue policy of flow 6. Real failures are never suppressed.
enum KnownAuditIssues {
    /// Framework defects reproduced in a minimal sample, each with its FB number. Empty: none is needed today.
    static let allowlist: [AuditAllowlistEntry] = []

    /// System chrome roles: window buttons, title bar, toolbar overflow, sheet containers, scroll bars and menus.
    static let chromeTypes: Set<XCUIElement.ElementType> = [
        .scrollBar, .menuBar, .menuBarItem, .menu, .menuItem, .toolbar, .window, .sheet, .splitGroup, .splitter,
        // Parts AppKit draws inside a system control the app labels (a slider knob, stepper arrows).
        .valueIndicator, .incrementArrow, .decrementArrow,
        // The tooltip AppKit shows for a `.help` tag under the pointer.
        .helpTag,
    ]

    /// Why an issue is ignored, or nil when it is a real failure.
    struct Verdict: Equatable {
        let rule: String
    }

    /// What the policy needs to know about an issue (a value, so the rules are testable without UI automation).
    struct IssueFacts {
        var auditType: XCUIAccessibilityAuditType
        var hasElement: Bool
        var elementType: XCUIElement.ElementType
        var identifier: String
        var label: String
        var value: String
        var title: String
        var frame: CGRect
        var isEnabled: Bool
        /// The frame of the window the element is in (for full-height pane containers).
        var windowFrame: CGRect?
        /// The element is an AppKit-built container of a table: a cell or header-cell group (from the surface snapshot).
        var isTableContainer = false
        /// The element belongs to the audited surface and is on screen (nil: no scope known).
        var inScope: Bool?

        @MainActor
        init(_ issue: XCUIAccessibilityAuditIssue, windowFrame: CGRect?) {
            auditType = issue.auditType
            // One snapshot reads every attribute in a single query (each property access is a query of its own).
            let s = try? issue.element?.snapshot()
            hasElement = s != nil
            elementType = s?.elementType ?? .any
            identifier = s?.identifier ?? ""
            label = s?.label ?? ""
            value = (s?.value as? String) ?? ""
            title = s?.title ?? ""
            frame = s?.frame ?? .zero
            isEnabled = s?.isEnabled ?? true
            self.windowFrame = windowFrame
        }

        init(auditType: XCUIAccessibilityAuditType, hasElement: Bool = true, elementType: XCUIElement.ElementType,
             identifier: String = "", label: String = "", value: String = "", title: String = "", frame: CGRect = .zero,
             isEnabled: Bool = true, windowFrame: CGRect? = nil) {
            self.auditType = auditType
            self.hasElement = hasElement
            self.elementType = elementType
            self.identifier = identifier
            self.label = label
            self.value = value
            self.title = title
            self.frame = frame
            self.isEnabled = isEnabled
            self.windowFrame = windowFrame
        }

        var hasAppIdentifier: Bool { !identifier.isEmpty && !identifier.hasPrefix("_") }
        var hasText: Bool { !label.isEmpty || !value.isEmpty || !title.isEmpty }

        /// A pane container of the window: an unlabelled group as tall as the window (the split view's columns and the
        /// window's content view, which SwiftUI builds and the app cannot label).
        var isWindowPane: Bool {
            guard elementType == .group, let w = windowFrame, w.height > 0 else { return false }
            return frame.height >= w.height * 0.9 && abs(frame.minY - w.minY) < 2 && frame.maxY <= w.maxY + 1
        }
    }

    static func verdict(_ f: IssueFacts, surface: String) -> Verdict? {
        // Scope: `performAccessibilityAudit` covers the whole app. An element outside the surface being audited (behind
        // its sheet, in another window, or scrolled out of view) is audited on the surface that shows it.
        if f.inScope == false { return Verdict(rule: "outside the audited surface (behind its sheet, in another window or off screen)") }
        if let entry = allowlist.first(where: { matches($0, f, surface: surface) }) {
            return Verdict(rule: "allowlist \(entry.feedback): \(entry.reason)")
        }
        // Rule 1: system chrome without an app identifier or app text (never an element the app identifies or labels).
        if !f.hasAppIdentifier, !f.hasText {
            if !f.hasElement || f.frame == .zero { return Verdict(rule: "chrome: no element to resolve (system-built)") }
            if chromeTypes.contains(f.elementType) { return Verdict(rule: "chrome: \(f.elementType.rawValue) role") }
            if f.isWindowPane { return Verdict(rule: "chrome: window, sheet or split-view pane container") }
            if f.isTableContainer { return Verdict(rule: "chrome: table cell container") }
        }
        // Rule 2: contrast on a disabled control (WCAG 1.4.3 exempts inactive components).
        if f.auditType == .contrast, !f.isEnabled, controlTypes.contains(f.elementType) {
            return Verdict(rule: "contrast on a disabled control")
        }
        return nil
    }

    static let controlTypes: Set<XCUIElement.ElementType> = [
        .button, .checkBox, .radioButton, .popUpButton, .menuButton, .slider, .stepper, .textField, .segmentedControl,
        .switch, .toggle, .link, .comboBox,
    ]

    static func matches(_ entry: AuditAllowlistEntry, _ f: IssueFacts, surface: String) -> Bool {
        entry.auditType == f.auditType.rawValue && entry.surface == surface
            && (entry.elementIdentifierOrRole == f.identifier || entry.elementIdentifierOrRole == "\(f.elementType.rawValue)")
    }
}

/// The audit of one surface: runs `performAccessibilityAudit`, collects failures and ignored issues (A11Y-029/030).
@MainActor
final class AuditRecorder {
    private(set) var failures: [String] = []
    private(set) var ignored: [String: [String]] = [:]
    private(set) var usedAllowlist: Set<AuditAllowlistEntry> = []
    private(set) var lastCallFailures: [String] = []

    static func describe(_ f: KnownAuditIssues.IssueFacts, _ issue: XCUIAccessibilityAuditIssue) -> String {
        "type=\(auditName(issue.auditType)) role=\(f.elementType.rawValue) id='\(f.identifier)' label='\(f.label)' "
            + "value='\(f.value)' frame=\(f.frame) — \(issue.compactDescription): \(issue.detailedDescription)"
    }

    static func auditName(_ t: XCUIAccessibilityAuditType) -> String {
        switch t {
        case .contrast: "contrast"
        case .elementDetection: "elementDetection"
        case .hitRegion: "hitRegion"
        case .sufficientElementDescription: "sufficientElementDescription"
        case .action: "action"
        case .parentChild: "parentChild"
        default: "\(t.rawValue)"
        }
    }

    /// Audits the app for `types` on `surface`; a timeout is retried twice.
    /// The failures of this call are in `lastCallFailures` (and in `failures`).
    func audit(_ app: XCUIApplication, surface: String, types: XCUIAccessibilityAuditType, windowFrame: CGRect?,
               scope: AuditScope? = nil) {
        let before = failures.count
        defer { lastCallFailures = Array(failures[before...]) }
        var attempt = 0
        while true {
            attempt += 1
            do {
                try app.performAccessibilityAudit(for: types) { issue in
                    var facts = KnownAuditIssues.IssueFacts(issue, windowFrame: scope?.visible ?? windowFrame)
                    scope?.classify(&facts)
                    let text = Self.describe(facts, issue)
                    if let v = KnownAuditIssues.verdict(facts, surface: surface) {
                        self.ignored[surface, default: []].append("\(text) [ignored: \(v.rule)]")
                        if let e = KnownAuditIssues.allowlist.first(where: { KnownAuditIssues.matches($0, facts, surface: surface) }) {
                            self.usedAllowlist.insert(e)
                        }
                    } else {
                        self.failures.append("[\(surface)] \(text)")
                    }
                    return true
                }
                return
            } catch {
                if attempt >= 3 {
                    failures.append("[\(surface)] the audit did not complete: \(error.localizedDescription)")
                    return
                }
            }
        }
    }

    /// Drops the failures of the last call (before a retry of the same surface).
    func discardLastCall() {
        failures.removeLast(lastCallFailures.count)
        lastCallFailures = []
    }

    /// The A11Y-030 attachment of ignored issues.
    func ignoredAttachment(surface: String) -> XCTAttachment? {
        guard let lines = ignored[surface], !lines.isEmpty else { return nil }
        let a = XCTAttachment(string: lines.joined(separator: "\n"))
        a.name = "a11y-ignored-\(surface).txt"
        a.lifetime = .keepAlways
        return a
    }
}
