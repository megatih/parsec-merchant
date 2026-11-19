// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import ParsecInsights
import SwiftUI

/// UI-PG-060: the Selected System panel of the Galactic Chart: the system's public facts, its ten average prices with
/// their tags, and Set as Target, Track, Plot Route and Use Wormhole. A click on the chart selects; only Set as
/// Target (or a double-click) changes the Target System. It replaces the pinned card and the Find Prices sheet of 1.x.
struct ChartSelectionPanel: View {
    @Environment(GameSession.self) private var session
    @Environment(\.pmScale) private var scale
    let ids: AXID.Map
    let snapshot: MapSnapshot
    /// The glyph selected on the chart; nil shows the Target System (or the current system when there is none).
    let hit: MapHit?
    let send: (Command) -> Void

    private var subject: MapHit { hit ?? .system(snapshot.hasTarget ? snapshot.warpSystem : snapshot.currentSystem) }

    var body: some View {
        PMPanel("Selected System", identifier: ids.selectionCard) {
            if let state = session.state, state.galaxy.systems.indices.contains(subject.systemIndex) {
                let index = subject.systemIndex
                let model = SystemCardModel.make(state: state, system: index)
                // The hero card where the panel is tall enough for it, the compact header otherwise.
                ViewThatFits(in: .vertical) {
                    VStack(alignment: .leading, spacing: PMSpace.s * scale) {
                        SystemHeroCard(model: model, planet: ArtAdapters.planetInput(system: index, state: state, showPressure: false))
                        details(index, state: state)
                    }
                    VStack(alignment: .leading, spacing: PMSpace.s * scale) {
                        compactHeader(model, state: state)
                        details(index, state: state)
                    }
                }
                .accessibilityElement(children: .contain)
            }
        }
    }

    private func compactHeader(_ model: SystemCardModel, state: GameState) -> some View {
        HStack(alignment: .top, spacing: PMSpace.s * scale) {
            PlanetHero(input: ArtAdapters.planetInput(system: model.index, state: state, showPressure: false))
                .frame(width: 72 * scale, height: 72 * scale)
                .clipShape(RoundedRectangle(cornerRadius: PMRadius.control * scale))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1 * scale) {
                Text(verbatim: model.name).pmFont(.title).foregroundStyle(PMColor.textPrimary).accessibilityAddTraits(.isHeader)
                Text("\(String(localized: Names.size(model.size))) · \(String(localized: SystemText.techLevel(model.techLevel)))")
                Text(SystemText.government(model.government))
                Text("Resources: \(String(localized: SystemText.resource(model.resource)))")
                Text("Police \(String(localized: SystemText.activity(model.police))) · Pirates \(String(localized: SystemText.activity(model.pirates)))")
            }
            .pmFont(.caption)
            .foregroundStyle(PMColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(ids.selectionFacts)
    }

    @ViewBuilder
    private func details(_ index: Int, state: GameState) -> some View {
        let here = index == snapshot.currentSystem
        Text(verbatim: here ? String(localized: "You are here") : MapText.parsecs(snapshot.systems[index].distance))
            .pmFont(.value)
            .foregroundStyle(PMColor.textPrimary)
        PMDivider()
        prices(index)
        PMDivider()
        buttons
    }

    /// The ten average prices (what the system pays), each with its tag: "est.", "today", "3 d ago" or "live".
    @ViewBuilder
    private func prices(_ index: Int) -> some View {
        if let inputs = session.intelInputs() {
            let model = SystemIntelModel.make(system: index, book: inputs.book, snapshot: inputs.snapshot)
            Text("Average prices").pmFont(.caption).foregroundStyle(PMColor.textSecondary)
                .help(Text("What this system pays for each good. Estimates carry no guarantee"))
            Grid(alignment: .leading, horizontalSpacing: PMSpace.s * scale, verticalSpacing: 1 * scale) {
                ForEach(0..<5, id: \.self) { n in
                    GridRow {
                        price(model.rows[n])
                        price(model.rows[n + 5])
                    }
                }
            }
        }
    }

    private func price(_ row: SystemIntelModel.Row) -> some View {
        HStack(spacing: PMSpace.xs * scale) {
            Text(Names.item(row.item)).foregroundStyle(PMColor.textSecondary)
            Spacer(minLength: 2 * scale)
            if let sell = row.quote.sell {
                // A11Y-029: the number at the value size (small digits measure as unreadable).
                Text(verbatim: sell.formatted()).pmFont(.value).foregroundStyle(PMColor.textPrimary)
                Text(verbatim: IntelText.age(row.quote)).foregroundStyle(PMColor.textSecondary)
            } else {
                Image(systemName: "minus").foregroundStyle(PMColor.textSecondary).accessibilityLabel(Text("Not traded there"))
            }
        }
        .pmFont(.caption)
        .help(IntelText.help(row.quote))
        // A11Y-029: a container, so the contrast audit measures each text in its own colour (the age says how old a price is).
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(Names.item(row.item)))
        .accessibilityIdentifier(AXID.SystemIntel.row(row.item))
    }

    /// The panel's buttons are the context menu's items (MAP-053): one rule for both.
    private var buttons: some View {
        let items = MapContextMenu.items(for: subject, snapshot: snapshot, isModal: session.isInputLocked)
        return VStack(alignment: .leading, spacing: PMSpace.xs * scale) {
            ForEach(items) { item in
                Button {
                    if let command = item.command { send(command) }
                    if item.kind == .plotRoute, let d = item.destination { session.planRoute(to: d) }
                } label: {
                    Text(verbatim: item.title)
                }
                .buttonStyle(PMButtonStyle(kind: item.kind == .setTarget ? .primary : .standard, fillsWidth: true))
                .disabled(!item.isEnabled)
                .help(item.reason.map { Text(verbatim: $0) } ?? Text(verbatim: item.title))
                .accessibilityIdentifier(ids.selection(item.kind))
            }
        }
    }
}

/// The filters of the Galactic Chart (MAP-072): which systems stay bright. The one search is the Find System sheet
/// (UI-PG-061).
struct MapFiltersView: View {
    @Environment(GameSession.self) private var session
    @Environment(\.pmScale) private var scale
    @Bindable var ui: MapViewModel
    let snapshot: MapSnapshot
    let ids: AXID.Map

    var body: some View {
        VStack(alignment: .leading, spacing: PMSpace.xs * scale) {
            Text("Filters").pmFont(.panelTitle).foregroundStyle(PMColor.textSecondary)
            ForEach(SystemSearchFilter.offered(snapshot), id: \.self) { f in
                Toggle(isOn: Binding { ui.filters.contains(f) } set: { on in
                    if on { ui.filters.insert(f) } else { ui.filters.remove(f) }
                }) {
                    Text(Self.title(f))
                }
                .toggleStyle(PMCheckToggleStyle())
                .help(Text("Dim every system that is not: \(String(localized: Self.title(f)))"))
                .accessibilityIdentifier(ids.searchFilter(f))
            }
            // INT-028: "sells <item>" from intel only (estimates are marked in the Selected System panel).
            // A11Y-029: an AppKit pull-down (SwiftUI's Menu has no press action for VoiceOver on macOS 27).
            PopUpMenuButton(title: ui.sellsItem.map { String(localized: "Sells \(String(localized: Names.item($0)))") } ?? String(localized: "Sells…"),
                            items: [PopUpMenuButton.Item(title: String(localized: "Any commodity"), isOn: ui.sellsItem == nil) { ui.sellsItem = nil }]
                                + TradeItemType.allCases.map { item in
                                    PopUpMenuButton.Item(title: String(localized: Names.item(item)), isOn: ui.sellsItem == item) { ui.sellsItem = item }
                                },
                            accessibilityLabel: String(localized: "Sells commodity"), identifier: ids.searchFilterSells, controlSize: .small)
        }
        .padding(PMSpace.s * scale)
        .background(PMColor.panel, in: RoundedRectangle(cornerRadius: PMRadius.panel * scale))
        .overlay { RoundedRectangle(cornerRadius: PMRadius.panel * scale).strokeBorder(PMColor.hairline) }
        .accessibilityElement(children: .contain)
    }

    static func title(_ f: SystemSearchFilter) -> LocalizedStringResource {
        switch f {
        case .visited: "Visited"
        case .unvisited: "Unvisited"
        case .inRange: "In range"
        case .questHere: "Quest here"
        case .hasShipyard: "Has shipyard"
        case .wormhole: "Wormhole"
        }
    }
}
