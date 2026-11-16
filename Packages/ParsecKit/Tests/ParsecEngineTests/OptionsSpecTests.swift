// SPDX-License-Identifier: GPL-2.0-or-later
// OPT {M6}: per-save game options: model, defaults, setOptions and normalization, and the behaviour map (docs/specs/OPT.md).
import Foundation
import Testing
@testable import ParsecEngine

/// Shared helpers for the OPT spec tests.
enum OptKit {
    /// Every `options.<field>` read in the engine sources outside the model file, as field → files.
    static func optionReads() throws -> [String: Set<String>] {
        var reads: [String: Set<String>] = [:]
        let pattern = /options\.([a-zA-Z]+)/
        for (name, text) in try RNGContractTests.engineSources() where name != "GameState.swift" {
            for m in text.matches(of: pattern) { reads[String(m.1), default: []].insert(name) }
        }
        return reads
    }

    /// Runs `body` on two copies of `base` (`option` as in `base` / on) from successive RNG positions.
    static func pairs(_ base: GameState, count: Int = 400, flip option: WritableKeyPath<GameOptions, Bool>,
                      _ body: (GameState, GameState) -> Void) {
        var s = base
        for _ in 0..<count {
            var on = s
            on.options[keyPath: option] = true
            body(s, on)
            _ = s.rng.next(below: 1_000)
        }
    }

    /// An option-free state change comparison: `a` and `b` are equal apart from their options.
    static func sameApartFromOptions(_ a: GameState, _ b: GameState) -> Bool {
        var b2 = b
        b2.options = a.options
        return a == b2
    }
}

@Suite("OPT §1: model and defaults")
struct OptionsModelTests {
    @Test("OPT-001 GameOptions encodes exactly the 16 C# options under their keys")
    func keys() throws {
        let data = try JSONEncoder().encode(GameOptions())
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["alwaysIgnorePirates", "alwaysIgnorePolice", "alwaysIgnoreTradeInOrbit", "alwaysIgnoreTraders",
                                     "autoFuel", "autoRepair", "continuousAttack", "continuousAttackFleeing", "disableOpponents",
                                     "newsAutoPay", "newsAutoShow", "remindLoans", "reserveMoney", "showTrackedRange",
                                     "trackAutoOff", "leaveEmpty"])
        #expect(object["leaveEmpty"] is Int && object.filter { $0.key != "leaveEmpty" }.allSatisfy { $0.value is Bool })
        #expect(Mirror(reflecting: GameOptions()).children.count == 16)
        #expect(try JSONDecoder().decode(GameOptions.self, from: data) == GameOptions())
    }

    @Test("OPT-002 GameOptions() has the C# defaults: traders ignored, loan reminders, tracked range and auto-off on")
    func windowsDefaults() {
        let o = GameOptions()
        #expect(!o.alwaysIgnorePirates && !o.alwaysIgnorePolice && !o.alwaysIgnoreTradeInOrbit && o.alwaysIgnoreTraders)
        #expect(!o.autoFuel && !o.autoRepair && !o.continuousAttack && !o.continuousAttackFleeing && !o.disableOpponents)
        #expect(!o.newsAutoPay && !o.newsAutoShow && o.remindLoans && !o.reserveMoney && o.showTrackedRange && o.trackAutoOff)
        #expect(o.leaveEmpty == 0)
    }

    @Test("OPT-003 Palm defaults: police ignored, traders not ignored; the rest as OPT-002")
    func palmDefaults() {
        let p = GameOptions.defaults(for: .palm122)
        var expected = GameOptions()
        expected.alwaysIgnorePolice = true
        expected.alwaysIgnoreTraders = false
        #expect(p == expected)
        #expect(!p.newsAutoShow && !p.disableOpponents)
    }

    @Test("OPT-004 defaults(for:) per ruleset; NewGameConfig.options defaults to nil; new games use defaults or normalized options")
    func newGameOptions() {
        #expect(GameOptions.defaults(for: .modern) == GameOptions() && GameOptions.defaults(for: .windows201) == GameOptions())
        #expect(NewGameConfig(commanderName: "A", seed: 1).options == nil)
        for id in RulesetID.allCases {
            let plain = GameState(config: NewGameConfig(commanderName: "A", ruleset: id, seed: 1))
            #expect(plain.options == GameOptions.defaults(for: id))
            var given = GameOptions()
            given.continuousAttackFleeing = true
            given.continuousAttack = false
            given.leaveEmpty = 400
            given.autoFuel = true
            let s = GameState(config: NewGameConfig(commanderName: "A", ruleset: id, seed: 1, options: given))
            var expected = given.normalized(for: Ruleset.named(id))
            expected.remindLoans = true
            expected.showTrackedRange = true
            #expect(s.options == expected && s.options.leaveEmpty == 99 && s.options.autoFuel)
        }
    }

    @Test("OPT-005 a new Palm game always starts with remindLoans and showTrackedRange on; other options are kept")
    func palmForced() {
        var given = GameOptions.defaults(for: .palm122)
        given.remindLoans = false
        given.showTrackedRange = false
        given.reserveMoney = true
        given.continuousAttackFleeing = true
        let s = GameState(config: NewGameConfig(commanderName: "P", ruleset: .palm122, seed: 2, options: given))
        #expect(s.options.remindLoans && s.options.showTrackedRange && s.options.reserveMoney && s.options.continuousAttackFleeing)
    }

    @Test("OPT-006 a new Modern or Windows game stores the given options (normalized) with nothing forced")
    func windowsGiven() {
        var given = GameOptions()
        given.remindLoans = false
        given.showTrackedRange = false
        given.trackAutoOff = false
        given.alwaysIgnoreTraders = false
        for id in [RulesetID.modern, .windows201] {
            let s = GameState(config: NewGameConfig(commanderName: "W", ruleset: id, seed: 2, options: given))
            #expect(s.options == given)
        }
    }
}

@Suite("OPT §2: changing options")
struct OptionsChangeTests {
    @Test("OPT-007 setOptions: docked only (notAllowedInPhase / gameOver), stores normalized, emits optionsChanged, no draws, nothing else")
    func setOptions() {
        for id in RulesetID.allCases {
            var e = makeEngine(id) { s in
                s.cheatsUsed = true
                s.reloadCount = 2
                s.ironman = true
            }
            let before = e.state
            var o = GameOptions()
            o.autoFuel = true
            o.leaveEmpty = 250
            let r = e.perform(.setOptions(o))
            #expect(r.rejection == nil && r.events == [.optionsChanged] && r.decision == nil)
            #expect(e.state.options == o.normalized(for: e.ruleset) && e.state.options.leaveEmpty == 99)
            #expect(OptKit.sameApartFromOptions(before, e.state) && e.state.rng == before.rng)
            #expect(e.state.cheatsUsed && e.state.reloadCount == 2 && e.state.ironman)
        }
        var enc = EncSpec.encounter(.pirateAttack)
        #expect(enc.perform(.setOptions(GameOptions())).rejection == .notAllowedInPhase)
        var transit = makeEngine { s in s.phase = .inTransit(TransitState(destination: 1, clicksRemaining: 2, viaWormhole: false)) }
        #expect(transit.perform(.setOptions(GameOptions())).rejection == .notAllowedInPhase)
        var pending = makeEngine { $0.pendingScoop = .food }
        #expect(pending.perform(.setOptions(GameOptions())).rejection == .notAllowedInPhase)
        var over = makeEngine { $0.phase = .gameOver(.killed) }
        #expect(over.perform(.setOptions(GameOptions())).rejection == .gameOver)
    }

    @Test("OPT-008 Modern/Windows dependencies: an off parent forces its dependent off; an on parent leaves it as given")
    func dependencies() {
        for id in [RulesetID.modern, .windows201] {
            let r = Ruleset.named(id)
            #expect(r.flags.optionDependencies)
            var o = GameOptions()
            o.continuousAttack = false
            o.continuousAttackFleeing = true
            o.alwaysIgnoreTraders = false
            o.alwaysIgnoreTradeInOrbit = true
            o.newsAutoPay = false
            o.newsAutoShow = true
            let n = o.normalized(for: r)
            #expect(!n.continuousAttackFleeing && !n.alwaysIgnoreTradeInOrbit && !n.newsAutoShow)
            o.continuousAttack = true
            o.alwaysIgnoreTraders = true
            o.newsAutoPay = true
            #expect(o.normalized(for: r) == o)
            var off = o
            off.continuousAttackFleeing = false
            off.alwaysIgnoreTradeInOrbit = false
            off.newsAutoShow = false
            #expect(off.normalized(for: r) == off)
        }
    }

    @Test("OPT-009 Palm has no dependencies; newsAutoShow and disableOpponents are forced off there")
    func palmNormalization() {
        let r = Ruleset.palm122
        #expect(!r.flags.optionDependencies)
        var o = GameOptions()
        o.continuousAttack = false
        o.continuousAttackFleeing = true
        o.alwaysIgnoreTraders = false
        o.alwaysIgnoreTradeInOrbit = true
        o.newsAutoPay = true
        o.newsAutoShow = true
        o.disableOpponents = true
        let n = o.normalized(for: r)
        #expect(n.continuousAttackFleeing && n.alwaysIgnoreTradeInOrbit && n.newsAutoPay)
        #expect(!n.newsAutoShow && !n.disableOpponents)
        var e = makeEngine(.palm122)
        _ = e.perform(.setOptions(o))
        #expect(e.state.options == n)
    }

    @Test("OPT-010 leaveEmpty is clamped to 0…99 in every ruleset")
    func leaveEmptyClamp() {
        for id in RulesetID.allCases {
            for (v, want) in [(-5, 0), (0, 0), (42, 42), (99, 99), (100, 99), (9_999, 99)] {
                var o = GameOptions()
                o.leaveEmpty = v
                #expect(o.normalized(for: Ruleset.named(id)).leaveEmpty == want)
            }
        }
    }

    @Test("OPT-011 options act at their next read point, never retroactively (autoFuel buys nothing now; newsAutoPay pays nothing)")
    func notRetroactive() {
        for id in RulesetID.allCases {
            var e = makeEngine(id) { s in
                s.commander.ship.fuel = 1
                s.commander.ship.hull = 1
                s.commander.cash = 50_000
            }
            let before = e.state
            var o = e.state.options
            o.autoFuel = true
            o.autoRepair = true
            o.newsAutoPay = true
            _ = e.perform(.setOptions(o))
            #expect(e.state.commander.ship.fuel == 1 && e.state.commander.ship.hull == 1)
            #expect(e.state.commander.cash == before.commander.cash && !e.state.paidForNewspaper)
            // The next arrival does read them.
            e.state.warpSystem = e.state.commander.currentSystem
            _ = e.state.arrival()
            #expect(e.state.commander.ship.fuel == e.state.commander.ship.fuelTanks(e.ruleset))
        }
    }

    @Test("OPT-012 decoding keeps options that break the dependencies; the next setOptions normalizes them")
    func decodeKeeps() throws {
        var e = makeEngine(.windows201)
        e.state.options.continuousAttack = false
        e.state.options.continuousAttackFleeing = true
        e.state.options.leaveEmpty = 500
        var decoded = GameEngine(state: try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(e.state)))
        #expect(decoded.state.options.continuousAttackFleeing && decoded.state.options.leaveEmpty == 500)
        _ = decoded.perform(.setOptions(decoded.state.options))
        #expect(!decoded.state.options.continuousAttackFleeing && decoded.state.options.leaveEmpty == 99)
    }
}

@Suite("OPT §3: what each option controls")
struct OptionsBehaviourTests {
    @Test("OPT-013 autoFuel/autoRepair act only in the arrival auto-buy (all-or-nothing C#, partial Palm); manual purchases ignore them")
    func autoBuy() throws {
        #expect(try OptKit.optionReads()["autoFuel"] == ["Travel.swift"] && OptKit.optionReads()["autoRepair"] == ["Travel.swift"])
        for id in RulesetID.allCases {
            for cash in [100_000, 10] {
                let base = makeEngine(id) { s in
                    s.commander.ship.fuel = 0
                    s.commander.ship.hull = 1
                    s.commander.cash = cash
                    s.warpSystem = s.commander.currentSystem
                }.state
                var off = base, on = base
                on.options.autoFuel = true
                on.options.autoRepair = true
                _ = off.arrival()
                let events = on.arrival()
                let tanks = on.commander.ship.fuelTanks(on.ruleset)
                if cash == 100_000 {
                    #expect(off.commander.ship.fuel == 0 && on.commander.ship.fuel == tanks)
                    #expect(on.commander.ship.hull == on.commander.ship.hullStrength(on.ruleset))
                } else if id == .palm122 {
                    #expect(on.commander.ship.fuel > 0 && on.commander.ship.fuel < tanks && events.contains(.autoFuelFailed))
                } else {
                    #expect(on.commander.ship.fuel == 0 && on.commander.cash == cash && events.contains(.autoFuelFailed))
                }
            }
            // Manual purchases are the same with the options on or off.
            var m1 = makeEngine(id) { $0.commander.ship.fuel = 0 }
            var m2 = m1
            m2.state.options.autoFuel = true
            m2.state.options.autoRepair = true
            #expect(m1.perform(.buyFuel(credits: 20)) == m2.perform(.buyFuel(credits: 20)))
            #expect(m1.state.commander.ship.fuel == m2.state.commander.ship.fuel)
        }
    }

    @Test("OPT-014 alwaysIgnorePirates only skips non-attacking pirate encounters")
    func ignorePirates() throws {
        #expect(try OptKit.optionReads()["alwaysIgnorePirates"] == ["Travel.swift"])
        for id in RulesetID.allCases {
            var skipped = 0, kept = 0
            let base = makeEngine(id) { $0.commander.reputationScore = 2_000 }.state
            OptKit.pairs(base, flip: \.alwaysIgnorePirates) { off, on in
                var a = off, b = on
                let ea = a.determinePirate(mantis: false, clicks: 5), eb = b.determinePirate(mantis: false, clicks: 5)
                #expect(OptKit.sameApartFromOptions(a, b))
                if let ea, ea.type != .pirateAttack {
                    #expect(eb == nil)
                    skipped += 1
                } else {
                    #expect(eb == ea)
                    if ea != nil { kept += 1 }
                }
            }
            #expect(skipped > 0 && kept > 0, "\(id)")
        }
    }

    @Test("OPT-015 alwaysIgnorePolice skips every police type except attack and inspect (surrender included in C#)")
    func ignorePolice() throws {
        #expect(try OptKit.optionReads()["alwaysIgnorePolice"] == ["Travel.swift"])
        for id in RulesetID.allCases {
            var skippedTypes: Set<EncounterType> = [], keptTypes: Set<EncounterType> = []
            for record in [-30, -2, 0, 3] {
                let base = makeEngine(id) { s in
                    s.commander.policeRecordScore = record
                    s.commander.reputationScore = 0
                    s.options.alwaysIgnorePolice = false
                }.state
                OptKit.pairs(base, count: 150, flip: \.alwaysIgnorePolice) { off, on in
                    var a = off, b = on
                    let ea = a.determinePolice(clicks: 5), eb = b.determinePolice(clicks: 5)
                    #expect(OptKit.sameApartFromOptions(a, b))
                    guard let ea else {
                        #expect(eb == nil)
                        return
                    }
                    if ea.type == .policeAttack || ea.type == .policeInspect {
                        #expect(eb == ea)
                        keptTypes.insert(ea.type)
                    } else {
                        #expect(eb == nil)
                        skippedTypes.insert(ea.type)
                    }
                }
            }
            #expect(skippedTypes.contains(.policeIgnore) && keptTypes.contains(.policeInspect), "\(id)")
            if id != .palm122 { #expect(skippedTypes.contains(.policeSurrender)) }
        }
    }

    @Test("OPT-016 alwaysIgnoreTraders skips trader ignore/flee; alwaysIgnoreTradeInOrbit skips buy/sell offers")
    func ignoreTraders() throws {
        let reads = try OptKit.optionReads()
        #expect(reads["alwaysIgnoreTraders"] == ["Travel.swift"] && reads["alwaysIgnoreTradeInOrbit"] == ["Travel.swift"])
        for id in RulesetID.allCases {
            var seen: Set<EncounterType> = []
            for (record, chance) in [(-100, 0), (0, 0), (0, 1_000)] {
                let base = makeEngine(id) { s in
                    s.commander.policeRecordScore = record
                    s.commander.reputationScore = 2_000
                    s.chanceOfTradeInOrbit = chance
                    s.commander.cash = 100_000
                    s.commander.ship.cargo[0] = 5
                    s.options.alwaysIgnoreTraders = false
                    s.options.alwaysIgnoreTradeInOrbit = false
                }.state
                for flag in [0, 1] {
                    OptKit.pairs(base, count: 150, flip: flag == 0 ? \.alwaysIgnoreTraders : \.alwaysIgnoreTradeInOrbit) { off, on in
                        var a = off, b = on
                        let ea = a.determineTrader(clicks: 5), eb = b.determineTrader(clicks: 5)
                        #expect(OptKit.sameApartFromOptions(a, b))
                        guard let ea else {
                        #expect(eb == nil)
                        return
                    }
                        seen.insert(ea.type)
                        let skips: Set<EncounterType> = flag == 0 ? [.traderIgnore, .traderFlee] : [.traderBuy, .traderSell]
                        #expect(skips.contains(ea.type) ? eb == nil : eb == ea)
                    }
                }
            }
            #expect(seen.contains(.traderIgnore) && seen.contains(.traderFlee) && !seen.isDisjoint(with: [.traderBuy, .traderSell]), "\(id) \(seen)")
        }
    }

    @Test("OPT-017 leaveEmpty reduces the free bays only for market purchases; trade in orbit ignores it")
    func leaveEmpty() throws {
        #expect(try OptKit.optionReads()["leaveEmpty"] == ["Market.swift"])
        for id in RulesetID.allCases {
            var a = makeEngine(id) { s in
                setMarket(&s, buy: 10, sell: 9, stock: 100)
                s.commander.cash = 100_000
            }
            var b = a
            b.state.options.leaveEmpty = 4
            let free = a.state.freeCargoBays
            #expect(b.perform(.buyCargo(.water, quantity: free - 3)).rejection == .invalidQuantity)
            #expect(a.perform(.buyCargo(.water, quantity: free)).rejection == nil)
            #expect(b.perform(.buyCargo(.water, quantity: free - 4)).rejection == nil)
            #expect(a.state.commander.ship.cargo[0] == free && b.state.commander.ship.cargo[0] == free - 4)
            var t = makeEngine(id) { $0.commander.cash = 100_000 }
            var trader = Ship(type: .beetle, spec: t.ruleset.tables.ship(.beetle))
            trader.cargo[1] = 50
            var u = t
            u.state.options.leaveEmpty = 4
            let o1 = t.state.makeOrbitTradeOffer(direction: .traderSells, trader: trader)
            let o2 = u.state.makeOrbitTradeOffer(direction: .traderSells, trader: trader)
            #expect(o1 != nil && o1 == o2 && o1?.maxQuantity == t.state.freeCargoBays)
        }
    }

    @Test("OPT-018 reserveMoney changes only cash-to-spend: C# reserves all current costs, Palm mercenaries and insurance")
    func reserveMoney() throws {
        #expect(try OptKit.optionReads()["reserveMoney"] == ["ShipMath.swift"])
        for id in RulesetID.allCases {
            var s = makeEngine(id) { s in
                s.commander.cash = 10_000
                s.commander.debt = 1_000
                s.commander.ship.escapePod = true
                s.commander.insurance = true
            }.state
            #expect(s.cashToSpend == 10_000)
            s.options.reserveMoney = true
            let expected = id == .palm122 ? 10_000 - s.mercenaryCosts - s.insuranceCosts : 10_000 - s.currentCosts
            #expect(s.cashToSpend == expected && s.interestCosts > 0)
        }
    }

    @Test("OPT-019 newsAutoPay pays an affordable paper without asking; newsAutoShow is never read by the engine")
    func news() throws {
        let reads = try OptKit.optionReads()
        #expect(reads["newsAutoPay"] == ["Newspaper.swift"] && reads["newsAutoShow"] == nil)
        for id in RulesetID.allCases {
            var asks = makeEngine(id)
            #expect(asks.perform(.readNewspaper).decision == .confirm(ParsecEngine.Confirmation(.buyNewspaper, amounts: [asks.state.newspaperCost])))
            var pays = makeEngine(id)
            pays.state.options.newsAutoPay = true
            let cash = pays.state.commander.cash
            let r = pays.perform(.readNewspaper)
            #expect(r.rejection == nil && pays.state.paidForNewspaper && pays.state.commander.cash == cash - pays.state.newspaperCost)
        }
    }

    @Test("OPT-020 remindLoans gates only the 5-day debt reminder; the large-debt warning is unaffected")
    func remindLoans() throws {
        #expect(try OptKit.optionReads()["remindLoans"] == ["PalmArrival.swift"])
        for id in RulesetID.allCases {
            var s = makeEngine(id) { s in
                s.commander.debt = 500
                s.commander.days = 10
            }.state
            #expect(s.debtNotices() == [.debtReminder(debt: 500)])
            s.options.remindLoans = false
            #expect(s.debtNotices().isEmpty)
            s.commander.debt = 80_000
            #expect(s.debtNotices() == [.debtWarning(debt: 80_000)])
        }
    }

    @Test("OPT-021 trackAutoOff clears the tracked system on arrival there, including the direct-warp cheat")
    func trackAutoOff() throws {
        #expect(try OptKit.optionReads()["trackAutoOff"] == ["Travel.swift", "PalmArrival.swift"])
        for id in RulesetID.allCases {
            for on in [true, false] {
                var s = makeEngine(id).state
                s.options.trackAutoOff = on
                s.warpSystem = (s.commander.currentSystem + 1) % s.galaxy.systems.count
                s.trackedSystem = s.warpSystem
                _ = s.arrival()
                #expect(s.trackedSystem == (on ? nil : s.commander.currentSystem))
            }
        }
        var e = CheatKit.engine()
        let t = CheatKit.goTarget(e.state, near: 20, avoid: e.state.commander.currentSystem)
        e.state.trackedSystem = t
        _ = e.perform(.cheat(.go(e.state.systemName(t))))
        #expect(e.state.commander.currentSystem == t && e.state.trackedSystem == nil)
    }

    @Test("OPT-022 showTrackedRange is display-only: no engine read, and flipping it changes no StepResult")
    func showTrackedRange() throws {
        #expect(try OptKit.optionReads()["showTrackedRange"] == nil)
        for id in RulesetID.allCases {
            var a = makeEngine(id, seed: 21), b = a
            b.state.options.showTrackedRange.toggle()
            let script: [Command] = [.buyFuel(credits: 50), .buyCargo(.water, quantity: 2), .track(4), .selectNextTarget(forward: true),
                                     .warp, .encounter(.flee), .encounter(.ignore), .encounter(.autoRepeat), .readNewspaper]
            for c in script {
                #expect(a.perform(c, acknowledging: Set(WarningID.allCases)) == b.perform(c, acknowledging: Set(WarningID.allCases)), "\(c)")
            }
            #expect(OptKit.sameApartFromOptions(a.state, b.state))
        }
    }

    @Test("OPT-023 continuousAttack/continuousAttackFleeing only set the auto-repeat flags after a round")
    func continuous() throws {
        let reads = try OptKit.optionReads()
        #expect(reads["continuousAttack"] == ["Combat.swift"] && reads["continuousAttackFleeing"] == ["Combat.swift"])
        var checked = 0
        for seed in UInt64(1)...40 {
            var off = CombatKit.engine(.pirateAttack, seed: seed) { s in
                var o = CombatKit.opponent(&s, .wasp, weapons: [.pulseLaser])
                o.hull = 500
                return o
            }
            var on = off
            on.state.options.continuousAttack = true
            on.state.options.continuousAttackFleeing = true
            _ = off.perform(.encounter(.attack), acknowledging: CombatKit.yes)
            _ = on.perform(.encounter(.attack), acknowledging: CombatKit.yes)
            guard let a = CombatKit.encounter(off), let b = CombatKit.encounter(on) else { continue }
            checked += 1
            #expect(!a.continueAttacking && b.continueAttacking)
            var b2 = b
            b2.continueAttacking = false
            var sb = on.state
            sb.phase = .encounter(b2)
            #expect(OptKit.sameApartFromOptions(off.state, sb))
        }
        #expect(checked > 0)
    }

    @Test("OPT-024 disableOpponents gates only the no-damage disable attempt (Modern/Windows; absent in Palm)")
    func disableOpponents() throws {
        #expect(try OptKit.optionReads()["disableOpponents"] == ["Combat.swift"])
        var attempts = 0
        for seed in UInt64(0)..<80 {
            var off = CombatKit.state(.normal, seed: seed)
            off.commander.ship = CombatKit.playerShip(off, .hornet, weapons: [.pulseLaser, .photonDisruptor])
            var encOff = EncounterState(type: .pirateAttack, opponent: CombatKit.opponent(&off, .wasp))
            var on = off, encOn = encOff
            on.options.disableOpponents = true
            let hitOff = off.executeAttack(commanderAttacks: true, fleeing: false, encounter: &encOff)
            _ = on.executeAttack(commanderAttacks: true, fleeing: false, encounter: &encOn)
            #expect(encOn.opponent.hull == 200)
            if hitOff, encOff.opponent.hull < 200 { attempts += 1 }
        }
        #expect(attempts > 0)
        var palm = GameOptions()
        palm.disableOpponents = true
        #expect(!palm.normalized(for: .palm122).disableOpponents && palm.normalized(for: .windows201).disableOpponents)
    }
}

@Suite("OPT §5: Palm preferences outside GameOptions")
struct OptionsPalmPreferencesTests {
    @Test("OPT-029 Palm-only preferences (AlwaysInfo, TextualEncounters, Shortcuts, PriceDifferences…) are not game options")
    func palmPreferences() throws {
        let data = try JSONEncoder().encode(GameOptions.defaults(for: .palm122))
        let keys = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any]).keys.map { $0.lowercased() }
        for dropped in ["alwaysinfo", "rectangularbuttonson", "textualencounters", "usehwbuttons", "shortcut1", "sharepreferences",
                        "identifystartup", "pricedifferences"] {
            #expect(!keys.contains(dropped))
        }
        #expect(keys.count == 16)
        let stateKeys = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(makeEngine(.palm122).state))
                                         as? [String: Any]).keys.map { $0.lowercased() }
        #expect(!stateKeys.contains { ["alwaysinfo", "textualencounters", "pricedifferences", "sharepreferences"].contains($0) })
    }
}
