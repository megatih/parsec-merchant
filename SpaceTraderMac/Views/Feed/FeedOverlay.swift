// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// UI-SHELL-044 / UI-ENC-065: the feed overlay (an overlay, never a popover): "Day N · <system>" groups, collapsed
/// combat rounds and category symbols. "Show Logbook" arrives with LOG in M10.
struct FeedOverlay: View {
    let groups: [FeedGroup]
    let state: GameState
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recent Events").font(.headline)
                Spacer()
                Button("Close", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier(AXID.Status.feedClose)
            }
            .padding(10)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(groups) { group in
                        Text("Day \(group.day) · \(Names.system(group.systemIndex, in: state))")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier(AXID.Feed.group(day: group.day, systemIndex: group.systemIndex))
                        ForEach(group.rows) { row in
                            switch row {
                            case let .item(item):
                                FeedRow(entry: item.entry, state: state)
                            case let .rounds(items, opponent):
                                RoundsRow(items: items, opponent: opponent, state: state)
                            }
                        }
                    }
                }
                .padding(10)
            }
        }
        .frame(width: 480, height: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Status.feedList)
    }
}

/// One feed line with its category symbol; warnings add a symbol, critical rows are bold with an exclamation symbol.
struct FeedRow: View {
    let entry: FeedItem.Entry
    let state: GameState

    var body: some View {
        let style = FeedStyle.classify(entry)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: style.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            if let badge = style.severity.badgeSymbol {
                Image(systemName: badge)
                    .foregroundStyle(style.severity == .critical ? .red : .orange)
                    .accessibilityLabel(style.severity == .critical ? Text("Critical") : Text("Warning"))
            }
            Text(verbatim: FeedText.text(for: entry, state: state))
                .fontWeight(style.severity == .critical ? .bold : .regular)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Consecutive combat rounds of one encounter: "N rounds against the <ship>", expandable (UI-ENC-065).
private struct RoundsRow: View {
    let items: [FeedItem]
    let opponent: ShipType?
    let state: GameState
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(items) { item in
                FeedRow(entry: item.entry, state: state)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: FeedCategory.combat.symbol).foregroundStyle(.secondary).frame(width: 16)
                if let opponent {
                    Text("\(items.count) rounds against the \(String(localized: Names.ship(opponent)))")
                } else {
                    Text("\(items.count) combat rounds")
                }
            }
        }
        .accessibilityIdentifier(AXID.Feed.rounds(items.first?.id ?? 0))
    }
}
