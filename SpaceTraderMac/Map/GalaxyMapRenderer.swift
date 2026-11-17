// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import ParsecInsights
import SwiftUI

/// Drawing layers, back to front (MAP-023). `heatmap` is {M10}.
nonisolated enum MapLayer: Int, CaseIterable, Comparable, Sendable, Hashable {
    case background, heatmap, searchDimming, fullTankRing, rangeRing, wormholeLinks, route, trackedBearing, systems,
         wormholeGlyphs, markers, labels

    static func < (a: MapLayer, b: MapLayer) -> Bool { a.rawValue < b.rawValue }

    /// Every layer drawn in M8 (heatmap arrives in M10).
    static let m8: Set<MapLayer> = Set(allCases).subtracting([.heatmap])
    /// MAP-023 / MAP-096: every layer, including the heatmap.
    static let m10: Set<MapLayer> = Set(allCases)
}

/// Per-render options.
struct MapRenderOptions {
    var style = MapStyle.standard
    /// Systems dimmed to 40% by active search filters (MAP-073).
    var dimmed: Set<Int> = []
    /// The mini chart draws a bearing triangle instead of the bearing line (MAP-041).
    var miniChart = false
    /// MAP-096: the heatmap to tint (nil: none).
    var heatmap: HeatmapResult?

    static let dimmedOpacity = 0.4
}

/// The only drawing code of the map, shared by all three scopes (MAP-023).
enum GalaxyMapRenderer {
    /// Draws the enabled layers in `MapLayer.allCases` order.
    static func draw(in context: inout GraphicsContext, snapshot s: MapSnapshot, projected pm: ProjectedMap,
                     layers: Set<MapLayer>, options: MapRenderOptions = MapRenderOptions()) {
        for layer in MapLayer.allCases where layers.contains(layer) {
            draw(layer, in: &context, snapshot: s, projected: pm, layers: layers, options: options)
        }
    }

    private static func draw(_ layer: MapLayer, in ctx: inout GraphicsContext, snapshot s: MapSnapshot, projected pm: ProjectedMap,
                             layers: Set<MapLayer>, options: MapRenderOptions) {
        let size = CGSize(width: pm.key.width, height: pm.key.height)
        switch layer {
        case .background:
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: [MapStyle.spaceTop, MapStyle.spaceBottom]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        case .heatmap:
            if let heat = options.heatmap { drawHeatmap(&ctx, s, pm, heat) }
        case .searchDimming:
            break // applied while drawing the systems.
        case .fullTankRing:
            if let r = MapRange.fullTankRadius(s) {
                ring(&ctx, s, pm, radius: r, dashed: true, label: options.style.differentiateWithoutColor
                    ? String(localized: "Full tank \(s.fuelCapacity)") : nil)
            }
        case .rangeRing:
            let r = MapRange.ringRadius(s)
            if r > 0 {
                ring(&ctx, s, pm, radius: r, dashed: false, label: options.style.differentiateWithoutColor
                    ? String(localized: "Range \(s.fuel)") : nil)
            }
        case .wormholeLinks:
            drawLinks(&ctx, s, pm)
        case .route:
            drawRoute(&ctx, s, pm)
        case .trackedBearing:
            drawBearing(&ctx, s, pm, mini: options.miniChart)
        case .systems:
            let dim = layers.contains(.searchDimming) ? options.dimmed : []
            for i in pm.visible { drawGlyph(&ctx, s, pm, i, dimmed: dim.contains(i), dwc: options.style.differentiateWithoutColor) }
        case .wormholeGlyphs:
            for w in s.wormholes where pm.visible.contains(w) {
                drawVortex(&ctx, center: MapGeometry.wormholeGlyphCenter(w, snapshot: s, projection: pm.projection, metrics: pm.metrics),
                           radius: pm.metrics.wormholeRadius)
            }
        case .markers:
            drawMarkers(&ctx, s, pm, dwc: options.style.differentiateWithoutColor)
        case .labels:
            for label in pm.labels { drawLabel(&ctx, label) }
        }
    }

    // MARK: Heatmap (MAP-096)

    private static func drawHeatmap(_ ctx: inout GraphicsContext, _ s: MapSnapshot, _ pm: ProjectedMap, _ heat: HeatmapResult) {
        let strengths = HeatmapTint.strengths(heat)
        for i in pm.visible where strengths.indices.contains(i) {
            guard let t = strengths[i] else { continue }
            let c = pm.centers[i]
            let r = pm.metrics.radius(s.systems[i].size) * 3.2
            let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
            let color = HeatmapTint.color(t)
            ctx.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(colors: [color.opacity(0.55), color.opacity(0)]),
                                                                center: c, startRadius: 0, endRadius: r))
            if heat.values[i].note == .estimate {
                ctx.stroke(Path(ellipseIn: rect.insetBy(dx: r * 0.45, dy: r * 0.45)), with: .color(color.opacity(0.8)),
                           style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            }
        }
    }

    // MARK: Rings

    private static func ring(_ ctx: inout GraphicsContext, _ s: MapSnapshot, _ pm: ProjectedMap, radius: Double, dashed: Bool,
                             label: String?) {
        let c = pm.centers[s.currentSystem]
        let r = radius * pm.projection.scale
        let path = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        if dashed {
            ctx.stroke(path, with: .color(MapStyle.range.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        } else {
            ctx.fill(path, with: .color(MapStyle.range.opacity(0.10)))
            ctx.stroke(path, with: .color(MapStyle.range.opacity(0.85)), lineWidth: 1.5)
        }
        if let label {
            ctx.draw(Text(verbatim: label).font(.caption2).foregroundStyle(MapStyle.range), at: CGPoint(x: c.x, y: c.y - r - 2),
                     anchor: .bottom)
        }
    }

    // MARK: Wormholes

    private static func drawLinks(_ ctx: inout GraphicsContext, _ s: MapSnapshot, _ pm: ProjectedMap) {
        for link in MapGeometry.wormholeLinks(s) {
            let a = MapGeometry.linkArc(link, snapshot: s, projection: pm.projection, metrics: pm.metrics)
            let targeted = s.targetWormhole == link.origin && s.warpSystem == link.destination
            var path = Path()
            path.move(to: a.start)
            path.addQuadCurve(to: a.end, control: a.control)
            let style = targeted ? StrokeStyle(lineWidth: 2) : StrokeStyle(lineWidth: 1, dash: [4, 4])
            var g = ctx
            g.opacity = targeted ? 1 : 0.6
            g.stroke(path, with: .linearGradient(Gradient(colors: [MapStyle.wormholeA, MapStyle.wormholeB]),
                                                  startPoint: a.start, endPoint: a.end), style: style)
            arrowhead(&ctx, from: a.control, to: a.end, inset: pm.metrics.radius(s.systems[link.destination].size) + 2,
                      color: MapStyle.wormholeB.opacity(targeted ? 1 : 0.7))
        }
    }

    private static func arrowhead(_ ctx: inout GraphicsContext, from a: CGPoint, to b: CGPoint, inset: Double, color: Color) {
        let dx = b.x - a.x, dy = b.y - a.y
        let d = (dx * dx + dy * dy).squareRoot()
        guard d > 1e-6 else { return }
        let ux = dx / d, uy = dy / d
        let tip = CGPoint(x: b.x - ux * inset, y: b.y - uy * inset)
        var p = Path()
        p.move(to: tip)
        p.addLine(to: CGPoint(x: tip.x - ux * 7 - uy * 3.5, y: tip.y - uy * 7 + ux * 3.5))
        p.addLine(to: CGPoint(x: tip.x - ux * 7 + uy * 3.5, y: tip.y - uy * 7 - ux * 3.5))
        p.closeSubpath()
        ctx.fill(p, with: .color(color))
    }

    static func drawVortex(_ ctx: inout GraphicsContext, center c: CGPoint, radius r: Double) {
        for k in 0..<3 {
            var p = Path()
            let start = Angle.degrees(Double(k) * 120)
            p.addArc(center: c, radius: r * (0.45 + 0.25 * Double(k)), startAngle: start, endAngle: start + .degrees(200), clockwise: false)
            ctx.stroke(p, with: .linearGradient(Gradient(colors: [MapStyle.wormholeA, MapStyle.wormholeB]),
                                                 startPoint: CGPoint(x: c.x - r, y: c.y), endPoint: CGPoint(x: c.x + r, y: c.y)),
                       lineWidth: 1.3)
        }
    }

    // MARK: Route and bearing

    private static func drawRoute(_ ctx: inout GraphicsContext, _ s: MapSnapshot, _ pm: ProjectedMap) {
        let segments = MapGeometry.routeSegments(s, projection: pm.projection, metrics: pm.metrics)
        for seg in segments {
            var p = Path()
            p.move(to: seg.start)
            if let c = seg.control { p.addQuadCurve(to: seg.end, control: c) } else { p.addLine(to: seg.end) }
            ctx.stroke(p, with: .color(MapStyle.route.opacity(seg.isNext ? 1 : 0.75)),
                       style: StrokeStyle(lineWidth: seg.isNext ? 4 : 2.5, lineCap: .round))
        }
    }

    private static func drawBearing(_ ctx: inout GraphicsContext, _ s: MapSnapshot, _ pm: ProjectedMap, mini: Bool) {
        guard let (a, b) = MapGeometry.trackedBearing(s, projection: pm.projection) else { return }
        if mini {
            guard let tri = MapGeometry.bearingTriangle(from: a, toward: b) else { return }
            var p = Path()
            p.addLines(tri)
            p.closeSubpath()
            ctx.fill(p, with: .color(MapStyle.tracked))
        } else {
            var p = Path()
            p.move(to: a)
            p.addLine(to: b)
            ctx.stroke(p, with: .color(MapStyle.tracked.opacity(0.8)), style: StrokeStyle(lineWidth: 1.2, dash: [1.5, 4]))
        }
    }

    // MARK: Glyphs

    private static func drawGlyph(_ ctx: inout GraphicsContext, _ s: MapSnapshot, _ pm: ProjectedMap, _ i: Int, dimmed: Bool, dwc: Bool) {
        let sys = s.systems[i]
        let st = MapGlyphStyle.style(for: sys, in: s, differentiateWithoutColor: dwc, zoom: pm.metrics.zoom)
        let c = pm.centers[i], r = st.radius
        let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        var g = ctx
        g.opacity = st.opacity * (dimmed ? MapRenderOptions.dimmedOpacity : 1)
        if st.filled {
            g.fill(Path(ellipseIn: rect), with: .color(MapStyle.visited))
        } else {
            g.fill(Path(ellipseIn: rect), with: .color(MapStyle.glyphCenter))
            g.stroke(Path(ellipseIn: rect.insetBy(dx: 0.6, dy: 0.6)), with: .color(MapStyle.unvisited), lineWidth: 1.4)
        }
        if st.halo {
            g.stroke(Path(ellipseIn: rect.insetBy(dx: -2, dy: -2)), with: .color(.white.opacity(0.7)),
                     style: StrokeStyle(lineWidth: 0.8, dash: [1, 2]))
        }
    }

    private static func drawMarkers(_ ctx: inout GraphicsContext, _ s: MapSnapshot, _ pm: ProjectedMap, dwc: Bool) {
        let visible = Set(pm.visible)
        for i in pm.visible {
            let st = MapGlyphStyle.style(for: s.systems[i], in: s, differentiateWithoutColor: dwc, zoom: pm.metrics.zoom)
            let c = pm.centers[i], r = st.radius
            if st.markers.contains(.current) {
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r - 4, y: c.y - r - 4, width: 2 * r + 8, height: 2 * r + 8)),
                           with: .color(MapStyle.brass), lineWidth: 1.5)
            }
            if st.markers.contains(.target) { crosshair(&ctx, at: c, radius: r) }
            if st.markers.contains(.tracked) { pennant(&ctx, at: CGPoint(x: c.x + r * 0.7, y: c.y - r * 0.7)) }
            if st.markers.contains(.quest) { sparkle(&ctx, at: CGPoint(x: c.x - r - 3, y: c.y - r - 3)) }
        }
        if let w = s.targetWormhole, visible.contains(w) {
            crosshair(&ctx, at: MapGeometry.wormholeGlyphCenter(w, snapshot: s, projection: pm.projection, metrics: pm.metrics),
                      radius: pm.metrics.wormholeRadius)
        }
        for seg in MapGeometry.routeSegments(s, projection: pm.projection, metrics: pm.metrics) {
            hopBadge(&ctx, number: seg.hop, at: CGPoint(x: seg.end.x, y: seg.end.y + 12), emphasised: seg.isNext)
        }
    }

    private static func crosshair(_ ctx: inout GraphicsContext, at c: CGPoint, radius r: Double) {
        var p = Path()
        for (dx, dy) in [(1.0, 0.0), (-1, 0), (0, 1), (0, -1)] {
            p.move(to: CGPoint(x: c.x + dx * (r + 3), y: c.y + dy * (r + 3)))
            p.addLine(to: CGPoint(x: c.x + dx * (r + 8), y: c.y + dy * (r + 8)))
        }
        ctx.stroke(p, with: .color(MapStyle.target), lineWidth: 1.5)
    }

    private static func pennant(_ ctx: inout GraphicsContext, at base: CGPoint) {
        var pole = Path()
        pole.move(to: base)
        pole.addLine(to: CGPoint(x: base.x, y: base.y - 10))
        ctx.stroke(pole, with: .color(MapStyle.tracked), lineWidth: 1.2)
        var flag = Path()
        flag.move(to: CGPoint(x: base.x, y: base.y - 10))
        flag.addLine(to: CGPoint(x: base.x + 7, y: base.y - 7.5))
        flag.addLine(to: CGPoint(x: base.x, y: base.y - 5))
        flag.closeSubpath()
        ctx.fill(flag, with: .color(MapStyle.tracked))
    }

    private static func sparkle(_ ctx: inout GraphicsContext, at c: CGPoint) {
        var p = Path()
        let a = 4.0, b = 1.2
        p.move(to: CGPoint(x: c.x, y: c.y - a))
        p.addLine(to: CGPoint(x: c.x + b, y: c.y - b))
        p.addLine(to: CGPoint(x: c.x + a, y: c.y))
        p.addLine(to: CGPoint(x: c.x + b, y: c.y + b))
        p.addLine(to: CGPoint(x: c.x, y: c.y + a))
        p.addLine(to: CGPoint(x: c.x - b, y: c.y + b))
        p.addLine(to: CGPoint(x: c.x - a, y: c.y))
        p.addLine(to: CGPoint(x: c.x - b, y: c.y - b))
        p.closeSubpath()
        ctx.fill(p, with: .color(MapStyle.quest))
    }

    private static func hopBadge(_ ctx: inout GraphicsContext, number: Int, at c: CGPoint, emphasised: Bool) {
        let r = emphasised ? 7.0 : 6.0
        let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        ctx.fill(Path(ellipseIn: rect), with: .color(MapStyle.route))
        if emphasised { ctx.stroke(Path(ellipseIn: rect.insetBy(dx: -1.5, dy: -1.5)), with: .color(.white), lineWidth: 1) }
        ctx.draw(Text(verbatim: "\(number)").font(.system(size: 8, weight: .bold)).foregroundStyle(.black), at: c)
    }

    // MARK: Labels

    private static func drawLabel(_ ctx: inout GraphicsContext, _ label: MapLabel) {
        ctx.draw(Text(verbatim: label.name).font(.system(size: 10, weight: .medium)).foregroundStyle(MapStyle.label),
                 at: label.rect.origin, anchor: .topLeading)
        if let cap = label.caption {
            let text = Text("\(SystemText.techLevel(cap.techLevel)) · \(SystemText.government(cap.politics))")
            ctx.draw(text.font(.system(size: 9)).foregroundStyle(MapStyle.caption),
                     at: CGPoint(x: label.rect.minX, y: label.rect.minY + MapLabelPolicy.nameHeight), anchor: .topLeading)
        }
    }

    /// The hover highlight and Show on Map pulse, drawn in the light overlay canvas (MAP-089).
    static func drawHighlight(_ ctx: inout GraphicsContext, center c: CGPoint, radius r: Double, pulse: Double, name: String?) {
        let rr = r + 6 + 6 * pulse
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: 2 * rr, height: 2 * rr)),
                   with: .color(MapStyle.highlight.opacity(0.9 - 0.4 * pulse)), lineWidth: 2)
        if let name {
            ctx.draw(Text(verbatim: name).font(.system(size: 10, weight: .semibold)).foregroundStyle(MapStyle.label),
                     at: CGPoint(x: c.x + r + 4, y: c.y - MapLabelPolicy.nameHeight / 2), anchor: .topLeading)
        }
    }
}
