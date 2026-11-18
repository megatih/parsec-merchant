// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import ParsecInsights
import SwiftUI

/// The hover card's content (MAP-045, MAP-046).
struct HoverCardView: View {
    let model: HoverCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: model.title).scaledFont(.headline)
            ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in
                Text(verbatim: row).scaledFont(.caption).foregroundStyle(.readableSecondary)
            }
            if !model.tags.isEmpty {
                Text(verbatim: model.tags.joined(separator: " · ")).scaledFont(.caption, weight: .bold).foregroundStyle(.signalOrange)
            }
        }
        .padding(10)
        .overlayBackground(cornerRadius: 10)  // A11Y-019
        .compositingGroup()  // one shadow for the card, not a halo around each text
        .shadow(radius: 4)
    }
}

/// Zoom In, Zoom Out, Fit Range, Fit Galaxy and Legend in the glass HUD (MAP-016).
struct MapZoomHUD: View {
    let ids: AXID.Map
    let viewport: MapViewport
    @Binding var legendShown: Bool
    let zoomIn: () -> Void
    let zoomOut: () -> Void
    let fitRange: () -> Void
    let fitGalaxy: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            button("Zoom In", "plus.magnifyingglass", ids.zoomIn, help: "Zoom in (⌘+)", action: zoomIn)
                .disabled(viewport.isAtMaxZoom)
            button("Zoom Out", "minus.magnifyingglass", ids.zoomOut, help: "Zoom out (⌘−)", action: zoomOut)
                .disabled(viewport.isAtMinZoom)
            button("Fit Range", "scope", ids.fitRange, help: "Show the systems in range", action: fitRange)
            button("Fit Galaxy", "arrow.up.left.and.down.right.magnifyingglass", ids.fitGalaxy, help: "Show the whole galaxy (⌘0)",
                   action: fitGalaxy)
            button("Legend", "info.circle", ids.legendToggle, help: "Show or hide the legend") { legendShown.toggle() }
        }
        .buttonStyle(.borderless)
        .padding(6)
        .glassEffect(in: .capsule)
    }

    private func button(_ title: LocalizedStringResource, _ symbol: String, _ id: String, help: LocalizedStringResource,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label { Text(title) } icon: { Image(systemName: symbol) }
                .labelStyle(.iconOnly)
                .pointerTarget()  // UI-PTR-013
        }
        .help(Text(help))
        .accessibilityLabel(Text(title))
        .accessibilityIdentifier(id)
    }
}

/// The legend overlay (MAP-032): each symbol drawn by the renderer's own primitives, with its meaning.
struct MapLegendView: View {
    let ids: AXID.Map

    private enum Symbol: CaseIterable {
        case visited, unvisited, current, target, tracked, quest, wormhole, range, fullTank, route, outOfRange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(Symbol.allCases.enumerated()), id: \.offset) { _, symbol in
                HStack(spacing: 12) {  // room between a swatch and its text (A11Y-029 contrast sampling)
                    Canvas { ctx, size in draw(symbol, in: &ctx, center: CGPoint(x: size.width / 2, y: size.height / 2)) }
                        .frame(width: 26, height: 18)
                        .background(MapStyle.spaceBottom, in: .rect(cornerRadius: 3))
                        .accessibilityHidden(true)
                    Text(title(symbol)).scaledFont(.caption)
                }
            }
        }
        .padding(10)
        .overlayBackground(cornerRadius: 10)  // A11Y-019
        // A11Y-029: a labelled container; each meaning is its own text (a combined element would be measured over the
        // dark symbol swatches).
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Legend"))
        .accessibilityIdentifier(ids.legend)
    }

    private func title(_ s: Symbol) -> LocalizedStringResource {
        switch s {
        case .visited: "Visited system"
        case .unvisited: "Unvisited system"
        case .current: "Current system"
        case .target: "Target"
        case .tracked: "Tracked system"
        case .quest: "Quest location"
        case .wormhole: "Wormhole and link direction"
        case .range: "Fuel range"
        case .fullTank: "Full-tank range"
        case .route: "Route and hop number"
        case .outOfRange: "Out of range (dimmed)"
        }
    }

    private func draw(_ s: Symbol, in ctx: inout GraphicsContext, center c: CGPoint) {
        let r = 3.5
        let disc = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        switch s {
        case .visited, .current, .target, .tracked, .quest:
            ctx.fill(disc, with: .color(MapStyle.visited))
            if s == .current {
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r - 4, y: c.y - r - 4, width: 2 * r + 8, height: 2 * r + 8)),
                           with: .color(MapStyle.brass), lineWidth: 1.5)
            }
            if s == .target {
                var p = Path()
                for (dx, dy) in [(1.0, 0.0), (-1, 0), (0, 1), (0, -1)] {
                    p.move(to: CGPoint(x: c.x + dx * (r + 2), y: c.y + dy * (r + 2)))
                    p.addLine(to: CGPoint(x: c.x + dx * (r + 6), y: c.y + dy * (r + 6)))
                }
                ctx.stroke(p, with: .color(MapStyle.target), lineWidth: 1.2)
            }
            if s == .tracked {
                var f = Path()
                f.move(to: CGPoint(x: c.x + 2, y: c.y - 8))
                f.addLine(to: CGPoint(x: c.x + 9, y: c.y - 5))
                f.addLine(to: CGPoint(x: c.x + 2, y: c.y - 2))
                ctx.fill(f, with: .color(MapStyle.tracked))
            }
            if s == .quest {
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 9, y: c.y - 8, width: 4, height: 4)), with: .color(MapStyle.quest))
            }
        case .unvisited:
            ctx.fill(disc, with: .color(MapStyle.glyphCenter))
            ctx.stroke(disc, with: .color(MapStyle.unvisited), lineWidth: 1.4)
        case .outOfRange:
            ctx.fill(disc, with: .color(MapStyle.visited.opacity(MapGlyphStyle.outOfRangeOpacity)))
        case .wormhole:
            GalaxyMapRenderer.drawVortex(&ctx, center: CGPoint(x: c.x - 5, y: c.y), radius: 5)
            var p = Path()
            p.move(to: CGPoint(x: c.x + 1, y: c.y))
            p.addLine(to: CGPoint(x: c.x + 11, y: c.y))
            ctx.stroke(p, with: .color(MapStyle.wormholeB), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
        case .range, .fullTank:
            let ring = Path(ellipseIn: CGRect(x: c.x - 8, y: c.y - 7, width: 16, height: 14))
            if s == .range {
                ctx.fill(ring, with: .color(MapStyle.range.opacity(0.15)))
                ctx.stroke(ring, with: .color(MapStyle.range), lineWidth: 1.5)
            } else {
                ctx.stroke(ring, with: .color(MapStyle.range), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
        case .route:
            var p = Path()
            p.move(to: CGPoint(x: c.x - 11, y: c.y))
            p.addLine(to: CGPoint(x: c.x + 3, y: c.y))
            ctx.stroke(p, with: .color(MapStyle.route), lineWidth: 2.5)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x + 2, y: c.y - 6, width: 12, height: 12)), with: .color(MapStyle.route))
            ctx.draw(Text(verbatim: "1").font(.system(size: 8, weight: .bold)).foregroundStyle(.black), at: CGPoint(x: c.x + 8, y: c.y))
        }
    }
}

/// The target strip (bottom centre): target, wormhole and tracked-range lines, Warp (MAP-027, MAP-039, MAP-040, MAP-051).
struct TargetStripView: View {
    @Environment(GameSession.self) private var session
    let ids: AXID.Map
    let snapshot: MapSnapshot
    var warpFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Group {
                    if snapshot.hasTarget {
                        let t = snapshot.systems[snapshot.warpSystem]
                        Text("Target: \(t.name) · \(MapText.parsecs(t.distance))")
                    } else {
                        Text("No target selected")
                    }
                }
                .scaledFont(.callout, weight: .bold)
                .accessibilityIdentifier(ids.target)
                if let state = session.state, snapshot.hasTarget, state.warpTargetPreview(snapshot.warpSystem).viaWormhole {
                    Text("Wormhole to \(snapshot.systems[snapshot.warpSystem].name)")
                        .scaledFont(.caption)
                        .accessibilityIdentifier(ids.wormholeLabel)
                }
                if snapshot.showTrackedRange, let t = snapshot.trackedSystem, t != snapshot.currentSystem {
                    Text("\(MapText.parsecs(snapshot.systems[t].distance)) to \(snapshot.systems[t].name).")
                        .scaledFont(.caption)
                        .accessibilityIdentifier(ids.trackedRange)
                }
            }
            let warp = WarpButtonModel.make(state: session.state, isModal: session.isInputLocked)
            Button {
                session.send(.warp)
            } label: {
                Label("Warp", systemImage: "arrow.up.forward.circle")
            }
            .disabled(!warp.isEnabled)
            .focused(warpFocused)
            .help(warp.help)
            .accessibilityIdentifier(ids.warp)
            if let state = session.state, state.quests.canSuperWarp {
                Button("Use Singularity") { session.send(.jump) }
                    .disabled(!state.jumpPreview.available || session.isInputLocked)
                    .help(Text("Jump with the portable singularity."))
                    .accessibilityIdentifier(ids.jump)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .overlayBackground(cornerRadius: 18)  // A11Y-019/029: legible over the dark map in the light appearance
        .accessibilityElement(children: .contain)
    }
}

/// The route panel (MAP-067).
struct RoutePanelView: View {
    @Environment(GameSession.self) private var session
    let ids: AXID.Map
    let snapshot: MapSnapshot

    var body: some View {
        if let pr = session.plannedRoute {
            VStack(alignment: .leading, spacing: 6) {
                Text("Route to \(snapshot.systems[pr.destination].name)").scaledFont(.headline)
                // A11Y-026: the objectives wrap rather than truncate their titles.
                WrappingHStack(spacing: 4, lineSpacing: 4, leading: true) {
                    ForEach(RouteObjective.allCases, id: \.self) { objective in
                        Button {
                            session.setRouteObjective(objective)
                        } label: {
                            Text(RouteObjectiveText.title(objective)).pointerTarget()
                        }
                        .buttonStyle(.bordered)
                        .tint(pr.objective == objective ? .accentColor : nil)
                        .help(Text(RouteObjectiveText.help(objective)))
                        .accessibilityAddTraits(pr.objective == objective ? .isSelected : [])
                        .accessibilityIdentifier(ids.routeObjective(objective))
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(ids.routeObjective)
                if let route = pr.route {
                    ForEach(Array(route.hops.enumerated()), id: \.offset) { n, hop in
                        hopRow(n + 1, hop)
                    }
                    Divider()
                    Text("\(route.totalJumps) jumps · \(route.totalParsecs) parsecs · \(route.estimatedCredits) cr. (Estimate)")
                        .scaledFont(.caption)
                        .fixedSize(horizontal: false, vertical: true)  // A11Y-026: wraps rather than truncating
                } else if pr.isPlanning {
                    ProgressView().controlSize(.small)
                } else {
                    Text("\(snapshot.systems[pr.destination].name) can't be reached with a full tank (\(snapshot.fuelCapacity) parsecs per jump).")
                        .scaledFont(.caption)
                        .foregroundStyle(.signalRed)
                        .accessibilityIdentifier(ids.routeUnreachable)
                }
                Button("Clear") { session.clearRoute() }
                    .help(Text("Forget this route."))
                    .accessibilityIdentifier(ids.routeClear)
            }
            .padding(10)
            .frame(width: 300, alignment: .leading)
            .overlayBackground(cornerRadius: 10)  // A11Y-019
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(ids.routePanel)
        }
    }

    private func hopLabel(_ n: Int, _ hop: RouteHop) -> String {
        var parts = ["\(n). \(snapshot.systems[hop.from].name) → \(snapshot.systems[hop.to].name)",
                     hop.viaWormhole ? String(localized: "Wormhole") : MapText.parsecs(hop.distance)]
        if hop.refuelUnits > 0 { parts.append(String(localized: "Buy \(hop.refuelUnits) fuel (\(hop.refuelCost) cr.)")) }
        parts.append(String(localized: "\(hop.cost) cr."))
        return parts.joined(separator: ", ")
    }

    private func hopRow(_ n: Int, _ hop: RouteHop) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: "\(n). \(snapshot.systems[hop.from].name) → \(snapshot.systems[hop.to].name)").scaledFont(.caption, weight: .bold)
            HStack {
                Text(hop.viaWormhole ? String(localized: "Wormhole") : MapText.parsecs(hop.distance))
                if hop.refuelUnits > 0 { Text("Buy \(hop.refuelUnits) fuel (\(hop.refuelCost) cr.)") }
                Spacer()
                Text("\(hop.cost) cr.")
            }
            .scaledFont(.caption2)
            .foregroundStyle(.readableSecondary)
        }
        // A11Y-029: a labelled container, so each line is measured in its own colour.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: hopLabel(n, hop)))
        .accessibilityIdentifier(ids.routeHop(n))
    }
}

/// The inline map search with filters and suggestions (MAP-070…073).
struct MapSearchView: View {
    @Environment(GameSession.self) private var session
    @Bindable var ui: MapViewModel
    let snapshot: MapSnapshot
    let ids: AXID.Map
    var searchFocused: FocusState<Bool>.Binding
    let center: (Int) -> Void
    let send: (Command) -> Void

    var body: some View {
        let sells = session.sellsMatches(ui.sellsItem)
        let suggestions = ui.suggestions(snapshot, sells: sells)
        VStack(alignment: .leading, spacing: 6) {
            TextField("Find a system", text: $ui.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .focused(searchFocused)
                .onChange(of: ui.searchText) {
                    ui.searchMessage = nil
                    ui.highlightedSuggestion = nil
                    ui.suggestionsShown = true
                }
                .onKeyPress(.downArrow) {
                    ui.moveHighlight(by: 1, in: suggestions)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    ui.moveHighlight(by: -1, in: suggestions)
                    return .handled
                }
                .onKeyPress(.escape) {
                    ui.suggestionsShown = false
                    return .handled
                }
                .onSubmit { submit(suggestions) }
                .help(Text("Type a system name; Return selects it."))
                .accessibilityLabel(Text("Search systems"))  // A11Y-003
                .accessibilityIdentifier(ids.searchField)
            // A11Y-026: the filters wrap rather than run under the zoom and heatmap controls.
            WrappingHStack(spacing: 4, lineSpacing: 4, leading: true) {
                ForEach(SystemSearchFilter.offered(snapshot), id: \.self) { f in
                    Toggle(isOn: Binding { ui.filters.contains(f) } set: { on in
                        if on { ui.filters.insert(f) } else { ui.filters.remove(f) }
                        ui.suggestionsShown = true
                    }) {
                        Text(title(f)).pointerTarget()
                    }
                    .toggleStyle(.button)
                    .help(Text(title(f)))
                    .accessibilityIdentifier(ids.searchFilter(f))
                }
                // INT-028: "sells <item>" from intel only (estimates marked in the rows).
                // A11Y-029: an AppKit pull-down (SwiftUI's Menu has no press action for VoiceOver on macOS 27).
                PopUpMenuButton(title: ui.sellsItem.map { String(localized: "Sells \(String(localized: Names.item($0)))") }
                                    ?? String(localized: "Sells…"),
                                items: [PopUpMenuButton.Item(title: String(localized: "Any commodity"), isOn: ui.sellsItem == nil) {
                                    ui.sellsItem = nil
                                }] + TradeItemType.allCases.map { item in
                                    PopUpMenuButton.Item(title: String(localized: Names.item(item)), isOn: ui.sellsItem == item) {
                                        ui.sellsItem = item
                                        ui.suggestionsShown = true
                                    }
                                },
                                accessibilityLabel: String(localized: "Sells commodity"), identifier: ids.searchFilterSells,
                                controlSize: .small)
            }
            if let message = ui.searchMessage {
                Text(verbatim: message).scaledFont(.caption).foregroundStyle(.signalRed)
            }
            if ui.suggestionsShown, !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(suggestions, id: \.self) { i in
                        Button {
                            choose(i)
                        } label: {
                            HStack {
                                Text(verbatim: snapshot.systems[i].name)
                                if let sells, sells.indices.contains(i), sells[i] == .estimate {
                                    Text("estimate").scaledFont(.caption2).foregroundStyle(.readableSecondary)
                                }
                                Spacer()
                                Text(i == snapshot.currentSystem ? String(localized: "Here") : MapText.parsecs(snapshot.systems[i].distance))
                                    .foregroundStyle(.readableSecondary)
                            }
                            .padding(.horizontal, 8)
                            .frame(width: 240)
                            .frame(minHeight: PointerTarget.minimum)  // UI-PTR-013
                            .background(ui.highlightedSuggestion == i ? Color.accentColor.opacity(0.35) : .clear)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: snapshot.systems[i].name))
                        .accessibilityValue(Text(verbatim: MapAccessibility.value(for: i, snapshot: snapshot)))
                        .accessibilityIdentifier(ids.searchResult(i))
                    }
                }
                .padding(.vertical, 4)
                .overlayBackground(cornerRadius: 8)  // A11Y-019
            }
        }
        .padding(8)
        .overlayBackground(cornerRadius: 10)  // A11Y-019
    }

    private func title(_ f: SystemSearchFilter) -> LocalizedStringResource {
        switch f {
        case .visited: "Visited"
        case .unvisited: "Unvisited"
        case .inRange: "In range"
        case .questHere: "Quest here"
        case .hasShipyard: "Has shipyard"
        case .wormhole: "Wormhole"
        }
    }

    /// MAP-073: centre, target and clear.
    private func choose(_ i: Int) {
        center(i)
        send(.selectTarget(i))
        ui.clearSearch()
    }

    /// Return: the highlighted suggestion, else `FindInput.parse` as the Find System sheet does.
    private func submit(_ suggestions: [Int]) {
        if let h = ui.highlightedSuggestion, suggestions.contains(h) { return choose(h) }
        guard let state = session.state else { return }
        let outcome = FindSystemModel.resolve(ui.searchText, track: false, state: state)
        switch outcome {
        case .noMatch:
            ui.searchMessage = String(localized: "No system found.")
        case let .select(system, _):
            choose(system)
        default:
            session.performFind(outcome)
            ui.clearSearch()
        }
    }
}

/// MAP-057 / MAP-069: the route objective buttons (Lowest Risk from M10, INT-027).
enum RouteObjectiveText {
    static func title(_ o: RouteObjective) -> LocalizedStringResource {
        switch o {
        case .fewestJumps: "Fewest Jumps"
        case .cheapest: "Cheapest"
        case .lowestRisk: "Lowest Risk"
        }
    }

    static func help(_ o: RouteObjective) -> LocalizedStringResource {
        switch o {
        case .fewestJumps: "Plan the route with the fewest jumps."
        case .cheapest: "Plan the cheapest route."
        case .lowestRisk: "Plan the route with the fewest pirates (and police, if you are wanted) on the way."
        }
    }
}
