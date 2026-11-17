// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecInsights

/// Which placement of the one `GalaxyMapView` component this is (MAP Conventions "One component").
/// The scope supplies the identifier prefix so the section and the window never share an identifier.
nonisolated enum MapScope: String, CaseIterable, Sendable, Hashable {
    case galaxy, galaxyWindow, miniChart

    var prefix: String {
        switch self {
        case .galaxy: "galaxy"
        case .galaxyWindow: "galaxyWindow"
        case .miniChart: "bridge.miniChart"
        }
    }

    /// The mini chart has no HUD, zoom, pan or search (MAP-074).
    var hasHUD: Bool { self != .miniChart }
}
