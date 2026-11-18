// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// ART-053: the app icon from code: "a brass-rimmed parsec ring around a cargo-hauler silhouette on deep indigo".
/// Three transparent layers on a 1024 × 1024 canvas plus a background fill.
public enum AppIconArt {
    public enum Layer: String, CaseIterable, Sendable {
        case stars, ring, hauler

        /// Icon Composer glass flag (ART-055).
        public var glass: Bool { self != .stars }
    }

    public static let canvas = 1024.0

    /// The background fill (top and bottom of the indigo gradient) for a scheme.
    public static func fill(scheme: ColorScheme) -> (top: ArtRGB, bottom: ArtRGB) {
        let top = ArtPalette.rgb(.spaceTop, scheme: .light), bottom = ArtPalette.rgb(.spaceBottom, scheme: .light)
        return scheme == .dark ? (top.shade(0.55), bottom.shade(0.4)) : (top, bottom)
    }

    /// The sparkles: centre (design space), radius, brass or white.
    static let sparkles: [(x: Double, y: Double, r: Double, brass: Bool)] = [
        (250, 230, 30, true), (790, 760, 24, false), (220, 760, 18, false), (830, 300, 14, true), (520, 140, 12, false),
        (150, 470, 10, true), (880, 520, 11, false), (610, 880, 13, true),
    ]

    /// The ring geometry in design space.
    static let ringCenter = CGPoint(x: 512, y: 512)
    static let ringRadius = 330.0
    static let ringWidth = 64.0
    /// The gap at the upper right (screen angles, y down).
    static let gapStart = -62.0, gapEnd = -28.0

    /// The ring arc (from the gap end round to the gap start) as a filled band.
    static func ringBand(scale s: Double) -> Path {
        var arc = Path()
        arc.addArc(center: CGPoint(x: ringCenter.x * s, y: ringCenter.y * s), radius: ringRadius * s, startAngle: .degrees(gapEnd),
                   endAngle: .degrees(gapStart + 360), clockwise: false)
        return arc.strokedPath(StrokeStyle(lineWidth: ringWidth * s, lineCap: .round))
    }

    static func ticks(scale s: Double) -> Path {
        var p = Path()
        for i in 0..<12 {
            let a = Double(i) * 30 * .pi / 180
            let deg = Double(i) * 30
            if deg > 360 + gapStart - 4 || deg < 0 { continue }
            let inner = ArtGeometry.polar(CGPoint(x: ringCenter.x * s, y: ringCenter.y * s), (ringRadius - ringWidth * 0.32) * s, a)
            let outer = ArtGeometry.polar(CGPoint(x: ringCenter.x * s, y: ringCenter.y * s), (ringRadius + ringWidth * 0.32) * s, a)
            p.move(to: inner)
            p.addLine(to: outer)
        }
        return p.strokedPath(StrokeStyle(lineWidth: 9 * s, lineCap: .round))
    }

    /// The generated freighter as one solid path, heading up-right at 35°, in design space scaled by `s`. The detailed
    /// version cuts the bridge window and the gaps between the container rows out of the silhouette and adds the engine
    /// nozzles, so it reads as a cargo ship.
    static func hauler(scale s: Double, simplified: Bool = false) -> Path {
        // ART-053: the generated freighter (an ART-010 hauler).
        let bp = ShipHullGenerator.make(ShipArtStats.standard(.beetle), variant: ArtSeed.kind(.beetle))
        let g = ShipGeometry.make(bp)
        var shape = g.silhouette
        if !simplified {
            let c = bp.cockpit
            shape = shape.subtracting(Path(roundedRect: CGRect(x: c.x - c.length, y: 0.5 - c.width / 2, width: c.length, height: c.width),
                                           cornerRadius: c.length * 0.3))
            let len = bp.noseX - bp.tailX
            for k in 1...3 {
                let x = bp.tailX + len * (0.08 + 0.185 * Double(k))
                shape = shape.subtracting(Path(CGRect(x: x - 0.011, y: 0, width: 0.022, height: 1)))
            }
            // A keel girder keeps the container rows one ship.
            shape = shape.union(Path(CGRect(x: bp.tailX + len * 0.1, y: 0.5 - 0.03, width: len * 0.72, height: 0.06)).intersection(g.silhouette))
            for e in bp.engines {
                for side in [-1.0, 1.0] {
                    let y = 0.5 + side * e.yOffset
                    shape = shape.union(ArtGeometry.capsule(from: CGPoint(x: e.x - 0.06, y: y), to: CGPoint(x: e.x + 0.02, y: y), radius: e.radius))
                }
            }
        }
        let b = shape.boundingRect
        let k = 470.0 * s / b.width
        let t = CGAffineTransform(translationX: -b.midX, y: -b.midY)
            .concatenating(CGAffineTransform(scaleX: k, y: k))
            .concatenating(CGAffineTransform(rotationAngle: -35 * .pi / 180))
            .concatenating(CGAffineTransform(translationX: 512 * s, y: 512 * s))
        return shape.applying(t)
    }
}

/// ART-053: one icon layer, transparent outside its shapes.
public struct AppIconLayerView: View {
    public var layer: AppIconArt.Layer
    public var simplified: Bool

    public init(_ layer: AppIconArt.Layer, simplified: Bool = false) {
        self.layer = layer
        self.simplified = simplified
    }

    public var body: some View {
        let layer = layer, simplified = simplified
        Canvas { ctx, size in
            AppIconRenderer.draw(layer, in: &ctx, side: min(size.width, size.height), simplified: simplified)
        }
        .accessibilityHidden(true)
    }
}

/// ART-055: the full-bleed composite (fill plus layers, opaque corners, no mask); simplified at ≤ 32 px.
public struct AppIconComposite: View {
    public var simplified: Bool
    @Environment(\.colorScheme) private var scheme

    public init(simplified: Bool = false) {
        self.simplified = simplified
    }

    public var body: some View {
        let simplified = simplified, fill = AppIconArt.fill(scheme: scheme)
        Canvas { ctx, size in
            let side = min(size.width, size.height)
            ctx.fill(Path(CGRect(x: 0, y: 0, width: side, height: side)),
                     with: .linearGradient(Gradient(colors: [fill.top.color, fill.bottom.color]), startPoint: .zero,
                                           endPoint: CGPoint(x: 0, y: side)))
            for layer in AppIconArt.Layer.allCases where !(simplified && layer == .stars) {
                AppIconRenderer.draw(layer, in: &ctx, side: side, simplified: simplified)
            }
        }
        .accessibilityHidden(true)
    }
}

enum AppIconRenderer {
    static func draw(_ layer: AppIconArt.Layer, in ctx: inout GraphicsContext, side: Double, simplified: Bool) {
        let s = side / AppIconArt.canvas
        let brass = ArtPalette.rgb(.brass, scheme: .light)
        switch layer {
        case .stars:
            for sp in AppIconArt.sparkles {
                let c = CGPoint(x: sp.x * s, y: sp.y * s)
                let tint = sp.brass ? brass : ArtRGB(1, 1, 1)
                ctx.fill(ArtGeometry.star(center: c, points: 4, outer: sp.r * s, inner: sp.r * 0.22 * s), with: .color(tint.color))
            }
        case .ring:
            let band = AppIconArt.ringBand(scale: s)
            ctx.fill(band, with: .linearGradient(Gradient(colors: [brass.shade(1.3).color, brass.color, brass.shade(0.7).color]),
                                                 startPoint: CGPoint(x: 150 * s, y: 150 * s), endPoint: CGPoint(x: 880 * s, y: 880 * s)))
            if !simplified {
                ctx.fill(AppIconArt.ticks(scale: s), with: .color(brass.shade(0.45).color))
            }
        case .hauler:
            let path = AppIconArt.hauler(scale: s, simplified: simplified)
            let cream = ArtPalette.rgb(.cream, scheme: .light)
            ctx.fill(path, with: .linearGradient(Gradient(colors: [ArtRGB(1, 1, 1).color, cream.color]),
                                                 startPoint: CGPoint(x: 300 * s, y: 250 * s), endPoint: CGPoint(x: 720 * s, y: 780 * s)))
        }
    }
}
