// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// The Settings tabs (OPT-028, UI-SHELL-100). Raw values are the identifier suffixes.
nonisolated enum SettingsTab: String, CaseIterable, Sendable {
    case general, sound, intelligence, advanced

    var title: LocalizedStringResource {
        switch self {
        case .general: "General"
        case .sound: "Sound"
        case .intelligence: "Intelligence"
        case .advanced: "Advanced"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .sound: "speaker.wave.2"
        case .intelligence: "sparkles"
        case .advanced: "slider.horizontal.3"
        }
    }

    /// The milestone that brings the tab's controls, for tabs still empty (none since M11, AUD-042).
    var arrivesIn: Int? {
        switch self {
        case .general, .advanced, .intelligence, .sound: nil
        }
    }
}

/// The Text Size choices: `DynamicTypeSize` from `.small` to `.accessibility3` (UI-SHELL-100).
nonisolated enum TextSizeSetting: String, CaseIterable, Sendable {
    case small, medium, large, xLarge, xxLarge, xxxLarge, accessibility1, accessibility2, accessibility3

    static let standard = TextSizeSetting.large

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .xLarge
        case .xxLarge: .xxLarge
        case .xxxLarge: .xxxLarge
        case .accessibility1: .accessibility1
        case .accessibility2: .accessibility2
        case .accessibility3: .accessibility3
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large (Default)"
        case .xLarge: "Extra Large"
        case .xxLarge: "Extra Extra Large"
        case .xxxLarge: "Huge"
        case .accessibility1: "Accessibility 1"
        case .accessibility2: "Accessibility 2"
        case .accessibility3: "Accessibility 3"
        }
    }
}

/// How the arrival report is shown (used from M9).
nonisolated enum ArrivalReportStyle: String, CaseIterable, Sendable {
    case card, sheet

    var title: LocalizedStringResource {
        switch self {
        case .card: "Card"
        case .sheet: "Sheet"
        }
    }
}

/// App-wide settings in `UserDefaults` (OPT-028). None of them reaches the engine or a save.
nonisolated enum AppSettingsKey {
    static let textSize = "settings.textSize"
    static let fastTravel = "settings.fastTravel"
    static let arrivalReportStyle = "settings.arrivalReportStyle"
    static let tacticalReadout = "settings.tacticalReadout"
    /// INT-038 (default on).
    static let showRecommendations = "settings.intel.showRecommendations"
    /// LLM-025 (default off).
    static let useFoundationModels = "settings.flavor.useFoundationModels"
    /// LLM-027 (default on).
    static let showFlavor = "settings.flavor.show"
}

/// Reads of the app settings (pure over a `UserDefaults`).
struct AppSettings {
    let defaults: UserDefaults

    var textSize: TextSizeSetting {
        defaults.string(forKey: AppSettingsKey.textSize).flatMap(TextSizeSetting.init(rawValue:)) ?? .standard
    }

    var fastTravel: Bool { defaults.object(forKey: AppSettingsKey.fastTravel) as? Bool ?? false }

    var arrivalReportStyle: ArrivalReportStyle {
        defaults.string(forKey: AppSettingsKey.arrivalReportStyle).flatMap(ArrivalReportStyle.init(rawValue:)) ?? .card
    }

    var tacticalReadout: Bool { defaults.object(forKey: AppSettingsKey.tacticalReadout) as? Bool ?? true }

    var showRecommendations: Bool { defaults.object(forKey: AppSettingsKey.showRecommendations) as? Bool ?? true }
    var useFoundationModels: Bool { defaults.object(forKey: AppSettingsKey.useFoundationModels) as? Bool ?? false }
    var showFlavor: Bool { defaults.object(forKey: AppSettingsKey.showFlavor) as? Bool ?? true }

    /// CHEAT-050: transit is instant with the setting or `-PMFastTravel`.
    func isFastTravel(launch: LaunchOptions) -> Bool { fastTravel || launch.fastTravel }
}

/// Applies the Text Size setting to a window (UI-SHELL-100).
struct AppTextSize: ViewModifier {
    @AppStorage(AppSettingsKey.textSize) private var textSize = TextSizeSetting.standard.rawValue

    func body(content: Content) -> some View {
        content.dynamicTypeSize((TextSizeSetting(rawValue: textSize) ?? .standard).dynamicTypeSize)
    }
}
