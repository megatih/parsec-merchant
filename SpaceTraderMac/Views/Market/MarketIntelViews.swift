// SPDX-License-Identifier: GPL-2.0-or-later
import Charts
import ParsecEngine
import ParsecInsights
import SwiftUI

/// INT-030: the Target column: the target's sell quote or "—", its age or "est.", dimmed when old, Δ vs the buy price
/// here with ▲/▼, and the profit per bay.
struct IntelTargetCell: View {
    let item: TradeItemType
    let quote: PriceQuote?
    let buyHere: Int?
    let profitPerBay: Int?

    var body: some View {
        Group {
            if let quote, let sell = quote.sell {
                HStack(spacing: 6) {
                    Text(verbatim: sell.formatted()).monospacedDigit()
                    Text(verbatim: IntelText.age(quote)).font(.caption2).foregroundStyle(.secondary)
                    if let buyHere {
                        let diff = sell - buyHere
                        Text(verbatim: "\(IntelText.arrow(diff)) \(IntelText.signed(diff))")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(diff > 0 ? Color.green : diff < 0 ? Color.red : Color.secondary)
                    }
                    if let profitPerBay {
                        Text("\(IntelText.signed(profitPerBay))/bay").font(.caption2).monospacedDigit()
                    }
                }
                .opacity(quote.staleness == .old ? 0.55 : 1)
                .help(IntelText.help(quote))
            } else {
                Text(verbatim: "—").foregroundStyle(.secondary).accessibilityLabel(Text("No target price"))
                    .help(quote.map(IntelText.help) ?? String(localized: "The target is this system."))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AXID.MarketIntel.target(item))
    }
}

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
                Text("No history").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("History"))
        .accessibilityValue(Text(verbatim: IntelText.historyValue(series)))
        .accessibilityIdentifier(AXID.MarketIntel.history(item))
    }
}

/// INT-033: the recommendations strip above the trade table.
struct RecommendationStripView: View {
    @Environment(GameSession.self) private var session
    let intel: MarketIntelModel
    let state: GameState
    let select: (TradeItemType) -> Void

    var body: some View {
        let targetName = Names.system(intel.target, in: state)
        VStack(alignment: .leading, spacing: 4) {
            if intel.bestBuys.isEmpty && intel.bestDestinations.isEmpty {
                Text("No profitable trade known").foregroundStyle(.secondary)
            }
            ForEach(Array(intel.bestBuys.enumerated()), id: \.offset) { n, r in
                Button {
                    select(r.item)
                } label: {
                    Label { Text(verbatim: IntelText.buyRecommendation(r, target: targetName)) } icon: { Image(systemName: "cart.badge.plus") }
                }
                .buttonStyle(.link)
                .accessibilityIdentifier(AXID.MarketIntel.recommendationBuy(n + 1))
            }
            ForEach(Array(intel.bestDestinations.enumerated()), id: \.offset) { n, d in
                let canTarget = RecommendationRules.canSelectTarget(d.system, state: state, inputLocked: session.isInputLocked)
                Button {
                    session.send(.selectTarget(d.system))
                } label: {
                    Label {
                        Text(verbatim: IntelText.destinationRecommendation(d, system: Names.system(d.system, in: state)))
                    } icon: {
                        Image(systemName: "scope")
                    }
                }
                .buttonStyle(.link)
                .disabled(!canTarget)
                .accessibilityIdentifier(AXID.MarketIntel.recommendationDestination(n + 1))
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.MarketIntel.recommendations)
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
                    Text("Why this price? \(Text(Names.item(item)))").font(.headline)
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
                            .foregroundStyle(.secondary)
                        Text(verbatim: step.valueAfter.formatted()).monospacedDigit().frame(width: 60, alignment: .trailing)
                    }
                    .font(.callout)
                }
            } else {
                Text("Select a commodity to see how its price is made").foregroundStyle(.secondary)
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
