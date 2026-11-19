// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import Observation
import ParsecEngine
import ParsecInsights
import SwiftUI

/// What the View menu's zoom items and ⌘F talk to: the focused map (MAP-015, MENU-022).
struct MapControl {
    var scope: MapScope
    var canZoomIn: Bool
    var canZoomOut: Bool
    var zoomIn: @MainActor () -> Void
    var zoomOut: @MainActor () -> Void
    var fit: @MainActor () -> Void
}

extension FocusedValues {
    @Entry var mapControl: MapControl?
}

/// Interaction state of one map instance: viewport, hover, search and animation. Views only wire it up.
@Observable @MainActor
final class MapViewModel {
    let scope: MapScope
    var viewSize = CGSize(width: 800, height: 600)
    /// The pointer location while it hovers the map (MAP-044).
    var hoverLocation: CGPoint?
    var hoverHit: MapHit?
    /// The hit whose card is shown (after the 0.2 s rest).
    var cardHit: MapHit?
    /// UI-PTR-011: the glyph whose selection card is pinned by a click or tap.
    var pinnedHit: MapHit?
    var legendShown = false
    /// MAP-096: the heatmap mode and its commodity.
    var heatmapChoice = MapHeatmapChoice.none
    var heatmapItem = TradeItemType.water
    var searchText = ""
    var filters: Set<SystemSearchFilter> = []
    /// INT-028: the "sells <item>" filter (nil: off).
    var sellsItem: TradeItemType?
    var highlightedSuggestion: Int?
    var searchMessage: String?
    var suggestionsShown = false
    /// Show on Map pulse (MAP-078).
    var pulseSystem: Int?
    var pulseStart = Date.distantPast
    @ObservationIgnored let cache = ProjectedMapCache()
    @ObservationIgnored var hoverTask: Task<Void, Never>?
    @ObservationIgnored var animationTask: Task<Void, Never>?
    @ObservationIgnored var pulseTask: Task<Void, Never>?
    @ObservationIgnored var lastClick: (time: Date, hit: MapHit)?
    @ObservationIgnored var dragStartViewport: MapViewport?
    @ObservationIgnored var pinchStartViewport: MapViewport?
    @ObservationIgnored var scrollMonitor: Any?

    init(scope: MapScope) {
        self.scope = scope
    }

    // MARK: Hover (MAP-044)

    static let hoverDelay: Duration = .milliseconds(200)

    func hover(at location: CGPoint?, hit: MapHit?) {
        hoverLocation = location
        guard hit != hoverHit else { return }
        hoverHit = hit
        cardHit = nil
        hoverTask?.cancel()
        guard let hit else { return }
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: Self.hoverDelay)
            guard !Task.isCancelled, let self, self.hoverHit == hit else { return }
            self.cardHit = hit
        }
    }

    /// Closes the hover card (exit, scroll, zoom, click, Esc, generation change).
    func closeCard() {
        closeHoverCard()
        pinnedHit = nil
    }

    /// Closes the hover preview only (a state change that keeps the ship where it is).
    func closeHoverCard() {
        hoverTask?.cancel()
        cardHit = nil
    }

    // MARK: Pulse (MAP-078)

    func pulse(_ system: Int) {
        pulseSystem = system
        pulseStart = .now
        pulseTask?.cancel()
        pulseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            self?.pulseSystem = nil
        }
    }

    // MARK: Search (MAP-071…073)

    func suggestions(_ snapshot: MapSnapshot, sells: [SellsMatch?]? = nil) -> [Int] {
        Array(SystemSearch.results(query: searchText, filters: filters, snapshot: snapshot, sells: sells)
            .prefix(SystemSearch.suggestionLimit))
    }

    func moveHighlight(by delta: Int, in list: [Int]) {
        guard !list.isEmpty else { return }
        let i = highlightedSuggestion.flatMap { list.firstIndex(of: $0) } ?? (delta > 0 ? -1 : list.count)
        highlightedSuggestion = list[min(max(i + delta, 0), list.count - 1)]
    }

    func clearSearch() {
        searchText = ""
        highlightedSuggestion = nil
        suggestionsShown = false
    }
}

/// Viewport storage and animation for a map instance (MAP-017, MAP-018).
extension MapViewModel {
    func viewport(session: GameSession, snapshot: MapSnapshot) -> MapViewport {
        let bounds = MapBounds(snapshot)
        if scope == .miniChart { return Self.miniChartViewport(snapshot: snapshot, viewSize: viewSize) }
        return (session.map.viewports[scope] ?? .fitGalaxy(bounds)).clamped(bounds)
    }

    /// MAP-074: ±20 parsecs on the shorter side, centred on the current system.
    static let miniChartRange: Double = 20

    static func miniChartViewport(snapshot: MapSnapshot, viewSize: CGSize) -> MapViewport {
        let fit = MapProjection.fitScale(viewSize: viewSize, content: MapBounds(snapshot).content)
        let zoom = min(viewSize.width, viewSize.height) / (2 * miniChartRange) / fit
        let c = snapshot.current
        return MapViewport(zoom: max(zoom, 1.0001), center: CGPoint(x: c.x, y: c.y))
    }

    /// Sets the viewport instantly (gestures follow the input directly).
    func setViewport(_ v: MapViewport, session: GameSession, snapshot: MapSnapshot) {
        guard scope != .miniChart else { return }
        animationTask?.cancel()
        session.map.viewports[scope] = v.clamped(MapBounds(snapshot))
    }

    /// Buttons, keys, search and Show on Map: a spring-like ease of at most 0.35 s; instant with Reduce Motion.
    func animateViewport(to target: MapViewport, session: GameSession, snapshot: MapSnapshot, reduceMotion: Bool) {
        guard scope != .miniChart else { return }
        closeCard()
        let bounds = MapBounds(snapshot)
        let end = target.clamped(bounds)
        let start = viewport(session: session, snapshot: snapshot)
        animationTask?.cancel()
        guard !reduceMotion, start != end else {
            session.map.viewports[scope] = end
            return
        }
        animationTask = Task { [weak self] in
            let duration = 0.3, frames = 18
            for f in 1...frames {
                try? await Task.sleep(for: .seconds(duration / Double(frames)))
                guard !Task.isCancelled, self != nil else { return }
                let t = Double(f) / Double(frames)
                let e = 1 - pow(1 - t, 3)
                let z = start.zoom + (end.zoom - start.zoom) * e
                let c = CGPoint(x: start.center.x + (end.center.x - start.center.x) * e,
                                y: start.center.y + (end.center.y - start.center.y) * e)
                session.map.viewports[self?.scope ?? .galaxy] = MapViewport(zoom: z, center: c)
            }
            session.map.viewports[self?.scope ?? .galaxy] = end
        }
    }
}
