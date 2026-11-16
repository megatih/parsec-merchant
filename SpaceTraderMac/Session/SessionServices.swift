// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import ParsecPersistence

/// Where the app keeps its files: `Application Support/Parsec Merchant/` inside the sandbox container.
enum AppPaths {
    static let folderName = "Parsec Merchant"

    static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(folderName, isDirectory: true)
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// CHEAT-051: deletes everything under the root folder and the app's defaults domain.
    static func resetState(root: URL, defaults: UserDefaults, domain: String?) {
        try? FileManager.default.removeItem(at: root)
        if let domain { defaults.removePersistentDomain(forName: domain) }
    }
}

/// UserDefaults keys owned by the shell.
enum DefaultsKey {
    static let lastCommanderName = "lastCommanderName"
    /// OPT-027: `defaultGameOptions.<rulesetID>` holds a JSON-encoded `GameOptions` template.
    static func optionsTemplate(_ r: RulesetID) -> String { "defaultGameOptions.\(r.rawValue)" }
}

/// OPT-027: the per-ruleset options template used by New Game and Quick Start.
enum OptionsTemplate {
    static func load(for ruleset: RulesetID, defaults: UserDefaults) -> GameOptions? {
        guard let data = defaults.data(forKey: DefaultsKey.optionsTemplate(ruleset)) else { return nil }
        return try? JSONDecoder().decode(GameOptions.self, from: data)
    }

    static func save(_ options: GameOptions, for ruleset: RulesetID, defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(options) {
            defaults.set(data, forKey: DefaultsKey.optionsTemplate(ruleset))
        }
    }
}

/// No-op stand-ins for services that arrive later (audio M11, haptics M11, achievements M10, flavor M10).
/// The session calls them at the right moments so the later milestones only replace the implementations.
@MainActor protocol SessionAudio { func play(events: [GameEvent]) }
@MainActor protocol SessionHaptics { func perform(events: [GameEvent]) }
@MainActor protocol SessionAchievements { func observe(events: [GameEvent], state: GameState) }
@MainActor protocol SessionFlavor { var isTemplateOnly: Bool { get } }

struct SilentAudio: SessionAudio { func play(events: [GameEvent]) {} }
struct NoHaptics: SessionHaptics { func perform(events: [GameEvent]) {} }
struct NoAchievements: SessionAchievements { func observe(events: [GameEvent], state: GameState) {} }
struct TemplateFlavor: SessionFlavor { var isTemplateOnly: Bool { true } }

/// The persistence services the session owns.
struct SessionStores: Sendable {
    var slotStore: SlotStore
    var highScoreStore: HighScoreStore

    init(root: URL, appVersion: String = AppPaths.appVersion) {
        slotStore = SlotStore(root: root, appVersion: appVersion)
        highScoreStore = HighScoreStore(root: root)
    }
}
