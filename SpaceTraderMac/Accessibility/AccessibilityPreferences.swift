// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecArt
import SwiftUI

/// The four display settings every view, style and art input reads (A11Y-001). Resolved once per window root from the
/// system environment, each OR'd with the Debug `-PMA11y` override (A11Y-002).
nonisolated struct AccessibilityPreferences: Equatable, Hashable, Sendable {
    var reduceMotion = false
    var increaseContrast = false
    var reduceTransparency = false
    var differentiateWithoutColor = false

    static let standard = AccessibilityPreferences()

    /// The `-PMA11y` names, in declaration order.
    enum Setting: String, CaseIterable, Sendable {
        case reduceMotion, increaseContrast, reduceTransparency, differentiateWithoutColor
    }

    init(reduceMotion: Bool = false, increaseContrast: Bool = false, reduceTransparency: Bool = false,
         differentiateWithoutColor: Bool = false) {
        self.reduceMotion = reduceMotion
        self.increaseContrast = increaseContrast
        self.reduceTransparency = reduceTransparency
        self.differentiateWithoutColor = differentiateWithoutColor
    }

    init(_ settings: Set<Setting>) {
        self.init(reduceMotion: settings.contains(.reduceMotion), increaseContrast: settings.contains(.increaseContrast),
                  reduceTransparency: settings.contains(.reduceTransparency),
                  differentiateWithoutColor: settings.contains(.differentiateWithoutColor))
    }

    /// A11Y-001: each setting is on when the system or the override has it on.
    static func resolve(system: AccessibilityPreferences, override: AccessibilityPreferences) -> AccessibilityPreferences {
        AccessibilityPreferences(reduceMotion: system.reduceMotion || override.reduceMotion,
                                 increaseContrast: system.increaseContrast || override.increaseContrast,
                                 reduceTransparency: system.reduceTransparency || override.reduceTransparency,
                                 differentiateWithoutColor: system.differentiateWithoutColor || override.differentiateWithoutColor)
    }

    /// A11Y-002: the comma-separated `-PMA11y` list. Unknown names and blanks are ignored.
    static func parse(list: String) -> AccessibilityPreferences {
        let names = list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return AccessibilityPreferences(Set(names.compactMap(Setting.init(rawValue:))))
    }

    /// ART-004's input.
    var art: ArtAccessibility {
        ArtAccessibility(reduceMotion: reduceMotion, increaseContrast: increaseContrast,
                         reduceTransparency: reduceTransparency, differentiateWithoutColor: differentiateWithoutColor)
    }
}

extension EnvironmentValues {
    /// A11Y-001: the resolved preferences of this window (system OR Debug override).
    @Entry var accessibilityPreferences = AccessibilityPreferences.standard
}

/// Resolves the preferences at a scene root and publishes them to the views and the art below (A11Y-001).
struct AccessibilityPreferencesRoot: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    var override: AccessibilityPreferences = Self.processOverride

    /// The `-PMA11y` value of this process (empty in Release, CHEAT-047).
    static let processOverride = LaunchOptions.current.accessibility

    func body(content: Content) -> some View {
        let system = AccessibilityPreferences(reduceMotion: reduceMotion, increaseContrast: contrast == .increased,
                                              reduceTransparency: reduceTransparency,
                                              differentiateWithoutColor: differentiateWithoutColor)
        let prefs = AccessibilityPreferences.resolve(system: system, override: override)
        content
            .environment(\.accessibilityPreferences, prefs)
            .environment(\.artAccessibilityOverride, prefs.art)
    }
}

/// The modifiers every scene root applies: Text Size (A11Y-024) and the accessibility preferences (A11Y-001).
struct SceneAccessibility: ViewModifier {
    func body(content: Content) -> some View {
        content
            .modifier(AccessibilityPreferencesRoot())
            .modifier(AppTextSize())
    }
}
