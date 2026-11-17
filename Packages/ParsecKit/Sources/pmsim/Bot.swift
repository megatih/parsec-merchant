// SPDX-License-Identifier: GPL-2.0-or-later
// pmsim bot (PRD §8.2 "Economy sanity"): a greedy trader. Under each ruleset on Normal it must grow net worth over
// 20 seeds without invariant violations; the median days for worth to reach the moon price is recorded in the QA report
// and must be finite for Modern.
import Foundation
import ParsecEngine

struct BotResult {
    var startWorth: Int
    var endWorth: Int
    var days: Int
    var daysToMoonWorth: Int?
    var ended: Bool
}

/// A greedy trader that owns its engine (a class, so the command sender and the decision code share one engine).
final class TraderBot {
    static let ackAll = Set(WarningID.allCases)
    static let moonWorth = QuestStatus.moonCost

    var e: GameEngine
    var violations: [String] = []
    var commands = 0
    let check: (GameState) -> String?

    init(ruleset: RulesetID, seed: UInt64, check: @escaping (GameState) -> String?) {
        e = GameEngine(config: NewGameConfig(commanderName: "Bot", difficulty: .normal, ruleset: ruleset, seed: seed))
        self.check = check
    }

    func send(_ c: Command) {
        e.perform(c, acknowledging: Self.ackAll)
        commands += 1
        if let v = check(e.state) { violations.append("day \(e.state.commander.days): \(v)") }
    }

    /// Plays one Normal game greedily for at most `maxDays` days (or `maxCommands` commands).
    static func play(ruleset: RulesetID, seed: UInt64, maxDays: Int = 4_000, maxCommands: Int = 250_000,
                     check: @escaping (GameState) -> String?) -> (BotResult, [String]) {
        let bot = TraderBot(ruleset: ruleset, seed: seed, check: check)
        let startWorth = bot.e.state.worth
        var daysToMoon: Int?
        while bot.commands < maxCommands, bot.e.state.commander.days < maxDays {
            if case .gameOver = bot.e.state.phase { break }
            if daysToMoon == nil, bot.e.state.worth >= moonWorth { daysToMoon = bot.e.state.commander.days }
            if case .encounter(let enc) = bot.e.state.phase {
                bot.resolvePending()
                if case .encounter = bot.e.state.phase {
                    let actions = enc.type.actions
                    // Survival first: ignore when possible, submit to inspections, surrender rather than risk a failed flee.
                    // Surrendering to police means arrest, so the bot flees them; pirates only take cargo.
                    let police: Bool = [.policeAttack, .policeSurrender, .marieCelestePolice].contains(enc.type)
                    let ship = bot.e.state.commander.ship
                    let battered = ship.hull * 100 < ship.hullStrength(bot.e.ruleset) * 40
                    let pick: EncounterAction = actions.contains(.ignore) ? .ignore
                        : actions.contains(.submit) ? .submit
                        : (!police && battered && actions.contains(.surrender)) ? .surrender
                        : actions.contains(.flee) ? .flee
                        : actions.contains(.surrender) && !police ? .surrender
                        : (actions.first ?? .attack)
                    bot.send(.encounter(pick))
                    bot.resolvePending()
                }
                continue
            }
            guard case .docked = bot.e.state.phase else { bot.send(.warp); continue }
            let day = bot.e.state.commander.days
            bot.dockedTurn()
            // Stranded: no reachable system and nothing changed (no cash, no loan) — the game cannot continue.
            if case .docked = bot.e.state.phase, bot.e.state.commander.days == day, bot.e.state.destinations.isEmpty { break }
        }
        let ended: Bool = if case .gameOver = bot.e.state.phase { true } else { false }
        return (BotResult(startWorth: startWorth, endWorth: bot.e.state.worth, days: bot.e.state.commander.days,
                          daysToMoonWorth: daysToMoon, ended: ended), bot.violations)
    }

    /// Declines or closes any decision the engine raised (trade in orbit, plunder, scoop).
    func resolvePending() {
        if e.state.pendingOrbitTrade != nil { send(.resolveTradeInOrbit(quantity: 0)) }
        if e.state.pendingPlunder != nil { send(.plunderDone) }
        if e.state.pendingScoop != nil { send(.resolveScoop(accept: false)) }
    }

    /// One docked turn: sell, refuel, repair, maybe upgrade the ship, buy the best cargo, warp to its destination.
    func dockedTurn() {
        let r = e.ruleset
        for item in TradeItemType.allCases where e.state.commander.ship.cargo[item.rawValue] > 0 {
            send(.sellCargo(item, quantity: e.state.commander.ship.cargo[item.rawValue]))
        }
        if e.state.commander.debt > 0, e.state.commander.cash > e.state.commander.debt { send(.repay(e.state.commander.debt)) }
        if e.state.destinations.isEmpty, e.state.commander.cash < 500 { send(.borrow(1_000)) }  // stranded: loan for fuel
        send(.buyFuel(credits: e.state.commander.cash))
        send(.repairHull(credits: e.state.commander.cash / 2))
        if !e.state.commander.ship.escapePod, e.state.commander.cash > 3_000 { send(.buyEscapePod) }
        upgradeShip()

        let state = e.state
        let here = state.currentSystem
        var best: (target: Int, item: TradeItemType, margin: Int)?
        for target in state.destinations {
            let there = state.galaxy.systems[target]
            for item in TradeItemType.allCases {
                let i = item.rawValue
                let buy = state.buyPrices[i]
                guard buy > 0, here.tradeItems[i] > 0, !item.isIllegal else { continue }
                let sell = Pricing.standardPrice(r.tables.tradeItems[i], in: there, ruleset: r)
                let margin = sell - buy
                if margin > (best?.margin ?? 0) { best = (target, item, margin) }
            }
        }
        if let best {
            let i = best.item.rawValue
            // Keep a reserve for fuel and repairs: a surrender to pirates can take the whole hold.
            let reserve = max(200, e.state.commander.cash / 5)
            let affordable = max(0, e.state.cashToSpend - reserve) / max(1, e.state.buyPrices[i])
            let qty = min(affordable, e.state.freeCargoBays, e.state.currentSystem.tradeItems[i])
            if qty > 0 { send(.buyCargo(best.item, quantity: qty)) }
            send(.selectTarget(best.target))
        } else if let any = e.state.destinations.first {
            send(.selectTarget(any))
        }
        send(.warp)
    }

    /// Buys the buyable ship with the most cargo bays when it costs less than half the bot's cash.
    func upgradeShip() {
        let r = e.ruleset
        let current = e.state.commander.ship.spec(r).cargoBays
        let candidates = ShipType.buyable.filter { r.tables.ship($0).cargoBays > current }
            .sorted { r.tables.ship($0).cargoBays > r.tables.ship($1).cargoBays }
        for type in candidates {
            let quote = e.state.shipQuote(type)
            guard quote.blocker == nil, quote.netPrice * 2 < e.state.commander.cash else { continue }
            send(.buyShip(type, transfers: TransferItem.allCases))
            return
        }
    }
}

/// Runs `games` bot games per ruleset; returns the exit code (non-zero when worth does not grow overall, an invariant
/// fails, or Modern never reaches the moon price).
func runBot(games: Int, seed: UInt64, rulesets: [RulesetID]) -> Int32 {
    var failed = false
    for ruleset in rulesets {
        var fuzzer = Fuzzer(ruleset: ruleset)
        var grew = 0, totalViolations = 0
        var moonDays: [Int] = []
        for g in 0..<games {
            let (res, violations) = TraderBot.play(ruleset: ruleset, seed: seed &+ UInt64(g)) { s in
                let before = fuzzer.violations.count
                fuzzer.check(s, game: g, step: 0, command: .warp, cashBefore: s.commander.cash)
                return fuzzer.violations.count > before ? fuzzer.violations.last : nil
            }
            totalViolations += violations.count
            if res.endWorth > res.startWorth { grew += 1 }
            if let d = res.daysToMoonWorth { moonDays.append(d) }
            if ProcessInfo.processInfo.environment["PM_BOT_TRACE"] != nil {
                print("  \(ruleset) game \(g): worth \(res.startWorth)→\(res.endWorth) days \(res.days) ended \(res.ended)")
            }
        }
        moonDays.sort()
        let median = moonDays.isEmpty ? nil : moonDays[moonDays.count / 2]
        let medianText = median.map(String.init) ?? "never"
        print("bot \(ruleset): worth grew in \(grew)/\(games) games, \(totalViolations) violations, "
              + "reached moon worth in \(moonDays.count)/\(games) (median day \(medianText))")
        if totalViolations > 0 || grew * 2 <= games { failed = true }
        if ruleset == .modern, median == nil { failed = true }
    }
    return failed ? 1 : 0
}
