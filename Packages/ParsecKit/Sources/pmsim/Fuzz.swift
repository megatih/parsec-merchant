// SPDX-License-Identifier: GPL-2.0-or-later
// pmsim fuzz: random legal-command games with invariants and determinism replays (PRD §8.1 step 3).
import Foundation
import ParsecEngine
import ParsecInsights
import ParsecPersistence

struct Fuzzer {
    let ruleset: RulesetID
    var violations: [String] = []

    /// Every warning acknowledged: the fuzzer explores consequences too.
    static let ackAll = Set(WarningID.allCases)

    /// Chooses a command for the current state using the fuzzer's own RNG (never the game's).
    static func pickCommand(_ s: GameState, _ r: inout Xoshiro256StarStar) -> Command {
        if s.pendingScoop != nil { return .resolveScoop(accept: r.next(below: 2) == 0) }
        if s.pendingPlunder != nil {
            if r.next(below: 3) == 0 { return .plunderDone }
            return .plunderTake(TradeItemType(rawValue: r.next(below: 10)) ?? .water, quantity: 1 + r.next(below: 3))
        }
        if let offer = s.pendingOrbitTrade { return .resolveTradeInOrbit(quantity: r.next(below: offer.maxQuantity + 1)) }
        switch s.phase {
        case let .encounter(enc):
            // Mostly offered actions (ENC-130), sometimes any action to exercise the rejections.
            var actions = enc.type.actions + [.resolve]
            if enc.continueAttacking || enc.continueFleeing { actions += [.autoRepeat, .autoRepeat, .stop] }
            if r.next(below: 10) == 0 { actions = EncounterAction.allCases }
            return .encounter(actions[r.next(below: actions.count)])
        case .docked:
            let item = TradeItemType(rawValue: r.next(below: 10)) ?? .water
            switch r.next(below: 16) {
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
            default: return .dumpCargo(item, quantity: 1)
            }
        default:
            return .warp
        }
    }

    mutating func check(_ s: GameState, game: Int, step: Int, command: Command, cashBefore: Int) {
        let r = s.ruleset
        let ship = s.commander.ship
        func fail(_ msg: String) { violations.append("\(ruleset) game \(game) step \(step): \(msg)") }
        if ship.cargo.contains(where: { $0 < 0 }) { fail("negative cargo") }
        if s.galaxy.systems.contains(where: { $0.tradeItems.contains { $0 < 0 } }) { fail("negative stock") }
        if s.filledCargoBays > ship.cargoBays(r) { fail("cargo \(s.filledCargoBays) > bays \(ship.cargoBays(r))") }
        if ship.hull < 0 || ship.hull > ship.hullStrength(r) { fail("hull \(ship.hull)") }
        if ship.fuel < 0 || ship.fuel > ship.fuelTanks(r) { fail("fuel \(ship.fuel)") }
        if ship.crewCount > ship.spec(r).crewQuarters { fail("crew > quarters") }
        if ship.weapons.count > ship.spec(r).weaponSlots || ship.shields.count > ship.spec(r).shieldSlots
            || ship.gadgets.count > ship.spec(r).gadgetSlots { fail("equipment > slots") }
        if s.commander.debt < 0 { fail("negative debt") }
        // Cash may only cross below zero through a documented source quirk: the C# trade-in-orbit cap (ECO-068) or
        // Palm's dump-cap precedence bug (RUL-043). Any other command that takes cash from ≥ 0 to < 0 is a violation.
        if cashBefore >= 0, s.commander.cash < 0 {
            let orbitQuirk: Bool = if case .resolveTradeInOrbit = command { !r.flags.tradeInOrbitCashCapUsesOrbitPrice } else { false }
            let dumpQuirk: Bool = if case .dumpCargo = command { r.flags.economy.dumpQuantityCap == .precedenceBug } else { false }
            if !orbitQuirk, !dumpQuirk { fail("cash went negative (\(cashBefore) → \(s.commander.cash)) on \(command)") }
        }
        if case let .encounter(enc) = s.phase {
            // ENC-192: the action set is never empty; a disabled opponent is in a disabled type or a quest ship.
            if enc.type.actions.isEmpty { fail("empty action set for \(enc.type)") }
            let disabledTypes: [EncounterType] = [.pirateDisabled, .policeDisabled, .traderDisabled, .famousCaptDisabled]
            if enc.opponentDisabled, !disabledTypes.contains(enc.type), ![.dragonfly, .scarab, .scorpion].contains(enc.opponent.type) {
                fail("disabled opponent in \(enc.type)")
            }
            if enc.opponent.hull <= 0, s.pendingScoop == nil { fail("encounter open with destroyed opponent") }
        }
        if s.quests.reactor < 0 || s.quests.reactor > 22 || s.quests.princess > 16 || s.quests.dragonfly > 6 { fail("quest status out of range") }
    }

    /// LOG-037: journal invariants after a step. `visited` tracks the systems the journal has seen visited.
    mutating func checkJournal(_ journal: GameJournal, from first: Int, rejected: Bool, state s: GameState, visited: inout [Bool],
                               game: Int, step: Int) {
        func fail(_ msg: String) { violations.append("\(ruleset) game \(game) step \(step): journal \(msg)") }
        if rejected, journal.entries.count != first { fail("entry appended for a rejected step") }
        var previous = first > 0 ? journal.entries[first - 1] : nil
        for entry in journal.entries[first...] {
            if let p = previous, entry.id <= p.id || entry.day < p.day { fail("ids or days out of order at entry \(entry.id)") }
            if !s.galaxy.systems.indices.contains(entry.system) { fail("entry \(entry.id) has system \(entry.system)") }
            switch entry.kind {
            case let .journalStarted(start): for i in start.visitedSystems where visited.indices.contains(i) { visited[i] = true }
            case let .arrived(a) where visited.indices.contains(a.system): visited[a.system] = true
            default: break
            }
            previous = entry
        }
        for (i, sys) in s.galaxy.systems.enumerated() where sys.visited != visited[i] {
            fail("visited systems differ at \(i)")
            break
        }
    }

    /// Plays one game with a journal; returns the command log, the final state's canonical JSON and the journal.
    mutating func play(game: Int, seed: UInt64, maxCommands: Int) -> ([Command], Data, GameJournal) {
        var engine = GameEngine(config: NewGameConfig(commanderName: "Fuzz", difficulty: Difficulty(rawValue: game % 5) ?? .normal,
                                                      ruleset: ruleset, seed: seed))
        var r = Xoshiro256StarStar(seed: seed &* 0x9E37_79B9 &+ 17)
        var log: [Command] = []
        var journal = GameJournal.start(state: engine.state)
        var visited = [Bool](repeating: false, count: engine.state.galaxy.systems.count)
        checkJournal(journal, from: 0, rejected: false, state: engine.state, visited: &visited, game: game, step: -1)
        for step in 0..<maxCommands {
            if case .gameOver = engine.state.phase { break }
            let cmd = Self.pickCommand(engine.state, &r)
            log.append(cmd)
            let before = engine.state
            let result = engine.perform(cmd, acknowledging: Self.ackAll)
            check(engine.state, game: game, step: step, command: cmd, cashBefore: before.commander.cash)
            let first = journal.entries.count
            JournalRecorder.record(JournalStep(command: cmd, before: before, result: result, after: engine.state), into: &journal)
            checkJournal(journal, from: first, rejected: result.rejection != nil, state: engine.state, visited: &visited,
                         game: game, step: step)
        }
        return (log, Self.canonical(engine.state), journal)
    }

    /// LOG-037: the journal round-trips byte-identically through `SaveCodec` beside the final state.
    static func journalRoundTrips(_ journal: GameJournal, state: GameState) -> Bool {
        let envelope = SaveEnvelope(state: state, appVersion: "fuzz", gameID: "fuzz", generation: 1, journal: journal)
        guard let bytes = try? SaveCodec.encode(envelope), let decoded = try? SaveCodec.decode(bytes),
              let again = try? SaveCodec.encode(decoded) else { return false }
        return decoded.journal == journal && again == bytes
    }

    static func canonical(_ s: GameState) -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return (try? enc.encode(s)) ?? Data()
    }

    /// Replays a log; returns the final state's canonical JSON, the state and the journal recorded again (LOG-014).
    static func replay(_ log: [Command], ruleset: RulesetID, game: Int, seed: UInt64) -> (Data, GameState, GameJournal) {
        var engine = GameEngine(config: NewGameConfig(commanderName: "Fuzz", difficulty: Difficulty(rawValue: game % 5) ?? .normal,
                                                      ruleset: ruleset, seed: seed))
        var journal = GameJournal.start(state: engine.state)
        for cmd in log {
            let before = engine.state
            let result = engine.perform(cmd, acknowledging: ackAll)
            JournalRecorder.record(JournalStep(command: cmd, before: before, result: result, after: engine.state), into: &journal)
        }
        return (canonical(engine.state), engine.state, journal)
    }
}

/// Runs the fuzz campaign; returns the process exit code.
func runFuzz(games: Int, seed: UInt64, rulesets: [RulesetID], maxCommands: Int) -> Int32 {
    var failures = 0
    let start = Date()
    for ruleset in rulesets {
        var fuzzer = Fuzzer(ruleset: ruleset)
        var commands = 0
        for g in 0..<games {
            let gameSeed = seed &+ UInt64(g)
            let (log, final, journal) = fuzzer.play(game: g, seed: gameSeed, maxCommands: maxCommands)
            commands += log.count
            if (try? JSONSerialization.jsonObject(with: final)) == nil { fuzzer.violations.append("game \(g): encode failed") }
            if g % 50 == 0 {
                let (again, state, replayed) = Fuzzer.replay(log, ruleset: ruleset, game: g, seed: gameSeed)
                if again != final { fuzzer.violations.append("\(ruleset) game \(g): replay diverged (non-deterministic)") }
                if replayed != journal { fuzzer.violations.append("\(ruleset) game \(g): journal replay diverged (LOG-014)") }
                if !Fuzzer.journalRoundTrips(journal, state: state) {
                    fuzzer.violations.append("\(ruleset) game \(g): journal round trip not byte-identical (LOG-037)")
                }
            }
        }
        failures += fuzzer.violations.count
        print("fuzz \(ruleset): \(games) games, \(commands) commands, \(fuzzer.violations.count) violations")
        for v in fuzzer.violations.prefix(20) { print("  - \(v)") }
    }
    print(String(format: "fuzz finished in %.1fs", Date().timeIntervalSince(start)))
    return failures == 0 ? 0 : 1
}
