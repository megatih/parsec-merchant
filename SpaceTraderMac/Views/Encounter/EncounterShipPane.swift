// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecArt
import ParsecEngine
import SwiftUI

/// UI-ENC-018…020, UI-ENC-098: one ship pane: title, the ParsecArt portrait, hull and shield bars and the accessibility label.
struct ShipPaneView: View {
    struct Identifiers {
        var pane: String
        var hull: String
        var shields: String

        static let player = Identifiers(pane: AXID.Encounter.player, hull: AXID.Encounter.playerHull, shields: AXID.Encounter.playerShields)
        static let opponent = Identifiers(pane: AXID.Encounter.opponent, hull: AXID.Encounter.opponentHull,
                                          shields: AXID.Encounter.opponentShields)
    }

    let model: ShipPaneModel
    let identifiers: Identifiers
    /// Seconds of ambient animation (engine glow); 0 under Reduce Motion.
    var phase: Double = 0
    /// ART-046: the ship's offset in pane widths (escape, arrive) and whether it is still drawn (explosion).
    var offset: Double = 0
    var visible = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(verbatim: model.title).font(.headline)
                if model.isDisabled {
                    Label("Disabled", systemImage: "bolt.slash.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier(AXID.Encounter.opponentDisabled)
                }
            }
            ArtAccessibilityReader { a11y in
                GeometryReader { geo in
                    ShipArt(Self.input(model.art, phase: phase, accessibility: a11y), scaleMode: .relative)
                        .opacity(visible ? 1 : 0)
                        .offset(x: offset * geo.size.width)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 90, maxHeight: 120)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: model.accessibilityLabel))
            EncounterBar(model: model.hull)
                .accessibilityIdentifier(identifiers.hull)
            EncounterBar(model: model.shields)
                .accessibilityIdentifier(identifiers.shields)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifiers.pane)
    }

    static func input(_ art: ShipArtInput, phase: Double, accessibility: ArtAccessibility) -> ShipArtInput {
        var input = art
        input.phase = accessibility.ambientPhase(phase)
        input.accessibility = accessibility
        return input
    }
}

/// UI-ENC-019: a labelled bar ("Hull 78%", "Shields 40%", "No shields"); a critical hull adds a warning symbol.
struct EncounterBar: View {
    let model: EncounterBarModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if model.isCritical {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
                Text(verbatim: model.text).font(.caption).monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.2))
                    Capsule().fill(tint).frame(width: geo.size.width * model.fraction)
                }
            }
            .frame(height: 6)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: model.fraction)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: model.text))
        .accessibilityValue(Text(verbatim: model.value))
    }

    private var tint: Color {
        switch model.kind {
        case .hull: model.isCritical ? .red : .green
        case .shields: .blue
        }
    }
}
