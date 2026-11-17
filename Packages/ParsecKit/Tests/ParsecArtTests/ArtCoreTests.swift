// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import SwiftUI
import Testing
@testable import ParsecArt

@Suite("Art core")
struct ArtCoreTests {
    static var sources: [(name: String, text: String)] {
        let dir = ArtSnapshot.packageRoot.appendingPathComponent("Sources/ParsecArt")
        let files = (FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "swift" }
        return files.map { ($0.lastPathComponent, (try? String(contentsOf: $0, encoding: .utf8)) ?? "") }
    }

    @Test("ART-001 ParsecArt imports no engine or AppKit, declares no resources and embeds no images, clocks or process randomness")
    func packageRules() throws {
        let manifest = try String(contentsOf: ArtSnapshot.packageRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
        let line = try #require(manifest.split(separator: "\n").first { $0.contains(".target(name: \"ParsecArt\"") })
        #expect(!line.contains("dependencies"))
        #expect(!line.contains("resources"))
        let files = Self.sources
        #expect(files.count >= 15)
        let forbidden = ["import ParsecEngine", "import AppKit", "import UIKit", "Image(\"", "NSImage(named:", "NSImage(contentsOf", "UIImage(",
                         "Bundle.module", "Data(base64Encoded", "Date(", ".random", "SystemRandomNumberGenerator", "Hasher", "hashValue"]
        for f in files {
            #expect(f.text.hasPrefix("// SPDX-License-Identifier: GPL-2.0-or-later"), "\(f.name)")
            for word in forbidden { #expect(!f.text.contains(word), "\(f.name) contains \(word)") }
            for literal in f.text.split(separator: "\"") where literal.count > 400 && !literal.contains("\n") {
                Issue.record("\(f.name) has a long string literal")
            }
        }
    }

    @Test("ART-002 ArtRandom is SplitMix64 with pinned golden values; ArtSeed derives with fixed arithmetic")
    func goldenValues() {
        var a = ArtRandom(seed: 0)
        #expect((0..<5).map { _ in a.next() } == [0xE220_A839_7B1D_CDAF, 0x6E78_9E6A_A1B9_65F4, 0x06C4_5D18_8009_454F, 0xF88B_B8A8_724C_81EC,
                                                  0x1B39_896A_51A8_749B])
        var b = ArtRandom(seed: 42)
        #expect((0..<5).map { _ in b.next() } == [0xBDD7_3226_2FEB_6E95, 0x28EF_E333_B266_F103, 0x4752_6757_130F_9F52, 0x581C_E1FF_0E4A_E394,
                                                  0x09BC_585A_2448_23F2])
        #expect(ArtSeed.mix(1, 2) == 0xBEEB_8DA1_658E_EC67)
        var c = ArtRandom(seed: 7)
        for _ in 0..<1000 {
            let u = c.unit()
            #expect(u >= 0 && u < 1)
            let r = c.range(2...3)
            #expect(r >= 2 && r <= 3)
        }
        #expect(ArtSeed.system(galaxySeed: 9, index: 3) == ArtSeed.system(galaxySeed: 9, index: 3))
        #expect(ArtSeed.system(galaxySeed: 9, index: 3) != ArtSeed.system(galaxySeed: 9, index: 4))
        #expect(ArtSeed.crew(galaxySeed: 9, crewID: 3) != ArtSeed.system(galaxySeed: 9, index: 3))
        #expect(Set(ShipArtKind.allCases.map(ArtSeed.kind)).count == 17)
    }

    @Test("ART-003 every token has light, dark and contrast values; map tokens equal the M8 map colours")
    func palette() {
        for token in ArtToken.allCases {
            for scheme in [ColorScheme.light, .dark] {
                let c = ArtPalette.rgb(token, scheme: scheme)
                #expect([c.r, c.g, c.b, c.a].allSatisfy { $0 >= 0 && $0 <= 1 }, "\(token)")
                _ = ArtPalette.resolve(token, scheme: scheme, contrast: true)
            }
        }
        #expect(ArtPalette.rgb(.spaceTop, scheme: .light) == ArtRGB(0.16, 0.17, 0.36))
        #expect(ArtPalette.rgb(.spaceTop, scheme: .dark) == ArtRGB(0.09, 0.08, 0.22))
        #expect(ArtPalette.rgb(.spaceBottom, scheme: .light) == ArtRGB(0.05, 0.06, 0.14))
        #expect(ArtPalette.rgb(.spaceBottom, scheme: .dark) == ArtRGB(0.01, 0.01, 0.04))
        #expect(ArtPalette.rgb(.visited, scheme: .light) == ArtRGB(0.35, 0.75, 1.0))
        #expect(ArtPalette.rgb(.unvisited, scheme: .dark) == ArtRGB(0.40, 0.95, 0.50))
        #expect(ArtPalette.rgb(.wormholeA, scheme: .light) == ArtRGB(1.0, 0.70, 0.20))
        #expect(ArtPalette.rgb(.wormholeB, scheme: .light) == ArtRGB(0.90, 0.30, 0.85))
        #expect(ArtPalette.rgb(.brass, scheme: .light) == ArtRGB(0.86, 0.70, 0.35))
        #expect(ArtPalette.rgb(.brass, scheme: .light, contrast: true) != ArtPalette.rgb(.brass, scheme: .light))
    }

    @Test("ART-004 accessibility rules: 1.5× outlines, Reduce Motion freezes ambient phase")
    func accessibilityRules() {
        #expect(ArtAccessibility(increaseContrast: true).outlineScale == 1.5)
        #expect(ArtAccessibility.standard.outlineScale == 1)
        #expect(ArtAccessibility(reduceMotion: true).ambientPhase(12.3) == 0)
        #expect(ArtAccessibility.standard.ambientPhase(12.3) == 12.3)
    }

    @Test("ART-005 Catmull-Rom splines use tension 0.5; paths are pure, closed and inside the unit square")
    func splines() {
        #expect(ArtGeometry.tension == 0.5)
        let pts = [SplinePoint(0, 0), SplinePoint(1, 0), SplinePoint(1, 1), SplinePoint(0, 1)]
        var controls: [CGPoint] = []
        ArtGeometry.closedSpline(pts).forEach { e in
            if case let .curve(_, c1, _) = e { controls.append(c1) }
        }
        // Segment 0→1: c1 = p0 + (p1 − p3) / 6 = (1/6, −1/6).
        #expect(abs(controls[0].x - 1.0 / 6) < 1e-6 && abs(controls[0].y + 1.0 / 6) < 1e-6)
        #expect(ArtGeometry.isClosed(ArtGeometry.closedSpline(pts)))
        #expect(!ArtGeometry.isClosed(ArtGeometry.openSpline(pts)))
        for kind in ShipArtKind.allCases {
            let g = ShipGeometry.make(ShipArtInput(kind: kind).blueprint)
            #expect(!g.silhouette.isEmpty)
            #expect(ArtGeometry.isClosed(g.hull), "\(kind)")
            let b = g.bounds
            #expect(b.minX >= -1e-9 && b.minY >= -1e-9 && b.maxX <= 1 + 1e-9 && b.maxY <= 1 + 1e-9, "\(kind) \(b)")
            #expect(ArtGeometry.area(g.silhouette) > 0.02, "\(kind)")
            #expect(ShipGeometry.make(ShipArtInput(kind: kind).blueprint).bounds == b)
        }
    }

    @MainActor
    @Test("ART-006 budgets: ship 240×160 and planet 160 pt render within 4 ms (median, warm); ArtCache is a 512-entry LRU")
    func budgets() {
        let cache = ArtCache()
        for i in 0..<600 { _ = cache.value(i) { i * 2 } }
        #expect(cache.count == ArtCache.capacity)
        #expect(cache.value(599) { -1 } == 1198)
        #expect(cache.value(0) { -1 } == -1) // evicted, recomputed
        func median(_ body: () -> Void) -> Double {
            body()
            var times: [Double] = []
            for _ in 0..<15 {
                let start = DispatchTime.now().uptimeNanoseconds
                body()
                times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
            }
            return times.sorted()[times.count / 2]
        }
        let ship = median { _ = ArtSnapshot.render(ShipArt(ShipArtInput(kind: .wasp, hullFraction: 0.6, shield: ShieldDisplay(kind: .energy, fraction: 0.5))),
                                                    size: CGSize(width: 240, height: 160), scale: 1) }
        let planet = median { _ = ArtSnapshot.render(PlanetArt(PlanetArtInput(seed: 4, tech: 7, government: 0, pressure: 1)),
                                                      size: CGSize(width: 160, height: 160), scale: 1) }
        print("ART-006 ship \(ship) ms, planet \(planet) ms (ImageRenderer + decode)")
        #expect(ship <= 4 * Self.debugFactor)
        #expect(planet <= 4 * Self.debugFactor)
    }

    /// Debug builds run unoptimised; the budget is checked against release-like code with this allowance.
    static var debugFactor: Double {
        #if DEBUG
        return 3
        #else
        return 1
        #endif
    }
}
