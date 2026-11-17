// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
#if canImport(FoundationModels)
import FoundationModels
#endif

/// LLM-018 / LLM-024 / LLM-025: where log flavor comes from.
nonisolated enum FlavorMode: String, Sendable, Equatable {
    /// `-PMFlavor template`: no model provider exists, no availability check runs, nothing is enqueued.
    case templateForced
    /// The default: the Settings toggle is off, so only template lines are written.
    case templateOnly
    /// The toggle is on: new entries with a flavor subject are sent to the on-device model.
    case foundationModels

    /// The mode for a launch and the Settings toggle (LLM-024 wins over LLM-025).
    static func derive(launch: LaunchOptions, useFoundationModels: Bool) -> FlavorMode {
        if launch.flavorTemplate { return .templateForced }
        return useFoundationModels ? .foundationModels : .templateOnly
    }
}

/// LLM-013: whether the on-device model can be asked right now, with the reason when it cannot.
nonisolated enum FlavorAvailability: String, Sendable, Equatable, CaseIterable {
    case available
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unsupportedLanguage
    case unsupportedBuild

    /// The system model's availability now (`.unsupportedBuild` when the framework is not in this build).
    static var current: FlavorAvailability {
        #if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return model.supportsLocale(Locale.current) ? .available : .unsupportedLanguage
        case let .unavailable(reason):
            switch reason {
            case .deviceNotEligible: return .deviceNotEligible
            case .appleIntelligenceNotEnabled: return .appleIntelligenceNotEnabled
            case .modelNotReady: return .modelNotReady
            @unknown default: return .modelNotReady
            }
        }
        #else
        return .unsupportedBuild
        #endif
    }

    /// LLM-025: the status line under the Settings toggle.
    var text: String {
        switch self {
        case .available: String(localized: "Available")
        case .deviceNotEligible: String(localized: "This Mac doesn't support Apple Intelligence")
        case .appleIntelligenceNotEnabled: String(localized: "Turn on Apple Intelligence in System Settings")
        case .modelNotReady: String(localized: "The model is downloading")
        case .unsupportedLanguage: String(localized: "Not available in your language")
        case .unsupportedBuild: String(localized: "Not available in this build")
        }
    }
}

/// LLM-025: what the Intelligence tab shows for the flavor toggle and its status line.
nonisolated struct FlavorSettingsModel: Equatable, Sendable {
    var toggleEnabled: Bool
    var status: String

    static func make(launch: LaunchOptions, availability: FlavorAvailability) -> FlavorSettingsModel {
        if launch.flavorTemplate {
            return FlavorSettingsModel(toggleEnabled: false, status: String(localized: "Template text is forced by a launch argument"))
        }
        return FlavorSettingsModel(toggleEnabled: availability == .available, status: availability.text)
    }
}
