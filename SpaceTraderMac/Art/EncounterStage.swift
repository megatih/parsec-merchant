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

    /// The effect boxes over two panes of `size` (the portrait sits under the pane title).
    static func geometry(_ size: CGSize) -> CombatGeometry {
        let half = (size.width - 24) / 2
        let top = 40.0, height = min(110, max(40, size.height - 90))
        return CombatGeometry(player: CGRect(x: 12 + half * 0.2, y: top + height * 0.15, width: half * 0.6, height: height * 0.7),
                              opponent: CGRect(x: half + 36 + half * 0.2, y: top + height * 0.15, width: half * 0.6, height: height * 0.7))
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
                GeometryReader { geo in
                    CombatEffectsLayer(effects: motion.effects, phase: t, geometry: EncounterMotion.geometry(geo.size))
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
