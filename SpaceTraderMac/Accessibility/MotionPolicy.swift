// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// Every animated site of the app (A11Y-016). New animations add a case here, never a literal `Animation`.
nonisolated enum MotionSite: String, CaseIterable, Sendable {
    /// The ≈1.2 s transit ship track (UI-ENC-007): skipped under Reduce Motion.
    case transitPlayback
    /// Beams, ripples, sparks and screen shake (ART-047, UI-ENC-098): a short colour flash under Reduce Motion.
    case combatEffects
    /// Map viewport changes from buttons, keys, search and Show on Map (MAP-017).
    case mapViewport
    /// The Show on Map pulse ring (MAP-078): a static ring under Reduce Motion.
    case showOnMapPulse
    /// Credit and worth tickers.
    case numberTicker
    /// Arrival card expand, feed overlay and inline tips (UI-ENC-055).
    case cardTransition
    /// Section switch and inspector toggle: system transitions only.
    case sectionSwitch
    /// Welcome drift, planet rotation, wormhole vortex and engine flicker (ART-026, ART-030, ART-038).
    case ambientArt
    /// The tribble wiggle (UI-ENC-100); its visual twin stays.
    case tribbleWiggle
    /// The achievement unlock badge (ACH).
    case achievementUnlock
    /// Hull and shield bar changes.
    case gaugeChange
}

/// What an animated site does, as data so tests can check durations (SwiftUI's `Animation` is opaque).
nonisolated enum MotionSpec: Equatable, Sendable {
    /// No animation: the value is replaced.
    case none
    /// An opacity-only change (crossfade or colour flash) of `duration` seconds.
    case opacity(duration: Double)
    /// A spring that settles within `settle` seconds.
    case spring(settle: Double)
    /// A continuous, timeline-driven motion (ambient art, playback, wiggle).
    case continuous

    /// The longest time the change takes to settle (continuous motion never settles).
    var settleTime: Double? {
        switch self {
        case .none: 0
        case let .opacity(d): d
        case let .spring(s): s
        case .continuous: nil
        }
    }

    var animation: Animation? {
        switch self {
        case .none, .continuous: nil
        case let .opacity(d): .easeInOut(duration: d)
        case let .spring(s): .spring(duration: s, bounce: 0)
        }
    }
}

/// The only source of UI animations (A11Y-016, UX-VISION §7): views use
/// `.animation(MotionPolicy.animation(for:prefs:), value:)` or `withAnimation(MotionPolicy.animation(for:prefs:))`.
nonisolated enum MotionPolicy {
    static let maximumSpring = 0.35
    static let maximumReducedOpacity = 0.2

    static func spec(for site: MotionSite, prefs: AccessibilityPreferences) -> MotionSpec {
        let reduce = prefs.reduceMotion
        switch site {
        case .transitPlayback, .ambientArt, .tribbleWiggle:
            return reduce ? .none : .continuous
        case .combatEffects:
            return reduce ? .opacity(duration: 0.2) : .continuous
        case .mapViewport:
            return reduce ? .none : .spring(settle: 0.35)
        case .showOnMapPulse:
            return reduce ? .none : .continuous
        case .numberTicker:
            return reduce ? .none : .spring(settle: 0.3)
        case .cardTransition, .achievementUnlock:
            return reduce ? .opacity(duration: 0.2) : .spring(settle: 0.3)
        case .sectionSwitch:
            return .none
        case .gaugeChange:
            return reduce ? .none : .spring(settle: 0.35)
        }
    }

    static func animation(for site: MotionSite, prefs: AccessibilityPreferences) -> Animation? {
        spec(for: site, prefs: prefs).animation
    }

    /// Whether a continuous (timeline) motion runs at this site.
    static func runsContinuously(_ site: MotionSite, prefs: AccessibilityPreferences) -> Bool {
        spec(for: site, prefs: prefs) == .continuous
    }
}
