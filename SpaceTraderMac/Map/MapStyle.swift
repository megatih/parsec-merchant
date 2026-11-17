// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import ParsecEngine
import ParsecInsights
import SwiftUI

/// Glyph sizes for a zoom level (MAP-028, MAP-020, MAP-037).
nonisolated struct GlyphMetrics: Sendable, Equatable, Hashable {
    var zoom: Double

    /// `min(max(√zoom, 1), 2)`.
    var multiplier: Double { min(max(zoom.squareRoot(), 1), 2) }

    func radius(_ size: SystemSize) -> Double {
        let base: Double = switch size {
        case .tiny: 2.5
        case .small: 3
        case .medium: 3.5
        case .large: 4
        case .huge, .gargantuan: 4.5
        }
        return base * multiplier
    }

    var wormholeRadius: Double { 3.5 * multiplier }

    /// MAP-020 hit radii.
    func systemHitRadius(_ size: SystemSize) -> Double { max(radius(size) + 4, 8) }
    var wormholeHitRadius: Double { max(wormholeRadius + 3, 6) }

    /// MAP-037: the vortex sits `glyphRadius + 6` pt to the right of its system.
    func wormholeOffset(_ size: SystemSize) -> Double { radius(size) + 6 }
}

/// A marker drawn around a glyph; each is a shape, not only a colour (MAP-029).
nonisolated enum GlyphMarker: String, Sendable, Hashable, CaseIterable {
    case current, target, tracked, quest
}

/// How one system glyph looks (MAP-028…030).
nonisolated struct GlyphStyle: Sendable, Equatable {
    /// Visited: filled disc; unvisited: stroked ring with a dark centre.
    var filled: Bool
    var radius: Double
    var opacity: Double
    /// Differentiate Without Color: a dotted halo on in-range systems.
    var halo: Bool
    var markers: Set<GlyphMarker>
}

nonisolated enum MapGlyphStyle {
    static let outOfRangeOpacity = 0.55

    /// MAP-028…030: pure; pairs colour with shape.
    static func style(for system: MapSystem, in snapshot: MapSnapshot, differentiateWithoutColor: Bool,
                      zoom: Double = 1) -> GlyphStyle {
        let isCurrent = system.index == snapshot.currentSystem
        var markers: Set<GlyphMarker> = []
        if isCurrent { markers.insert(.current) }
        if snapshot.hasTarget, system.index == snapshot.warpSystem { markers.insert(.target) }
        if snapshot.trackedSystem == system.index { markers.insert(.tracked) }
        if system.isQuestLocation { markers.insert(.quest) }
        let outOfRange = !system.inRange && !isCurrent
        return GlyphStyle(filled: system.visited, radius: GlyphMetrics(zoom: zoom).radius(system.size),
                          opacity: outOfRange ? outOfRangeOpacity : 1, halo: differentiateWithoutColor && system.inRange,
                          markers: markers)
    }
}

/// The map palette (UX-VISION §7): named colours with light and dark variants, drawn in code.
struct MapStyle {
    /// A11Y-018 / MAP-087: stroke widths are doubled under Increase Contrast.
    var strokeScale = 1.0
    var differentiateWithoutColor = false

    static let standard = MapStyle()

    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    static func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    /// `MapSpace`: indigo to near-black.
    static let spaceTop = dynamic(light: rgb(0.16, 0.17, 0.36), dark: rgb(0.09, 0.08, 0.22))
    static let spaceBottom = dynamic(light: rgb(0.05, 0.06, 0.14), dark: rgb(0.01, 0.01, 0.04))
    /// `MapVisited`: cyan-blue.
    static let visited = dynamic(light: rgb(0.35, 0.75, 1.0), dark: rgb(0.40, 0.80, 1.0))
    /// `MapUnvisited`: green.
    static let unvisited = dynamic(light: rgb(0.35, 0.90, 0.45), dark: rgb(0.40, 0.95, 0.50))
    static let glyphCenter = Color(nsColor: rgb(0.03, 0.04, 0.10))
    /// Brass accent for the current-system ring.
    static let brass = Color(nsColor: rgb(0.86, 0.70, 0.35))
    static let target = Color.white
    /// Crimson for tracking.
    static let tracked = Color(nsColor: rgb(0.90, 0.20, 0.30))
    static let quest = Color(nsColor: rgb(1.0, 0.85, 0.30))
    /// `MapWormhole`: amber to magenta.
    static let wormholeA = Color(nsColor: rgb(1.0, 0.70, 0.20))
    static let wormholeB = Color(nsColor: rgb(0.90, 0.30, 0.85))
    /// `MapRange`.
    static let range = Color(nsColor: rgb(0.45, 0.75, 1.0))
    /// `MapRoute`.
    static let route = Color(nsColor: rgb(1.0, 0.62, 0.20))
    static let label = Color.white.opacity(0.92)
    static let caption = Color.white.opacity(0.65)
    static let highlight = Color.white
}
