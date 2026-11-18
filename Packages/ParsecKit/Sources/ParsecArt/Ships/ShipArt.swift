// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// ART-014: how the silhouette is sized in its frame.
public enum ShipScaleMode: Sendable, Hashable {
    /// The silhouette fills the frame (ship grid, inspector, designer).
    case fit
    /// `0.5 + 0.1 × sizeClass` of the reference box fitted to the frame, around the frame centre (encounter panes, transit).
    case relative
}

/// Cached geometry and scorch order of one blueprint.
struct ShipArtModel: Sendable {
    var blueprint: ShipBlueprint
    var geometry: ShipGeometry
    var scorch: ShipScorch

    private struct Key: Hashable {
        var blueprint: ShipBlueprint
        var seed: UInt64
    }

    @MainActor
    static func make(_ input: ShipArtInput) -> ShipArtModel {
        let bp = input.blueprint
        let seed = ArtSeed.kind(input.kind)
        return ArtCache.shared.value(Key(blueprint: bp, seed: seed)) {
            let g = ShipGeometry.make(bp)
            return ShipArtModel(blueprint: bp, geometry: g, scorch: ShipScorch.make(g, seed: seed))
        }
    }
}

/// ART-014/015: unit space → view space.
public enum ShipArtLayout {
    /// Room left around the silhouette for the shield bubble (12% larger than the bounding box, plus the rim).
    public static let bubbleRoom = 1.16
    /// ART-014: the envelope of every generated hull in unit space; `.relative` sizes ships against it.
    public static let referenceBox = CGSize(width: 0.90, height: 0.56)

    public static func scale(bounds: CGRect, size: CGSize, mode: ShipScaleMode, sizeClass: Int) -> Double {
        switch mode {
        case .fit:
            guard bounds.width > 0, bounds.height > 0 else { return 1 }
            return min(size.width / (bounds.width * bubbleRoom), size.height / (bounds.height * bubbleRoom))
        case .relative:
            // ART-014: k(sizeClass) of the reference box fitted on both axes, never larger than the ship's own fit.
            let k = 0.5 + 0.1 * Double(min(5, max(0, sizeClass)))
            let reference = min(size.width / (referenceBox.width * bubbleRoom), size.height / (referenceBox.height * bubbleRoom))
            return min(k * reference, scale(bounds: bounds, size: size, mode: .fit, sizeClass: sizeClass))
        }
    }

    /// The transform drawing unit-space geometry into a frame of `size`, mirrored for `.left`.
    public static func transform(bounds: CGRect, size: CGSize, mode: ShipScaleMode, sizeClass: Int, facing: ShipFacing) -> CGAffineTransform {
        let s = scale(bounds: bounds, size: size, mode: mode, sizeClass: sizeClass)
        let fx: Double = facing == .left ? -1 : 1
        let cx = bounds.midX, cy = bounds.midY
        // x' = fx·s·(x − cx) + W/2, y' = s·(y − cy) + H/2
        return CGAffineTransform(a: fx * s, b: 0, c: 0, d: s, tx: size.width / 2 - fx * s * cx, ty: size.height / 2 - s * cy)
    }

    /// The silhouette's bounding box in view space (effects aim at it).
    @MainActor
    public static func frame(_ input: ShipArtInput, mode: ShipScaleMode, in size: CGSize) -> CGRect {
        let b = ShipArtModel.make(input).geometry.bounds
        return b.applying(transform(bounds: b, size: size, mode: mode, sizeClass: input.sizeClass, facing: input.facing))
    }
}

/// ART-008…019: a ship portrait with engine glow, shield bubble, scorch, disabled and cloaked overlays.
public struct ShipArt: View {
    public var input: ShipArtInput
    public var scaleMode: ShipScaleMode
    @Environment(\.colorScheme) private var scheme

    public init(_ input: ShipArtInput, scaleMode: ShipScaleMode = .fit) {
        self.input = input
        self.scaleMode = scaleMode
    }

    public var body: some View {
        let model = ShipArtModel.make(input)
        let input = input, mode = scaleMode, ink = ArtInk(scheme: scheme, contrast: input.accessibility.increaseContrast)
        Canvas { ctx, size in
            ShipRenderer.draw(&ctx, size: size, model: model, input: input, mode: mode, ink: ink)
        }
        .accessibilityHidden(true)
    }
}

/// ART-013: the solid alpha mask of a silhouette (no overlays).
public struct ShipSilhouette: View {
    public var input: ShipArtInput
    public var scaleMode: ShipScaleMode

    public init(_ input: ShipArtInput, scaleMode: ShipScaleMode = .fit) {
        self.input = input
        self.scaleMode = scaleMode
    }

    public var body: some View {
        let model = ShipArtModel.make(input)
        let input = input, mode = scaleMode
        Canvas { ctx, size in
            let t = ShipArtLayout.transform(bounds: model.geometry.bounds, size: size, mode: mode, sizeClass: input.sizeClass,
                                            facing: input.facing)
            for part in model.geometry.parts where part.solid { ctx.fill(part.path.applying(t), with: .color(.black)) }
        }
        .accessibilityHidden(true)
    }
}
