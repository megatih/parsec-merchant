// SPDX-License-Identifier: GPL-2.0-or-later
import Darwin
import Foundation
import Testing
@testable import ParsecAudio

/// AUD-046 / AUD-049: the real-time constraints. Serialized so the allocation counter sees as little foreign
/// activity as possible.
@Suite("AudioBudget", .serialized)
struct AudioBudget {
    /// A core with all 16 SFX voices busy (long cues) and music on.
    static func loadedCore() -> SynthCore {
        let core = SynthCore(sampleRate: 48_000, seed: 1)
        core.setMusic(enabled: true, mood: .tension)
        refill(core)
        return core
    }

    static func refill(_ core: SynthCore) {
        let cues: [SoundCue] = [.arrestSiren, .gameEndFanfare, .warpDeparture, .explosion]
        for i in 0..<16 { core.enqueue(CueRequest(cue: cues[i % cues.count], variant: UInt8(i % 2))) }
    }

    static func blocksInUse() -> Int {
        var stats = malloc_statistics_t()
        malloc_zone_statistics(nil, &stats)
        return Int(stats.blocks_in_use)
    }

    @Test("AUD-046 10 000 renders of 512 frames with 16 voices and music change blocks in use by fewer than 10")
    func allocationFree() {
        let core = Self.loadedCore()
        let l = UnsafeMutablePointer<Float>.allocate(capacity: 512)
        let r = UnsafeMutablePointer<Float>.allocate(capacity: 512)
        defer {
            l.deallocate()
            r.deallocate()
        }
        core.render(frameCount: 512, left: l, right: r)
        // Other suites run in parallel in this process; take the best of a few attempts.
        var best = Int.max
        for _ in 0..<4 {
            let before = Self.blocksInUse()
            for i in 0..<10_000 {
                if i % 50 == 0 { Self.refill(core) }
                core.render(frameCount: 512, left: l, right: r)
            }
            best = min(best, abs(Self.blocksInUse() - before))
            if best < 10 { break }
        }
        #expect(best < 10)
        #expect(core.activeVoices == 16)
    }

    @Test("AUD-046 the render-path sources use no allocating, locking or async APIs")
    func sourceScan() throws {
        let core = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/ParsecAudio/Core")
        let files = try FileManager.default.contentsOfDirectory(at: core, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(files.count >= 5)
        let forbidden = ["print(", "NSLock", "Mutex", "os_unfair_lock", "DispatchQueue", "await", "Task", "String(",
                         ".append(", "Array(", "Logger", "[Float]("]
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for token in forbidden {
                #expect(!text.contains(token), "\(file.lastPathComponent) contains \(token)")
            }
        }
    }

    @Test("AUD-049 one second at 48 kHz with 16 voices and music renders within the budget")
    func renderBudget() {
        let core = Self.loadedCore()
        let l = UnsafeMutablePointer<Float>.allocate(capacity: 512)
        let r = UnsafeMutablePointer<Float>.allocate(capacity: 512)
        defer {
            l.deallocate()
            r.deallocate()
        }
        core.render(frameCount: 512, left: l, right: r)
        var best = Duration.seconds(10)
        let clock = ContinuousClock()
        for _ in 0..<3 {
            Self.refill(core)
            let elapsed = clock.measure {
                for _ in 0..<(48_000 / 512) { core.render(frameCount: 512, left: l, right: r) }
            }
            best = min(best, elapsed)
        }
        #if DEBUG
        let budget = Duration.milliseconds(250)
        let configuration = "debug"
        #else
        let budget = Duration.milliseconds(50)
        let configuration = "release"
        #endif
        let ms = Double(best.components.attoseconds) / 1e15 + Double(best.components.seconds) * 1000
        // scripts/bench-audio.sh greps this line (the QA-REPORT AUD-049 row records it).
        print("AUD-049 \(configuration): rendered 1 s of audio in \(String(format: "%.2f", ms)) ms (budget \(budget))")
        #expect(best <= budget, "rendered 1 s in \(best)")
    }
}
