// SPDX-License-Identifier: GPL-2.0-or-later
import CoreGraphics
import CryptoKit
import Foundation
import SwiftUI
@testable import ParsecArt

/// ART-059: decoded pixels of a render, 8-bit RGBA premultiplied sRGB.
struct ArtPixels: Equatable {
    var width: Int
    var height: Int
    var bytes: [UInt8]

    var fingerprint: String {
        SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
    }

    func alpha(_ x: Int, _ y: Int) -> UInt8 { bytes[(y * width + x) * 4 + 3] }

    /// Share of pixels with alpha above `threshold`.
    func coverage(threshold: UInt8 = 0) -> Double {
        var n = 0
        for i in stride(from: 3, to: bytes.count, by: 4) where bytes[i] > threshold { n += 1 }
        return Double(n) / Double(width * height)
    }

    /// Sum of alpha over all pixels / 255.
    var alphaSum: Double {
        var s = 0
        for i in stride(from: 3, to: bytes.count, by: 4) { s += Int(bytes[i]) }
        return Double(s) / 255
    }

    var distinctColors: Int {
        var set = Set<UInt32>()
        for i in stride(from: 0, to: bytes.count, by: 4) where bytes[i + 3] > 0 {
            set.insert(UInt32(bytes[i]) << 24 | UInt32(bytes[i + 1]) << 16 | UInt32(bytes[i + 2]) << 8 | UInt32(bytes[i + 3]))
            if set.count > 64 { break }
        }
        return set.count
    }

    /// The alpha mask as booleans (alpha ≥ 128).
    var mask: [Bool] { stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] >= 128 } }

    /// The mask's bounding box width in pixels.
    var maskWidth: Int {
        var minX = width, maxX = -1
        for y in 0..<height {
            for x in 0..<width where alpha(x, y) >= 128 {
                minX = min(minX, x)
                maxX = max(maxX, x)
            }
        }
        return maxX >= minX ? maxX - minX + 1 : 0
    }

    /// Pixels mirrored horizontally.
    var mirrored: ArtPixels {
        var out = bytes
        for y in 0..<height {
            for x in 0..<width {
                let src = (y * width + x) * 4, dst = (y * width + (width - 1 - x)) * 4
                for k in 0..<4 { out[dst + k] = bytes[src + k] }
            }
        }
        return ArtPixels(width: width, height: height, bytes: out)
    }

    /// Whether the render is non-empty: alpha on `lo`…`hi` of pixels and at least `colors` distinct colours.
    func isNonEmpty(lo: Double = 0.05, hi: Double = 0.95, colors: Int = 3) -> Bool {
        let c = coverage()
        return c >= lo && c <= hi && distinctColors >= colors
    }
}

enum ArtSnapshot {
    /// ART-059: renders with a fresh `ImageRenderer` (fixed proposed size, scale and colour scheme) straight into a
    /// fixed-format `CGContext` (8-bit RGBA, premultiplied, sRGB) through `ImageRenderer.render(rasterizationScale:renderer:)`.
    /// The Core Graphics route is used instead of `cgImage` because the default rasteriser caches content it has drawn a few
    /// times and then changes some pixels by one unit, which would make "byte-identical twice" depend on render history.
    @MainActor
    static func render<V: View>(_ view: V, size: CGSize, scale: CGFloat = 2, scheme: ColorScheme = .light) -> ArtPixels {
        let content = view
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, scheme)
            .environment(\.displayScale, scale)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(size)
        let w = Int((size.width * scale).rounded()), h = Int((size.height * scale).rounded())
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        bytes.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            renderer.render(rasterizationScale: scale) { _, draw in
                ctx.scaleBy(x: scale, y: scale)
                draw(ctx)
            }
        }
        return ArtPixels(width: w, height: h, bytes: bytes)
    }

    static func decode(_ image: CGImage) -> ArtPixels {
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        bytes.withUnsafeMutableBytes { buf in
            if let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
        }
        return ArtPixels(width: w, height: h, bytes: bytes)
    }

    /// Renders twice with fresh renderers and returns both.
    @MainActor
    static func twice<V: View>(_ view: V, size: CGSize, scale: CGFloat = 2, scheme: ColorScheme = .light) -> (ArtPixels, ArtPixels) {
        (render(view, size: size, scale: scale, scheme: scheme), render(view, size: size, scale: scale, scheme: scheme))
    }

    static func iou(_ a: [Bool], _ b: [Bool]) -> Double {
        var inter = 0, union = 0
        for (x, y) in zip(a, b) {
            if x && y { inter += 1 }
            if x || y { union += 1 }
        }
        return union == 0 ? 0 : Double(inter) / Double(union)
    }

    /// The `Sources/ParsecArt` and package root folders, from this file's path.
    static var packageRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
}
