// SPDX-License-Identifier: GPL-2.0-or-later
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ParsecArt

@Suite("Icon pipeline and license guard")
struct IconPipelineTests {
    static var repo: URL { ArtSnapshot.packageRoot.deletingLastPathComponent().deletingLastPathComponent() }

    static func text(_ path: String) throws -> String {
        try String(contentsOf: repo.appendingPathComponent(path), encoding: .utf8)
    }

    static func pngSize(_ path: String) -> (Int, Int)? {
        guard let src = CGImageSourceCreateWithURL(repo.appendingPathComponent(path) as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return (img.width, img.height)
    }

    @Test("ART-054 pmart is an executable product that depends only on ParsecArt and has the icon subcommand")
    func pmart() throws {
        let manifest = try String(contentsOf: ArtSnapshot.packageRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
        #expect(manifest.contains(".executable(name: \"pmart\", targets: [\"pmart\"])"))
        #expect(manifest.contains(".executableTarget(name: \"pmart\", dependencies: [\"ParsecArt\"]"))
        let main = try String(contentsOf: ArtSnapshot.packageRoot.appendingPathComponent("Sources/pmart/main.swift"), encoding: .utf8)
        #expect(main.contains("case \"icon\"") && main.contains("--out") && main.contains("--check"))
    }

    @Test("ART-055 make-icon.sh wrote the .icon bundle (three 1024 px layers, icon.json) and the ten full-bleed PNGs")
    func iconFiles() throws {
        let script = try Self.text("scripts/make-icon.sh")
        #expect(script.hasPrefix("#!/bin/bash\n# SPDX-License-Identifier: GPL-2.0-or-later"))
        #expect(!script.contains(" grep ") && script.contains("/usr/bin/grep"))
        for layer in AppIconArt.Layer.allCases {
            let size = Self.pngSize("SpaceTraderMac/AppIcon.icon/Assets/\(layer.rawValue).png")
            #expect(size?.0 == 1024 && size?.1 == 1024, "\(layer)")
        }
        let json = try #require(try JSONSerialization.jsonObject(with: Data(Self.text("SpaceTraderMac/AppIcon.icon/icon.json").utf8)) as? [String: Any])
        let groups = try #require(json["groups"] as? [[String: Any]])
        let layers = groups.compactMap { ($0["layers"] as? [[String: Any]])?.first }
        #expect(layers.compactMap { $0["name"] as? String } == ["hauler", "ring", "stars"])
        #expect(layers.compactMap { $0["glass"] as? Bool } == [true, true, false])
        #expect((json["supported-platforms"] as? [String: Any])?["squares"] as? String == "shared")
        let fills = try #require(json["fill-specializations"] as? [[String: Any]])
        #expect(fills.count == 2 && fills.last?["appearance"] as? String == "dark")
        let contents = try #require(try JSONSerialization.jsonObject(
            with: Data(Self.text("SpaceTraderMac/Assets.xcassets/AppIcon.appiconset/Contents.json").utf8)) as? [String: Any])
        let images = try #require(contents["images"] as? [[String: Any]])
        #expect(images.count == 10)
        for image in images {
            let name = try #require(image["filename"] as? String)
            let points = Int((image["size"] as? String)?.split(separator: "x").first ?? "") ?? 0
            let scale = Int((image["scale"] as? String)?.dropLast() ?? "") ?? 0
            let size = Self.pngSize("SpaceTraderMac/Assets.xcassets/AppIcon.appiconset/\(name)")
            #expect(size?.0 == points * scale && size?.1 == points * scale, "\(name)")
        }
    }

    @Test("ART-056 make-icon.sh --check compares pixels and runs actool with zero diagnostics; verify.sh runs it from M11")
    func check() throws {
        let script = try Self.text("scripts/make-icon.sh")
        #expect(script.contains("--check") && script.contains("xcrun actool --compile"))
        #expect(script.contains("--warnings --notices --errors --output-format xml1"))
        #expect(script.contains("com\\.apple\\.actool\\.(document\\.(warnings|notices|errors)|errors)"))
        #expect(script.contains("CFBundleIconName") && script.contains("make-icon: OK"))
        let verify = try Self.text("scripts/verify.sh")
        #expect(verify.contains("scripts/make-icon.sh --check"))
    }

    @Test("ART-065 ART-066 license-check keeps the original-image hash check and allows only the generated icon images")
    func licenseGuard() throws {
        let script = try Self.text("scripts/license-check.sh")
        #expect(script.contains("identical to original asset") && script.contains("SpaceTraderSource201"))
        #expect(script.contains(".bmp\", \".gif\", \".ico\""))
        #expect(script.contains("\"SpaceTraderMac/AppIcon.icon/Assets/*.png\"")
            && script.contains("\"SpaceTraderMac/Assets.xcassets/AppIcon.appiconset/*.png\""))
        for ext in ["png", "jpg", "jpeg", "tif", "tiff", "heic", "webp", "pdf", "svg", "icns"] { #expect(script.contains("\".\(ext)\""), "\(ext)") }
        let verify = try Self.text("scripts/verify.sh")
        #expect(verify.contains("scripts/license-check.sh"))
    }
}
