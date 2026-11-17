// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecArt
import ParsecEngine
import SwiftUI

/// The Transit view (UI-ENC-008, -012, -013): "En route to …", the drawn transit scene (ART-039: the player's ship over a
/// starfield with speed streaks), a 20-segment progress track, and Skip.
struct TransitView: View {
    @Environment(GameSession.self) private var session
    let playback: TransitPlayback

    var body: some View {
        let tick = session.transitPlayback == playback ? session.transitTick : 0
        let flown = playback.clicksFlown(atTick: tick)
        VStack(spacing: 24) {
            if let rip = playback.fabricRip, let state = session.state {
                Label {
                    Text("A fracture in the space-time fabric pulls you to \(Names.system(rip, in: state))!")
                } icon: {
                    Image(systemName: "tornado")
                }
                .font(.headline)
                .padding(12)
                .background(.orange.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(AXID.Transit.fabricRip)
            }
            if let state = session.state {
                Text(TransitText.title(playback, state: state))
                    .font(.title2)
                TransitArt(ship: ArtAdapters.shipInput(state.commander.ship, ruleset: state.ruleset, facing: .right),
                           progress: Double(flown) / Double(TransitPlayback.totalClicks), wormhole: playback.viaWormhole, seed: state.seed)
                    .frame(maxWidth: 520, minHeight: 110, maxHeight: 130)
            }
            TransitTrack(flown: flown)
                .frame(maxWidth: 520)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Transit progress"))
                .accessibilityValue(Text("Click \(flown) of \(TransitPlayback.totalClicks)"))
                .accessibilityIdentifier(AXID.Transit.progress)
            if playback.isFrozen {
                Text("Transit interrupted")
                    .foregroundStyle(.secondary)
            } else {
                Button("Skip") { session.skipPlayback() }
                    .keyboardShortcut(.defaultAction)
                    .help(Text("Skip the rest of the trip animation."))
                    .accessibilityIdentifier(AXID.Transit.skip)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand { session.skipPlayback() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Transit.view)
    }
}

/// Twenty segments.
private struct TransitTrack: View {
    let flown: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                ForEach(0..<TransitPlayback.totalClicks, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i < flown ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(height: 10)
                }
            }
        }
    }
}

/// Transit view texts (UI-ENC-008).
enum TransitText {
    static func title(_ playback: TransitPlayback, state: GameState) -> LocalizedStringResource {
        let name = Names.system(playback.destination, in: state)
        return playback.viaWormhole ? "En route to \(name) via wormhole" : "En route to \(name)"
    }
}

/// ART-039, ART-052: the transit scene with one `TimelineView`, paused when the window is inactive; Reduce Motion shows the
/// final frame (UI-ENC-008).
private struct TransitArt: View {
    let ship: ShipArtInput
    let progress: Double
    let wormhole: Bool
    let seed: UInt64
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        ArtAccessibilityReader { a11y in
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !appearsActive || a11y.reduceMotion)) { timeline in
                TransitScene(input: Self.input(ship, a11y), progress: progress,
                             phase: timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 600), wormhole: wormhole,
                             seed: seed)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityHidden(true)
    }

    static func input(_ ship: ShipArtInput, _ a11y: ArtAccessibility) -> ShipArtInput {
        var s = ship
        s.accessibility = a11y
        return s
    }
}
