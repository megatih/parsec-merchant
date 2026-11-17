// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecArt
import ParsecEngine
import ParsecPersistence
import SwiftUI

/// UI-ENC-082: the full-window game-over card (SCORE-015 order): vignette, ending and cause, score, high-score outcome,
/// career card and actions.
struct GameOverView: View {
    @Environment(GameSession.self) private var session
    @Environment(\.openWindow) private var openWindow
    /// The game's ruleset table, read when the card appears and after each recording (for "already recorded" ranks).
    @State private var table: HighScoreTable?

    var body: some View {
        ScrollView {
            if let state = session.state,
               let model = GameOverCardModel.make(state: state, recorded: session.recordedScore, lastStep: session.lastStep,
                                                  table: table, stats: session.careerStats) {
                content(model)
                    .frame(maxWidth: .infinity)
                    .padding(32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.GameOver.card)
        .onAppear(perform: loadTable)
        .onChange(of: session.highScoresRevision) { loadTable() }
    }

    private func content(_ m: GameOverCardModel) -> some View {
        VStack(spacing: 18) {
            GameOverArt(end: m.end, ship: session.state?.commander.ship.type ?? .gnat)
                .frame(width: 280, height: 150)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(Names.ending(m.end)))
                .accessibilityIdentifier(AXID.GameOver.vignette)
            Text(Names.ending(m.end))
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            if let cause = m.cause {
                Text(verbatim: CareerText.cause(cause))
                    .foregroundStyle(.secondary)
            }
            Text(verbatim: CareerText.score(m.scoreText))
                .font(.title3)
                .monospacedDigit()
                .accessibilityIdentifier(AXID.GameOver.score)
            if let outcome = m.highScoreText {
                Text(verbatim: outcome)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(AXID.GameOver.highScore)
            }
            CareerCardView(card: m.career)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(AXID.GameOver.career)
            actions(m)
            // LOG-035: the Logbook of the ended game.
            Button("Show Logbook") { session.showLogbook(tab: .log) }
                .buttonStyle(.link)
                .accessibilityIdentifier(AXID.LogbookLinks.gameOverShowLogbook)
        }
        .frame(maxWidth: 560)
    }

    private func actions(_ m: GameOverCardModel) -> some View {
        HStack(spacing: 12) {
            Button("Main Menu") { session.requestCloseGame() }
                .accessibilityIdentifier(AXID.GameOver.mainMenu)
            Button("High Scores") {
                // The window opens at this game's ruleset (UI-ENC-087) and highlights the new rank (UI-ENC-089).
                session.highScoresRevision += 1
                openWindow(id: HighScoresWindowView.windowID)
            }
            .accessibilityIdentifier(AXID.GameOver.highScores)
            ShareLink(item: CareerCardImage(card: m.career),
                      preview: SharePreview(CareerText.shareTitle(commander: m.career.commanderName),
                                            image: Image(systemName: m.vignette.symbol)))
                .accessibilityIdentifier(AXID.GameOver.share)
            Button("New Game…") { session.requestNewGame() }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier(AXID.GameOver.newGame)
        }
        .controlSize(.large)
    }

    private func loadTable() {
        guard let ruleset = session.state?.rulesetID else { return }
        table = try? session.highScoreStore.table(for: ruleset)
    }
}
