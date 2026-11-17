// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// The Transit view (UI-ENC-008, -012, -013): "En route to …", a 20-segment progress track with a moving ship
/// placeholder, and Skip. The animated silhouette and starfield are M11.
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

/// Twenty segments; the ship placeholder sits at the current click.
private struct TransitTrack: View {
    let flown: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let step = geo.size.width / CGFloat(TransitPlayback.totalClicks)
                Image(systemName: "airplane")
                    .font(.title3)
                    .offset(x: min(geo.size.width - step, CGFloat(flown) * step))
            }
            .frame(height: 24)
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
