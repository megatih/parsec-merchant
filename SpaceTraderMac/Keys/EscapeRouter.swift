// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Observation
import ParsecEngine
import SwiftUI

/// UI-KEYS-017: what is open when Esc is pressed.
nonisolated struct EscapeContext: Equatable, Sendable {
    var dialogShown = false
    var sheet: SheetSurface?
    var fieldHasText = false
    var mapOverlayOpen = false
    var encounterCanStop = false
    var transitPlaying = false
    var feedOpen = false
    var compareSelection = false
    /// UI-NAV-003: a secondary page is shown while docked.
    var onSecondaryPage = false
}

/// UI-KEYS-017: what Esc does.
nonisolated enum EscapeTarget: Equatable, Sendable {
    case dialogCancel
    case sheet(SheetButton)
    case clearField
    case closeMapOverlay
    case stopEncounter
    case skipTransit
    case closeFeed
    case clearCompare
    /// UI-NAV-003: back to the Bridge, when nothing closer is open.
    case backToBridge
}

/// UI-KEYS-017: the Esc priority. Esc never closes a window or a game: with nothing to cancel it does nothing (on the Bridge).
nonisolated enum EscapeRouter {
    static func target(in c: EscapeContext) -> EscapeTarget? {
        if c.dialogShown { return .dialogCancel }
        if let sheet = c.sheet { return .sheet(SheetKeys.roles(sheet).escapeAction) }
        if c.fieldHasText { return .clearField }
        if c.mapOverlayOpen { return .closeMapOverlay }
        if c.encounterCanStop { return .stopEncounter }
        if c.transitPlaying { return .skipTransit }
        if c.feedOpen { return .closeFeed }
        if c.compareSelection { return .clearCompare }
        if c.onSecondaryPage { return .backToBridge }
        return nil
    }
}

/// The levels the registry holds.
enum EscapeLevel: Hashable, CaseIterable {
    case clearField, closeMapOverlay, closeFeed, clearCompare
}

/// The main window's Esc handlers that live in other views (UI-KEYS-018): the focused field's clear, the map's hover
/// card / legend / suggestions, the event feed and the Shipyard comparison. Views register while they are open; a view
/// only removes its own registration, so a section that appears before the old one disappears keeps its handler.
@Observable
final class EscapeRegistry {
    private struct Entry {
        var owner: UUID
        var action: () -> Void
    }

    private var entries: [EscapeLevel: Entry] = [:]

    func register(_ level: EscapeLevel, owner: UUID, action: (() -> Void)?) {
        if let action {
            entries[level] = Entry(owner: owner, action: action)
        } else if entries[level]?.owner == owner {
            entries[level] = nil
        }
    }

    func isActive(_ level: EscapeLevel) -> Bool { entries[level] != nil }

    func context(session: GameSession) -> EscapeContext {
        var c = EscapeContext()
        c.fieldHasText = isActive(.clearField)
        c.mapOverlayOpen = isActive(.closeMapOverlay)
        c.encounterCanStop = session.engine?.encounterPreview?.canStop ?? false
        c.transitPlaying = session.transitPlayback != nil
        c.feedOpen = isActive(.closeFeed)
        c.compareSelection = isActive(.clearCompare)
        c.onSecondaryPage = session.selectedSection != .bridge && session.state?.phase == .docked && !session.isInputLocked
        return c
    }

    /// Runs the router's target; returns whether Esc did something.
    @discardableResult
    func handle(session: GameSession) -> Bool {
        switch EscapeRouter.target(in: context(session: session)) {
        case .clearField?: entries[.clearField]?.action()
        case .closeMapOverlay?: entries[.closeMapOverlay]?.action()
        case .stopEncounter?: session.stopEncounter()
        case .skipTransit?: session.skipPlayback()
        case .closeFeed?: entries[.closeFeed]?.action()
        case .clearCompare?: entries[.clearCompare]?.action()
        case .backToBridge?: session.selectedSection = .bridge
        case .dialogCancel?, .sheet?, nil: return false
        }
        return true
    }
}

/// Registers an Esc handler with the main window's router while `active` (UI-KEYS-018).
struct EscapeHandler: ViewModifier {
    @Environment(EscapeRegistry.self) private var registry: EscapeRegistry?
    @State private var owner = UUID()
    let level: EscapeLevel
    let active: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear { update(active) }
            .onChange(of: active) { _, new in update(new) }
            .onDisappear { update(false) }
    }

    private func update(_ on: Bool) {
        registry?.register(level, owner: owner, action: on ? action : nil)
    }
}

extension View {
    /// Registers `action` as the main window's Esc at `level` while `active` (UI-KEYS-017/018).
    func escapeHandler(_ level: EscapeLevel, active: Bool, perform action: @escaping () -> Void) -> some View {
        modifier(EscapeHandler(level: level, active: active, action: action))
    }
}

/// UI-KEYS-018: the main window's single Esc handler, an invisible `.cancelAction` button at the window root (plus the
/// exit command), running `EscapeRouter` levels 3–8. Sheets are their own windows and keep their own `.cancelAction`.
struct WindowEscapeRouter: ViewModifier {
    @Environment(GameSession.self) private var session
    let registry: EscapeRegistry

    func body(content: Content) -> some View {
        content
            .environment(registry)
            .onExitCommand { registry.handle(session: session) }
            .background {
                Button {
                    registry.handle(session: session)
                } label: {
                    EmptyView()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.plain)
                .frame(width: 0, height: 0)
                .opacity(0)
                .focusable(false)
                .accessibilityHidden(true)
                .accessibilityIdentifier("window.escape")
            }
    }
}
