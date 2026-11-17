// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import ParsecArt
import ParsecEngine
import ParsecInsights
import SwiftUI

/// The one galaxy map component (MAP Conventions): the Galaxy section, the Galaxy Chart window and the Bridge mini chart.
struct GalaxyMapView: View {
    @Environment(GameSession.self) private var session
    @Environment(\.accessibilityPreferences) private var a11yPrefs
    private var reduceMotion: Bool { a11yPrefs.reduceMotion }
    /// A11Y-016: viewport changes are instant when MotionPolicy gives the map viewport no animation.
    private var viewportJumps: Bool { MotionPolicy.spec(for: .mapViewport, prefs: a11yPrefs) == .none }
    private var differentiateWithoutColor: Bool { a11yPrefs.differentiateWithoutColor }
    private var reduceTransparency: Bool { a11yPrefs.reduceTransparency }
    @Environment(\.appearsActive) private var appearsActive
    @State private var ui: MapViewModel
    @FocusState private var canvasFocused: Bool
    @FocusState private var searchFocused: Bool
    @FocusState private var warpFocused: Bool
    @AccessibilityFocusState private var axFocus: Int?
    @Namespace private var rotorNamespace

    init(scope: MapScope) {
        _ui = State(initialValue: MapViewModel(scope: scope))
    }

    private var scope: MapScope { ui.scope }

    /// MAP-095: the art options (galaxy-seeded starfield, nebula and mini-planets; vortices swirl in the overlay unless Reduce
    /// Motion is on or the window is inactive).
    private var mapArt: MapArt? {
        guard let seed = session.state?.seed else { return nil }
        return MapArt(galaxySeed: seed, reduceTransparency: reduceTransparency, vorticesInOverlay: !reduceMotion && appearsActive)
    }
    private var ids: AXID.Map { AXID.Map(scope) }

    var body: some View {
        if let snapshot = session.mapSnapshot {
            content(snapshot)
                .onChange(of: snapshot.generation) { ui.closeCard() }
        }
    }

    // MARK: Layout

    private func content(_ snapshot: MapSnapshot) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            let viewport = ui.viewport(session: session, snapshot: snapshot)
            let projected = ui.cache.map(snapshot: snapshot, viewport: viewport, viewSize: size, labelAll: scope == .miniChart)
            ZStack(alignment: .topLeading) {
                mapCanvas(snapshot, projected: projected)
                overlayCanvas(snapshot, projected: projected)
                if let hit = ui.cardHit {
                    hoverCard(hit, snapshot: snapshot, projected: projected, size: size)
                }
                if scope.hasHUD {
                    hud(snapshot, size: size)
                }
            }
            .onAppear { ui.viewSize = size }
            .onChange(of: size) { _, new in ui.viewSize = new }
        }
        .clipped()
        .onAppear { installScrollMonitor() }
        .onDisappear { removeScrollMonitor() }
        .onChange(of: session.map.focusRequest) { _, request in handleFocusRequest(request, snapshot: snapshot) }
        .sheet(item: $ui.intelSheet) { request in
            SystemIntelSheet(system: request.id) { ui.intelSheet = nil }
                .environment(session)
        }
        .focusedSceneValue(\.contextSearch, scope.hasHUD ? ContextSearchAction { searchFocused = true } : nil)
        // UI-KEYS-027: the Galaxy section opens with the canvas focused, so the arrows pan at once.
        .task(id: scope) {
            // After the canvas is laid out inside the GeometryReader (an assignment in onAppear comes too early).
            guard scope.hasHUD else { return }
            try? await Task.sleep(for: .milliseconds(150))
            // The sidebar's outline view keeps AppKit's first responder after ⌘7; hand it to the SwiftUI host so the
            // focused canvas receives the keys.
            if let window = NSApp.keyWindow, window.firstResponder is NSTableView, let host = window.contentView {
                window.makeFirstResponder(host)
            }
            canvasFocused = true
        }
        // UI-KEYS-017 levels 3 and 4, run by the main window's Esc router.
        .escapeHandler(.clearField, active: searchFocused && !ui.searchText.isEmpty) { ui.searchText = "" }
        .escapeHandler(.closeMapOverlay, active: ui.cardHit != nil || ui.legendShown || suggestionsVisible(snapshot)) { dismissOverlays() }
    }

    // MARK: Canvas

    private func mapCanvas(_ snapshot: MapSnapshot, projected: ProjectedMap) -> some View {
        var options = MapRenderOptions(style: MapStyle(strokeScale: ContrastStyle.make(prefs: a11yPrefs).mapStrokeScale,
                                                                 differentiateWithoutColor: differentiateWithoutColor),
                                       dimmed: SystemSearch.dimmed(filters: ui.filters, snapshot: snapshot, sells: session.sellsMatches(ui.sellsItem)),
                                       miniChart: scope == .miniChart)
        options.heatmap = scope.hasHUD ? session.heatmap(ui.heatmapChoice.mode(item: ui.heatmapItem)) : nil
        options.art = mapArt
        return Canvas { ctx, _ in
            GalaxyMapRenderer.draw(in: &ctx, snapshot: snapshot, projected: projected, layers: MapLayer.m10, options: options)
        }
        // `.edit` interactions: the canvas takes focus by click or programmatically even without Full Keyboard Access.
        .focusable(scope.hasHUD, interactions: .edit)
        .focused($canvasFocused)
        .focusEffectDisabled(false)
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case let .active(location):
                ui.hover(at: location, hit: hit(at: location, snapshot: snapshot, projected: projected))
            case .ended:
                ui.hover(at: nil, hit: nil)
            }
        }
        .gesture(dragGesture(snapshot, projected: projected))
        .simultaneousGesture(pinchGesture(snapshot))
        .contextMenu { contextMenuItems(snapshot) }
        // UI-KEYS-001 / UI-KEYS-013: keys are looked up in `MapKeys` (arrows pan, ⌘= zooms in, Esc dismisses).
        .onKeyPress(phases: .down) { press in
            guard let action = MapKeys.action(for: MenuShortcut(press: press.key, characters: press.characters, modifiers: press.modifiers))
            else { return .ignored }
            return handleKey(action, snapshot: snapshot)
        }
        .focusedValue(\.mapControl, scope.hasHUD ? mapControl(snapshot) : nil)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Galaxy chart"))
        .accessibilityIdentifier(ids.map)
        .accessibilityChildren { accessibilityChildren(snapshot, projected: projected) }
        .modifier(MapRotors(snapshot: snapshot, namespace: rotorNamespace))
        .onChange(of: axFocus) { _, focus in
            guard let focus, scope.hasHUD else { return }
            let c = projected.centers[focus]
            if !CGRect(origin: .zero, size: ui.viewSize).contains(c) {
                ui.animateViewport(to: ui.viewport(session: session, snapshot: snapshot).centered(on: focus, snapshot: snapshot),
                                   session: session, snapshot: snapshot, reduceMotion: viewportJumps)
            }
        }
    }

    /// The light overlay canvas: hover highlight and Show on Map pulse (MAP-089). Never takes hit testing.
    private func overlayCanvas(_ snapshot: MapSnapshot, projected: ProjectedMap) -> some View {
        let swirl = mapArt?.vorticesInOverlay == true && !snapshot.wormholes.isEmpty
        return TimelineView(.animation(minimumInterval: 1.0 / 30, paused: (ui.pulseSystem == nil && !swirl) || reduceMotion)) { timeline in
            Canvas { ctx, _ in
                if swirl {
                    // MAP-095 / ART-030: the wormhole vortices turn here so the main canvas stays static.
                    let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: WormholeVortex.period * 100)
                    for w in snapshot.wormholes where projected.visible.contains(w) {
                        GalaxyMapRenderer.drawVortex(&ctx, center: MapGeometry.wormholeGlyphCenter(w, snapshot: snapshot, projection: projected.projection,
                                                                                                    metrics: projected.metrics),
                                                     radius: projected.metrics.wormholeRadius, phase: phase)
                    }
                }
                if let hit = ui.hoverHit {
                    let (c, r) = glyph(hit, snapshot: snapshot, projected: projected)
                    let name: String? = if case let .system(i) = hit, !projected.labels.contains(where: { $0.system == i }) {
                        snapshot.systems[i].name
                    } else { nil }
                    GalaxyMapRenderer.drawHighlight(&ctx, center: c, radius: r, pulse: 0, name: name)
                }
                if let p = ui.pulseSystem, snapshot.systems.indices.contains(p) {
                    let t = timeline.date.timeIntervalSince(ui.pulseStart)
                    let phase = reduceMotion ? 0 : (sin(t * 2 * .pi * 1.5) + 1) / 2
                    GalaxyMapRenderer.drawHighlight(&ctx, center: projected.centers[p],
                                                    radius: projected.metrics.radius(snapshot.systems[p].size) + 4, pulse: phase, name: nil)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func glyph(_ hit: MapHit, snapshot: MapSnapshot, projected: ProjectedMap) -> (CGPoint, Double) {
        switch hit {
        case let .system(i):
            (projected.centers[i], projected.metrics.radius(snapshot.systems[i].size))
        case let .wormhole(w):
            (MapGeometry.wormholeGlyphCenter(w, snapshot: snapshot, projection: projected.projection, metrics: projected.metrics),
             projected.metrics.wormholeRadius)
        }
    }

    private func hit(at p: CGPoint, snapshot: MapSnapshot, projected: ProjectedMap) -> MapHit? {
        MapHitTester.hit(at: p, snapshot: snapshot, projection: projected.projection, metrics: projected.metrics, viewSize: ui.viewSize)
    }

    // MARK: Pointer (MAP-013, MAP-014, MAP-048…053)

    private static let clickSlop: Double = 3

    private func dragGesture(_ snapshot: MapSnapshot, projected: ProjectedMap) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let t = value.translation
                guard scope.hasHUD, (t.width * t.width + t.height * t.height).squareRoot() >= Self.clickSlop else { return }
                let start = ui.dragStartViewport ?? ui.viewport(session: session, snapshot: snapshot)
                if ui.dragStartViewport == nil {
                    ui.dragStartViewport = start
                    ui.closeCard()
                }
                ui.setViewport(start.panned(byViewDelta: t, viewSize: ui.viewSize, bounds: MapBounds(snapshot)), session: session,
                               snapshot: snapshot)
            }
            .onEnded { value in
                let wasDrag = ui.dragStartViewport != nil
                ui.dragStartViewport = nil
                let t = value.translation
                guard !wasDrag, (t.width * t.width + t.height * t.height).squareRoot() < Self.clickSlop else { return }
                click(at: value.location, snapshot: snapshot, projected: projected)
            }
    }

    private func pinchGesture(_ snapshot: MapSnapshot) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard scope.hasHUD else { return }
                let start = ui.pinchStartViewport ?? ui.viewport(session: session, snapshot: snapshot)
                if ui.pinchStartViewport == nil {
                    ui.pinchStartViewport = start
                    ui.closeCard()
                }
                let anchor = CGPoint(x: value.startAnchor.x * ui.viewSize.width, y: value.startAnchor.y * ui.viewSize.height)
                ui.setViewport(start.zoomed(by: value.magnification, anchor: anchor, viewSize: ui.viewSize, bounds: MapBounds(snapshot)),
                               session: session, snapshot: snapshot)
            }
            .onEnded { _ in ui.pinchStartViewport = nil }
    }

    private func click(at location: CGPoint, snapshot: MapSnapshot, projected: ProjectedMap) {
        ui.closeCard()
        ui.suggestionsShown = false
        if scope.hasHUD { canvasFocused = true }
        guard let hit = hit(at: location, snapshot: snapshot, projected: projected) else {
            ui.lastClick = nil
            return
        }
        let now = Date.now
        let gesture: MapGesture
        if NSEvent.modifierFlags.contains(.option) {
            gesture = .optionClick
        } else if let last = ui.lastClick, last.hit == hit, now.timeIntervalSince(last.time) <= NSEvent.doubleClickInterval {
            gesture = .doubleClick
        } else {
            gesture = .click
        }
        ui.lastClick = gesture == .click ? (now, hit) : nil
        perform(MapActions.action(for: hit, gesture: gesture, snapshot: snapshot, isModal: session.isInputLocked))
    }

    private func perform(_ action: MapAction) {
        switch action {
        case let .send(command):
            sendFromMap(command)
        case let .sendAndFocusWarp(command):
            sendFromMap(command)
            if WarpButtonModel.make(state: session.state, isModal: session.isInputLocked).isEnabled { warpFocused = true }
        case .none:
            break
        }
    }

    /// Sends a map command and announces a target change (MAP-085).
    private func sendFromMap(_ command: Command) {
        let before = session.state?.warpSystem
        session.send(command)
        guard session.lastRejection == nil, let s = session.mapSnapshot, s.warpSystem != before || isTargetCommand(command),
              let text = MapAccessibility.targetAnnouncement(s) else { return }
        AccessibilityNotification.Announcement(text).post()
    }

    private func isTargetCommand(_ c: Command) -> Bool {
        switch c {
        case .selectTarget, .selectWormhole: true
        default: false
        }
    }

    // MARK: Context menu (MAP-053)

    @ViewBuilder
    private func contextMenuItems(_ snapshot: MapSnapshot) -> some View {
        ForEach(MapContextMenu.items(for: ui.hoverHit, snapshot: snapshot, isModal: session.isInputLocked)) { item in
            Button {
                if let command = item.command { sendFromMap(command) }
                if item.kind == .plotRoute, let d = item.destination { session.planRoute(to: d) }
                if item.kind == .findPrices, let d = item.destination { ui.intelSheet = SystemIntelRequest(id: d) }
            } label: {
                Text(verbatim: item.title)
            }
            .disabled(!item.isEnabled)
            .help(item.reason.map { Text(verbatim: $0) } ?? Text(verbatim: item.title))
            .accessibilityIdentifier(ids.context(item.kind))
        }
    }

    // MARK: Keyboard (MAP-015)

    private func dismissOverlays() {
        ui.closeCard()
        ui.suggestionsShown = false
        ui.legendShown = false
    }

    /// Whether the search's suggestion list is on screen (as `MapSearchView` shows it).
    private func suggestionsVisible(_ snapshot: MapSnapshot) -> Bool {
        scope.hasHUD && ui.suggestionsShown && !ui.suggestions(snapshot, sells: session.sellsMatches(ui.sellsItem)).isEmpty
    }

    private func handleKey(_ action: MapKeyAction, snapshot: MapSnapshot) -> KeyPress.Result {
        let (dx, dy): (Int, Int)
        switch action {
        case .dismiss:
            dismissOverlays()
            return .handled
        case .zoomIn:
            guard scope.hasHUD else { return .ignored }
            zoom(MapViewport.zoomStep, snapshot: snapshot)
            return .handled
        case .zoomOut:
            guard scope.hasHUD else { return .ignored }
            zoom(1 / MapViewport.zoomStep, snapshot: snapshot)
            return .handled
        case .fit:
            guard scope.hasHUD else { return .ignored }
            fitGalaxy(snapshot)
            return .handled
        case let .pan(x, y):
            guard scope.hasHUD else { return .ignored }
            (dx, dy) = (x, y)
        }
        let v = ui.viewport(session: session, snapshot: snapshot)
        ui.animateViewport(to: v.pannedByArrow(dx: dx, dy: dy, viewSize: ui.viewSize, bounds: MapBounds(snapshot)), session: session,
                           snapshot: snapshot, reduceMotion: viewportJumps)
        return .handled
    }

    func zoom(_ factor: Double, snapshot: MapSnapshot) {
        let v = ui.viewport(session: session, snapshot: snapshot)
        ui.animateViewport(to: v.zoomed(by: factor, viewSize: ui.viewSize, bounds: MapBounds(snapshot)), session: session,
                           snapshot: snapshot, reduceMotion: viewportJumps)
    }

    func fitGalaxy(_ snapshot: MapSnapshot) {
        ui.animateViewport(to: .fitGalaxy(MapBounds(snapshot)), session: session, snapshot: snapshot, reduceMotion: viewportJumps)
    }

    private func mapControl(_ snapshot: MapSnapshot) -> MapControl {
        let v = ui.viewport(session: session, snapshot: snapshot)
        return MapControl(scope: scope, canZoomIn: !v.isAtMaxZoom, canZoomOut: !v.isAtMinZoom,
                          zoomIn: { zoom(MapViewport.zoomStep, snapshot: snapshot) },
                          zoomOut: { zoom(1 / MapViewport.zoomStep, snapshot: snapshot) },
                          fit: { fitGalaxy(snapshot) })
    }

    // MARK: Scroll wheel (MAP-014)

    private func installScrollMonitor() {
        guard scope.hasHUD, ui.scrollMonitor == nil else { return }
        let ui = ui, session = session
        ui.scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            let command = event.modifierFlags.contains(.command), precise = event.hasPreciseScrollingDeltas
            let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
            let handled = MainActor.assumeIsolated {
                Self.scroll(ui: ui, session: session, command: command, precise: precise, dx: dx, dy: dy)
            }
            return handled ? nil : event
        }
    }

    /// Wheel / two-finger scroll pans; ⌘ + wheel zooms ×1.1 per step at the pointer. Returns whether it was handled.
    private static func scroll(ui: MapViewModel, session: GameSession, command: Bool, precise: Bool, dx: Double, dy: Double) -> Bool {
        guard let location = ui.hoverLocation, let snapshot = session.mapSnapshot else { return false }
        let v = ui.viewport(session: session, snapshot: snapshot)
        let bounds = MapBounds(snapshot)
        ui.closeCard()
        if command {
            let steps = dy / (precise ? 10 : 1)
            ui.setViewport(v.zoomed(by: pow(MapViewport.wheelZoomStep, steps), anchor: location, viewSize: ui.viewSize, bounds: bounds),
                           session: session, snapshot: snapshot)
        } else {
            let k: Double = precise ? 1 : 10
            ui.setViewport(v.panned(byViewDelta: CGSize(width: dx * k, height: dy * k), viewSize: ui.viewSize, bounds: bounds),
                           session: session, snapshot: snapshot)
        }
        return true
    }

    private func removeScrollMonitor() {
        if let m = ui.scrollMonitor { NSEvent.removeMonitor(m) }
        ui.scrollMonitor = nil
    }

    // MARK: Show on Map, search focus (MAP-012, MAP-078)

    private func handleFocusRequest(_ request: MapFocusRequest?, snapshot: MapSnapshot) {
        guard let request, request.scope == scope, scope.hasHUD else { return }
        let v = ui.viewport(session: session, snapshot: snapshot)
        ui.animateViewport(to: v.centered(on: request.system, snapshot: snapshot), session: session, snapshot: snapshot,
                           reduceMotion: viewportJumps)
        if request.pulse { ui.pulse(request.system) }
    }

    // MARK: Accessibility (MAP-081, MAP-082)

    private func accessibilityChildren(_ snapshot: MapSnapshot, projected: ProjectedMap) -> some View {
        let locked = MapActions.isLocked(snapshot, isModal: session.isInputLocked)
        let warpEnabled = WarpButtonModel.make(state: session.state, isModal: session.isInputLocked).isEnabled
        return ZStack(alignment: .topLeading) {
            ForEach(MapAccessibility.order(snapshot), id: \.self) { i in
                let r = projected.metrics.systemHitRadius(snapshot.systems[i].size)
                let c = projected.centers[i]
                Color.clear
                    .frame(width: 2 * r, height: 2 * r)
                    .position(c)
                    .accessibilityElement()
                    .accessibilityLabel(Text(verbatim: MapAccessibility.label(for: i, snapshot: snapshot)))
                    .accessibilityValue(Text(verbatim: MapAccessibility.value(for: i, snapshot: snapshot)))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier(ids.system(i))
                    .accessibilityRotorEntry(id: i, in: rotorNamespace)
                    .accessibilityFocused($axFocus, equals: i)
                    .modifier(SystemAXActions(enabled: !locked, index: i, snapshot: snapshot, warpEnabled: warpEnabled,
                                              send: sendFromMap, plot: { session.planRoute(to: i) }))
            }
        }
        .frame(width: ui.viewSize.width, height: ui.viewSize.height, alignment: .topLeading)
    }

    // MARK: Hover card (MAP-044…046)

    private func hoverCard(_ hit: MapHit, snapshot: MapSnapshot, projected: ProjectedMap, size: CGSize) -> some View {
        let model: HoverCardModel
        switch hit {
        case let .system(i):
            let jumps: HoverJumps = if let counts = session.hoverJumpCounts() {
                counts.indices.contains(i) ? (counts[i].map(HoverJumps.count) ?? .unreachable) : .unreachable
            } else { .computing }
            let titles = session.state.map { st in snapshot.systems[i].questKinds.map { QuestText.string(for: $0, state: st) } } ?? []
            let preview = session.state?.warpTargetPreview(i)
            // INT-036 / MAP-047: known prices and the best profit for the hold, from intel only.
            let intelRows = session.intelInputs().map { inputs in
                HoverIntel.rows(system: i, book: inputs.book, snapshot: inputs.snapshot) { String(localized: Names.item($0)) }
            } ?? []
            model = preview.map { HoverCardModel.make(system: snapshot.systems[i], snapshot: snapshot, preview: $0, jumps: jumps,
                                                      questTitles: titles, intelRows: intelRows) }
                ?? HoverCardModel(title: snapshot.systems[i].name, rows: [], tags: [])
        case let .wormhole(w):
            model = HoverCardModel.make(wormhole: w, snapshot: snapshot, tax: session.state.map { $0.wormholeTaxPerJump } ?? 0)
        }
        let (c, _) = glyph(hit, snapshot: snapshot, projected: projected)
        let cardSize = CGSize(width: 250, height: 30 + Double(model.rows.count) * 16 + (model.tags.isEmpty ? 0 : 20))
        let frame = HoverCardPlacement.frame(anchor: c, cardSize: cardSize, bounds: CGRect(origin: .zero, size: size))
        return HoverCardView(model: model)
            .frame(width: cardSize.width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .offset(x: frame.minX, y: frame.minY)
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(ids.hoverCard)
    }

    // MARK: HUD (MAP-016, MAP-027)

    private func hud(_ snapshot: MapSnapshot, size: CGSize) -> some View {
        ZStack {
            VStack(alignment: .leading) {
                MapSearchView(ui: ui, snapshot: snapshot, ids: ids, searchFocused: $searchFocused, center: { i in
                    let v = ui.viewport(session: session, snapshot: snapshot)
                    ui.animateViewport(to: v.centered(on: i, snapshot: snapshot), session: session, snapshot: snapshot,
                                       reduceMotion: viewportJumps)
                }, send: sendFromMap)
                Spacer()
                HStack(alignment: .bottom) {
                    if session.plannedRoute != nil {
                        RoutePanelView(ids: ids, snapshot: snapshot)
                    }
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            VStack {
                HStack {
                    Spacer()
                    MapZoomHUD(ids: ids, viewport: ui.viewport(session: session, snapshot: snapshot), legendShown: $ui.legendShown,
                               zoomIn: { zoom(MapViewport.zoomStep, snapshot: snapshot) },
                               zoomOut: { zoom(1 / MapViewport.zoomStep, snapshot: snapshot) },
                               fitRange: {
                                   ui.animateViewport(to: .fitRange(snapshot: snapshot, viewSize: ui.viewSize), session: session,
                                                      snapshot: snapshot, reduceMotion: viewportJumps)
                               },
                               fitGalaxy: { fitGalaxy(snapshot) })
                }
                HStack {
                    Spacer()
                    HeatmapHUDView(ids: ids, choice: $ui.heatmapChoice, item: $ui.heatmapItem,
                                   result: session.heatmap(ui.heatmapChoice.mode(item: ui.heatmapItem)))
                }
                if ui.legendShown {
                    HStack {
                        Spacer()
                        MapLegendView(ids: ids)
                    }
                }
                Spacer()
                TargetStripView(ids: ids, snapshot: snapshot, warpFocused: $warpFocused)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
    }
}

/// MAP-082: Set Target (default), Track / Stop Tracking, Plot Route, and Warp on the target's element.
private struct SystemAXActions: ViewModifier {
    let enabled: Bool
    let index: Int
    let snapshot: MapSnapshot
    let warpEnabled: Bool
    let send: (Command) -> Void
    let plot: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            let track = MapActions.trackCommand(for: index, snapshot: snapshot)
            content
                .accessibilityAction { send(.selectTarget(index)) }
                .accessibilityAction(named: snapshot.trackedSystem == index ? Text("Stop Tracking") : Text("Track")) {
                    if let track { send(track) }
                }
                .accessibilityAction(named: Text("Plot Route")) { if index != snapshot.currentSystem { plot() } }
                .modifier(WarpAXAction(shown: warpEnabled && snapshot.hasTarget && snapshot.warpSystem == index, send: send))
        } else {
            content
        }
    }
}

private struct WarpAXAction: ViewModifier {
    let shown: Bool
    let send: (Command) -> Void

    func body(content: Content) -> some View {
        if shown {
            content.accessibilityAction(named: Text("Warp")) { send(.warp) }
        } else {
            content
        }
    }
}

/// MAP-084: one rotor per `MapRotor`.
private struct MapRotors: ViewModifier {
    let snapshot: MapSnapshot
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        content
            .accessibilityRotor(Text(MapRotor.inRange.title)) { entries(.inRange) }
            .accessibilityRotor(Text(MapRotor.questLocations.title)) { entries(.questLocations) }
            .accessibilityRotor(Text(MapRotor.wormholes.title)) { entries(.wormholes) }
            .accessibilityRotor(Text(MapRotor.visited.title)) { entries(.visited) }
            .accessibilityRotor(Text(MapRotor.unvisited.title)) { entries(.unvisited) }
    }

    private func entries(_ rotor: MapRotor) -> some AccessibilityRotorContent {
        ForEach(MapRotor.members(rotor, snapshot: snapshot), id: \.self) { i in
            AccessibilityRotorEntry(Text(verbatim: snapshot.systems[i].name), id: i, in: namespace)
        }
    }
}
