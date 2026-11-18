// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// ART-040: items that have no ship or planet of their own.
public enum VignetteObject: String, CaseIterable, Sendable, Hashable {
    case artifact, reactor, jewels, antidote, japoriMedicine, moonDeed, tonicBottle, gemulonFleet, experimentRip
}

/// ART-040: what a narrative sheet illustrates.
public enum VignetteKind: Sendable, Hashable {
    case planet(PlanetArtInput)
    case ship(ShipArtInput)
    case object(VignetteObject)
}

/// ART-040: a small composed scene for a narrative sheet.
public struct Vignette: View {
    public var kind: VignetteKind
    public var seed: UInt64

    public init(kind: VignetteKind, seed: UInt64 = 7) {
        self.kind = kind
        self.seed = seed
    }

    public var body: some View {
        ZStack {
            SpaceBackground(seed: seed)
            switch kind {
            case let .planet(input): PlanetArt(input).padding(6)
            case let .ship(input): ShipArt(input, scaleMode: .fit).padding(10)
            case let .object(object): VignetteObjectArt(object: object)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityHidden(true)
    }
}

struct VignetteObjectArt: View {
    var object: VignetteObject
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let object = object, ink = ArtInk(scheme: scheme, contrast: false)
        Canvas { ctx, size in
            let side = min(size.width, size.height)
            let t = CGAffineTransform(a: side, b: 0, c: 0, d: side, tx: (size.width - side) / 2, ty: (size.height - side) / 2)
            VignetteObjectArt.draw(&ctx, object, t: t, ink: ink)
        }
    }

    static func draw(_ ctx: inout GraphicsContext, _ object: VignetteObject, t: CGAffineTransform, ink: ArtInk) {
        typealias GK = GlyphKit
        func fill(_ p: Path, _ c: ArtRGB) { ctx.fill(p.applying(t), with: .color(c.color)) }
        func glow(_ x: Double, _ y: Double, _ r: Double, _ c: ArtRGB) {
            let center = CGPoint(x: x, y: y).applying(t), rr = r * t.a
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - rr, y: center.y - rr, width: 2 * rr, height: 2 * rr)),
                     with: .radialGradient(Gradient(colors: [c.color, c.opacity(0).color]), center: center, startRadius: 0, endRadius: rr))
        }
        switch object {
        case .artifact:
            glow(0.5, 0.5, 0.34, ink.rgb(.alienGlow).opacity(0.6))
            fill(GK.poly([(0.5, 0.18), (0.72, 0.5), (0.5, 0.82), (0.28, 0.5)]), ink.rgb(.teal))
            fill(GK.poly([(0.5, 0.28), (0.62, 0.5), (0.5, 0.72), (0.38, 0.5)]), ink.rgb(.alienGlow))
        case .reactor:
            glow(0.5, 0.5, 0.36, ink.rgb(.yellowGreen).opacity(0.7))
            fill(GK.rect(0.32, 0.26, 0.36, 0.5, corner: 0.05), ink.rgb(.steel))
            fill(GK.rect(0.38, 0.34, 0.24, 0.34, corner: 0.04), ink.rgb(.yellowGreen))
            fill(ArtGeometry.star(center: CGPoint(x: 0.5, y: 0.51), points: 3, outer: 0.1, inner: 0.03), ink.rgb(.nightBlack))
        case .jewels:
            fill(GK.rect(0.3, 0.62, 0.4, 0.14, corner: 0.02), ink.rgb(.cream))
            fill(GK.poly([(0.36, 0.62), (0.4, 0.3), (0.5, 0.2), (0.6, 0.3), (0.64, 0.62)]), ink.rgb(.ivory).shade(0.9))
            for (x, y) in [(0.44, 0.36), (0.56, 0.36), (0.5, 0.48)] {
                fill(ArtGeometry.star(center: CGPoint(x: x, y: y), points: 4, outer: 0.05, inner: 0.02), ink.rgb(.danger))
            }
        case .antidote, .japoriMedicine:
            let tint = object == .antidote ? ink.rgb(.profit) : ink.rgb(.shieldEnergy)
            for k in 0..<3 {
                let x = 0.28 + Double(k) * 0.16
                fill(GK.rect(x, 0.34, 0.12, 0.38, corner: 0.04), ArtRGB(0.85, 0.92, 0.95, 0.9))
                fill(GK.rect(x, 0.5, 0.12, 0.22, corner: 0.04), tint)
                fill(GK.rect(x + 0.02, 0.28, 0.08, 0.07, corner: 0.02), ink.rgb(.slate))
            }
            if object == .japoriMedicine { fill(GK.union([GK.rect(0.47, 0.12, 0.06, 0.14), GK.rect(0.43, 0.16, 0.14, 0.06)]), ink.rgb(.danger)) }
        case .moonDeed:
            fill(GK.rect(0.22, 0.26, 0.56, 0.5, corner: 0.03), ink.rgb(.parchment))
            for k in 0..<4 { fill(GK.rect(0.3, 0.36 + Double(k) * 0.07, 0.4 - Double(k % 2) * 0.1, 0.025), ink.rgb(.landBrown)) }
            fill(GK.circle(0.64, 0.66, 0.06), ink.rgb(.danger))
            fill(GK.circle(0.78, 0.2, 0.08).subtracting(GK.circle(0.82, 0.18, 0.07)), ink.rgb(.ivory))
        case .tonicBottle:
            let bottle = ShipArtEmblem.path(.bottle)
            fill(GlyphKit.rotated(bottle, degrees: -70), ArtRGB(0.55, 0.85, 0.6, 0.8))
        case .gemulonFleet:
            for k in 0..<5 {
                let p = CGPoint(x: 0.2 + Double(k) * 0.14, y: 0.3 + Double(k % 2) * 0.3 + Double(k) * 0.02)
                let s = ShipArtEmblem.path(.mantis).applying(CGAffineTransform(a: 0.18, b: 0, c: 0, d: 0.18, tx: p.x - 0.09, ty: p.y - 0.09))
                fill(s, ink.rgb(.teal))
            }
        case .experimentRip:
            var rip = Path()
            rip.move(to: CGPoint(x: 0.5, y: 0.1))
            for k in 1...8 { rip.addLine(to: CGPoint(x: 0.5 + (k.isMultiple(of: 2) ? 0.07 : -0.07), y: 0.1 + Double(k) * 0.1)) }
            glow(0.5, 0.5, 0.3, ink.rgb(.wormholeB).opacity(0.6))
            ctx.stroke(rip.applying(t), with: .color(ink(.wormholeA)), lineWidth: max(2, t.a * 0.03))
        }
    }
}
