// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecEngine

struct DotNetVector: Decodable {
    let seed: Int32
    let next: [Int]
    let belowMax: [Int]
    let below: [Int]
    let rangePairs: [String]
    let range: [Int]
    let doubles: [Double]
}

@Suite("RNG")
struct RNGTests {
    static let vectors: [DotNetVector] = (try? Fixtures.decode([DotNetVector].self, "harness/rng-dotnet.json")) ?? []

    @Test("DotNetRandom Next() matches .NET for harness seeds")
    func dotNetNext() throws {
        #expect(Self.vectors.count == 6)
        for v in Self.vectors {
            var r = DotNetRandom(seed: v.seed)
            #expect((0..<20).map { _ in r.nextInt() } == v.next, "seed \(v.seed)")
        }
    }

    @Test("DotNetRandom Next(0,max) incl. max 0 matches .NET")
    func dotNetBelow() {
        for v in Self.vectors {
            var r = DotNetRandom(seed: v.seed)
            #expect(v.belowMax.map { r.next(below: $0) } == v.below, "seed \(v.seed)")
        }
    }

    @Test("DotNetRandom Next(min,max) matches .NET")
    func dotNetRange() {
        for v in Self.vectors {
            var r = DotNetRandom(seed: v.seed)
            let got = v.rangePairs.map { pair -> Int in
                let parts = pair.split(separator: ",").compactMap { Int($0) }
                return r.next(in: parts[0], parts[1])
            }
            #expect(got == v.range, "seed \(v.seed)")
        }
    }

    @Test("DotNetRandom Sample() matches .NET NextDouble")
    func dotNetDoubles() {
        for v in Self.vectors {
            var r = DotNetRandom(seed: v.seed)
            #expect((0..<5).map { _ in r.sample() } == v.doubles, "seed \(v.seed)")
        }
    }
}
