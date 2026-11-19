// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecArt
import ParsecEngine
import SwiftUI

/// The Transit view (UI-ENC-008, -012, -013): "En route to …", the drawn transit scene (ART-039: the player's ship over a
/// starfield with speed streaks), a 20-segment progress track, and Skip.
struct TransitView: View {
    @Environment(GameSession.self) private var session
    let playback: TransitPlayback
    @Environment(\.pmScale) private var scale

    var body: some View {
        let tick = session.transitPlayback == playback ? session.transitTick : 0
        let flown = playback.clicksFlown(atTick: tick)
        VStack(spacing: PMSpace.l * scale) {
            if let rip = playback.fabricRip, let state = session.state {
                Label {
                    Text("A fracture in the space-time fabric pulls you to \(Names.system(rip, in: state))!")
                } icon: {
                    Image(systemName: "tornado")
                }
                .pmFont(.valueLarge)
                .foregroundStyle(PMColor.caution)
                .padding(PMSpace.m * scale)
                .background(PMColor.panelRaised, in: RoundedRectangle(cornerRadius: PMRadius.panel * scale))
                .overlay { RoundedRectangle(cornerRadius: PMRadius.panel * scale).strokeBorder(PMColor.caution) }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(AXID.Transit.fabricRip)
            }
            if let state = session.state {
                Text(TransitText.title(playback, state: state))
                    .pmFont(.title)
                    .foregroundStyle(PMColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                TransitArt(ship: ArtAdapters.playerShipInput(state),
                           progress: Double(flown) / Double(TransitPlayback.totalClicks), wormhole: playback.viaWormhole, seed: state.seed)
                    // PRD §4.12: the scene takes the game area.
                    .frame(maxWidth: .infinity, minHeight: ShipPanelSize.transit.lowerBound, maxHeight: .infinity)
            }
            TransitTrack(flown: flown)
                .frame(maxWidth: 640 * scale)
                // A11Y-004: a progress element "Click N of 20".
                .accessibilityRepresentation {
                    ProgressView(value: Double(flown), total: Double(TransitPlayback.totalClicks)) { Text("Transit progress") }
                        .accessibilityValue(Text(verbatim: AccessibilityText.transitClick(flown, of: TransitPlayback.totalClicks)))
                }
                .accessibilityIdentifier(AXID.Transit.progress)
            if playback.isFrozen {
                Text("Transit interrupted")
                    .pmFont(.body)
                    .foregroundStyle(PMColor.textSecondary)
            } else {
                PMButton(title: "Skip", kind: .primary, key: "↩", help: "Skip the rest of the trip animation", identifier: AXID.Transit.skip) {
                    session.skipPlayback()
                }
                .fixedSize()
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(PMSpace.xl * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    RoundedRectangle(cornerRadius: PMRadius.control)
                        .fill(i < flown ? PMColor.accent : PMColor.panelRaised)
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
        .clipShape(RoundedRectangle(cornerRadius: PMRadius.panel))
        .accessibilityHidden(true)
    }

    static func input(_ ship: ShipArtInput, _ a11y: ArtAccessibility) -> ShipArtInput {
        var s = ship
        s.accessibility = a11y
        return s
    }
}
