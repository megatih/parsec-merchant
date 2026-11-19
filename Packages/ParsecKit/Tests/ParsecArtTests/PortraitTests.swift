// SPDX-License-Identifier: GPL-2.0-or-later
import CryptoKit
import Foundation
import SwiftUI
import Testing
@testable import ParsecArt

/// ART-FACE: procedural portraits (docs/PRD-UI-Revamp.md §5.2).
@MainActor
@Suite("Portraits (ART-FACE)")
struct PortraitTests {
    /// The crew ids that have a portrait in a game: the commander, the hireable mercenaries of the largest crew list and
    /// Zeethibal. The special characters and famous captains use authored genomes.
    static let seededCrew = Array(0...30) + Array(38...52)

    static func crewGenomes(galaxySeed: UInt64) -> [PortraitGenome] {
        seededCrew.map { PortraitGenome.make(seed: ArtSeed.crew(galaxySeed: galaxySeed, crewID: $0)) }
            + PortraitRole.allCases.map { PortraitGenome.fixed($0) }
    }

    static func render(_ genome: PortraitGenome, side: Double) -> ArtPixels {
        ArtSnapshot.render(CharacterPortrait(genome: genome), size: CGSize(width: side, height: side))
    }

    static func digest(_ genomes: [PortraitGenome]) -> String {
        let text = genomes.map { $0.genes.map(String.init).joined(separator: ",") }.joined(separator: "\n")
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    @Test("ART-FACE-001 the same seed gives the same genome and pixels; the genomes of galaxy seed 1001 are pinned")
    func determinism() {
        let genomes = (0..<55).map { PortraitGenome.make(seed: ArtSeed.crew(galaxySeed: 1001, crewID: $0)) }
        #expect(genomes == (0..<55).map { PortraitGenome.make(seed: ArtSeed.crew(galaxySeed: 1001, crewID: $0)) })
        for genome in genomes.prefix(8) + PortraitRole.allCases.map({ PortraitGenome.fixed($0) }) {
            let (a, b) = ArtSnapshot.twice(CharacterPortrait(genome: genome), size: CGSize(width: 96, height: 96))
            #expect(a.fingerprint == b.fingerprint)
        }
        let digest = Self.digest(genomes + PortraitRole.allCases.map { PortraitGenome.fixed($0) })
        #expect(digest == "c8abe9567f25a6f267866d324194de186a4e882f2f54d00a36cfd751a520f2f1", "now \(digest)")
    }

    @Test("ART-FACE-002 within a game every portrait differs from every other in at least 4 genes and in its pixels")
    func uniqueWithinAGame() {
        for seed in UInt64(1)...500 {
            let genomes = Self.crewGenomes(galaxySeed: seed)
            #expect(Set(genomes).count == genomes.count, "galaxy seed \(seed)")
            var closest = Int.max
            for i in genomes.indices {
                for j in genomes.indices where j > i { closest = min(closest, genomes[i].distance(to: genomes[j])) }
            }
            #expect(closest >= 4, "galaxy seed \(seed): two portraits differ in only \(closest) genes")
        }
        for seed in UInt64(1)...20 {
            let prints = Self.crewGenomes(galaxySeed: seed).map { Self.render($0, side: 96).fingerprint }
            #expect(Set(prints).count == prints.count, "galaxy seed \(seed)")
        }
    }

    @Test("ART-FACE-003 100,000 random seeds give at least 99,900 distinct genomes")
    func uniqueAtLarge() {
        var rng = ArtRandom(seed: 0x00C0_FFEE)
        var seen = Set<PortraitGenome>()
        for _ in 0..<100_000 { seen.insert(PortraitGenome.make(seed: rng.next())) }
        #expect(seen.count >= 99_900, "\(seen.count)")
    }

    @Test("ART-FACE-004 proportions: eye line near half height, mirrored eyes, features in order, inside the head and apart")
    func proportions() {
        var rng = ArtRandom(seed: 7)
        let genomes = (0..<10_000).map { _ in PortraitGenome.make(seed: rng.next()) } + PortraitRole.allCases.map { PortraitGenome.fixed($0) }
        for g in genomes {
            let l = PortraitLayout(g)
            #expect((0.46...0.54).contains(l.eyeLine))
            let left = l.eyeRect(-1), right = l.eyeRect(1)
            #expect(abs((PortraitLayout.centerX - left.midX) - (right.midX - PortraitLayout.centerX)) < 1e-9 && left.midY == right.midY)
            #expect(l.browRect(-1).midY < left.minY + 0.004 && l.noseBaseY > l.eyeY && l.noseBaseY < l.mouthRect.minY && l.mouthRect.maxY < l.chinY)
            let head = l.head, c = CGPoint(x: PortraitLayout.centerX, y: (PortraitLayout.top + l.chinY) / 2)
            for rect in [left, right, l.browRect(-1), l.browRect(1), l.noseRect, l.mouthRect] {
                for p in [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY),
                          CGPoint(x: rect.maxX, y: rect.maxY)] {
                    // The corner pushed 4 % away from the head's centre is still inside the outline.
                    let q = CGPoint(x: c.x + (p.x - c.x) * 1.04, y: c.y + (p.y - c.y) * 1.04)
                    #expect(head.contains(q), "\(g.genes) \(rect)")
                }
            }
            let features = [left, right, l.noseRect, l.mouthRect]
            for i in features.indices {
                for j in features.indices where j > i { #expect(!features[i].intersects(features[j]), "\(g.genes)") }
            }
            for side in [-1.0, 1.0] {
                let overlap = l.browRect(side).intersection(l.eyeRect(side))
                let share = overlap.isNull ? 0 : overlap.width * overlap.height / (l.eyeRect(side).width * l.eyeRect(side).height)
                #expect(share <= 0.10, "\(g.genes)")
            }
        }
    }

    @Test("ART-FACE-006 portraits render at 28, 64, 96 and 128 pt; at 28 pt the face keeps at least three tones")
    func legibility() {
        let genomes = (0..<240).map { PortraitGenome.make(seed: ArtSeed.crew(galaxySeed: 3, crewID: $0)) }
            + PortraitRole.allCases.map { PortraitGenome.fixed($0) }
        for g in genomes {
            for side in [28.0, 64, 96, 128] { #expect(Self.render(g, side: side).isNonEmpty(lo: 0.9, hi: 1, colors: 8)) }
            let pixels = Self.render(g, side: 28), face = PortraitLayout(g).faceRect
            var lums: [Int] = []
            let x0 = Int(face.minX * Double(pixels.width)), x1 = Int(face.maxX * Double(pixels.width))
            let y0 = Int(face.minY * Double(pixels.height)), y1 = Int(face.maxY * Double(pixels.height))
            for y in y0..<y1 {
                for x in x0..<x1 {
                    let i = (y * pixels.width + x) * 4
                    lums.append((Int(pixels.bytes[i]) * 299 + Int(pixels.bytes[i + 1]) * 587 + Int(pixels.bytes[i + 2]) * 114) / 1000)
                }
            }
            lums.sort()
            // Three tones, each on at least a tenth of the face: the darkest tenth, the middle and the lightest tenth are
            // each at least 8 of 255 brightness steps apart (a blob would have one tone).
            let dark = lums[lums.count / 10], middle = lums[lums.count / 2], bright = lums[lums.count * 9 / 10]
            #expect(middle - dark >= 8 && bright - middle >= 8, "\(g.genes): \(dark) \(middle) \(bright)")
        }
    }

    @Test("ART-FACE-007 a 96 pt portrait draws within 3 ms (median)")
    func budget() {
        let genomes = (0..<8).map { PortraitGenome.make(seed: UInt64($0) + 11) }
        func once() { for g in genomes { _ = Self.render(g, side: 96) } }
        once()
        var times: [Double] = []
        for _ in 0..<15 {
            let start = DispatchTime.now().uptimeNanoseconds
            once()
            times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6 / Double(genomes.count))
        }
        let median = times.sorted()[times.count / 2]
        #expect(median <= 3.0, "median \(median) ms")
    }

    @Test("ART-FACE-008 ART-FACE-011 the authored characters are fixed and distinct; the genome has at least 16 genes")
    func authoredCharacters() {
        #expect(PortraitGenome.geneCount >= 16 && PortraitGenome.make(seed: 1).genes.count == PortraitGenome.geneCount)
        let fixed = PortraitRole.allCases.map { PortraitGenome.fixed($0) }
        #expect(Set(fixed).count == PortraitRole.allCases.count)
        #expect(Set(fixed.map { Self.render($0, side: 96).fingerprint }).count == fixed.count)
        // At most a quarter of seeded faces wear facial hair, and seven in ten carry no mark.
        var rng = ArtRandom(seed: 99)
        let many = (0..<4000).map { _ in PortraitGenome.make(seed: rng.next()) }
        #expect(Double(many.filter { $0.facialHair > 0 }.count) / 4000 <= 0.28)
        #expect((0.64...0.76).contains(Double(many.filter { $0.mark == 0 }.count) / 4000))
        for g in many {
            #expect((-4...4).contains(g.cranium) && (-4...4).contains(g.jaw) && (-4...4).contains(g.chin) && (-4...4).contains(g.cheek))
            #expect(g.skin < PortraitGenome.skinCount && g.hairStyle < PortraitGenome.hairStyleCount && g.age < 3 && g.insignia < 4)
        }
    }
}
