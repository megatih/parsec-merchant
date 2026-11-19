// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// The main window's root: Welcome without a game, the playing shell otherwise (UI-SHELL-017, -034).
struct RootView: View {
    @Environment(GameSession.self) private var session
    @AppStorage(AppSettingsKey.textSize) private var textSize = TextSizeSetting.standard.rawValue

    var body: some View {
        let titles = WindowTitles.make(state: session.state, page: session.selectedSection)
        // UI-DS-004: the window's minimum follows the Text Size, on the Welcome screen too.
        let minimum = GameShellView.minimumSize(textSize)
        Group {
            switch session.mode {
            case .welcome:
                WelcomeView()
            case .playing, .gameOver:
                GameShellView()
            }
        }
        .frame(minWidth: minimum.width, minHeight: minimum.height)
        .background(WindowMinimumEnforcer(minimum: minimum))
        .navigationTitle(titles.title)
        .navigationSubtitle(titles.subtitle ?? "")
        .modifier(PresentationHost())
    }
}
