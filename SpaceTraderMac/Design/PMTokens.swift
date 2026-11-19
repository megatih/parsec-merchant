// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// UI-DS-020: the colours of the game area (docs/PRD-UI-Revamp.md §3.3). One dark "console" palette in both system
/// appearances; window chrome, menus and sheets' frames follow the system. Views use these tokens, never colour literals.
nonisolated enum PMColor {
    /// sRGB components 0…1 of a token (the contrast test of UI-DS-010 reads these).
    struct RGB: Equatable, Sendable {
        var r: Double
        var g: Double
        var b: Double

        init(_ hex: UInt32) {
            r = Double((hex >> 16) & 0xFF) / 255
            g = Double((hex >> 8) & 0xFF) / 255
            b = Double(hex & 0xFF) / 255
        }

        var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }

        /// WCAG relative luminance.
        var luminance: Double {
            func channel(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
        }

        /// WCAG contrast ratio against another colour, 1…21.
        func contrast(with other: RGB) -> Double {
            let a = luminance, b = other.luminance
            return (max(a, b) + 0.05) / (min(a, b) + 0.05)
        }
    }

    enum Token: String, CaseIterable, Sendable {
        case space, panel, panelRaised, panelInset, hairline, strongLine, textPrimary, textSecondary, textDisabled, accent
        case profit, loss, caution, info, rolePolice, rolePirate, roleTrader, roleAlien
    }

    static func rgb(_ token: Token) -> RGB {
        switch token {
        case .space: RGB(0x070A12)
        case .panel: RGB(0x111827)
        case .panelRaised: RGB(0x1A2436)
        case .panelInset: RGB(0x0C1220)
        case .hairline: RGB(0x2A3650)
        case .strongLine: RGB(0x5A6E94)
        case .textPrimary: RGB(0xE8EEF8)
        case .textSecondary: RGB(0xA9B6CC)
        case .textDisabled: RGB(0x7C89A1)
        case .accent: RGB(0xE0B050)
        case .profit: RGB(0x5BD68A)
        case .loss: RGB(0xFF7A6B)
        case .caution: RGB(0xF5B942)
        case .info: RGB(0x6CB6FF)
        case .rolePolice: RGB(0x5AA0FF)
        case .rolePirate: RGB(0xFF6B5E)
        case .roleTrader: RGB(0x7FD1AE)
        case .roleAlien: RGB(0xB48CFF)
        }
    }

    static let space = rgb(.space).color
    static let panel = rgb(.panel).color
    static let panelRaised = rgb(.panelRaised).color
    static let panelInset = rgb(.panelInset).color
    static let hairline = rgb(.hairline).color
    static let strongLine = rgb(.strongLine).color
    static let textPrimary = rgb(.textPrimary).color
    static let textSecondary = rgb(.textSecondary).color
    static let textDisabled = rgb(.textDisabled).color
    static let accent = rgb(.accent).color
    static let profit = rgb(.profit).color
    static let loss = rgb(.loss).color
    static let caution = rgb(.caution).color
    static let info = rgb(.info).color
    static let rolePolice = rgb(.rolePolice).color
    static let rolePirate = rgb(.rolePirate).color
    static let roleTrader = rgb(.roleTrader).color
    static let roleAlien = rgb(.roleAlien).color

    /// UI-DS-011: with Increase Contrast, hairlines become strong lines and secondary text becomes primary.
    static func border(increaseContrast: Bool) -> Color { increaseContrast ? strongLine : hairline }
    static func label(increaseContrast: Bool) -> Color { increaseContrast ? textPrimary : textSecondary }
    static func borderWidth(increaseContrast: Bool) -> CGFloat { increaseContrast ? 2 : 1 }
}

/// A meaning carried by colour, always together with a symbol or a word (UI-DS-012).
nonisolated enum PMTone: String, CaseIterable, Sendable {
    case neutral, profit, loss, caution, info

    var color: Color {
        switch self {
        case .neutral: PMColor.textPrimary
        case .profit: PMColor.profit
        case .loss: PMColor.loss
        case .caution: PMColor.caution
        case .info: PMColor.info
        }
    }

    /// The symbol that carries the meaning without colour; nil for neutral.
    var symbol: String? {
        switch self {
        case .neutral: nil
        case .profit: "arrowtriangle.up.fill"
        case .loss: "arrowtriangle.down.fill"
        case .caution: "exclamationmark.triangle.fill"
        case .info: "info.circle"
        }
    }
}

/// UI-DS-020: spacing on a 4-point grid, at interface scale 1.
nonisolated enum PMSpace {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let all: [CGFloat] = [xs, s, m, l, xl]
}

/// UI-DS-020: the two corner radii.
nonisolated enum PMRadius {
    static let control: CGFloat = 4
    static let panel: CGFloat = 8
}

/// UI-DS-020: durations in seconds. Nothing in the interface is longer than 0.35 s except transit, combat and endings.
nonisolated enum PMMotion {
    static let hover = 0.12
    static let page = 0.20
    static let value = 0.25
    static let longest = 0.35

    /// The animation for a kind of change; nil with Reduce Motion (changes are then instant).
    static func animation(_ duration: Double, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: duration)
    }
}

/// UI-DS-020: the type styles of the game area, at interface scale 1 (PRD §3.4). Nothing is smaller than 11 pt.
nonisolated enum PMFont {
    enum Style: CaseIterable, Sendable {
        case title, panelTitle, body, value, valueLarge, caption
        /// Dock button labels: a little smaller than body, so ten pages fit the minimum window on one line.
        case dock

        var size: CGFloat {
            switch self {
            case .title: 17
            case .panelTitle: 11
            case .body: 13
            case .value: 13
            case .valueLarge: 15
            case .caption: 11
            case .dock: 12
            }
        }

        var weight: Font.Weight {
            switch self {
            case .title, .panelTitle, .valueLarge: .semibold
            case .value: .medium
            case .body, .caption, .dock: .regular
            }
        }
    }

    static func font(_ style: Style, scale: CGFloat) -> Font {
        let font = Font.system(size: (style.size * scale).rounded(), weight: style.weight)
        return style == .value || style == .valueLarge ? font.monospacedDigit() : font
    }
}

/// UI-DS-002: the interface scale of the game area.
nonisolated enum PMScale {
    static let designSize = CGSize(width: 1200, height: 680)
    static let maximum: CGFloat = 2
    static let step: CGFloat = 0.05

    /// `clamp(min(W / 1200, H / 680), floor, 2)`, rounded down to a multiple of 0.05.
    static func scale(for size: CGSize, floor: CGFloat = 1) -> CGFloat {
        let fitted = min(size.width / designSize.width, size.height / designSize.height)
        let stepped = (fitted / step + 1e-6).rounded(.down) * step
        return min(maximum, max(max(1, floor), stepped))
    }

    /// UI-DS-004: the Text Size steps: the lower clamp of the interface scale.
    static let textSteps: [CGFloat] = [1, 1.15, 1.3, 1.5, 2]

    /// The window's minimum content size at a Text Size floor.
    static func minimumSize(floor: CGFloat) -> CGSize {
        CGSize(width: (designSize.width * floor).rounded(), height: (designSize.height * floor).rounded())
    }

    /// The largest Text Size step at or below `wanted` whose minimum window fits `available` (the screen's visible
    /// frame less the title bar); never below 1.
    static func effectiveFloor(wanted: CGFloat, available: CGSize?) -> CGFloat {
        let candidates = textSteps.filter { $0 <= wanted + 1e-6 }
        guard let available else { return candidates.last ?? 1 }
        return candidates.last { minimumSize(floor: $0).width <= available.width && minimumSize(floor: $0).height <= available.height } ?? 1
    }
}

extension EnvironmentValues {
    /// UI-DS-002: the interface scale of the game area this view is in (1 at the minimum window).
    @Entry var pmScale: CGFloat = 1
}

extension View {
    /// A game-area type style at the interface scale.
    func pmFont(_ style: PMFont.Style) -> some View { modifier(PMFontModifier(style: style)) }

    /// Padding from the spacing tokens, at the interface scale.
    func pmPadding(_ edges: Edge.Set = .all, _ space: CGFloat = PMSpace.m) -> some View { modifier(PMPaddingModifier(edges: edges, space: space)) }
}

private struct PMFontModifier: ViewModifier {
    @Environment(\.pmScale) private var scale
    let style: PMFont.Style

    func body(content: Content) -> some View {
        content
            .font(PMFont.font(style, scale: scale))
            .textCase(style == .panelTitle ? .uppercase : nil)
            .tracking(style == .panelTitle ? 0.6 * scale : 0)
    }
}

private struct PMPaddingModifier: ViewModifier {
    @Environment(\.pmScale) private var scale
    let edges: Edge.Set
    let space: CGFloat

    func body(content: Content) -> some View { content.padding(edges, space * scale) }
}
