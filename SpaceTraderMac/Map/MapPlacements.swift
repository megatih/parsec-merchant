// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import ParsecInsights
import SwiftUI

/// Galactic Chart (⌘8, MAP-075, PRD §4.11): the page frame with Find… and the chart with its Selected System panel.
struct GalaxySectionView: View {
    @Environment(GameSession.self) private var session
    @Environment(\.pmScale) private var scale

    var body: some View {
        GamePage(section: .galaxy) {
            PMButton(title: "Find…", systemImage: "magnifyingglass", key: "⌘F", help: "Find a system by name",
                     disabledReason: session.isInputLocked ? String(localized: ReasonText.text(for: .pendingDecisionFirst)) : nil,
                     identifier: AXID.Galaxy.find) {
                session.showFindSystem()
            }
            .fixedSize()
        } content: {
            VStack(spacing: PMSpace.xs * scale) {
                InlineTipView(tip: GalaxyTip(), id: .galaxy, margin: 6)  // A11Y-043, MAP-098
                GalaxyMapView(scope: .galaxy)
            }
        }
    }
}

/// Measures of the Galactic Chart's layout, in design points.
nonisolated enum ChartMetrics {
    static let selectionWidth: CGFloat = 300
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
                    .pmFont(.title)
                    .foregroundStyle(PMColor.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier(AXID.Galaxy.windowPlaceholder)
            }
        }
        .frame(minWidth: GalaxyWindowMetrics.minimumSize.width, minHeight: GalaxyWindowMetrics.minimumSize.height)
        // UI-NAV-008: the same console as the page, in both appearances.
        .environment(\.colorScheme, .dark)
        .background(PMColor.space)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Galaxy.windowRoot)
        .navigationTitle(Text("Galactic Chart"))
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
