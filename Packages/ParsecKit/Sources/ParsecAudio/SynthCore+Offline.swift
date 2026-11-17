// SPDX-License-Identifier: GPL-2.0-or-later

public extension SynthCore {
    /// AUD-007: renders `requests` (all enqueued before the first block) for `seconds` in 512-frame blocks. For tests
    /// and tools only: it allocates the result arrays and is not on the real-time path. Equal inputs, seed and sample
    /// rate give bit-identical output.
    func renderOffline(requests: [CueRequest], seconds: Double) -> (left: [Float], right: [Float]) {
        for r in requests { enqueue(r) }
        let total = max(0, Int(seconds * sampleRate))
        var left = [Float](repeating: 0, count: total)
        var right = [Float](repeating: 0, count: total)
        let block = 512
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                guard let lb = l.baseAddress, let rb = r.baseAddress else { return }
                var offset = 0
                while offset < total {
                    let n = min(block, total - offset)
                    render(frameCount: n, left: lb + offset, right: rb + offset)
                    offset += n
                }
            }
        }
        return (left, right)
    }
}
