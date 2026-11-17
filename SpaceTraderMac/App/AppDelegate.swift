// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import ParsecEngine
import ParsecPersistence

/// Owns the one `GameSession` of the process and the AppKit lifecycle hooks (UI-SHELL-013, -015).
final class AppDelegate: NSObject, NSApplicationDelegate {
    let launchOptions: LaunchOptions
    let session: GameSession
    let helpRouter = HelpRouter()

    override init() {
        // UI-SHELL-013: bare debug flags (`-PMResetState -PMSeed 11`) make NSUserDefaults read the next flag as the
        // value and leave "11" over, which AppKit would open as a document instead of opening the main window.
        // Finder opens arrive as Apple events, not arguments, so nothing is lost.
        UserDefaults.standard.register(defaults: [LaunchOptions.treatUnknownArgumentsAsOpenKey: "NO"])
        let options = LaunchOptions.current
        launchOptions = options
        session = AppBootstrap.makeSession(options: options, defaults: .standard)
        super.init()
        // App Intents reach the session through this bridge (UI-SHELL-112…114).
        IntentSessionBridge.session = session
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let scenario = launchOptions.scenario {
            let status = ScenarioRunner.run(scenario, session: session)
            if let status { exit(status) }
        }
    }

    /// UI-ENC-011: the Dock badge shows only while the app is inactive.
    func applicationDidBecomeActive(_ notification: Notification) { session.setAppActive(true) }
    func applicationDidResignActive(_ notification: Notification) { session.setAppActive(false) }

    /// ⌘W closes the window; the app keeps running (UI-SHELL-015).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Clicking the Dock icon with no visible window lets SwiftUI reopen the main window with the same session.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { true }

    /// Quitting autosaves (SAV-038) or writes the Ironman slot (SAV-046), and never asks to discard (SAV-043).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        session.writeOnQuit()
        return .terminateNow
    }

    /// Finder-open of `.parsecsave` files (UI-SHELL-093): each file is imported and offered in turn.
    func application(_ application: NSApplication, open urls: [URL]) {
        session.openFromFinder(urls)
    }
}

/// The launch sequence (UI-SHELL-013): parse, reset, create stores, create the session.
enum AppBootstrap {
    static func makeSession(options: LaunchOptions, defaults: UserDefaults, root: URL = AppPaths.applicationSupport) -> GameSession {
        if options.resetState {
            AppPaths.resetState(root: root, defaults: defaults, domain: Bundle.main.bundleIdentifier)
        }
        let stores = SessionStores(root: root)
        // LLM-024 / LLM-025: `-PMFlavor template` forces templates; otherwise the Settings toggle (default off) decides.
        let useModel = defaults.object(forKey: AppSettingsKey.useFoundationModels) as? Bool ?? false
        let flavor = FlavorService(mode: FlavorMode.derive(launch: options, useFoundationModels: useModel))
        // AUD-044: `-PMAudio off` gets `SilentAudio`/`NoHaptics` and never creates an audio engine.
        let services = SessionAudioFactory.make(options: options, defaults: defaults)
        return GameSession(stores: stores, launchOptions: options, defaults: defaults, audio: services.audio,
                           haptics: services.haptics, achievements: AchievementService(store: stores.achievementStore),
                           flavor: flavor, dock: AppDock())
    }
}
