// SPDX-License-Identifier: GPL-2.0-or-later
import CoreGraphics
import Foundation
import ParsecEngine
import ParsecInsights

/// Jumps from the current system for the hover card (MAP-045, MAP-055).
enum HoverJumps: Equatable, Sendable {
    case computing
    case unreachable
    case count(Int)
}

/// The content of the hover card (MAP-045, MAP-046). Pure; reuses the engine's warp preview.
struct HoverCardModel: Equatable {
    var title: String
    var rows: [String]
    var tags: [String]

    /// MAP-045/046: a system glyph.
    static func make(system sys: MapSystem, snapshot s: MapSnapshot, preview: WarpTargetPreview, jumps: HoverJumps,
                     questTitles: [String] = [], intelRows: [String] = []) -> HoverCardModel {
        var rows: [String] = []
        rows.append(sys.visited ? String(localized: "Visited") : String(localized: "Not visited"))
        rows.append(String(localized: "\(String(localized: Names.size(sys.size))) · \(String(localized: SystemText.techLevel(sys.techLevel))) · \(String(localized: SystemText.government(sys.politics)))"))
        rows.append(String(localized: SystemText.resource(sys.knownResource)))
        rows.append(String(localized: "Police: \(String(localized: SystemText.activity(sys.police))) · Pirates: \(String(localized: SystemText.activity(sys.pirates)))"))
        if sys.index == s.currentSystem {
            rows.append(String(localized: "You are here"))
        } else {
            rows.append(MapText.parsecs(sys.distance))
            if preview.inRange {
                rows.append(String(localized: "In range · \(preview.fuelAfter) fuel left after the jump"))
            } else {
                rows.append(String(localized: "Out of range"))
            }
            if preview.viaWormhole {
                rows.append(String(localized: "Via wormhole · tax \(preview.costs.wormholeTax) cr."))
            }
            if preview.inRange {
                rows.append(String(localized: "Warp costs \(preview.costs.total) cr."))
            }
            switch jumps {
            case .computing: rows.append("…")
            case .unreachable: rows.append(String(localized: "Can't be reached with a full tank"))
            case let .count(n): rows.append(n == 1 ? String(localized: "1 jump") : String(localized: "\(n) jumps"))
            }
        }
        rows += intelRows
        var tags: [String] = []
        if s.hasTarget, sys.index == s.warpSystem { tags.append(String(localized: "Target")) }
        if s.trackedSystem == sys.index { tags.append(String(localized: "Tracked")) }
        tags += questTitles
        return HoverCardModel(title: sys.name, rows: rows, tags: tags)
    }

    /// MAP-046: a wormhole glyph beside system `w`.
    static func make(wormhole w: Int, snapshot s: MapSnapshot, tax: Int) -> HoverCardModel {
        guard let dest = s.systems[w].wormholeDestination else {
            return HoverCardModel(title: s.systems[w].name, rows: [], tags: [])
        }
        var rows = [String(localized: "(from \(s.systems[w].name) System)")]
        if w == s.currentSystem {
            rows.append(String(localized: "No fuel used · tax \(tax) cr."))
        } else {
            rows.append(String(localized: "Usable only from \(s.systems[w].name)"))
        }
        return HoverCardModel(title: String(localized: "Wormhole to \(s.systems[dest].name)"), rows: rows, tags: [])
    }
}

/// Places the hover card 12 pt from its glyph, flipped to stay inside the map (MAP-044).
nonisolated enum HoverCardPlacement {
    static let gap: Double = 12

    static func frame(anchor: CGPoint, cardSize: CGSize, bounds: CGRect) -> CGRect {
        var x = anchor.x + gap
        var y = anchor.y + gap
        if x + cardSize.width > bounds.maxX { x = anchor.x - gap - cardSize.width }
        if y + cardSize.height > bounds.maxY { y = anchor.y - gap - cardSize.height }
        x = min(max(x, bounds.minX), max(bounds.minX, bounds.maxX - cardSize.width))
        y = min(max(y, bounds.minY), max(bounds.minY, bounds.maxY - cardSize.height))
        return CGRect(x: x, y: y, width: cardSize.width, height: cardSize.height)
    }
}

/// Shared map strings.
enum MapText {
    /// The plural-aware "N parsecs".
    static func parsecs(_ n: Int) -> String {
        n == 1 ? String(localized: "1 parsec") : String(localized: "\(n) parsecs")
    }
}
