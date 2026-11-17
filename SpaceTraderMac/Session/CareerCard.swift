// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import ParsecInsights

/// STAT-021: the log-based totals of the career card (from `CareerStats`).
struct CareerStatTotals: Equatable, Sendable {
    var encountersWon: Int
    var encountersFled: Int
    var encountersSurrendered: Int
    var bestTrade: BestSale?
    var systemsVisited: Int
    var systemCount: Int
    var parsecsTravelled: Int
    var achievementsUnlocked: Int

    init(_ s: CareerStats) {
        encountersWon = s.won
        encountersFled = s.fled
        encountersSurrendered = s.surrendered
        bestTrade = s.bestSale
        systemsVisited = s.visitedCount
        systemCount = s.systemCount
        parsecsTravelled = s.parsecsTravelled
        achievementsUnlocked = s.achievementsUnlocked
    }
}

/// UI-ENC-083: the career summary of an ended game, built from the state only, so a reopened ended save shows the
/// same card. The log-based totals (STAT-021) are added when the session has the game's statistics.
struct CareerCard: Equatable, Sendable {
    var commanderName: String
    var shipType: ShipType
    var shipName: String?
    var ruleset: RulesetID
    var difficulty: Difficulty
    var galaxyCode: String
    var end: GameEndType
    var days: Int
    /// `GameState.worth` (RUL-119).
    var worth: Int
    /// The display tenths (SCORE-024/025) and their text (UI-ENC-081).
    var scoreTenths: Int
    var scoreText: String
    var policeRecord: PoliceRecordType
    var reputation: ReputationType
    var piratesKilled: Int
    var policeKilled: Int
    var tradersKilled: Int
    var cash: Int
    var debt: Int
    var ironman: Bool
    var reloaded: Bool
    var cheatsUsed: Bool
    /// The rank this game entered at, when the session recorded one (SCORE-036).
    var enteredRank: Int?
    /// STAT-021: nil when no statistics are available (kills stay state-derived either way).
    var stats: CareerStatTotals?

    var totalKills: Int { piratesKilled + policeKilled + tradersKilled }

    static func make(state: GameState, end: GameEndType, recorded: RecordedScore?, stats: CareerStats? = nil,
                     locale: Locale = .current) -> CareerCard {
        let c = state.commander
        let tenths = state.scoreTenths(for: end)
        let rank: Int? = if case let .outcome(.entered(r))? = recorded { r } else { nil }
        return CareerCard(commanderName: c.name, shipType: c.ship.type, shipName: c.shipName, ruleset: state.rulesetID,
                          difficulty: state.difficulty, galaxyCode: GalaxyCode(state).string, end: end, days: c.days,
                          worth: state.worth, scoreTenths: tenths,
                          scoreText: ScoreText.tenths(tenths, ruleset: state.ruleset, locale: locale),
                          policeRecord: state.policeRecord, reputation: state.reputation, piratesKilled: c.kills.pirates,
                          policeKilled: c.kills.police, tradersKilled: c.kills.traders, cash: c.cash, debt: c.debt,
                          ironman: state.ironman, reloaded: state.reloadCount > 0, cheatsUsed: state.cheatsUsed,
                          enteredRank: rank, stats: stats.map(CareerStatTotals.init))
    }
}

/// UI-ENC-082: the vignette placeholder per ending (the animations are M11).
enum GameOverVignette: String, CaseIterable, Sendable {
    case destroyed, retired, moon, moonGirl

    init(_ end: GameEndType) {
        switch end {
        case .killed: self = .destroyed
        case .retired: self = .retired
        case .boughtMoon: self = .moon
        case .boughtMoonGirl: self = .moonGirl
        }
    }

    /// The SF Symbol of the placeholder.
    var symbol: String {
        switch self {
        case .destroyed: "flame"
        case .retired: "sun.horizon"
        case .moon: "moon.stars"
        case .moonGirl: "moon.stars.fill"
        }
    }
}

/// UI-ENC-082: how a `killed` game ended, read from the step that ended it (nil for other endings or a reopened save).
enum GameOverCause: Equatable, Sendable {
    /// Destroyed in combat (`playerDestroyed` / `bothDestroyed`) by an opponent of this badge and ship type.
    case destroyedBy(badge: EncounterBadge, ship: ShipType)
    /// The reactor melted down with no escape pod (QST reactor, ALR-128).
    case reactorMeltdown

    static func make(step: StepRecord?) -> GameOverCause? {
        guard let step, case .gameOver(.killed) = step.after.phase else { return nil }
        let events = step.result.events
        if events.contains(where: { if case .reactorMeltdown = $0 { true } else { false } }) { return .reactorMeltdown }
        let destroyed = events.contains { if case .playerDestroyed = $0 { true } else if case .bothDestroyed = $0 { true } else { false } }
        guard destroyed, case let .encounter(enc) = step.before.phase,
              let preview = GameEngine(state: step.before).encounterPreview else { return nil }
        return .destroyedBy(badge: preview.badge, ship: enc.opponent.type)
    }
}

/// UI-ENC-082: everything the full-window game-over card shows, in the SCORE-015 order.
struct GameOverCardModel: Equatable, Sendable {
    var end: GameEndType
    var vignette: GameOverVignette
    var cause: GameOverCause?
    var scoreText: String
    /// UI-ENC-084 (nil before the session has recorded the game).
    var highScoreText: String?
    var career: CareerCard

    static func make(state: GameState, recorded: RecordedScore?, lastStep: StepRecord?, table: HighScoreTable?,
                     stats: CareerStats? = nil, locale: Locale = .current) -> GameOverCardModel? {
        guard case let .gameOver(end) = state.phase else { return nil }
        let career = CareerCard.make(state: state, end: end, recorded: recorded, stats: stats, locale: locale)
        return GameOverCardModel(end: end, vignette: GameOverVignette(end), cause: GameOverCause.make(step: lastStep),
                                 scoreText: career.scoreText,
                                 highScoreText: HighScoreOutcomeText.text(for: recorded, entry: state.highScoreEntry(for: end),
                                                                          table: table),
                                 career: career)
    }
}
