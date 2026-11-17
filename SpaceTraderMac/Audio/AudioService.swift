// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Observation
import ParsecAudio
import os

/// The output the audio service drives: `AudioOutput` in the app, a fake in tests.
@MainActor
protocol AudioOutputting: AnyObject {
    func start() throws(AudioOutputError)
    func stop()
    func pause()
    func resume() throws(AudioOutputError)
    func rebuild() throws(AudioOutputError)
    @discardableResult func enqueue(_ request: CueRequest) -> Bool
    func setGains(overall: Float, effects: Float, music: Float)
    func setMusic(enabled: Bool, mood: MusicMood)
    func stopAll()
    var renderCount: Int { get }
    var droppedRequests: Int { get }
    var activeVoices: Int { get }
    func observeConfigurationChanges(_ handler: @escaping @Sendable () -> Void)
}

extension AudioOutput: AudioOutputting {}

/// AUD-008…012, AUD-036: the session's audio. Maps steps to cues (AUD-031), schedules them (AUD-033/034), applies the
/// Sound settings live (AUD-043), pauses when muted or inactive (AUD-012), survives device changes (AUD-010) and
/// reports failures through `status` and the log only (AUD-011). Audio never changes game state.
@Observable @MainActor
final class AudioService: SessionAudio {
    /// Seconds an inactive app keeps the engine before pausing, and a Mute before pausing (AUD-012).
    static let inactivePauseDelay: Duration = .seconds(1)
    static let mutePauseDelay: Duration = .seconds(2)
    /// Failed restarts in a row before giving up until the next settings change or activation (AUD-010).
    static let maxRestarts = 3

    private(set) var status: AudioStatus = .idle
    private(set) var errorCount = 0
    private(set) var settings: SoundSettings

    @ObservationIgnored let output: any AudioOutputting
    @ObservationIgnored let scheduler: CueScheduler
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let sleep: @Sendable (Duration) async -> Void
    @ObservationIgnored private(set) var mood: MusicMood = .calm
    @ObservationIgnored private(set) var isAppActive = true
    @ObservationIgnored private(set) var hasStarted = false
    @ObservationIgnored private(set) var pauseTask: Task<Void, Never>?
    @ObservationIgnored private var defaultsObserver: (any NSObjectProtocol)?
    @ObservationIgnored private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "io.github.megatih.ParsecMerchant",
                                                    category: "audio")

    init(output: any AudioOutputting, defaults: UserDefaults,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.output = output
        self.defaults = defaults
        self.sleep = sleep
        settings = SoundSettings(defaults: defaults)
        scheduler = CueScheduler(now: now)
        scheduler.sink = { [weak self] request in self?.output.enqueue(request) }
    }

    isolated deinit {
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
    }

    /// Launch (AUD-012): observe settings and device changes, and start unless Mute is on.
    func activate() {
        output.observeConfigurationChanges { [weak self] in
            MainActor.assumeIsolated { self?.handleConfigurationChange() }
        }
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                                  object: defaults, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadSettings() }
        }
        applyGains()
        applyMusic()
        if !settings.muted { startEngine() }
    }

    // MARK: SessionAudio

    func play(record: StepRecord) {
        guard status == .running else { return }
        scheduler.schedule(AudioCueMap.requests(for: record))
    }

    func play(app: AppCue) {
        guard status == .running else { return }
        scheduler.schedule([AudioCueMap.cue(for: app)])
    }

    func setMood(_ mood: MusicMood) {
        guard mood != self.mood else { return }
        self.mood = mood
        applyMusic()
    }

    func transit(_ event: TransitAudioEvent) {
        scheduler.handle(event)
    }

    func setAppActive(_ active: Bool) {
        guard active != isAppActive else { return }
        isAppActive = active
        applyGains()
        if active, case .failed = status { startEngine() }
        updatePower()
    }

    // MARK: Settings (AUD-043)

    /// Re-reads the Sound settings and applies them live (30 ms ramps in the synth, no restart).
    func reloadSettings() {
        let new = SoundSettings(defaults: defaults)
        let failed = if case .failed = status { true } else { false }
        guard new != settings || failed else { return }
        settings = new
        applyGains()
        applyMusic()
        if failed { startEngine() }
        updatePower()
    }

    private func applyGains() {
        let g = settings.gains(isAppActive: isAppActive)
        output.setGains(overall: g.overall, effects: g.effects, music: g.music)
    }

    private func applyMusic() {
        output.setMusic(enabled: settings.musicEnabled, mood: mood)
    }

    // MARK: Power (AUD-012)

    private var wantsPause: Bool { settings.muted || (!isAppActive && settings.muteWhenInactive) }

    private func updatePower() {
        if wantsPause {
            schedulePause(after: settings.muted ? Self.mutePauseDelay : Self.inactivePauseDelay)
        } else {
            pauseTask?.cancel()
            pauseTask = nil
            guard status == .idle else { return }
            if hasStarted { resumeEngine() } else { startEngine() }
        }
    }

    private func schedulePause(after delay: Duration) {
        guard status == .running, pauseTask == nil else { return }
        let sleep = sleep
        pauseTask = Task { [weak self] in
            await sleep(delay)
            guard !Task.isCancelled else { return }
            self?.pauseNow()
        }
    }

    private func pauseNow() {
        pauseTask = nil
        guard wantsPause, status == .running else { return }
        output.stopAll()
        output.pause()
        scheduler.handle(.cancelled)
        status = .idle
    }

    // MARK: Engine lifecycle (AUD-009…011)

    private func startEngine() {
        do {
            try output.start()
            hasStarted = true
            status = .running
            applyGains()
            applyMusic()
        } catch {
            record(error)
        }
    }

    private func resumeEngine() {
        do {
            try output.resume()
            status = .running
        } catch {
            record(error)
        }
    }

    /// AUD-010: rebuild at the new hardware rate; three failures in a row give up until the next settings change or
    /// activation.
    func handleConfigurationChange() {
        guard hasStarted else { return }
        let wasPaused = status == .idle
        var lastError: AudioOutputError?
        for _ in 0..<Self.maxRestarts {
            do {
                try output.rebuild()
                status = .running
                applyGains()
                applyMusic()
                if wasPaused || wantsPause { pauseNow() }
                return
            } catch {
                record(error)
                lastError = error
            }
        }
        if case let .engineFailed(code) = lastError {
            status = .failed(code: code)
        } else {
            status = .failed(code: -1)
        }
    }

    /// AUD-011: one log line and one count per failure; never an alert.
    private func record(_ error: AudioOutputError) {
        errorCount += 1
        switch error {
        case .noOutputDevice:
            status = .noOutputDevice
            logger.error("Audio output unavailable: no output device")
        case let .engineFailed(code):
            status = .failed(code: code)
            logger.error("Audio engine failed to start (code \(code, privacy: .public))")
        }
    }

    // MARK: Diagnostics (AUD-050)

    var renderCount: Int { output.renderCount }
    var droppedRequests: Int { output.droppedRequests }
    var activeVoices: Int { output.activeVoices }

    /// Plays one cue directly (the launch check plays every cue and variant).
    func play(cue: SoundCue, variant: UInt8 = 0) {
        guard status == .running else { return }
        output.enqueue(CueRequest(cue: cue, variant: variant))
    }
}

/// AUD-044: the audio and haptics services for a launch. `-PMAudio off` creates no engine or output at all.
enum SessionAudioFactory {
    static func make(options: LaunchOptions, defaults: UserDefaults,
                     output: () -> any AudioOutputting = { AudioOutput() },
                     performer: () -> any HapticPerforming = { SystemHapticPerformer() })
        -> (audio: any SessionAudio, haptics: any SessionHaptics) {
        if options.audioOff { return (SilentAudio(), NoHaptics()) }
        let audio = AudioService(output: output(), defaults: defaults)
        audio.activate()
        return (audio, HapticsService(performer: performer(), defaults: defaults))
    }
}
