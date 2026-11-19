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
    /// UI-DS-001: 1200 × 680 fits a 10-row cargo table beside the chart, and the smallest supported Mac display.
    static let mainDefaultSize = CGSize(width: 1440, height: 860)
    static let mainMinimumSize = PMScale.designSize
    static let mainWindowID = "main"

    /// The content size a launch argument asks for, never below the minimum of the Text Size in effect (UI-DS-004):
    /// a window set smaller by code would clip the game area.
    @MainActor
    static func launchSize(_ options: LaunchOptions) -> CGSize? {
        let minimum = GameShellView.minimumSize(UserDefaults.standard.string(forKey: AppSettingsKey.textSize) ?? TextSizeSetting.standard.rawValue)
        let wanted: CGSize
        if let points = options.windowPoints {
            wanted = points
        } else if let size = options.windowSize {
            wanted = size == .minimum ? minimum : mainDefaultSize
        } else {
            return nil
        }
        return CGSize(width: max(wanted.width, minimum.width), height: max(wanted.height, minimum.height))
    }
}

/// Window sizes are measured below the title bar (`contentLayoutRect`): the game area's 1200 × 680 excludes it.
@MainActor
enum WindowSizing {
    /// Resizes `window` so that its layout area is `size`, keeping its top-left corner.
    static func setLayoutSize(_ size: CGSize, of window: NSWindow) {
        let layout = window.contentLayoutRect.size
        var frame = window.frame
        let dw = size.width - layout.width, dh = size.height - layout.height
        frame.size.width += dw
        frame.size.height += dh
        frame.origin.y -= dh
        window.setFrame(frame, display: true)
    }

    /// UI-DS-004: grows `window` to `minimum` if its layout area is smaller (the Text Size was raised, or the game area
    /// replaced the Welcome screen).
    static func enforce(minimum: CGSize, on window: NSWindow) {
        let layout = window.contentLayoutRect.size
        guard layout.width < minimum.width - 0.5 || layout.height < minimum.height - 0.5 else { return }
        setLayoutSize(CGSize(width: max(layout.width, minimum.width), height: max(layout.height, minimum.height)), of: window)
    }
}

/// UI-DS-004: keeps the hosting window at least as large as the minimum of the Text Size in effect.
struct WindowMinimumEnforcer: NSViewRepresentable {
    let minimum: CGSize

    final class EnforcerView: NSView {
        var minimum = CGSize.zero
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        func apply() {
            let minimum = minimum
            DispatchQueue.main.async { [weak self] in
                guard let window = self?.window, !window.styleMask.contains(.fullScreen) else { return }
                WindowSizing.enforce(minimum: minimum, on: window)
            }
        }
    }

    func makeNSView(context: Context) -> EnforcerView {
        let view = EnforcerView()
        view.minimum = minimum
        return view
    }

    func updateNSView(_ view: EnforcerView, context: Context) {
        guard view.minimum != minimum else { return }
        view.minimum = minimum
        view.apply()
    }
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
                WindowSizing.setLayoutSize(size, of: window)
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
                    if let size = SceneMetrics.launchSize(appDelegate.launchOptions) { LaunchWindowSizer(size: size) }
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
