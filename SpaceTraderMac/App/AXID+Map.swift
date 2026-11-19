// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import ParsecInsights

extension AXID {
    /// Galaxy chart identifiers (MAP §20, MAP-099), built from a `MapScope` prefix.
    nonisolated struct Map: Sendable {
        let scope: MapScope
        init(_ scope: MapScope) { self.scope = scope }
        private var p: String { scope.prefix }

        var map: String { "\(p).map" }
        func system(_ i: Int) -> String { "\(p).system.\(i)" }
        var hoverCard: String { "\(p).hoverCard" }
        /// UI-PTR-011: the pinned selection card, its facts and its buttons.
        var selectionCard: String { "\(p).selectionCard" }
        var selectionFacts: String { "\(p).selectionCard.facts" }
        func selection(_ kind: MapContextItem.Kind) -> String {
            switch kind {
            case .setTarget: "\(p).selection.setTarget"
            case .track: "\(p).selection.track"
            case .plotRoute: "\(p).selection.plotRoute"
            case .useWormhole: "\(p).selection.useWormhole"
            case .findPrices: "\(p).selection.findPrices"
            }
        }
        var legend: String { "\(p).legend" }
        var legendToggle: String { "\(p).legend.toggle" }
        var zoomIn: String { "\(p).zoomIn" }
        var zoomOut: String { "\(p).zoomOut" }
        var fitRange: String { "\(p).fitRange" }
        var fitGalaxy: String { "\(p).fitGalaxy" }
        var target: String { "\(p).target" }
        var warp: String { "\(p).warp" }
        var jump: String { "\(p).jump" }
        var trackedRange: String { "\(p).trackedRange" }
        var wormholeLabel: String { "\(p).wormholeLabel" }
        var contextSetTarget: String { "\(p).context.setTarget" }
        var contextTrack: String { "\(p).context.track" }
        var contextPlotRoute: String { "\(p).context.plotRoute" }
        var contextUseWormhole: String { "\(p).context.useWormhole" }
        /// INT-037 / MAP-053 (M10).
        var contextFindPrices: String { "\(p).context.findPrices" }
        /// MAP-096 (M10).
        var heatmap: String { "\(p).heatmap" }
        var heatmapCommodity: String { "\(p).heatmap.commodity" }
        func context(_ kind: MapContextItem.Kind) -> String {
            switch kind {
            case .setTarget: contextSetTarget
            case .track: contextTrack
            case .plotRoute: contextPlotRoute
            case .useWormhole: contextUseWormhole
            case .findPrices: contextFindPrices
            }
        }
        var searchField: String { "\(p).search.field" }
        func searchResult(_ i: Int) -> String { "\(p).search.result.\(i)" }
        func searchFilter(_ f: SystemSearchFilter) -> String { "\(p).search.filter.\(f.rawValue)" }
        /// INT-028 (M10): the "sells <item>" filter menu.
        var searchFilterSells: String { "\(p).search.filter.sells" }
        var routePanel: String { "\(p).route.panel" }
        var routeObjective: String { "\(p).route.objective" }
        func routeObjective(_ o: RouteObjective) -> String { "\(p).route.objective.\(o.rawValue)" }
        func routeHop(_ n: Int) -> String { "\(p).route.hop.\(n)" }
        var routeClear: String { "\(p).route.clear" }
        var routeUnreachable: String { "\(p).route.unreachable" }

        /// The identifiers of this scope for systems `0..<systemCount`.
        func all(systemCount: Int) -> [String] {
            var ids = [map, hoverCard, legend, legendToggle, zoomIn, zoomOut, fitRange, fitGalaxy, target, warp, jump, trackedRange,
                       wormholeLabel, contextSetTarget, contextTrack, contextPlotRoute, contextUseWormhole, searchField, routePanel,
                       routeObjective, routeClear, routeUnreachable, contextFindPrices, heatmap, heatmapCommodity,
                       searchFilterSells, selectionCard, selectionFacts]
            ids += [MapContextItem.Kind.setTarget, .track, .plotRoute, .useWormhole, .findPrices].map(selection)
            ids += (0..<systemCount).flatMap { [system($0), searchResult($0)] }
            ids += SystemSearchFilter.allCases.map(searchFilter)
            ids += RouteObjective.allCases.map(routeObjective)
            ids += (1...systemCount).map(routeHop)
            return ids
        }
    }

    nonisolated enum Galaxy {
        static let root = "galaxy.root"
        static let windowRoot = "galaxyWindow.root"
        static let windowPlaceholder = "galaxyWindow.placeholder"
        static let miniChartMap = "bridge.miniChart.map"
        static let miniChartOpen = BridgeID.Chart.open
        static let bridgePlotRoute = "bridge.target.plotRoute"
        static let bridgeShowOnMap = "bridge.target.showOnMap"
        static func questShowOnMap(_ entry: Int) -> String { "quests.entry.\(entry).showOnMap" }
    }

    /// MAP-099: every map identifier for all three scopes (system indices of the largest content pack).
    nonisolated static var mapAll: [String] {
        let count = RulesetID.allCases.map { Ruleset.named($0).tables.systemNames.count }.max() ?? 0
        // `bridge.miniChart.map` is the mini chart's `map` identifier; root identifiers are listed once.
        return MapScope.allCases.flatMap { Map($0).all(systemCount: count) }
            + [Galaxy.windowRoot, Galaxy.windowPlaceholder, Galaxy.bridgePlotRoute, Galaxy.bridgeShowOnMap, Galaxy.miniChartOpen]
            + (0..<4).map(Galaxy.questShowOnMap)
    }
}
