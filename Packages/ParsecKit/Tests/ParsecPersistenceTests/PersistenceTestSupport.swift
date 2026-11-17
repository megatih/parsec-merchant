// SPDX-License-Identifier: GPL-2.0-or-later
// Shared helpers for the persistence tests: temporary store roots, fixed game states and fuzz-played states.
import Foundation
@testable import ParsecEngine
import ParsecInsights
@testable import ParsecPersistence

/// A fresh, empty directory under the temporary directory; remove it with `cleanUp`.
func makeTempRoot() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pm-persist-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func cleanUp(_ url: URL) { try? FileManager.default.removeItem(at: url) }

/// A new game state for `ruleset`.
func newState(_ ruleset: RulesetID = .modern, seed: UInt64 = 42, name: String = "Tester", ironman: Bool = false) -> GameState {
    GameState(config: NewGameConfig(commanderName: name, ruleset: ruleset, seed: seed, ironman: ironman))
}

/// File names in a directory (sorted), or [] when it does not exist.
func fileNames(_ dir: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
}

/// The fuzz command picker of `pmsim fuzz` (Sources/pmsim/Fuzz.swift), duplicated because test targets can't
/// import an executable target. Uses its own RNG, never the game's.
enum FuzzPlayer {
    static let ackAll = Set(WarningID.allCases)

    static func pickCommand(_ s: GameState, _ r: inout Xoshiro256StarStar) -> Command {
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

    /// A coarse phase label used to make sure the sample covers every phase and pending decision.
    static func category(_ s: GameState) -> String {
        if s.pendingScoop != nil { return "scoop" }
        if s.pendingPlunder != nil { return "plunder" }
        if s.pendingOrbitTrade != nil { return "orbitTrade" }
        switch s.phase {
        case .docked: return "docked"
        case .inTransit: return "transit"
        case .encounter: return "encounter"
        case .gameOver: return "gameOver"
        }
    }

    /// Kills are rare in random play, so a fork of an encounter is armed (opponent at 1 hull with cargo, player with
    /// military lasers) and attacked until the scoop decision opens. Nil when it doesn't within 30 rounds.
    static func forcedScoop(_ base: GameEngine) -> GameState? {
        guard case var .encounter(enc) = base.state.phase, enc.type.actions.contains(.attack) else { return nil }
        var probe = base
        enc.opponent.hull = 1
        enc.opponent.cargo = enc.opponent.cargo.map { _ in 2 }
        probe.state.phase = .encounter(enc)
        probe.state.commander.ship.weapons = [.militaryLaser]
        for _ in 0..<30 {
            probe.perform(.encounter(.attack), acknowledging: ackAll)
            if probe.state.pendingScoop != nil { return probe.state }
            guard case .encounter = probe.state.phase else { return nil }
        }
        return nil
    }

    /// `count` states of `ruleset` sampled from random legal-command games (the `pmsim fuzz` approach). States are
    /// bucketed by category and drawn round-robin, so rare phases (scoop, plunder, orbit trade, game over) are always
    /// represented; some games are ended by retiring, and the persistence-only flags (cheats, reloads, Ironman) vary.
    static func sampleStates(_ ruleset: RulesetID, count: Int, seed: UInt64, games: Int = 40) -> [GameState] {
        sampleGames(ruleset, count: count, seed: seed, games: games).map(\.state)
    }

    /// LOG-003: like `sampleStates`, with the journal recorded alongside each game (as `pmsim` records it).
    static func sampleGames(_ ruleset: RulesetID, count: Int, seed: UInt64,
                            games: Int = 40) -> [(state: GameState, journal: GameJournal)] {
        let order = ["docked", "encounter", "scoop", "plunder", "orbitTrade", "transit", "gameOver"]
        var buckets: [String: [(state: GameState, journal: GameJournal)]] = [:]
        for game in 0..<UInt64(games) {
            let gameSeed = seed &+ game
            var engine = GameEngine(config: NewGameConfig(commanderName: game % 3 == 0 ? "Zoë 🚀 \"/\\" : "Fuzz",
                                                          difficulty: Difficulty(rawValue: Int(game % 5)) ?? .normal,
                                                          ruleset: ruleset, seed: gameSeed, ironman: game % 4 == 1))
            var r = Xoshiro256StarStar(seed: gameSeed &* 0x9E37_79B9 &+ 17)
            var journal = GameJournal.start(state: engine.state)
            for step in 0..<300 {
                if case .gameOver = engine.state.phase { break }
                let command = pickCommand(engine.state, &r)
                let before = engine.state
                let result = engine.perform(command, acknowledging: ackAll)
                JournalRecorder.record(JournalStep(command: command, before: before, result: result, after: engine.state), into: &journal)
                let cat = category(engine.state)
                let common = cat == "docked" || cat == "encounter"
                guard buckets[cat, default: []].count < count, !common || step % 13 == 0 else { continue }
                var s = engine.state
                s.cheatsUsed = step % 3 == 0
                s.reloadCount = step % 5
                buckets[cat, default: []].append((s, journal))
                if cat == "encounter", buckets["scoop", default: []].count < count / 10, let scoop = forcedScoop(engine) {
                    buckets["scoop", default: []].append((scoop, journal))
                }
            }
            if game % 3 == 2, case .docked = engine.state.phase {
                let before = engine.state
                let result = engine.perform(.retire, acknowledging: ackAll)
                JournalRecorder.record(JournalStep(command: .retire, before: before, result: result, after: engine.state), into: &journal)
                buckets["gameOver", default: []].append((engine.state, journal))
            }
        }
        var out: [(state: GameState, journal: GameJournal)] = []
        var index = 0
        while out.count < count {
            var added = false
            for cat in order where out.count < count {
                if let bucket = buckets[cat], index < bucket.count {
                    out.append(bucket[index])
                    added = true
                }
            }
            if !added { break }
            index += 1
        }
        return out
    }
}
