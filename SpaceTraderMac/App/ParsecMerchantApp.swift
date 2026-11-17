// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// Static information about the app and its linked engine.
enum AppInfo {
    static let engineVersion = ParsecEngineInfo.version
}

/// Scene sizes (UI-SHELL-014). Explicit sizes rather than content-fitting (research 05 §4).
enum SceneMetrics {
    static let mainDefaultSize = CGSize(width: 1320, height: 860)
    static let mainMinimumSize = CGSize(width: 1100, height: 720)
    static let mainWindowID = "main"
}

@main
struct ParsecMerchantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Parsec Merchant", id: SceneMetrics.mainWindowID) {
            RootView()
                .modifier(FileTransferHost())
                .modifier(AppTextSize())
                .environment(appDelegate.session)
        }
        .defaultSize(SceneMetrics.mainDefaultSize)
        .windowResizability(.contentMinSize)
        .commands {
            MenuCommands(session: appDelegate.session, helpRouter: appDelegate.helpRouter)
        }
        Window("Galaxy Chart", id: GalaxyWindowMetrics.id) {
            GalaxyChartWindowView()
                .modifier(AppTextSize())
                .environment(appDelegate.session)
        }
        .defaultSize(GalaxyWindowMetrics.defaultSize)
        .windowResizability(.contentMinSize)
        Window("High Scores", id: HighScoresWindowView.windowID) {
            HighScoresWindowView()
                .modifier(AppTextSize())
                .environment(appDelegate.session)
        }
        .defaultSize(HighScoresWindowView.defaultSize)
        Settings {
            SettingsView()
                .environment(appDelegate.session)
        }
        Window("About Parsec Merchant", id: AppWindowID.about) {
            AboutView()
        }
        .windowResizability(.contentSize)
        Window("Parsec Merchant Help", id: AppWindowID.help) {
            HelpView()
                .environment(appDelegate.helpRouter)
        }
        .defaultSize(width: 860, height: 600)
    }
}
