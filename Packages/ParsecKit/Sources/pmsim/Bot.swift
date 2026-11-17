// SPDX-License-Identifier: GPL-2.0-or-later
// pmsim bot (PRD §8.2 "Economy sanity"): a greedy trader. Under each ruleset on Normal it must grow net worth over
// 20 seeds without invariant violations; the median days for worth to reach the moon price is recorded in the QA report
// and must be finite for Modern.
//
// The bot plays only through legal public commands and reads only what the player can see (the market, the outfitter,
// the shipyard quote, the bank and warp previews, average prices and the tactical readout). It stays lawful, never
// carries illegal goods, flees hostile ships, protects itself with an escape pod, insurance and shields, and trades the
// cargo plan with the best expected profit over every reachable system.
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
    var previousSystem: Int?
    let check: (GameState) -> String?

    init(ruleset: RulesetID, seed: UInt64, check: @escaping (GameState) -> String?) {
        e = GameEngine(config: NewGameConfig(commanderName: "Bot", difficulty: .normal, ruleset: ruleset, seed: seed))
        self.check = check
    }

    var state: GameState { e.state }
    var r: Ruleset { e.ruleset }

    /// Sends a command; returns whether the engine accepted it.
    @discardableResult
    func send(_ c: Command) -> Bool {
        let result = e.perform(c, acknowledging: Self.ackAll)
        commands += 1
        if let v = check(e.state) { violations.append("day \(e.state.commander.days): \(v)") }
        if result.rejection != nil { return false }
        if case .confirm = result.decision, result.events.isEmpty { return false }
        return true
    }

    /// Plays one Normal game greedily for at most `maxDays` days (or `maxCommands` commands).
    static func play(ruleset: RulesetID, seed: UInt64, maxDays: Int = 4_000, maxCommands: Int = 250_000,
                     check: @escaping (GameState) -> String?) -> (BotResult, [String]) {
        let bot = TraderBot(ruleset: ruleset, seed: seed, check: check)
        let startWorth = bot.state.worth
        var daysToMoon: Int?
        var stalls = 0
        while bot.commands < maxCommands, bot.state.commander.days < maxDays {
            if case .gameOver = bot.state.phase { break }
            if daysToMoon == nil, bot.state.worth >= moonWorth { daysToMoon = bot.state.commander.days }
            if case .encounter = bot.state.phase {
                bot.encounterTurn()
                continue
            }
            guard case .docked = bot.state.phase else {
                bot.resolvePending()
                bot.send(.warp)
                continue
            }
            let day = bot.state.commander.days
            bot.dockedTurn()
            // Stranded: still docked on the same day after a full turn (no fuel, no cash, no loan).
            if case .docked = bot.state.phase, bot.state.commander.days == day {
                stalls += 1
                if stalls >= 3 { break }
            } else {
                stalls = 0
            }
        }
        if ProcessInfo.processInfo.environment["PM_BOT_TRACE"] != nil {
            let c = bot.state.commander
            print("    end cash \(c.cash) debt \(c.debt) fuel \(c.ship.fuel)/\(bot.state.fuelCapacity) ship \(c.ship.type) "
                  + "hull \(c.ship.hull) dest \(bot.state.destinations.count) reach \(bot.reachable.count) "
                  + "pod \(c.ship.escapePod) record \(c.policeRecordScore) cargo \(c.ship.cargo)")
        }
        let ended: Bool = if case .gameOver = bot.state.phase { true } else { false }
        return (BotResult(startWorth: startWorth, endWorth: bot.state.worth, days: bot.state.commander.days,
                          daysToMoonWorth: daysToMoon, ended: ended), bot.violations)
    }

    /// Declines or closes any decision the engine raised (trade in orbit, plunder, scoop).
    func resolvePending() {
        if state.pendingOrbitTrade != nil { send(.resolveTradeInOrbit(quantity: 0)) }
        if state.pendingPlunder != nil { send(.plunderDone) }
        if state.pendingScoop != nil { send(.resolveScoop(accept: false)) }
    }

    // MARK: Encounters

    /// One encounter decision: leave peaceful ships alone, submit to inspections, flee hostile ships and surrender
    /// cargo to pirates only when the hull is failing.
    func encounterTurn() {
        resolvePending()
        guard case .encounter(let enc) = state.phase else { return }
        let actions = enc.type.actions
        let police = [EncounterType.policeAttack, .policeSurrender, .marieCelestePolice].contains(enc.type)
        let ship = state.commander.ship
        let hullPercent = ship.hull * 100 / max(1, ship.hullStrength(r))
        var order: [EncounterAction] = []
        if actions.contains(.ignore) { order.append(.ignore) }
        if actions.contains(.submit) { order.append(.submit) }
        // Surrendering an empty hold costs blackmail, so it is kept for a failing hull; a full hold is given up early
        // against a ship the bot is unlikely to escape when it has no escape pod.
        let emptyHold = ship.cargo.allSatisfy { $0 == 0 }
        let hopeless = !ship.escapePod && e.tacticalReadout?.fleeOdds == .poor
        let giveUp = emptyHold ? hullPercent < 20 : (hullPercent < 35 || hopeless)
        if !police, actions.contains(.surrender), giveUp { order.append(.surrender) }
        if actions.contains(.flee) { order.append(.flee) }
        if !police, actions.contains(.surrender) { order.append(.surrender) }
        if actions.contains(.plunder) { order.append(.plunder) }
        if actions.contains(.yield) { order.append(.yield) }
        order += actions.filter { !order.contains($0) }
        for action in order where send(.encounter(action)) {
            resolvePending()
            return
        }
        // Nothing was accepted (should not happen): fall back to continuing the journey.
        send(.warp)
    }

    // MARK: Docked turn

    /// One docked turn: sell, settle the bank, refuel, repair, protect and upgrade the ship, buy the best cargo plan
    /// and warp to its destination.
    func dockedTurn() {
        resolvePending()
        sellCargo()
        refuelAndRepair()
        repayDebt()
        protectShip()
        upgradeShip()
        buyShields()
        refuelAndRepair()
        if reachable.isEmpty { rescueFromStranding() }
        let plan = bestPlan()
        if let plan {
            for (item, qty) in plan.buys where qty > 0 { send(.buyCargo(item, quantity: qty)) }
        }
        var targets = rankedTargets()
        if let plan { targets.removeAll { $0 == plan.target }; targets.insert(plan.target, at: 0) }
        let from = state.commander.currentSystem
        for target in targets {
            guard send(.selectTarget(target)) else { continue }
            if send(.warp) {
                previousSystem = from
                return
            }
        }
    }

    func sellCargo() {
        for item in TradeItemType.allCases where state.commander.ship.cargo[item.rawValue] > 0 {
            let qty = state.commander.ship.cargo[item.rawValue]
            if !send(.sellCargo(item, quantity: qty)), item.isIllegal { send(.dumpCargo(item, quantity: qty)) }
        }
    }

    func refuelAndRepair() {
        if state.fullTankCost > 0 { send(.buyFuel(credits: state.commander.cash)) }
        let repair = state.fullRepairCost
        if repair > 0 {
            // Repair fully when it leaves trading capital; otherwise patch up to what a quarter of the cash buys.
            let budget = repair * 3 <= state.commander.cash ? repair : state.commander.cash / 4
            if budget > 0 { send(.repairHull(credits: budget)) }
        }
    }

    /// Interest is 10% a day, so any debt is repaid as soon as cash allows (keeping fuel money).
    func repayDebt() {
        let debt = state.commander.debt
        guard debt > 0 else { return }
        let spare = state.commander.cash - operatingReserve
        if spare > 0 { send(.repay(min(debt, spare))) }
    }

    /// No reachable system: borrow for fuel, then sell equipment, so the game can continue.
    func rescueFromStranding() {
        if state.commander.insurance { send(.stopInsurance) }
        let need = max(state.fullTankCost, 1)
        if state.commander.cash < need {
            let loan = min(state.bankPreview.availableToBorrow, max(need, 500))
            if loan > 0 { send(.borrow(loan)) }
        }
        refuelAndRepair()
        while state.destinations.isEmpty, let item = state.equipmentMarket.installed.last(where: { $0.sellBlocker == nil }) {
            let sold: Bool
            switch item.item {
            case .weapon: sold = send(.sellWeapon(index: item.slot))
            case .shield: sold = send(.sellShield(index: item.slot))
            case .gadget: sold = send(.sellGadget(index: item.slot))
            }
            if !sold { break }
            refuelAndRepair()
        }
    }

    /// Cash kept back from trading: a full tank, a hull repair, a few days of costs and a cushion that scales with
    /// worth (a pirate raid can take the whole hold).
    var operatingReserve: Int {
        let spec = state.commander.ship.spec(r)
        let tank = spec.fuelTanks * spec.fuelCost
        let hull = spec.hullStrength * spec.repairCost / 2
        let daily = state.bankPreview.currentPremium + state.commander.debt / 10
        return tank + hull + 3 * daily + 50
    }

    /// Escape pod first (a destroyed ship without one ends the game), then insurance on the ship.
    func protectShip() {
        if !state.commander.ship.escapePod, state.escapePodOffered, state.commander.cash > 8_000 + 2 * operatingReserve {
            send(.buyEscapePod)
        }
        let bank = state.bankPreview
        if bank.canBuyInsurance, state.commander.debt == 0, bank.premiumQuote * 100 < state.commander.cash {
            send(.buyInsurance)
        } else if bank.insured, bank.currentPremium * 3 > state.commander.cash {
            send(.stopInsurance)  // cannot afford the daily premium: it would block every warp
        }
    }

    /// Buys the best shield the bot can comfortably afford into a free slot, or replaces a weaker one.
    func buyShields() {
        guard state.commander.debt == 0 else { return }
        let market = state.equipmentMarket
        let offers = market.offers.compactMap { offer -> (ShieldType, Int)? in
            guard case .shield(let s) = offer.item, offer.buyPrice > 0 else { return nil }
            return (s, offer.buyPrice)
        }.sorted { $0.0 > $1.0 }
        let budget = state.commander.cash / 4
        guard let (best, price) = offers.first(where: { $0.1 <= budget }) else { return }
        if state.commander.ship.freeShieldSlots(r) > 0 {
            send(.buyShield(best))
            return
        }
        let installed = market.installed.compactMap { item -> (Int, ShieldType)? in
            guard case .shield(let s) = item.item, item.sellBlocker == nil else { return nil }
            return (item.slot, s)
        }
        if let weakest = installed.min(by: { $0.1 < $1.1 }), weakest.1 < best, price <= budget,
           send(.sellShield(index: weakest.0)) {
            send(.buyShield(best))
        }
    }

    /// Buys a ship with more cargo bays (and at least as many shield slots) when it costs at most a third of the cash.
    func upgradeShip() {
        guard state.commander.debt == 0 else { return }
        for type in upgradeCandidates {
            let quote = state.shipQuote(type)
            guard quote.blocker == nil, quote.netPrice * 3 < state.commander.cash else { continue }
            if send(.buyShip(type, transfers: quote.candidates.map(\.item))) { return }
        }
    }

    /// Ship types with more cargo bays than the current ship and comparable defences, largest hold first.
    var upgradeCandidates: [ShipType] {
        let current = state.commander.ship.spec(r)
        return ShipType.buyable.filter {
            let spec = r.tables.ship($0)
            return spec.cargoBays > current.cargoBays && spec.shieldSlots >= min(current.shieldSlots, 1)
                && spec.hullStrength >= current.hullStrength / 2
        }.sorted { r.tables.ship($0).cargoBays > r.tables.ship($1).cargoBays }
    }

    /// The tech level of the shipyard the bot wants to visit: one selling an upgrade it could afford (list price
    /// within a third of its cash), or an escape pod it lacks. Nil when it has nothing to buy.
    var wantedTechLevel: TechLevel? {
        let cash = state.commander.cash
        if let type = upgradeCandidates.first(where: { r.tables.ship($0).price * 3 < cash }) {
            return max(.earlyIndustrial, r.tables.ship(type).minTechLevel)
        }
        if !state.commander.ship.escapePod, cash > 8_000 + 2 * operatingReserve { return .earlyIndustrial }
        return nil
    }

    // MARK: Trade planning

    struct Plan {
        var target: Int
        var buys: [(TradeItemType, Int)]
        var profit: Int
    }

    /// The reachable systems the bot may warp to now (no blocking cost, wormhole tax affordable).
    var reachable: [Int] {
        state.destinations.filter { state.warpTargetPreview($0).blocking == nil }
    }

    /// The cargo plan with the highest expected profit over every reachable system, using the visible buy prices
    /// here and the average (standard) prices there.
    func bestPlan() -> Plan? {
        let here = state.currentSystem
        let budget = max(0, state.cashToSpend - operatingReserve)
        let bays = state.freeCargoBays
        let wanted = wantedTechLevel
        let shipyardBonus = wanted == nil ? 0 : max(500, state.commander.cash / 10)
        var best: Plan?
        for target in reachable {
            let there = state.galaxy.systems[target]
            let preview = state.warpTargetPreview(target)
            var margins: [(TradeItemType, Int, Int)] = []
            for item in TradeItemType.allCases where !item.isIllegal {
                let i = item.rawValue
                let buy = state.buyPrices[i]
                guard buy > 0, here.tradeItems[i] > 0 else { continue }
                let sell = Pricing.standardPrice(r.tables.tradeItems[i], in: there, ruleset: r)
                // Demand a margin above the price noise (about ±10%) so the trade is profitable on average.
                let margin = sell - buy
                if margin * 10 > buy { margins.append((item, buy, margin)) }
            }
            margins.sort { $0.2 * $1.1 > $1.2 * $0.1 || ($0.2 * $1.1 == $1.2 * $0.1 && $0.2 > $1.2) }
            var plan = Plan(target: target, buys: [], profit: -preview.costs.total)
            var money = budget - preview.costs.total, space = bays
            // Spend on the most profitable item per bay first when cash, not space, is the limit, else per credit.
            let cashBound = margins.first.map { money / max(1, $0.1) < space } ?? false
            if !cashBound { margins.sort { $0.2 > $1.2 } }
            for (item, buy, margin) in margins where space > 0 && money >= buy && budget > 0 {
                let qty = min(space, here.tradeItems[item.rawValue], money / buy)
                guard qty > 0 else { continue }
                plan.buys.append((item, qty))
                plan.profit += qty * margin
                space -= qty
                money -= qty * buy
            }
            // Expected loss to pirates: the chance of at least one pirate roll on the way, times a lost hold.
            let invested = budget - preview.costs.total - money
            plan.profit -= invested * pirateRiskPermille(target) / 1_000
            if let wanted, there.techLevel >= wanted { plan.profit += shipyardBonus }
            if plan.profit > (best?.profit ?? 0) { best = plan }
        }
        return best
    }

    /// Per-mille chance that a trip to `target` loses the hold to pirates: at least one pirate roll in the trip's
    /// encounter checks (C# `DetermineRandomEncounter`: `roll < pirates` out of `44 − 2·difficulty`), times the chance
    /// the bot fails to escape.
    func pirateRiskPermille(_ target: Int) -> Int {
        let pirates = r.tables.politics(state.galaxy.systems[target].politics).activityPirates.rawValue
        let sides = 44 - 2 * state.difficulty.rawValue
        let factor = state.commander.ship.type == .flea ? 2 : 1
        let perClick = Double(min(sides, pirates * factor)) / Double(sides)
        let atLeastOne = 1 - pow(1 - perClick, 20)
        return Int(atLeastOne * Self.escapeFailure * 1_000)
    }

    static let escapeFailure = 0.35

    /// Fallback destinations without a profitable plan: richer, larger markets first, avoiding the system just left.
    func rankedTargets() -> [Int] {
        reachable.sorted { a, b in
            let sa = state.galaxy.systems[a], sb = state.galaxy.systems[b]
            let pa = (a == previousSystem ? 0 : 100) + sa.techLevel.rawValue * 10 + sa.size.rawValue
            let pb = (b == previousSystem ? 0 : 100) + sb.techLevel.rawValue * 10 + sb.size.rawValue
            return pa != pb ? pa > pb : a < b
        }
    }
}

/// Runs `games` bot games per ruleset; returns the exit code (non-zero when worth does not grow in more than half the
/// games, an invariant fails, or Modern's median day to the moon price over all games is not finite).
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
                let moon = res.daysToMoonWorth.map { " moon day \($0)" } ?? ""
                print("  \(ruleset) game \(g): worth \(res.startWorth)→\(res.endWorth) days \(res.days) ended \(res.ended)\(moon)")
            }
        }
        moonDays.sort()
        // Median over all games, counting games that never reached the moon price as infinite.
        let allGamesMedian: Int? = games > 0 && moonDays.count > (games - 1) / 2 ? moonDays[(games - 1) / 2] : nil
        let reachedMedian = moonDays.isEmpty ? nil : moonDays[moonDays.count / 2]
        print("bot \(ruleset): worth grew in \(grew)/\(games) games, \(totalViolations) violations, "
              + "reached moon worth in \(moonDays.count)/\(games) "
              + "(median day over all games \(allGamesMedian.map(String.init) ?? "infinite"), "
              + "over reaching games \(reachedMedian.map(String.init) ?? "none"))")
        if totalViolations > 0 || grew * 2 <= games { failed = true }
        if ruleset == .modern, allGamesMedian == nil { failed = true }
    }
    return failed ? 1 : 0
}
