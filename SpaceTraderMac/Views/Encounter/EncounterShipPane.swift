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
                Text(verbatim: model.title).scaledFont(.headline)
                if model.isDisabled {
                    Label("Disabled", systemImage: "bolt.slash.fill")
                        .scaledFont(.caption, weight: .bold)
                        .foregroundStyle(.signalOrange)
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
            .accessibilityAddTraits(.isImage)
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
    @Environment(\.accessibilityPreferences) private var a11yPrefs
    private var reduceMotion: Bool { a11yPrefs.reduceMotion }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if model.isCritical {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.signalRed)
                }
                Text(verbatim: model.text).scaledFont(.caption).monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.2))
                    Capsule().fill(tint).frame(width: geo.size.width * model.fraction)
                    // A11Y-021: stripes on a critical hull under Differentiate Without Color.
                    if model.isCritical, ColorSignal.hullCritical.extra(prefs: a11yPrefs) != nil {
                        BarStripes().clipShape(Capsule()).frame(width: geo.size.width * model.fraction)
                    }
                }
                // A11Y-018: the bar outline (2 pt under Increase Contrast).
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.45),
                                                lineWidth: ContrastStyle.make(prefs: a11yPrefs).barOutlineWidth))
            }
            .frame(height: 6)
            .animation(MotionPolicy.animation(for: .gaugeChange, prefs: a11yPrefs), value: model.fraction)
        }
        // A11Y-004: a progress element "Hull 78%" with the value "78 percent" ("No shields" without shields).
        .accessibilityRepresentation {
            ProgressView(value: model.fraction) { Text(verbatim: model.text) }
                .accessibilityValue(Text(verbatim: model.percent.map(AccessibilityText.percent) ?? AccessibilityText.noShields))
        }
    }

    private var tint: Color {
        switch model.kind {
        case .hull: model.isCritical ? .red : .green
        case .shields: .blue
        }
    }
}

/// Diagonal stripes for a bar's pattern twin (A11Y-021).
struct BarStripes: View {
    var body: some View {
        Canvas { context, size in
            var x: CGFloat = -size.height
            while x < size.width {
                var p = Path()
                p.move(to: CGPoint(x: x, y: size.height))
                p.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(p, with: .color(.black.opacity(0.45)), lineWidth: 1.5)
                x += 5
            }
        }
        .accessibilityHidden(true)
    }
}
