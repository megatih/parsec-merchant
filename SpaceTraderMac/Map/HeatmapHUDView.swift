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
                Text("Heatmap").pmFont(.body).foregroundStyle(PMColor.textPrimary).accessibilityHidden(true)
                // A11Y-029: AppKit pop-ups (a SwiftUI menu-style Picker here has no press action for VoiceOver).
                PopUpMenuButton(title: "", items: MapHeatmapChoice.allCases.map { c in
                    PopUpMenuButton.Item(title: String(localized: c.title)) { choice = c }
                }, pullsDown: false, selectedIndex: MapHeatmapChoice.allCases.firstIndex(of: choice),
                accessibilityLabel: String(localized: "Heatmap"), identifier: ids.heatmap,
                help: String(localized: "Tint the map by known prices, profit, police, pirates, tech level or last visit."))
                if choice == .price {
                    PopUpMenuButton(title: "", items: TradeItemType.allCases.map { i in
                        PopUpMenuButton.Item(title: String(localized: Names.item(i))) { item = i }
                    }, pullsDown: false, selectedIndex: TradeItemType.allCases.firstIndex(of: item),
                    accessibilityLabel: String(localized: "Heatmap commodity"), identifier: ids.heatmapCommodity)
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
                        ForEach(HeatmapTint.legend(result), id: \.self) { Text(verbatim: $0).pmFont(.caption).foregroundStyle(PMColor.textPrimary) }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(PMSpace.s)
        // UI-DS-024: a solid panel fill; the game area uses no glass.
        .background(PMColor.panel, in: RoundedRectangle(cornerRadius: PMRadius.panel))
        .overlay { RoundedRectangle(cornerRadius: PMRadius.panel).strokeBorder(PMColor.hairline) }
    }
}
