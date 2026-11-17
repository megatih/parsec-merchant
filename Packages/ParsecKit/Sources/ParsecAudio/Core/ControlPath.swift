// SPDX-License-Identifier: GPL-2.0-or-later
import Synchronization

/// AUD-003: one request to play a cue. Plain old data, copied into the request ring without allocation.
public struct CueRequest: Sendable, Equatable, BitwiseCopyable {
    public var cue: SoundCue
    public var variant: UInt8
    /// Transposition in semitones (the coin cues use `amountPitch`).
    public var pitchSemitones: Float
    /// Linear request gain (multiplied with the effects and overall gains).
    public var gain: Float
    /// Stereo position, −1 (left) … 1 (right).
    public var pan: Float
    /// Start delay in seconds, 0 … 2.
    public var delay: Float

    public init(cue: SoundCue, variant: UInt8 = 0, pitchSemitones: Float = 0, gain: Float = 1, pan: Float = 0,
                delay: Float = 0) {
        self.cue = cue
        self.variant = variant
        self.pitchSemitones = pitchSemitones
        self.gain = gain
        self.pan = pan
        self.delay = delay
    }
}

/// A single-producer single-consumer ring of `CueRequest`s with fixed capacity (research 05 §3). The producer (the
/// main actor) calls `push`, the consumer (the render thread) calls `pop`. Neither side blocks, locks or allocates.
nonisolated final class RequestRing: @unchecked Sendable {
    // @unchecked: `slots` is written only by the producer at indices it owns (head) and read only by the consumer at
    // indices it owns (tail); ownership moves with the acquiring/releasing stores of `head` and `tail`.
    let capacity: Int
    private let slots: UnsafeMutablePointer<CueRequest>
    private let head = Atomic<Int>(0)
    private let tail = Atomic<Int>(0)

    init(capacity: Int) {
        self.capacity = max(1, capacity)
        slots = UnsafeMutablePointer<CueRequest>.allocate(capacity: self.capacity)
        slots.initialize(repeating: CueRequest(cue: .uiTick), count: self.capacity)
    }

    deinit {
        slots.deinitialize(count: capacity)
        slots.deallocate()
    }

    /// Producer side. Returns false when the ring is full.
    func push(_ request: CueRequest) -> Bool {
        let h = head.load(ordering: .relaxed)
        let t = tail.load(ordering: .acquiring)
        if h &- t >= capacity { return false }
        slots[h % capacity] = request
        head.store(h &+ 1, ordering: .releasing)
        return true
    }

    /// Consumer side. Returns nil when the ring is empty.
    func pop() -> CueRequest? {
        let t = tail.load(ordering: .relaxed)
        let h = head.load(ordering: .acquiring)
        if t == h { return nil }
        let request = slots[t % capacity]
        tail.store(t &+ 1, ordering: .releasing)
        return request
    }

    /// Number of queued requests (approximate from either side).
    var count: Int { head.load(ordering: .acquiring) &- tail.load(ordering: .acquiring) }
}

/// A `Float` stored as its bit pattern in an atomic word.
nonisolated struct AtomicFloatBox: ~Copyable {
    private let bits: Atomic<UInt32>

    init(_ value: Float) { bits = Atomic(value.bitPattern) }

    func load() -> Float { Float(bitPattern: bits.load(ordering: .relaxed)) }
    func store(_ value: Float) { bits.store(value.bitPattern, ordering: .relaxed) }
}
