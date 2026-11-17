// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecAudio

/// AUD-036: cues the app raises itself (not from a step).
nonisolated enum AppCue: String, CaseIterable, Sendable {
    case newspaper, achievement, tribble, testSound, rejected
}

/// AUD-033: the transit playback's progress, as the session reports it.
nonisolated enum TransitAudioEvent: Equatable, Sendable {
    case started
    /// The playback advanced; `clicksFlown` is "click N of 20".
    case tick(clicksFlown: Int)
    /// The playback ended or was skipped: held cues play now.
    case ended
    /// The step state was reset (load, new game, close): held cues are dropped.
    case cancelled
}

/// AUD-011: what the audio output is doing.
nonisolated enum AudioStatus: Equatable, Sendable {
    /// `-PMAudio off`.
    case offForLaunch
    /// Not started yet, or paused (Mute, inactive app).
    case idle
    case running
    case noOutputDevice
    case failed(code: Int)

    /// The Settings › Sound status line (AUD-042).
    var title: LocalizedStringResource {
        switch self {
        case .running: "Running"
        case .offForLaunch: "Off for this launch"
        case .idle: "Paused"
        case .noOutputDevice: "No audio output device"
        case .failed: "Audio couldn't start"
        }
    }
}

/// AUD-040: haptics the app raises from controls.
nonisolated enum AppHaptic: String, CaseIterable, Sendable {
    /// A market quantity reached the most the player can afford, carry or buy (UI-SHELL-067).
    case quantitySnap
    /// A dock slider reached full.
    case sliderFull
}

/// AUD-040: the `NSHapticFeedbackManager` patterns the game uses.
nonisolated enum HapticPattern: String, CaseIterable, Sendable {
    case alignment, generic, levelChange
}

/// AUD-035: the visual surface that shows what a cue says, with or without sound.
nonisolated enum VisualTwin: String, CaseIterable, Sendable {
    case transitProgress, controlState, statusText, cashTicker, cargoCount, dockGauge, slotTile, transitView
    case arrivalReport, encounterBadge, beamEffect, shieldRipple, hullSparks, explosionEffect, disabledTag
    case escapeEffect, hullBarCritical, reportSheet, feedItem, narrativeSheet, gameOverCard, newspaperSheet
    case achievementToast, tribbleWiggle
}

extension MusicMood {
    /// AUD-038: Welcome and docked are calm, transit travels, encounters are tense, game over is silent.
    static func derive(detailMode: DetailMode) -> MusicMood {
        switch detailMode {
        case .transit: .travel
        case .encounter: .tension
        case .gameOver: .silent
        case .section: .calm
        }
    }
}
