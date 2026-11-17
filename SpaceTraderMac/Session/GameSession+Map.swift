// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Observation
import ParsecEngine
import ParsecInsights

/// MAP-063: the session-only planned route.
struct PlannedRoute: Equatable, Sendable {
    var destination: Int
    var objective: RouteObjective
    /// nil while planning, or when the destination can't be reached with a full tank.
    var route: Route?
    var generation: Int
    var isPlanning = false
}

/// The route planner entry points, injectable for tests (MAP-062).
struct RoutePlanning: Sendable {
    var plan: @Sendable (_ from: Int, _ to: Int, _ snapshot: RouteSnapshot, _ objective: RouteObjective) async -> Route?
    var jumpCounts: @Sendable (_ from: Int, _ snapshot: RouteSnapshot) async -> [Int?]

    static let standard = RoutePlanning(
        plan: { from, to, snapshot, objective in await RoutePlanning.planOffMain(from, to, snapshot, objective) },
        jumpCounts: { from, snapshot in await RoutePlanning.jumpCountsOffMain(from, snapshot) })

    /// Runs off the main actor (PRD §6.5 "Heavy pure work … runs off the main actor").
    @concurrent
    nonisolated static func planOffMain(_ from: Int, _ to: Int, _ snapshot: RouteSnapshot, _ objective: RouteObjective) async -> Route? {
        RoutePlanner.plan(from: from, to: to, in: snapshot, objective: objective)
    }

    @concurrent
    nonisolated static func jumpCountsOffMain(_ from: Int, _ snapshot: RouteSnapshot) async -> [Int?] {
        RoutePlanner.jumpCounts(from: from, in: snapshot)
    }
}

/// A request to centre a map on a system and pulse it (MAP-078), or to centre after search/rotor (MAP-012).
struct MapFocusRequest: Equatable, Sendable {
    var system: Int
    var scope: MapScope
    var serial: Int
    var pulse: Bool
}

/// Map state that lives for the session (MAP-018, MAP-062, MAP-078).
@Observable @MainActor
final class MapSessionState {
    /// Each map instance's viewport (the window also keeps its own in `@SceneStorage`).
    var viewports: [MapScope: MapViewport] = [:]
    /// Bumped when a new game, load or close resets every viewport to Fit Galaxy.
    private(set) var resetSerial = 0
    var focusRequest: MapFocusRequest?
    private var focusSerial = 0
    /// The Galaxy Chart window is on screen / key (MAP-068, MAP-070, MAP-078).
    var galaxyWindowOpen = false
    var galaxyWindowIsKey = false
    /// Hover-card jump counts for one generation (MAP-062).
    var jumpCounts: (generation: Int, counts: [Int?])?
    @ObservationIgnored var jumpCountsPending: Int?

    func reset() {
        viewports = [:]
        resetSerial += 1
        focusRequest = nil
        jumpCounts = nil
        jumpCountsPending = nil
    }

    func requestFocus(on system: Int, scope: MapScope, pulse: Bool) {
        focusSerial += 1
        focusRequest = MapFocusRequest(system: system, scope: scope, serial: focusSerial, pulse: pulse)
    }
}

extension GameSession {
    var galaxyWindowIsKey: Bool { map.galaxyWindowIsKey }

    /// MAP-003: rebuilt only when the generation or the planned route changes.
    var mapSnapshot: MapSnapshot? {
        guard let state else { return nil }
        let generation = stateGeneration
        let route = plannedRoute?.route
        if let cached = mapSnapshotCache, cached.generation == generation, cached.route == route { return cached }
        let snapshot = MapSnapshot.make(state: state, generation: generation, route: route)
        mapSnapshotCache = snapshot
        mapSnapshotBuilds += 1
        return snapshot
    }

    /// New game, load or close: forget the route and reset every viewport (MAP-018, MAP-063).
    func resetMapForNewGame() {
        routeTask?.cancel()
        routeTask = nil
        plannedRoute = nil
        mapSnapshotCache = nil
        map.reset()
    }

    // MARK: Route planning (MAP-062…065)

    /// MAP-062: plans off the main actor; applies the result only if the state has not changed meanwhile.
    func planRoute(to destination: Int, objective: RouteObjective = .fewestJumps) {
        planRoute(to: destination, objective: objective, retry: true)
    }

    private func planRoute(to destination: Int, objective: RouteObjective, retry: Bool) {
        guard let state, state.galaxy.systems.indices.contains(destination), destination != state.commander.currentSystem else { return }
        let generation = stateGeneration
        let keep = plannedRoute?.destination == destination ? plannedRoute?.route : nil
        plannedRoute = PlannedRoute(destination: destination, objective: objective, route: keep, generation: generation, isPlanning: true)
        let snapshot = RouteSnapshot(state)
        let from = state.commander.currentSystem
        let planner = routePlanner
        routeTask?.cancel()
        routeTask = Task { [weak self] in
            let route = await planner.plan(from, destination, snapshot, objective)
            guard !Task.isCancelled else { return }
            self?.finishPlanning(route, destination: destination, objective: objective, generation: generation, retry: retry)
        }
    }

    private func finishPlanning(_ route: Route?, destination: Int, objective: RouteObjective, generation: Int, retry: Bool) {
        guard plannedRoute?.destination == destination else { return }
        guard stateGeneration == generation else {
            if retry {
                planRoute(to: destination, objective: objective, retry: false)
            } else {
                plannedRoute?.isPlanning = false
            }
            return
        }
        plannedRoute = PlannedRoute(destination: destination, objective: objective, route: route, generation: generation)
        if let route { applyRouteFollower(route) }
    }

    /// Changes the objective of the planned route and replans.
    func setRouteObjective(_ objective: RouteObjective) {
        guard let pr = plannedRoute, pr.objective != objective else { return }
        planRoute(to: pr.destination, objective: objective)
    }

    /// MAP-063: Clear.
    func clearRoute() {
        routeTask?.cancel()
        routeTask = nil
        plannedRoute = nil
    }

    /// MAP-064: pre-selects the next hop's target (never warps).
    private func applyRouteFollower(_ route: Route) {
        guard let state, let command = RouteFollower.nextCommand(route: route, state: state),
              !RouteFollower.isApplied(command, state: state) else { return }
        send(command)
    }

    /// MAP-063…065: after a step that ends docked at a (new) system.
    func followPlannedRouteAfterDocking() {
        guard let pr = plannedRoute, let state else { return }
        let cur = state.commander.currentSystem
        if cur == pr.destination {
            clearRoute()
        } else if let route = pr.route, route.hops.contains(where: { $0.from == cur }) {
            applyRouteFollower(route)
        } else if !pr.isPlanning {
            planRoute(to: pr.destination, objective: pr.objective)
        }
    }

    /// Game › Plot Route… and the Bridge button (MAP-068): plan to the current target, shown in the Galaxy section
    /// unless the Galaxy Chart window is key.
    func plotRouteToTarget() {
        guard let state, state.warpSystem != state.commander.currentSystem else { return }
        let target = state.warpSystem
        if !map.galaxyWindowIsKey { selectedSection = .galaxy }
        planRoute(to: target)
    }

    // MARK: Hover jump counts (MAP-045, MAP-062)

    /// The jump counts of this generation; starts computing them (off the main actor) when missing.
    func hoverJumpCounts() -> [Int?]? {
        let generation = stateGeneration
        if let jc = map.jumpCounts, jc.generation == generation { return jc.counts }
        guard let state, map.jumpCountsPending != generation else { return nil }
        map.jumpCountsPending = generation
        let snapshot = RouteSnapshot(state)
        let from = state.commander.currentSystem
        let planner = routePlanner
        Task { [weak self] in
            let counts = await planner.jumpCounts(from, snapshot)
            guard let self, self.stateGeneration == generation else { return }
            self.map.jumpCounts = (generation, counts)
        }
        return nil
    }

    // MARK: Show on Map (MAP-078)

    /// Centres the Galaxy Chart window (when open) or the Galaxy section on `system` and pulses it. Never targets.
    func showOnMap(_ system: Int) {
        let scope: MapScope = map.galaxyWindowOpen ? .galaxyWindow : .galaxy
        if scope == .galaxy { selectedSection = .galaxy }
        map.requestFocus(on: system, scope: scope, pulse: true)
    }
}
