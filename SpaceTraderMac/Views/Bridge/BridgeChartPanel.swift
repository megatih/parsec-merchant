// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// Region C, the Short-Range Chart (UI-BRG-010…013): the one map component at its fixed zoom. A click on a system
/// makes it the Target System; the button opens the Galactic Chart page on it.
struct BridgeChartPanel: View {
    @Environment(GameSession.self) private var session
    @Environment(\.pmScale) private var scale

    var body: some View {
        BridgePanel(identifier: BridgeID.chart) {
            ZStack(alignment: .bottomTrailing) {
                GalaxyMapView(scope: .miniChart)
                    .clipShape(RoundedRectangle(cornerRadius: PMRadius.control * scale))
                PMButton(title: "Galactic Chart", systemImage: "arrow.up.right", help: "Open the Galactic Chart on the target system",
                         identifier: BridgeID.Chart.open) {
                    session.openGalacticChartAtTarget()
                }
                .fixedSize()
                .padding(PMSpace.xs * scale)
            }
            // A11Y-043: the two onboarding tips of the Bridge sit over the chart until they are dismissed.
            .overlay(alignment: .top) {
                VStack(spacing: PMSpace.xs * scale) {
                    InlineTipView(tip: MarketTip(), id: .market, margin: 6)
                    InlineTipView(tip: WarpTip(), id: .warp, margin: 6)
                }
                .padding(.top, (PMSpace.xl + PMSpace.xs) * scale)
            }
            .overlay(alignment: .topLeading) {
                BridgeTitle(title: "Short-Range Chart")
                    .padding(.horizontal, PMSpace.s * scale)
                    .padding(.vertical, PMSpace.xs * scale)
                    .background(PMColor.panel.opacity(0.85), in: RoundedRectangle(cornerRadius: PMRadius.control * scale))
                    .padding(PMSpace.xs * scale)
                    .allowsHitTesting(false)
            }
        }
    }
}
