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
                    .padding(PMSpace.xl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.GameOver.card)
        .onAppear(perform: loadTable)
        .onChange(of: session.highScoresRevision) { loadTable() }
    }

    private func content(_ m: GameOverCardModel) -> some View {
        VStack(spacing: PMSpace.l) {
            // D8: a cinematic 16:9 scene as wide as the card.
            GameOverArt(end: m.end, ship: session.state?.commander.ship.type ?? .gnat, shipInput: session.state.map { ArtAdapters.playerShipInput($0) })
                .aspectRatio(ShipPanelSize.endingAspect, contentMode: .fit)
                .frame(maxWidth: 640)
                .clipShape(RoundedRectangle(cornerRadius: PMRadius.panel))
                .accessibilityElement(children: .ignore)
                // ART-END-001: the scene in words.
                .accessibilityLabel(Text(EndingText.scene(m.end)))
                .accessibilityAddTraits(.isImage)
                .accessibilityIdentifier(AXID.GameOver.vignette)
            Text(Names.ending(m.end))
                .pmFont(.title)
                .multilineTextAlignment(.center)
            if let cause = m.cause {
                Text(verbatim: CareerText.cause(cause))
                    .foregroundStyle(PMColor.textSecondary)
            }
            Text(verbatim: CareerText.score(m.scoreText))
                .pmFont(.title)
                .monospacedDigit()
                .accessibilityIdentifier(AXID.GameOver.score)
            if let outcome = m.highScoreText {
                Text(verbatim: outcome)
                    .foregroundStyle(PMColor.textSecondary)
                    .accessibilityIdentifier(AXID.GameOver.highScore)
            }
            CareerCardView(card: m.career)
                .background(PMColor.panel, in: RoundedRectangle(cornerRadius: PMRadius.panel))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(AXID.GameOver.career)
            actions(m)
            // LOG-035: the Logbook of the ended game.
            Button("Show Logbook") { session.showLogbook(tab: .log) }
                .buttonStyle(PMButtonStyle(kind: .quiet))
                .accessibilityIdentifier(AXID.LogbookLinks.gameOverShowLogbook)
        }
        .frame(maxWidth: 560)
        .foregroundStyle(PMColor.textPrimary)
    }

    private func actions(_ m: GameOverCardModel) -> some View {
        HStack(spacing: PMSpace.m) {
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
                .buttonStyle(PMButtonStyle(kind: .primary))
                .accessibilityIdentifier(AXID.GameOver.newGame)
        }
        // UI-PG-070: the console's buttons.
        .buttonStyle(PMButtonStyle())
    }

    private func loadTable() {
        guard let ruleset = session.state?.rulesetID else { return }
        table = try? session.highScoreStore.table(for: ruleset)
    }
}

/// ART-END-001: what each ending scene shows, for VoiceOver.
enum EndingText {
    static func scene(_ end: GameEndType) -> LocalizedStringResource {
        switch end {
        case .killed: "Your ship drifts in pieces among cooling debris."
        case .retired: "Your ship comes to rest in low orbit as the sun sets behind the planet."
        case .boughtMoon: "Your ship stands on the landing pad of your own moon base, the planet large in the black sky."
        case .boughtMoonGirl: "Two ships stand on the landing pads of your moon base, two windows lit, the planet large in the black sky."
        }
    }
}
