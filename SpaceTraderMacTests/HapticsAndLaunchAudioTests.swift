// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import Foundation
import ParsecAudio
import ParsecEngine
import SwiftUI
import Testing
@testable import ParsecMerchant

@MainActor
@Suite("Haptics (AUD §6)")
struct HapticsTests {
    static func heavyHit(loss percent: Int) -> StepRecord {
        let before = AudioFixtures.encounter(playerHull: AudioFixtures.maxHull(AudioFixtures.base))
        let max = AudioFixtures.maxHull(before)
        let hull = max - max * percent / 100
        var after = before
        after.commander.ship.hull = hull
        return AudioFixtures.record([.combatRound(round: 1, playerHit: true, opponentHit: false, playerHull: hull,
                                                  opponentHull: 10)], before: before, after: after)
    }

    @Test("AUD-040 UI-ENC-100 the map: snaps → alignment, departure → generic, heavy hit and destruction → levelChange")
    func map() {
        #expect(HapticMap.pattern(for: .quantitySnap) == .alignment && HapticMap.pattern(for: .sliderFull) == .alignment)
        #expect(HapticMap.pattern(for: AudioFixtures.record([.departed(from: 0, to: 1, viaWormhole: false)])) == .generic)
        #expect(HapticMap.pattern(for: Self.heavyHit(loss: 15)) == .levelChange)
        #expect(HapticMap.pattern(for: Self.heavyHit(loss: 10)) == nil)
        #expect(HapticMap.pattern(for: AudioFixtures.record([.playerDestroyed])) == .levelChange)
        #expect(HapticMap.pattern(for: AudioFixtures.record([.bothDestroyed])) == .levelChange)
        // Nothing else produces haptics (AUD-053: the event map is exhaustive).
        let others = GameEventKind.allCases.filter { ![.departed, .playerDestroyed, .bothDestroyed].contains($0) }
        for kind in others { #expect(HapticMap.pattern(for: kind.fixture) == nil, "\(kind)") }
        #expect(HapticMap.quantitySnaps(requested: 20, maximum: 12) && HapticMap.quantitySnaps(requested: 12, maximum: 12))
        #expect(!HapticMap.quantitySnaps(requested: 5, maximum: 12) && !HapticMap.quantitySnaps(requested: 5, maximum: 0))
        #expect(SystemHapticPerformer.feedback(.levelChange) == .levelChange)
        #expect(SystemHapticPerformer.feedback(.alignment) == .alignment && SystemHapticPerformer.feedback(.generic) == .generic)
    }

    @Test("AUD-041 only while active, at most once per 100 ms and per step, only with the setting on")
    func rules() throws {
        let recorder = HapticRecorder()
        let clock = FakeClock()
        let defaults = try AudioFixtures.defaults()
        let service = HapticsService(performer: recorder, defaults: defaults, now: { clock.now })
        let departure = AudioFixtures.record([.departed(from: 0, to: 1, viaWormhole: false), .playerDestroyed])
        service.perform(record: departure)
        #expect(recorder.patterns == [.levelChange])  // one per step, the strongest
        clock.now += 0.05
        service.perform(app: .quantitySnap)
        #expect(recorder.patterns.count == 1)  // within 100 ms
        clock.now += 0.1
        service.perform(app: .quantitySnap)
        #expect(recorder.patterns == [.levelChange, .alignment])
        service.setAppActive(false)
        clock.now += 1
        service.perform(app: .sliderFull)
        #expect(recorder.patterns.count == 2)
        service.setAppActive(true)
        defaults.set(false, forKey: SoundSettingsKey.hapticsEnabled)
        service.perform(app: .sliderFull)
        #expect(recorder.patterns.count == 2)
        defaults.set(true, forKey: SoundSettingsKey.hapticsEnabled)
        // Auto-repeat: one round per step → at most one haptic per round even with several heavy rounds.
        let rounds = AudioFixtures.record([
            .combatRound(round: 1, playerHit: true, opponentHit: false, playerHull: 50, opponentHull: 10),
            .combatRound(round: 2, playerHit: true, opponentHit: false, playerHull: 20, opponentHull: 10),
        ], before: AudioFixtures.encounter(playerHull: 100))
        service.perform(record: rounds)
        #expect(recorder.patterns == [.levelChange, .alignment, .levelChange])
    }
}

@MainActor
@Suite("Launch with audio on (AUD-050)", .serialized)
struct LaunchAudioTests {
    @Test("AUD-050 AUD-008 AUD-009 the real output at overall 0 plays every cue and music with no errors or drops")
    func launchWithAudioOn() async throws {
        let defaults = try AudioFixtures.defaults()
        defaults.set(0.0, forKey: SoundSettingsKey.overall)
        defaults.set(true, forKey: SoundSettingsKey.musicEnabled)
        let service = AudioService(output: AudioOutput(), defaults: defaults)
        service.activate()
        if service.status == .noOutputDevice {
            withKnownIssue("No audio output device on this machine (AUD-050 records the status and skips)") {
                Issue.record("status \(service.status)")
            }
            return
        }
        #expect(service.status == .running)
        service.setMood(.travel)
        // Every cue and variant, in batches small enough that voice stealing never drops a request.
        var batch = 0
        for cue in SoundCue.allCases {
            for v in 0..<cue.variantCount {
                service.play(cue: cue, variant: UInt8(v))
                batch += 1
                if batch == 8 {
                    batch = 0
                    try await Task.sleep(for: .milliseconds(600))
                }
            }
        }
        try await Task.sleep(for: .seconds(2))
        #expect(service.status == .running)
        #expect(service.renderCount > 0)
        #expect(service.errorCount == 0)
        #expect(service.droppedRequests == 0)
        // The render block runs off the main actor: blocking the main thread does not stop rendering.
        let before = service.renderCount
        Self.blockMainThread(seconds: 0.3)
        #expect(service.renderCount > before)
        (service.output as? AudioOutput)?.stop()
    }

    /// Busy-blocks the calling (main) thread.
    nonisolated static func blockMainThread(seconds: Double) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {}
    }
}
