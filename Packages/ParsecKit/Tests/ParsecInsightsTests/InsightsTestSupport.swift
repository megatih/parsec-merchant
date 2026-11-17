// SPDX-License-Identifier: GPL-2.0-or-later
// Shared helpers for the M10 insights tests: fresh states, recorded games and hand-built entries.
import ParsecEngine
@testable import ParsecInsights

/// A new game state.
func freshState(_ ruleset: RulesetID = .modern, seed: UInt64 = 42, difficulty: Difficulty = .normal,
                ironman: Bool = false) -> GameState {
    GameState(config: NewGameConfig(commanderName: "Insight", difficulty: difficulty, ruleset: ruleset, seed: seed,
                                    ironman: ironman))
}

/// A game played with a journal recorded after every step.
struct RecordedGame {
    var engine: GameEngine
    var journal: GameJournal
    var outputs: [JournalStepOutput] = []
    var steps = 0

    init(_ state: GameState) {
        engine = GameEngine(state: state)
        journal = GameJournal.start(state: state)
    }

    init(_ ruleset: RulesetID = .modern, seed: UInt64 = 42, difficulty: Difficulty = .normal) {
        self.init(freshState(ruleset, seed: seed, difficulty: difficulty))
    }

    var state: GameState { engine.state }

    /// Performs and records one command; returns the step result.
    @discardableResult
    mutating func send(_ command: Command, ack: Set<WarningID> = Set(WarningID.allCases)) -> StepResult {
        let before = engine.state
        let result = engine.perform(command, acknowledging: ack)
        let out = JournalRecorder.record(JournalStep(command: command, before: before, result: result, after: engine.state),
                                         into: &journal)
        outputs.append(out)
        steps += 1
        return result
    }

    /// Plays `count` fuzz commands (stopping at game over).
    mutating func fuzz(_ count: Int, seed: UInt64, cheats: Bool = false) {
        var r = Xoshiro256StarStar(seed: seed &* 0x9E37_79B9 &+ 17)
        for _ in 0..<count {
            if case .gameOver = engine.state.phase { break }
            send(InsightsFuzz.pickCommand(engine.state, &r, cheats: cheats))
        }
    }
}

/// The `pmsim fuzz` command picker (Sources/pmsim/Fuzz.swift), duplicated because test targets can't import an
/// executable target. Uses its own RNG, never the game's.
enum InsightsFuzz {
    static func pickCommand(_ s: GameState, _ r: inout Xoshiro256StarStar, cheats: Bool = false) -> Command {
        if s.pendingScoop != nil { return .resolveScoop(accept: r.next(below: 2) == 0) }
        if s.pendingPlunder != nil {
            if r.next(below: 3) == 0 { return .plunderDone }
            return .plunderTake(TradeItemType(rawValue: r.next(below: 10)) ?? .water, quantity: 1 + r.next(below: 3))
        }
        if let offer = s.pendingOrbitTrade { return .resolveTradeInOrbit(quantity: r.next(below: offer.maxQuantity + 1)) }
        switch s.phase {
        case let .encounter(enc):
            var actions = enc.type.actions + [.resolve]
            if enc.continueAttacking || enc.continueFleeing { actions += [.autoRepeat, .autoRepeat, .stop] }
            if r.next(below: 10) == 0 { actions = EncounterAction.allCases }
            return .encounter(actions[r.next(below: actions.count)])
        case .docked:
            let item = TradeItemType(rawValue: r.next(below: 10)) ?? .water
            switch r.next(below: cheats ? 17 : 16) {
            case 0, 1: return .buyCargo(item, quantity: 1 + r.next(below: 8))
            case 2, 3: return .sellCargo(item, quantity: 1 + r.next(below: 8))
            case 4: return .buyFuel(credits: r.next(below: 200))
            case 5: return .repairHull(credits: r.next(below: 300))
            case 6:
                let dests = s.destinations
                return dests.isEmpty ? .buyFuel(credits: 100) : .selectTarget(dests[r.next(below: dests.count)])
            case 7, 8, 9: return .warp
            case 10: return r.next(below: 2) == 0 ? .borrow(1 + r.next(below: 2_000)) : .repay(1 + r.next(below: 2_000))
            case 11: return .buyWeapon(WeaponType(rawValue: r.next(below: 3)) ?? .pulseLaser)
            case 12: return .buyGadget(GadgetType(rawValue: r.next(below: 5)) ?? .extraCargoBays)
            case 13: return .buyShip(ShipType.buyable[r.next(below: 10)], transfers: TransferItem.allCases)
            case 14: return .readNewspaper
            case 16: return .cheat(.enable)
            default: return .dumpCargo(item, quantity: 1)
            }
        default:
            return .warp
        }
    }
}

/// A hand-built entry list builder (ids and days increase as entries are added).
struct EntryBuilder {
    var entries: [LogEntry] = []
    var day = 0
    var system = 0
    var worth = 1_000

    init(start: JournalStart? = nil) {
        if let start { add(.journalStarted(start)) }
    }

    mutating func add(_ kind: LogEntryKind, day: Int? = nil, system: Int? = nil, worth: Int? = nil) {
        if let day { self.day = day }
        if let system { self.system = system }
        if let worth { self.worth = worth }
        entries.append(LogEntry(id: entries.count + 1, day: self.day, system: self.system, worth: self.worth, kind: kind))
    }

    var stats: CareerStats { CareerStats.fold(entries) }

    static func start(_ origin: JournalOrigin = .newGame, ruleset: RulesetID = .modern, difficulty: Difficulty = .normal,
                      ironman: Bool = false, systems: Int = 120, visited: [Int] = [0]) -> JournalStart {
        JournalStart(origin: origin, rulesetID: ruleset, difficulty: difficulty, ironman: ironman, systemCount: systems,
                     startSystem: visited.first ?? 0, visitedSystems: visited, kills: Kills())
    }
}

/// An encounter record with defaults.
func record(_ outcome: EncounterOutcomeKind, type: EncounterType = .pirateAttack, opponent: ShipType = .gnat,
            hull: Int = 50, bounty: Int = 0, kills: Kills = Kills(), surrendered: Bool = false) -> EncounterRecord {
    EncounterRecord(type: type, opponent: opponent, rounds: 2, outcome: outcome, bounty: bounty, minHullPercent: hull,
                    killsAfter: kills, surrendered: surrendered)
}

/// One fixture per `LogEntryKind` case (LOG-009/010/011), with its expected category.
let kindFixtures: [(LogEntryKind, LogCategory)] = [
    (.journalStarted(EntryBuilder.start()), .game),
    (.cheatsEnabled, .game),
    (.gameEnded(.retired, score: 10), .game),
    (.achievementUnlocked(.firstProfit), .achievement),
    (.trade(TradeEntry(action: .sell, item: .ore, quantity: 2, total: 100, profit: 20)), .trade),
    (.departed(from: 0, to: 1, viaWormhole: false, parsecs: 5), .travel),
    (.arrived(TripArrival(system: 1, from: 0, viaWormhole: false, firstVisit: true, uneventful: true, encounterCount: 0)), .travel),
    (.fabricRip(newDestination: 3), .travel),
    (.singularityLost, .travel),
    (.encounter(record(.escaped)), .encounter),
    (.police(.arrested(term: 30, fine: 100, shipSold: false)), .police),
    (.finance(.borrowed(amount: 500)), .finance),
    (.ship(.fuel(units: 3, cost: 6)), .ship),
    (.crew(.hired(crewID: 4)), .crew),
    (.quest(.completed(.lottery)), .quest),
    (.news(NewsEntry(headlines: [.internalPressure(.war)], cost: 2)), .news),
    (.status(.policeRecord(from: .clean, to: .dubious)), .status),
]
