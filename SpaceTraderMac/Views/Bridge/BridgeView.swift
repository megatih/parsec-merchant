// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// The Bridge (⌘1, PRD §4.2): System Information, Cargo, the Short-Range Chart and the Target System on one fixed
/// page. Nothing scrolls, nothing collapses, and the same elements are present at every window size.
struct BridgeView: View {
    @Environment(GameSession.self) private var session
    @Environment(\.pmScale) private var scale

    var body: some View {
        if let state = session.state, let cargo = session.bridgeCargo {
            GeometryReader { geo in
                let layout = BridgeLayout.make(size: geo.size, scale: scale)
                ZStack(alignment: .topLeading) {
                    place(BridgeSystemPanel(state: state), layout.system)
                    place(BridgeCargoPanel(model: cargo, rowHeight: layout.rowHeight), layout.cargo)
                    place(BridgeChartPanel(), layout.chart)
                    place(BridgeTargetPanel(model: .make(state: state, isModal: session.isInputLocked)), layout.target)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
            .accessibilityElement(children: .contain)
            .probed(BridgeID.root)
        }
    }

    private func place(_ view: some View, _ frame: CGRect) -> some View {
        view.frame(width: frame.width, height: frame.height).offset(x: frame.minX, y: frame.minY)
    }
}
