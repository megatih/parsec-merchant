// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// AUD-043: the Sound settings' `UserDefaults` keys (app-wide; never in a save, never read by the engine, OPT-028).
nonisolated enum SoundSettingsKey {
    static let overall = "settings.sound.master"
    static let effects = "settings.sound.effects"
    static let music = "settings.sound.music"
    static let muted = "settings.sound.muted"
    static let musicEnabled = "settings.sound.musicEnabled"
    static let muteWhenInactive = "settings.sound.muteWhenInactive"
    static let hapticsEnabled = "settings.haptics.enabled"
}

/// AUD-043: the Sound settings with their defaults, read from `UserDefaults` with values clamped to 0…1. Because they
/// are defaults keys, a launch argument such as `-settings.sound.master 0` overrides them for one launch.
nonisolated struct SoundSettings: Equatable, Sendable {
    var overall = 0.8
    var effects = 1.0
    var music = 0.5
    var muted = false
    var musicEnabled = false
    var muteWhenInactive = true
    var hapticsEnabled = true

    static let standard = SoundSettings()

    init() {}

    init(defaults: UserDefaults) {
        let d = Self.standard
        overall = Self.level(defaults, SoundSettingsKey.overall, d.overall)
        effects = Self.level(defaults, SoundSettingsKey.effects, d.effects)
        music = Self.level(defaults, SoundSettingsKey.music, d.music)
        muted = Self.flag(defaults, SoundSettingsKey.muted, d.muted)
        musicEnabled = Self.flag(defaults, SoundSettingsKey.musicEnabled, d.musicEnabled)
        muteWhenInactive = Self.flag(defaults, SoundSettingsKey.muteWhenInactive, d.muteWhenInactive)
        hapticsEnabled = Self.flag(defaults, SoundSettingsKey.hapticsEnabled, d.hapticsEnabled)
    }

    /// A volume in 0…1 (argument-domain strings such as "0" convert like numbers).
    private static func level(_ defaults: UserDefaults, _ key: String, _ fallback: Double) -> Double {
        guard defaults.object(forKey: key) != nil else { return fallback }
        let v = defaults.double(forKey: key)
        return v.isFinite ? min(max(v, 0), 1) : fallback
    }

    private static func flag(_ defaults: UserDefaults, _ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) != nil ? defaults.bool(forKey: key) : fallback
    }

    /// The slider values the synth receives (AUD-006): Mute, or an inactive app with "Mute when inactive", ramp the
    /// overall to zero.
    func gains(isAppActive: Bool) -> (overall: Float, effects: Float, music: Float) {
        let silenced = muted || (!isAppActive && muteWhenInactive)
        return (silenced ? 0 : Float(overall), Float(effects), Float(music))
    }
}
