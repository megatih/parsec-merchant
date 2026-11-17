// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// A11Y-024 fallback. `.dynamicTypeSize` does not change text on macOS (the guard test renders the same height at `.large`
/// and `.accessibility3`), so Text Size scales an app font metric instead: every text style is a system font of the
/// macOS point size times `textScale`, and the root sets the scaled body font for controls and plain text.
extension TextSizeSetting {
    /// The multiplier of the macOS text-style sizes.
    var scale: CGFloat {
        switch self {
        case .small: 0.85
        case .medium: 0.92
        case .large: 1
        case .xLarge: 1.12
        case .xxLarge: 1.24
        case .xxxLarge: 1.36
        case .accessibility1: 1.55
        case .accessibility2: 1.75
        case .accessibility3: 2
        }
    }
}

extension EnvironmentValues {
    /// A11Y-024: the Text Size multiplier of this window (1 at the default size).
    @Entry var textScale: CGFloat = 1
}

/// The macOS point sizes of the text styles (the system's values at the default size).
nonisolated enum AppFontMetrics {
    static func pointSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 26
        case .title: 22
        case .title2: 17
        case .title3: 15
        case .headline: 13
        case .subheadline: 11
        case .body: 13
        case .callout: 12
        case .footnote: 10
        case .caption: 10
        case .caption2: 10
        case .extraLargeTitle: 36
        case .extraLargeTitle2: 28
        @unknown default: 13
        }
    }

    /// The default weight of a style (macOS headlines are bold).
    static func weight(_ style: Font.TextStyle) -> Font.Weight {
        style == .headline ? .bold : .regular
    }

    static func font(_ style: Font.TextStyle, scale: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil) -> Font {
        .system(size: (pointSize(style) * scale).rounded(), weight: weight ?? Self.weight(style), design: design ?? .default)
    }
}

/// Applies a text style at the window's Text Size (A11Y-024).
struct ScaledFont: ViewModifier {
    @Environment(\.textScale) private var scale
    let style: Font.TextStyle
    var weight: Font.Weight?
    var design: Font.Design?

    func body(content: Content) -> some View {
        content.font(AppFontMetrics.font(style, scale: scale, weight: weight, design: design))
    }
}

extension View {
    /// A text style that follows the app's Text Size setting (use instead of `.font(.<style>)`, A11Y-024).
    func scaledFont(_ style: Font.TextStyle, weight: Font.Weight? = nil, design: Font.Design? = nil) -> some View {
        modifier(ScaledFont(style: style, weight: weight, design: design))
    }
}
