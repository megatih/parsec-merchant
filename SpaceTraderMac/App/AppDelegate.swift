// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import ParsecEngine
import ParsecPersistence

/// Owns the one `GameSession` of the process and the AppKit lifecycle hooks (UI-SHELL-013, -015).
final class AppDelegate: NSObject, NSApplicationDelegate {
    let launchOptions: LaunchOptions
    let session: GameSession

    override init() {
        let options = LaunchOptions.current
        launchOptions = options
        session = AppBootstrap.makeSession(options: options, defaults: .standard)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let scenario = launchOptions.scenario {
            let status = ScenarioRunner.run(scenario, session: session)
            if let status { exit(status) }
        }
    }

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
        for url in urls {
            guard let data = try? Data(contentsOf: url) else {
                session.present(.systemAlert(.openFailed(reason: url.lastPathComponent, suggestion: nil)))
                continue
            }
            session.importSave(data)
        }
    }
}

/// The launch sequence (UI-SHELL-013): parse, reset, create stores, create the session.
enum AppBootstrap {
    static func makeSession(options: LaunchOptions, defaults: UserDefaults, root: URL = AppPaths.applicationSupport) -> GameSession {
        if options.resetState {
            AppPaths.resetState(root: root, defaults: defaults, domain: Bundle.main.bundleIdentifier)
        }
        return GameSession(stores: SessionStores(root: root), launchOptions: options, defaults: defaults)
    }
}

/// `-PMScenario` fixtures (CHEAT-049). Returns an exit status when the scenario ends the process.
enum ScenarioRunner {
    static let smokeSeed: UInt64 = 20_261_117

    static func run(_ name: String, session: GameSession) -> Int32? {
        switch name {
        case "smoke": smoke(session: session) ? 0 : 1
        default: 2
        }
    }

    /// Creates a game, saves it to a slot, loads it back and checks the loaded state equals the saved one.
    static func smoke(session: GameSession) -> Bool {
        var state = GameState(config: NewGameConfig(commanderName: "Smoke", seed: smokeSeed))
        state.cheatsUsed = true
        let gameID = SlotStore.newSlotID()
        do {
            _ = try session.slotStore.save(state, slot: gameID, gameID: gameID)
            let loaded = try session.slotStore.load(slot: gameID)
            try? session.slotStore.delete(slot: gameID)
            return loaded.state == state
        } catch {
            return false
        }
    }
}
