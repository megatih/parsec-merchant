// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// The waveform of one recipe layer.
enum LayerWave: UInt8, Sendable, BitwiseCopyable {
    case sine, triangle, saw, square, noise, fm, crackle
}

/// One layer of a cue recipe (plain old data). Times are seconds from the cue start, frequencies Hz.
struct LayerSpec: Sendable, BitwiseCopyable {
    var wave: LayerWave = .sine
    var start: Float = 0
    var attack: Float = 0.002
    var hold: Float = 0
    var decay: Float = 0.1
    var freq: Float = 440
    /// Exponential pitch sweep: octaves (signed) over `sweepTime` seconds.
    var sweepOctaves: Float = 0
    var sweepTime: Float = 0
    /// A second oscillator of the same wave at `freq × detune` (0 = none).
    var detune: Float = 0
    var vibratoRate: Float = 0
    var vibratoSemitones: Float = 0
    /// Vibrato start phase in cycles (−0.25 starts at the bottom of the swing).
    var vibratoPhase: Float = 0
    var tremoloRate: Float = 0
    var tremoloDepth: Float = 0
    var fmRatio: Float = 1
    var fmIndexStart: Float = 0
    var fmIndexEnd: Float = 0
    /// Ring modulation by a sine at this frequency (0 = none).
    var ringHz: Float = 0
    var filter: StateVariableFilter.Mode = .none
    var cutoff: Float = 1000
    var cutoffOctaves: Float = 0
    var cutoffTime: Float = 0
    var q: Float = 0.707
    var gain: Float = 0.5

    var end: Float { start + attack + hold + decay }
}

/// One cue variant: a span of layers in the layer table plus voice-level settings.
struct RecipeSpec: Sendable, BitwiseCopyable {
    var firstLayer: Int
    var layerCount: Int
    /// Seconds from the start to the end of the last layer.
    var length: Float
    var priority: UInt8
    /// Send level into the shared reverb (warp and achievement tails).
    var reverbSend: Float
    /// Sweep the pan from the requested position to that side's outer edge over the cue (escape).
    var panSweep: Bool
}

/// Per-layer render state of a voice.
struct LayerState {
    var osc = Oscillator()
    var osc2 = Oscillator()
    var fm = FMOperatorPair()
    var ring = Oscillator()
    var vibrato = LFO()
    var tremolo = LFO()
    var filter = StateVariableFilter()
    var noise = NoiseSource(seed: 1)
    // Control-rate values (recomputed every `SynthCore.controlInterval` samples).
    var dt: Float = 0
    var dt2: Float = 0
    var fmIndex: Float = 0
    var envNow: Float = 0
    var envStep: Float = 0
    var trem: Float = 1
}

/// One SFX voice (AUD-005).
struct VoiceState {
    var active = false
    var recipe = 0
    var priority: UInt8 = 0
    var serial: UInt64 = 0
    /// Samples left before the cue starts (request delay).
    var delaySamples = 0
    /// Samples since the cue started.
    var time = 0
    var lengthSamples = 0
    var pitchRatio: Float = 1
    var gain: Float = 1
    var pan: Float = 0
    var panTarget: Float = 0
    var panSweep = false
    var reverbSend: Float = 0
    /// Steal / stop fade: samples left and total (0 = not fading).
    var fadeRemaining = 0
    var fadeTotal = 0
    var pending = CueRequest(cue: .uiTick)
    var hasPending = false
}

/// Renders one layer of a voice into `out` (accumulating). `voiceTime` is the voice's time at frame 0.
@inline(__always)
func renderLayer(_ spec: UnsafePointer<LayerSpec>, _ state: UnsafeMutablePointer<LayerState>, voiceTime: Int,
                 frames: Int, out: UnsafeMutablePointer<Float>, pitchRatio: Float, sampleRate: Float,
                 table: SineTable) {
    let s = spec.pointee
    let startSample = Int(s.start * sampleRate)
    let endSample = Int(s.end * sampleRate)
    let first = max(0, startSample - voiceTime)
    let last = min(frames, endSample - voiceTime)
    if first >= last { return }
    let inv = 1 / sampleRate
    let interval = SynthCore.controlInterval
    let env = DecayEnvelope(attack: s.attack, hold: s.hold, decay: s.decay)
    let pitchSweep = ExponentialSweep(start: s.freq * pitchRatio, octaves: s.sweepOctaves, time: s.sweepTime)
    let cutoffSweep = ExponentialSweep(start: s.cutoff, octaves: s.cutoffOctaves, time: s.cutoffTime)
    let length = max(s.attack + s.hold + s.decay, 1e-4)
    var i = first
    while i < last {
        let lt = voiceTime + i - startSample
        // Control rate: frequency, filter, FM index, tremolo and the envelope segment.
        let phaseInBlock = lt % interval
        if phaseInBlock == 0 || i == first {
            let aligned = phaseInBlock == 0
            let base = lt - phaseInBlock
            let t = Float(base) * inv
            let step = Float(interval) * inv
            var f = pitchSweep.value(at: t)
            if s.vibratoSemitones != 0 {
                if lt == 0 { state.pointee.vibrato.phase = s.vibratoPhase }
                let v = aligned ? state.pointee.vibrato.next(rate: s.vibratoRate, step: step, table)
                    : table.sine(state.pointee.vibrato.phase)
                f *= exp2f(s.vibratoSemitones * v / 12)
            }
            state.pointee.dt = min(f * inv, 0.49)
            state.pointee.dt2 = min(f * s.detune * inv, 0.49)
            if s.filter != .none {
                state.pointee.filter.set(cutoff: cutoffSweep.value(at: t), q: s.q, sampleRate: sampleRate)
            }
            let u = min(t / length, 1)
            state.pointee.fmIndex = s.fmIndexStart + (s.fmIndexEnd - s.fmIndexStart) * u
            if s.tremoloDepth != 0 {
                let v = aligned ? state.pointee.tremolo.next(rate: s.tremoloRate, step: step, table)
                    : table.sine(state.pointee.tremolo.phase)
                state.pointee.trem = 1 - s.tremoloDepth * (0.5 + 0.5 * v)
            } else {
                state.pointee.trem = 1
            }
            let e0 = env.value(at: t)
            let e1 = env.value(at: t + step)
            state.pointee.envStep = (e1 - e0) / Float(interval)
            state.pointee.envNow = e0 + state.pointee.envStep * Float(phaseInBlock)
        }
        let dt = state.pointee.dt
        var x: Float
        switch s.wave {
        case .sine:
            x = state.pointee.osc.sine(dt, table)
            if s.detune != 0 { x = 0.5 * (x + state.pointee.osc2.sine(state.pointee.dt2, table)) }
        case .triangle:
            x = state.pointee.osc.triangle(dt)
            if s.detune != 0 { x = 0.5 * (x + state.pointee.osc2.triangle(state.pointee.dt2)) }
        case .saw:
            x = state.pointee.osc.saw(dt)
            if s.detune != 0 { x = 0.5 * (x + state.pointee.osc2.saw(state.pointee.dt2)) }
        case .square:
            x = state.pointee.osc.square(dt)
            if s.detune != 0 { x = 0.5 * (x + state.pointee.osc2.square(state.pointee.dt2)) }
        case .noise:
            x = state.pointee.noise.next()
        case .fm:
            x = state.pointee.fm.sample(dt, ratio: s.fmRatio, index: state.pointee.fmIndex, table)
        case .crackle:
            let r = state.pointee.noise.next()
            x = abs(r) > 0.93 ? r : 0
        }
        if s.ringHz != 0 {
            x *= state.pointee.ring.sine(s.ringHz * inv, table)
        }
        if s.filter != .none {
            x = state.pointee.filter.process(x, mode: s.filter)
        }
        out[i] += x * state.pointee.envNow * state.pointee.trem * s.gain
        state.pointee.envNow += state.pointee.envStep
        i += 1
    }
}
