// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Testing
@testable import ParsecAudio

@Suite("Generative music")
struct MusicTests {
    /// Renders `segments` of (mood, seconds) with music on.
    static func render(seed: UInt64, rate: Double = 48_000, _ segments: [(MusicMood, Double)], enabled: Bool = true) -> [Float] {
        let core = SynthCore(sampleRate: rate, seed: seed)
        var out: [Float] = []
        for (mood, seconds) in segments {
            core.setMusic(enabled: enabled, mood: mood)
            out += core.renderOffline(requests: [], seconds: seconds).left
        }
        return out
    }

    static func rms(_ x: ArraySlice<Float>) -> Float {
        guard !x.isEmpty else { return 0 }
        return (x.reduce(0) { $0 + $1 * $1 } / Float(x.count)).squareRoot()
    }

    @Test("AUD-037 same seed, mood sequence and rate give bit-identical music; the seed changes the bells")
    func determinism() {
        let plan: [(MusicMood, Double)] = [(.calm, 9), (.travel, 5), (.tension, 6)]
        let a = Self.render(seed: 11, plan)
        let b = Self.render(seed: 11, plan)
        let c = Self.render(seed: 12, plan)
        #expect(a == b)
        #expect(a != c)
        #expect(Self.rms(a[48_000 * 3..<48_000 * 8]) > 0.005)
        #expect(a.allSatisfy { $0.isFinite && abs($0) <= 1 })
    }

    @Test("AUD-038 moods sound different; tension carries the low pulse; silent fades out completely")
    func moods() {
        let calm = Array(Self.render(seed: 1, [(.calm, 4)])[48_000 * 2..<48_000 * 4])
        let tension = Array(Self.render(seed: 1, [(.tension, 4)])[48_000 * 2..<48_000 * 4])
        #expect(AudioTestSupport.correlation(calm, tension) < 0.9)
        let silent = Self.render(seed: 1, [(.calm, 3), (.silent, 4)])
        #expect(silent.suffix(4800).allSatisfy { $0 == 0 })
        // A mood change fades through silence without clicks (3 s in total).
        let change = Self.render(seed: 1, [(.calm, 3), (.tension, 4)])
        let maxStep = (1..<change.count).map { abs(change[$0] - change[$0 - 1]) }.max() ?? 1
        #expect(maxStep < 0.05)
        let dip = Self.rms(change[48_000 * 4 + 24_000..<48_000 * 4 + 26_400])
        #expect(dip < Self.rms(change[48_000 * 2..<48_000 * 3]))
        #expect(Self.rms(change[48_000 * 6..<48_000 * 7]) > 0.005)
    }

    @Test("AUD-039 music is off by default and renders nothing; enabling fades in over 2 s")
    func offByDefault() {
        let core = SynthCore(sampleRate: 48_000, seed: 1)
        let idle = core.renderOffline(requests: [], seconds: 1)
        #expect(idle.left.allSatisfy { $0 == 0 } && idle.right.allSatisfy { $0 == 0 })
        let on = Self.render(seed: 1, [(.calm, 3)])
        #expect(Self.rms(on[0..<4800]) < Self.rms(on[96_000..<100_800]) * 0.3)
        // Music gain follows overall² × music².
        let core2 = SynthCore(sampleRate: 48_000, seed: 1)
        core2.setGains(overall: 1, effects: 1, music: 0)
        core2.setMusic(enabled: true, mood: .calm)
        let muted = core2.renderOffline(requests: [], seconds: 1)
        #expect(muted.left.suffix(24_000).allSatisfy { $0 == 0 })
        // Disabling stops rendering after a short fade.
        let core3 = SynthCore(sampleRate: 48_000, seed: 1)
        core3.setMusic(enabled: true, mood: .calm)
        _ = core3.renderOffline(requests: [], seconds: 3)
        core3.setMusic(enabled: false, mood: .calm)
        let stopped = core3.renderOffline(requests: [], seconds: 1)
        #expect(stopped.left.suffix(4800).allSatisfy { $0 == 0 })
    }
}
