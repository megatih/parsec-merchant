// SPDX-License-Identifier: GPL-2.0-or-later
// Captain's log entries (docs/specs/LOG.md §2, LOG-008…012): typed payloads, no user-facing strings.
import ParsecEngine

/// LOG-005/006: how a journal began.
public enum JournalOrigin: String, Codable, Sendable, Equatable {
    /// New Game, Quick Start or a scenario: the journal holds the whole history.
    case newGame
    /// Bootstrapped from a state that had no journal: a partial history (STAT-004).
    case resumed
}

/// LOG-005: the facts of the first entry.
public struct JournalStart: Codable, Sendable, Equatable {
    public var origin: JournalOrigin
    public var rulesetID: RulesetID
    public var difficulty: Difficulty
    public var ironman: Bool
    public var systemCount: Int
    public var startSystem: Int
    /// The systems already visited when the journal began, ascending.
    public var visitedSystems: [Int]
    public var kills: Kills

    public init(origin: JournalOrigin, rulesetID: RulesetID, difficulty: Difficulty, ironman: Bool, systemCount: Int,
                startSystem: Int, visitedSystems: [Int], kills: Kills) {
        self.origin = origin
        self.rulesetID = rulesetID
        self.difficulty = difficulty
        self.ironman = ironman
        self.systemCount = systemCount
        self.startSystem = startSystem
        self.visitedSystems = visitedSystems
        self.kills = kills
    }
}

/// LOG-009: what a trade entry records.
public enum TradeAction: String, Codable, Sendable, Equatable, CaseIterable {
    case buy, sell, dump, jettison, plunder, scoop, orbitBuy, orbitSell, sealedCanisters
}

/// LOG-009: a trade. `profit` is set for sales (docked or in orbit) only.
public struct TradeEntry: Codable, Sendable, Equatable {
    public var action: TradeAction
    public var item: TradeItemType
    public var quantity: Int
    public var total: Int
    public var profit: Int?

    public init(action: TradeAction, item: TradeItemType, quantity: Int, total: Int, profit: Int? = nil) {
        self.action = action
        self.item = item
        self.quantity = quantity
        self.total = total
        self.profit = profit
    }
}

/// LOG-009 / LOG-018: an arrival.
public struct TripArrival: Codable, Sendable, Equatable {
    public var system: Int
    public var from: Int
    public var viaWormhole: Bool
    public var firstVisit: Bool
    public var uneventful: Bool
    public var encounterCount: Int

    public init(system: Int, from: Int, viaWormhole: Bool, firstVisit: Bool, uneventful: Bool, encounterCount: Int) {
        self.system = system
        self.from = from
        self.viaWormhole = viaWormhole
        self.firstVisit = firstVisit
        self.uneventful = uneventful
        self.encounterCount = encounterCount
    }
}

/// LOG-009: police entries.
public enum PoliceEntry: Codable, Sendable, Equatable {
    case arrested(term: Int, fine: Int, shipSold: Bool)
    case caughtLittering
    case reactorConfiscated
}

/// LOG-009: bank and insurance entries.
public enum FinanceEntry: Codable, Sendable, Equatable {
    case borrowed(amount: Int)
    case repaid(amount: Int, remainingDebt: Int)
    case insuranceBought
    case insuranceStopped
    case debtWarning(debt: Int)
    case debtReminder(debt: Int)
}

/// LOG-009: the weapon, shield or gadget bought or sold (taken from the command).
public enum EquipmentChange: Codable, Sendable, Equatable {
    case boughtWeapon(WeaponType)
    case boughtShield(ShieldType)
    case boughtGadget(GadgetType)
    case soldWeapon(WeaponType)
    case soldShield(ShieldType)
    case soldGadget(GadgetType)
}

/// LOG-009: ship and service entries.
public enum ShipEntry: Codable, Sendable, Equatable {
    case boughtShip(ShipType, netPrice: Int)
    case customShipBuilt(ShipyardID)
    case equipment(EquipmentChange, price: Int)
    case boughtEscapePod(price: Int)
    case fuel(units: Int, cost: Int)
    case repair(points: Int, cost: Int)
    case autoFuelFailed
    case autoRepairFailed
    case escapePodUsed(insurancePayout: Int)
}

/// LOG-009: crew entries.
public enum CrewEntry: Codable, Sendable, Equatable {
    case hired(crewID: Int)
    case fired(crewID: Int)
    case passengerConcerned(crewID: Int)
    case passengerImpatient(crewID: Int)
}

/// LOG-009: quest entries.
public enum QuestEntry: Codable, Sendable, Equatable {
    case completed(SpecialEventType)
    case refused(SpecialEventType)
    case tribbles(from: Int, to: Int)
    case tribblesDied(TribbleDeath)
    case tribblesAteFood(eaten: Int)
    case tribbleInspectorWarning(count: Int)
    case reactorWarning(status: Int)
    case reactorMeltdown
    case gemulonInvaded
    case experimentPerformed
    case wildLeftShip
    case easterEgg(shieldInstalled: Bool)
}

/// LOG-016: a newspaper read.
public struct NewsEntry: Codable, Sendable, Equatable {
    public var headlines: [Headline]
    public var cost: Int

    public init(headlines: [Headline], cost: Int) {
        self.headlines = headlines
        self.cost = cost
    }
}

/// LOG-017: a change of police record or reputation level.
public enum StatusEntry: Codable, Sendable, Equatable {
    case policeRecord(from: PoliceRecordType, to: PoliceRecordType)
    case reputation(from: ReputationType, to: ReputationType)
}

/// LOG-009: every kind of entry.
public enum LogEntryKind: Codable, Sendable, Equatable {
    case journalStarted(JournalStart)
    case cheatsEnabled
    case gameEnded(GameEndType, score: Int)
    case achievementUnlocked(AchievementID)
    case trade(TradeEntry)
    case departed(from: Int, to: Int, viaWormhole: Bool, parsecs: Int)
    case arrived(TripArrival)
    case fabricRip(newDestination: Int)
    case singularityLost
    case encounter(EncounterRecord)
    case police(PoliceEntry)
    case finance(FinanceEntry)
    case ship(ShipEntry)
    case crew(CrewEntry)
    case quest(QuestEntry)
    case news(NewsEntry)
    case status(StatusEntry)
}

/// LOG-010: the filter categories of the Logbook.
public enum LogCategory: String, Codable, Sendable, Equatable, CaseIterable {
    case trade, travel, encounter, police, finance, ship, crew, quest, news, status, achievement, game
}

public extension LogEntryKind {
    /// LOG-010: every kind maps to exactly one category.
    var category: LogCategory {
        switch self {
        case .journalStarted, .cheatsEnabled, .gameEnded: .game
        case .achievementUnlocked: .achievement
        case .trade: .trade
        case .departed, .arrived, .fabricRip, .singularityLost: .travel
        case .encounter: .encounter
        case .police: .police
        case .finance: .finance
        case .ship: .ship
        case .crew: .crew
        case .quest: .quest
        case .news: .news
        case .status: .status
        }
    }

    /// LOG-011 / LLM-003: the facts flavor text is written about; non-nil only for arrivals, encounters, completed
    /// quests, game endings and achievements.
    var flavorSubject: FlavorSubject? {
        switch self {
        case let .arrived(a):
            .arrival(system: a.system, viaWormhole: a.viaWormhole, firstVisit: a.firstVisit, uneventful: a.uneventful,
                     encounterCount: a.encounterCount)
        case let .encounter(r):
            .encounter(type: r.type, opponent: r.opponent, result: r.result, rounds: r.rounds, minHullPercent: r.minHullPercent)
        case let .quest(.completed(event)): .quest(event)
        case let .gameEnded(end, _): .gameEnded(end)
        case let .achievementUnlocked(id): .achievement(id)
        case .journalStarted, .cheatsEnabled, .trade, .departed, .fabricRip, .singularityLost, .police, .finance, .ship,
             .crew, .quest, .news, .status:
            nil
        }
    }
}

/// LOG-008: one log entry. Entries are never edited except `flavor` (LLM-021).
public struct LogEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var day: Int
    public var system: Int
    public var worth: Int
    public var kind: LogEntryKind
    public var flavor: FlavorText?

    public init(id: Int, day: Int, system: Int, worth: Int, kind: LogEntryKind, flavor: FlavorText? = nil) {
        self.id = id
        self.day = day
        self.system = system
        self.worth = worth
        self.kind = kind
        self.flavor = flavor
    }

    public var category: LogCategory { kind.category }
}
