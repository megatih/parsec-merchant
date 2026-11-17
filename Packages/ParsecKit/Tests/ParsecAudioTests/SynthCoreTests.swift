// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Testing
@testable import ParsecAudio

@Suite("SynthCore")
struct SynthCoreTests {
    static func peak(_ s: (left: [Float], right: [Float])) -> Float {
        zip(s.left, s.right).reduce(0) { max($0, abs($1.0), abs($1.1)) }
    }

    @Test("AUD-001 sample rates from 22 050 to 192 000 Hz render every cue; voice counts are kept",
          arguments: [22_050.0, 44_100.0, 96_000.0, 192_000.0])
    func sampleRates(rate: Double) {
        let core = SynthCore(sampleRate: rate, sfxVoices: 16, musicVoices: 6, queueCapacity: 64, seed: 1)
        #expect(core.sampleRate == rate)
        #expect(core.sfxVoiceCount == 16 && core.musicVoiceCount == 6)
        let out = core.renderOffline(requests: [CueRequest(cue: .coinIn), CueRequest(cue: .explosion)], seconds: 0.3)
        #expect(out.left.count == Int(0.3 * rate))
        #expect(Self.peak(out) > 0.05 && Self.peak(out) <= 1)
        #expect(out.left.allSatisfy { $0.isFinite })
        // Out-of-range rates are clamped into the supported range.
        #expect(SynthCore(sampleRate: 8000, seed: 1).sampleRate == 22_050)
        #expect(SynthCore(sampleRate: 384_000, seed: 1).sampleRate == 192_000)
    }

    @Test("AUD-002 one large render equals 512-frame blocks; counts above 4096 are chunked")
    func chunking() {
        let requests = [CueRequest(cue: .warpDeparture, variant: 1), CueRequest(cue: .escape, pan: -0.4),
                        CueRequest(cue: .laser, variant: 2, pan: 0.4)]
        let blocks = SynthCore(sampleRate: 48_000, seed: 9).renderOffline(requests: requests, seconds: 1.0)
        let core = SynthCore(sampleRate: 48_000, seed: 9)
        for r in requests { core.enqueue(r) }
        var l = [Float](repeating: 0, count: 48_000)
        var r = [Float](repeating: 0, count: 48_000)
        l.withUnsafeMutableBufferPointer { lp in
            r.withUnsafeMutableBufferPointer { rp in
                if let a = lp.baseAddress, let b = rp.baseAddress { core.render(frameCount: 48_000, left: a, right: b) }
            }
        }
        #expect(core.renderCount == 1)
        #expect(l == blocks.left && r == blocks.right)
    }

    @Test("AUD-003 AUD-048 a full ring drops and counts requests without blocking; counters are readable")
    func ringFull() {
        let core = SynthCore(sampleRate: 48_000, queueCapacity: 4, seed: 1)
        let accepted = (0..<6).map { _ in core.enqueue(CueRequest(cue: .uiTick)) }
        #expect(accepted == [true, true, true, true, false, false])
        #expect(core.droppedRequests == 2)
        _ = core.renderOffline(requests: [], seconds: 0.01)
        #expect(core.activeVoices == 4)
        #expect(core.renderCount == 1)
        #expect(_isPOD(CueRequest.self))
        // The ring is drained by the render, so it accepts again.
        #expect(core.enqueue(CueRequest(cue: .uiTick)))
    }

    @Test("AUD-003 the SPSC ring keeps order across wrap-around")
    func ringOrder() {
        let ring = RequestRing(capacity: 3)
        var popped: [UInt8] = []
        for round in 0..<5 {
            for k in 0..<3 { #expect(ring.push(CueRequest(cue: .uiTick, variant: UInt8(round * 3 + k)))) }
            while let r = ring.pop() { popped.append(r.variant) }
        }
        #expect(popped == (0..<15).map(UInt8.init))
    }

    @Test("AUD-004 building blocks: deterministic noise, filter, PolyBLEP, envelopes, sweep, delay and reverb")
    func buildingBlocks() {
        var a = NoiseSource(seed: 42), b = NoiseSource(seed: 42), c = NoiseSource(seed: 43)
        let sa = (0..<64).map { _ in a.next() }, sb = (0..<64).map { _ in b.next() }, sc = (0..<64).map { _ in c.next() }
        #expect(sa == sb && sa != sc && sa.allSatisfy { abs($0) <= 1 })

        let table = SineTable.make()
        defer { table.free() }
        func filtered(_ hz: Float) -> Float {
            var f = StateVariableFilter()
            f.set(cutoff: 500, q: 0.707, sampleRate: 48_000)
            var osc = Oscillator(), peak: Float = 0
            for i in 0..<9600 {
                let y = f.process(osc.sine(hz / 48_000, table), mode: .lowPass)
                if i > 4800 { peak = max(peak, abs(y)) }
            }
            return peak
        }
        #expect(filtered(100) > 0.9 && filtered(8000) < 0.02)

        var saw = Oscillator(), square = Oscillator(), tri = Oscillator()
        for _ in 0..<4800 {
            #expect(abs(saw.saw(1000 / 48_000)) <= 1.01)
            #expect(abs(square.square(1000 / 48_000)) <= 1.01)
            #expect(abs(tri.triangle(1000 / 48_000)) <= 1)
        }
        var fm = FMOperatorPair(), sine = Oscillator()
        for _ in 0..<100 {
            #expect(abs(fm.sample(0.01, ratio: 2, index: 0, table) - sine.sine(0.01, table)) < 1e-6)
        }

        let env = DecayEnvelope(attack: 0.01, hold: 0.05, decay: 0.2)
        #expect(env.value(at: 0.005) == 0.5 && env.value(at: 0.03) == 1)
        #expect(abs(env.value(at: 0.257) - 0.01) < 0.003)
        #expect(env.value(at: 0.261) == 0 && abs(env.length - 0.26) < 1e-6)

        var adsr = ADSR(attack: 0.001, decay: 0.001, sustain: 0.5, release: 0.001, sampleRate: 48_000)
        adsr.gate = true
        for _ in 0..<500 { _ = adsr.next() }
        #expect(abs(adsr.level - 0.5) < 1e-4)
        adsr.gate = false
        for _ in 0..<500 { _ = adsr.next() }
        #expect(adsr.level == 0)

        let sweep = ExponentialSweep(start: 110, octaves: 3, time: 0.9)
        #expect(sweep.value(at: 0) == 110 && abs(sweep.value(at: 0.9) - 880) < 0.01 && abs(sweep.value(at: 2) - 880) < 0.01)

        var lfo = LFO()
        let first = lfo.next(rate: 1, step: 0.25, table), second = lfo.next(rate: 1, step: 0.25, table)
        #expect(abs(first) < 1e-6 && abs(second - 1) < 1e-6)

        var delay = FeedbackDelay.make(sampleRate: 1000)
        defer { delay.free() }
        var outs: [Float] = []
        for i in 0..<30 { outs.append(delay.process(i == 0 ? 1 : 0, delaySamples: 10, feedback: 0.5)) }
        #expect(outs[10] == 1 && outs[20] == 0.5 && outs[5] == 0)

        let reverb = SchroederReverb.make(sampleRate: 48_000, rt60: 0.35)
        defer { reverb.free() }
        var early: Float = 0, late: Float = 0
        for i in 0..<48_000 {
            let (l, r) = reverb.process(i == 0 ? 1 : 0)
            if i < 4800 { early = max(early, abs(l), abs(r)) } else if i > 24_000 { late = max(late, abs(l), abs(r)) }
        }
        #expect(early > 0.01 && late < early * 0.001)
    }

    @Test("AUD-005 AUD-048 a priority-3 cue always sounds with 16 busy priority-0 voices; lower ones are dropped")
    func voiceStealing() {
        let core = SynthCore(sampleRate: 48_000, seed: 1)
        for _ in 0..<16 { core.enqueue(CueRequest(cue: .uiConfirm)) }
        _ = core.renderOffline(requests: [], seconds: 0.01)
        #expect(core.activeVoices == 16)
        let out = core.renderOffline(requests: [CueRequest(cue: .explosion)], seconds: 0.3)
        #expect(core.droppedRequests == 0)
        // After the 5 ms fade the explosion plays (the uiConfirm voices end at 120 ms).
        let late = Array(out.left[9600..<14_400])
        #expect(late.map { abs($0) }.max() ?? 0 > 0.05)

        let busy = SynthCore(sampleRate: 48_000, seed: 1)
        for _ in 0..<16 { busy.enqueue(CueRequest(cue: .arrestSiren)) }
        _ = busy.renderOffline(requests: [], seconds: 0.01)
        _ = busy.renderOffline(requests: [CueRequest(cue: .uiTick)], seconds: 0.01)
        #expect(busy.droppedRequests == 1)
        // A stolen voice fades out over 5 ms: no step larger than the signal's own slope.
        let steal = SynthCore(sampleRate: 48_000, seed: 1)
        for _ in 0..<16 { steal.enqueue(CueRequest(cue: .rejected, gain: 0.5)) }
        let s = steal.renderOffline(requests: [], seconds: 0.03)
        let t = steal.renderOffline(requests: [CueRequest(cue: .powerDown)], seconds: 0.03)
        let joined = s.left + t.left
        let maxStep = (1..<joined.count).map { abs(joined[$0] - joined[$0 - 1]) }.max() ?? 0
        #expect(maxStep < 0.2)
    }

    @Test("AUD-006 gain law v² on overall and effects; overall 0 is silent")
    func gainLaw() {
        func peakAt(overall: Float, effects: Float) -> Float {
            let core = SynthCore(sampleRate: 48_000, seed: 1)
            core.setGains(overall: overall, effects: effects, music: 1)
            _ = core.renderOffline(requests: [], seconds: 0.05)  // let the 30 ms ramp settle
            return Self.peak(core.renderOffline(requests: [CueRequest(cue: .coinOut)], seconds: 0.3))
        }
        let full = peakAt(overall: 1, effects: 1)
        #expect(abs(peakAt(overall: 0.5, effects: 1) / full - 0.25) < 0.01)
        #expect(abs(peakAt(overall: 1, effects: 0.5) / full - 0.25) < 0.01)
        #expect(peakAt(overall: 0, effects: 1) == 0)
    }

    @Test("AUD-006 the soft limiter passes 0.5 within 1 dB and bounds every output to [−1, 1]")
    func limiter() {
        #expect(SynthCore.limit(0.5) == 0.5 && SynthCore.limit(-0.3) == -0.3)
        #expect(20 * log10(SynthCore.limit(0.5) / 0.5) > -1)
        for x in stride(from: Float(-100), through: 100, by: 0.37) {
            let y = SynthCore.limit(x)
            #expect(abs(y) <= 1 && y.isFinite)
        }
        #expect(SynthCore.limit(.infinity) == 0 && SynthCore.limit(.nan) == 0)
        // Monotonic and continuous at the knee.
        #expect(SynthCore.limit(0.5001) > SynthCore.limit(0.5) && SynthCore.limit(0.5001) - 0.5 < 0.0002)
        // A loud pile-up stays in range.
        let core = SynthCore(sampleRate: 48_000, seed: 1)
        let requests = (0..<16).map { _ in CueRequest(cue: .explosion, gain: 4) }
        let out = core.renderOffline(requests: requests, seconds: 0.5)
        #expect(out.left.allSatisfy { abs($0) <= 1 } && out.right.allSatisfy { abs($0) <= 1 })
    }

    @Test("AUD-007 offline renders are bit-identical for equal inputs and differ with the seed")
    func offlineDeterminism() {
        let requests = [CueRequest(cue: .explosion), CueRequest(cue: .drink, delay: 0.2),
                        CueRequest(cue: .coinIn, pitchSemitones: 4, gain: 0.5, pan: 0.3)]
        let a = SynthCore(sampleRate: 44_100, seed: 5).renderOffline(requests: requests, seconds: 1.5)
        let b = SynthCore(sampleRate: 44_100, seed: 5).renderOffline(requests: requests, seconds: 1.5)
        let c = SynthCore(sampleRate: 44_100, seed: 6).renderOffline(requests: requests, seconds: 1.5)
        #expect(a.left == b.left && a.right == b.right)
        #expect(a.left != c.left)
    }

    @Test("AUD-003 delayed requests start late; stopAll fades everything and discards the queue")
    func delayAndStop() {
        let core = SynthCore(sampleRate: 48_000, seed: 1)
        let out = core.renderOffline(requests: [CueRequest(cue: .coinOut, delay: 0.1)], seconds: 0.2)
        #expect(out.left[0..<4700].allSatisfy { $0 == 0 })
        #expect(out.left[4900..<9000].contains { $0 != 0 })
        core.enqueue(CueRequest(cue: .arrestSiren))
        _ = core.renderOffline(requests: [], seconds: 0.05)
        core.stopAll()
        core.enqueue(CueRequest(cue: .arrestSiren))
        let after = core.renderOffline(requests: [], seconds: 0.05)
        #expect(after.left[480..<2400].allSatisfy { $0 == 0 })
        #expect(core.activeVoices == 0)
    }

    @Test("AUD-045 render runs off the main thread: finite, in range, sounding while a cue plays, zero when idle")
    func offMainThread() async {
        AudioTestSupport.every { cue, v in
            let core = SynthCore(sampleRate: 48_000, seed: 2)
            core.enqueue(CueRequest(cue: cue, variant: v))
            let box = RenderBox()
            let thread = Thread {
                box.check(core: core, seconds: cue.nominalDuration(variant: v))
                box.done.signal()
            }
            thread.start()
            box.done.wait()
            #expect(!box.onMain && box.allFinite && box.inRange, "\(cue) v\(v)")
            #expect(box.sounding, "\(cue) v\(v) sounds")
            #expect(box.silentAfter, "\(cue) v\(v) silent after its end")
        }
        let core = SynthCore(sampleRate: 48_000, seed: 2)
        core.enqueue(CueRequest(cue: .explosion))
        let result = await Task.detached { () -> (Bool, Bool, Bool) in
            let box = RenderBox()
            box.check(core: core, seconds: 1.2)
            return (box.onMain, box.sounding, box.silentAfter)
        }.value
        #expect(result == (false, true, true))
    }

    @Test("AUD-048 gains ramp without discontinuity on a held sine")
    func gainRamp() {
        let core = SynthCore(sampleRate: 48_000, seed: 1)
        core.setCalibrationTone(frequency: 100, amplitude: 0.5)
        core.setGains(overall: 0, effects: 1, music: 1)
        let a = core.renderOffline(requests: [], seconds: 0.1)
        core.setGains(overall: 1, effects: 1, music: 1)
        let b = core.renderOffline(requests: [], seconds: 0.2)
        let x = a.left + b.left
        let maxStep = (1..<x.count).map { abs(x[$0] - x[$0 - 1]) }.max() ?? 1
        #expect(maxStep < 0.01)
        #expect(a.left.suffix(100).allSatisfy { $0 == 0 })
        #expect((b.left.suffix(4800).map { abs($0) }.max() ?? 0) > 0.45)
    }
}

/// Collects one render's checks on the rendering thread.
final class RenderBox: @unchecked Sendable {
    var onMain = true
    var allFinite = true
    var inRange = true
    var sounding = false
    var silentAfter = true
    let done = DispatchSemaphore(value: 0)

    func check(core: SynthCore, seconds: Double) {
        onMain = Thread.isMainThread
        let frames = 512
        var l = [Float](repeating: 0, count: frames)
        var r = [Float](repeating: 0, count: frames)
        let playing = Int(seconds * 48_000) / frames
        let total = playing + 60
        l.withUnsafeMutableBufferPointer { lp in
            r.withUnsafeMutableBufferPointer { rp in
                guard let a = lp.baseAddress, let b = rp.baseAddress else { return }
                for block in 0..<total {
                    let silent = core.render(frameCount: frames, left: a, right: b)
                    for i in 0..<frames {
                        if !a[i].isFinite || !b[i].isFinite { allFinite = false }
                        if abs(a[i]) > 1 || abs(b[i]) > 1 { inRange = false }
                        if block < playing && (a[i] != 0 || b[i] != 0) { sounding = true }
                        if block >= total - 5 && (a[i] != 0 || b[i] != 0) { silentAfter = false }
                    }
                    if block >= total - 5 && !silent { silentAfter = false }
                }
            }
        }
    }
}
