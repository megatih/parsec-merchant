// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// AUD-037 / AUD-038 / AUD-039: the optional generative pad. Four detuned triangle/saw pad voices through a low-pass
/// whose cutoff drifts with a 0.05 Hz LFO, one sparse FM bell voice playing a pentatonic note every 4–12 s, and one
/// low pulse drone for the tension mood (6 music voices). Chords change every 8 s with a 2 s overlap; a mood change
/// fades out and back in over 3 s in total; enabling fades in over 2 s. When disabled (or silent and faded out) nothing
/// is rendered. Owned and driven by `SynthCore` on the render thread; it allocates nothing after `make`.
nonisolated struct MusicGenerator {
    static var padCount: Int { 4 }
    static var chordsPerMood: Int { 4 }
    static var scaleLength: Int { 5 }

    let sampleRate: Float
    /// [mood][chord][pad] frequencies, [mood][degree] bell scale, [mood] drone (0 = none), [mood] cutoff.
    let chords: UnsafeMutablePointer<Float>
    let scales: UnsafeMutablePointer<Float>
    let drones: UnsafeMutablePointer<Float>
    let cutoffs: UnsafeMutablePointer<Float>
    /// Per pad: [previous tri, previous saw, current tri, current saw].
    let oscillators: UnsafeMutablePointer<Oscillator>
    /// Per pad: previous and current frequency.
    let frequencies: UnsafeMutablePointer<Float>

    private(set) var isRunning = false
    private var mood = 0
    private var level: Float = 0
    private var levelGoal: Float = 0
    private var levelStep: Float = 0
    private var requestedAudible = false
    private var requestedMood = 0
    private var chordIndex = 0
    private var sampleInChord = 0
    private var crossfade: Float = 1
    private var filterL = StateVariableFilter()
    private var filterR = StateVariableFilter()
    private var cutoffLFO = LFO()
    private var bell = FMOperatorPair()
    private var bellFreq: Float = 0
    private var bellTime = 0
    private var bellActive = false
    private var samplesToBell = 0
    private var drone = Oscillator()
    private var droneLFO = LFO()
    private var rng: NoiseSource
    private var controlCounter = 0

    /// Allocates the tables (init time only). The table contents come from `MusicTables`.
    static func make(sampleRate: Double, seed: UInt32, chords chordValues: [Float], scales scaleValues: [Float],
                     drones droneValues: [Float], cutoffs cutoffValues: [Float]) -> MusicGenerator {
        func copy(_ values: [Float]) -> UnsafeMutablePointer<Float> {
            let p = UnsafeMutablePointer<Float>.allocate(capacity: max(1, values.count))
            p.initialize(repeating: 0, count: max(1, values.count))
            for i in 0..<values.count { p[i] = values[i] }
            return p
        }
        let osc = UnsafeMutablePointer<Oscillator>.allocate(capacity: padCount * 4)
        osc.initialize(repeating: Oscillator(), count: padCount * 4)
        let freqs = UnsafeMutablePointer<Float>.allocate(capacity: padCount * 2)
        freqs.initialize(repeating: 0, count: padCount * 2)
        return MusicGenerator(sampleRate: Float(sampleRate), chords: copy(chordValues), scales: copy(scaleValues),
                              drones: copy(droneValues), cutoffs: copy(cutoffValues), oscillators: osc,
                              frequencies: freqs, rng: NoiseSource(seed: seed))
    }

    func free() {
        chords.deallocate()
        scales.deallocate()
        drones.deallocate()
        cutoffs.deallocate()
        oscillators.deallocate()
        frequencies.deallocate()
    }

    private func chordNote(mood: Int, chord: Int, pad: Int) -> Float {
        chords[(mood * Self.chordsPerMood + chord) * Self.padCount + pad]
    }

    private mutating func fade(to goal: Float, seconds: Float) {
        levelGoal = goal
        levelStep = (goal - level) / max(1, seconds * sampleRate)
    }

    private mutating func enterMood(_ m: Int) {
        mood = m
        chordIndex = 0
        sampleInChord = 0
        crossfade = 1
        for p in 0..<Self.padCount {
            let f = chordNote(mood: m, chord: 0, pad: p)
            frequencies[p * 2] = f
            frequencies[p * 2 + 1] = f
        }
        samplesToBell = Int(4 * sampleRate)
    }

    /// Called once per render chunk with the requested state.
    mutating func update(enabled: Bool, mood requested: MusicMood) {
        requestedAudible = enabled && requested != .silent
        requestedMood = min(Int(requested.rawValue), 2)
        if !isRunning {
            guard requestedAudible else { return }
            isRunning = true
            level = 0
            enterMood(requestedMood)
            fade(to: 1, seconds: 2)
            return
        }
        if !requestedAudible {
            if levelGoal != 0 { fade(to: 0, seconds: enabled ? 3 : 0.5) }
        } else if requestedMood != mood {
            // Fade out; the render loop enters the new mood at silence and fades back in (3 s in total).
            if levelGoal != 0 { fade(to: 0, seconds: 1.5) }
        } else if levelGoal != 1 {
            fade(to: 1, seconds: 1.5)
        }
    }

    /// Renders `frames` stereo samples into `left`/`right` (overwriting).
    mutating func render(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>,
                         table: SineTable) {
        let inv = 1 / sampleRate
        let chordSamples = Int(8 * sampleRate)
        let overlapSamples = 2 * sampleRate
        let droneHz = drones[mood]
        for i in 0..<frames {
            // Level fades, mood switches and stopping.
            if levelStep != 0 {
                level += levelStep
                if (levelStep > 0 && level >= levelGoal) || (levelStep < 0 && level <= levelGoal) {
                    level = levelGoal
                    levelStep = 0
                }
            }
            if level <= 0 && levelStep == 0 && levelGoal == 0 {
                if requestedAudible && requestedMood != mood {
                    enterMood(requestedMood)
                    fade(to: 1, seconds: 1.5)
                } else if !requestedAudible {
                    isRunning = false
                    for j in i..<frames {
                        left[j] = 0
                        right[j] = 0
                    }
                    return
                }
            }
            // Chord changes every 8 s with a 2 s crossfade.
            sampleInChord += 1
            if sampleInChord >= chordSamples {
                sampleInChord = 0
                chordIndex = (chordIndex + 1) % Self.chordsPerMood
                for p in 0..<Self.padCount {
                    frequencies[p * 2] = frequencies[p * 2 + 1]
                    frequencies[p * 2 + 1] = chordNote(mood: mood, chord: chordIndex, pad: p)
                    oscillators[p * 4] = oscillators[p * 4 + 2]
                    oscillators[p * 4 + 1] = oscillators[p * 4 + 3]
                }
                crossfade = 0
            }
            if crossfade < 1 { crossfade = min(1, crossfade + 1 / overlapSamples) }
            // Filter cutoff drift (control rate).
            if controlCounter == 0 {
                let lfo = cutoffLFO.next(rate: 0.05, step: 64 * inv, table)
                let cutoff = cutoffs[mood] * exp2f(0.8 * lfo)
                filterL.set(cutoff: cutoff, q: 0.8, sampleRate: sampleRate)
                filterR.set(cutoff: cutoff, q: 0.8, sampleRate: sampleRate)
            }
            controlCounter = (controlCounter + 1) % 64
            var l: Float = 0
            var r: Float = 0
            for p in 0..<Self.padCount {
                let fPrev = frequencies[p * 2] * inv
                let fCur = frequencies[p * 2 + 1] * inv
                var prev: Float = 0
                if crossfade < 1 {
                    prev = oscillators[p * 4].triangle(fPrev) + 0.5 * oscillators[p * 4 + 1].saw(fPrev * 1.004)
                }
                let cur = oscillators[p * 4 + 2].triangle(fCur) + 0.5 * oscillators[p * 4 + 3].saw(fCur * 1.004)
                let v = (prev * (1 - crossfade) + cur * crossfade) * 0.07
                let w = Float(p) / Float(Self.padCount - 1)
                l += v * (1.0 - 0.5 * w)
                r += v * (0.5 + 0.5 * w)
            }
            l = filterL.process(l, mode: .lowPass)
            r = filterR.process(r, mode: .lowPass)
            // The sparse bell.
            samplesToBell -= 1
            if samplesToBell <= 0 {
                let degree = min(Self.scaleLength - 1, Int(rng.unit() * Float(Self.scaleLength)))
                bellFreq = scales[mood * Self.scaleLength + degree]
                bellTime = 0
                bellActive = true
                bell = FMOperatorPair()
                samplesToBell = Int((4 + 8 * rng.unit()) * sampleRate)
            }
            if bellActive {
                let t = Float(bellTime) * inv
                let env = exp2f(-6.643_856 * t / 2.5)
                let b = bell.sample(bellFreq * inv, ratio: 3.5, index: 1.5 * env, table) * env * 0.09
                l += b * 0.6
                r += b
                bellTime += 1
                if t >= 2.5 { bellActive = false }
            }
            // The tension drone: a low tone pulsing at 1 Hz.
            if droneHz > 0 {
                let pulse = 0.6 + 0.4 * droneLFO.next(rate: 1, step: inv, table)
                let d = (drone.sine(droneHz * inv, table)) * pulse * 0.12
                l += d
                r += d
            }
            left[i] = l * level
            right[i] = r * level
        }
    }
}
