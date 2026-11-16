// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// The main window's root: Welcome without a game, the playing shell otherwise (UI-SHELL-017, -034).
struct RootView: View {
    @Environment(GameSession.self) private var session

    var body: some View {
        let titles = WindowTitles.make(state: session.state)
        Group {
            switch session.mode {
            case .welcome:
                WelcomeView()
            case .playing, .gameOver:
                MainShellView()
            }
        }
        .frame(minWidth: SceneMetrics.mainMinimumSize.width, minHeight: SceneMetrics.mainMinimumSize.height)
        .navigationTitle(titles.title)
        .navigationSubtitle(titles.subtitle ?? "")
        .modifier(PresentationHost())
    }
}
