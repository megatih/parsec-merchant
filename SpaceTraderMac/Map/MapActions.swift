// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import ParsecInsights

nonisolated enum MapGesture: Sendable, Equatable, CaseIterable {
    case click, doubleClick, optionClick
}

nonisolated enum MapAction: Sendable, Equatable {
    case send(Command)
    /// Double-click: send, then move focus to the window's Warp control (never warps, MAP-051).
    case sendAndFocusWarp(Command)
    case none
}

/// Pointer → command mapping (MAP-042, MAP-048…053, MAP-079). Pure.
nonisolated enum MapActions {
    /// MAP-079: outside `.docked` or while a dialog is up, the map is read-only.
    static func isLocked(_ s: MapSnapshot, isModal: Bool) -> Bool { !s.isDocked || isModal }

    /// MAP-042: track, stop tracking, or nothing for the current system.
    static func trackCommand(for i: Int, snapshot s: MapSnapshot) -> Command? {
        if i == s.currentSystem { return nil }
        return i == s.trackedSystem ? .track(nil) : .track(i)
    }

    /// MAP-049/050: the click command for a hit.
    static func clickCommand(for hit: MapHit, snapshot s: MapSnapshot) -> Command {
        switch hit {
        case let .system(i):
            return .selectTarget(i)
        case let .wormhole(w):
            return s.wormholeSelectionScope == .anyWormhole || w == s.currentSystem ? .selectWormhole(w) : .selectTarget(w)
        }
    }

    /// MAP-048: exhaustive table over hit kind × gesture × locked.
    static func action(for hit: MapHit, gesture: MapGesture, snapshot s: MapSnapshot, isModal: Bool = false) -> MapAction {
        if isLocked(s, isModal: isModal) { return .none }
        switch gesture {
        case .click:
            return .send(clickCommand(for: hit, snapshot: s))
        case .doubleClick:
            return .sendAndFocusWarp(clickCommand(for: hit, snapshot: s))
        case .optionClick:
            return trackCommand(for: hit.systemIndex, snapshot: s).map(MapAction.send) ?? .none
        }
    }
}

/// One item of the map context menu (MAP-053).
struct MapContextItem: Equatable, Identifiable {
    nonisolated enum Kind: String, Equatable, Sendable {
        case setTarget, track, plotRoute, useWormhole, findPrices
    }

    var kind: Kind
    var title: String
    var command: Command?
    /// The destination for Plot Route.
    var destination: Int?
    var isEnabled: Bool
    var reason: String?

    var id: String { kind.rawValue }
}

enum MapContextMenu {
    /// MAP-053: built for the hit under the pointer; disabled items carry the reason. Nothing for empty space.
    static func items(for hit: MapHit?, snapshot s: MapSnapshot, isModal: Bool) -> [MapContextItem] {
        guard let hit else { return [] }
        let locked = MapActions.isLocked(s, isModal: isModal)
        let lockReason = isModal ? DisabledReason.modal.text : DisabledReason.notDocked.text
        let i = hit.systemIndex
        let name = s.systems[i].name
        var items: [MapContextItem] = []
        items.append(MapContextItem(kind: .setTarget, title: String(localized: "Set Target"), command: .selectTarget(i), destination: nil,
                                    isEnabled: !locked, reason: locked ? lockReason : nil))
        let track = MapActions.trackCommand(for: i, snapshot: s)
        let trackTitle = s.trackedSystem == i ? String(localized: "Stop Tracking “\(name)”") : String(localized: "Track “\(name)”")
        items.append(MapContextItem(kind: .track, title: trackTitle, command: track, destination: nil, isEnabled: !locked && track != nil,
                                    reason: locked ? lockReason : track == nil ? DisabledReason.targetIsCurrentSystem.text : nil))
        let canPlot = !locked && i != s.currentSystem
        items.append(MapContextItem(kind: .plotRoute, title: String(localized: "Plot Route to \(name)"), command: nil, destination: i,
                                    isEnabled: canPlot, reason: locked ? lockReason : canPlot ? nil : String(localized: "You are here.")))
        if case let .wormhole(w) = hit, let dest = s.systems[w].wormholeDestination {
            let cmd = MapActions.clickCommand(for: hit, snapshot: s)
            items.append(MapContextItem(kind: .useWormhole, title: String(localized: "Use Wormhole to \(s.systems[dest].name)"),
                                        command: cmd, destination: nil, isEnabled: !locked, reason: locked ? lockReason : nil))
        }
        // INT-037: Find Prices opens the System Intel sheet (disabled under the MAP-079 lock like every item).
        items.append(MapContextItem(kind: .findPrices, title: String(localized: "Find Prices"), command: nil, destination: i,
                                    isEnabled: !locked, reason: locked ? lockReason : nil))
        return items
    }
}

/// MAP-064: the next selection along a planned route. Never warps.
nonisolated enum RouteFollower {
    static func nextCommand(route: Route, state: GameState) -> Command? {
        guard state.phase == .docked else { return nil }
        let cur = state.commander.currentSystem
        guard cur != route.to, let hop = route.hops.first(where: { $0.from == cur }) else { return nil }
        return hop.viaWormhole ? .selectWormhole(cur) : .selectTarget(hop.to)
    }

    /// Whether `command` is already in effect (so the session does not resend it).
    static func isApplied(_ command: Command, state: GameState) -> Bool {
        switch command {
        case let .selectTarget(t): state.warpSystem == t && !state.targetWormhole
        case let .selectWormhole(w): state.targetWormhole && state.galaxy.wormholeDestination(from: w) == state.warpSystem
        default: false
        }
    }
}
