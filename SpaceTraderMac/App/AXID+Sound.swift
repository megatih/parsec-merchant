// SPDX-License-Identifier: GPL-2.0-or-later

/// Settings › Sound identifiers (AUD-042).
nonisolated extension AXID {
    enum Sound {
        static let mute = "settings.sound.mute"
        static let overall = "settings.sound.master"
        static let effects = "settings.sound.effects"
        static let musicEnabled = "settings.sound.musicEnabled"
        static let music = "settings.sound.music"
        static let muteWhenInactive = "settings.sound.muteWhenInactive"
        static let haptics = "settings.sound.haptics"
        static let preview = "settings.sound.preview"
        static let status = "settings.sound.status"
        static let all = [mute, overall, effects, musicEnabled, music, muteWhenInactive, haptics, preview, status]
    }
}
