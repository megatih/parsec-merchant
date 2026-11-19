// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecArt
import ParsecEngine
import SwiftUI

/// PRD-1.1 D7: the sizes of the ship panels, in points.
nonisolated enum ShipPanelSize {
    static let cardBanner: CGFloat = 96
    static let inspectorHero: CGFloat = 104
    static let purchaseHero: CGFloat = 120
    static let compare = CGSize(width: 96, height: 56)
    static let vignette = CGSize(width: 160, height: 120)
    static let encounterPane: ClosedRange<CGFloat> = 160...240
    /// The panes give height back when the window is small or the Text Size large, so the action bar stays on screen.
    static let encounterPaneFloor: CGFloat = 96
    static let transit: ClosedRange<CGFloat> = 150...180
    /// The ending scene is a cinematic 16:9 card as wide as the game-over card.
    static let endingAspect: CGFloat = 16.0 / 9
}

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

/// ART-FACE: a crew member's portrait (special characters have an authored one).
struct CrewAvatarView: View {
    let crewID: Int
    var side: CGFloat = 34
    @Environment(GameSession.self) private var session

    var body: some View {
        if let state = session.state {
            CharacterPortrait(genome: ArtAdapters.portraitGenome(crewID: crewID, state: state))
                .frame(width: side, height: side)
                // ART-FACE-010: a labelled picture; it takes no keyboard focus.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Portrait of \(Names.crew(crewID, in: state))"))
                .accessibilityAddTraits(.isImage)
        }
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
    /// ART-END-003: the player's own ship at the end of the game (statistics, equipment and livery).
    var shipInput: ShipArtInput?
    @State private var appeared: Date?
    @State private var finished = false

    var body: some View {
        ArtAccessibilityReader { a11y in
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: finished || a11y.reduceMotion)) { timeline in
                GameOverScene(end: ArtAdapters.gameEnd(end), phase: appeared.map { timeline.date.timeIntervalSince($0) } ?? 0,
                              ship: ArtAdapters.shipKind(ship), accessibility: a11y, shipInput: shipInput)
            }
        }
        .onAppear { appeared = .now }
        .task {
            try? await Task.sleep(for: .seconds(GameOverScene.duration + 0.1))
            finished = true
        }
    }
}
