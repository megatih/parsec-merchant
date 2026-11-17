// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Synchronization

/// A linear gain ramp (AUD-006): every change of target moves there in a straight line over `rampSamples`.
nonisolated struct GainRamp {
    var current: Float
    var target: Float
    var step: Float = 0
    var remaining = 0
    let rampSamples: Int

    init(value: Float, rampSamples: Int) {
        current = value
        target = value
        self.rampSamples = max(1, rampSamples)
    }

    @inline(__always)
    mutating func setTarget(_ t: Float) {
        if t == target { return }
        target = t
        step = (t - current) / Float(rampSamples)
        remaining = rampSamples
    }

    @inline(__always)
    mutating func next() -> Float {
        if remaining > 0 {
            remaining -= 1
            current = remaining == 0 ? target : current + step
        }
        return current
    }

    @inline(__always)
    mutating func skip(_ n: Int) {
        if remaining == 0 { return }
        if n >= remaining {
            remaining = 0
            current = target
        } else {
            remaining -= n
            current += step * Float(n)
        }
    }

    var isSteady: Bool { remaining == 0 }
}

/// AUD-001…007: the procedural synthesiser. `render` is the single real-time entry point: it drains the request ring,
/// mixes the SFX voices (equal-power pan), the music voices and the reverb bus, applies the smoothed gains and a soft
/// limiter. It never allocates, locks or suspends; the main actor talks to it only through the request ring and atomics.
public nonisolated final class SynthCore: @unchecked Sendable {
    // @unchecked Sendable: every mutable stored property is either owned by the render thread (voices, buffers, music,
    // ramps, reverb, which only `render` touches) or exchanged through `Atomic`s and the SPSC `RequestRing`. Producers
    // (the main actor) only call `enqueue`, `setGains`, `setMusic`, `stopAll`, `setCalibrationTone` and read counters.

    /// Samples between control-rate parameter updates.
    static var controlInterval: Int { 16 }
    /// Largest chunk processed at once (AUD-002).
    public static var maxChunk: Int { 4096 }

    public let sampleRate: Double
    let sr: Float
    public let sfxVoiceCount: Int
    public let musicVoiceCount: Int
    let seed: UInt64

    private let ring: RequestRing
    private let voices: UnsafeMutablePointer<VoiceState>
    private let layerStates: UnsafeMutablePointer<LayerState>
    private let maxLayers: Int
    private let layerTable: UnsafeMutablePointer<LayerSpec>
    private let layerCount: Int
    private let recipes: UnsafeMutablePointer<RecipeSpec>
    private let recipeCount: Int
    private let firstRecipe: UnsafeMutablePointer<Int>
    private let variants: UnsafeMutablePointer<Int>
    private let cueCount: Int
    private let table: SineTable
    private var reverb: SchroederReverb
    private var echo: FeedbackDelay
    private var music: MusicGenerator
    private let mixL: UnsafeMutablePointer<Float>
    private let mixR: UnsafeMutablePointer<Float>
    private let voiceBuffer: UnsafeMutablePointer<Float>
    private let sendBuffer: UnsafeMutablePointer<Float>
    private let musicL: UnsafeMutablePointer<Float>
    private let musicR: UnsafeMutablePointer<Float>

    // Control path (main actor → render thread).
    private let overallTarget = AtomicFloatBox(1)
    private let effectsTarget = AtomicFloatBox(1)
    private let musicVolumeTarget = AtomicFloatBox(1)
    private let musicEnabled = Atomic<Bool>(false)
    private let musicMood = Atomic<UInt8>(0)
    private let stopGeneration = Atomic<Int>(0)
    private let toneFrequency = AtomicFloatBox(0)
    private let toneAmplitude = AtomicFloatBox(0)
    // Counters (render thread → main actor).
    private let renderCounter = Atomic<Int>(0)
    private let droppedCounter = Atomic<Int>(0)
    private let activeCounter = Atomic<Int>(0)

    // Render-thread state.
    private var sfxGain: GainRamp
    private var musicGain: GainRamp
    private var toneGain: GainRamp
    private var tone = Oscillator()
    private var seenStopGeneration = 0
    private var serial: UInt64 = 0
    private var reverbActive = false

    /// Preallocates every buffer (AUD-001). Sample rates from 22 050 to 192 000 Hz are supported.
    public init(sampleRate: Double, sfxVoices: Int = 16, musicVoices: Int = 6, queueCapacity: Int = 64, seed: UInt64) {
        let rate = min(max(sampleRate, 22_050), 192_000)
        self.sampleRate = rate
        sr = Float(rate)
        sfxVoiceCount = max(1, sfxVoices)
        musicVoiceCount = max(6, musicVoices)
        self.seed = seed
        ring = RequestRing(capacity: queueCapacity)
        let catalog = CueRecipes.build()
        layerCount = catalog.layers.count
        recipeCount = catalog.recipes.count
        cueCount = catalog.firstRecipe.count
        layerTable = UnsafeMutablePointer<LayerSpec>.allocate(capacity: layerCount)
        layerTable.initialize(repeating: LayerSpec(), count: layerCount)
        for i in 0..<layerCount { layerTable[i] = catalog.layers[i] }
        recipes = UnsafeMutablePointer<RecipeSpec>.allocate(capacity: recipeCount)
        recipes.initialize(repeating: RecipeSpec(firstLayer: 0, layerCount: 0, length: 0, priority: 0, reverbSend: 0,
                                                 panSweep: false), count: recipeCount)
        var widest = 1
        for i in 0..<recipeCount {
            recipes[i] = catalog.recipes[i]
            widest = max(widest, catalog.recipes[i].layerCount)
        }
        maxLayers = widest
        firstRecipe = UnsafeMutablePointer<Int>.allocate(capacity: cueCount)
        firstRecipe.initialize(repeating: 0, count: cueCount)
        variants = UnsafeMutablePointer<Int>.allocate(capacity: cueCount)
        variants.initialize(repeating: 1, count: cueCount)
        for i in 0..<cueCount {
            firstRecipe[i] = catalog.firstRecipe[i]
            variants[i] = catalog.variantCounts[i]
        }
        voices = UnsafeMutablePointer<VoiceState>.allocate(capacity: sfxVoiceCount)
        voices.initialize(repeating: VoiceState(), count: sfxVoiceCount)
        layerStates = UnsafeMutablePointer<LayerState>.allocate(capacity: sfxVoiceCount * maxLayers)
        layerStates.initialize(repeating: LayerState(), count: sfxVoiceCount * maxLayers)
        table = SineTable.make()
        reverb = SchroederReverb.make(sampleRate: rate, rt60: 0.35)
        echo = FeedbackDelay.make(sampleRate: rate)
        music = MusicGenerator.make(sampleRate: rate, seed: UInt32(truncatingIfNeeded: seed ^ 0xA5A5_5A5A),
                                    chords: MusicTables.chords, scales: MusicTables.scales, drones: MusicTables.drones,
                                    cutoffs: MusicTables.cutoffs)
        func buffer() -> UnsafeMutablePointer<Float> {
            let p = UnsafeMutablePointer<Float>.allocate(capacity: Self.maxChunk)
            p.initialize(repeating: 0, count: Self.maxChunk)
            return p
        }
        mixL = buffer()
        mixR = buffer()
        voiceBuffer = buffer()
        sendBuffer = buffer()
        musicL = buffer()
        musicR = buffer()
        let ramp = Int(0.03 * rate)
        sfxGain = GainRamp(value: 1, rampSamples: ramp)
        musicGain = GainRamp(value: 1, rampSamples: ramp)
        toneGain = GainRamp(value: 0, rampSamples: ramp)
    }

    deinit {
        voices.deinitialize(count: sfxVoiceCount)
        voices.deallocate()
        layerStates.deinitialize(count: sfxVoiceCount * maxLayers)
        layerStates.deallocate()
        layerTable.deallocate()
        recipes.deallocate()
        firstRecipe.deallocate()
        variants.deallocate()
        table.free()
        reverb.free()
        echo.free()
        music.free()
        mixL.deallocate()
        mixR.deallocate()
        voiceBuffer.deallocate()
        sendBuffer.deallocate()
        musicL.deallocate()
        musicR.deallocate()
    }

    // MARK: Control path (AUD-003)

    /// Queues a cue. Returns false (and counts a drop) when the ring is full; never blocks.
    @discardableResult
    public func enqueue(_ request: CueRequest) -> Bool {
        if ring.push(request) { return true }
        droppedCounter.wrappingAdd(1, ordering: .relaxed)
        return false
    }

    /// Slider values in 0…1; the gain law (AUD-006) squares them.
    public func setGains(overall: Float, effects: Float, music: Float) {
        overallTarget.store(Self.clamp01(overall))
        effectsTarget.store(Self.clamp01(effects))
        musicVolumeTarget.store(Self.clamp01(music))
    }

    public func setMusic(enabled: Bool, mood: MusicMood) {
        musicEnabled.store(enabled, ordering: .relaxed)
        musicMood.store(mood.rawValue, ordering: .relaxed)
    }

    /// Fades every voice out over 5 ms and discards queued requests.
    public func stopAll() {
        stopGeneration.wrappingAdd(1, ordering: .relaxed)
    }

    /// A held sine under the effects gain, for calibration and the gain-smoothing test (amplitude 0 turns it off).
    public func setCalibrationTone(frequency: Float, amplitude: Float) {
        toneFrequency.store(max(0, frequency))
        toneAmplitude.store(Self.clamp01(amplitude))
    }

    public var renderCount: Int { renderCounter.load(ordering: .relaxed) }
    public var droppedRequests: Int { droppedCounter.load(ordering: .relaxed) }
    public var activeVoices: Int { activeCounter.load(ordering: .relaxed) }

    static func clamp01(_ v: Float) -> Float { v.isFinite ? min(max(v, 0), 1) : 0 }

    /// The soft limiter (AUD-006): identity up to 0.5, then the `x / (1 + |x|)` curve scaled into the remaining
    /// headroom, so the output is continuous, finite and always within [−1, 1].
    @inline(__always)
    static func limit(_ x: Float) -> Float {
        if !x.isFinite { return 0 }
        let a = abs(x)
        if a <= 0.5 { return x }
        let u = (a - 0.5) / 0.5
        let y = 0.5 + 0.5 * (u / (1 + u))
        return x < 0 ? -y : y
    }

    // MARK: Render (AUD-002)

    /// Writes `frameCount` non-interleaved Float32 samples per channel. Callable from any thread (one at a time).
    /// Returns true when the written output is exact silence.
    @discardableResult
    public func render(frameCount: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) -> Bool {
        renderCounter.wrappingAdd(1, ordering: .relaxed)
        var offset = 0
        var silent = true
        while offset < frameCount {
            let n = min(Self.maxChunk, frameCount - offset)
            if !renderChunk(n, left + offset, right + offset) { silent = false }
            offset += n
        }
        return silent
    }

    private func renderChunk(_ n: Int, _ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>) -> Bool {
        applyStopIfRequested()
        while let request = ring.pop() { start(request) }
        let overall = overallTarget.load()
        let effects = effectsTarget.load()
        let musicVolume = musicVolumeTarget.load()
        sfxGain.setTarget(overall * overall * effects * effects)
        musicGain.setTarget(overall * overall * musicVolume * musicVolume)
        toneGain.setTarget(toneAmplitude.load())
        music.update(enabled: musicEnabled.load(ordering: .relaxed),
                     mood: MusicMood(rawValue: musicMood.load(ordering: .relaxed)) ?? .calm)

        mixL.update(repeating: 0, count: n)
        mixR.update(repeating: 0, count: n)
        var active = 0
        var rendered = false
        var sends = false
        for v in 0..<sfxVoiceCount where voices[v].active {
            rendered = true
            if voices[v].reverbSend > 0 {
                if !sends { sendBuffer.update(repeating: 0, count: n) }
                sends = true
            }
            renderVoice(v, n, sends: sends)
            if voices[v].active { active += 1 }
        }
        let toneOn = toneGain.current > 0 || toneGain.target > 0
        let musicOn = music.isRunning
        if musicOn { music.render(frames: n, left: musicL, right: musicR, table: table) }
        if sends || reverbActive { mixReverb(n, sends: sends) }
        activeCounter.store(active, ordering: .relaxed)

        if !rendered && !musicOn && !reverbActive && !toneOn && !sends {
            sfxGain.skip(n)
            musicGain.skip(n)
            left.update(repeating: 0, count: n)
            right.update(repeating: 0, count: n)
            return true
        }
        let toneStep = toneFrequency.load() / sr
        for i in 0..<n {
            let g = sfxGain.next()
            let mg = musicGain.next()
            var l = mixL[i]
            var r = mixR[i]
            if toneOn {
                let t = tone.sine(toneStep, table) * toneGain.next()
                l += t
                r += t
            }
            l *= g
            r *= g
            if musicOn {
                l += musicL[i] * mg
                r += musicR[i] * mg
            }
            left[i] = Self.limit(l)
            right[i] = Self.limit(r)
        }
        return false
    }

    private func mixReverb(_ n: Int, sends: Bool) {
        var peak: Float = 0
        for i in 0..<n {
            let input = sends ? sendBuffer[i] : 0
            let (rl, rr) = reverb.process(input)
            mixL[i] += rl
            mixR[i] += rr
            peak = max(peak, abs(rl), abs(rr))
        }
        let ringing = peak > 1e-5
        if !ringing && !sends && reverbActive { reverb.clear() }
        reverbActive = ringing || sends
    }

    private func applyStopIfRequested() {
        let generation = stopGeneration.load(ordering: .relaxed)
        guard generation != seenStopGeneration else { return }
        seenStopGeneration = generation
        while ring.pop() != nil {}
        let fade = Int(0.005 * sr)
        for v in 0..<sfxVoiceCount where voices[v].active {
            voices[v].hasPending = false
            if voices[v].delaySamples > 0 {
                voices[v].active = false
            } else if voices[v].fadeTotal == 0 {
                voices[v].fadeTotal = fade
                voices[v].fadeRemaining = fade
            }
        }
    }

    // MARK: Voices (AUD-005)

    private func recipeIndex(for request: CueRequest) -> Int {
        let cue = min(Int(request.cue.rawValue), cueCount - 1)
        let variant = min(Int(request.variant), variants[cue] - 1)
        return firstRecipe[cue] + max(0, variant)
    }

    private func start(_ request: CueRequest) {
        let recipe = recipeIndex(for: request)
        let priority = recipes[recipe].priority
        for v in 0..<sfxVoiceCount where !voices[v].active {
            startVoice(v, request, recipe: recipe)
            return
        }
        // Steal the oldest voice of the lowest priority that is ≤ the request's, with a 5 ms fade.
        var candidate = -1
        for v in 0..<sfxVoiceCount {
            let voice = voices[v]
            if voice.fadeTotal != 0 || voice.hasPending || voice.priority > priority { continue }
            if candidate < 0 {
                candidate = v
                continue
            }
            let best = voices[candidate]
            if voice.priority < best.priority || (voice.priority == best.priority && voice.serial < best.serial) {
                candidate = v
            }
        }
        guard candidate >= 0 else {
            droppedCounter.wrappingAdd(1, ordering: .relaxed)
            return
        }
        if voices[candidate].delaySamples > 0 {
            startVoice(candidate, request, recipe: recipe)
            return
        }
        let fade = max(1, Int(0.005 * sr))
        voices[candidate].fadeTotal = fade
        voices[candidate].fadeRemaining = fade
        voices[candidate].pending = request
        voices[candidate].hasPending = true
    }

    private func startVoice(_ v: Int, _ request: CueRequest, recipe: Int) {
        serial &+= 1
        let spec = recipes[recipe]
        var voice = VoiceState()
        voice.active = true
        voice.recipe = recipe
        voice.priority = spec.priority
        voice.serial = serial
        let delay = request.delay.isFinite ? min(max(request.delay, 0), 2) : 0
        voice.delaySamples = Int(delay * sr)
        voice.lengthSamples = Int(spec.length * sr) + 1
        voice.pitchRatio = request.pitchSemitones.isFinite ? exp2f(min(max(request.pitchSemitones, -24), 24) / 12) : 1
        voice.gain = request.gain.isFinite ? min(max(request.gain, 0), 4) : 0
        let pan = request.pan.isFinite ? min(max(request.pan, -1), 1) : 0
        voice.pan = pan
        voice.panSweep = spec.panSweep
        voice.panTarget = pan < 0 ? -1 : 1
        voice.reverbSend = spec.reverbSend
        voices[v] = voice
        let base = v * maxLayers
        for l in 0..<maxLayers {
            var state = LayerState()
            state.noise = NoiseSource(seed: Self.noiseSeed(seed, serial, l))
            layerStates[base + l] = state
        }
    }

    /// SplitMix64-style mixing of the core seed, the voice serial and the layer index.
    static func noiseSeed(_ seed: UInt64, _ serial: UInt64, _ layer: Int) -> UInt32 {
        var z = seed &+ serial &* 0x9E37_79B9_7F4A_7C15 &+ UInt64(layer) &* 0xD1B5_4A32_D192_ED03
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        let s = UInt32(truncatingIfNeeded: z)
        return s == 0 ? 1 : s
    }

    private func renderVoice(_ v: Int, _ n: Int, sends: Bool) {
        var voice = voices[v]
        var startFrame = 0
        if voice.delaySamples > 0 {
            startFrame = min(voice.delaySamples, n)
            voice.delaySamples -= startFrame
            if startFrame >= n {
                voices[v] = voice
                return
            }
        }
        let frames = n - startFrame
        voiceBuffer.update(repeating: 0, count: frames)
        let spec = recipes[voice.recipe]
        let base = v * maxLayers
        for l in 0..<spec.layerCount {
            renderLayer(layerTable + spec.firstLayer + l, layerStates + base + l, voiceTime: voice.time, frames: frames,
                        out: voiceBuffer, pitchRatio: voice.pitchRatio, sampleRate: sr, table: table)
        }
        let length = Float(max(1, voice.lengthSamples))
        var startPan = voice.pan
        if voice.panSweep {
            let aligned = voice.time - voice.time % Self.controlInterval
            startPan += (voice.panTarget - voice.pan) * min(1, Float(aligned) / length)
        }
        var panL = table.sine((startPan + 1) * 0.125 + 0.25)
        var panR = table.sine((startPan + 1) * 0.125)
        var finished = false
        var i = 0
        while i < frames {
            if voice.panSweep && (voice.time + i) % Self.controlInterval == 0 {
                let u = min(1, Float(voice.time + i) / length)
                let p = voice.pan + (voice.panTarget - voice.pan) * u
                panL = table.sine((p + 1) * 0.125 + 0.25)
                panR = table.sine((p + 1) * 0.125)
            }
            var a = voiceBuffer[i] * voice.gain
            if voice.fadeTotal > 0 {
                a *= Float(voice.fadeRemaining) / Float(voice.fadeTotal)
                if voice.fadeRemaining > 0 { voice.fadeRemaining -= 1 }
                if voice.fadeRemaining == 0 {
                    finished = true
                    break
                }
            }
            let out = startFrame + i
            mixL[out] += a * panL
            mixR[out] += a * panR
            if sends && voice.reverbSend > 0 { sendBuffer[out] += a * voice.reverbSend }
            i += 1
        }
        voice.time += frames
        if finished || voice.time >= voice.lengthSamples {
            voice.active = false
            voices[v] = voice
            if voice.hasPending {
                let next = voice.pending
                startVoice(v, next, recipe: recipeIndex(for: next))
            }
            return
        }
        voices[v] = voice
    }
}
