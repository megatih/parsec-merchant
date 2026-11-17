// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// ART-018: a deterministic scorch mask. The silhouette is divided into small cells which are revealed in a fixed,
/// blotchy order (seeded by `ArtSeed.kind`) until the revealed share equals the hull loss.
public struct ShipScorch: Sendable {
    /// Cells touching the silhouette, in reveal order (unit space), with the share of each cell inside the silhouette.
    public var cells: [CGRect]
    public var weights: [Double]

    public static let grid = 64
    /// Raster samples per cell side used to weigh each cell.
    static let samples = 4

    public static func make(_ geometry: ShipGeometry, seed: UInt64) -> ShipScorch {
        let b = geometry.bounds
        guard b.width > 0, b.height > 0 else { return ShipScorch(cells: [], weights: []) }
        let side = max(b.width, b.height) / Double(grid)
        let cols = Int((b.width / side).rounded(.up)), rows = Int((b.height / side).rounded(.up))
        let coverage = rasterCoverage(geometry.silhouette, bounds: b, side: side, cols: cols, rows: rows)
        var inside: [(CGRect, Double)] = []
        for j in 0..<rows {
            for i in 0..<cols where coverage[j * cols + i] > 0 {
                inside.append((CGRect(x: b.minX + Double(i) * side, y: b.minY + Double(j) * side, width: side, height: side), coverage[j * cols + i]))
            }
        }
        guard !inside.isEmpty else { return ShipScorch(cells: [], weights: []) }
        var rng = ArtRandom(seed: seed)
        let centres = (0..<6).map { _ in inside[Int(rng.next() % UInt64(inside.count))].0 }
        let spread = centres.map { _ in rng.range(0.7...1.4) }
        let keyed = inside.enumerated().map { index, cell -> (Double, Int) in
            var best = Double.infinity
            for (c, w) in zip(centres, spread) {
                let dx = cell.0.midX - c.midX, dy = cell.0.midY - c.midY
                best = min(best, (dx * dx + dy * dy).squareRoot() * w)
            }
            var jr = ArtRandom(seed: ArtSeed.mix(seed, UInt64(index)))
            return (best + jr.unit() * side * 3, index)
        }
        let order = keyed.sorted { ($0.0, $0.1) < ($1.0, $1.1) }.map { inside[$0.1] }
        return ShipScorch(cells: order.map(\.0), weights: order.map(\.1))
    }

    /// The share of each cell covered by `path`, from a CoreGraphics raster (`samples × samples` pixels per cell).
    static func rasterCoverage(_ path: Path, bounds b: CGRect, side: Double, cols: Int, rows: Int) -> [Double] {
        let k = samples, w = cols * k, h = rows * k
        var pixels = [UInt8](repeating: 0, count: w * h)
        pixels.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            ctx.translateBy(x: 0, y: Double(h))
            ctx.scaleBy(x: 1, y: -1)
            let scale = Double(k) / side
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -b.minX, y: -b.minY)
            ctx.addPath(path.cgPath)
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.fillPath()
        }
        var out = [Double](repeating: 0, count: cols * rows)
        for y in 0..<h {
            for x in 0..<w { out[(y / k) * cols + x / k] += Double(pixels[y * w + x]) }
        }
        return out.map { $0 / (255 * Double(k * k)) }
    }

    /// The revealed cells for a hull fraction (1 = pristine, nothing revealed): the shortest prefix of the reveal order whose
    /// covered area is closest to the hull loss.
    public func revealed(hullFraction: Double) -> Path {
        let total = weights.reduce(0, +)
        let target = (1 - min(1, max(0, hullFraction))) * total
        var p = Path()
        var sum = 0.0
        for (cell, w) in zip(cells, weights) {
            if sum >= target || (sum + w - target) > (target - sum) { break }
            p.addRect(cell)
            sum += w
        }
        return p
    }
}

/// ART-018 test support: renders only the hull (`scorch == false`) or only the scorch (`scorch == true`) as solid black,
/// with the same layout as `ShipArt`, so coverage can be measured on a render.
public struct ShipScorchMask: View {
    public var input: ShipArtInput
    public var scorch: Bool

    public init(input: ShipArtInput, scorch: Bool) {
        self.input = input
        self.scorch = scorch
    }

    public var body: some View {
        let model = ShipArtModel.make(input)
        Canvas { ctx, size in
            let t = ShipArtLayout.transform(bounds: model.geometry.bounds, size: size, mode: .fit, sizeClass: input.sizeClass,
                                            facing: input.facing)
            let hull = model.geometry.silhouette.applying(t)
            if scorch {
                ctx.clip(to: hull)
                ctx.fill(model.scorch.revealed(hullFraction: input.hullFraction).applying(t), with: .color(.black))
            } else {
                ctx.fill(hull, with: .color(.black))
            }
        }
        .accessibilityHidden(true)
    }
}
