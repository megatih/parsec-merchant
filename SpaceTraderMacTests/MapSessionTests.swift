// SPDX-License-Identifier: GPL-2.0-or-later
import CoreGraphics
import Foundation
import ParsecEngine
import ParsecInsights
import Testing
@testable import ParsecMerchant

/// A planner the test releases by hand (MAP-062).
actor GatedPlanner {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var calls = 0

    func wait() async {
        calls += 1
        await withCheckedContinuation { waiters.append($0) }
    }

    func releaseAll() {
        waiters.forEach { $0.resume() }
        waiters = []
    }

    var pending: Int { waiters.count }
}

@MainActor
@Suite("Galaxy chart: session, routes, placement, menus")
struct MapSessionTests {
    /// Waits for the session's route task (and the follow-up selection) to finish.
    static func settle(_ s: GameSession) async {
        for _ in 0..<20 {
            await s.routeTask?.value
            await Task.yield()
        }
    }

    static func farSystem(_ st: GameState?) -> Int? {
        guard let st else { return nil }
        return st.galaxy.systems.indices.filter { !st.destinationOK($0) && $0 != st.commander.currentSystem }
            .min { st.warpTargetPreview($0).distance < st.warpTargetPreview($1).distance }
    }

    @Test("MAP-003 the snapshot is rebuilt per generation, not per viewport change")
    func snapshotBuilds() throws {
        let s = try TestSessions.playing()
        let g0 = s.stateGeneration
        _ = s.mapSnapshot
        let builds = s.mapSnapshotBuilds
        let ui = MapViewModel(scope: .galaxy)
        let snap = try #require(s.mapSnapshot)
        for k in 0..<100 {
            ui.setViewport(MapViewport(zoom: 1 + Double(k % 10), center: CGPoint(x: k, y: k)), session: s, snapshot: snap)
            _ = s.mapSnapshot
        }
        #expect(s.mapSnapshotBuilds == builds)
        s.send(.selectTarget(snap.systems.indices.first { $0 != snap.currentSystem } ?? 0))
        _ = s.mapSnapshot
        #expect(s.stateGeneration == g0 + 1 && s.mapSnapshotBuilds == builds + 1)
        s.send(.track(3))
        s.send(.setOptions(s.state?.options ?? GameOptions()))
        #expect(s.stateGeneration == g0 + 3)
        s.send(.warp)
        let afterReject = s.stateGeneration
        s.send(.warp)
        #expect(s.lastRejection == nil || s.stateGeneration == afterReject)
        s.closeGame()
        #expect(s.stateGeneration > afterReject)
    }

    @Test("MAP-018 each map keeps its viewport; a new game, load or close resets them")
    func viewportsReset() throws {
        let s = try TestSessions.playing()
        s.map.viewports[.galaxy] = MapViewport(zoom: 4, center: CGPoint(x: 20, y: 20))
        s.map.viewports[.galaxyWindow] = MapViewport(zoom: 2, center: CGPoint(x: 40, y: 20))
        s.selectedSection = .bridge
        #expect(s.map.viewports[.galaxy]?.zoom == 4)
        let serial = s.map.resetSerial
        s.requestQuickStart()
        #expect(s.map.viewports.isEmpty && s.map.resetSerial == serial + 1)
        s.closeGame()
        #expect(s.map.resetSerial == serial + 2)
    }

    @Test("MAP-062 planning runs off the main actor and a stale result is discarded and replanned once")
    func stalePlan() async throws {
        let s = try TestSessions.playing()
        let gate = GatedPlanner()
        s.routePlanner = RoutePlanning(plan: { from, to, snap, objective in
            await gate.wait()
            return RoutePlanner.plan(from: from, to: to, in: snap, objective: objective)
        }, jumpCounts: { from, snap in RoutePlanner.jumpCounts(from: from, in: snap) })
        let st = try #require(s.state)
        let far = try #require(Self.farSystem(st))
        s.planRoute(to: far)
        #expect(s.plannedRoute?.isPlanning == true)
        while await gate.pending == 0 { await Task.yield() }
        s.send(.track(far))                      // the state changes while planning
        await gate.releaseAll()
        while await gate.calls < 2 { await Task.yield() }
        #expect(s.plannedRoute?.route == nil)    // stale result discarded, replanning
        while await gate.pending == 0 { await Task.yield() }
        await gate.releaseAll()
        await Self.settle(s)
        #expect(s.plannedRoute?.route?.to == far && s.plannedRoute?.isPlanning == false)
        #expect(await gate.calls == 2)
    }

    @Test("MAP-063 the planned route is session-only and cleared on new game, close, Clear and arrival")
    func plannedRouteLifetime() async throws {
        let s = try TestSessions.playing()
        let far = try #require(Self.farSystem(s.state))
        s.planRoute(to: far)
        await Self.settle(s)
        #expect(s.plannedRoute != nil)
        s.clearRoute()
        #expect(s.plannedRoute == nil)
        s.planRoute(to: far)
        await Self.settle(s)
        s.requestQuickStart()
        #expect(s.plannedRoute == nil)
        s.planRoute(to: far)
        s.closeGame()
        #expect(s.plannedRoute == nil)
    }

    @Test("MAP-064 RouteFollower: next hop when docked on the route; nil at the destination, off route or not docked")
    func follower() throws {
        let st = MapFx.state()
        let far = try #require(Self.farSystem(st))
        let route = try #require(RoutePlanner.plan(from: st.commander.currentSystem, to: far, in: RouteSnapshot(st)))
        let first = route.hops[0]
        #expect(RouteFollower.nextCommand(route: route, state: st) == (first.viaWormhole ? .selectWormhole(first.from) : .selectTarget(first.to)))
        var at = st
        at.commander.currentSystem = far
        #expect(RouteFollower.nextCommand(route: route, state: at) == nil)
        var off = st
        off.commander.currentSystem = st.galaxy.systems.indices.first { i in !route.hops.contains { $0.from == i } && i != far } ?? 0
        #expect(RouteFollower.nextCommand(route: route, state: off) == nil)
        var moving = st
        moving.phase = .gameOver(.retired)
        #expect(RouteFollower.nextCommand(route: route, state: moving) == nil)
        let w = RouteHop(from: 3, to: 9, viaWormhole: true, distance: 30, fuelBefore: 0, refuelUnits: 0, refuelCost: 0, cost: 0)
        var wst = st
        wst.commander.currentSystem = 3
        let wr = Route(from: 3, to: 9, objective: .fewestJumps, hops: [w], totalJumps: 1, totalParsecs: 0, estimatedCredits: 0,
                       totalRefuelUnits: 0)
        #expect(RouteFollower.nextCommand(route: wr, state: wst) == .selectWormhole(3))
    }

    @Test("MAP-065 off the route the session replans; an unreachable destination keeps route nil")
    func replan() async throws {
        let s = try TestSessions.playing()
        let st = try #require(s.state)
        let far = try #require(Self.farSystem(st))
        s.planRoute(to: far)
        await Self.settle(s)
        let original = try #require(s.plannedRoute?.route)
        #expect(s.state?.warpSystem == original.hops[0].to || original.hops[0].viaWormhole)
        // Dock somewhere off the route: the session replans from there.
        let off = try #require(st.galaxy.systems.indices.first { i in i != far && !original.hops.contains { $0.from == i || $0.to == i } })
        try TestSessions.edit(s) { $0.commander.currentSystem = off }
        s.plannedRoute = PlannedRoute(destination: far, objective: .fewestJumps, route: original, generation: s.stateGeneration)
        s.followPlannedRouteAfterDocking()
        await Self.settle(s)
        #expect(s.plannedRoute?.route?.from == off && s.plannedRoute?.destination == far)
        // Unreachable: a 0-capacity tank can't make any normal hop.
        let gate = RoutePlanning(plan: { _, _, _, _ in nil }, jumpCounts: { _, _ in [] })
        s.routePlanner = gate
        s.planRoute(to: far)
        await Self.settle(s)
        #expect(s.plannedRoute?.destination == far && s.plannedRoute?.route == nil && s.plannedRoute?.isPlanning == false)
    }

    @Test("MAP-068 Plot Route: enabled iff game command and a target; shows the Galaxy section unless the window is key")
    func plotRoute() async throws {
        let s = try TestSessions.playing()
        var ctx = MenuContext.make(session: s)
        #expect(!MenuRules.availability(of: .plotRoute, in: ctx).isEnabled)
        let far = try #require(Self.farSystem(s.state))
        s.send(.selectTarget(far))
        ctx = MenuContext.make(session: s)
        #expect(MenuRules.availability(of: .plotRoute, in: ctx).isEnabled)
        s.plotRouteToTarget()
        #expect(s.selectedSection == .galaxy && s.plannedRoute?.destination == far)
        await Self.settle(s)
        s.selectedSection = .bridge
        s.map.galaxyWindowIsKey = true
        s.send(.selectTarget(far))
        s.plotRouteToTarget()
        #expect(s.selectedSection == .bridge)
        await Self.settle(s)
    }

    @Test("MAP-067 the route panel's data: hops, refuel, totals; unreachable text")
    func routePanelData() async throws {
        let s = try TestSessions.playing()
        let far = try #require(Self.farSystem(s.state))
        s.planRoute(to: far)
        await Self.settle(s)
        let route = try #require(s.plannedRoute?.route)
        #expect(route.hops.count >= 2 && route.hops.first?.from == s.state?.commander.currentSystem && route.hops.last?.to == far)
        #expect(route.estimatedCredits == route.hops.reduce(0) { $0 + $1.cost })
        let ids = AXID.Map(.galaxy)
        #expect([ids.routePanel, ids.routeObjective, ids.routeHop(1), ids.routeClear, ids.routeUnreachable].allSatisfy(AXID.all.contains))
        s.setRouteObjective(.cheapest)
        await Self.settle(s)
        #expect(s.plannedRoute?.objective == .cheapest && s.plannedRoute?.route != nil)
    }

    @Test("MAP-070 ⌘F searches the map in the Galaxy section or when the Galaxy Chart window is key")
    func contextSearch() throws {
        let s = try TestSessions.playing()
        s.selectedSection = .galaxy
        #expect(MenuContext.make(session: s).searchContext == .galaxy)
        var focused = false
        ContextSearch.perform(.galaxy, focused: ContextSearchAction { focused = true }, session: s)
        #expect(focused && s.presentation == nil)
        s.selectedSection = .market
        s.map.galaxyWindowIsKey = true
        #expect(MenuContext.make(session: s).searchContext == .galaxy)
        s.map.galaxyWindowIsKey = false
        #expect(MenuContext.make(session: s).searchContext == .market)
        s.selectedSection = .bridge
        ContextSearch.perform(MenuContext.make(session: s).searchContext, focused: nil, session: s)
        #expect(s.presentation == .sheet(.findSystem))
    }

    @Test("MAP-073 Return with no suggestion uses FindInput like the Find System sheet; unknown text finds nothing")
    func searchReturn() throws {
        let s = try TestSessions.playing()
        let st = try #require(s.state)
        let name = st.ruleset.tables.systemNames[10]
        let outcome = FindSystemModel.resolve(String(name.prefix(3)), track: false, state: st)
        let first = FindSystemModel.matches(String(name.prefix(3)), in: st).first
        #expect(outcome == .select(system: first ?? -1, track: false))
        #expect(FindSystemModel.resolve("zzzqqq", track: false, state: st) == .noMatch)
        let ui = MapViewModel(scope: .galaxy)
        let snap = try #require(s.mapSnapshot)
        ui.searchText = String(name.prefix(3))
        let list = ui.suggestions(snap)
        ui.moveHighlight(by: 1, in: list)
        #expect(ui.highlightedSuggestion == list.first)
        ui.moveHighlight(by: -1, in: list)
        #expect(ui.highlightedSuggestion == list.first)
        ui.filters = [.inRange]
        ui.searchText = ""
        #expect(ui.suggestions(snap).allSatisfy { snap.systems[$0].inRange } && !SystemSearch.dimmed(filters: ui.filters, snapshot: snap).isEmpty)
    }

    @Test("MAP-074 the mini chart shows ±20 parsecs on its shorter side around the current system")
    func miniChart() throws {
        let snap = MapFx.snapshot(MapFx.state())
        let size = CGSize(width: 420, height: 240)
        let v = MapViewModel.miniChartViewport(snapshot: snap, viewSize: size)
        let p = v.projection(viewSize: size, bounds: MapBounds(snap))
        #expect(abs(p.scale * 40 - 240) < 1e-9)
        #expect(p.toView(x: snap.current.x, y: snap.current.y) == CGPoint(x: 210, y: 120))
        #expect(!MapScope.miniChart.hasHUD && MapScope.miniChart.prefix == "bridge.miniChart")
        #expect(ProjectedMap.make(snapshot: snap, viewport: v, viewSize: size, labelAll: true).labels.count > 3)
    }

    @Test("MAP-075 the Galaxy section sits between Bank and Quests with ⌘7")
    func section() {
        #expect(Section.allCases == [.bridge, .market, .shipyard, .outfitter, .crew, .bank, .galaxy, .quests, .logbook])
        #expect(Section.galaxy.shortcutDigit == "7" && Section.galaxy.systemImage == "map" && Section.galaxy.axID == "sidebar.galaxy")
        #expect(AXID.SectionRoot.root(.galaxy) == "galaxy.root")
        #expect(Section.galaxy.isAvailable(in: SectionContext.make(state: MapFx.state())))
        #expect(!Section.galaxy.isAvailable(in: .noGame))
    }

    @Test("MAP-076 the Galaxy Chart window: id, sizes, identifiers")
    func window() {
        #expect(GalaxyWindowMetrics.id == "galaxy" && GalaxyWindowMetrics.defaultSize == CGSize(width: 1000, height: 720))
        #expect(GalaxyWindowMetrics.minimumSize == CGSize(width: 640, height: 480))
        #expect(MenuCatalog.entry(for: .galaxyChartWindow).identifier == "menu.window.galaxyChart")
        #expect(AXID.all.contains("galaxyWindow.warp") && AXID.all.contains(AXID.Galaxy.windowPlaceholder))
    }

    @Test("MAP-077 every map reads the same session snapshot, so a change shows everywhere after one step")
    func sync() throws {
        let s = try TestSessions.playing()
        let snap = try #require(s.mapSnapshot)
        let t = snap.systems.indices.first { $0 != snap.currentSystem } ?? 0
        s.send(MapActions.clickCommand(for: .system(t), snapshot: snap))
        #expect(s.mapSnapshot?.warpSystem == t && s.state?.warpSystem == t)
        let after = try #require(s.mapSnapshot)
        #expect(MapAccessibility.value(for: t, snapshot: after).hasPrefix("target"))
    }

    @Test("MAP-078 Show on Map targets the window when open, else the section; it never changes the target")
    func showOnMap() throws {
        let s = try TestSessions.playing()
        let target = s.state?.warpSystem
        s.showOnMap(12)
        #expect(s.selectedSection == .galaxy && s.map.focusRequest?.scope == .galaxy && s.map.focusRequest?.system == 12)
        #expect(s.map.focusRequest?.pulse == true && s.state?.warpSystem == target)
        s.selectedSection = .bridge
        s.map.galaxyWindowOpen = true
        s.showOnMap(13)
        #expect(s.selectedSection == .bridge && s.map.focusRequest?.scope == .galaxyWindow)
    }

    @Test("MAP-039 the target strip's wormhole line follows the engine preview")
    func wormholeLabel() throws {
        let s = try TestSessions.playing()
        let st = try #require(s.state)
        let w = try #require(st.galaxy.wormholes.first)
        try TestSessions.edit(s) { $0.commander.currentSystem = w }
        s.send(.selectWormhole(w))
        let st2 = try #require(s.state)
        #expect(st2.warpTargetPreview(st2.warpSystem).viaWormhole && AXID.all.contains(AXID.Map(.galaxy).wormholeLabel))
    }

    @Test("MAP-040 tracked range: the distance under the ruleset rule, shown while showTrackedRange is on")
    func trackedRange() throws {
        let s = try TestSessions.playing()
        let far = try #require(Self.farSystem(s.state))
        s.send(.track(far))
        let snap = try #require(s.mapSnapshot)
        #expect(snap.trackedSystem == far && snap.showTrackedRange)
        #expect(snap.systems[far].distance == s.state.map { GalaxyGenerator.distance($0.galaxy.systems[far], $0.currentSystem, rule: .floor) })
    }

    @Test("MAP-051 double-click sends the click's command and asks for Warp focus; it never warps")
    func doubleClick() throws {
        let s = try TestSessions.playing()
        let snap = try #require(s.mapSnapshot)
        let t = snap.systems.first { $0.inRange }?.index ?? 0
        let a = MapActions.action(for: .system(t), gesture: .doubleClick, snapshot: snap)
        #expect(a == .sendAndFocusWarp(.selectTarget(t)))
        let days = s.state?.commander.days
        if case let .sendAndFocusWarp(c) = a { s.send(c) }
        #expect(s.state?.commander.days == days && s.state?.warpSystem == t)
    }

    @Test("MAP-013 MAP-014 MAP-015 gesture and key arithmetic: pinch anchor, ⌘-wheel ×1.1, 3 pt click slop, arrows ⅛, ⌘± √2")
    func gestureMath() {
        let b = MapBounds(galaxyWidth: 154, galaxyHeight: 110)
        let v = MapViewport(zoom: 2, center: CGPoint(x: 60, y: 50))
        #expect(MapViewport.wheelZoomStep == 1.1 && abs(MapViewport.zoomStep - 2.0.squareRoot()) < 1e-12)
        let z = v.zoomed(by: MapViewport.zoomStep, viewSize: MapFx.view, bounds: b)
        #expect(abs(z.zoom - 2 * 2.0.squareRoot()) < 1e-12 && abs(z.center.x - 60) < 1e-9)
        let arrow = v.pannedByArrow(dx: 1, dy: 0, viewSize: MapFx.view, bounds: b)
        #expect(abs((arrow.center.x - v.center.x) * v.scale(viewSize: MapFx.view, bounds: b) - 100) < 1e-9)
        let pinch = v.zoomed(by: 3, anchor: CGPoint(x: 10, y: 10), viewSize: MapFx.view, bounds: b)
        #expect(pinch.zoom == 6)
        #expect(MapViewport(zoom: 30, center: .zero).clamped(b).zoom == 12)
    }

    @Test("MAP-016 MAP-017 HUD limits and animation: Zoom In/Out disabled at the limits; Reduce Motion is instant")
    func hudAndAnimation() throws {
        let s = try TestSessions.playing()
        let snap = try #require(s.mapSnapshot)
        let b = MapBounds(snap)
        #expect(MapViewport.fitGalaxy(b).isAtMinZoom && MapViewport(zoom: 12, center: .zero).isAtMaxZoom)
        let ui = MapViewModel(scope: .galaxy)
        let target = MapViewport(zoom: 5, center: CGPoint(x: 30, y: 30))
        ui.animateViewport(to: target, session: s, snapshot: snap, reduceMotion: true)
        #expect(s.map.viewports[.galaxy] == target)
        ui.animateViewport(to: .fitGalaxy(b), session: s, snapshot: snap, reduceMotion: false)
        #expect(s.map.viewports[.galaxy] == target)  // animating: not jumped yet
    }

    @Test("MAP-081 MAP-082 MAP-084 accessibility children per system with actions; rotors list the system elements")
    func accessibilityModel() throws {
        let s = try TestSessions.playing()
        let snap = try #require(s.mapSnapshot)
        let order = MapAccessibility.order(snap)
        #expect(Set(order) == Set(snap.systems.indices) && order.first == snap.currentSystem)
        #expect(MapAccessibility.label(for: order[1], snapshot: snap).contains(snap.systems[order[1]].name))
        #expect(MapRotor.allCases.allSatisfy { MapRotor.members($0, snapshot: snap).allSatisfy(snap.systems.indices.contains) })
        let v = MapViewport.fitGalaxy(MapBounds(snap)).centered(on: order.last ?? 0, snapshot: snap)
        #expect(v.zoom >= 3)
    }

    @Test("MAP-086 keyboard path controls carry identifiers")
    func keyboardPath() {
        let ids = AXID.Map(.galaxy)
        let path = [ids.searchField, ids.searchFilter(.inRange), ids.zoomIn, ids.zoomOut, ids.fitRange, ids.fitGalaxy, ids.legendToggle,
                    ids.map, ids.routePanel, ids.target, ids.warp]
        #expect(path.allSatisfy(AXID.all.contains))
    }

    @Test("MAP-100 mapFlowTarget is the in-range system nearest the flow start and a warp there docks on day 1")
    func flowTarget() throws {
        let s = try TestSessions.make(seed: FlowFixtures.mapFlowSeed)
        s.requestQuickStart()
        let st = try #require(s.state)
        let nearest = st.destinations.filter { !st.galaxy.wormholeExists(from: st.commander.currentSystem, to: $0) }
            .min { (st.warpTargetPreview($0).distance, $0) < (st.warpTargetPreview($1).distance, $1) }
        #expect(FlowFixtures.mapFlowTarget == nearest)
        s.send(.selectTarget(FlowFixtures.mapFlowTarget))
        s.send(.warp)
        let end = try #require(s.state)
        #expect(end.phase == .docked && end.commander.currentSystem == FlowFixtures.mapFlowTarget && end.commander.days == 1)
        // MAP-102's route: the nearest out-of-range system, ≥ 2 hops, whose first hop is an uneventful warp too.
        let r = try TestSessions.make(seed: FlowFixtures.mapFlowSeed)
        r.requestQuickStart()
        let rs = try #require(r.state)
        let far = rs.galaxy.systems.indices.filter { !rs.destinationOK($0) && $0 != rs.commander.currentSystem }
            .min { (rs.warpTargetPreview($0).distance, $0) < (rs.warpTargetPreview($1).distance, $1) }
        #expect(far == FlowFixtures.mapRouteDestination)
        let route = try #require(RoutePlanner.plan(from: rs.commander.currentSystem, to: FlowFixtures.mapRouteDestination, in: RouteSnapshot(rs)))
        #expect(route.hops.count >= 2 && route.hops[0].to == FlowFixtures.mapFlowTarget && !route.hops[0].viaWormhole)
    }
}
