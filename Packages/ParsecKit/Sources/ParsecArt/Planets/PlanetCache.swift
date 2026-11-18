// SPDX-License-Identifier: GPL-2.0-or-later
import CoreGraphics
import Foundation
import Synchronization

/// A projected planet image; `CGImage` is immutable, so it may cross threads.
public struct PlanetImage: @unchecked Sendable {
    public let cgImage: CGImage

    public init(_ cgImage: CGImage) { self.cgImage = cgImage }

    public var byteCount: Int { cgImage.bytesPerRow * cgImage.height }
}

/// ART-080: a byte-bounded LRU for baked maps and projected images, usable from any thread.
public final class PlanetCache: Sendable {
    public static let shared = PlanetCache(byteLimit: 32 << 20)

    private struct Entry {
        var value: any Sendable
        var bytes: Int
        var tick: UInt64
    }

    private struct State {
        var store: [AnyHashable: Entry] = [:]
        var bytes = 0
        var tick: UInt64 = 0
    }

    public let byteLimit: Int
    private let state = Mutex(State())

    public init(byteLimit: Int) { self.byteLimit = byteLimit }

    public var byteCount: Int { state.withLock { $0.bytes } }
    public var count: Int { state.withLock { $0.store.count } }

    /// The cached value for `key`, or nil.
    public func peek<K: Hashable & Sendable, V: Sendable>(_ key: K, as type: V.Type = V.self) -> V? {
        state.withLock { s in
            let k = AnyHashable(key)
            guard let hit = s.store[k], let v = hit.value as? V else { return nil }
            s.tick &+= 1
            s.store[k]?.tick = s.tick
            return v
        }
    }

    /// The cached value for `key`, computing and storing it on a miss. `make` runs outside the lock.
    public func value<K: Hashable & Sendable, V: Sendable>(_ key: K, bytes: (V) -> Int, make: () -> V) -> V {
        if let hit: V = peek(key) { return hit }
        let v = make()
        insert(key, v, bytes: bytes(v))
        return v
    }

    public func insert<K: Hashable & Sendable, V: Sendable>(_ key: K, _ value: V, bytes: Int) {
        guard bytes <= byteLimit else { return }
        state.withLock { s in
            let k = AnyHashable(key)
            if let old = s.store[k] { s.bytes -= old.bytes }
            s.tick &+= 1
            s.store[k] = Entry(value: value, bytes: bytes, tick: s.tick)
            s.bytes += bytes
            while s.bytes > byteLimit, let oldest = s.store.min(by: { $0.value.tick < $1.value.tick })?.key {
                s.bytes -= s.store[oldest]?.bytes ?? 0
                s.store[oldest] = nil
            }
        }
    }
}
