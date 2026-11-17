// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecArt
import ParsecEngine
import SwiftUI

/// ART-051: a still ship portrait (inspector, shipyard cards, designer preview) with the environment's accessibility flags.
struct ShipPortrait: View {
    let input: ShipArtInput
    var mode: ShipScaleMode = .fit

    var body: some View {
        ArtAccessibilityReader { a11y in
            ShipArt(Self.with(input, a11y), scaleMode: mode)
        }
        .accessibilityHidden(true)
    }

    static func with(_ input: ShipArtInput, _ a11y: ArtAccessibility) -> ShipArtInput {
        var i = input
        i.accessibility = a11y
        return i
    }
}

/// ART-026, ART-052: the Bridge planet portrait; it turns slowly through one `TimelineView`, paused when the window is
/// inactive and replaced by a still frame under Reduce Motion.
struct PlanetPortrait: View {
    let input: PlanetArtInput
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        ArtAccessibilityReader { a11y in
            if a11y.reduceMotion {
                PlanetArt(Self.with(input, a11y, phase: 0))
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !appearsActive)) { timeline in
                    PlanetArt(Self.with(input, a11y, phase: timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 600)))
                }
            }
        }
    }

    static func with(_ input: PlanetArtInput, _ a11y: ArtAccessibility, phase: Double) -> PlanetArtInput {
        var i = input
        i.accessibility = a11y
        i.phase = phase
        return i
    }
}

/// ART-034: a crew member's avatar (special passengers have a fixed one).
struct CrewAvatarView: View {
    let crewID: Int
    @Environment(GameSession.self) private var session

    var body: some View {
        CrewAvatar(seed: ArtSeed.crew(galaxySeed: session.state?.seed ?? 0, crewID: crewID), role: ArtAdapters.avatarRole(crewID: crewID))
            .frame(width: 34, height: 34)
            .accessibilityHidden(true)
    }
}

/// ART-032: the outfitter's item icon.
struct EquipmentIcon: View {
    let item: EquipmentItem

    static func kind(_ item: EquipmentItem) -> EquipmentGlyphKind {
        switch item {
        case let .weapon(w): ArtAdapters.weapon(w)
        case let .shield(s): ArtAdapters.shieldGlyph(s)
        case let .gadget(g): ArtAdapters.gadget(g)
        }
    }

    var body: some View {
        EquipmentGlyph(kind: Self.kind(item))
            .foregroundStyle(.tint)
            .accessibilityHidden(true)
    }
}

/// ART-041, ART-052: the ending cinematic; it animates for at most 4 s after it appears, then holds (the final frame
/// under Reduce Motion).
struct GameOverArt: View {
    let end: GameEndType
    let ship: ShipType
    @State private var appeared: Date?
    @State private var finished = false

    var body: some View {
        ArtAccessibilityReader { a11y in
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: finished || a11y.reduceMotion)) { timeline in
                GameOverScene(end: ArtAdapters.gameEnd(end), phase: appeared.map { timeline.date.timeIntervalSince($0) } ?? 0,
                              ship: ArtAdapters.shipKind(ship), accessibility: a11y)
            }
        }
        .onAppear { appeared = .now }
        .task {
            try? await Task.sleep(for: .seconds(GameOverScene.duration + 0.1))
            finished = true
        }
    }
}
