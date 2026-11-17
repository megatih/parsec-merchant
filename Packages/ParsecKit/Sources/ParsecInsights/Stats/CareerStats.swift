// SPDX-License-Identifier: GPL-2.0-or-later
// Career statistics as a fold over the log (docs/specs/STAT.md §1–3, STAT-001…014). Reads entries only; total; no RNG.
import ParsecEngine

/// STAT-007: net worth on a day.
public struct WorthSample: Codable, Sendable, Equatable {
    public var day: Int
    public var worth: Int

    public init(day: Int, worth: Int) {
        self.day = day
        self.worth = worth
    }
}

/// STAT-006: the most profitable single sale.
public struct BestSale: Codable, Sendable, Equatable {
    public var item: TradeItemType
    public var quantity: Int
    public var profit: Int
    public var day: Int
    public var system: Int

    public init(item: TradeItemType, quantity: Int, profit: Int, day: Int, system: Int) {
        self.item = item
        self.quantity = quantity
        self.profit = profit
        self.day = day
        self.system = system
    }
}

/// STAT-001…012: the statistics of a journal's entries.
public struct CareerStats: Sendable, Equatable {
    // Bookkeeping.
    /// Entries folded so far.
    public internal(set) var entryCount = 0
    /// STAT-004: the journal began from a resumed state.
    public internal(set) var isPartial = false
    // STAT-005: time and travel.
    public internal(set) var startDay: Int?
    public internal(set) var lastDay: Int?
    public internal(set) var warps = 0
    public internal(set) var wormholeJumps = 0
    public internal(set) var parsecsTravelled = 0
    public internal(set) var arrivals = 0
    public internal(set) var fabricRips = 0
    public internal(set) var systemCount = 0
    public internal(set) var visitedSystems: [Bool] = []
    public internal(set) var visitedCount = 0
    // STAT-006: trade.
    public internal(set) var buys = 0
    public internal(set) var sells = 0
    public internal(set) var unitsBought = 0
    public internal(set) var unitsSold = 0
    public internal(set) var spentOnCargo = 0
    public internal(set) var earnedFromCargo = 0
    public internal(set) var profitByItem = Array(repeating: 0, count: TradeItemType.allCases.count)
    public internal(set) var totalTradeProfit = 0
    public internal(set) var itemsBought = Array(repeating: false, count: TradeItemType.allCases.count)
    public internal(set) var itemsSold = Array(repeating: false, count: TradeItemType.allCases.count)
    public internal(set) var bestSale: BestSale?
    public internal(set) var firstProfitDay: Int?
    public internal(set) var plunderedUnits = 0
    public internal(set) var scoopedUnits = 0
    public internal(set) var dumpCosts = 0
    // STAT-007: worth.
    public internal(set) var worthSamples: [WorthSample] = []
    public internal(set) var peakWorth: Int?
    public internal(set) var latestWorth: Int?
    // STAT-008 / STAT-009: combat.
    public internal(set) var encounters = 0
    public internal(set) var encountersByType = Array(repeating: 0, count: EncounterType.allCases.count)
    public internal(set) var destroyedByShipType = Array(repeating: 0, count: ShipType.allCases.count)
    public internal(set) var kills = Kills()
    public internal(set) var bountiesCollected = 0
    public internal(set) var bountyTotal = 0
    public internal(set) var lowestHullPercentSurvived: Int?
    public internal(set) var won = 0
    public internal(set) var fled = 0
    public internal(set) var surrendered = 0
    public internal(set) var lost = 0
    public internal(set) var otherResults = 0
    // STAT-010: law and money.
    public internal(set) var arrests = 0
    public internal(set) var finesPaid = 0
    public internal(set) var bribesPaid = 0
    public internal(set) var inspectionsPassed = 0
    public internal(set) var policeRecordLowest = PoliceRecordType.clean
    public internal(set) var policeRecordHighest = PoliceRecordType.clean
    public internal(set) var reputationHighest = ReputationType.harmless
    public internal(set) var borrowedTotal = 0
    public internal(set) var repaidTotal = 0
    public internal(set) var loansPaidOff = 0
    public internal(set) var insurancePayouts = 0
    public internal(set) var escapePodsUsed = 0
    // STAT-011: ship, crew and quests.
    public internal(set) var shipsBought = 0
    public internal(set) var customShipsBuilt = 0
    public internal(set) var equipmentBought = 0
    public internal(set) var equipmentSold = 0
    public internal(set) var fuelSpent = 0
    public internal(set) var repairsSpent = 0
    public internal(set) var mercenariesHired = 0
    public internal(set) var questsCompleted = Array(repeating: false, count: SpecialEventType.allCases.count)
    public internal(set) var maxTribbles = 0
    public internal(set) var newspapersRead = 0
    public internal(set) var marieCelesteFound = false
    /// Ahab, Conrad, Huie.
    public internal(set) var famousCaptainsMet = [false, false, false]
    // STAT-012: game.
    public internal(set) var ruleset: RulesetID?
    public internal(set) var difficulty: Difficulty?
    public internal(set) var ironman = false
    public internal(set) var cheatsUsed = false
    public internal(set) var ended: GameEndType?
    public internal(set) var finalScore: Int?
    public internal(set) var achievementsUnlocked = 0

    public init() {}

    /// STAT-001.
    public static func fold(_ entries: [LogEntry]) -> CareerStats {
        entries.reduce(into: CareerStats()) { $0.add($1) }
    }

    /// STAT-005: days between the first and the last entry.
    public var daysPlayed: Int {
        guard let startDay, let lastDay else { return 0 }
        return lastDay - startDay
    }

    /// STAT-009: the counter of a result class.
    public func count(_ result: EncounterResultClass) -> Int {
        switch result {
        case .won: won
        case .fled: fled
        case .surrendered: surrendered
        case .lost: lost
        case .other: otherResults
        }
    }

    /// STAT-011: quest completion by event type.
    public func completed(_ event: SpecialEventType) -> Bool { questsCompleted[event.rawValue] }

    /// STAT-001: folds one entry.
    public mutating func add(_ entry: LogEntry) {
        entryCount += 1
        if startDay == nil { startDay = entry.day }
        lastDay = entry.day
        addWorth(entry)
        switch entry.kind {
        case let .journalStarted(start): addStart(start)
        case .cheatsEnabled: cheatsUsed = true
        case let .gameEnded(end, score):
            ended = end
            finalScore = score
        case .achievementUnlocked: achievementsUnlocked += 1
        case let .trade(t): addTrade(t, entry: entry)
        case let .departed(_, _, via, parsecs):
            warps += 1
            if via { wormholeJumps += 1 }
            parsecsTravelled += parsecs
        case let .arrived(a):
            arrivals += 1
            markVisited(a.system)
        case .fabricRip: fabricRips += 1
        case .singularityLost: break
        case let .encounter(r): addEncounter(r)
        case let .police(p): addPolice(p)
        case let .finance(f): addFinance(f)
        case let .ship(s): addShip(s)
        case let .crew(c): if case .hired = c { mercenariesHired += 1 }
        case let .quest(q): addQuest(q)
        case .news: newspapersRead += 1
        case let .status(s): addStatus(s)
        }
    }

    private mutating func addWorth(_ entry: LogEntry) {
        if let last = worthSamples.last, last.day == entry.day {
            worthSamples[worthSamples.count - 1].worth = entry.worth
        } else {
            worthSamples.append(WorthSample(day: entry.day, worth: entry.worth))
        }
        peakWorth = max(peakWorth ?? entry.worth, entry.worth)
        latestWorth = entry.worth
    }

    private mutating func addStart(_ s: JournalStart) {
        isPartial = s.origin == .resumed
        ruleset = s.rulesetID
        difficulty = s.difficulty
        ironman = s.ironman
        systemCount = s.systemCount
        visitedSystems = Array(repeating: false, count: max(0, s.systemCount))
        visitedCount = 0
        for i in s.visitedSystems { markVisited(i) }
        markVisited(s.startSystem)
        kills = s.kills
    }

    private mutating func markVisited(_ system: Int) {
        guard visitedSystems.indices.contains(system), !visitedSystems[system] else { return }
        visitedSystems[system] = true
        visitedCount += 1
    }

    private mutating func addTrade(_ t: TradeEntry, entry: LogEntry) {
        let i = t.item.rawValue
        switch t.action {
        case .buy, .orbitBuy:
            buys += 1
            unitsBought += t.quantity
            spentOnCargo += t.total
            itemsBought[i] = true
        case .sell, .orbitSell:
            sells += 1
            unitsSold += t.quantity
            earnedFromCargo += t.total
            itemsSold[i] = true
            let profit = t.profit ?? 0
            profitByItem[i] += profit
            totalTradeProfit += profit
            if profit > 0, firstProfitDay == nil { firstProfitDay = entry.day }
            if bestSale.map({ profit > $0.profit }) ?? true {
                bestSale = BestSale(item: t.item, quantity: t.quantity, profit: profit, day: entry.day, system: entry.system)
            }
        case .plunder: plunderedUnits += t.quantity
        case .scoop: scoopedUnits += t.quantity
        case .dump: dumpCosts += t.total
        case .jettison, .sealedCanisters: break
        }
    }

    private mutating func addEncounter(_ r: EncounterRecord) {
        encounters += 1
        encountersByType[r.type.rawValue] += 1
        kills = r.killsAfter
        if case let .destroyed(ship) = r.outcome { destroyedByShipType[ship.rawValue] += 1 }
        if r.bounty > 0 {
            bountiesCollected += 1
            bountyTotal += r.bounty
        }
        switch r.result {
        case .won: won += 1
        case .fled: fled += 1
        case .surrendered: surrendered += 1
        case .lost: lost += 1
        case .other: otherResults += 1
        }
        if r.result != .lost { lowestHullPercentSurvived = min(lowestHullPercentSurvived ?? r.minHullPercent, r.minHullPercent) }
        switch r.outcome {
        case let .fined(amount): finesPaid += amount
        case let .bribed(amount): bribesPaid += amount
        case .inspectedClean: inspectionsPassed += 1
        default: break
        }
        switch r.type {
        case .marieCeleste: marieCelesteFound = true
        case .captainAhab: famousCaptainsMet[0] = true
        case .captainConrad: famousCaptainsMet[1] = true
        case .captainHuie: famousCaptainsMet[2] = true
        default: break
        }
    }

    private mutating func addPolice(_ p: PoliceEntry) {
        if case let .arrested(_, fine, _) = p {
            arrests += 1
            finesPaid += fine
        }
    }

    private mutating func addFinance(_ f: FinanceEntry) {
        switch f {
        case let .borrowed(amount): borrowedTotal += amount
        case let .repaid(amount, remaining):
            repaidTotal += amount
            if remaining == 0, amount > 0 { loansPaidOff += 1 }
        case .insuranceBought, .insuranceStopped, .debtWarning, .debtReminder: break
        }
    }

    private mutating func addShip(_ s: ShipEntry) {
        switch s {
        case .boughtShip: shipsBought += 1
        case .customShipBuilt:
            shipsBought += 1
            customShipsBuilt += 1
        case let .equipment(change, _):
            switch change {
            case .boughtWeapon, .boughtShield, .boughtGadget: equipmentBought += 1
            case .soldWeapon, .soldShield, .soldGadget: equipmentSold += 1
            }
        case .boughtEscapePod: break
        case let .fuel(_, cost): fuelSpent += cost
        case let .repair(_, cost): repairsSpent += cost
        case .autoFuelFailed, .autoRepairFailed: break
        case let .escapePodUsed(payout):
            escapePodsUsed += 1
            insurancePayouts += payout
        }
    }

    private mutating func addQuest(_ q: QuestEntry) {
        switch q {
        case let .completed(event): questsCompleted[event.rawValue] = true
        case let .tribbles(_, to): maxTribbles = max(maxTribbles, to)
        default: break
        }
    }

    private mutating func addStatus(_ s: StatusEntry) {
        switch s {
        case let .policeRecord(from, to):
            policeRecordLowest = min(policeRecordLowest, from, to)
            policeRecordHighest = max(policeRecordHighest, from, to)
        case let .reputation(from, to):
            reputationHighest = max(reputationHighest, from, to)
        }
    }
}
