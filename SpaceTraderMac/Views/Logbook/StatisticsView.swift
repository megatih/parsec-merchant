// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import Charts
import ParsecEngine
import ParsecInsights
import SwiftUI

/// STAT-017 / STAT-018 / STAT-019: tiles, net worth over days, profit by commodity and kills by ship type.
struct StatisticsView: View {
    @Environment(GameSession.self) private var session

    var body: some View {
        Group {
            if let stats = session.careerStats {
                content(StatisticsModel.make(stats: stats))
                    .onCopyCommand { [NSItemProvider(object: StatisticsModel.copyText(stats: stats) as NSString)] }
            } else {
                // STAT-003: the statistics are rebuilt off the main actor after a load.
                ProgressView("Calculating statistics…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Logbook.stats)
    }

    private func content(_ m: StatisticsModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(verbatim: m.sinceText).scaledFont(.headline)
                    Spacer()
                    if let notice = m.cheatNotice {
                        Label { Text(verbatim: notice) } icon: { Image(systemName: "exclamationmark.triangle") }
                            .foregroundStyle(.signalOrange)
                    }
                }
                AccessibleLazyVGrid(label: "Figures", columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                    ForEach(m.tiles) { tile in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: tile.label).scaledFont(.caption).foregroundStyle(.readableSecondary)
                            Text(verbatim: tile.value).scaledFont(.title3, weight: .semibold).monospacedDigit()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier(AXID.Logbook.figure(tile.kind))
                    }
                }
                chartBox("Net worth", id: AXID.Logbook.worthChart, empty: m.worth.count < 2) {
                    Chart(m.worth, id: \.day) { s in
                        LineMark(x: .value("Day", s.day), y: .value("Worth", s.worth))
                    }
                }
                chartBox("Profit by commodity", id: AXID.Logbook.profitChart, empty: m.profitBars.isEmpty) {
                    Chart(m.profitBars) { bar in
                        BarMark(x: .value("Profit", bar.value), y: .value("Commodity", bar.label))
                            .foregroundStyle(bar.value >= 0 ? Color.signalGreen : Color.signalRed)
                            .annotation(position: bar.value >= 0 ? .trailing : .leading) {
                                Text(verbatim: "\(bar.signText)\(abs(bar.value).formatted())").scaledFont(.caption2)
                            }
                    }
                }
                chartBox("Kills by ship type", id: AXID.Logbook.killsChart, empty: m.killBars.isEmpty) {
                    Chart(m.killBars) { bar in
                        BarMark(x: .value("Kills", bar.value), y: .value("Ship", bar.label))
                    }
                }
            }
            .padding(16)
        }
    }

    private func chartBox(_ title: LocalizedStringResource, id: String, empty: Bool,
                          @ViewBuilder chart: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).scaledFont(.headline)
            if empty {
                Text("No data yet").foregroundStyle(.readableSecondary).frame(maxWidth: .infinity, minHeight: 80)
            } else {
                chart().frame(height: 180)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
    }
}
