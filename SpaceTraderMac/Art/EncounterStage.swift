// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecArt
import ParsecEngine
import SwiftUI

/// ART-047/048: the motion of the encounter panes at a time `t` into the current plan. Under Reduce Motion the plan is
/// replaced by flashes, so nothing moves, scales or shakes.
nonisolated struct EncounterMotion: Equatable, Sendable {
    var effects: [CombatEffect]
    var shake: CGSize
    var playerOffset: Double
    var opponentOffset: Double
    var playerVisible: Bool
    var opponentVisible: Bool

    static func make(plan: [CombatEffect], reduceMotion: Bool, at t: Double) -> EncounterMotion {
        let effects = reduceMotion ? CombatEffect.reducedMotion(plan) : plan
        return EncounterMotion(effects: effects, shake: CombatMotion.shake(effects, at: t),
                               playerOffset: CombatMotion.shipOffset(effects, side: .player, at: t),
                               opponentOffset: CombatMotion.shipOffset(effects, side: .opponent, at: t),
                               playerVisible: CombatMotion.shipVisible(effects, side: .player, at: t),
                               opponentVisible: CombatMotion.shipVisible(effects, side: .opponent, at: t))
    }

    /// ART-083: the effect boxes are the ships' own bounding boxes: `ShipArtLayout.frame` inside each pane's portrait
    /// rectangle (in the stage's coordinates). Nothing here is a constant, so the effects follow any pane size.
    @MainActor
    static func geometry(playerArt: CGRect, opponentArt: CGRect, player: ShipArtInput, opponent: ShipArtInput) -> CombatGeometry {
        func box(_ input: ShipArtInput, in art: CGRect) -> CGRect {
            ShipArtLayout.frame(input, mode: .relative, in: art.size).offsetBy(dx: art.minX, dy: art.minY)
        }
        return CombatGeometry(player: box(player, in: playerArt), opponent: box(opponent, in: opponentArt))
    }

    /// The portrait rectangles of two panes laid out side by side in a stage of `size` (the stage's own layout: 24 pt between
    /// the panes, 12 pt of padding, the title above and the two bars below). Used before the first layout pass and by tests.
    static func portraitRects(stage size: CGSize) -> (player: CGRect, opponent: CGRect) {
        let pane = (size.width - 24) / 2
        let height = min(ShipPanelSize.encounterPane.upperBound, max(ShipPanelSize.encounterPane.lowerBound, size.height - 100))
        let rect = CGRect(x: 12, y: 40, width: max(1, pane - 24), height: height)
        return (rect, rect.offsetBy(dx: pane + 24, dy: 0))
    }
}

/// UI-ENC-098, ART-052: the two ship panes with ambient animation (one `TimelineView` for the whole surface, paused when
/// the window is inactive and static under Reduce Motion once the plan's flashes are over) and the combat effects layer.
struct EncounterStage: View {
    let player: ShipPaneModel
    let opponent: ShipPaneModel
    let plan: [CombatEffect]
    let planStart: Date?
    @Environment(\.accessibilityPreferences) private var a11yPrefs
    private var reduceMotion: Bool { a11yPrefs.reduceMotion }
    @Environment(\.appearsActive) private var appearsActive
    @State private var settledStart: Date?

    private var planRunning: Bool { planStart != nil && settledStart != planStart }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !appearsActive || (reduceMotion && !planRunning))) { timeline in
            let ambient = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 600)
            let t = planStart.map { timeline.date.timeIntervalSince($0) } ?? 1_000
            let motion = EncounterMotion.make(plan: plan, reduceMotion: reduceMotion, at: t)
            HStack(alignment: .top, spacing: 24) {
                ShipPaneView(model: player, identifiers: .player, phase: reduceMotion ? 0 : ambient, offset: motion.playerOffset,
                             visible: motion.playerVisible)
                ShipPaneView(model: opponent, identifiers: .opponent, phase: reduceMotion ? 0 : ambient + 0.13,
                             offset: motion.opponentOffset, visible: motion.opponentVisible)
            }
            .offset(motion.shake)
            .overlay {
                Color.clear
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .overlayPreferenceValue(ShipPaneArtKey.self) { anchors in
                GeometryReader { geo in
                    let fallback = EncounterMotion.portraitRects(stage: geo.size)
                    let playerArt = anchors[AXID.Encounter.player].map { geo[$0] } ?? fallback.player
                    let opponentArt = anchors[AXID.Encounter.opponent].map { geo[$0] } ?? fallback.opponent
                    CombatEffectsLayer(effects: motion.effects, phase: t,
                                       geometry: EncounterMotion.geometry(playerArt: playerArt, opponentArt: opponentArt,
                                                                          player: player.art, opponent: opponent.art))
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .task(id: planStart) {
            guard let start = planStart else { return }
            let end = CombatEffect.end(of: plan) + CombatTiming.symbolHold + 0.1
            try? await Task.sleep(for: .seconds(max(0, end - Date().timeIntervalSince(start))))
            settledStart = start
        }
    }
}
