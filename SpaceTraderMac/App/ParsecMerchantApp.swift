// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
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

/// `-PMWindowSize min|default` (A11Y-002): sets the hosting window to the main window's minimum or default size and centres
/// it, ignoring the restored frame.
struct LaunchWindowSizer: NSViewRepresentable {
    let size: CGSize

    final class SizerView: NSView {
        var size = CGSize.zero
        /// Applied once per process: later moves (Welcome ↔ playing shell) keep the user's frame.
        static var applied = false
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !Self.applied else { return }
            Self.applied = true
            let size = size
            DispatchQueue.main.async {
                window.setContentSize(size)
                window.center()
            }
        }
    }

    func makeNSView(context: Context) -> SizerView {
        let view = SizerView()
        view.size = size
        return view
    }

    func updateNSView(_ nsView: SizerView, context: Context) {}
}

@main
struct ParsecMerchantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Parsec Merchant", id: SceneMetrics.mainWindowID) {
            RootView()
                .modifier(FileTransferHost())
                .modifier(SceneAccessibility())
                .background {
                    if let size = appDelegate.launchOptions.windowSize {
                        LaunchWindowSizer(size: size == .minimum ? SceneMetrics.mainMinimumSize : SceneMetrics.mainDefaultSize)
                    }
                }
                .environment(appDelegate.session)
                .environment(appDelegate.helpRouter)
        }
        .defaultSize(SceneMetrics.mainDefaultSize)
        .windowResizability(.contentMinSize)
        .commands {
            MenuCommands(session: appDelegate.session, helpRouter: appDelegate.helpRouter)
        }
        Window("Galaxy Chart", id: GalaxyWindowMetrics.id) {
            GalaxyChartWindowView()
                .modifier(SceneAccessibility())
                .environment(appDelegate.session)
        }
        .defaultSize(GalaxyWindowMetrics.defaultSize)
        .windowResizability(.contentMinSize)
        .commandsRemoved()  // MENU-038: Window › Galaxy Chart comes from MenuCatalog (no duplicate auto item)
        Window("High Scores", id: HighScoresWindowView.windowID) {
            HighScoresWindowView()
                .modifier(SceneAccessibility())
                .environment(appDelegate.session)
        }
        .defaultSize(HighScoresWindowView.defaultSize)
        .commandsRemoved()  // Window › High Scores comes from MenuCatalog (no duplicate auto item)
        Settings {
            SettingsView()
                .environment(appDelegate.session)
        }
        Window("About Parsec Merchant", id: AppWindowID.about) {
            AboutView()
                .modifier(SceneAccessibility())
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)  // an About panel shows its name in the content, like the system's
        .commandsRemoved()  // the About item comes from MenuCommands
        Window("Parsec Merchant Help", id: AppWindowID.help) {
            HelpView()
                .modifier(SceneAccessibility())
                .environment(appDelegate.helpRouter)
        }
        .defaultSize(width: 860, height: 600)
        .commandsRemoved()  // the Help items come from MenuCommands
    }
}
