// SPDX-License-Identifier: GPL-2.0-or-later
import CryptoKit
import Foundation
import SwiftUI
import Testing
@testable import ParsecArt

/// PROT-003: the planet graphics are frozen for release 2.0. The literals below were recorded at M18 on commit 296ad2c,
/// before any other change of the interface revamp. A differing value means planet pixels changed: find the change
/// and undo it; the literals are never re-recorded.
@MainActor
@Suite("Planet graphics are frozen (PROT)")
struct PlanetFrozenTests {
    static let size = CGSize(width: 96, height: 96)

    static func digest(_ parts: [String]) -> String {
        SHA256.hash(data: Data(parts.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func classInputs() -> [PlanetArtInput] {
        var inputs: [PlanetArtInput] = []
        for cls in PlanetClass.allCases {
            for seedOffset in [0, 1] {
                let size = (cls == .gasGiant ? PlanetClass.gasGiantMinimumSize : 2) + seedOffset
                inputs.append(PlanetArtInput(seed: PlanetSphereTests.seed(for: cls, size: size), sizeClass: size, tech: 4, government: 6))
            }
        }
        return inputs
    }

    static func styleInputs() -> [PlanetArtInput] {
        var inputs: [PlanetArtInput] = []
        for tech in 0...7 { inputs.append(PlanetArtInput(seed: 42, tech: tech, government: 6, resource: 5)) }
        for g in 0...16 { inputs.append(PlanetArtInput(seed: 42, tech: 4, government: g)) }
        for r in 0...12 { inputs.append(PlanetArtInput(seed: 42, tech: 4, government: 6, resource: r)) }
        for p in 0...7 { inputs.append(PlanetArtInput(seed: 42, tech: 4, government: 6, pressure: p)) }
        return inputs
    }

    @Test("PROT-003 planet stills per class and level of detail keep their recorded pixels")
    func classPixels() {
        #expect(Set(Self.classInputs().map { PlanetRecipe.make($0).planetClass }).count == 10)
        var prints: [String] = []
        for input in Self.classInputs() {
            for lod in [PlanetLOD.mini, .still, .hero] {
                prints.append(ArtSnapshot.render(PlanetArt(input, lod: lod), size: Self.size).fingerprint)
            }
        }
        let digest = Self.digest(prints)
        #expect(digest == "a87aa3bb1fe27f002741e1d59aeadd76dbb00f967f4f1b524c4966866c019367", "now \(digest)")
    }

    @Test("PROT-003 planet looks per tech level, government, resource and pressure keep their recorded pixels")
    func stylePixels() {
        let prints = Self.styleInputs().map { ArtSnapshot.render(PlanetArt($0), size: Self.size).fingerprint }
        let digest = Self.digest(prints)
        #expect(digest == "8307e628ab1e1f70f1749852cea22ab746da35629b09f7bb9ba28176df5a7ac6", "now \(digest)")
    }

    @Test("PROT-003 planet overlays and map sprites keep their recorded pixels")
    func overlayAndSpritePixels() {
        var prints: [String] = []
        for input in [PlanetArtInput(seed: 42, tech: 7, government: 7), PlanetArtInput(seed: 7, tech: 6, government: 0),
                      PlanetArtInput(seed: 9, sizeClass: 4, tech: 7, government: 2)] {
            for part in [PlanetOverlayArt.Part.behind, .front] {
                prints.append(ArtSnapshot.render(PlanetOverlayArt(input, part: part), size: Self.size).fingerprint)
            }
        }
        for input in Self.classInputs().prefix(10) {
            if let sprite = PlanetRenderer.sprite(input, pixelDiameter: 24) {
                prints.append(ArtSnapshot.decode(sprite.cgImage).fingerprint)
            } else {
                prints.append("nil")
            }
        }
        let digest = Self.digest(prints)
        #expect(digest == "97b579785c97af6601e284355a75a1b609381f1575eeeab18e28bb4cc3663a36", "now \(digest)")
    }

    @Test("PROT-003 the planet recipe of a seed is unchanged")
    func recipes() {
        let text = (0..<64).map { i in
            let r = PlanetRecipe.make(PlanetArtInput(seed: ArtSeed.system(galaxySeed: 1001, index: i), sizeClass: i % 5, tech: i % 8, government: i % 17))
            return "\(r.planetClass)|\(r.tint)|\(r.accent)|\(r.style)|\(r.motif)"
        }
        let digest = Self.digest(text)
        #expect(digest == "ba8cd706b1be3fd06dedadd28d1fa4369a1dd3fe294193e1840b0c4de0aa5233", "now \(digest)")
    }
}

/// PROT-001, PROT-002: the two freeze scripts pass on this checkout.
@Suite("Freeze scripts (PROT)")
struct FreezeScriptTests {
    static func run(_ script: String, _ arguments: [String] = []) throws -> (status: Int32, output: String) {
        // …/Packages/ParsecKit/Tests/ParsecArtTests/PlanetFrozenTests.swift → the repository root, five levels up.
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let process = Process()
        process.executableURL = root.appendingPathComponent("scripts/\(script)")
        process.arguments = arguments
        process.currentDirectoryURL = root
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(bytes: data, encoding: .utf8) ?? "")
    }

    @Test("PROT-001 the 22 protected planet files are byte-identical to the revamp's base commit")
    func protectedFiles() throws {
        let result = try Self.run("protected-check.sh")
        #expect(result.status == 0, "\(result.output)")
        #expect(result.output.contains("PROTECTED OK (22 files)"))
    }

    @Test("PROT-002 engine, insights, persistence and pmsim sources and tests are byte-identical to v1.1.0")
    func frozenLogic() throws {
        let result = try Self.run("logic-frozen.sh", ["--fast"])
        #expect(result.status == 0, "\(result.output)")
        #expect(result.output.contains("LOGIC FROZEN OK"))
    }
}
