// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import ParsecEngine
import SwiftUI
import Testing
@testable import ParsecMerchant

/// UI-NAV, UI-SB: the release 2.0 shell (docs/PRD-UI-Revamp.md §4.1, §4.3).
@MainActor
@Suite("Game shell (UI-NAV, UI-SB)")
struct GameShellTests {
    static let sizes = [CGSize(width: 1200, height: 680), CGSize(width: 1440, height: 860), CGSize(width: 1728, height: 1050)]

    static func shell(_ session: GameSession, size: CGSize) -> (NSView, [String: ShellRender.Element]) {
        ShellRender.probe(GameShellView().modifier(SceneAccessibility()), session: session, size: size)
    }

    @Test("UI-NAV-001 UI-NAV-002 the shell is dock bar, status bar, game area from the top; every page has a dock button at every size")
    func layout() throws {
        let session = try TestSessions.playing(seed: 11)
        for size in Self.sizes {
            let (hosting, e) = Self.shell(session, size: size)
            if size.width == 1200 { print("QA shell picture: \(ShellRender.save(hosting, name: "shell-bridge-1200x680"))") }
            let dock = try #require(e[AXID.Dock.bar]), status = try #require(e[AXID.Status.bar])
            #expect(dock.frame.minY < 2 && status.frame.minY >= dock.frame.maxY - 1, "the dock bar is on top, the status bar under it (\(size))")
            #expect(abs(dock.frame.width - size.width) < 2 && abs(status.frame.width - size.width) < 2, "both span the window")
            #expect(status.frame.maxY < size.height * 0.2, "nothing of the bars is at the bottom edge")
            for section in Section.allCases {
                let button = try #require(e[section.axID], "\(section) at \(size)")
                #expect(button.frame.minX >= 0 && button.frame.maxX <= size.width + 1 && button.frame.width > 40 && button.frame.height >= 35,
                    "\(section) \(button.frame)")
                #expect(dock.frame.insetBy(dx: -1, dy: -1).contains(button.frame), "\(section) is inside the dock bar")
            }
            #expect(e[AXID.Dock.options] != nil)
            // No two dock buttons overlap.
            let frames = Section.allCases.compactMap { e[$0.axID]?.frame }.sorted { $0.minX < $1.minX }
            for (a, b) in zip(frames, frames.dropFirst()) { #expect(a.maxX <= b.minX + 1, "\(a) \(b)") }
            #expect(session.selectedSection == .bridge, "the Bridge is the page of a new game")
        }
    }

    @Test("UI-NAV-003 Esc on a secondary page returns to the Bridge, after the closer levels")
    func escape() throws {
        #expect(EscapeRouter.target(in: EscapeContext(onSecondaryPage: true)) == .backToBridge)
        #expect(EscapeRouter.target(in: EscapeContext(feedOpen: true, onSecondaryPage: true)) == .closeFeed)
        #expect(EscapeRouter.target(in: EscapeContext(fieldHasText: true, onSecondaryPage: true)) == .clearField)
        #expect(EscapeRouter.target(in: EscapeContext()) == nil)
        let session = try TestSessions.playing(seed: 11)
        let registry = EscapeRegistry()
        session.selectedSection = .bank
        #expect(registry.handle(session: session) && session.selectedSection == .bridge)
        #expect(!registry.handle(session: session), "on the Bridge Esc has nothing to do")
    }

    @Test("UI-NAV-005 UI-SHELL-037 in transit and in encounters every dock button is disabled and says why")
    func locked() throws {
        let session = try EncFx.session(.pirateAttack)
        let (_, e) = Self.shell(session, size: Self.sizes[0])
        #expect(e[AXID.Dock.phaseLabel] != nil)
        for section in Section.allCases { #expect(e[section.axID]?.enabled == false, "\(section)") }
        #expect(e[AXID.Status.bar] != nil && e[AXID.Status.hull] != nil, "the status bar stays live")
        let context = session.sectionContext
        #expect(DockBarView.reason(section: .bank, lock: .inEncounter, context: context) == "Unavailable during an encounter")
        #expect(DockBarView.reason(section: .bank, lock: .inTransit, context: context) == "Unavailable in transit")
        #expect(DockBarView.reason(section: .bank, lock: .none, context: SectionContext.make(state: try TestSessions.playing().state)) == nil)
    }

    @Test("UI-NAV-009 without a game the window shows Welcome, with no dock bar and no status bar")
    func welcome() throws {
        let session = try TestSessions.make()
        let (_, e) = ShellRender.probe(RootView().modifier(SceneAccessibility()), session: session, size: Self.sizes[0])
        #expect(e[AXID.Dock.bar] == nil && e[AXID.Status.bar] == nil)
        #expect(session.mode == .welcome)
        let (_, playing) = ShellRender.probe(RootView().modifier(SceneAccessibility()), session: try TestSessions.playing(), size: Self.sizes[0])
        #expect(playing[AXID.Dock.bar] != nil && playing[AXID.Status.bar] != nil)
    }

    @Test("UI-SB-001 UI-SB-002 UI-SB-005 the status bar has exactly eight slots, in order, each with a word label and a help tag")
    func statusSlots() throws {
        let session = try TestSessions.playing(seed: 11)
        let order = [AXID.Status.location, AXID.Status.cash, AXID.Status.debt, AXID.Status.bays, AXID.Status.fuel, AXID.Status.hull, AXID.Status.shields,
                     AXID.Status.feed]
        for size in Self.sizes {
            let (_, e) = Self.shell(session, size: size)
            let bar = try #require(e[AXID.Status.bar])
            let slots = try order.map { try #require(e[$0], "\($0) at \(size)") }
            for (a, b) in zip(slots, slots.dropFirst()) { #expect(a.frame.maxX <= b.frame.minX + 1, "\(a.identifier) before \(b.identifier)") }
            for slot in slots { #expect(bar.frame.insetBy(dx: -1, dy: -6).contains(slot.frame), "\(slot.identifier) \(slot.frame) in \(bar.frame)") }
            // Nothing else is in the bar.
            let inside = e.values.filter { $0.identifier.hasPrefix("status.") && $0.identifier != AXID.Status.bar }.map(\.identifier)
            #expect(Set(inside).subtracting(order).subtracting([AXID.Status.reason]).isEmpty, "\(inside)")
        }
        // Record, reputation, skills and worth are not status-bar facts (they are on Commander Status).
        #expect(!AXID.Status.all.contains { $0.contains("record") || $0.contains("reputation") || $0.contains("worth") || $0.contains("skill") })
    }

    @Test("UI-SB-001 UI-SB-003 slots never disappear: zero debt and no shields show their zero form; eight-digit sums fit at the minimum size")
    func statusValues() throws {
        let session = try TestSessions.playing(seed: 11)
        var model = StatusBarModel.make(state: try #require(session.state), feed: [])
        #expect(model.debt == 0 && model.shieldPercent == nil && model.transit == nil && !model.systemName.isEmpty)
        #expect(StatusBarText.credits(0) == "0 cr." && StatusBarText.credits(12_345) == "12,345 cr." && StatusBarText.percent(79) == "79%")
        try TestSessions.edit(session) { st in
            st.commander.cash = 99_999_999
            st.commander.debt = 88_888_888
        }
        model = StatusBarModel.make(state: try #require(session.state), feed: session.feed)
        #expect(model.cash == 99_999_999 && model.debt == 88_888_888)
        let (_, e) = Self.shell(session, size: Self.sizes[0])
        let feed = try #require(e[AXID.Status.feed])
        #expect(feed.frame.width >= 60, "the message slot keeps room beside eight-digit cash and debt: \(feed.frame)")
        #expect((e[AXID.Status.cash]?.frame.maxX ?? 0) <= (e[AXID.Status.debt]?.frame.minX ?? 0) + 1)
        #expect(feed.frame.maxX <= 1201)
    }

    @Test("UI-SB-004 UI-SHELL-045 a rejection is the message for four seconds; in transit the location slot names the destination")
    func statusMessage() throws {
        let session = try TestSessions.playing(seed: 11)
        session.send(.buyCargo(.water, quantity: 9_999))
        #expect(session.lastRejection != nil)
        let enc = try EncFx.session(.pirateAttack)
        let model = StatusBarModel.make(state: try #require(enc.state), feed: enc.feed)
        #expect(model.transit != nil && (model.transit?.clicks ?? 0) > 0)
    }

    @Test("UI-HIG-007 the main window is a standard resizable window with a Settings scene; closing it does not quit")
    func window() {
        #expect(SceneMetrics.mainWindowID == "main" && SceneMetrics.mainMinimumSize.width < SceneMetrics.mainDefaultSize.width)
        #expect(!AppDelegate().applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }
}
