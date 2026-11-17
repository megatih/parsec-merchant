// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// An sRGB colour value with alpha, in 0…1.
public struct ArtRGB: Sendable, Hashable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    public func opacity(_ o: Double) -> ArtRGB { ArtRGB(r, g, b, a * o) }

    /// Linear blend towards `other` by `t` (0: self, 1: other).
    public func mix(_ other: ArtRGB, _ t: Double) -> ArtRGB {
        ArtRGB(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t, a + (other.a - a) * t)
    }

    /// Scales the brightness (values above 1 lighten towards white).
    public func shade(_ f: Double) -> ArtRGB {
        f <= 1 ? ArtRGB(r * f, g * f, b * f, a) : mix(ArtRGB(1, 1, 1, a), min(1, f - 1))
    }

    /// Keeps `amount` of the saturation (0: grey, 1: unchanged).
    public func saturation(_ amount: Double) -> ArtRGB {
        let grey = 0.299 * r + 0.587 * g + 0.114 * b
        return ArtRGB(grey + (r - grey) * amount, grey + (g - grey) * amount, grey + (b - grey) * amount, a)
    }
}

/// ART-003: every art colour as a token.
public enum ArtToken: String, Sendable, Hashable, CaseIterable {
    // Space and map (MAP-024, MAP-037).
    case spaceTop, spaceBottom, visited, unvisited, wormholeA, wormholeB, brass
    // Signals.
    case danger, profit, shieldEnergy, shieldReflective, shieldLightning, engineGlow, scorch, outline, highlight, spark
    // Liveries.
    case hullGrey, slateBlue, slate, ivory, rust, cream, amber, nightBlack, crimson, violet, teal, iridescentGreen,
         iridescentBlue, yellowGreen, glassTint, cork, parchment, olive, sand, steel, alienGlow, bioGlow
    // Planets.
    case ocean, oceanDeep, landGreen, landBrown, landSand, landGrey, landDark, landPale, landLush, ice, cloud, cityLight,
         haze, smoke, fire, plague, atmosphere, mushroom, herb, metal, ring
}

/// ART-003: light, dark and Increase Contrast variants of each token.
public enum ArtPalette {
    struct Entry {
        var light: ArtRGB
        var dark: ArtRGB
        var contrast: ArtRGB?
    }

    static func entry(_ token: ArtToken) -> Entry {
        func e(_ l: ArtRGB, _ d: ArtRGB? = nil, _ c: ArtRGB? = nil) -> Entry { Entry(light: l, dark: d ?? l, contrast: c) }
        switch token {
        case .spaceTop: return e(ArtRGB(0.16, 0.17, 0.36), ArtRGB(0.09, 0.08, 0.22), ArtRGB(0.08, 0.08, 0.20))
        case .spaceBottom: return e(ArtRGB(0.05, 0.06, 0.14), ArtRGB(0.01, 0.01, 0.04), ArtRGB(0, 0, 0))
        case .visited: return e(ArtRGB(0.35, 0.75, 1.0), ArtRGB(0.40, 0.80, 1.0), ArtRGB(0.55, 0.90, 1.0))
        case .unvisited: return e(ArtRGB(0.35, 0.90, 0.45), ArtRGB(0.40, 0.95, 0.50), ArtRGB(0.50, 1.0, 0.60))
        case .wormholeA: return e(ArtRGB(1.0, 0.70, 0.20))
        case .wormholeB: return e(ArtRGB(0.90, 0.30, 0.85))
        case .brass: return e(ArtRGB(0.86, 0.70, 0.35), nil, ArtRGB(1.0, 0.80, 0.30))
        case .danger: return e(ArtRGB(0.85, 0.18, 0.15), ArtRGB(1.0, 0.30, 0.25), ArtRGB(1.0, 0.10, 0.05))
        case .profit: return e(ArtRGB(0.20, 0.70, 0.30), ArtRGB(0.35, 0.85, 0.45))
        case .shieldEnergy: return e(ArtRGB(0.35, 0.65, 1.0), ArtRGB(0.45, 0.75, 1.0), ArtRGB(0.30, 0.60, 1.0))
        case .shieldReflective: return e(ArtRGB(0.70, 0.85, 0.95), ArtRGB(0.80, 0.92, 1.0), ArtRGB(0.85, 0.95, 1.0))
        case .shieldLightning: return e(ArtRGB(0.65, 0.45, 1.0), ArtRGB(0.75, 0.55, 1.0), ArtRGB(0.80, 0.55, 1.0))
        case .engineGlow: return e(ArtRGB(1.0, 0.60, 0.25), ArtRGB(1.0, 0.68, 0.30))
        case .scorch: return e(ArtRGB(0.12, 0.09, 0.07), ArtRGB(0.10, 0.07, 0.05), ArtRGB(0, 0, 0))
        case .outline: return e(ArtRGB(0.10, 0.11, 0.16), ArtRGB(0.80, 0.82, 0.90), ArtRGB(0, 0, 0))
        case .highlight: return e(ArtRGB(1, 1, 1))
        case .spark: return e(ArtRGB(1.0, 0.90, 0.50))
        default: return liveryEntry(token) ?? planetEntry(token)
        }
    }

    private static func liveryEntry(_ token: ArtToken) -> Entry? {
        func e(_ l: ArtRGB, _ d: ArtRGB? = nil) -> Entry { Entry(light: l, dark: d ?? l.shade(0.9), contrast: nil) }
        switch token {
        case .hullGrey: return e(ArtRGB(0.62, 0.66, 0.72))
        case .slateBlue: return e(ArtRGB(0.42, 0.52, 0.66))
        case .slate: return e(ArtRGB(0.32, 0.36, 0.42))
        case .ivory: return e(ArtRGB(0.90, 0.88, 0.80))
        case .rust: return e(ArtRGB(0.66, 0.33, 0.20))
        case .cream: return e(ArtRGB(0.93, 0.87, 0.72))
        case .amber: return e(ArtRGB(0.95, 0.66, 0.15))
        case .nightBlack: return e(ArtRGB(0.14, 0.14, 0.17), ArtRGB(0.20, 0.20, 0.24))
        case .crimson: return e(ArtRGB(0.72, 0.10, 0.16))
        case .violet: return e(ArtRGB(0.50, 0.30, 0.70))
        case .teal: return e(ArtRGB(0.15, 0.62, 0.62))
        case .iridescentGreen: return e(ArtRGB(0.20, 0.75, 0.55))
        case .iridescentBlue: return e(ArtRGB(0.25, 0.50, 0.90))
        case .yellowGreen: return e(ArtRGB(0.80, 0.95, 0.30))
        case .glassTint: return e(ArtRGB(0.65, 0.85, 0.80, 0.45))
        case .cork: return e(ArtRGB(0.62, 0.45, 0.28))
        case .parchment: return e(ArtRGB(0.95, 0.90, 0.74))
        case .olive: return e(ArtRGB(0.45, 0.50, 0.25))
        case .sand: return e(ArtRGB(0.85, 0.75, 0.52))
        case .steel: return e(ArtRGB(0.52, 0.55, 0.60))
        case .alienGlow: return e(ArtRGB(0.40, 1.0, 0.85))
        case .bioGlow: return e(ArtRGB(0.70, 0.40, 1.0))
        default: return nil
        }
    }

    private static func planetEntry(_ token: ArtToken) -> Entry {
        func e(_ l: ArtRGB) -> Entry { Entry(light: l, dark: l.shade(0.92), contrast: nil) }
        switch token {
        case .ocean: return e(ArtRGB(0.16, 0.42, 0.72))
        case .oceanDeep: return e(ArtRGB(0.06, 0.20, 0.45))
        case .landGreen: return e(ArtRGB(0.30, 0.55, 0.28))
        case .landBrown: return e(ArtRGB(0.52, 0.40, 0.26))
        case .landSand: return e(ArtRGB(0.86, 0.74, 0.48))
        case .landGrey: return e(ArtRGB(0.55, 0.55, 0.55))
        case .landDark: return e(ArtRGB(0.16, 0.36, 0.18))
        case .landPale: return e(ArtRGB(0.74, 0.64, 0.50))
        case .landLush: return e(ArtRGB(0.22, 0.70, 0.30))
        case .ice: return e(ArtRGB(0.93, 0.96, 1.0))
        case .cloud: return e(ArtRGB(1, 1, 1, 0.75))
        case .cityLight: return e(ArtRGB(1.0, 0.86, 0.45))
        case .haze: return e(ArtRGB(0.60, 0.50, 0.35, 0.35))
        case .smoke: return e(ArtRGB(0.25, 0.22, 0.22, 0.55))
        case .fire: return e(ArtRGB(1.0, 0.42, 0.10))
        case .plague: return e(ArtRGB(0.70, 0.85, 0.20, 0.35))
        case .atmosphere: return e(ArtRGB(0.55, 0.80, 1.0))
        case .mushroom: return e(ArtRGB(0.62, 0.35, 0.75))
        case .herb: return e(ArtRGB(0.20, 0.72, 0.68))
        case .metal: return e(ArtRGB(0.82, 0.84, 0.88))
        case .ring: return e(ArtRGB(0.80, 0.76, 0.66, 0.85))
        default: return e(ArtRGB(1, 0, 1))
        }
    }

    /// The raw value of `token` for a scheme and contrast setting.
    public static func rgb(_ token: ArtToken, scheme: ColorScheme, contrast: Bool = false) -> ArtRGB {
        let e = entry(token)
        if contrast, let c = e.contrast { return c }
        return scheme == .dark ? e.dark : e.light
    }

    /// ART-003: the token as an sRGB `Color`.
    public static func resolve(_ token: ArtToken, scheme: ColorScheme, contrast: Bool = false) -> Color {
        rgb(token, scheme: scheme, contrast: contrast).color
    }

    /// Whether the token has a distinct dark variant (ART-050).
    public static func hasDarkVariant(_ token: ArtToken) -> Bool {
        entry(token).light != entry(token).dark
    }
}

/// Resolves tokens for one render.
public struct ArtInk: Sendable, Hashable {
    public var scheme: ColorScheme
    public var contrast: Bool

    public init(scheme: ColorScheme, contrast: Bool) {
        self.scheme = scheme
        self.contrast = contrast
    }

    public func rgb(_ token: ArtToken) -> ArtRGB { ArtPalette.rgb(token, scheme: scheme, contrast: contrast) }
    public func callAsFunction(_ token: ArtToken) -> Color { rgb(token).color }
}
