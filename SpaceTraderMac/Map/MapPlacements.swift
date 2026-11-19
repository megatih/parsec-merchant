// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecInsights
import SwiftUI

/// Galaxy (⌘7, MAP-075): the map filling the detail area.
struct GalaxySectionView: View {
    var body: some View {
        VStack(spacing: 0) {
            InlineTipView(tip: GalaxyTip(), id: .galaxy, margin: 12)  // A11Y-043, MAP-098
            GalaxyMapView(scope: .galaxy)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.SectionRoot.root(.galaxy))
    }
}

/// The Galaxy Chart window's content (MAP-076).
struct GalaxyChartWindowView: View {
    @Environment(GameSession.self) private var session
    @Environment(\.controlActiveState) private var controlActiveState
    @SceneStorage("galaxyWindow.zoom") private var storedZoom = 1.0
    @SceneStorage("galaxyWindow.centerX") private var storedX = -1.0
    @SceneStorage("galaxyWindow.centerY") private var storedY = -1.0
    @SceneStorage("galaxyWindow.resetSerial") private var storedReset = 0

    var body: some View {
        Group {
            if session.state != nil {
                GalaxyMapView(scope: .galaxyWindow)
            } else {
                Text("No game loaded")
                    .scaledFont(.title3)
                    .foregroundStyle(.readableSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier(AXID.Galaxy.windowPlaceholder)
            }
        }
        .frame(minWidth: GalaxyWindowMetrics.minimumSize.width, minHeight: GalaxyWindowMetrics.minimumSize.height)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Galaxy.windowRoot)
        .navigationTitle(Text("Galaxy Chart"))
        .onAppear {
            session.map.galaxyWindowOpen = true
            restoreViewport()
        }
        .onDisappear {
            session.map.galaxyWindowOpen = false
            session.map.galaxyWindowIsKey = false
        }
        .onChange(of: controlActiveState, initial: true) { _, state in
            session.map.galaxyWindowIsKey = state == .key
        }
        .onChange(of: session.map.viewports[.galaxyWindow]) { _, v in
            guard let v else { return }
            storedZoom = v.zoom
            storedX = v.center.x
            storedY = v.center.y
        }
        .onChange(of: session.map.resetSerial) { _, serial in storedReset = serial }
    }

    /// MAP-018: zoom and centre come back from `@SceneStorage` (unless a new game, load or close reset them).
    private func restoreViewport() {
        guard storedReset == session.map.resetSerial, storedX >= 0, storedY >= 0, session.map.viewports[.galaxyWindow] == nil
        else { return }
        session.map.viewports[.galaxyWindow] = MapViewport(zoom: storedZoom, center: CGPoint(x: storedX, y: storedY))
    }
}

enum GalaxyWindowMetrics {
    static let id = "galaxy"
    static let defaultSize = CGSize(width: 1000, height: 720)
    static let minimumSize = CGSize(width: 640, height: 480)
}
