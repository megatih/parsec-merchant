// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// ART-FACE-004: where every feature of a face sits, in the unit square (y down). Proportions follow the usual drawing
/// rules: the eye line at half the head height, one eye width between the eyes, the nose base about two thirds of the way
/// from the eye line to the mouth, the mouth about as wide as the distance between the pupils. Every value is clamped.
public struct PortraitLayout: Sendable {
    public static let centerX = 0.5
    public static let top = 0.13

    public let chinY: Double
    public let eyeY: Double
    /// Half widths of the head at the temple, the cheekbone, the jaw corner and the chin.
    public let craniumHalf: Double
    public let cheekHalf: Double
    public let jawHalf: Double
    public let chinHalf: Double
    public let eyeWidth: Double
    public let eyeHeight: Double
    /// Half the distance between the eye centres.
    public let eyeOffset: Double
    public let browY: Double
    public let noseBaseY: Double
    public let noseHalf: Double
    public let mouthY: Double
    public let mouthHalf: Double
    public let lipHeight: Double

    public init(_ g: PortraitGenome) {
        let top = Self.top
        chinY = 0.715 + Double(g.chin) * 0.006
        eyeY = top + (chinY - top) * 0.5
        cheekHalf = 0.202 * (1 + 0.03 * Double(g.cheek))
        // The skull is never much wider than the cheekbones (a wider one reads as a lightbulb on a bald head).
        craniumHalf = min(0.214 * (1 + 0.03 * Double(g.cranium)), cheekHalf * 1.04)
        jawHalf = max(0.160 * (1 + 0.03 * Double(g.jaw)), cheekHalf * 0.74)
        chinHalf = 0.064 * (1 + 0.02 * Double(g.jaw))
        eyeWidth = cheekHalf * 2 / 4.8
        eyeHeight = eyeWidth * [0.44, 0.50, 0.40, 0.44, 0.44, 0.36][g.eyeShape % 6]
        eyeOffset = cheekHalf * 2 / 5 * (1 + 0.05 * Double(g.eyeSpacing))
        browY = eyeY - eyeWidth * 0.62 - Double(g.browHeight) * 0.004
        let lower = chinY - eyeY
        noseBaseY = eyeY + lower * (0.47 + Double(g.noseSize) * 0.015)
        noseHalf = eyeWidth * [0.50, 0.60, 0.42, 0.46, 0.50, 0.64][g.noseShape % 6]
        mouthY = noseBaseY + (chinY - noseBaseY) * 0.37
        mouthHalf = eyeOffset * 0.84 * (1 + 0.05 * Double(g.mouthWidth))
        lipHeight = eyeWidth * [0.20, 0.27, 0.13, 0.19, 0.18, 0.25][g.mouthShape % 6]
    }

    /// The eye line as a share of the head height.
    public var eyeLine: Double { (eyeY - Self.top) / (chinY - Self.top) }

    /// The head outline.
    public var head: Path {
        let cx = Self.centerX, top = Self.top
        let right: [(Double, Double)] = [
            (craniumHalf * 0.56, top + 0.030), (craniumHalf * 0.90, top + 0.110), (craniumHalf * 0.985, top + 0.20),
            (cheekHalf, eyeY + 0.065), (jawHalf, chinY - 0.105), (jawHalf * 0.72, chinY - 0.040), (chinHalf, chinY - 0.008),
        ]
        var points: [SplinePoint] = [SplinePoint(cx, top)]
        points += right.map { SplinePoint(cx + $0.0, $0.1) }
        points.append(SplinePoint(cx, chinY))
        points += right.reversed().map { SplinePoint(cx - $0.0, $0.1) }
        return ArtGeometry.closedSpline(points)
    }

    public var headRect: CGRect {
        let half = max(craniumHalf, cheekHalf)
        return CGRect(x: Self.centerX - half, y: Self.top, width: half * 2, height: chinY - Self.top)
    }

    /// The centre of an eye; `side` is −1 for the eye on the left of the picture and +1 for the right.
    public func eyeCenter(_ side: Double) -> CGPoint { CGPoint(x: Self.centerX + side * eyeOffset, y: eyeY) }

    public func eyeRect(_ side: Double) -> CGRect {
        let c = eyeCenter(side)
        return CGRect(x: c.x - eyeWidth / 2, y: c.y - eyeHeight / 2, width: eyeWidth, height: eyeHeight)
    }

    public func browRect(_ side: Double) -> CGRect {
        let c = eyeCenter(side)
        return CGRect(x: c.x - eyeWidth * 0.62, y: browY - 0.012, width: eyeWidth * 1.24, height: 0.020)
    }

    public var noseRect: CGRect {
        CGRect(x: Self.centerX - noseHalf, y: eyeY + eyeHeight / 2 + 0.012, width: noseHalf * 2, height: noseBaseY - eyeY - eyeHeight / 2 - 0.006)
    }

    public var mouthRect: CGRect {
        CGRect(x: Self.centerX - mouthHalf, y: mouthY - lipHeight, width: mouthHalf * 2, height: lipHeight * 2.2)
    }

    /// The part of the face the tone test samples (ART-FACE-006): brow to mouth, cheekbone to cheekbone.
    public var faceRect: CGRect {
        let half = cheekHalf * 0.92
        return CGRect(x: Self.centerX - half, y: browY - 0.02, width: half * 2, height: mouthY + lipHeight - browY + 0.04)
    }
}
