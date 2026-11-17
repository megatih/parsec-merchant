// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// AUD-013…030: the recipe of every cue variant, as layers of oscillators, noise, envelopes and filters. Built once by
/// `SynthCore.init` (allocation is fine here) and copied into preallocated tables for the render thread.
enum CueRecipes {
    struct Catalog {
        var layers: [LayerSpec] = []
        var recipes: [RecipeSpec] = []
        /// Index of variant 0 of each cue in `recipes`, in `SoundCue` order.
        var firstRecipe: [Int] = []
        var variantCounts: [Int] = []
    }

    /// Recipe-level options.
    struct Options {
        var reverbSend: Float = 0
        var panSweep = false
    }

    static func build() -> Catalog {
        var c = Catalog()
        for cue in SoundCue.allCases {
            c.firstRecipe.append(c.recipes.count)
            c.variantCounts.append(cue.variantCount)
            for v in 0..<cue.variantCount {
                let (layers, options) = recipe(cue, variant: UInt8(v))
                let length = layers.map(\.end).max() ?? 0.01
                c.recipes.append(RecipeSpec(firstLayer: c.layers.count, layerCount: layers.count, length: length,
                                            priority: cue.priority, reverbSend: options.reverbSend,
                                            panSweep: options.panSweep))
                c.layers.append(contentsOf: layers)
            }
        }
        return c
    }

    // MARK: Helpers

    static func db(_ value: Float) -> Float { powf(10, value / 20) }
    static func octaves(_ from: Float, _ to: Float) -> Float { log2f(to / from) }
    static func semitones(_ f: Float, _ s: Float) -> Float { f * powf(2, s / 12) }

    /// An FM bell strike.
    static func bell(_ freq: Float, start: Float = 0, decay: Float, ratio: Float = 3.5, index: Float = 2,
                     gain: Float = 0.35) -> LayerSpec {
        LayerSpec(wave: .fm, start: start, attack: 0.001, hold: 0, decay: decay, freq: freq, fmRatio: ratio,
                  fmIndexStart: index, fmIndexEnd: 0, gain: gain)
    }

    /// A short beep of any wave.
    static func beep(_ wave: LayerWave, _ freq: Float, start: Float, length: Float, gain: Float) -> LayerSpec {
        LayerSpec(wave: wave, start: start, attack: 0.003, hold: length * 0.7, decay: length * 0.3 - 0.003,
                  freq: freq, gain: gain)
    }

    /// A deterministic generator for the "seeded" recipe details (bubbles, rustle gaps).
    struct RecipeRandom {
        var state: UInt64
        mutating func unit() -> Float {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(state >> 40) / Float(1 << 24)
        }
    }

    // MARK: Recipes

    static func recipe(_ cue: SoundCue, variant: UInt8) -> ([LayerSpec], Options) {
        switch cue {
        case .uiTick:
            return ([LayerSpec(wave: .sine, attack: 0.0005, decay: 0.0245, freq: 2400, gain: db(-18))], Options())
        case .uiConfirm:
            return ([LayerSpec(wave: .sine, attack: 0.002, hold: 0.03, decay: 0.028, freq: 880, gain: 0.35),
                     LayerSpec(wave: .sine, start: 0.06, attack: 0.002, hold: 0.03, decay: 0.028, freq: 1320, gain: 0.35)],
                    Options())
        case .rejected:
            return ([LayerSpec(wave: .triangle, attack: 0.005, hold: 0.045, decay: 0.04, freq: 220, gain: 0.45)], Options())
        case .coinIn:
            return ([bell(1568, decay: 0.38, gain: 0.3), bell(1568, start: 0.07, decay: 0.38, gain: 0.3)], Options())
        case .coinOut:
            return ([bell(semitones(1568, -5), decay: 0.30, gain: 0.35)], Options())
        case .coinLoss:
            return ([bell(semitones(1568, -7), decay: 0.30, index: 0.9, gain: 0.35),
                     bell(semitones(1568, -10), start: 0.10, decay: 0.30, index: 0.9, gain: 0.35)], Options())
        case .jettison:
            return ([LayerSpec(wave: .noise, attack: 0.005, hold: 0.12, decay: 0.225, filter: .lowPass, cutoff: 2000,
                               cutoffOctaves: octaves(2000, 300), cutoffTime: 0.35, q: 0.9, gain: 0.8),
                     LayerSpec(wave: .sine, attack: 0.002, decay: 0.118, freq: 60, gain: 0.5)], Options())
        case .fuelFill:
            return ([LayerSpec(wave: .noise, attack: 0.05, hold: 0.25, decay: 0.10, filter: .bandPass, cutoff: 400,
                               cutoffOctaves: octaves(400, 1200), cutoffTime: 0.4, q: 4, gain: 0.9)], Options())
        case .repair:
            return ([bell(420, decay: 0.09, ratio: 1.41, index: 4, gain: 0.35),
                     bell(420, start: 0.12, decay: 0.09, ratio: 1.41, index: 4, gain: 0.35)], Options())
        case .equip:
            return ([LayerSpec(wave: .noise, attack: 0.0005, decay: 0.012, filter: .highPass, cutoff: 3000, gain: 0.3),
                     LayerSpec(wave: .sine, attack: 0.002, decay: 0.098, freq: 140, gain: 0.45),
                     bell(1760, start: 0.05, decay: 0.20, index: 1.5, gain: 0.3)], Options())
        case .shipPurchase:
            return ([bell(523.25, decay: 0.66, gain: 0.28), bell(659.26, start: 0.12, decay: 0.66, gain: 0.28),
                     bell(783.99, start: 0.24, decay: 0.66, gain: 0.28)], Options())
        case .warpDeparture:
            return (warp(wormhole: variant == WarpVariant.wormhole.rawValue), Options(reverbSend: 0.35))
        case .arrival:
            return ([bell(392, decay: 0.45, ratio: 2, index: 1, gain: 0.35),
                     bell(587.33, start: 0.15, decay: 0.45, ratio: 2, index: 1, gain: 0.35)], Options())
        case .encounterStinger:
            return (stinger(StingerVariant(rawValue: variant) ?? .pirate), Options())
        case .laser:
            return (laser(LaserVariant(rawValue: variant) ?? .pulse), Options())
        case .shieldHit:
            return ([LayerSpec(wave: .noise, attack: 0.002, hold: 0.05, decay: 0.198, filter: .bandPass, cutoff: 1800,
                               q: 12, gain: 1.4),
                     LayerSpec(wave: .sine, attack: 0.002, hold: 0.05, decay: 0.148, freq: 600, vibratoRate: 25,
                               vibratoSemitones: 1, gain: 0.3)], Options())
        case .hullHit:
            return ([LayerSpec(wave: .noise, attack: 0.001, hold: 0.03, decay: 0.119, filter: .lowPass, cutoff: 1200,
                               gain: 0.8),
                     LayerSpec(wave: .sine, attack: 0.002, decay: 0.148, freq: 80, gain: 0.55)], Options())
        case .explosion:
            return ([LayerSpec(wave: .noise, attack: 0.005, hold: 0.75, decay: 0.445, filter: .lowPass, cutoff: 4000,
                               cutoffOctaves: octaves(4000, 120), cutoffTime: 1.2, q: 0.8, gain: 0.9),
                     LayerSpec(wave: .sine, attack: 0.01, decay: 0.59, freq: 40, gain: 0.5)], Options())
        case .powerDown:
            return ([LayerSpec(wave: .sine, attack: 0.005, hold: 0.3, decay: 0.295, freq: 440,
                               sweepOctaves: octaves(440, 55), sweepTime: 0.6, gain: 0.45)], Options())
        case .escape:
            return ([LayerSpec(wave: .saw, attack: 0.005, hold: 0.2, decay: 0.295, freq: 300,
                               sweepOctaves: octaves(300, 180), sweepTime: 0.5, filter: .lowPass, cutoff: 2500,
                               gain: 0.4)], Options(panSweep: true))
        case .lowHullAlarm:
            return ((0..<4).map { i in
                var b = beep(.square, i % 2 == 0 ? 880 : 660, start: Float(i) * 0.27, length: 0.12, gain: 0.3)
                b.filter = .lowPass
                b.cutoff = 3000
                return b
            }, Options())
        case .arrestSiren:
            return ([LayerSpec(wave: .sine, attack: 0.05, hold: 1.35, decay: 0.2, freq: 774.6, vibratoRate: 1.25,
                               vibratoSemitones: 4.42, vibratoPhase: -0.25, gain: 0.45),
                     LayerSpec(wave: .triangle, attack: 0.05, hold: 1.35, decay: 0.2, freq: 774.6, vibratoRate: 1.25,
                               vibratoSemitones: 4.42, vibratoPhase: -0.25, gain: 0.12)], Options())
        case .notice:
            return ([beep(.triangle, 784, start: 0, length: 0.15, gain: 0.4),
                     beep(.triangle, 659.26, start: 0.15, length: 0.15, gain: 0.4)], Options())
        case .questChime:
            return ([523.25, 587.33, 659.26, 783.99].enumerated().map { i, f in
                bell(f, start: Float(i) * 0.12, decay: 0.44, gain: 0.26)
            }, Options())
        case .pickup:
            return ([LayerSpec(wave: .sine, attack: 0.003, hold: 0.06, decay: 0.057, freq: 500, sweepOctaves: 1,
                               sweepTime: 0.12, gain: 0.4)], Options())
        case .drink:
            var r = RecipeRandom(state: 0xD12_1C)
            return ((0..<6).map { i in
                let start = i == 5 ? 0.43 : Float(i) * 0.075 + r.unit() * 0.03
                return LayerSpec(wave: .sine, start: start, attack: 0.004, hold: 0.02, decay: 0.046,
                                 freq: 300 + 400 * r.unit(), sweepOctaves: 0.5, sweepTime: 0.05, gain: 0.35)
            }, Options())
        case .gameEndFanfare:
            return (fanfare(moon: variant == FanfareVariant.moon.rawValue), Options())
        case .newspaperRustle:
            var r = RecipeRandom(state: 0x9E_55)
            let starts: [Float] = [0, 0.11 + 0.02 * r.unit(), 0.24 + 0.02 * r.unit(), 0.37]
            let lengths: [Float] = [0.06, 0.04 + 0.02 * r.unit(), 0.08, 0.08]
            return ((0..<4).map { i in
                LayerSpec(wave: .noise, start: starts[i], attack: 0.004, hold: lengths[i] * 0.4,
                          decay: lengths[i] * 0.6 - 0.004, filter: .highPass, cutoff: 2500, gain: 0.5)
            }, Options())
        case .achievementChime:
            return ([bell(1046.5, decay: 0.87, gain: 0.22), bell(1318.5, decay: 0.87, gain: 0.22),
                     bell(1568, decay: 0.87, gain: 0.22),
                     LayerSpec(wave: .sine, start: 0.1, attack: 0.1, hold: 0.1, decay: 0.6, freq: 4186,
                               tremoloRate: 9, tremoloDepth: 0.6, gain: 0.06)], Options(reverbSend: 0.25))
        case .tribbleSqueak:
            return ([LayerSpec(wave: .sine, attack: 0.005, hold: 0.07, decay: 0.03, freq: 1400,
                               sweepOctaves: octaves(1400, 2000), sweepTime: 0.09, vibratoRate: 18, vibratoSemitones: 0.6,
                               gain: 0.35),
                     LayerSpec(wave: .sine, start: 0.085, attack: 0.02, hold: 0.03, decay: 0.045, freq: 2000,
                               sweepOctaves: octaves(2000, 1600), sweepTime: 0.09, vibratoRate: 18, vibratoSemitones: 0.6,
                               gain: 0.35)], Options())
        }
    }

    static func warp(wormhole: Bool) -> [LayerSpec] {
        var sweep = LayerSpec(wave: .saw, attack: 0.05, hold: 0.55, decay: 0.3, freq: 110, sweepOctaves: 3,
                              sweepTime: 0.9, filter: .lowPass, cutoff: 6000, cutoffOctaves: octaves(6000, 500),
                              cutoffTime: 0.9, q: 1.2, gain: 0.4)
        var whoosh = LayerSpec(wave: .noise, attack: 0.3, decay: 0.6, filter: .bandPass, cutoff: 800,
                               cutoffOctaves: octaves(800, 3000), cutoffTime: 0.9, q: 1.5, gain: 0.5)
        if wormhole {
            sweep.detune = 1.5
            sweep.tremoloRate = 6
            sweep.tremoloDepth = 0.5
            whoosh.tremoloRate = 6
            whoosh.tremoloDepth = 0.4
        }
        let sub = LayerSpec(wave: .sine, attack: 0.4, hold: 0.3, decay: 0.7, freq: 45, gain: 0.6)
        return [sweep, whoosh, sub]
    }

    static func stinger(_ v: StingerVariant) -> [LayerSpec] {
        switch v {
        case .pirate:
            return [LayerSpec(wave: .saw, attack: 0.01, hold: 0.25, decay: 0.24, freq: 110, detune: 117.0 / 110.0,
                              filter: .lowPass, cutoff: 1200, gain: 0.55)]
        case .police:
            return (0..<4).map { i in beep(.square, i % 2 == 0 ? 660 : 880, start: Float(i) * 0.1, length: 0.1, gain: 0.25) }
        case .trader:
            return [bell(523, decay: 0.35, gain: 0.4)]
        case .alien:
            return [LayerSpec(wave: .sine, attack: 0.05, hold: 0.35, decay: 0.3, freq: 300, ringHz: 47, gain: 0.55)]
        case .special:
            return [1046.5, 1174.7, 1318.5, 1568, 1760].enumerated().map { i, f in
                bell(f, start: Float(i) * 0.06, decay: 0.16, gain: 0.25)
            }
        }
    }

    static func laser(_ v: LaserVariant) -> [LayerSpec] {
        switch v {
        case .pulse:
            return [LayerSpec(wave: .square, attack: 0.001, hold: 0.02, decay: 0.099, freq: 1200, sweepOctaves: -2,
                              sweepTime: 0.12, gain: 0.3)]
        case .beam:
            return [LayerSpec(wave: .saw, attack: 0.005, hold: 0.12, decay: 0.095, freq: 900,
                              sweepOctaves: octaves(900, 500), sweepTime: 0.22, vibratoRate: 9, vibratoSemitones: 0.7,
                              gain: 0.35)]
        case .military:
            return military(length: 0.2)
        case .morgans:
            var layers = military(length: 0.26)
            layers.append(LayerSpec(wave: .sine, attack: 0.002, hold: 0.1, decay: 0.158, freq: 350,
                                    sweepOctaves: octaves(350, 100), sweepTime: 0.26, gain: 0.4))
            return layers
        case .photonDisruptor:
            return [LayerSpec(wave: .sine, attack: 0.002, hold: 0.1, decay: 0.078, freq: 200, sweepOctaves: 3,
                              sweepTime: 0.18, ringHz: 220, gain: 0.5)]
        case .quantumDisruptor:
            return [LayerSpec(wave: .noise, attack: 0.002, hold: 0.1, decay: 0.138, filter: .bandPass, cutoff: 3000,
                              cutoffOctaves: octaves(3000, 600), cutoffTime: 0.24, q: 8, gain: 1.6),
                    LayerSpec(wave: .crackle, attack: 0.002, hold: 0.1, decay: 0.138, gain: 0.25)]
        }
    }

    static func military(length: Float) -> [LayerSpec] {
        [LayerSpec(wave: .saw, attack: 0.002, hold: length * 0.4, decay: length * 0.6 - 0.002, freq: 700, sweepOctaves: octaves(700, 200),
                   sweepTime: length, detune: 1.012, gain: 0.35),
         LayerSpec(wave: .noise, attack: 0.001, decay: length * 0.75, filter: .lowPass, cutoff: 3000, gain: 0.2)]
    }

    static func fanfare(moon: Bool) -> [LayerSpec] {
        let notes: [(Float, Float, Float)] = [(196, 0, 0.25), (261.63, 0.25, 0.25), (329.63, 0.5, 0.25),
                                              (392, 0.75, 0.25), (329.63, 1.0, 0.2), (523.25, 1.2, 0.8)]
        var layers = notes.map { f, start, length in
            LayerSpec(wave: .saw, start: start, attack: 0.02, hold: length * 0.6, decay: length * 0.4 - 0.02, freq: f,
                      detune: 1.005, filter: .lowPass, cutoff: 1800, q: 0.9, gain: 0.32)
        }
        if moon {
            layers += [2093, 2637, 3136].enumerated().map { i, f in
                bell(f, start: 1.3 + Float(i) * 0.12, decay: 0.45, gain: 0.12)
            }
        }
        return layers
    }
}

/// AUD-037 / AUD-038: the chord tables of the generative music (frequencies in Hz).
enum MusicTables {
    /// [mood][chord][pad] for calm (I–vi–IV–V with sevenths), travel (suspended / Lydian) and tension (minor).
    static let chords: [Float] = [
        // calm: Cmaj7, Am7, Fmaj7, Gmaj7
        130.81, 164.81, 196.00, 246.94, 110.00, 130.81, 164.81, 196.00,
        87.31, 110.00, 130.81, 164.81, 98.00, 123.47, 146.83, 185.00,
        // travel: Dsus2, Esus4, Cmaj7♯11, Asus4
        146.83, 164.81, 220.00, 293.66, 164.81, 220.00, 246.94, 293.66,
        130.81, 164.81, 185.00, 246.94, 110.00, 146.83, 164.81, 220.00,
        // tension: Am, F, Dm, E
        110.00, 130.81, 164.81, 220.00, 87.31, 110.00, 130.81, 174.61,
        146.83, 174.61, 220.00, 293.66, 82.41, 103.83, 123.47, 164.81,
    ]
    /// [mood][degree] pentatonic bell notes.
    static let scales: [Float] = [
        523.25, 587.33, 659.26, 783.99, 880.00,
        587.33, 659.26, 739.99, 880.00, 987.77,
        440.00, 523.25, 587.33, 659.26, 783.99,
    ]
    /// [mood] drone frequency (tension only).
    static let drones: [Float] = [0, 0, 55]
    /// [mood] base low-pass cutoff (travel is brighter).
    static let cutoffs: [Float] = [900, 1500, 700]
}
