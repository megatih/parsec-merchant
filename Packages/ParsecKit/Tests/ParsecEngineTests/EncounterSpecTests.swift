// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecEngine

/// Shared builders for the ENC spec tests (Windows 2.01 ruleset).
enum EncSpec {
    /// A Windows 2.01 game whose commander flies a Grasshopper (2 weapon, 2 shield, 3 gadget slots, 3 quarters) with a
    /// military laser, skills 5/5/5/5, and a plain destination (not a quest system).
    static func engine(_ difficulty: Difficulty = .normal, seed: UInt64 = 7, _ adjust: (inout GameState) -> Void = { _ in }) -> GameEngine {
        var e = makeEngine(.windows201, seed: seed, difficulty: difficulty)
        var ship = Ship(type: .grasshopper, spec: e.ruleset.tables.ship(.grasshopper))
        ship.crew[0] = CrewID.commander
        ship.weapons = [.militaryLaser]
        e.state.commander.ship = ship
        e.state.commander.priceCargo = Array(repeating: 0, count: 10)
        e.state.mercenaries[CrewID.commander].skills = [5, 5, 5, 5]
        e.state.warpSystem = e.state.commander.currentSystem == 1 ? 2 : 1
        e.state.galaxy.systems[e.state.warpSystem].politics = .confederacy
        adjust(&e.state)
        return e
    }

    /// A Gnat opponent with a pulse laser, crewed by the shared opponent record.
    static func gnat(_ s: GameState) -> Ship {
        var o = Ship(type: .gnat, spec: s.ruleset.tables.ship(.gnat))
        o.weapons = [.pulseLaser]
        o.crew[0] = CrewID.opponent
        return o
    }

    static func ship(_ s: GameState, _ type: ShipType) -> Ship { Ship(type: type, spec: s.ruleset.tables.ship(type)) }

    /// Puts the engine into an encounter. A Normal end resumes transit with one click left, i.e. arrives.
    static func enter(_ e: inout GameEngine, _ type: EncounterType, opponent: Ship? = nil) {
        e.state.encounterTransit = TransitState(destination: e.state.warpSystem, clicksRemaining: 1, viaWormhole: false)
        e.state.phase = .encounter(EncounterState(type: type, opponent: opponent ?? gnat(e.state), clicks: 1))
    }

    static func encounter(_ type: EncounterType, _ difficulty: Difficulty = .normal, with adjust: (inout GameState) -> Void = { _ in },
                          opponent: ((GameState) -> Ship)? = nil) -> GameEngine {
        var e = engine(difficulty, adjust)
        enter(&e, type, opponent: opponent?(e.state))
        return e
    }

    static func current(_ e: GameEngine) -> EncounterState? { if case let .encounter(x) = e.state.phase { x } else { nil } }

    /// The encounter ended Normal: transit resumed and (one click left) the ship arrived, without an arrest.
    static func endedNormally(_ e: GameEngine, _ r: StepResult) -> Bool {
        e.state.phase == .docked && r.events.contains(.arrived(system: e.state.warpSystem)) && !r.events.contains { ev in
            if case .arrested = ev { true } else { false }
        }
    }

    /// Advances the game RNG one draw at a time until `pred` holds for a copy at that position.
    static func seek(_ s: inout GameState, _ pred: (inout RNGState) -> Bool) {
        for _ in 0..<300_000 {
            var p = s.rng
            if pred(&p) { return }
            _ = s.rng.next(below: 2)
        }
        Issue.record("no RNG position satisfies the predicate")
    }

    /// The RNG after making `draws` from the current position.
    static func after(_ s: GameState, _ draws: [Int]) -> RNGState {
        var r = s.rng
        for d in draws { _ = r.next(below: d) }
        return r
    }

    /// The opponent `generateOpponent(kind)` yields after `draws` determination draws.
    static func opponent(_ s: GameState, _ kind: OpponentType, after draws: [Int]) -> Ship {
        var g = s
        g.rng = after(s, draws)
        return g.generateOpponent(kind)
    }
}

// MARK: - §1 Transit hook and fixed encounters

@Suite("ENC §1: transit hook and fixed encounters")
struct EncounterHookTests {
    @Test("ENC-001 each click: repairs first, then the fixed checks; the random roll only when no fixed check matched")
    func clickOrder() throws {
        var e = EncSpec.engine { s in
            s.warpSystem = SystemID.acamar
            s.quests.spaceMonster = QuestStatus.SpaceMonster.atAcamar
            s.commander.ship.hull = 100
        }
        e.state.phase = .inTransit(TransitState(destination: SystemID.acamar, clicksRemaining: 1, viaWormhole: false))
        var r = e.state.rng
        let repairs = r.next(below: e.state.shipSkills[3])
        _ = e.continueTransit()
        #expect(e.state.rng == r, "only the repair draw: the fixed check matched and no random roll was made")
        #expect(e.state.commander.ship.hull == 100 + repairs)
        #expect(EncSpec.current(e)?.type == .spaceMonsterAttack)

        // No fixed match: the random determination runs after the repairs.
        var f = EncSpec.engine()
        f.state.phase = .inTransit(TransitState(destination: f.state.warpSystem, clicksRemaining: 1, viaWormhole: false))
        var g = f.state
        _ = g.rng.next(below: g.shipSkills[3])
        let expected = g.determineRandomEncounter(clicks: 1)
        _ = f.continueTransit()
        if let expected {
            let got = try #require(EncSpec.current(f))
            #expect(got.type == expected.type && got.opponent == expected.opponent)
        } else {
            #expect(f.state.phase == .docked)
        }
    }

    @Test("ENC-002 a hidden encounter emits nothing, keeps its RNG draws and transit continues uneventfully")
    func hiddenEncounter() {
        var e = EncSpec.engine { s in
            s.options.alwaysIgnoreTraders = true
            s.options.alwaysIgnoreTradeInOrbit = true
            s.commander.days = 0
        }
        let skill = e.state.shipSkills[3]
        // Confederacy (P 3, Q 4, T 5), record 0: the trader band is 7..<12; every trader type is hidden by the options.
        EncSpec.seek(&e.state) { p in
            _ = p.next(below: skill)
            return (7..<12).contains(p.next(below: 40))
        }
        var probe = e.state
        _ = probe.rng.next(below: skill)
        let before = probe.rng
        #expect(probe.determineRandomEncounter(clicks: 1) == nil)
        #expect(probe.rng != before, "the roll and the trader generation stay consumed")
        #expect(probe.lastOpponent == EncSpec.opponent(e.state, .trader, after: [skill, 40]))

        e.state.phase = .inTransit(TransitState(destination: e.state.warpSystem, clicksRemaining: 1, viaWormhole: false))
        let events = e.continueTransit()
        #expect(!events.contains { if case .encounterStarted = $0 { true } else { false } })
        #expect(events.contains(.uneventfulTrip))
        #expect(e.state.phase == .docked)
    }

    @Test("ENC-003 a shown encounter enters .encounter; Normal resumes transit, Arrested/EscapePod arrive, Killed ends the game")
    func encounterResults() throws {
        var shown = EncSpec.engine { s in
            s.warpSystem = SystemID.acamar
            s.quests.spaceMonster = QuestStatus.SpaceMonster.atAcamar
        }
        shown.state.phase = .inTransit(TransitState(destination: SystemID.acamar, clicksRemaining: 1, viaWormhole: false))
        let events = shown.continueTransit()
        let enc = try #require(EncSpec.current(shown))
        #expect(events.last == .encounterStarted(type: .spaceMonsterAttack, opponent: .spaceMonster, clicks: 1, playerCloaked: false))
        #expect(enc.clicks == 1)

        // Normal: the click counter decrements and transit continues.
        var n = EncSpec.encounter(.pirateIgnore)
        n.state.encounterTransit?.clicksRemaining = 5
        _ = n.finishEncounter(.normal)
        switch n.state.phase {
        case let .encounter(next): #expect(next.clicks < 5)
        case .docked: #expect(n.state.commander.currentSystem == n.state.warpSystem)
        default: Issue.record("unexpected phase \(n.state.phase)")
        }

        // Arrested (surrender to police): the remaining clicks are dropped, the arrest runs, then arrival.
        var a = EncSpec.encounter(.policeAttack)
        a.state.encounterTransit?.clicksRemaining = 5
        let ar = a.perform(.encounter(.surrender), acknowledging: [.surrenderToPolice])
        #expect(ar.events.contains { if case .arrested = $0 { true } else { false } })
        #expect(ar.events.contains(.arrived(system: a.state.warpSystem)) && a.state.phase == .docked)

        // EscapePod: the remaining clicks are dropped, the escape-pod sequence runs, then arrival.
        var p = EncSpec.encounter(.pirateAttack) { s in s.commander.ship.escapePod = true }
        p.state.encounterTransit?.clicksRemaining = 5
        let pe = p.finishEncounter(.escapePod)
        #expect(pe.contains { if case .escapePodUsed = $0 { true } else { false } })
        #expect(p.state.phase == .docked && p.state.commander.ship.type == .flea)
        #expect(p.state.commander.currentSystem == p.state.warpSystem)

        var k = EncSpec.encounter(.pirateAttack)
        _ = k.finishEncounter(.killed)
        #expect(k.state.phase == .gameOver(.killed))
    }

    @Test("ENC-010 fixed checks in order monster, Scarab, Dragonfly, Scorpion, customs; only customs draws from the RNG")
    func fixedOrder() {
        func run(clicks: Int, _ adjust: (inout GameState) -> Void) -> (EncounterType?, Bool) {
            var s = EncSpec.engine(.normal, adjust).state
            let before = s.rng
            let enc = s.determineFixedEncounter(clicks: clicks)
            return (enc?.type, s.rng == before)
        }
        let monster: (inout GameState) -> Void = { s in s.warpSystem = SystemID.acamar; s.quests.spaceMonster = 1 }
        #expect(run(clicks: 1, monster) == (.spaceMonsterAttack, true))
        #expect(run(clicks: 2, monster).0 == nil)
        let scarab: (inout GameState) -> Void = { s in
            s.arrivedViaWormhole = true
            s.galaxy.systems[s.warpSystem].specialEvent = .scarabDestroyed
            s.quests.scarab = QuestStatus.Scarab.hunting
        }
        #expect(run(clicks: 20, scarab) == (.scarabAttack, true))
        #expect(run(clicks: 19, scarab).0 == nil)
        #expect(run(clicks: 20) { s in scarab(&s); s.arrivedViaWormhole = false }.0 == nil)
        let dragonfly: (inout GameState) -> Void = { s in s.warpSystem = SystemID.zalkon; s.quests.dragonfly = QuestStatus.Dragonfly.flyZalkon }
        #expect(run(clicks: 1, dragonfly) == (.dragonflyAttack, true))
        let scorpion: (inout GameState) -> Void = { s in s.warpSystem = SystemID.qonos; s.quests.princess = QuestStatus.Princess.flyQonos }
        #expect(run(clicks: 1, scorpion) == (.scorpionAttack, true))
        let customs: (inout GameState) -> Void = { s in s.quests.justLootedMarie = true }
        #expect(run(clicks: 1, customs) == (.marieCelestePolice, false))
        #expect(run(clicks: 2, customs).0 == nil)
        // First match wins: the monster and the Dragonfly take click 1 ahead of the customs police.
        #expect(run(clicks: 1) { s in monster(&s); customs(&s) } == (.spaceMonsterAttack, true))
        #expect(run(clicks: 1) { s in dragonfly(&s); customs(&s) } == (.dragonflyAttack, true))
        #expect(run(clicks: 1) { _ in }.0 == nil)
    }

    @Test("ENC-011 quest ships start as …Ignore when the player is cloaked against that ship, else …Attack, and are always shown")
    func fixedCloak() {
        func initial(_ adjust: (inout GameState) -> Void) -> EncounterType? {
            var s = EncSpec.engine { s in
                adjust(&s)
                s.options.alwaysIgnorePirates = true
                s.options.alwaysIgnorePolice = true
                s.options.alwaysIgnoreTraders = true
            }.state
            return s.determineFixedEncounter(clicks: s.arrivedViaWormhole ? 20 : 1)?.type
        }
        let cloak: (inout GameState) -> Void = { s in
            s.commander.ship.gadgets = [.cloakingDevice]
            s.mercenaries[CrewID.commander].skills[3] = 10
        }
        let monster: (inout GameState) -> Void = { s in s.warpSystem = SystemID.acamar; s.quests.spaceMonster = 1 }
        let scarab: (inout GameState) -> Void = { s in
            s.arrivedViaWormhole = true
            s.galaxy.systems[s.warpSystem].specialEvent = .scarabDestroyed
            s.quests.scarab = 1
        }
        let dragonfly: (inout GameState) -> Void = { s in s.warpSystem = SystemID.zalkon; s.quests.dragonfly = 4 }
        let scorpion: (inout GameState) -> Void = { s in s.warpSystem = SystemID.qonos; s.quests.princess = 3 }
        #expect(initial(monster) == .spaceMonsterAttack)
        #expect(initial { s in monster(&s); cloak(&s) } == .spaceMonsterIgnore)       // engineer 10 > monster 1+D = 3
        #expect(initial(scarab) == .scarabAttack)
        #expect(initial { s in scarab(&s); cloak(&s) } == .scarabIgnore)             // 10 > 6+D = 8
        // Engineer 6+D = 8 plus the auto-repair system (+3) = 11 beats the cloak: not cloaked against these ships.
        #expect(initial { s in dragonfly(&s); cloak(&s) } == .dragonflyAttack)
        #expect(initial { s in scorpion(&s); cloak(&s) } == .scorpionAttack)
        #expect(initial { s in dragonfly(&s); cloak(&s); s.commander.ship.gadgets.append(.autoRepairSystem) } == .dragonflyIgnore)
        #expect(initial { s in scorpion(&s); cloak(&s); s.commander.ship.gadgets.append(.autoRepairSystem) } == .scorpionIgnore)
    }

    @Test("ENC-012 ENC-165 the quest ship is the persistent special ship; its damage, charges and cargo are written back when the encounter ends")
    func specialShipPersists() throws {
        var e = EncSpec.engine { s in s.warpSystem = SystemID.acamar; s.quests.spaceMonster = 1 }
        e.state.phase = .inTransit(TransitState(destination: SystemID.acamar, clicksRemaining: 1, viaWormhole: false))
        _ = e.continueTransit()
        var enc = try #require(EncSpec.current(e))
        #expect(enc.opponent == e.state.specialShips.spaceMonster)
        enc.opponent.hull = 123
        e.state.phase = .encounter(enc)
        _ = e.finishEncounter(.normal)
        #expect(EncSpec.current(e) == nil, "the EncounterState is discarded")
        #expect(e.state.specialShips.spaceMonster.hull == 123)

        var d = EncSpec.engine { s in s.warpSystem = SystemID.zalkon; s.quests.dragonfly = 4 }
        let found = d.state.determineFixedEncounter(clicks: 1)
        var dragon = try #require(found)
        #expect(d.state.specialShips.dragonfly.shields[0].charge == 350)
        dragon.opponent.shields[0].charge = 7
        dragon.opponent.cargo[0] = 2
        EncSpec.enter(&d, dragon.type, opponent: dragon.opponent)
        _ = d.finishEncounter(.normal)
        #expect(d.state.specialShips.dragonfly.shields[0].charge == 7 && d.state.specialShips.dragonfly.cargo[0] == 2)
        // A generated (non-quest) opponent never touches the special ships.
        var g = EncSpec.encounter(.pirateAttack)
        let before = g.state.specialShips
        _ = g.finishEncounter(.normal)
        #expect(g.state.specialShips == before)
    }

    @Test("ENC-014 special-ship loadouts and their crew skills are fixed at new game")
    func specialLoadouts() {
        for diff in Difficulty.allCases {
            let s = EncSpec.engine(diff).state
            let d = diff.rawValue
            let sp = s.specialShips
            #expect(sp.dragonfly.weapons == [.militaryLaser, .pulseLaser])
            #expect(sp.dragonfly.shields == Array(repeating: ShieldInstance(type: .lightning, charge: 350), count: 3))
            #expect(sp.dragonfly.gadgets == [.autoRepairSystem, .targetingSystem])
            #expect(sp.scarab.weapons == [.militaryLaser, .militaryLaser] && sp.scarab.shields.isEmpty && sp.scarab.gadgets.isEmpty)
            #expect(sp.scorpion.weapons == [.militaryLaser, .militaryLaser])
            #expect(sp.scorpion.shields == Array(repeating: ShieldInstance(type: .reflective, charge: 200), count: 2))
            #expect(sp.scorpion.gadgets == [.autoRepairSystem, .targetingSystem])
            #expect(sp.spaceMonster.weapons == Array(repeating: .militaryLaser, count: 3) && sp.spaceMonster.shields.isEmpty)
            #expect(sp.dragonfly.crew[0] == CrewID.dragonfly && sp.scarab.crew[0] == CrewID.scarab)
            #expect(sp.scorpion.crew[0] == CrewID.scorpion && sp.spaceMonster.crew[0] == CrewID.spaceMonster)
            #expect(s.mercenaries[CrewID.dragonfly].skills == [4 + d, 6 + d, 1, 6 + d])
            #expect(s.mercenaries[CrewID.scarab].skills == [5 + d, 6 + d, 1, 6 + d])
            #expect(s.mercenaries[CrewID.scorpion].skills == [8 + d, 8 + d, 1, 6 + d])
            #expect(s.mercenaries[CrewID.spaceMonster].skills == [8 + d, 8 + d, 1, 1 + d])
        }
    }

    @Test("ENC-015 customs: a generated police opponent, type marieCelestePolice, flag cleared, shown despite cloak and options")
    func customs() throws {
        var s = EncSpec.engine { s in
            s.quests.justLootedMarie = true
            s.options.alwaysIgnorePolice = true
            s.commander.ship.gadgets = [.cloakingDevice]
            s.mercenaries[CrewID.commander].skills[3] = 10
        }.state
        var g = s
        let expected = g.generateOpponent(.police)
        let found = s.determineFixedEncounter(clicks: 1)
        let enc = try #require(found)
        #expect(enc.type == .marieCelestePolice)
        #expect(enc.opponent == expected && s.rng == g.rng)
        #expect(!s.quests.justLootedMarie)
    }

    @Test("ENC-016 justLootedMarie survives a click 1 taken by an earlier fixed check; customs appear on a later trip")
    func customsDeferred() {
        var s = EncSpec.engine { s in
            s.quests.justLootedMarie = true
            s.warpSystem = SystemID.acamar
            s.quests.spaceMonster = 1
        }.state
        #expect(s.determineFixedEncounter(clicks: 1)?.type == .spaceMonsterAttack)
        #expect(s.quests.justLootedMarie)
        s.warpSystem = s.commander.currentSystem == 1 ? 2 : 1
        #expect(s.determineFixedEncounter(clicks: 1)?.type == .marieCelestePolice)
        #expect(!s.quests.justLootedMarie)
    }
}

// MARK: - §2 Random encounter roll

@Suite("ENC §2: random encounter roll")
struct EncounterRollTests {
    static let policeTypes: Set<EncounterType> = [.policeAttack, .policeIgnore, .policeFlee, .policeSurrender, .policeInspect]

    @Test("ENC-020 ENC-026 invaded Gemulon: exactly one draw, rand(10) > 4 → a Mantis pirate encounter")
    func gemulon() throws {
        var s = EncSpec.engine { s in
            s.warpSystem = SystemID.gemulon
            s.quests.gemulon = QuestStatus.Gemulon.tooLate
            s.commander.days = 50
            s.chanceOfVeryRareEncounter = 1000
        }.state
        var hit = s
        EncSpec.seek(&hit) { p in p.next(below: 10) > 4 }
        let mantis = EncSpec.opponent(hit, .mantis, after: [10])
        let found = hit.determineRandomEncounter(clicks: 3)
        let enc = try #require(found)
        #expect(enc.type == .pirateAttack && enc.opponent.type == .mantis && enc.opponent == mantis)
        EncSpec.seek(&s) { p in p.next(below: 10) <= 4 }
        let one = EncSpec.after(s, [10])
        // No pirate/police/trader band applies; with no flag the very-rare check follows (rand(1000)).
        var miss = s
        miss.veryRareEncounters = []
        #expect(miss.determineRandomEncounter(clicks: 3) == nil)
        var expectedRNG = one
        _ = expectedRNG.next(below: 1000)
        #expect(miss.rng == expectedRNG)
    }

    /// Positions the RNG so that the band roll `rand(44 − 2D)` is `value`, then determines the encounter.
    static func roll(_ value: Int, _ adjust: (inout GameState) -> Void, then extra: [(Int, (Int) -> Bool)] = [])
        -> (GameState, EncounterState?, GameState) {
        var s = EncSpec.engine { s in
            s.options.alwaysIgnoreTraders = false
            s.commander.days = 0
            adjust(&s)
        }.state
        let n = 44 - 2 * s.difficulty.rawValue
        EncSpec.seek(&s) { p in
            guard p.next(below: n) == value else { return false }
            return extra.allSatisfy { pair in pair.1(p.next(below: pair.0)) }
        }
        let start = s
        let enc = s.determineRandomEncounter(clicks: 5)
        return (start, enc, s)
    }

    @Test("ENC-021 r = rand(44 − 2D), doubled for a Flea; policeModifier 3 / 2 / 1 for rec < −70 / < −30 / otherwise")
    func bandRoll() {
        // Confederacy: P 3, Q 4, T 5. Police band is r < 3 + 4 × modifier; trader band then up to + 5.
        let cases: [(record: Int, r: Int, police: Bool)] = [
            (-80, 11, true), (-71, 11, true), (-70, 11, false), (-50, 11, false),
            (-50, 8, true), (-31, 8, true), (-30, 8, false), (0, 8, false),
        ]
        for c in cases {
            let (start, _, end) = Self.roll(c.r) { s in s.commander.policeRecordScore = c.record }
            let kind: OpponentType = c.police ? .police : .trader
            #expect(end.lastOpponent == EncSpec.opponent(start, kind, after: [40]), "record \(c.record) r \(c.r)")
            #expect(max(1, 3 - start.policeRecord.rawValue) == (c.record < -70 ? 3 : c.record < -30 ? 2 : 1))
        }
        // Flea: r = 4 → 8 lands in the trader band; the same roll on a Grasshopper is police.
        let (fs, _, fe) = Self.roll(4) { s in s.commander.ship = EncSpec.ship(s, .flea) }
        #expect(fe.lastOpponent == EncSpec.opponent(fs, .trader, after: [40]))
        let (gs, _, ge) = Self.roll(4) { _ in }
        #expect(ge.lastOpponent == EncSpec.opponent(gs, .police, after: [40]))
    }

    @Test("ENC-022 ENC-024 bands pirate, police, trader; then the Kravat/Wild police roll; then the artifact Mantis roll")
    func bands() throws {
        let (ps, pEnc, pe) = Self.roll(1) { _ in }
        #expect(pe.lastOpponent == EncSpec.opponent(ps, .pirate, after: [40]))
        #expect(pEnc.map { [.pirateAttack, .pirateFlee, .pirateIgnore].contains($0.type) } ?? true)
        let (ts, tEnc, te) = Self.roll(9) { _ in }
        #expect(te.lastOpponent == EncSpec.opponent(ts, .trader, after: [40]))
        #expect(tEnc.map { [.traderIgnore, .traderBuy, .traderSell, .traderFlee].contains($0.type) } ?? true)
        let (cs, cEnc, ce) = Self.roll(5) { _ in }
        #expect(ce.lastOpponent == EncSpec.opponent(cs, .police, after: [40]))
        #expect(cEnc.map { Self.policeTypes.contains($0.type) } ?? true)

        // Kravat with Wild aboard: rand(100) < 100 / max(2, min(4, 5 − D)) → police (25, 25, 33, 50, 50 %).
        let wild: (inout GameState) -> Void = { s in
            s.warpSystem = SystemID.kravat
            s.galaxy.systems[SystemID.kravat].politics = .confederacy
            s.commander.ship.crew[1] = CrewID.wild
            s.quests.artifact = QuestStatus.Artifact.onBoard
        }
        for (d, limit) in zip(Difficulty.allCases, [25, 25, 33, 50, 50]) {
            let (ks, _, ke) = Self.roll(30, { s in wild(&s); s.difficulty = d }, then: [(100, { $0 == limit - 1 })])
            #expect(ke.lastOpponent == EncSpec.opponent(ks, .police, after: [44 - 2 * d.rawValue, 100]), "D \(d)")
            let (ms, mEnc, me) = Self.roll(30, { s in wild(&s); s.difficulty = d }, then: [(100, { $0 == limit })])
            #expect(mEnc == nil && me.rng == EncSpec.after(ms, [44 - 2 * d.rawValue, 100]), "failed Kravat roll: no Mantis roll (D \(d))")
        }
        // Artifact aboard (no Wild): rand(20) ≤ 3 → Mantis.
        let art: (inout GameState) -> Void = { s in s.quests.artifact = QuestStatus.Artifact.onBoard }
        let (as3, aEnc, _) = Self.roll(30, art, then: [(20, { $0 == 3 })])
        let mantis = try #require(aEnc)
        #expect(mantis.type == .pirateAttack && mantis.opponent == EncSpec.opponent(as3, .mantis, after: [40, 20]))
        let (as4, a4, a4e) = Self.roll(30, art, then: [(20, { $0 == 4 })])
        #expect(a4 == nil && a4e.rng == EncSpec.after(as4, [40, 20]))
    }

    @Test("ENC-023 raided: a pirate-band roll sets no flag and skips the Kravat and Mantis rolls, going to the very-rare check")
    func raidedPirateBand() {
        let setup: (inout GameState) -> Void = { s in
            s.raided = true
            s.warpSystem = SystemID.kravat
            s.galaxy.systems[SystemID.kravat].politics = .confederacy
            s.commander.ship.crew[1] = CrewID.wild
            s.quests.artifact = QuestStatus.Artifact.onBoard
            s.veryRareEncounters = []
        }
        let (s, enc, e) = Self.roll(1, setup)
        #expect(enc == nil && e.rng == EncSpec.after(s, [40]))
        let (s2, enc2, e2) = Self.roll(1) { s in setup(&s); s.commander.days = 11 }
        #expect(enc2 == nil && e2.rng == EncSpec.after(s2, [40, 1000]), "only the very-rare rand(1000) follows")
    }
}

// MARK: - §3 Very rare encounters

@Suite("ENC §3: very rare encounters")
struct EncounterVeryRareTests {
    static func state(_ adjust: (inout GameState) -> Void = { _ in }) -> GameState {
        EncSpec.engine { s in
            s.mercenaries[CrewID.commander].skills = [5, 5, 5, 5]
            adjust(&s)
        }.state
    }

    @Test("ENC-040 attempted iff days > 10, rand(1000) < chance and a non-empty list; rand(1000) is drawn even when the list is empty")
    func gate() {
        let (s0, e0, f0) = EncounterRollTests.roll(30) { s in s.commander.days = 10; s.chanceOfVeryRareEncounter = 1000 }
        #expect(e0 == nil && f0.rng == EncSpec.after(s0, [40]))
        let (s1, e1, f1) = EncounterRollTests.roll(30) { s in s.commander.days = 11; s.veryRareEncounters = [] }
        #expect(e1 == nil && f1.rng == EncSpec.after(s1, [40, 1000]))
        let (s2, e2, f2) = EncounterRollTests.roll(30) { s in s.commander.days = 11; s.chanceOfVeryRareEncounter = 0 }
        #expect(e2 == nil && f2.rng == EncSpec.after(s2, [40, 1000]) && f2.veryRareEncounters.count == 6)
        let (_, e3, _) = EncounterRollTests.roll(30) { s in
            s.commander.days = 11
            s.chanceOfVeryRareEncounter = 1000
            s.veryRareEncounters = [.bottleGood]
        }
        #expect(e3?.type == .bottleGood, "no flag dispatches to the very-rare check (ENC-024)")
    }

    @Test("ENC-041 picks remaining[rand(count)]; a met condition removes it (order kept), an unmet one leaves the list unchanged")
    func selection() {
        for pick in 0..<2 {
            var s = Self.state { s in s.veryRareEncounters = [.marieCeleste, .bottleOld] }
            EncSpec.seek(&s) { p in p.next(below: 2) == pick }
            let enc = s.determineVeryRare(clicks: 1)     // clicks 1: the Marie Celeste condition fails
            if pick == 0 {
                #expect(enc == nil && s.veryRareEncounters == [.marieCeleste, .bottleOld])
            } else {
                #expect(enc?.type == .bottleOld && s.veryRareEncounters == [.marieCeleste])
            }
        }
        var full = Self.state()
        #expect(full.veryRareEncounters == [.marieCeleste, .captainAhab, .captainConrad, .captainHuie, .bottleOld, .bottleGood])
        EncSpec.seek(&full) { p in p.next(below: 6) == 4 }
        #expect(full.determineVeryRare(clicks: 5)?.type == .bottleOld)
        #expect(full.veryRareEncounters == [.marieCeleste, .captainAhab, .captainConrad, .captainHuie, .bottleGood])
    }

    @Test("ENC-042 Marie Celeste (Windows): clicks > 1 and the departure system not Acamar/Zalkon/Qonos; trader hull with ≤ 5 narcotics only")
    func marieCeleste() throws {
        for departure in [SystemID.acamar, SystemID.zalkon, SystemID.qonos] {
            var s = Self.state { s in s.veryRareEncounters = [.marieCeleste]; s.commander.currentSystem = departure }
            #expect(s.determineVeryRare(clicks: 5) == nil && s.veryRareEncounters == [.marieCeleste])
        }
        var c1 = Self.state { s in s.veryRareEncounters = [.marieCeleste] }
        #expect(c1.determineVeryRare(clicks: 1) == nil)
        // Windows 2.01 tests the departure system: a trip *to* Acamar still meets her.
        var s = Self.state { s in s.veryRareEncounters = [.marieCeleste]; s.warpSystem = SystemID.acamar }
        let trader = EncSpec.opponent(s, .trader, after: [1])
        let found = s.determineVeryRare(clicks: 5)
        let enc = try #require(found)
        #expect(enc.type == .marieCeleste && s.veryRareEncounters.isEmpty)
        var cargo = Array(repeating: 0, count: 10)
        cargo[TradeItemType.narcotics.rawValue] = min(trader.cargoBays(s.ruleset), 5)
        #expect(enc.opponent.type == trader.type && enc.opponent.weapons == trader.weapons && enc.opponent.cargo == cargo)
    }

    @Test("ENC-044 famous captains need rec > −30 plus equipment and a raw commander skill below 10")
    func captains() {
        func meet(_ v: VeryRareEncounter, _ adjust: (inout GameState) -> Void) -> EncounterType? {
            var s = Self.state { s in s.veryRareEncounters = [v]; adjust(&s) }
            return s.determineVeryRare(clicks: 5)?.type
        }
        let reflective: (inout GameState) -> Void = { s in s.commander.ship.shields = [ShieldInstance(type: .reflective, charge: 200)] }
        #expect(meet(.captainAhab, reflective) == .captainAhab)
        #expect(meet(.captainAhab) { _ in } == nil)
        #expect(meet(.captainAhab) { s in reflective(&s); s.commander.policeRecordScore = -30 } == nil)
        #expect(meet(.captainAhab) { s in reflective(&s); s.commander.policeRecordScore = -29 } == .captainAhab)
        #expect(meet(.captainAhab) { s in reflective(&s); s.mercenaries[0].skills[0] = 10 } == nil)
        // Raw skill, not ship skill: a navigating system (+3 pilot) does not disqualify a raw pilot of 9.
        #expect(meet(.captainAhab) { s in reflective(&s); s.mercenaries[0].skills[0] = 9; s.commander.ship.gadgets = [.navigatingSystem] } == .captainAhab)
        #expect(meet(.captainConrad) { _ in } == .captainConrad)                 // military laser fitted by EncSpec
        #expect(meet(.captainConrad) { s in s.mercenaries[0].skills[3] = 10 } == nil)
        #expect(meet(.captainConrad) { s in s.commander.ship.weapons = [.beamLaser] } == nil)
        #expect(meet(.captainHuie) { _ in } == .captainHuie)
        #expect(meet(.captainHuie) { s in s.mercenaries[0].skills[2] = 10 } == nil)
        #expect(meet(.captainHuie) { s in s.commander.ship.weapons = [.morgansLaser] } == nil, "exact type: Morgan's is not a military laser")
        var s = Self.state { s in s.veryRareEncounters = [.captainHuie] }
        #expect(s.determineVeryRare(clicks: 5)?.opponent.crew[0] == CrewID.famousCaptain)
    }

    @Test("ENC-045 ENC-047 bottles have no condition; very-rare encounters skip cloak and always-ignore and start as their own type")
    func bottlesAndVisibility() {
        for v in [VeryRareEncounter.bottleOld, .bottleGood] {
            var s = Self.state { s in
                s.veryRareEncounters = [v]
                s.options.alwaysIgnorePirates = true
                s.options.alwaysIgnorePolice = true
                s.options.alwaysIgnoreTraders = true
                s.options.alwaysIgnoreTradeInOrbit = true
                s.commander.ship.gadgets = [.cloakingDevice]
                s.mercenaries[CrewID.commander].skills[3] = 10
            }
            let enc = s.determineVeryRare(clicks: 5)
            #expect(enc?.type == (v == .bottleOld ? .bottleOld : .bottleGood))
            #expect(enc?.opponent.type == .bottle)
        }
        var c = Self.state { s in
            s.veryRareEncounters = [.captainConrad]
            s.options.alwaysIgnorePirates = true
            s.options.alwaysIgnoreTraders = true
            s.commander.ship.gadgets = [.cloakingDevice]
            s.mercenaries[CrewID.commander].skills[3] = 9   // raw engineer must stay below 10 for Conrad
        }
        #expect(c.determineVeryRare(clicks: 5)?.type == .captainConrad)
    }
}
