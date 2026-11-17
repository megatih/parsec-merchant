// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// UI-ENC-018…020: one ship pane: title, placeholder portrait, hull and shield bars and the accessibility label.
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
            ShipPlaceholder(type: model.shipType, size: model.size, facing: model.facing)
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
}

/// UI-ENC-018: the placeholder portrait (ParsecArt replaces it in M11, UI-ENC-101): an SF Symbol sized by the ship's
/// size class, facing right for the player and left for the opponent.
struct ShipPlaceholder: View {
    let type: ShipType
    let size: SystemSize
    let facing: ShipPaneModel.Facing

    /// 0.5…1.0 of the available height, by size class.
    static func scale(_ size: SystemSize) -> CGFloat {
        0.5 + CGFloat(size.rawValue) * 0.1
    }

    var body: some View {
        GeometryReader { geo in
            Image(systemName: type == .spaceMonster ? "tortoise.fill" : "airplane")
                .resizable()
                .scaledToFit()
                .frame(height: geo.size.height * Self.scale(size))
                .scaleEffect(x: facing == .right ? 1 : -1, y: 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(.secondary)
        }
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
