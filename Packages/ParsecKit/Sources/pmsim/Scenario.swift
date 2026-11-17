// SPDX-License-Identifier: GPL-2.0-or-later
// pmsim scenario (PRD §10): one complete game per ending (moon, death, retirement) under each ruleset, played only
// through `GameEngine.perform` by players built on the greedy trader (no cheats, no setters, no debug commands).
// Each game must end with its ending (SCORE-001) and keep the fuzzer's invariants on every step.
import Foundation
import ParsecEngine
import ParsecInsights

/// The ending a scenario game plays for.
enum ScenarioEnding: String, CaseIterable, Sendable {
    case moon, death, retirement

    /// The end types that count as reaching this ending (the Modern moon-girl variant counts as the moon, SCORE-008).
    var accepted: Set<GameEndType> {
        switch self {
        case .moon: [.boughtMoon, .boughtMoonGirl]
        case .death: [.killed]
        case .retirement: [.retired]
        }
    }
}

struct ScenarioOutcome: Sendable {
    var ruleset: RulesetID
    var ending: ScenarioEnding
    var seed: UInt64
    var end: GameEndType?
    var day: Int
    var score: Int
    var commands: Int
    var violations: [String]

    var passed: Bool { end.map(ending.accepted.contains) ?? false && violations.isEmpty }

    var line: String {
        let ended = end.map { "ended .\($0)" } ?? "did not end"
        let extra = violations.isEmpty ? "" : ", \(violations.count) violations (first: \(violations[0]))"
        return "scenario \(ruleset.rawValue) \(ending.rawValue): \(ended) on day \(day), score \(score), "
            + "commands \(commands), seed \(seed)\(extra)"
    }
}

enum Scenario {
    /// The default seed: fixed, and found by search to reach all nine endings (seed 1 strands Palm's moon trader).
    static let defaultSeed: UInt64 = 2
    /// Day after which the retirement player retires.
    static let retirementDay = 40
    /// Cash kept beyond the moon's price for the trip to the moon and on to Utopia.
    static let moonTravelReserve = 20_000
    static let maxCommands = 400_000
    static let maxDays = 4_000

    /// Plays one scenario game and reports how it ended.
    static func play(_ ruleset: RulesetID, _ ending: ScenarioEnding, seed: UInt64) -> ScenarioOutcome {
        var fuzzer = Fuzzer(ruleset: ruleset)
        let bot = TraderBot(ruleset: ruleset, seed: seed) { s in
            let before = fuzzer.violations.count
            fuzzer.check(s, game: 0, step: 0, command: .warp, cashBefore: s.commander.cash)
            return fuzzer.violations.count > before ? fuzzer.violations.last : nil
        }
        var player: (TraderBot) -> Bool
        switch ending {
        case .moon: player = moonStep
        case .death:
            bot.buysProtection = false
            bot.repairs = false
            player = deathStep
        case .retirement: player = retirementStep
        }
        while bot.commands < maxCommands, bot.state.commander.days < maxDays {
            if case .gameOver = bot.state.phase { break }
            if !player(bot) { break }
        }
        var end: GameEndType?
        if case .gameOver(let e) = bot.state.phase { end = e }
        return ScenarioOutcome(ruleset: ruleset, ending: ending, seed: seed, end: end, day: bot.state.commander.days,
                               score: end.map { bot.state.score(for: $0) } ?? 0, commands: bot.commands,
                               violations: bot.violations)
    }

    // MARK: Moon

    /// Trades until the moon is affordable, buys it where it is offered, then flies to Utopia and claims it.
    static func moonStep(_ bot: TraderBot) -> Bool {
        guard case .docked = bot.state.phase else { return bot.step() }
        let s = bot.state
        if s.quests.moon >= QuestStatus.Moon.bought {
            return claimOrTravel(bot, to: SystemID.utopia, event: .moonRetirement)
        }
        bot.resolvePending()
        bot.sellCargo()
        bot.repayDebt()
        guard bot.state.cashToSpend >= QuestStatus.moonCost + moonTravelReserve,
              let moonSystem = bot.state.galaxy.systems.firstIndex(where: { $0.specialEvent == .moon }) else {
            return bot.step()
        }
        return claimOrTravel(bot, to: moonSystem, event: .moon)
    }

    /// At `goal`, accepts its special event; elsewhere flies the first hop of the fewest-jumps route to it. Falls back
    /// to a greedy trading turn when there is no route yet (the ship's range may grow) or no hop is accepted.
    static func claimOrTravel(_ bot: TraderBot, to goal: Int, event: SpecialEventType) -> Bool {
        bot.resolvePending()
        if bot.state.commander.currentSystem == goal, bot.state.specialEventAvailable == event {
            if bot.send(.specialEvent) { return true }
        }
        bot.sellCargo()
        bot.refuelAndRepair()
        bot.repayDebt()
        if travel(bot, toward: goal) { return true }
        return bot.step()
    }

    /// Warps along the planned route's first hop (through a wormhole when the route says so).
    static func travel(_ bot: TraderBot, toward goal: Int) -> Bool {
        let here = bot.state.commander.currentSystem
        guard here != goal, let hop = RoutePlanner.plan(from: here, to: goal, in: RouteSnapshot(bot.state))?.hops.first
        else { return false }
        let selected = hop.viaWormhole ? bot.send(.selectWormhole(here)) : bot.send(.selectTarget(hop.to))
        guard selected, bot.send(.warp) else { return false }
        bot.previousSystem = here
        return true
    }

    // MARK: Death

    /// Trades without an escape pod, insurance or repairs, and attacks every ship it meets until it is destroyed.
    static func deathStep(_ bot: TraderBot) -> Bool {
        guard case .encounter(let enc) = bot.state.phase else { return bot.step() }
        bot.resolvePending()
        let actions = enc.type.actions
        if actions.contains(.attack), bot.send(.encounter(.attack)) {
            bot.resolvePending()
            return true
        }
        bot.encounterTurn()
        return true
    }

    // MARK: Retirement

    /// Trades greedily for `retirementDay` days, then retires when docked.
    static func retirementStep(_ bot: TraderBot) -> Bool {
        if bot.state.commander.days >= retirementDay, case .docked = bot.state.phase {
            bot.resolvePending()
            return bot.send(.retire)
        }
        return bot.step()
    }
}

/// `pmsim scenario`: plays the three endings under each ruleset; returns 0 iff every game reaches its ending.
func runScenario(rulesets: [RulesetID], seed: UInt64?) -> Int32 {
    var passed = 0, total = 0
    for ruleset in rulesets {
        for ending in ScenarioEnding.allCases {
            let outcome = Scenario.play(ruleset, ending, seed: seed ?? Scenario.defaultSeed)
            print(outcome.line)
            total += 1
            if outcome.passed { passed += 1 }
        }
    }
    print("SCENARIO \(passed)/\(total) \(passed == total ? "PASS" : "FAIL")")
    return passed == total ? 0 : 1
}
