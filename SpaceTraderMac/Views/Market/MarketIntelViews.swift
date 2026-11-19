// SPDX-License-Identifier: GPL-2.0-or-later
import Charts
import ParsecEngine
import ParsecInsights
import SwiftUI

/// INT-031: a Swift Charts sparkline of the remembered sell prices at this system.
struct PriceSparkline: View {
    let item: TradeItemType
    let series: [Int]

    var body: some View {
        Group {
            if series.count >= 2 {
                Chart(Array(series.enumerated()), id: \.offset) { point in
                    LineMark(x: .value("Visit", point.offset), y: .value("Price", point.element))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(width: 70, height: 20)
            } else {
                Text("No history").scaledFont(.caption2).foregroundStyle(.readableSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("History"))
        .accessibilityAddTraits(.isImage)
        .accessibilityValue(Text(verbatim: IntelText.historyValue(series)))
        .accessibilityIdentifier(AXID.MarketIntel.history(item))
    }
}

/// INT-033: a destination can be targeted under the same rule as Set Target.
enum RecommendationRules {
    static func canSelectTarget(_ system: Int, state: GameState, inputLocked: Bool) -> Bool {
        !inputLocked && state.phase == .docked && state.destinations.contains(system)
    }
}

/// INT-032: "Why this price?" for the selected row (an inline panel, never a popover).
struct PriceExplanationPanel: View {
    let item: TradeItemType?
    let explanation: PriceExplanation?
    @State private var showAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let item, let explanation, !explanation.steps.isEmpty {
                HStack {
                    Text("Why this price? \(Text(Names.item(item)))").scaledFont(.headline)
                    Spacer()
                    if explanation.steps.contains(where: \.isNeutral) {
                        Button(showAll ? "Hide unchanged" : "Show all") { showAll.toggle() }
                            .buttonStyle(.link)
                            .accessibilityIdentifier(AXID.MarketIntel.whyShowAll)
                    }
                }
                ForEach(PriceExplanationRows.visible(explanation, showAll: showAll), id: \.factor) { step in
                    HStack {
                        Text(verbatim: IntelText.factor(step.factor))
                        Spacer()
                        Text(verbatim: step.factor == .base ? step.valueAfter.formatted() : IntelText.signed(step.delta))
                            .monospacedDigit()
                            .foregroundStyle(.readableSecondary)
                        Text(verbatim: step.valueAfter.formatted()).monospacedDigit().frame(width: 60, alignment: .trailing)
                    }
                    .scaledFont(.callout)
                }
            } else {
                Text("Select a commodity to see how its price is made").foregroundStyle(.readableSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.MarketIntel.why)
    }
}

/// INT-032: neutral steps (delta 0) are collapsed behind "Show all"; the base step is always shown.
enum PriceExplanationRows {
    static func visible(_ e: PriceExplanation, showAll: Bool) -> [PriceExplanationStep] {
        showAll ? e.steps : e.steps.filter { $0.factor == .base || !$0.isNeutral }
    }
}
