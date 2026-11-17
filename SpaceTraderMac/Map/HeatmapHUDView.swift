// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import ParsecInsights
import SwiftUI

/// MAP-096: the heatmap control in the map HUD and its legend (numeric labels plus colour).
struct HeatmapHUDView: View {
    let ids: AXID.Map
    @Binding var choice: MapHeatmapChoice
    @Binding var item: TradeItemType
    let result: HeatmapResult?

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 6) {
                Picker(selection: $choice) {
                    ForEach(MapHeatmapChoice.allCases, id: \.self) { c in
                        Text(c.title).tag(c)
                    }
                } label: {
                    Text("Heatmap")
                }
                .pickerStyle(.menu)
                .fixedSize()
                .help(Text("Tint the map by known prices, profit, police, pirates, tech level or last visit."))
                .accessibilityIdentifier(ids.heatmap)
                if choice == .price {
                    Picker(selection: $item) {
                        ForEach(TradeItemType.allCases, id: \.self) { i in
                            Text(Names.item(i)).tag(i)
                        }
                    } label: {
                        Text("Commodity")
                    }
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier(ids.heatmapCommodity)
                }
            }
            if let result, choice != .none {
                HStack(spacing: 6) {
                    LinearGradient(colors: [HeatmapTint.color(0), HeatmapTint.color(0.5), HeatmapTint.color(1)],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: 80, height: 8)
                        .clipShape(.capsule)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(HeatmapTint.legend(result), id: \.self) { Text(verbatim: $0).font(.caption2) }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(6)
        .glassEffect(in: .rect(cornerRadius: 10))
    }
}
