// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
@testable import ParsecAudio

/// The measured shape of one offline cue render (AUD-047).
struct CueMeasurement {
    var peak: Float
    /// Seconds until the cue's envelope has ended: every recipe envelope decays to −40 dB and is then cut within
    /// 2 ms, so the end is the last sample above −60 dB relative to the peak (which also covers reverb tails).
    var duration: Double
    /// True when every sample from `duration + 0.1 s` on is below −60 dBFS.
    var quietAfter: Bool
    var allFinite: Bool
    var left: [Float]
    var right: [Float]
}

enum AudioTestSupport {
    static func every(_ body: (SoundCue, UInt8) -> Void) {
        for cue in SoundCue.allCases {
            for v in 0..<cue.variantCount { body(cue, UInt8(v)) }
        }
    }

    static func render(_ cue: SoundCue, variant: UInt8 = 0, rate: Double = 48_000, seed: UInt64 = 7,
                       seconds: Double? = nil) -> (left: [Float], right: [Float]) {
        let core = SynthCore(sampleRate: rate, seed: seed)
        let length = seconds ?? cue.nominalDuration(variant: variant) + 0.6
        return core.renderOffline(requests: [CueRequest(cue: cue, variant: variant)], seconds: length)
    }

    static func measure(_ cue: SoundCue, variant: UInt8 = 0, rate: Double = 48_000) -> CueMeasurement {
        let (l, r) = render(cue, variant: variant, rate: rate)
        var peak: Float = 0
        var finite = true
        for i in 0..<l.count {
            if !l[i].isFinite || !r[i].isFinite { finite = false }
            peak = max(peak, abs(l[i]), abs(r[i]))
        }
        let threshold = peak * 0.001
        var last = 0
        for i in 0..<l.count where max(abs(l[i]), abs(r[i])) >= threshold { last = i }
        let duration = Double(last + 1) / rate
        let quietFrom = min(l.count, Int((duration + 0.1) * rate))
        var quiet = true
        for i in quietFrom..<l.count where max(abs(l[i]), abs(r[i])) >= 0.001 { quiet = false }
        return CueMeasurement(peak: peak, duration: duration, quietAfter: quiet, allFinite: finite, left: l, right: r)
    }

    /// Mono mix of a render.
    static func mono(_ s: (left: [Float], right: [Float])) -> [Float] {
        (0..<s.left.count).map { (s.left[$0] + s.right[$0]) * 0.5 }
    }

    /// Normalised cross-correlation at zero lag of two signals (trimmed to the shorter one).
    static func correlation(_ a: [Float], _ b: [Float]) -> Double {
        let n = min(a.count, b.count)
        var ab = 0.0, aa = 0.0, bb = 0.0
        for i in 0..<n {
            ab += Double(a[i]) * Double(b[i])
            aa += Double(a[i]) * Double(a[i])
            bb += Double(b[i]) * Double(b[i])
        }
        guard aa > 0, bb > 0 else { return 0 }
        return abs(ab) / (aa * bb).squareRoot()
    }

    /// Magnitude spectrum correlation (timbre similarity independent of phase): 64 bands of a naive DFT over the
    /// first `window` samples.
    static func spectrum(_ x: [Float], bands: Int = 96, rate: Double = 48_000) -> [Double] {
        let n = min(x.count, 4096)
        return (0..<bands).map { b in
            let f = 60.0 * pow(2, Double(b) / 12)
            var re = 0.0, im = 0.0
            for i in 0..<n {
                let w = 2 * Double.pi * f * Double(i) / rate
                re += Double(x[i]) * cos(w)
                im += Double(x[i]) * sin(w)
            }
            return (re * re + im * im).squareRoot()
        }
    }

    static func spectralSimilarity(_ a: [Float], _ b: [Float]) -> Double {
        let sa = spectrum(a), sb = spectrum(b)
        var ab = 0.0, aa = 0.0, bb = 0.0
        for i in 0..<sa.count {
            ab += sa[i] * sb[i]
            aa += sa[i] * sa[i]
            bb += sb[i] * sb[i]
        }
        guard aa > 0, bb > 0 else { return 0 }
        return ab / (aa * bb).squareRoot()
    }
}
