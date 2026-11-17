// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecAudio
import ParsecEngine
import ParsecInsights
import ParsecPersistence
import Testing
@testable import ParsecMerchant

/// An audio output that records what the service asks of it.
@MainActor
final class FakeAudioOutput: AudioOutputting {
    var requests: [CueRequest] = []
    var gains: [(overall: Float, effects: Float, music: Float)] = []
    var music: [(enabled: Bool, mood: MusicMood)] = []
    var startError: AudioOutputError?
    var rebuildErrors: [AudioOutputError] = []
    var isRunning = false
    var isPaused = false
    var starts = 0, rebuilds = 0, pauses = 0, resumes = 0, stops = 0, stopAlls = 0
    var configurationHandler: (@Sendable () -> Void)?

    func start() throws(AudioOutputError) {
        starts += 1
        if let startError { throw startError }
        isRunning = true
    }

    func stop() {
        stops += 1
        isRunning = false
    }

    func pause() {
        pauses += 1
        isPaused = true
    }

    func resume() throws(AudioOutputError) {
        resumes += 1
        isPaused = false
    }

    func rebuild() throws(AudioOutputError) {
        rebuilds += 1
        if !rebuildErrors.isEmpty { throw rebuildErrors.removeFirst() }
        isRunning = true
    }

    func enqueue(_ request: CueRequest) -> Bool {
        requests.append(request)
        return true
    }

    func setGains(overall: Float, effects: Float, music: Float) { gains.append((overall, effects, music)) }
    func setMusic(enabled: Bool, mood: MusicMood) { music.append((enabled, mood)) }
    func stopAll() { stopAlls += 1 }
    var renderCount: Int { 0 }
    var droppedRequests: Int { 0 }
    var activeVoices: Int { 0 }
    func observeConfigurationChanges(_ handler: @escaping @Sendable () -> Void) { configurationHandler = handler }

    var cues: [SoundCue] { requests.map(\.cue) }
}

/// Records the session's audio calls (AUD-036).
@MainActor
final class RecordingAudio: SessionAudio {
    var records: [StepRecord] = []
    var apps: [AppCue] = []
    var moods: [MusicMood] = []
    var transits: [TransitAudioEvent] = []
    var activations: [Bool] = []

    func play(record: StepRecord) { records.append(record) }
    func play(app: AppCue) { apps.append(app) }
    func setMood(_ mood: MusicMood) { moods.append(mood) }
    func transit(_ event: TransitAudioEvent) { transits.append(event) }
    func setAppActive(_ active: Bool) { activations.append(active) }
    var status: AudioStatus { .running }
}

/// Records the session's haptics calls.
@MainActor
final class RecordingSessionHaptics: SessionHaptics {
    var records: [StepRecord] = []
    var apps: [AppHaptic] = []

    func perform(record: StepRecord) { records.append(record) }
    func perform(app: AppHaptic) { apps.append(app) }
    func setAppActive(_ active: Bool) {}
}

/// Records the patterns `HapticsService` performs (AUD-040).
@MainActor
final class HapticRecorder: HapticPerforming {
    var patterns: [HapticPattern] = []
    func perform(_ pattern: HapticPattern) { patterns.append(pattern) }
}

/// Unlocks one achievement on every observed step that produced journal output.
@MainActor
struct OneAchievement: SessionAchievements {
    func observe(_ output: JournalStepOutput, gameID: String, state: GameState) -> [AchievementID] {
        AchievementID.allCases.first.map { [$0] } ?? []
    }
    var records: [AchievementRecord] { [] }
    func reset() throws {}
}

/// A settable clock for the scheduler and haptics.
@MainActor
final class FakeClock {
    var now: TimeInterval = 100
}

@MainActor
enum AudioFixtures {
    static func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "pm-audio-\(UUID().uuidString)"))
    }

    static func session(audio: any SessionAudio, haptics: any SessionHaptics = NoHaptics(), fastTravel: Bool = true,
                        achievements: any SessionAchievements = NoAchievements(), seed: UInt64 = 1) throws -> GameSession {
        let id = UUID().uuidString
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pm-audio-\(id)", isDirectory: true)
        var options = LaunchOptions()
        options.seed = seed
        options.fastTravel = fastTravel
        let s = GameSession(stores: SessionStores(root: root, appVersion: "test"), launchOptions: options,
                            defaults: try defaults(), audio: audio, haptics: haptics, achievements: achievements)
        s.playbackClock = nil
        return s
    }

    /// An `AudioService` over a fake output with an immediate pause timer.
    static func service(_ output: FakeAudioOutput = FakeAudioOutput(), defaults: UserDefaults? = nil,
                        clock: FakeClock = FakeClock()) throws -> AudioService {
        let service = AudioService(output: output, defaults: try defaults ?? Self.defaults(), now: { clock.now },
                                   sleep: { _ in })
        service.activate()
        return service
    }

    static let base = TransitFixtures.base

    /// A record of `events` on the docked base state.
    static func record(_ events: [GameEvent], before: GameState = base, after: GameState = base,
                       command: Command = .warp) -> StepRecord {
        StepRecord(command: command, acknowledged: [], before: before, result: StepResult(events: events), after: after)
    }

    /// An encounter state: the player carries `playerWeapons` at `playerHull`, the opponent `opponentWeapons`.
    static func encounter(type: EncounterType = .pirateAttack, playerWeapons: [WeaponType] = [.militaryLaser, .pulseLaser],
                          opponentWeapons: [WeaponType] = [.beamLaser], playerHull: Int? = nil,
                          opponentHull: Int? = nil, continueAttacking: Bool = false) -> GameState {
        var s = base
        var opponent = Ship(type: .gnat, spec: s.ruleset.tables.ship(.gnat))
        opponent.weapons = opponentWeapons
        if let opponentHull { opponent.hull = opponentHull }
        var enc = EncounterState(type: type, opponent: opponent, clicks: 7)
        enc.continueAttacking = continueAttacking
        s.phase = .encounter(enc)
        s.commander.ship.weapons = playerWeapons
        if let playerHull { s.commander.ship.hull = playerHull }
        return s
    }

    static func maxHull(_ s: GameState) -> Int { s.commander.ship.hullStrength(s.ruleset) }
}
