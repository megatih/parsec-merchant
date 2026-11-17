// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecAudio
import ParsecEngine
import ParsecInsights
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

/// Session services (PRD §6.5). Audio and haptics are real from M11 (AUD-036; `AudioService`, `HapticsService`),
/// achievements (ACH-016) and flavor (LLM-018) from M10. The session calls them at the right moments.
@MainActor protocol SessionAudio: AnyObject {
    /// After every accepted step (AUD-031…034).
    func play(record: StepRecord)
    /// App-originated cues (AUD-030): newspaper, achievement, tribble, the Settings test sound and rejections.
    func play(app: AppCue)
    /// The music mood derived from `DetailMode` (AUD-038).
    func setMood(_ mood: MusicMood)
    /// Transit playback progress, so cues revealed by the playback wait for its end (AUD-033).
    func transit(_ event: TransitAudioEvent)
    /// App activation (AUD-012 "Mute when inactive").
    func setAppActive(_ active: Bool)
    /// What the Settings › Sound status line shows (AUD-011).
    var status: AudioStatus { get }
}

@MainActor protocol SessionHaptics: AnyObject {
    /// After every accepted step (AUD-040).
    func perform(record: StepRecord)
    /// App-originated haptics: quantity snaps and full sliders (AUD-040).
    func perform(app: AppHaptic)
    /// Haptics fire only while the app is active (AUD-041).
    func setAppActive(_ active: Bool)
}

/// ACH-016 / ACH-017: receives each recorded step's unlocks; returns the ids newly added to the app-wide store.
@MainActor protocol SessionAchievements {
    func observe(_ output: JournalStepOutput, gameID: String, state: GameState) -> [AchievementID]
    /// The app-wide unlocks (ACH-015).
    var records: [AchievementRecord] { get }
    /// ACH-021: Settings › Advanced › Reset Achievements.
    func reset() throws
}

/// LLM-018: the flavor service (`FlavorService`).
@MainActor protocol SessionFlavor: AnyObject {
    var mode: FlavorMode { get }
    var isTemplateOnly: Bool { get }
    func setMode(_ mode: FlavorMode)
    func enqueue(_ entries: [LogEntry], gameID: String, names: () -> FlavorNames)
    func cancelAll()
    func setResultHandler(_ handler: @escaping (FlavorResult) -> Void)
}

/// No audio: `-PMAudio off`, unit tests and previews (AUD-044).
final class SilentAudio: SessionAudio {
    func play(record: StepRecord) {}
    func play(app: AppCue) {}
    func setMood(_ mood: MusicMood) {}
    func transit(_ event: TransitAudioEvent) {}
    func setAppActive(_ active: Bool) {}
    var status: AudioStatus { .offForLaunch }
}

/// No haptics: `-PMAudio off`, unit tests and previews (AUD-044).
final class NoHaptics: SessionHaptics {
    func perform(record: StepRecord) {}
    func perform(app: AppHaptic) {}
    func setAppActive(_ active: Bool) {}
}

/// ACH-018: the service that unlocks nothing (the reference run of the determinism test).
struct NoAchievements: SessionAchievements {
    func observe(_ output: JournalStepOutput, gameID: String, state: GameState) -> [AchievementID] { [] }
    var records: [AchievementRecord] { [] }
    func reset() throws {}
}

/// The persistence services the session owns.
struct SessionStores: Sendable {
    var slotStore: SlotStore
    var highScoreStore: HighScoreStore
    var achievementStore: AchievementStore

    init(root: URL, appVersion: String = AppPaths.appVersion) {
        slotStore = SlotStore(root: root, appVersion: appVersion)
        highScoreStore = HighScoreStore(root: root)
        achievementStore = AchievementStore(root: root)
    }
}
