// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import SwiftUI

// MARK: Readable secondary text (A11Y-029 contrast)

/// Secondary text that keeps a 4.5:1 contrast on window, grouped-form and glass backgrounds in both appearances (the system
/// `.secondary` measures about 4:1 on white, which the contrast audit reports). On a selected row (increased background
/// prominence) it turns light, like the system's own secondary text.
struct ReadableSecondaryStyle: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> Color {
        if environment.backgroundProminence == .increased { return Color.white.opacity(0.88) }
        return environment.colorScheme == .dark ? Color.white.opacity(0.74) : Color.black.opacity(0.7)
    }
}

extension ShapeStyle where Self == ReadableSecondaryStyle {
    static var readableSecondary: ReadableSecondaryStyle { ReadableSecondaryStyle() }
}

extension ShapeStyle where Self == Color {
    /// Signal colours for text: darker in the light appearance, lighter in the dark one, each at least 4.5:1
    /// (system green, orange and yellow text measure 2–3:1 on white). Never the only signal (A11Y-021).
    static var signalGreen: Color { dynamic("signalGreen", light: (0.05, 0.45, 0.16), dark: (0.39, 0.86, 0.47)) }
    static var signalRed: Color { dynamic("signalRed", light: (0.75, 0.10, 0.12), dark: (1.0, 0.47, 0.45)) }
    static var signalOrange: Color { dynamic("signalOrange", light: (0.62, 0.30, 0.0), dark: (1.0, 0.70, 0.30)) }

    private static func dynamic(_ name: String, light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: NSColor.Name(name)) { appearance in
            let c = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}

/// `LabeledContent` with its value in the primary colour (grouped forms draw values in `.secondary`, A11Y-018/029).
struct ReadableLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline) {
            configuration.label
            Spacer(minLength: 8)
            configuration.content
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: Increase Contrast (A11Y-018)

/// The stroke widths, colours and borders that change under Increase Contrast (pure; A11Y-018).
nonisolated struct ContrastStyle: Equatable, Sendable {
    /// Map stroke multiplier (MAP-087, ART-003).
    var mapStrokeScale: Double
    /// Hull and shield bar outline (UI-ENC-102).
    var barOutlineWidth: Double
    /// Sparkline and chart lines.
    var chartLineWidth: Double
    /// Profit, loss and danger colours come from their high-contrast variants.
    var highContrastSignals: Bool
    /// A separator-colour border on cards and the hover card (0: none).
    var cardBorderWidth: Double
    /// Key numbers (credits, prices, percentages) use the primary label colour instead of secondary.
    var keyNumbersPrimary: Bool

    static func make(prefs: AccessibilityPreferences) -> ContrastStyle {
        prefs.increaseContrast
            ? ContrastStyle(mapStrokeScale: 2, barOutlineWidth: 2, chartLineWidth: 2.5, highContrastSignals: true,
                            cardBorderWidth: 1, keyNumbersPrimary: true)
            : ContrastStyle(mapStrokeScale: 1, barOutlineWidth: 1, chartLineWidth: 1.5, highContrastSignals: false,
                            cardBorderWidth: 0, keyNumbersPrimary: false)
    }

    var profit: Color { highContrastSignals ? Color(nsColor: .systemGreen).mix(with: .black, by: 0.35) : .green }
    var loss: Color { highContrastSignals ? Color(nsColor: .systemRed).mix(with: .black, by: 0.25) : .red }
    var danger: Color { highContrastSignals ? Color(nsColor: .systemOrange).mix(with: .black, by: 0.3) : .orange }
    /// The style of a key number that is secondary in the standard look.
    var keyNumber: HierarchicalShapeStyle { keyNumbersPrimary ? .primary : .secondary }
}

extension View {
    /// A11Y-018: the 1 pt separator border cards get under Increase Contrast.
    func contrastCardBorder(_ style: ContrastStyle, cornerRadius: CGFloat = 10) -> some View {
        overlay {
            if style.cardBorderWidth > 0 {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: style.cardBorderWidth)
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: Reduce Transparency (A11Y-019)

/// The background of app-drawn translucency behind text: hover card, feed overlay, tactical readout, map legend.
nonisolated enum OverlayBackground: Equatable, Sendable {
    /// A system material (it adapts on its own).
    case material
    /// The opaque window background colour (Reduce Transparency).
    case opaque

    static func make(prefs: AccessibilityPreferences) -> OverlayBackground {
        prefs.reduceTransparency ? .opaque : .material
    }
}

/// Applies `OverlayBackground` in a rounded shape.
struct OverlayBackgroundModifier: ViewModifier {
    @Environment(\.accessibilityPreferences) private var prefs
    var cornerRadius: CGFloat = 10

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        let style = ContrastStyle.make(prefs: prefs)
        switch OverlayBackground.make(prefs: prefs) {
        case .material:
            // A material tinted with the window colour, so text keeps 4.5:1 over the dark map (A11Y-029).
            content.background(Color(nsColor: .windowBackgroundColor).opacity(0.95), in: shape)
                .background(.regularMaterial, in: shape)
                .contrastCardBorder(style, cornerRadius: cornerRadius)
        case .opaque:
            content.background(Color(nsColor: .windowBackgroundColor), in: shape)
                .contrastCardBorder(style, cornerRadius: cornerRadius)
        }
    }
}

extension View {
    /// A11Y-019: an overlay background that turns opaque under Reduce Transparency.
    func overlayBackground(cornerRadius: CGFloat = 10) -> some View {
        modifier(OverlayBackgroundModifier(cornerRadius: cornerRadius))
    }
}

// MARK: Differentiate Without Color (A11Y-021)

/// Every colour-coded state of the app. Each has a twin (symbol or text) shown whatever the setting (UX-VISION §1.7).
nonisolated enum ColorSignal: String, CaseIterable, Sendable {
    case visitedSystem, unvisitedSystem
    case inRange, outOfRange
    case profit, loss, priceUp, priceDown
    case heatmapScale
    case hullCritical, shieldsDown
    case debtWarning
    case policeRecord, reputation
    case encounterPirate, encounterPolice, encounterTrader, encounterMonster, encounterSpecial
    case achievementLocked, achievementUnlocked
    case questDeadline
    case cheatedSave, ironman, reloaded
    case statisticsGain, statisticsLoss

    /// What carries the state besides its colour.
    enum Twin: Equatable, Sendable {
        case symbol(String)
        case text(LocalizedStringResource)
        case symbolAndText(String, LocalizedStringResource)
        /// A shape or opacity difference drawn by the surface (map glyphs, the out-of-range dimming).
        case shape(LocalizedStringResource)
    }

    /// The always-on twin (A11Y-021 table, column 2).
    var twin: Twin {
        switch self {
        case .visitedSystem: .shape("filled system glyph")
        case .unvisitedSystem: .shape("hollow system glyph")
        case .inRange: .shape("full opacity")
        case .outOfRange: .shape("55 percent opacity")
        case .profit: .text("+")
        case .loss: .text("−")
        case .priceUp: .symbol("arrowtriangle.up.fill")
        case .priceDown: .symbol("arrowtriangle.down.fill")
        case .heatmapScale: .text("legend with numeric labels")
        case .hullCritical: .symbolAndText("exclamationmark", "Critical")
        case .shieldsDown: .symbolAndText("exclamationmark", "No shields")
        case .debtWarning: .symbol("exclamationmark.triangle")
        case .policeRecord: .text("police record level word")
        case .reputation: .text("reputation level word")
        case .encounterPirate: .symbolAndText("flag.2.crossed", "Pirate")
        case .encounterPolice: .symbolAndText("shield.lefthalf.filled", "Police")
        case .encounterTrader: .symbolAndText("shippingbox", "Trader")
        case .encounterMonster: .symbolAndText("tortoise", "Monster")
        case .encounterSpecial: .symbolAndText("star", "Special")
        case .achievementLocked: .symbolAndText("lock", "locked")
        case .achievementUnlocked: .symbolAndText("checkmark.seal", "unlocked")
        case .questDeadline: .text("N days left")
        case .cheatedSave: .text("Cheated")
        case .ironman: .text("Ironman")
        case .reloaded: .text("↺")
        case .statisticsGain: .text("+")
        case .statisticsLoss: .text("−")
        }
    }

    /// The extra cue added under Differentiate Without Color (column 3), if any.
    var differentiateExtra: LocalizedStringResource? {
        switch self {
        case .inRange: "dotted ring"
        case .heatmapScale: "hatching on legend swatches"
        case .hullCritical, .shieldsDown: "striped bar"
        default: nil
        }
    }

    /// The extras shown for these preferences.
    func extra(prefs: AccessibilityPreferences) -> LocalizedStringResource? {
        prefs.differentiateWithoutColor ? differentiateExtra : nil
    }
}
