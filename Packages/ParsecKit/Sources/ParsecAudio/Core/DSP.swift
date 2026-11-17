// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

// AUD-004: the synthesis building blocks. All are value types with in-place `mutating` sample functions; none of
// them allocates. Buffers (sine table, delay lines) are allocated by `SynthCore.init` and freed in its `deinit`.

/// A 4096-point sine table with linear interpolation, read with a phase in cycles.
nonisolated struct SineTable {
    static var size: Int { 4096 }
    let table: UnsafeMutablePointer<Float>

    /// Allocates and fills the table (init time only).
    static func make() -> SineTable {
        let p = UnsafeMutablePointer<Float>.allocate(capacity: size + 1)
        for i in 0...size {
            p[i] = Float(sin(2 * Double.pi * Double(i) / Double(size)))
        }
        return SineTable(table: p)
    }

    func free() { table.deallocate() }

    /// sin(2π·phase) for any finite phase.
    @inline(__always)
    func sine(_ phase: Float) -> Float {
        var p = phase - phase.rounded(.down)
        if !(p >= 0 && p < 1) { p = 0 }
        let x = p * Float(Self.size)
        let i = Int(x)
        let f = x - Float(i)
        let a = table[i]
        return a + (table[i + 1] - a) * f
    }
}

/// Phase accumulator with band-limited (PolyBLEP) saw and square, and naive triangle.
nonisolated struct Oscillator {
    var phase: Float = 0

    @inline(__always)
    static func polyBLEP(_ t: Float, _ dt: Float) -> Float {
        if t < dt {
            let x = t / dt
            return x + x - x * x - 1
        } else if t > 1 - dt {
            let x = (t - 1) / dt
            return x * x + x + x + 1
        }
        return 0
    }

    @inline(__always)
    mutating func advance(_ dt: Float) {
        phase += dt
        if phase >= 1 { phase -= phase.rounded(.down) }
    }

    @inline(__always)
    mutating func saw(_ dt: Float) -> Float {
        let v = 2 * phase - 1 - Self.polyBLEP(phase, dt)
        advance(dt)
        return v
    }

    @inline(__always)
    mutating func square(_ dt: Float) -> Float {
        var v: Float = phase < 0.5 ? 1 : -1
        v += Self.polyBLEP(phase, dt)
        var shifted = phase + 0.5
        if shifted >= 1 { shifted -= 1 }
        v -= Self.polyBLEP(shifted, dt)
        advance(dt)
        return v
    }

    @inline(__always)
    mutating func triangle(_ dt: Float) -> Float {
        let v = 1 - 4 * abs(phase - 0.5)
        advance(dt)
        return v
    }

    @inline(__always)
    mutating func sine(_ dt: Float, _ table: SineTable) -> Float {
        let v = table.sine(phase)
        advance(dt)
        return v
    }
}

/// Two-operator FM: a sine carrier whose phase is modulated by a sine at `ratio` × the carrier frequency.
nonisolated struct FMOperatorPair {
    var carrier = Oscillator()
    var modulator = Oscillator()

    @inline(__always)
    mutating func sample(_ dt: Float, ratio: Float, index: Float, _ table: SineTable) -> Float {
        let m = table.sine(modulator.phase)
        let v = table.sine(carrier.phase + index * m * 0.159_154_94)
        carrier.advance(dt)
        modulator.advance(dt * ratio)
        return v
    }
}

/// Deterministic white noise (xorshift32).
nonisolated struct NoiseSource {
    var state: UInt32

    init(seed: UInt32) { state = seed == 0 ? 0x9E37_79B9 : seed }

    @inline(__always)
    mutating func next() -> Float {
        var x = state
        x ^= x << 13
        x ^= x >> 17
        x ^= x << 5
        state = x
        return Float(Int32(bitPattern: x)) * (1.0 / 2_147_483_648.0)
    }

    /// A value in [0, 1).
    @inline(__always)
    mutating func unit() -> Float { next() * 0.5 + 0.5 }
}

/// Topology-preserving state-variable filter (low, band and high outputs) with a modulatable cutoff.
nonisolated struct StateVariableFilter {
    enum Mode: UInt8, Sendable, BitwiseCopyable { case none, lowPass, highPass, bandPass }
    var ic1: Float = 0
    var ic2: Float = 0
    var k: Float = 1.4
    var a1: Float = 0
    var a2: Float = 0
    var a3: Float = 0

    @inline(__always)
    mutating func set(cutoff: Float, q: Float, sampleRate: Float) {
        let fc = min(max(cutoff, 10), sampleRate * 0.45)
        let g = tanf(Float.pi * fc / sampleRate)
        k = 1 / max(q, 0.1)
        a1 = 1 / (1 + g * (g + k))
        a2 = g * a1
        a3 = g * a2
    }

    @inline(__always)
    mutating func process(_ v0: Float, mode: Mode) -> Float {
        let v3 = v0 - ic2
        let v1 = a1 * ic1 + a2 * v3
        let v2 = ic2 + a2 * ic1 + a3 * v3
        ic1 = 2 * v1 - ic1
        ic2 = 2 * v2 - ic2
        switch mode {
        case .none: return v0
        case .lowPass: return v2
        case .bandPass: return k * v1
        case .highPass: return v0 - k * v1 - v2
        }
    }
}

/// Attack–hold–exponential decay envelope: linear attack, flat hold, then a decay that reaches −40 dB exactly at its
/// end, with a 2 ms linear fade so the end is click-free. Times in seconds.
nonisolated struct DecayEnvelope {
    var attack: Float
    var hold: Float
    var decay: Float

    var length: Float { attack + hold + decay }

    @inline(__always)
    func value(at t: Float) -> Float {
        if t < 0 { return 0 }
        if t < attack { return t / attack }
        let d = t - attack - hold
        if d < 0 { return 1 }
        if d >= decay { return 0 }
        var v = exp2f(-6.643_856 * d / decay)
        let remaining = decay - d
        if remaining < 0.002 { v *= remaining / 0.002 }
        return v
    }
}

/// A gated ADSR envelope advanced per sample (the music pad voices).
nonisolated struct ADSR {
    var attackStep: Float
    var decayStep: Float
    var sustain: Float
    var releaseStep: Float
    var level: Float = 0
    var gate = false
    private var decaying = false

    init(attack: Float, decay: Float, sustain: Float, release: Float, sampleRate: Float) {
        attackStep = 1 / max(1, attack * sampleRate)
        decayStep = (1 - sustain) / max(1, decay * sampleRate)
        self.sustain = sustain
        releaseStep = 1 / max(1, release * sampleRate)
    }

    @inline(__always)
    mutating func next() -> Float {
        if gate {
            if !decaying {
                level += attackStep
                if level >= 1 {
                    level = 1
                    decaying = true
                }
            } else if level > sustain {
                level = max(sustain, level - decayStep)
            }
        } else {
            decaying = false
            level = max(0, level - releaseStep)
        }
        return level
    }
}

/// Exponential pitch (or cutoff) sweep from `start` by `octaves` over `time` seconds.
nonisolated struct ExponentialSweep {
    var start: Float
    var octaves: Float
    var time: Float

    @inline(__always)
    func value(at t: Float) -> Float {
        if octaves == 0 || time <= 0 { return start }
        let u = min(max(t / time, 0), 1)
        return start * exp2f(octaves * u)
    }
}

/// A sine low-frequency oscillator.
nonisolated struct LFO {
    var phase: Float = 0

    @inline(__always)
    mutating func next(rate: Float, step: Float, _ table: SineTable) -> Float {
        let v = table.sine(phase)
        phase += rate * step
        if phase >= 1 { phase -= phase.rounded(.down) }
        return v
    }
}

/// A feedback delay over a preallocated one-second line.
nonisolated struct FeedbackDelay {
    let line: UnsafeMutablePointer<Float>
    let length: Int
    var index = 0

    static func make(sampleRate: Double) -> FeedbackDelay {
        let n = max(1, Int(sampleRate))
        let p = UnsafeMutablePointer<Float>.allocate(capacity: n)
        p.initialize(repeating: 0, count: n)
        return FeedbackDelay(line: p, length: n)
    }

    func free() { line.deallocate() }
    func clear() { line.update(repeating: 0, count: length) }

    /// Returns the delayed sample and writes `input + feedback × delayed` into the line.
    @inline(__always)
    mutating func process(_ input: Float, delaySamples: Int, feedback: Float) -> Float {
        let d = min(max(1, delaySamples), length - 1)
        var r = index - d
        if r < 0 { r += length }
        let out = line[r]
        line[index] = input + out * feedback
        index += 1
        if index >= length { index = 0 }
        return out
    }
}

/// A small Schroeder reverb (four parallel combs, two series all-passes per channel) over preallocated lines.
nonisolated struct SchroederReverb {
    private static let combSeconds: [Double] = [0.0297, 0.0371, 0.0411, 0.0437]
    private static let allpassSeconds: [Double] = [0.0050, 0.0017]
    /// Lines: 4 combs then 2 all-passes for the left channel, then the same with a stereo spread for the right.
    let lines: UnsafeMutablePointer<UnsafeMutablePointer<Float>>
    let lengths: UnsafeMutablePointer<Int>
    let indices: UnsafeMutablePointer<Int>
    let combFeedback: UnsafeMutablePointer<Float>
    static var lineCount: Int { 12 }

    /// Allocates the lines for `sampleRate` with a decay time of `rt60` seconds (init time only).
    static func make(sampleRate: Double, rt60: Double) -> SchroederReverb {
        let lines = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: lineCount)
        let lengths = UnsafeMutablePointer<Int>.allocate(capacity: lineCount)
        let indices = UnsafeMutablePointer<Int>.allocate(capacity: lineCount)
        let feedback = UnsafeMutablePointer<Float>.allocate(capacity: 8)
        for channel in 0..<2 {
            let spread = channel == 0 ? 1.0 : 1.037
            for j in 0..<6 {
                let seconds = j < 4 ? combSeconds[j] : allpassSeconds[j - 4]
                let n = max(2, Int(seconds * spread * sampleRate))
                let slot = channel * 6 + j
                let p = UnsafeMutablePointer<Float>.allocate(capacity: n)
                p.initialize(repeating: 0, count: n)
                lines[slot] = p
                lengths[slot] = n
                indices[slot] = 0
                if j < 4 {
                    feedback[channel * 4 + j] = Float(pow(10, -3 * seconds * spread / rt60))
                }
            }
        }
        return SchroederReverb(lines: lines, lengths: lengths, indices: indices, combFeedback: feedback)
    }

    func free() {
        for i in 0..<Self.lineCount { lines[i].deallocate() }
        lines.deallocate()
        lengths.deallocate()
        indices.deallocate()
        combFeedback.deallocate()
    }

    func clear() {
        for i in 0..<Self.lineCount { lines[i].update(repeating: 0, count: lengths[i]) }
    }

    @inline(__always)
    private func tap(_ slot: Int) -> Float { lines[slot][indices[slot]] }

    @inline(__always)
    private func write(_ slot: Int, _ v: Float) {
        lines[slot][indices[slot]] = v
        var i = indices[slot] + 1
        if i >= lengths[slot] { i = 0 }
        indices[slot] = i
    }

    /// One mono input sample in, one stereo sample out.
    @inline(__always)
    func process(_ input: Float) -> (Float, Float) {
        var out: (Float, Float) = (0, 0)
        for channel in 0..<2 {
            let base = channel * 6
            var sum: Float = 0
            for j in 0..<4 {
                let y = tap(base + j)
                write(base + j, input + y * combFeedback[channel * 4 + j])
                sum += y
            }
            var x = sum * 0.25
            for j in 4..<6 {
                let delayed = tap(base + j)
                let y = -0.5 * x + delayed
                write(base + j, x + 0.5 * y)
                x = y
            }
            if channel == 0 { out.0 = x } else { out.1 = x }
        }
        return out
    }
}
