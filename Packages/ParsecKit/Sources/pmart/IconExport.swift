// SPDX-License-Identifier: GPL-2.0-or-later
import CoreGraphics
import Foundation
import ImageIO
import ParsecArt
import SwiftUI
import UniformTypeIdentifiers

/// ART-054/055: renders the icon layers and the full-bleed fallback and writes them with no metadata.
@MainActor
enum IconExport {
    /// The appiconset entries of the existing `Contents.json`: point size and scale.
    static let entries: [(size: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2),
                                                     (512, 1), (512, 2)]

    static func filename(size: Int, scale: Int) -> String {
        scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@\(scale)x.png"
    }

    static let iconDir = "AppIcon.icon"
    static let setDir = "Assets.xcassets/AppIcon.appiconset"

    /// Writes every file; returns the relative paths written.
    static func write(to root: URL) throws -> [String] {
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("\(iconDir)/Assets"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent(setDir), withIntermediateDirectories: true)
        var written: [String] = []
        for layer in AppIconArt.Layer.allCases {
            let rel = "\(iconDir)/Assets/\(layer.rawValue).png"
            try writePNG(render(AppIconLayerView(layer), pixels: 1024), to: root.appendingPathComponent(rel))
            written.append(rel)
        }
        let json = "\(iconDir)/icon.json"
        try iconJSON().write(to: root.appendingPathComponent(json))
        written.append(json)
        for e in entries {
            let px = e.size * e.scale
            let rel = "\(setDir)/\(filename(size: e.size, scale: e.scale))"
            try writePNG(render(AppIconComposite(simplified: px <= 32), pixels: px), to: root.appendingPathComponent(rel))
            written.append(rel)
        }
        let contents = "\(setDir)/Contents.json"
        try contentsJSON().write(to: root.appendingPathComponent(contents))
        written.append(contents)
        return written
    }

    /// Renders `view` at `pixels × pixels` (scale 1) straight into an 8-bit RGBA sRGB `CGContext` through
    /// `ImageRenderer.render(rasterizationScale:renderer:)` (the Core Graphics route is deterministic across runs).
    static func render<V: View>(_ view: V, pixels: Int) -> CGImage {
        let size = CGSize(width: pixels, height: pixels)
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height).environment(\.colorScheme, .light))
        renderer.proposedSize = ProposedViewSize(size)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fail("no CGContext") }
        renderer.render(rasterizationScale: 1) { _, draw in draw(ctx) }
        guard let image = ctx.makeImage() else { fail("no image") }
        return image
    }

    static func normalise(_ image: CGImage) -> CGImage {
        let w = image.width, h = image.height
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fail("no CGContext") }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage() else { fail("no image") }
        return out
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { fail("no PNG encoder") }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { fail("PNG encoding failed") }
        try (data as Data).write(to: url)
    }

    static func srgb(_ c: ArtRGB) -> String {
        String(format: "srgb:%.5f,%.5f,%.5f,%.5f", c.r, c.g, c.b, c.a)
    }

    static func gradient(_ scheme: ColorScheme) -> [String: Any] {
        let f = AppIconArt.fill(scheme: scheme)
        return ["linear-gradient": [srgb(f.top), srgb(f.bottom)],
                "orientation": ["start": ["x": 0.5, "y": 0.0], "stop": ["x": 0.5, "y": 1.0]]]
    }

    /// ART-055: one group per layer, back to front, sorted keys.
    static func iconJSON() throws -> Data {
        let groups: [[String: Any]] = AppIconArt.Layer.allCases.reversed().map { layer in
            ["layers": [["glass": layer.glass, "image-name": "\(layer.rawValue).png", "name": layer.rawValue]],
             "shadow": ["kind": "neutral", "opacity": 0.5],
             "translucency": ["enabled": true, "value": 0.5]]
        }
        let doc: [String: Any] = [
            "fill-specializations": [["value": gradient(.light)], ["appearance": "dark", "value": gradient(.dark)]],
            "groups": groups,
            "supported-platforms": ["squares": "shared"],
        ]
        return try JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys]) + Data("\n".utf8)
    }

    static func contentsJSON() throws -> Data {
        let images: [[String: Any]] = entries.map { e in
            ["filename": filename(size: e.size, scale: e.scale), "idiom": "mac", "scale": "\(e.scale)x", "size": "\(e.size)x\(e.size)"]
        }
        let doc: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
        return try JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys]) + Data("\n".utf8)
    }

    // MARK: Check (ART-056)

    /// Compares each written file with the same relative path under `other`: PNGs by decoded pixels (at most 0.1% of
    /// pixels may differ by more than 2 in any channel), other files byte for byte.
    static func compare(_ files: [String], outRoot: URL, against other: URL) -> [String] {
        var problems: [String] = []
        for rel in files {
            let a = outRoot.appendingPathComponent(rel), b = other.appendingPathComponent(rel)
            guard let da = try? Data(contentsOf: a), let db = try? Data(contentsOf: b) else {
                problems.append("\(rel): missing")
                continue
            }
            if rel.hasSuffix(".png") {
                if let why = pixelDifference(da, db) { problems.append("\(rel): \(why)") }
            } else if da != db {
                problems.append("\(rel): content differs")
            }
        }
        return problems
    }

    static func decode(_ data: Data) -> (Int, Int, [UInt8])? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            return nil
        }
        let n = normalise(img)
        guard let provider = n.dataProvider?.data as Data? else { return nil }
        return (n.width, n.height, [UInt8](provider))
    }

    static func pixelDifference(_ a: Data, _ b: Data) -> String? {
        guard let (wa, ha, pa) = decode(a), let (wb, hb, pb) = decode(b) else { return "undecodable" }
        guard wa == wb, ha == hb, pa.count == pb.count else { return "size \(wa)×\(ha) vs \(wb)×\(hb)" }
        var differing = 0, maxDiff = 0
        for px in stride(from: 0, to: pa.count, by: 4) {
            var d = 0
            for k in 0..<4 { d = max(d, abs(Int(pa[px + k]) - Int(pb[px + k]))) }
            if d > 2 { differing += 1 }
            maxDiff = max(maxDiff, d)
        }
        let share = Double(differing) / Double(wa * ha)
        return share <= 0.001 ? nil : "\(differing) pixels differ by more than 2 (max \(maxDiff))"
    }
}
