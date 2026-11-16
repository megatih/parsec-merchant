// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecEngine

/// An independent model of ENC §4 (Windows 2.01 `Ship(OpponentType)`), written from the spec text. It draws from the
/// game RNG in the order the spec states, so agreement with the engine checks both the values and the draw sequence.
enum OpponentSpecModel {
    static let special: Set<Int> = [0, 31, 32, 33, 34, 35, 36, 37, 53, 54]

    static func allowed(_ s: GameState, _ t: ShipType, _ kind: OpponentType) -> Bool {
        let gov = s.ruleset.tables.politics(s.galaxy.systems[s.warpSystem].politics)
        let spec = s.ruleset.tables.ship(t)
        let bonus = max(0, s.difficulty.rawValue - 2)
        switch kind {
        case .pirate: return gov.activityPirates.rawValue + bonus >= spec.pirates.rawValue
        case .police: return gov.activityPolice.rawValue + bonus >= spec.police.rawValue
        default: return gov.activityTraders.rawValue + bonus >= spec.traders.rawValue
        }
    }

    /// ENC-062: ship-type tries.
    static func shipTries(_ s: GameState, _ kind: OpponentType) -> Int {
        let d = s.difficulty.rawValue
        switch kind {
        case .pirate: return max(1, 1 + s.worth / 100_000 + d - 2)
        case .police:
            let rec = s.commander.policeRecordScore
            let base = rec < -100 || s.wildOnBoard ? 5 : (rec < -70 ? 3 : 1)
            return max(1, base + d - 2)
        default: return 1
        }
    }

    /// ENC-065: the Windows 2.01 type pick over indices 0…8.
    static func pickType(_ s: inout GameState, _ kind: OpponentType) -> ShipType {
        let occ = (0...8).map { s.ruleset.tables.ship(ShipType.buyable[$0]).occurrence }
        let ok = (0...8).map { allowed(s, ShipType.buyable[$0], kind) }
        let total = (0...8).filter { ok[$0] }.map { occ[$0] }.reduce(0, +)
        var best = kind == .trader ? 0 : 1
        for _ in 0..<shipTries(s, kind) {
            let x = s.rng.next(below: total)
            var sum = -1
            var j = 0
            while true {
                if ok[j] {
                    sum = sum > 0 ? sum + occ[j] : occ[j]
                    if sum >= x { break }
                }
                j += 1
            }
            best = max(best, j)
        }
        return ShipType.buyable[best]
    }

    /// ENC-074/075/076: one weighted pick with `tries` attempts, skipping fitted types (index-0 fallback).
    static func pick(_ s: inout GameState, _ chances: [Int], tries: Int, fitted: (Int) -> Bool) -> Int {
        var best = 0
        for _ in 0..<tries {
            let x = s.rng.next(below: 100)
            var t = 0
            var sum = chances[0]
            while sum < x {
                t += 1
                sum += chances[t]
            }
            if !fitted(t), t > best { best = t }
        }
        return best
    }

    static func count(_ s: inout GameState, slots: Int, extra: (Int) -> Bool, needsCoin: (Int) -> Bool, tries: Int) -> Int {
        if s.difficulty == .impossible { return slots }
        var n = s.rng.next(below: slots + 1)
        if n < slots, extra(tries) || (needsCoin(tries) && s.rng.next(below: 2) > 0) { n += 1 }
        return n
    }

    static func generate(_ s: inout GameState, _ kind: OpponentType) -> Ship {
        let r = s.ruleset
        let d = s.difficulty.rawValue
        let tries = kind == .mantis ? d + 1 : max(1, s.worth / 150_000 + d - 2)        // ENC-068
        let type: ShipType = kind == .mantis ? .mantis : pickType(&s, kind)
        var ship = Ship(type: type, spec: r.tables.ship(type))
        // ENC-069/070/072: crew into slot 31; the Windows Kravat boost never fires.
        for k in 0..<4 { s.mercenaries[31].skills[k] = 1 + s.rng.next(below: 10) }
        ship.crew[0] = 31
        let quarters = ship.crew.count
        var n = quarters
        if s.difficulty != .impossible {
            n = 1 + s.rng.next(below: quarters)
            if s.difficulty == .hard, n < quarters { n += 1 }
        }
        for i in 1..<max(1, n) {
            var c: Int
            repeat { c = s.rng.next(below: 55) } while special.contains(c)
            ship.crew[i] = c
        }
        let spec = r.tables.ship(type)
        if spec.gadgetSlots > 0 {                                                         // ENC-074
            let g = count(&s, slots: spec.gadgetSlots, extra: { $0 > 4 }, needsCoin: { $0 > 2 }, tries: tries)
            for _ in 0..<g {
                let best = pick(&s, r.tables.gadgets.map(\.chance), tries: tries) { ship.gadgets.contains(GadgetType.allCases[$0]) }
                ship.gadgets.append(GadgetType.allCases[best])
            }
        }
        if spec.shieldSlots > 0 {                                                         // ENC-075
            let c = count(&s, slots: spec.shieldSlots, extra: { $0 > 3 }, needsCoin: { $0 > 1 }, tries: tries)
            for _ in 0..<c {
                let best = pick(&s, r.tables.shields.map(\.chance), tries: tries) { k in ship.shields.contains { $0.type.rawValue == k } }
                let power = r.tables.shields[best].power
                let charge = (0..<5).map { _ in 1 + s.rng.next(below: power) }.max() ?? 0
                ship.shields.append(ShieldInstance(type: ShieldType.allCases[best], charge: charge))
            }
        }
        if spec.weaponSlots > 0 {                                                         // ENC-076
            var w: Int
            if s.difficulty == .impossible {
                w = spec.weaponSlots
            } else if spec.weaponSlots == 1 {
                w = 1
            } else {
                w = 1 + s.rng.next(below: spec.weaponSlots)
                if w < spec.weaponSlots, tries > 4 || (tries > 3 && s.rng.next(below: 2) > 0) { w += 1 }
            }
            for _ in 0..<w {
                let best = pick(&s, r.tables.weapons.map(\.chance), tries: tries) { ship.weapons.contains(WeaponType.allCases[$0]) }
                ship.weapons.append(WeaponType.allCases[best])
            }
        }
        if kind != .mantis, ship.shieldStrength(r) == 0 || s.rng.next(below: 5) == 0 {     // ENC-077
            ship.hull = (0..<5).map { _ in 1 + s.rng.next(below: spec.hullStrength) }.max() ?? 0
        }
        let bays = ship.cargoBays(r)
        if kind != .police, bays > 0 {                                                    // ENC-078
            var b = bays
            if s.difficulty >= .normal { b = min(15, 3 + s.rng.next(below: bays - 5)) }
            if kind == .pirate { b = s.difficulty < .normal ? b * 4 / 5 : max(1, b / d) }
            var i = 0
            while i < b {
                let item = s.rng.next(below: 10)
                let q = min(b - i, 1 + s.rng.next(below: 10 - item))
                ship.cargo[item] += q
                i += q
            }
        }
        return ship
    }
}

@Suite("ENC §4: opponent generation")
struct EncounterGenerationTests {
    @Test("ENC-060 ENC-085 famous captain and bottle use no RNG; generated ships match the C# harness field by field and in RNG position")
    func harnessAndOrder() throws {
        var s = EncSpec.engine().state
        let before = s.rng
        _ = s.generateOpponent(.famousCaptain)
        _ = s.generateOpponent(.bottle)
        #expect(s.rng == before)
        _ = s.generateOpponent(.pirate)
        #expect(s.rng != before)

        let runs = try Fixtures.decode([HarnessOpponents].self, "harness/opponents-windows201.json")
        try #require(!runs.isEmpty)
        for run in runs {
            var g = GameState(config: NewGameConfig(commanderName: "Harness", difficulty: Difficulty(rawValue: run.difficulty) ?? .normal,
                                                    ruleset: .windows201, seed: UInt64(UInt32(bitPattern: run.seed))))
            for c in run.cases {
                g.warpSystem = c.warp
                g.commander.cash = c.cash
                g.commander.policeRecordScore = c.record
                let ship = g.generateOpponent(try #require(OpponentType(rawValue: c.oppType)))
                // Every case starts where the previous one left the RNG, so the whole run checks the RNG positions too.
                #expect(ship.type.rawValue == c.ship.type && ship.hull == c.ship.hull && ship.cargo == c.ship.cargo)
                #expect(ship.weapons.map(\.rawValue) == c.ship.weapons.filter { $0 >= 0 })
                #expect(ship.shields.map(\.charge) == Array(c.ship.charges.prefix(ship.shields.count)))
            }
        }
    }

    @Test("ENC-061 worth W is the Windows Commander.Worth: ship list price + cash − debt + moon (not trade-in value)")
    func worth() {
        var s = EncSpec.engine().state
        s.commander.cash = 5_000
        s.commander.debt = 1_000
        let list = s.ruleset.tables.ship(.grasshopper).price
        #expect(s.worth == list + 4_000)
        s.commander.ship.hull = 1
        s.commander.ship.fuel = 0
        s.commander.ship.weapons = []
        #expect(s.worth == list + 4_000, "damage and equipment do not change the list price")
        s.quests.moon = QuestStatus.Moon.bought
        #expect(s.worth == list + 4_000 + 500_000)
    }

    /// Random generation contexts: difficulty, government, worth, record, Wild aboard, destination.
    static func contexts(_ count: Int) -> [GameState] {
        var r = Xoshiro256StarStar(seed: 99)
        var out: [GameState] = []
        for k in 0..<count {
            let diff = Difficulty(rawValue: k % 5) ?? .normal
            var s = EncSpec.engine(diff, seed: UInt64(k + 1)).state
            s.galaxy.systems[s.warpSystem].politics = PoliticalSystemType(rawValue: r.next(below: 17)) ?? .anarchy
            s.commander.cash = [0, 60_000, 160_000, 450_000, 2_000_000][r.next(below: 5)]
            s.commander.policeRecordScore = [-150, -101, -100, -80, -70, -10, 0, 20][r.next(below: 8)]
            if r.next(below: 4) == 0 { s.commander.ship.crew[1] = CrewID.wild }
            if r.next(below: 4) == 0 {
                s.warpSystem = SystemID.kravat
            }
            for _ in 0..<r.next(below: 50) { _ = s.rng.next(below: 7) }
            out.append(s)
        }
        return out
    }

    @Test("""
    ENC-062 ENC-064 ENC-065 ENC-068 ENC-069 ENC-070 ENC-072 ENC-074 ENC-075 ENC-076 ENC-077 ENC-078 ENC-083 \
    generation follows the spec model: tries, type walk over 0…8, crew, gadgets, shields, weapons, hull and cargo
    """)
    func specModel() {
        for (k, s) in Self.contexts(250).enumerated() {
            for kind in [OpponentType.pirate, .police, .trader, .mantis] {
                var engine = s
                var model = s
                let got = engine.generateOpponent(kind)
                let want = OpponentSpecModel.generate(&model, kind)
                #expect(got == want, "context \(k) \(kind)")
                #expect(engine.rng == model.rng, "context \(k) \(kind): RNG position")
                #expect(engine.mercenaries[CrewID.opponent].skills == model.mercenaries[CrewID.opponent].skills, "context \(k) \(kind): slot 31")
                #expect(got.crew[0] == CrewID.opponent)
                if kind == .mantis {
                    #expect(got.type == .mantis && got.hull == s.ruleset.tables.ship(.mantis).hullStrength, "ENC-083 full Mantis hull")
                }
                #expect(!got.weapons.contains { $0.isDisruptor }, "opponents never carry disruptors")
            }
        }
    }

    @Test("ENC-064 a ship type is allowed iff activity + max(0, D − 2) ≥ its minimum; NA (100) never")
    func shipTypeLikely() {
        for diff in Difficulty.allCases {
            var s = EncSpec.engine(diff).state
            for gov in PoliticalSystemType.allCases {
                s.galaxy.systems[s.warpSystem].politics = gov
                let g = s.ruleset.tables.politics(gov)
                for t in ShipType.allCases {
                    let spec = s.ruleset.tables.ship(t)
                    let b = max(0, diff.rawValue - 2)
                    #expect(s.shipTypeLikely(t, .pirate, government: g) == (spec.pirates != .na && g.activityPirates.rawValue + b >= spec.pirates.rawValue))
                    #expect(s.shipTypeLikely(t, .police, government: g) == (spec.police != .na && g.activityPolice.rawValue + b >= spec.police.rawValue))
                    #expect(s.shipTypeLikely(t, .trader, government: g) == (spec.traders != .na && g.activityTraders.rawValue + b >= spec.traders.rawValue))
                }
            }
        }
    }

    @Test("ENC-065 a Wasp is never a random opponent in Windows 2.01, even where Wasps are allowed and tries are many")
    func noWasp() {
        var s = EncSpec.engine(.impossible).state
        s.galaxy.systems[s.warpSystem].politics = .anarchy        // pirates swarm: the Wasp is allowed
        s.commander.cash = 5_000_000
        s.commander.policeRecordScore = -200
        #expect(s.shipTypeLikely(.wasp, .pirate, government: s.ruleset.tables.politics(.anarchy)))
        var seen: Set<ShipType> = []
        for _ in 0..<300 {
            seen.insert(s.generateOpponent(.pirate).type)
            seen.insert(s.generateOpponent(.trader).type)
        }
        #expect(!seen.contains(.wasp))
        #expect(seen.contains(.termite), "the walk does reach index 8")
    }

    @Test("ENC-069 ENC-086 generation overwrites slot 31 and otherwise changes only the RNG")
    func purity() {
        for s in Self.contexts(40) {
            for kind in OpponentType.allCases {
                var after = s
                _ = after.generateOpponent(kind)
                var normalized = after
                normalized.rng = s.rng
                normalized.mercenaries[CrewID.opponent] = s.mercenaries[CrewID.opponent]
                #expect(normalized == s, "\(kind) changed state beyond slot 31 and the RNG")
            }
        }
    }

    @Test("ENC-070 Windows: no Kravat engineer boost and no boost draw, even at Kravat with Wild aboard the player's ship")
    func noKravatBoost() {
        var s = EncSpec.engine(.impossible) { s in
            s.warpSystem = SystemID.kravat
            s.commander.ship.crew[1] = CrewID.wild
        }.state
        var model = s
        for _ in 0..<50 {
            let got = s.generateOpponent(.pirate)
            #expect(got == OpponentSpecModel.generate(&model, .pirate))
            #expect(s.rng == model.rng)
        }
    }

    @Test("ENC-079 ENC-080 a famous captain: Wasp, 2 full reflective shields, 3 military lasers, navigating + targeting, crew 34 at 10/10/10/10")
    func famousCaptain() {
        var s = EncSpec.engine().state
        let ship = s.generateOpponent(.famousCaptain)
        #expect(ship.type == .wasp && ship.hull == 200 && ship.fuel == s.ruleset.tables.ship(.wasp).fuelTanks && ship.tribbles == 0)
        #expect(ship.shields == Array(repeating: ShieldInstance(type: .reflective, charge: 200), count: 2))
        #expect(ship.weapons == Array(repeating: .militaryLaser, count: 3))
        #expect(ship.gadgets == [.navigatingSystem, .targetingSystem])
        #expect(ship.crew[0] == CrewID.famousCaptain && s.mercenaries[CrewID.famousCaptain].skills == [10, 10, 10, 10])
        #expect(ship.cargo.allSatisfy { $0 == 0 })
        // ENC-079 for generated ships: full fuel and no tribbles.
        for kind in [OpponentType.pirate, .police, .trader, .mantis] {
            let g = s.generateOpponent(kind)
            #expect(g.fuel == s.ruleset.tables.ship(g.type).fuelTanks && g.tribbles == 0)
        }
    }

    @Test("ENC-082 a bottle: hull 10, no slots, no crew; its skills evaluate to the minimum")
    func bottle() {
        var s = EncSpec.engine().state
        let b = s.generateOpponent(.bottle)
        #expect(b.type == .bottle && b.hull == 10 && b.crew.isEmpty)
        #expect(b.weapons.isEmpty && b.shields.isEmpty && b.gadgets.isEmpty)
        #expect(s.skills(of: b) == [1, 1, 1, 1])
    }

    @Test("ENC-087 a shown encounter makes the C# tribble-sprite draws: min(36, ⌊√(tribbles / 74)⌋) × (rand(36), rand(8))")
    func tribbleDraws() {
        for (tribbles, sprites) in [(0, 0), (73, 0), (74, 1), (74 * 16, 4), (100_000, 36)] {
            var e = EncSpec.encounter(.pirateAttack) { s in s.commander.ship.tribbles = tribbles }
            e.state.phase = .inTransit(TransitState(destination: e.state.warpSystem, clicksRemaining: 3, viaWormhole: false))
            let enc = EncounterState(type: .pirateAttack, opponent: EncSpec.gnat(e.state), clicks: 3)
            let expected = EncSpec.after(e.state, Array(repeating: [36, 8], count: sprites).flatMap { $0 })
            _ = e.startEncounter(enc)
            #expect(e.state.rng == expected, "\(tribbles) tribbles → \(sprites) sprites")
        }
    }
}

// MARK: - §5 Initial reactions and visibility

@Suite("ENC §5: initial reactions and visibility")
struct EncounterReactionTests {
    /// Random reaction contexts: reputation, record, player ship, cloak, options, inspected.
    static func contexts(_ count: Int) -> [GameState] {
        var r = Xoshiro256StarStar(seed: 5)
        return (0..<count).map { k in
            var s = EncSpec.engine(Difficulty(rawValue: k % 5) ?? .normal, seed: UInt64(1_000 + k)).state
            s.galaxy.systems[s.warpSystem].politics = PoliticalSystemType(rawValue: r.next(below: 17)) ?? .anarchy
            s.commander.reputationScore = [0, 20, 39, 40, 300, 1_500][r.next(below: 6)]
            s.commander.policeRecordScore = [-120, -31, -30, -6, -5, -1, 0, 3, 5, 30][r.next(below: 10)]
            s.commander.ship.type = [ShipType.flea, .gnat, .firefly, .hornet, .wasp][r.next(below: 5)]
            if r.next(below: 3) == 0 { s.commander.ship.gadgets = [.cloakingDevice] }
            s.mercenaries[CrewID.commander].skills[3] = 1 + r.next(below: 10)
            s.options.alwaysIgnorePirates = r.next(below: 2) == 0
            s.options.alwaysIgnorePolice = r.next(below: 2) == 0
            s.options.alwaysIgnoreTraders = r.next(below: 2) == 0
            s.options.alwaysIgnoreTradeInOrbit = r.next(below: 2) == 0
            s.inspected = r.next(below: 3) == 0
            s.chanceOfTradeInOrbit = [100, 1000][r.next(below: 2)]
            return s
        }
    }

    @Test("ENC-100 cloaked iff the ship has a cloaking device and a greater effective engineer skill; pilot plays no part")
    func cloak() {
        var s = EncSpec.engine().state
        var opp = EncSpec.gnat(s)
        s.mercenaries[CrewID.opponent].skills = [10, 5, 5, 5]
        s.lastOpponent = opp
        s.mercenaries[CrewID.commander].skills = [1, 5, 5, 6]
        #expect(!s.commanderCloaked, "no device")
        s.commander.ship.gadgets = [.cloakingDevice]
        #expect(s.commanderCloaked, "engineer 6 > 5 despite pilot 1 vs 10")
        s.mercenaries[CrewID.commander].skills[3] = 5
        #expect(!s.commanderCloaked, "equal engineer is not enough")
        opp.gadgets = [.cloakingDevice]
        s.mercenaries[CrewID.opponent].skills = [1, 5, 5, 6]
        #expect(s.opponentCloaked(opp))
        opp.gadgets = []
        #expect(!s.opponentCloaked(opp))
    }

    @Test("ENC-101 ENC-102 pirate reaction (Mantis attacks; cloaked → ignore; outclassing → attack; else the reputation draw) and visibility")
    func pirates() {
        for (k, s0) in Self.contexts(400).enumerated() {
            var s = s0
            var g = s0
            let opp = g.generateOpponent(.pirate)
            g.lastOpponent = opp
            var type: EncounterType
            if g.commanderCloaked {
                type = .pirateIgnore
            } else if opp.type.rawValue > g.commander.ship.type.rawValue || opp.type.rawValue >= ShipType.grasshopper.rawValue {
                type = .pirateAttack
            } else {
                type = g.rng.next(below: 1_500) > g.commander.reputationScore * 4 / (1 + opp.type.rawValue) ? .pirateAttack : .pirateFlee
            }
            let shown = type == .pirateAttack || !(g.opponentCloaked(opp) || g.options.alwaysIgnorePirates)
            let got = s.determinePirate(mantis: false, clicks: 4)
            #expect(got?.type == (shown ? type : nil), "context \(k)")
            #expect(s.rng == g.rng, "context \(k): draws")
            var m = s0
            var mg = s0
            _ = mg.generateOpponent(.mantis)
            let mantis = m.determinePirate(mantis: true, clicks: 4)
            #expect(mantis?.type == .pirateAttack && m.rng == mg.rng, "Mantis: attack, no reaction draw")
        }
    }

    @Test("ENC-104 ENC-105 police reaction (surrender/attack/flee/ignore, the inspection rolls) and visibility")
    func police() {
        for (k, s0) in Self.contexts(400).enumerated() {
            var s = s0
            var g = s0
            let opp = g.generateOpponent(.police)
            g.lastOpponent = opp
            let rec = g.commander.policeRecordScore, rep = g.commander.reputationScore
            var type: EncounterType = .policeIgnore
            var inspected = g.inspected
            if !g.commanderCloaked {
                if rec < -5 {
                    let armed = opp.weaponStrength(g.ruleset) > 0 && (rep < 40 || g.rng.next(below: 1_500) > rep / (1 + opp.type.rawValue))
                    if armed || opp.type.rawValue > g.commander.ship.type.rawValue {
                        type = rec >= -30 ? .policeSurrender : .policeAttack
                    } else {
                        type = g.opponentCloaked(opp) ? .policeIgnore : .policeFlee
                    }
                } else if !inspected {
                    let roll: Bool
                    if rec < 0 {
                        roll = true
                    } else if rec < 5 {
                        roll = g.rng.next(below: 12 - g.difficulty.rawValue) < 1
                    } else {
                        roll = g.rng.next(below: 40) == 0
                    }
                    if roll {
                        type = .policeInspect
                        inspected = true
                    }
                }
            }
            let shown = type == .policeAttack || type == .policeInspect || !(g.opponentCloaked(opp) || g.options.alwaysIgnorePolice)
            let got = s.determinePolice(clicks: 4)
            #expect(got?.type == (shown ? type : nil), "context \(k)")
            #expect(s.rng == g.rng && s.inspected == inspected, "context \(k): draws / inspected")
        }
    }

    @Test("ENC-107 ENC-108 trader reaction (flee draw at rec ≤ −30, else the trade-in-orbit roll) and visibility")
    func traders() {
        for (k, s0) in Self.contexts(400).enumerated() {
            var s = s0
            var g = s0
            let opp = g.generateOpponent(.trader)
            g.lastOpponent = opp
            var type: EncounterType = .traderIgnore
            if !g.commanderCloaked {
                if g.commander.policeRecordScore <= -30,
                   g.rng.next(below: 1_500) <= g.commander.reputationScore * 10 / (1 + opp.type.rawValue) {
                    type = .traderFlee
                } else if let orbit = g.tradeInOrbitRoll(trader: opp) {
                    type = orbit
                }
            }
            let hiddenByOption = g.options.alwaysIgnoreTraders && (type == .traderIgnore || type == .traderFlee)
            let hiddenTrade = g.options.alwaysIgnoreTradeInOrbit && (type == .traderBuy || type == .traderSell)
            let shown = !g.opponentCloaked(opp) && !hiddenByOption && !hiddenTrade
            let got = s.determineTrader(clicks: 4)
            #expect(got?.type == (shown ? type : nil), "context \(k)")
            #expect(s.rng == g.rng, "context \(k): draws")
        }
        #expect(GameOptions().alwaysIgnoreTraders, "alwaysIgnoreTraders defaults to on")
    }

    @Test("ENC-110 a shown encounter starts with continue flags, disabled and commander-fleeing false; opponent fleeing only for flee types")
    func initialFlags() {
        for type in EncounterType.allCases {
            var e = EncSpec.engine()
            var enc = EncounterState(type: type, opponent: EncSpec.gnat(e.state), clicks: 2)
            enc.oppFleeing = true
            _ = e.startEncounter(enc)
            guard let got = EncSpec.current(e) else { Issue.record("no encounter"); continue }
            #expect(!got.opponentDisabled && !got.cmdrFleeing && !got.continueAttacking && !got.continueFleeing)
            #expect(got.oppFleeing == [.pirateFlee, .policeFlee, .traderFlee].contains(type), "\(type)")
        }
    }

    @Test("ENC-111 the initial type of a shown encounter is never a disabled, surrender, trader-attack or famous-captain-attack type")
    func neverInitial() {
        let forbidden: Set<EncounterType> = [.famousCaptainAttack, .famousCaptDisabled, .policeDisabled, .pirateDisabled,
                                             .pirateSurrender, .traderAttack, .traderDisabled, .traderSurrender]
        var seen = 0
        for s0 in Self.contexts(300) {
            var s = s0
            s.commander.days = 20
            s.chanceOfVeryRareEncounter = 300
            for clicks in stride(from: 20, to: 0, by: -1) {
                if let enc = s.determineFixedEncounter(clicks: clicks) ?? s.determineRandomEncounter(clicks: clicks) {
                    seen += 1
                    #expect(!forbidden.contains(enc.type), "\(enc.type)")
                }
            }
        }
        #expect(seen > 500)
    }

    @Test("ENC-112 encounterStarted.playerCloaked is true only for an ignore type caused by the player's cloak")
    func playerCloaked() {
        func started(_ type: EncounterType, cloaked: Bool, opponent: ShipType = .gnat) -> Bool? {
            var e = EncSpec.engine()
            var opp = EncSpec.gnat(e.state)
            opp.type = opponent
            e.state.lastOpponent = opp
            e.state.mercenaries[CrewID.opponent].skills = [5, 5, 5, 3]
            if cloaked { e.state.commander.ship.gadgets = [.cloakingDevice] }
            if case let .encounterStarted(_, _, _, c) = e.startEncounter(EncounterState(type: type, opponent: opp, clicks: 2)) { return c }
            return nil
        }
        #expect(started(.pirateIgnore, cloaked: true) == true)
        #expect(started(.policeIgnore, cloaked: true) == true)
        #expect(started(.traderIgnore, cloaked: true) == true)
        #expect(started(.pirateIgnore, cloaked: false) == false)
        #expect(started(.pirateAttack, cloaked: true, opponent: .mantis) == false, "a Mantis attacks whatever the cloak")
        #expect(started(.marieCelestePolice, cloaked: true) == false)
    }

    @Test("ENC-113 each type maps to a badge: special, pirate, alien (Mantis pirates, monster), police or trader")
    func badges() throws {
        let special: Set<EncounterType> = [.bottleGood, .bottleOld, .captainAhab, .captainConrad, .captainHuie, .marieCeleste,
                                           .famousCaptainAttack, .famousCaptDisabled]
        let questPirates: Set<EncounterType> = [.dragonflyAttack, .dragonflyIgnore, .scarabAttack, .scarabIgnore, .scorpionAttack, .scorpionIgnore]
        let pirates: Set<EncounterType> = [.pirateAttack, .pirateIgnore, .pirateFlee, .pirateSurrender, .pirateDisabled]
        let police: Set<EncounterType> = [.marieCelestePolice, .policeAttack, .policeIgnore, .policeFlee, .policeSurrender, .policeDisabled, .policeInspect]
        let traders: Set<EncounterType> = [.traderAttack, .traderIgnore, .traderFlee, .traderSurrender, .traderDisabled, .traderBuy, .traderSell]
        for t in EncounterType.allCases {
            let expected: EncounterBadge
            if special.contains(t) {
                expected = .special
            } else if questPirates.contains(t) || pirates.contains(t) {
                expected = .pirate
            } else if police.contains(t) {
                expected = .police
            } else if traders.contains(t) {
                expected = .trader
            } else {
                expected = .alien      // the Space Monster types
            }
            #expect(t.badge(opponent: .gnat) == expected, "\(t)")
            #expect(t.badge(opponent: .mantis) == (pirates.contains(t) ? .alien : expected), "\(t) vs Mantis")
        }
        let e = EncSpec.encounter(.pirateAttack, opponent: { s in EncSpec.ship(s, .mantis) })
        #expect(try #require(e.encounterPreview).badge == .alien)
    }
}
