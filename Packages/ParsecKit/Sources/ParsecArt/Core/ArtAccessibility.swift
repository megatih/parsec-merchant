// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// ART-004: the accessibility settings that change how art draws, passed in as a value so tests can render every variant.
public struct ArtAccessibility: Sendable, Hashable {
    public var reduceMotion: Bool
    public var increaseContrast: Bool
    public var reduceTransparency: Bool
    public var differentiateWithoutColor: Bool

    public init(reduceMotion: Bool = false, increaseContrast: Bool = false, reduceTransparency: Bool = false,
                differentiateWithoutColor: Bool = false) {
        self.reduceMotion = reduceMotion
        self.increaseContrast = increaseContrast
        self.reduceTransparency = reduceTransparency
        self.differentiateWithoutColor = differentiateWithoutColor
    }

    public static let standard = ArtAccessibility()

    /// ART-004: outline widths are 1.5× under Increase Contrast.
    public var outlineScale: Double { increaseContrast ? 1.5 : 1 }

    /// ART-004: ambient animation stops under Reduce Motion (a still frame is phase 0).
    public func ambientPhase(_ phase: Double) -> Double { reduceMotion ? 0 : phase }
}

/// Reads the four settings from the environment for a host view.
public struct ArtAccessibilityReader<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    private let content: (ArtAccessibility) -> Content

    public init(@ViewBuilder content: @escaping (ArtAccessibility) -> Content) {
        self.content = content
    }

    public var body: some View {
        content(ArtAccessibility(reduceMotion: reduceMotion, increaseContrast: contrast == .increased,
                                 reduceTransparency: reduceTransparency, differentiateWithoutColor: differentiateWithoutColor))
    }
}
