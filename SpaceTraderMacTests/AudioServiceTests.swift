// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecAudio
import ParsecEngine
import Testing
@testable import ParsecMerchant

@MainActor
@Suite("Audio service, scheduler and settings (AUD §2, §4, §7)")
struct AudioServiceTests {
    // MARK: Scheduling (AUD-033 / AUD-034)

    @Test("AUD-033 cues revealed by the playback wait for its end; departed plays at once; ticks at 5/10/15/20")
    func playbackHolding() {
        let clock = FakeClock()
        var sent: [CueRequest] = []
        let scheduler = CueScheduler(now: { clock.now }, sink: { sent.append($0) })
        let record = AudioFixtures.record([.departed(from: 0, to: 1, viaWormhole: false), .uneventfulTrip,
                                           .arrived(system: 1), .boughtFuel(units: 3, cost: 6)])
        scheduler.handle(.started)
        scheduler.schedule(AudioCueMap.requests(for: record))
        #expect(sent.map(\.cue) == [.warpDeparture])
        #expect(scheduler.held.map(\.cue) == [.arrival, .fuelFill])
        for click in 1...20 {
            clock.now += 0.06
            scheduler.handle(.tick(clicksFlown: click))
        }
        #expect(sent.filter { $0.cue == .uiTick }.count == 4)
        clock.now += 0.1
        scheduler.handle(.ended)
        #expect(sent.suffix(2).map(\.cue) == [.arrival, .fuelFill])
        #expect(sent.suffix(2).first?.delay == 0)
        #expect(scheduler.held.isEmpty && !scheduler.isPlaybackRunning)
    }

    @Test("AUD-033 skipping releases at once; with Fast travel the order is kept by offsets; cancel drops held cues")
    func fastTravelAndSkip() {
        let clock = FakeClock()
        var sent: [CueRequest] = []
        let scheduler = CueScheduler(now: { clock.now }, sink: { sent.append($0) })
        let record = AudioFixtures.record([.departed(from: 0, to: 1, viaWormhole: true),
                                           .encounterStarted(type: .policeInspect, opponent: .gnat, clicks: 9,
                                                             playerCloaked: false)])
        scheduler.schedule(AudioCueMap.requests(for: record))
        #expect(sent.map(\.cue) == [.warpDeparture, .encounterStinger])
        #expect(sent[0].delay == 0 && sent[1].delay == Float(CombatCueTiming.fastArrivalDelay))
        sent = []
        clock.now += 5
        scheduler.handle(.started)
        scheduler.schedule(AudioCueMap.requests(for: record))
        scheduler.handle(.ended)  // Skip
        #expect(sent.map(\.cue) == [.warpDeparture, .encounterStinger] && sent[1].delay == 0)
        clock.now += 5
        scheduler.handle(.started)
        scheduler.schedule(AudioCueMap.requests(for: record))
        scheduler.handle(.cancelled)
        scheduler.handle(.ended)
        #expect(sent.count == 3)
    }

    @Test("AUD-034 an identical cue within 60 ms of the previous one merges; auto-repeat rounds queue one round each")
    func mergingAcrossSteps() {
        let clock = FakeClock()
        var sent: [CueRequest] = []
        let scheduler = CueScheduler(now: { clock.now }, sink: { sent.append($0) })
        scheduler.schedule([ScheduledCue(cue: .coinIn)])
        clock.now += 0.03
        scheduler.schedule([ScheduledCue(cue: .coinIn)])
        clock.now += 0.1
        scheduler.schedule([ScheduledCue(cue: .coinIn)])
        #expect(sent.count == 2)
        sent = []
        let before = AudioFixtures.encounter(continueAttacking: true)
        let round = AudioFixtures.record([.combatRound(round: 2, playerHit: true, opponentHit: true, playerHull: 99,
                                                       opponentHull: 1)], before: before, after: before,
                                         command: .encounter(.autoRepeat))
        for _ in 0..<3 {
            clock.now += 0.6
            let count = sent.count
            scheduler.schedule(AudioCueMap.requests(for: round))
            #expect(sent.count - count <= 4)
            #expect(sent.suffix(sent.count - count).allSatisfy { $0.delay <= 0.55 })
        }
    }

    @Test("AUD-033 in the session: warp plays at once, the arrival waits for the playback, ticks play")
    func sessionPlayback() throws {
        var checked = false
        for seed in UInt64(1)...40 where !checked {
            let output = FakeAudioOutput()
            let s = try AudioFixtures.session(audio: try AudioFixtures.service(output), fastTravel: false, seed: seed)
            s.requestQuickStart()
            output.requests = []
            s.send(.selectNextTarget(forward: true))
            s.send(.warp)
            // A trip whose encounter comes at the first click has no playback; its stinger plays at once.
            guard let playback = s.transitPlayback, playback.tickCount >= 5 else { continue }
            checked = true
            #expect(output.cues == [.warpDeparture])
            TransitFixtures.play(s)
            #expect(output.cues.contains(.uiTick))
            #expect(output.cues.contains(.arrival) || output.cues.contains(.encounterStinger))
        }
        #expect(checked)
    }

    // MARK: Service lifecycle (AUD-009…012)

    @Test("AUD-009 AUD-011 no output device: status and one error, nothing played, the game stays playable")
    func noDevice() throws {
        let output = FakeAudioOutput()
        output.startError = .noOutputDevice
        let service = try AudioFixtures.service(output)
        #expect(service.status == .noOutputDevice && service.errorCount == 1)
        service.play(app: .testSound)
        #expect(output.requests.isEmpty)
        let s = try AudioFixtures.session(audio: service)
        s.requestQuickStart()
        s.send(.buyFuel(credits: 10))
        #expect(s.state != nil)
        let failing = FakeAudioOutput()
        failing.startError = .engineFailed(code: -50)
        let failed = try AudioFixtures.service(failing)
        #expect(failed.status == .failed(code: -50) && failed.errorCount == 1)
    }

    @Test("AUD-010 a device change rebuilds; three failed restarts give up until a settings change or activation")
    func configurationChange() throws {
        let output = FakeAudioOutput()
        let defaults = try AudioFixtures.defaults()
        let service = try AudioFixtures.service(output, defaults: defaults)
        #expect(service.status == .running)
        output.configurationHandler?()
        #expect(output.rebuilds == 1 && service.status == .running)
        output.rebuildErrors = [.engineFailed(code: 1), .engineFailed(code: 2), .engineFailed(code: 3)]
        service.handleConfigurationChange()
        #expect(output.rebuilds == 4 && service.status == .failed(code: 3) && service.errorCount == 3)
        defaults.set(0.5, forKey: SoundSettingsKey.overall)
        service.reloadSettings()
        #expect(service.status == .running && output.starts == 2)
    }

    @Test("AUD-011 statuses have their Settings titles")
    func statusTitles() {
        #expect(String(localized: AudioStatus.running.title) == "Running")
        #expect(String(localized: AudioStatus.offForLaunch.title) == "Off for this launch")
        #expect(String(localized: AudioStatus.idle.title) == "Paused")
        #expect(String(localized: AudioStatus.noOutputDevice.title) == "No audio output device")
        #expect(String(localized: AudioStatus.failed(code: 1).title) == "Audio couldn't start")
    }

    @Test("AUD-012 power: start unless muted; overall 0 keeps running; inactive pauses after the delay and resumes")
    func power() async throws {
        let defaults = try AudioFixtures.defaults()
        defaults.set(true, forKey: SoundSettingsKey.muted)
        let mutedOutput = FakeAudioOutput()
        let muted = try AudioFixtures.service(mutedOutput, defaults: defaults)
        #expect(muted.status == .idle && mutedOutput.starts == 0)
        defaults.set(false, forKey: SoundSettingsKey.muted)
        muted.reloadSettings()
        #expect(muted.status == .running && mutedOutput.starts == 1)

        let output = FakeAudioOutput()
        let d2 = try AudioFixtures.defaults()
        d2.set(0, forKey: SoundSettingsKey.overall)
        let service = try AudioFixtures.service(output, defaults: d2)
        #expect(service.status == .running && output.gains.last?.overall == 0)
        service.setAppActive(false)
        #expect(output.gains.last?.overall == 0)
        await service.pauseTask?.value
        #expect(service.status == .idle && output.pauses == 1)
        service.play(app: .testSound)
        #expect(output.requests.isEmpty)  // discarded while paused, not queued
        service.setAppActive(true)
        #expect(service.status == .running && output.resumes == 1)

        // Mute pauses too (after its delay); turning it off resumes.
        d2.set(true, forKey: SoundSettingsKey.muted)
        service.reloadSettings()
        await service.pauseTask?.value
        #expect(service.status == .idle)
        d2.set(false, forKey: SoundSettingsKey.muted)
        service.reloadSettings()
        #expect(service.status == .running)

        // "Mute when inactive" off keeps playing in the background.
        d2.set(false, forKey: SoundSettingsKey.muteWhenInactive)
        service.reloadSettings()
        service.setAppActive(false)
        #expect(service.pauseTask == nil && service.status == .running)
        #expect(AudioService.inactivePauseDelay == .seconds(1) && AudioService.mutePauseDelay == .seconds(2))
    }

    // MARK: Settings (AUD-043 / AUD-006)

    @Test("AUD-043 defaults, clamping and the launch-argument override")
    func settings() throws {
        let d = try AudioFixtures.defaults()
        #expect(SoundSettings(defaults: d) == SoundSettings.standard)
        let s = SoundSettings.standard
        #expect(s.overall == 0.8 && s.effects == 1 && s.music == 0.5 && !s.muted && !s.musicEnabled
                && s.muteWhenInactive && s.hapticsEnabled)
        #expect([SoundSettingsKey.overall, SoundSettingsKey.effects, SoundSettingsKey.music, SoundSettingsKey.muted,
                 SoundSettingsKey.musicEnabled, SoundSettingsKey.muteWhenInactive, SoundSettingsKey.hapticsEnabled]
                == ["settings.sound.master", "settings.sound.effects", "settings.sound.music", "settings.sound.muted",
                    "settings.sound.musicEnabled", "settings.sound.muteWhenInactive", "settings.haptics.enabled"])
        d.set(4.0, forKey: SoundSettingsKey.overall)
        d.set(-1.0, forKey: SoundSettingsKey.effects)
        #expect(SoundSettings(defaults: d).overall == 1 && SoundSettings(defaults: d).effects == 0)
        // The argument domain (`-settings.sound.master 0`) wins over the stored value for this launch.
        d.set(0.8, forKey: SoundSettingsKey.overall)
        let standard = UserDefaults.standard
        let previous = standard.volatileDomain(forName: UserDefaults.argumentDomain)
        var arguments = previous
        arguments[SoundSettingsKey.overall] = "0"
        standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        defer { standard.setVolatileDomain(previous, forName: UserDefaults.argumentDomain) }
        #expect(SoundSettings(defaults: standard).overall == 0)
    }

    @Test("AUD-006 AUD-043 settings apply live as slider values: mute and inactivity ramp the overall to zero")
    func liveSettings() throws {
        let output = FakeAudioOutput()
        let d = try AudioFixtures.defaults()
        let service = try AudioFixtures.service(output, defaults: d)
        #expect(output.gains.last.map { $0.overall == 0.8 && $0.effects == 1 && $0.music == 0.5 } == true)
        d.set(0.25, forKey: SoundSettingsKey.effects)
        d.set(true, forKey: SoundSettingsKey.musicEnabled)
        service.reloadSettings()
        #expect(output.gains.last.map { $0.overall == 0.8 && $0.effects == 0.25 && $0.music == 0.5 } == true)
        #expect(output.music.last.map { $0.enabled && $0.mood == .calm } == true)
        #expect(output.starts == 1)  // no restart
        #expect(SoundSettings.standard.gains(isAppActive: false).overall == 0)
        var muted = SoundSettings.standard
        muted.muted = true
        #expect(muted.gains(isAppActive: true).overall == 0)
    }

    // MARK: Moods (AUD-038 / AUD-039)

    @Test("AUD-038 every DetailMode has a mood; the session follows encounters and transit")
    func moods() throws {
        let playback = TransitPlayback(destination: 1, viaWormhole: false, fromClick: 20, toClick: 0, end: .arrival)
        #expect(MusicMood.derive(detailMode: .transit(playback)) == .travel)
        #expect(MusicMood.derive(detailMode: .encounter) == .tension)
        #expect(MusicMood.derive(detailMode: .gameOver(.retired)) == .silent)
        for section in Section.allCases { #expect(MusicMood.derive(detailMode: .section(section)) == .calm) }
        let audio = RecordingAudio()
        let s = try AudioFixtures.session(audio: audio)
        s.requestQuickStart()
        #expect(audio.moods.last == .calm)
        try TestSessions.edit(s) { $0.phase = TransitFixtures.encounterPhase(clicks: 5) }
        s.updateMusicMood()
        #expect(audio.moods.last == .tension)
    }

    @Test("AUD-039 music is off by default and follows the setting")
    func musicDefault() throws {
        let output = FakeAudioOutput()
        let d = try AudioFixtures.defaults()
        let service = try AudioFixtures.service(output, defaults: d)
        #expect(output.music.last.map { !$0.enabled } == true)
        service.setMood(.tension)
        #expect(output.music.last.map { !$0.enabled && $0.mood == .tension } == true)
        d.set(true, forKey: SoundSettingsKey.musicEnabled)
        service.reloadSettings()
        #expect(output.music.last.map { $0.enabled && $0.mood == .tension } == true)
    }

    // MARK: Session wiring (AUD-036) and launch options (AUD-044)

    @Test("AUD-036 the session calls the services after steps, on rejections, newspapers, tribbles and achievements")
    func sessionWiring() throws {
        let audio = RecordingAudio()
        let haptics = RecordingSessionHaptics()
        let s = try AudioFixtures.session(audio: audio, haptics: haptics, achievements: OneAchievement())
        s.requestQuickStart()
        TestSessions.resolvePresentation(s)
        s.readNewspaper()
        if case .confirmation = s.presentation { TestSessions.resolvePresentation(s) }
        #expect(audio.apps.contains(.newspaper))  // the newspaper sheet appeared
        s.dismissPresentation()
        let steps = audio.records.count
        s.send(.selectNextTarget(forward: true))
        s.send(.warp)
        #expect(audio.records.count > steps && haptics.records.count == audio.records.count)
        #expect(audio.apps.contains(.achievement))
        TestSessions.resolvePresentation(s)
        s.send(.sellCargo(.narcotics, quantity: 5))
        if s.lastRejection != nil { #expect(audio.apps.last == .rejected) }
        s.tribbleClicked()
        #expect(audio.apps.last == .tribble)
        s.playTestSound()
        #expect(audio.apps.last == .testSound)
        s.performHaptic(.quantitySnap)
        #expect(haptics.apps == [.quantitySnap])
        s.setAppActive(false)
        #expect(audio.activations == [false])
    }

    @Test("AUD-044 -PMAudio off builds SilentAudio and NoHaptics and no output; audio never changes the game")
    func audioOff() throws {
        var off = LaunchOptions()
        off.audioOff = true
        var made = 0
        let services = SessionAudioFactory.make(options: off, defaults: try AudioFixtures.defaults(),
                                                output: { made += 1; return FakeAudioOutput() })
        #expect(services.audio is SilentAudio && services.haptics is NoHaptics && made == 0)
        #expect(services.audio.status == .offForLaunch && SoundSettingsModel.controlsDisabled(status: services.audio.status))
        let on = SessionAudioFactory.make(options: LaunchOptions(), defaults: try AudioFixtures.defaults(),
                                          output: { made += 1; return FakeAudioOutput() },
                                          performer: { HapticRecorder() })
        #expect(on.audio is AudioService && on.haptics is HapticsService && made == 1)
        #expect(on.audio.status == .running)

        // The same command script with audio on (fake output) and off ends in identical states.
        func run(_ audio: any SessionAudio) throws -> GameState? {
            let s = try AudioFixtures.session(audio: audio, seed: 42)
            s.requestQuickStart()
            s.dismissPresentation()
            for _ in 0..<3 {
                s.send(.selectNextTarget(forward: true))
                s.send(.warp)
                var guardSteps = 0
                while case .encounter = s.state?.phase, guardSteps < 30 {
                    TestSessions.resolvePresentation(s)
                    s.send(.encounter(.resolve))
                    TestSessions.resolvePresentation(s)
                    guardSteps += 1
                }
                TestSessions.resolvePresentation(s)
                s.send(.buyFuel(credits: 50))
            }
            return s.state
        }
        let withAudio = try run(try AudioFixtures.service())
        let without = try run(SilentAudio())
        #expect(withAudio != nil && withAudio == without)
    }

    // MARK: Sound tab (AUD-042)

    @Test("AUD-042 Sound tab: identifiers in order, percentage labels, disabled under -PMAudio off")
    func soundTab() {
        #expect(AXID.Sound.all == ["settings.sound.mute", "settings.sound.master", "settings.sound.effects",
                                   "settings.sound.musicEnabled", "settings.sound.music", "settings.sound.muteWhenInactive",
                                   "settings.sound.haptics", "settings.sound.preview", "settings.sound.status"])
        #expect(AXID.all.contains(AXID.Sound.status))
        #expect(AXID.Settings.tab(.sound) == "settings.tab.sound")
        #expect(SoundSettingsModel.percent(0.8) == 0.8.formatted(.percent.precision(.fractionLength(0))))
        #expect(SoundSettingsModel.percent(2) == 1.0.formatted(.percent.precision(.fractionLength(0))))
        #expect(SoundSettingsModel.controlsDisabled(status: .offForLaunch))
        #expect(!SoundSettingsModel.controlsDisabled(status: .running) && !SoundSettingsModel.controlsDisabled(status: .idle))
        #expect(SettingsTab.sound.arrivesIn == nil)
        #expect(AudioCueMap.cue(for: .testSound).cue == .coinIn)
    }
}
