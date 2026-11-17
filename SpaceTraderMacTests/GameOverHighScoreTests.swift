// SPDX-License-Identifier: GPL-2.0-or-later
import CoreGraphics
import Foundation
import ParsecEngine
import ParsecPersistence
import Testing
@testable import ParsecMerchant

/// UI-ENC §12–13: the score formatter, the game-over card, the career card, the high-score outcome and the High Scores
/// window's rows.
@MainActor
@Suite("Game over and high scores (UI-ENC §12–13)")
struct GameOverHighScoreTests {
    private let enUS = Locale(identifier: "en_US")

    private func state(_ ruleset: RulesetID = .modern, seed: UInt64 = 7) -> GameState {
        GameState(config: NewGameConfig(commanderName: "Career", difficulty: .hard, ruleset: ruleset, seed: seed))
    }

    // MARK: UI-ENC-081

    @Test("UI-ENC-081 SCORE-024 SCORE-027 one formatter: grouped integer part, both parts carry the C# sign")
    func scoreTextCSharp() {
        let m = Ruleset.modern
        let golden: [(Int, String)] = [(11, "1.1%"), (12, "1.2%"), (190, "19.0%"), (1_824, "182.4%"), (1_079, "107.9%"),
                                       (1_080, "108.0%"), (900, "90.0%"), (672, "67.2%"), (320, "32.0%"), (3_000, "300.0%"),
                                       (-5, "0.-5%"), (-5_969, "-596.-9%"), (11_210, "1,121.0%"), (0, "0.0%")]
        for (t, text) in golden {
            #expect(ScoreText.tenths(t, ruleset: m, locale: enUS) == text, "\(t)")
            #expect(ScoreText.tenths(t, ruleset: .windows201, locale: enUS) == text, "\(t)")
        }
        // Retire sheet and game-over card use the same formatter (the old abs() formatters printed "-596.9").
        var st = state()
        st.phase = .gameOver(.retired)
        let card = CareerCard.make(state: st, end: .retired, recorded: nil)
        #expect(card.scoreText == ScoreText.tenths(st.scoreTenths(for: .retired), ruleset: st.ruleset))
        let retire = ConfirmationText.content(for: Confirmation(.retire, amounts: [-5_969]), state: state())
        #expect(retire.message.contains(ScoreText.tenths(-5_969, ruleset: .modern)))
    }

    @Test("UI-ENC-081 SCORE-025 SCORE-028 Palm: tenths = score / 5, integer part ungrouped")
    func scoreTextPalm() {
        let p = Ruleset.palm122
        let golden: [(Int, Int, String)] = [(57, 11, "1.1%"), (60, 12, "1.2%"), (4_500, 900, "90.0%"), (33, 6, "0.6%"),
                                            (56_050, 11_210, "1121.0%")]
        for (score, tenths, text) in golden {
            #expect(ScoreText.displayTenths(score: score, ruleset: p) == tenths)
            #expect(ScoreText.score(score, ruleset: p, locale: enUS) == text)
        }
        #expect(ScoreText.displayTenths(score: 57, ruleset: .modern) == 57)
        let retire = ConfirmationText.content(for: Confirmation(.retire, amounts: [56_050]), state: state(.palm122))
        #expect(retire.message.contains("1121.0%"))
    }

    // MARK: UI-ENC-082, -083

    @Test("UI-ENC-083 the career card per ending and ruleset, from the state only")
    func careerCard() {
        for ruleset in RulesetID.allCases {
            for end in GameEndType.allCases {
                var st = state(ruleset)
                st.phase = .gameOver(end)
                st.commander.kills.pirates = 3
                st.commander.kills.police = 1
                st.commander.kills.traders = 2
                st.commander.cash = 12_345
                st.commander.debt = 678
                st.commander.shipName = "Rocinante"
                st.ironman = true
                st.reloadCount = 1
                st.cheatsUsed = true
                let card = CareerCard.make(state: st, end: end, recorded: .outcome(.entered(rank: 2)), locale: enUS)
                #expect(card.commanderName == "Career" && card.shipType == st.commander.ship.type && card.shipName == "Rocinante")
                #expect(card.ruleset == ruleset && card.difficulty == .hard && card.galaxyCode == GalaxyCode(st).string)
                #expect(card.end == end && card.days == st.commander.days && card.worth == st.worth)
                #expect(card.scoreTenths == st.scoreTenths(for: end))
                #expect(card.scoreText == ScoreText.tenths(st.scoreTenths(for: end), ruleset: st.ruleset, locale: enUS))
                #expect(card.policeRecord == st.policeRecord && card.reputation == st.reputation)
                #expect(card.piratesKilled == 3 && card.policeKilled == 1 && card.tradersKilled == 2 && card.totalKills == 6)
                #expect(card.cash == 12_345 && card.debt == 678 && card.enteredRank == 2)
                #expect(CareerText.badges(card) == ["Ironman", "↺ reloaded", "Cheats used"])
                // A reopened ended save (same state) shows the same card.
                #expect(CareerCard.make(state: st, end: end, recorded: .outcome(.entered(rank: 2)), locale: enUS) == card)
            }
        }
        var plain = state()
        plain.phase = .gameOver(.retired)
        #expect(CareerText.badges(CareerCard.make(state: plain, end: .retired, recorded: nil)).isEmpty)
        #expect(CareerCard.make(state: plain, end: .retired, recorded: .alreadyRecorded).enteredRank == nil)
    }

    @Test("UI-ENC-082 SCORE-015 the game-over card: vignette per ending, ending, cause, score, outcome, career, actions")
    func gameOverCard() throws {
        for end in GameEndType.allCases {
            var st = state()
            st.phase = .gameOver(end)
            let m = try #require(GameOverCardModel.make(state: st, recorded: .outcome(.missed), lastStep: nil, table: nil))
            #expect(m.end == end && m.vignette == GameOverVignette(end) && m.cause == nil)
            #expect(m.scoreText == m.career.scoreText)
            #expect(m.highScoreText == "Your score didn't make the high-score table.")
            #expect(CareerText.score(m.scoreText) == "You achieved a score of \(m.scoreText).")
        }
        #expect(GameEndType.allCases.map(GameOverVignette.init) == [.destroyed, .retired, .moon, .moonGirl])
        #expect(Set(GameOverVignette.allCases.map(\.symbol)).count == 4)

        // The cause line of a combat death comes from the step that ended the game.
        var engine = PirateAmbushScenario.make()
        engine.perform(.warp)
        let before = engine.state
        guard case let .encounter(enc) = before.phase else {
            Issue.record("the ambush warp ends in an encounter")
            return
        }
        var after = before
        after.phase = .gameOver(.killed)
        let step = StepRecord(command: .encounter(.attack), acknowledged: [], before: before,
                              result: StepResult(events: [.playerDestroyed, .gameEnded(.killed, score: 1)]), after: after)
        let cause = try #require(GameOverCause.make(step: step))
        #expect(cause == .destroyedBy(badge: .pirate, ship: enc.opponent.type))
        #expect(CareerText.cause(cause) == "Your ship was destroyed by the pirate \(String(localized: Names.ship(enc.opponent.type))).")
        let model = GameOverCardModel.make(state: after, recorded: nil, lastStep: step, table: nil)
        #expect(model?.cause == cause && model?.highScoreText == nil)
        let meltdown = StepRecord(command: .warp, acknowledged: [], before: before,
                                  result: StepResult(events: [.reactorMeltdown, .gameEnded(.killed, score: 1)]), after: after)
        #expect(GameOverCause.make(step: meltdown) == .reactorMeltdown)
        #expect(!CareerText.cause(.reactorMeltdown).isEmpty)

        // Every card identifier is in the catalog and matches the scheme.
        let regex = try Regex(AXID.pattern)
        for id in AXID.gameOverArea {
            #expect(id.wholeMatch(of: regex) != nil, "\(id)")
            #expect(AXID.all.contains(id))
        }
        #expect(Set(AXID.all).count == AXID.all.count)
        #expect(AXID.GameOver.all == ["gameOver.card", "gameOver.vignette", "gameOver.score", "gameOver.highScore",
                                      "gameOver.career", "gameOver.newGame", "gameOver.mainMenu", "gameOver.highScores",
                                      "gameOver.share"])
    }

    // MARK: UI-ENC-084

    @Test("UI-ENC-084 ALR-098 ALR-099 ALR-100 SCORE-035 SCORE-037 the high-score outcome text with Ironman and ↺")
    func outcomeText() {
        var entry = state().highScoreEntry(for: .retired)
        #expect(HighScoreOutcomeText.text(for: nil, entry: entry) == nil)
        #expect(HighScoreOutcomeText.text(for: .outcome(.entered(rank: 4)), entry: entry) == "You entered the high-score table at rank 4.")
        #expect(HighScoreOutcomeText.text(for: .outcome(.missed), entry: entry) == "Your score didn't make the high-score table.")
        #expect(HighScoreOutcomeText.text(for: .outcome(.excludedForCheats), entry: entry)?.contains("Cheats") == true)
        #expect(HighScoreOutcomeText.text(for: .outcome(.excludedForReload), entry: entry)?.contains("reloaded") == true)
        #expect(HighScoreOutcomeText.text(for: .failed, entry: entry) == "The high-score table couldn't be updated.")
        #expect(HighScoreOutcomeText.text(for: .alreadyRecorded, entry: entry) == "This game's score was already recorded.")
        let other = HighScoreEntry(name: "Other", endType: .killed, score: 999_999, days: 1, worth: 1, difficulty: .normal,
                                   rulesetID: .modern)
        let table = HighScoreTable(entries: [other, entry])
        #expect(HighScoreOutcomeText.text(for: .alreadyRecorded, entry: entry, table: table)
            == "This game's score was already recorded, at rank 2.")
        entry.ironman = true
        entry.reloaded = true
        #expect(HighScoreOutcomeText.text(for: .outcome(.entered(rank: 1)), entry: entry)
            == "You entered the high-score table at rank 1. Ironman ↺ reloaded")
    }

    // MARK: UI-ENC-085

    @Test("UI-ENC-085 the shared PNG of the career card is non-empty and deterministic; preview title")
    func shareImage() throws {
        var st = state()
        st.phase = .gameOver(.boughtMoon)
        let card = CareerCard.make(state: st, end: .boughtMoon, recorded: nil, locale: enUS)
        // The process's first render can differ in a few bytes while glyph fallbacks load; every later one is identical.
        _ = CareerCardRenderer.png(card: card)
        let a = try #require(CareerCardRenderer.png(card: card))
        let b = try #require(CareerCardRenderer.png(card: card))
        #expect(a.count > 1_000)
        #expect(a.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        #expect(a == b)
        let image = try #require(CareerCardRenderer.image(card: card))
        #expect(image.width == 880, "the 440-point card at scale 2")
        #expect(CareerText.shareTitle(commander: card.commanderName) == "Parsec Merchant — Career")
    }

    // MARK: UI-ENC-086

    @Test("UI-ENC-086 SCORE-037 a combat death goes straight to the game-over card without a playback, recorded once")
    func combatDeath() throws {
        let s = try TestSessions.make(seed: nil, fastTravel: false)
        s.playbackClock = nil
        s.install(PirateAmbushScenario.make(), gameID: "death", slotID: nil)
        s.send(.warp)
        if s.transitPlayback != nil { s.finishPlayback() }
        try TestSessions.edit(s) { st in
            st.commander.ship.hull = 1
            st.commander.ship.escapePod = false
            st.commander.ship.shields = []
        }
        var attacks = 0
        while case .encounter = s.state?.phase, attacks < 40 {
            s.send(.encounter(.attack))
            TestSessions.resolvePresentation(s)
            attacks += 1
        }
        let st = try #require(s.state)
        guard case .gameOver(.killed) = st.phase else {
            Issue.record("the one-hull ship is destroyed, got \(st.phase)")
            return
        }
        #expect(s.transitPlayback == nil)
        #expect(DetailMode.derive(state: st, playback: s.transitPlayback, selected: .bridge) == .gameOver(.killed))
        #expect(s.recordedScore != nil)
        if case .destroyedBy(.pirate, _)? = GameOverCause.make(step: s.lastStep) {} else {
            Issue.record("cause from the last step: \(String(describing: GameOverCause.make(step: s.lastStep)))")
        }
        // Recorded once: offering the game again changes nothing.
        #expect(try s.highScoreStore.record(st, end: .killed, gameID: "death") == nil)
    }

    // MARK: UI-ENC-087…089

    @Test("UI-ENC-088 SCORE-039 ten rows per table: rank, name, score and the line with plural variants; Empty ranks")
    func rows() {
        let empty = HighScoreRowModel.rows(table: HighScoreTable(), ruleset: .modern, locale: enUS)
        #expect(empty.count == HighScoreTable.capacity && empty.map(\.rank) == Array(1...10) && empty.allSatisfy { $0.entry == nil })
        let one = HighScoreEntry(name: "Solo", endType: .retired, score: 12, days: 1, worth: 1, difficulty: .normal,
                                 rulesetID: .modern, ironman: true)
        let many = HighScoreEntry(name: "Many", endType: .killed, score: 11, days: 12, worth: 11_000, difficulty: .hard,
                                  rulesetID: .modern, reloaded: true)
        let negative = HighScoreEntry(name: "Wrap", endType: .boughtMoon, score: -5_969, days: 300, worth: 50_000_000,
                                      difficulty: .impossible, rulesetID: .modern)
        let rows = HighScoreRowModel.rows(table: HighScoreTable(entries: [one, many, negative]), ruleset: .modern, locale: enUS)
        #expect(rows.count == 10 && rows[3...].allSatisfy { $0.entry == nil })
        #expect(rows[0].entry == HighScoreRow.Filled(name: "Solo", scoreText: "1.2%",
                                                    line: "Retired in 1 day, worth 1 credit on normal level.",
                                                    ironman: true, reloaded: false))
        #expect(rows[1].entry?.line == "Was killed in 12 days, worth 11,000 credits on hard level.")
        #expect(rows[1].entry?.reloaded == true && rows[1].entry?.scoreText == "1.1%")
        #expect(rows[2].entry?.scoreText == "-596.-9%")
        #expect(rows[2].entry?.line == "Claimed moon in 300 days, worth 50,000,000 credits on impossible level.")
        let palm = HighScoreEntry(name: "Palm", endType: .retired, score: 56_050, days: 2, worth: 50_000_000,
                                  difficulty: .impossible, rulesetID: .palm122)
        #expect(HighScoreRowModel.rows(table: HighScoreTable(entries: [palm]), ruleset: .palm122, locale: enUS)[0].entry?.scoreText
            == "1121.0%")
        #expect(HighScoreRowModel.ending(.boughtMoonGirl) != HighScoreRowModel.ending(.boughtMoon))
    }

    @Test("UI-ENC-087 the scores window: id, size, menu item, ruleset segments; defaults to the game's ruleset, else the last viewed")
    func scoresWindow() throws {
        #expect(HighScoresWindowView.windowID == "scores")
        #expect(HighScoresWindowView.defaultSize == CGSize(width: 560, height: 520))
        let menu = MenuCatalog.entry(for: .highScores)
        #expect(menu.identifier == "menu.window.highScores" && menu.milestone == 9)
        #expect(HighScoresSelection.defaultsKey == "scores.ruleset")
        #expect(HighScoresSelection.initial(gameRuleset: .palm122, stored: "windows201") == .palm122)
        #expect(HighScoresSelection.initial(gameRuleset: nil, stored: "windows201") == .windows201)
        #expect(HighScoresSelection.initial(gameRuleset: nil, stored: nil) == .modern)
        #expect(HighScoresSelection.initial(gameRuleset: nil, stored: "bogus") == .modern)
        #expect(AXID.Scores.window == "scores.window")
        #expect(RulesetID.allCases.map(AXID.Scores.ruleset)
            == ["scores.ruleset.modern", "scores.ruleset.windows201", "scores.ruleset.palm122"])
    }

    @Test("UI-ENC-089 rows carry identifiers; the new rank is highlighted; the window reloads after recording and clearing")
    func scoresHighlightAndReload() throws {
        #expect(AXID.Scores.row(3) == "scores.row.3" && AXID.Scores.rowIronman(3) == "scores.row.3.ironman")
        #expect((1...10).allSatisfy { AXID.all.contains(AXID.Scores.row($0)) && AXID.all.contains(AXID.Scores.rowIronman($0)) })
        #expect(HighScoreRowModel.highlightedRank(recorded: .outcome(.entered(rank: 2)), gameRuleset: .modern, shown: .modern) == 2)
        #expect(HighScoreRowModel.highlightedRank(recorded: .outcome(.entered(rank: 2)), gameRuleset: .modern, shown: .palm122) == nil)
        #expect(HighScoreRowModel.highlightedRank(recorded: .alreadyRecorded, gameRuleset: .modern, shown: .modern) == nil)
        #expect(HighScoreRowModel.highlightedRank(recorded: nil, gameRuleset: nil, shown: .modern) == nil)

        let s = try TestSessions.playing()
        let start = s.highScoresRevision
        s.send(.retire)
        guard case let .sheet(.retire(p)) = s.presentation else {
            Issue.record("retire asks first")
            return
        }
        s.confirm(p)
        #expect(s.highScoresRevision > start)
        let table = try s.highScoreStore.table(for: .modern)
        let rows = HighScoreRowModel.rows(table: table, ruleset: .modern)
        #expect(rows[0].entry?.name == s.state?.commander.name)
        #expect(HighScoreRowModel.highlightedRank(recorded: s.recordedScore, gameRuleset: s.state?.rulesetID, shown: .modern) == 1)
        let afterRecord = s.highScoresRevision
        s.clearHighScores(.modern)
        #expect(s.highScoresRevision > afterRecord)
        #expect(try s.highScoreStore.table(for: .modern).entries.isEmpty)
    }
}
