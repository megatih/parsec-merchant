// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// The interim game-over card (UI-SHELL-097; the cinematic card is M9).
struct GameOverCard: View {
    @Environment(GameSession.self) private var session

    var body: some View {
        VStack(spacing: 16) {
            if let state = session.state, let m = GameOverModel.make(state: state, recorded: session.recordedScore) {
                Text("Game Over").font(.largeTitle.bold())
                Text(Names.ending(m.end)).font(.title3)
                Text("You achieved a score of \(m.scoreText)%.").monospacedDigit()
                if let outcome = m.outcomeText {
                    Text(outcome).foregroundStyle(.secondary)
                }
                HStack {
                    Button("New Game…") { session.requestNewGame() }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier(AXID.GameOver.newGame)
                    Button("Main Menu") { session.requestCloseGame() }
                        .accessibilityIdentifier(AXID.GameOver.mainMenu)
                }
                .controlSize(.large)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.GameOver.card)
    }
}
