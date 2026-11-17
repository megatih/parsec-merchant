// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Testing
@testable import ParsecAudio

@Suite("Cue catalog")
struct CueCatalogTests {
    /// Covers the recipe bullets AUD-013, AUD-014, AUD-015, AUD-016, AUD-017, AUD-018, AUD-019, AUD-020, AUD-021,
    /// AUD-022, AUD-023, AUD-024, AUD-025, AUD-026, AUD-027, AUD-028, AUD-029 and AUD-030.
    @Test("AUD-013…030 the catalog has one case per recipe bullet, in spec order, with its nominal length")
    func catalogOrder() {
        let expected: [SoundCue] = [.uiTick, .uiConfirm, .rejected, .coinIn, .coinOut, .coinLoss, .jettison, .fuelFill,
                                    .repair, .equip, .shipPurchase, .warpDeparture, .arrival, .encounterStinger, .laser,
                                    .shieldHit, .hullHit, .explosion, .powerDown, .escape, .lowHullAlarm, .arrestSiren,
                                    .notice, .questChime, .pickup, .drink, .gameEndFanfare, .newspaperRustle,
                                    .achievementChime, .tribbleSqueak]
        #expect(SoundCue.allCases == expected)
        #expect(SoundCue.encounterStinger.variantCount == 5)
        #expect(SoundCue.laser.variantCount == 6)
        #expect(SoundCue.warpDeparture.variantCount == 2)
        #expect(SoundCue.gameEndFanfare.variantCount == 2)
        let catalog = CueRecipes.build()
        #expect(catalog.recipes.count == SoundCue.allCases.reduce(0) { $0 + $1.variantCount })
        // Every recipe's length is its nominal duration (AUD-013…030), up to the reverb tail of warp and achievement.
        for cue in SoundCue.allCases {
            for v in 0..<cue.variantCount {
                let recipe = catalog.recipes[catalog.firstRecipe[Int(cue.rawValue)] + v]
                let nominal = cue.nominalDuration(variant: UInt8(v))
                #expect(abs(Double(recipe.length) - nominal) <= nominal * 0.1 + 0.002, "\(cue) v\(v)")
            }
        }
    }

    @Test("AUD-005 cue priorities")
    func priorities() {
        #expect([SoundCue.explosion, .lowHullAlarm, .arrestSiren, .gameEndFanfare].allSatisfy { $0.priority == 3 })
        #expect([SoundCue.laser, .shieldHit, .hullHit, .powerDown, .escape, .encounterStinger].allSatisfy { $0.priority == 2 })
        #expect([SoundCue.uiTick, .uiConfirm, .rejected].allSatisfy { $0.priority == 0 })
        #expect([SoundCue.coinIn, .warpDeparture, .notice, .questChime].allSatisfy { $0.priority == 1 })
    }

    @Test("AUD-016 amountPitch rises 2 semitones per decade, capped at 12")
    func amountPitchValues() {
        #expect(amountPitch(0) == 0)
        #expect(amountPitch(9) == 0)
        #expect(amountPitch(10) == 2)
        #expect(amountPitch(-250) == 4)
        #expect(amountPitch(99_999) == 8)
        #expect(amountPitch(1_000_000) == 12)
        #expect(amountPitch(Int.max) == 12)
    }

    @Test("AUD-047 every cue and variant: bit-identical, peak 0.05…1, finite, nominal duration ±10%, then silent",
          arguments: [44_100.0, 48_000.0])
    func everyCueRenders(rate: Double) {
        AudioTestSupport.every { cue, v in
            let m = AudioTestSupport.measure(cue, variant: v, rate: rate)
            let again = AudioTestSupport.render(cue, variant: v, rate: rate)
            #expect(m.left == again.left && m.right == again.right, "\(cue) v\(v) is deterministic")
            #expect(m.allFinite, "\(cue) v\(v) finite")
            #expect(m.peak >= 0.05 && m.peak <= 1.0, "\(cue) v\(v) peak \(m.peak)")
            let nominal = cue.nominalDuration(variant: v)
            #expect(abs(m.duration - nominal) <= nominal * 0.1, "\(cue) v\(v) duration \(m.duration) vs \(nominal)")
            #expect(m.quietAfter, "\(cue) v\(v) below −60 dBFS 100 ms after its end")
        }
    }

    @Test("AUD-023 AUD-047 the six laser timbres are pairwise distinct")
    func lasersDistinct() {
        let renders = LaserVariant.allCases.map { AudioTestSupport.mono(AudioTestSupport.render(.laser, variant: $0.rawValue)) }
        for i in 0..<renders.count {
            for j in (i + 1)..<renders.count {
                #expect(AudioTestSupport.correlation(renders[i], renders[j]) < 0.9, "laser \(i) vs \(j)")
            }
        }
    }

    @Test("AUD-022 AUD-047 the five encounter stingers are pairwise distinct")
    func stingersDistinct() {
        let renders = StingerVariant.allCases.map {
            AudioTestSupport.mono(AudioTestSupport.render(.encounterStinger, variant: $0.rawValue))
        }
        for i in 0..<renders.count {
            for j in (i + 1)..<renders.count {
                #expect(AudioTestSupport.correlation(renders[i], renders[j]) < 0.9, "stinger \(i) vs \(j)")
            }
        }
    }

    @Test("AUD-020 AUD-029 the wormhole and moon variants differ from the defaults")
    func variantsDiffer() {
        let warp = AudioTestSupport.mono(AudioTestSupport.render(.warpDeparture, variant: 0))
        let wormhole = AudioTestSupport.mono(AudioTestSupport.render(.warpDeparture, variant: 1))
        // The shared sub-bass swell dominates the correlation; the variant must still change the sound audibly.
        let difference = zip(warp, wormhole).map { $0 - $1 }
        func rms(_ x: [Float]) -> Float { (x.reduce(0) { $0 + $1 * $1 } / Float(max(1, x.count))).squareRoot() }
        #expect(rms(difference) > rms(warp) * 0.2)
        let standard = AudioTestSupport.render(.gameEndFanfare, variant: 0)
        let moon = AudioTestSupport.render(.gameEndFanfare, variant: 1)
        #expect(standard.left != moon.left)
    }

    @Test("AUD-025 escape sweeps towards the escaping ship's outer edge")
    func escapePanSweep() {
        let core = SynthCore(sampleRate: 48_000, seed: 3)
        let (l, r) = core.renderOffline(requests: [CueRequest(cue: .escape, pan: 0.4)], seconds: 0.5)
        func energy(_ x: [Float], _ range: Range<Int>) -> Float { range.reduce(0) { $0 + x[$1] * x[$1] } }
        let early = 0..<4800, late = 19_200..<24_000
        let earlyRatio = energy(r, early) / max(1e-9, energy(l, early))
        let lateRatio = energy(r, late) / max(1e-9, energy(l, late))
        #expect(lateRatio > earlyRatio * 2)
    }

    @Test("AUD-016 coin cues transpose by the request's pitch")
    func coinPitch() {
        let core = SynthCore(sampleRate: 48_000, seed: 1)
        let low = AudioTestSupport.mono(core.renderOffline(requests: [CueRequest(cue: .coinIn)], seconds: 0.2))
        let core2 = SynthCore(sampleRate: 48_000, seed: 1)
        let high = AudioTestSupport.mono(core2.renderOffline(requests: [CueRequest(cue: .coinIn, pitchSemitones: 12)],
                                                             seconds: 0.2))
        func crossings(_ x: [Float]) -> Int { (1..<x.count).filter { (x[$0 - 1] < 0) != (x[$0] < 0) }.count }
        #expect(Double(crossings(high)) > Double(crossings(low)) * 1.5)
    }
}
