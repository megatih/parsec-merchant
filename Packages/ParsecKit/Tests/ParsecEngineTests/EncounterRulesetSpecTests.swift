// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecEngine

/// Builders for the M5 encounter ruleset tests (Windows 2.01 vs Modern vs Palm 1.2.2).
enum RS {
    static func state(_ r: RulesetID, _ d: Difficulty = .normal, seed: UInt64 = 11, _ adjust: (inout GameState) -> Void = { _ in }) -> GameState {
        var s = GameState(config: NewGameConfig(commanderName: "Rules", difficulty: d, ruleset: r, seed: seed))
        s.commander.ship = CombatKit.playerShip(s, .gnat, weapons: [.pulseLaser])
        s.commander.days = 5
        s.commander.policeRecordScore = 0
        s.commander.reputationScore = 0
        adjust(&s)
        return s
    }

    /// Number of RNG draws between two states (each `next(below:)` consumes one step), or nil beyond `limit`.
    static func draws(_ from: RNGState, _ to: RNGState, limit: Int = 400) -> Int? {
        var r = from
        for n in 0...limit {
            if r == to { return n }
            _ = r.next(below: 2)
        }
        return nil
    }

    /// Advances the state's RNG `k` steps (to explore draw outcomes deterministically).
    static func advanced(_ s: GameState, _ k: Int) -> GameState {
        var c = s
        for _ in 0..<k { _ = c.rng.next(below: 2) }
        return c
    }

    /// Peeks the next draws `next(below: n)` for each bound without changing `s`.
    static func peek(_ s: GameState, _ bounds: [Int]) -> [Int] {
        var r = s.rng
        return bounds.map { r.next(below: $0) }
    }

    static func gnatOpponent(_ s: inout GameState, _ type: ShipType = .gnat, weapons: [WeaponType] = [.pulseLaser],
                             skills: [Int] = [5, 5, 5, 5]) -> Ship {
        CombatKit.opponent(&s, type, weapons: weapons, skills: skills)
    }
}

@Suite("RUL §2 / ENC: encounter determination by ruleset")
struct EncounterDeterminationRulesetTests {
    @Test("RUL-130 POL-007 police constants: −30/−70/−100 (Modern, Windows) and −10/−30/−70 (Palm); displayed levels unchanged")
    func constants() {
        #expect(Ruleset.windows201.flags.encounter.policeConstants == PoliceConstants(criminal: -30, villain: -70, psychopath: -100))
        #expect(Ruleset.modern.flags.encounter.policeConstants == .windows)
        #expect(Ruleset.palm122.flags.encounter.policeConstants == PoliceConstants(criminal: -10, villain: -30, psychopath: -70))
        // The displayed thresholds are ruleset independent (POL-002): −30 is "Criminal", −70 "Villain", below −70 "Psychopath".
        #expect(PoliceRecordType(score: -10) == .crook && PoliceRecordType(score: -30) == .criminal)
        #expect(PoliceRecordType(score: -70) == .villain && PoliceRecordType(score: -71) == .psychopath)
    }

    @Test("RUL-074 ENC-046 captains need record > −30 (Modern, Windows) or > −10 (Palm)")
    func captainThreshold() {
        for r in [RulesetID.windows201, .modern] {
            var s = RS.state(r) { s in
                s.veryRareEncounters = [.captainAhab]
                s.commander.ship.shields = [ShieldInstance(type: .reflective, charge: 1)]
                s.mercenaries[CrewID.commander].skills[0] = 5
                s.commander.policeRecordScore = -29
            }
            #expect(s.determineVeryRare(clicks: 5)?.type == .captainAhab)
            s.veryRareEncounters = [.captainAhab]
            s.commander.policeRecordScore = -30
            #expect(s.determineVeryRare(clicks: 5) == nil)
        }
        let base = RS.state(.palm122) { s in
            s.veryRareEncounters = [.captainAhab]
            s.commander.ship.shields = [ShieldInstance(type: .reflective, charge: 1)]
            s.mercenaries[CrewID.commander].skills[0] = 5
        }
        var met = 0
        for k in 0..<60 {
            var ok = RS.advanced(base, k)
            ok.commander.policeRecordScore = -9
            var bad = ok
            bad.commander.policeRecordScore = -10
            if ok.determineVeryRare(clicks: 5)?.type == .captainAhab {
                met += 1
                #expect(bad.determineVeryRare(clicks: 5) == nil)
            }
        }
        #expect(met > 0)
    }

    @Test("RUL-073 ENC-046 very rare pick: uniform over the remaining list (Modern, Windows) vs rand(6) over all six (Palm)")
    func veryRarePick() {
        for k in 0..<30 {
            var s = RS.advanced(RS.state(.windows201) { $0.veryRareEncounters = [.bottleGood] }, k)
            #expect(s.determineVeryRare(clicks: 5)?.type == .bottleGood)
        }
        var results: Set<String> = []
        let base = RS.state(.palm122) { $0.veryRareEncounters = [.bottleGood] }
        for k in 0..<60 {
            var s = RS.advanced(base, k)
            let pick = RS.peek(s, [6])[0]
            let enc = s.determineVeryRare(clicks: 5)
            // Only the still-available entry yields an encounter; an already-used pick yields nothing and keeps the list.
            if pick == VeryRareEncounter.bottleGood.rawValue {
                #expect(enc?.type == .bottleGood && enc?.opponent.hull == 10 && enc?.opponent.type == .bottle)
                #expect(s.veryRareEncounters.isEmpty)
            } else {
                #expect(enc == nil && s.veryRareEncounters == [.bottleGood])
            }
            results.insert(enc == nil ? "none" : "bottle")
        }
        #expect(results == ["none", "bottle"])
    }

    @Test("ENC-046 Palm bottle: a full trader is generated first (its draws are consumed), then a Bottle with hull 10")
    func palmBottleDraws() {
        var w = RS.state(.windows201) { $0.veryRareEncounters = [.bottleOld] }
        let w0 = w.rng
        #expect(w.determineVeryRare(clicks: 5)?.type == .bottleOld)
        #expect(RS.draws(w0, w.rng) == 1) // only the pick
        let base = RS.state(.palm122) { $0.veryRareEncounters = [.bottleOld] }
        let k = (0..<60).first { RS.peek(RS.advanced(base, $0), [6])[0] == VeryRareEncounter.bottleOld.rawValue } ?? 0
        var p = RS.advanced(base, k)
        let p0 = p.rng
        let enc = p.determineVeryRare(clicks: 5)
        #expect(enc?.type == .bottleOld && enc?.opponent.hull == 10)
        #expect((RS.draws(p0, p.rng) ?? 0) > 5)
    }

    @Test("RUL-110 ENC-043 ENC-046 Marie Celeste: departure (Windows), destination (Modern), no restriction (Palm)")
    func marieRestriction() {
        func make(_ r: RulesetID, from: Int, to: Int, clicks: Int, k: Int = 0) -> EncounterType? {
            var s = RS.advanced(RS.state(r) { s in
                s.veryRareEncounters = [.marieCeleste]
                s.commander.currentSystem = from
                s.warpSystem = to
            }, k)
            return s.determineVeryRare(clicks: clicks)?.type
        }
        let other = SystemID.acamar == 1 ? 2 : 1
        #expect(make(.windows201, from: SystemID.acamar, to: other, clicks: 5) == nil)
        #expect(make(.windows201, from: other, to: SystemID.acamar, clicks: 5) == .marieCeleste)
        #expect(make(.modern, from: SystemID.acamar, to: other, clicks: 5) == .marieCeleste)
        #expect(make(.modern, from: other, to: SystemID.acamar, clicks: 5) == nil)
        #expect(make(.modern, from: other, to: other == 1 ? 3 : 1, clicks: 1) == nil) // clicks > 1 kept
        // Palm: whenever the pick is the Marie Celeste, even at click 1 bound for Acamar; narcotics ≤ base bays and 5.
        let base = RS.state(.palm122) { s in
            s.veryRareEncounters = [.marieCeleste]
            s.warpSystem = SystemID.acamar
        }
        let k = (0..<60).first { RS.peek(RS.advanced(base, $0), [6])[0] == 0 } ?? 0
        var s = RS.advanced(base, k)
        let enc = s.determineVeryRare(clicks: 1)
        #expect(enc?.type == .marieCeleste)
        if let opp = enc?.opponent {
            #expect(opp.cargo[TradeItemType.narcotics.rawValue] == min(opp.spec(s.ruleset).cargoBays, 5))
        }
    }

    @Test("RUL-070 ENC-004 post-Marie customs: click 1 inside the loop (Windows) vs after the loop, then straight to arrival (Palm)")
    func postMarieTiming() {
        var w = RS.state(.windows201) { $0.quests.justLootedMarie = true }
        #expect(w.determineFixedEncounter(clicks: 1)?.type == .marieCelestePolice)
        var p = RS.state(.palm122) { $0.quests.justLootedMarie = true }
        #expect(p.determineFixedEncounter(clicks: 1) == nil && p.quests.justLootedMarie)
        // Palm: an exhausted loop shows the customs encounter; finishing it arrives with no further click.
        var e = GameEngine(state: RS.state(.palm122) { s in
            s.quests.justLootedMarie = true
            s.phase = .inTransit(TransitState(destination: s.warpSystem, clicksRemaining: 0, viaWormhole: false))
        })
        let events = e.continueTransit()
        guard case let .encounter(enc) = e.state.phase else { Issue.record("no customs encounter"); return }
        #expect(enc.type == .marieCelestePolice && events.count == 1)
        #expect(e.state.encounterTransit?.clicksRemaining == 1)
        let r = e.perform(.encounter(.yield)) // Palm yields without confirmation when nothing special is aboard
        #expect(e.state.phase == .docked)
        #expect(r.events.contains(.arrived(system: e.state.warpSystem)))
    }

    @Test("RUL-071 ENC-025 a raided pirate-band roll: no encounter (Windows) vs a police encounter (Palm)")
    func raidedFallthrough() {
        func find(_ r: RulesetID) -> GameState {
            let base = RS.state(r) { s in
                s.raided = true
                s.galaxy.systems[s.warpSystem].politics = .anarchy
            }
            let pir = base.ruleset.tables.politics(.anarchy).activityPirates.rawValue
            let k = (0..<200).first { RS.peek(RS.advanced(base, $0), [44 - 4])[0] < pir } ?? 0
            return RS.advanced(base, k)
        }
        var w = find(.windows201)
        let w0 = w.rng
        #expect(w.determineRandomEncounter(clicks: 5) == nil)
        #expect(RS.draws(w0, w.rng) == 1)
        var p = find(.palm122)
        let p0 = p.rng
        let enc = p.determineRandomEncounter(clicks: 5)
        #expect((RS.draws(p0, p.rng) ?? 0) > 3) // a police opponent was generated
        if let enc { #expect([.policeIgnore, .policeInspect, .policeFlee, .policeAttack].contains(enc.type)) }
    }

    @Test("RUL-072 ENC-025 artifact Mantis roll after a failed Kravat roll: never (Windows) vs always drawn (Palm); Kravat chance equal")
    func mantisAfterKravat() {
        // The Kravat chance: C# 100/max(2, min(4, 5 − D)) equals Palm's 25 / 33 / 50 % for D ≤ Easy / Normal / ≥ Hard.
        for d in Difficulty.allCases {
            let palm = d <= .easy ? 25 : (d == .normal ? 33 : 50)
            #expect(100 / max(2, min(4, 5 - d.rawValue)) == palm)
        }
        func find(_ r: RulesetID) -> GameState {
            let base = RS.state(r) { s in
                s.warpSystem = SystemID.kravat
                boardWild(&s)
                s.quests.artifact = QuestStatus.Artifact.onBoard
            }
            let gov = base.ruleset.tables.politics(base.galaxy.systems[SystemID.kravat].politics)
            let band = gov.activityPirates.rawValue + gov.activityPolice.rawValue * max(1, 3 - base.policeRecord.rawValue)
                + gov.activityTraders.rawValue
            let k = (0..<400).first {
                let v = RS.peek(RS.advanced(base, $0), [40, 100])
                return v[0] >= band && v[1] >= 33
            } ?? 0
            return RS.advanced(base, k)
        }
        var w = find(.windows201)
        let w0 = w.rng
        #expect(w.determineRandomEncounter(clicks: 5) == nil)
        #expect(RS.draws(w0, w.rng) == 2)
        var p = find(.palm122)
        let p0 = p.rng
        let mantis = RS.peek(RS.advanced(p, 2), [20])[0] <= 3
        let enc = p.determineRandomEncounter(clicks: 5)
        if mantis {
            #expect(enc?.type == .pirateAttack && enc?.opponent.type == .mantis)
        } else {
            #expect(enc == nil && RS.draws(p0, p.rng) == 3)
        }
    }
}

@Suite("RUL §2 / ENC: opponent generation by ruleset")
struct OpponentGenerationRulesetTests {
    @Test("RUL-075 ENC-063 police tries: psychopath-first (Modern, Windows) vs villain-first (Palm)")
    func policeTries() {
        func tries(_ r: RulesetID, _ rec: Int, wild: Bool = false) -> Int {
            let s = RS.state(r) { s in
                s.commander.policeRecordScore = rec
                if wild { boardWild(&s) }
            }
            return s.policeBaseTries()
        }
        for r in [RulesetID.windows201, .modern] {
            #expect(tries(r, 0) == 1 && tries(r, -31) == 1 && tries(r, -71) == 3 && tries(r, -101) == 5 && tries(r, 0, wild: true) == 5)
        }
        #expect(tries(.palm122, 0) == 1 && tries(.palm122, -31) == 3 && tries(.palm122, -71) == 3)
        #expect(tries(.palm122, -101) == 3) // a psychopath without Wild gets 3 in Palm
        #expect(tries(.palm122, -101, wild: true) == 5 && tries(.palm122, 0, wild: true) == 5)
    }

    @Test("RUL-076 RUL-120 ENC-066 ENC-067 ship roll: Windows never a Wasp; Modern and Palm can; Palm redraws disallowed types")
    func shipRoll() {
        var seen: [RulesetID: Set<ShipType>] = [:]
        for r in [RulesetID.windows201, .modern, .palm122] {
            for seed in 0..<300 {
                var s = RS.state(r, .impossible, seed: UInt64(seed)) { s in
                    s.galaxy.systems[s.warpSystem].politics = .anarchy
                    s.commander.cash = 5_000_000
                }
                let gov = s.ruleset.tables.politics(.anarchy)
                let opp = s.generateOpponentShip(.pirate)
                seen[r, default: []].insert(opp.type)
                if r == .palm122, opp.type != .gnat { #expect(s.shipTypeLikely(opp.type, .pirate, government: gov)) }
            }
        }
        #expect(seen[.windows201]?.contains(.wasp) == false)
        #expect(seen[.modern]?.contains(.wasp) == true)
        #expect(seen[.palm122]?.contains(.wasp) == true)
        // Palm's Mantis runs 1 + D unfiltered tries before being overwritten (C#: no type draws at all).
        var w = RS.state(.windows201, .hard)
        let w0 = w.rng
        #expect(w.generateOpponentShip(.mantis).type == .mantis && RS.draws(w0, w.rng) == 0)
        var p = RS.state(.palm122, .hard)
        let p0 = p.rng
        #expect(p.generateOpponentShip(.mantis).type == .mantis && RS.draws(p0, p.rng) == 4)
    }

    @Test("RUL-077 RUL-078 ENC-084 equipment roll: Palm's backwards walk gives only the first or last type; weapons and shields repeat")
    func equipmentRoll() {
        var palmWeapons: Set<WeaponType> = [], palmGadgets: Set<GadgetType> = [], winWeapons: Set<WeaponType> = []
        var palmRepeat = false
        for seed in 0..<200 {
            for r in [RulesetID.windows201, .palm122] {
                var s = RS.state(r, .impossible, seed: UInt64(seed))
                var ship = Ship(type: .wasp, spec: s.ruleset.tables.ship(.wasp))
                s.addOpponentGadgets(&ship, tries: 3)
                s.addOpponentWeapons(&ship, tries: 3)
                s.addOpponentShields(&ship, tries: 3)
                if r == .palm122 {
                    palmWeapons.formUnion(ship.weapons)
                    palmGadgets.formUnion(ship.gadgets)
                    let w = ship.weapons.filter { $0 != .pulseLaser }
                    let sh = ship.shields.map(\.type).filter { $0 != .energy }
                    if Set(w).count < w.count || Set(sh).count < sh.count { palmRepeat = true }
                } else {
                    winWeapons.formUnion(ship.weapons)
                    // C# skips fitted types except the index-0 fallback.
                    let w = ship.weapons.filter { $0 != .pulseLaser }
                    #expect(Set(w).count == w.count)
                    let sh = ship.shields.map(\.type).filter { $0 != .energy }
                    #expect(Set(sh).count == sh.count)
                }
            }
        }
        #expect(palmWeapons.isSubset(of: [.pulseLaser, .militaryLaser]) && palmWeapons.count == 2)
        #expect(palmGadgets.isSubset(of: [.extraCargoBays, .cloakingDevice]))
        #expect(winWeapons.contains(.beamLaser))
        #expect(palmRepeat)
    }

    @Test("RUL-079 extra opponent weapon: Palm adds the difficulty ≥ Hard test (one more rand(2) draw on Hard with few tries)")
    func weaponCount() {
        for seed in 0..<40 {
            for r in [RulesetID.windows201, .palm122] {
                var s = RS.state(r, .hard, seed: UInt64(seed))
                var ship = Ship(type: .wasp, spec: s.ruleset.tables.ship(.wasp)) // 3 weapon slots
                let count = 1 + RS.peek(s, [3])[0]
                let s0 = s.rng
                s.addOpponentWeapons(&ship, tries: 1)
                let n = RS.draws(s0, s.rng) ?? -1
                if r == .windows201 {
                    #expect(ship.weapons.count == count && n == 1 + count)
                } else {
                    let extra = count < 3 ? 1 : 0
                    #expect(n == 1 + extra + ship.weapons.count)
                    #expect(ship.weapons.count >= count && ship.weapons.count <= count + extra)
                }
            }
        }
    }

    @Test("RUL-080 RUL-081 cargo: bays > 0 (Windows) vs bays > 5 and at least one unit, police included (Palm)")
    func cargo() {
        for seed in 0..<30 {
            var w = RS.state(.windows201, seed: UInt64(seed)) { $0.galaxy.systems[$0.warpSystem].politics = .capitalist }
            #expect(w.generateOpponent(.police).cargo.reduce(0, +) == 0)
            var p = RS.state(.palm122, seed: UInt64(seed)) { $0.galaxy.systems[$0.warpSystem].politics = .capitalist }
            let police = p.generateOpponent(.police)
            #expect(police.cargoBays(p.ruleset) <= 5 || police.cargo.reduce(0, +) == 1)
        }
        // A ship with exactly 5 bays: cargo in Windows, none in Palm.
        var spec = Ruleset.windows201.tables.ship(.gnat)
        spec.cargoBays = 5
        for r in [RulesetID.windows201, .palm122] {
            var s = RS.state(r, .easy)
            var ship = Ship(type: .custom, spec: spec)
            ship.customSpec = spec
            s.addOpponentCargo(&ship, opp: .trader)
            #expect((ship.cargo.reduce(0, +) > 0) == (r == .windows201))
        }
    }

    @Test("RUL-082 ENC-081 famous captains: Wasp, 3 military lasers, targeting + navigating; 2 reflective (Windows) or 3 (Palm); no draws")
    func famousCaptain() {
        for (r, shields) in [(RulesetID.windows201, 2), (.modern, 2), (.palm122, 3)] {
            var s = RS.state(r)
            let s0 = s.rng
            let opp = s.generateOpponent(.famousCaptain)
            #expect(opp.type == .wasp && opp.weapons == [.militaryLaser, .militaryLaser, .militaryLaser])
            #expect(opp.shields.count == shields && opp.shields.allSatisfy { $0.type == .reflective && $0.charge == 200 })
            #expect(Set(opp.gadgets) == [.targetingSystem, .navigatingSystem] && opp.hull == opp.hullStrength(s.ruleset))
            #expect(s.rng == s0)
        }
    }

    @Test("RUL-083 hull: best of 5 unless shielded and rand(5) ≠ 0 (Windows) vs full if shielded and rand(10) ≤ 7 (Palm); Palm Mantis full")
    func hullRoll() {
        for seed in 0..<30 {
            for r in [RulesetID.windows201, .palm122] {
                var s = RS.state(r, seed: UInt64(seed))
                var ship = Ship(type: .hornet, spec: s.ruleset.tables.ship(.hornet))
                ship.shields = [ShieldInstance(type: .energy, charge: 10)]
                let first = RS.peek(s, [r == .palm122 ? 10 : 5])[0]
                let full = r == .palm122 ? first <= 7 : first != 0
                let s0 = s.rng
                s.setOpponentHull(&ship)
                #expect(RS.draws(s0, s.rng) == (full ? 1 : 6))
                if full { #expect(ship.hull == ship.hullStrength(s.ruleset)) }
            }
            var m = RS.state(.palm122, seed: UInt64(seed))
            let mantis = m.generateOpponent(.mantis)
            #expect(mantis.hull == mantis.hullStrength(m.ruleset))
        }
    }

    @Test("RUL-084 ENC-084 generation order: Windows type/crew/gadgets/shields/weapons/hull/cargo; Palm type/gadgets/cargo/weapons/shields/hull/crew")
    func generationOrder() {
        for seed in 0..<15 {
            for r in [RulesetID.windows201, .palm122] {
                let base = RS.state(r, seed: UInt64(seed)) { $0.galaxy.systems[$0.warpSystem].politics = .anarchy }
                var a = base
                let real = a.generateOpponent(.pirate)
                var b = base
                var ship = b.generateOpponentShip(.pirate)
                let tries = max(1, b.worth / 150_000 + b.difficulty.rawValue - 2)
                if r == .windows201 {
                    b.generateOpponentCrew(&ship)
                    b.addOpponentGadgets(&ship, tries: tries)
                    b.addOpponentShields(&ship, tries: tries)
                    b.addOpponentWeapons(&ship, tries: tries)
                    b.setOpponentHull(&ship)
                    b.addOpponentCargo(&ship, opp: .pirate)
                } else {
                    b.addOpponentGadgets(&ship, tries: tries)
                    b.addOpponentCargo(&ship, opp: .pirate)
                    b.addOpponentWeapons(&ship, tries: tries)
                    b.addOpponentShields(&ship, tries: tries)
                    b.setOpponentHull(&ship)
                    b.generateOpponentCrew(&ship)
                }
                #expect(ship == real && a.rng == b.rng)
                #expect(a.mercenaries[CrewID.opponent].skills == b.mercenaries[CrewID.opponent].skills)
            }
        }
    }

    @Test("RUL-085 RUL-109 ENC-071 ENC-073 crew: Kravat engineer boost checks the player (Modern, Palm) or the opponent (Windows); Palm extra crew any slot")
    func crew() {
        func setup(_ r: RulesetID, _ seed: UInt64) -> GameState {
            RS.state(r, .impossible, seed: seed) { s in
                s.warpSystem = SystemID.kravat
                boardWild(&s)
            }
        }
        for seed in UInt64(0)..<30 {
            var w = setup(.windows201, seed)
            var ship = Ship(type: .wasp, spec: w.ruleset.tables.ship(.wasp))
            let wv = RS.peek(w, [10, 10, 10, 10])
            w.generateOpponentCrew(&ship)
            #expect(w.mercenaries[CrewID.opponent].skills[3] == 1 + wv[3]) // Wild is never aboard the opponent
            #expect(ship.crew.dropFirst().compactMap { $0 }.allSatisfy { !OpponentSpecModel.special.contains($0) })
            var m = setup(.modern, seed)
            let mv = RS.peek(m, [10, 10, 10, 10, 10])
            var mship = Ship(type: .wasp, spec: m.ruleset.tables.ship(.wasp))
            m.generateOpponentCrew(&mship)
            #expect(m.mercenaries[CrewID.opponent].skills[3] == (mv[3] < 5 ? 10 : 1 + mv[4]))
            var p = setup(.palm122, seed)
            let pv = RS.peek(p, [10, 10, 10, 10, 10])
            var pship = Ship(type: .wasp, spec: p.ruleset.tables.ship(.wasp))
            p.generateOpponentCrew(&pship)
            #expect(p.mercenaries[CrewID.opponent].skills[3] == (pv[4] < 5 ? 10 : 1 + pv[3]))
            #expect(pship.crew.dropFirst().compactMap { $0 }.allSatisfy { $0 < 31 })
        }
    }
}

@Suite("RUL §2 / ENC: reactions by ruleset")
struct EncounterReactionRulesetTests {
    @Test("RUL-086 RUL-087 ENC-106 police: surrender demand only in Windows/Modern; Palm attacks, even unarmed")
    func policeAttack() {
        for r in [RulesetID.windows201, .modern, .palm122] {
            var s = RS.state(r) { $0.commander.policeRecordScore = -10 }
            let armed = RS.gnatOpponent(&s)
            #expect(s.policeReaction(armed) == (r == .palm122 ? .policeAttack : .policeSurrender))
            let unarmed = RS.gnatOpponent(&s, weapons: [])
            #expect(s.policeReaction(unarmed) == (r == .palm122 ? .policeAttack : .policeFlee))
            s.commander.policeRecordScore = -31
            #expect(s.policeReaction(armed) == .policeAttack)
        }
    }

    @Test("RUL-088 ENC-106 lawful inspection rand(40) == 0 (Windows) vs == 1 (Palm); Palm draws even when already inspected")
    func lawfulInspection() {
        for k in 0..<120 {
            for r in [RulesetID.windows201, .palm122] {
                var s = RS.advanced(RS.state(r) { $0.commander.policeRecordScore = 10 }, k)
                let roll = RS.peek(s, [40])[0]
                let opp = RS.gnatOpponent(&s)
                let t = s.policeReaction(opp)
                #expect((t == .policeInspect) == (roll == (r == .palm122 ? 1 : 0)))
            }
        }
        for r in [RulesetID.windows201, .palm122] {
            var s = RS.state(r) { s in
                s.commander.policeRecordScore = 2
                s.inspected = true
            }
            let opp = RS.gnatOpponent(&s)
            let s0 = s.rng
            #expect(s.policeReaction(opp) == .policeIgnore)
            #expect(RS.draws(s0, s.rng) == (r == .palm122 ? 1 : 0))
        }
    }

    @Test("ENC-106 an outclassing police ship: attack before the cloak test (Windows) vs cloaked → ignore, else flee → attack (Palm)")
    func policeOutclassed() {
        for r in [RulesetID.windows201, .palm122] {
            var s = RS.state(r) { s in
                s.commander.ship = CombatKit.playerShip(s, .flea, weapons: [.pulseLaser])
                s.commander.policeRecordScore = -40
                s.commander.reputationScore = 100_000 // the rand(1500) attack draw always fails
            }
            var opp = RS.gnatOpponent(&s, .wasp, skills: [5, 5, 5, 10])
            #expect(s.policeReaction(opp) == .policeAttack)
            opp.gadgets = [.cloakingDevice]
            s.mercenaries[CrewID.commander].skills[3] = 1
            #expect(s.opponentCloaked(opp))
            #expect(s.policeReaction(opp) == (r == .palm122 ? .policeIgnore : .policeAttack))
        }
    }

    @Test("ENC-103 pirates: Windows skips the draw when outclassed; Palm draws unless type ≥ 7, then flee → attack")
    func pirateReaction() {
        for r in [RulesetID.windows201, .palm122] {
            var s = RS.state(r) { s in
                s.commander.ship = CombatKit.playerShip(s, .flea, weapons: [.pulseLaser])
                s.commander.reputationScore = 100_000
            }
            let beetle = RS.gnatOpponent(&s, .beetle)
            let s0 = s.rng
            #expect(s.pirateReaction(beetle) == .pirateAttack)
            #expect(RS.draws(s0, s.rng) == (r == .palm122 ? 1 : 0))
            let hornet = RS.gnatOpponent(&s, .grasshopper)
            let s1 = s.rng
            #expect(s.pirateReaction(hornet) == .pirateAttack && s.rng == s1)
            s.commander.ship = CombatKit.playerShip(s, .wasp, weapons: [.pulseLaser])
            #expect(s.pirateReaction(beetle) == .pirateFlee) // reputation scares a weaker pirate
        }
    }

    @Test("RUL-089 ENC-109 traders may flee from record ≤ −30 (Windows) or ≤ −10 (Palm)")
    func traderFlee() {
        for seed in UInt64(0)..<20 {
            for r in [RulesetID.windows201, .palm122] {
                var s = RS.state(r, seed: seed) { s in
                    s.commander.policeRecordScore = -10
                    s.commander.reputationScore = 100_000
                }
                let enc = s.determineTrader(clicks: 5)
                if r == .palm122 {
                    #expect(enc == nil || enc?.type == .traderFlee)
                } else {
                    #expect(enc?.type != .traderFlee)
                }
            }
        }
    }

    @Test("ENC-133 Palm shows the same action sets; police surrender is unreachable in Palm")
    func palmActions() {
        for t in EncounterType.allCases {
            let e = Pol.engine(t, .palm122)
            if let preview = e.encounterPreview { #expect(preview.actions.map(\.action) == t.actions) }
        }
        for rec in stride(from: -120, through: 10, by: 5) {
            var s = RS.state(.palm122) { $0.commander.policeRecordScore = rec }
            let opp = RS.gnatOpponent(&s)
            #expect(s.policeReaction(opp) != .policeSurrender)
        }
    }

    @Test("ENC-013 Palm meets quest ships fresh: damage does not persist; the monster hull is written back only on escape")
    func specialShips() {
        var p = RS.state(.palm122) { s in
            s.warpSystem = SystemID.acamar
            s.quests.spaceMonster = QuestStatus.SpaceMonster.atAcamar
        }
        let enc = p.determineFixedEncounter(clicks: 1)
        #expect(enc?.type == .spaceMonsterAttack || enc?.type == .spaceMonsterIgnore)
        let d = p.difficulty.rawValue
        #expect(p.skills(of: p.specialShips.spaceMonster) == Skills.shipSkills(p.specialShips.spaceMonster, crew: p.mercenaries,
                                                                                  difficulty: p.difficulty, ruleset: p.ruleset))
        #expect(p.mercenaries[CrewID.spaceMonster].skills == [8 + d, 8 + d, 1, 1 + d])
        #expect(p.mercenaries[CrewID.dragonfly].skills == [4 + d, 6 + d, 1, 6 + d])
        #expect(p.mercenaries[CrewID.scarab].skills == [5 + d, 6 + d, 1, 6 + d])
        // A damaging round leaves the shared Dragonfly untouched in Palm and damaged in Windows.
        for r in [RulesetID.windows201, .palm122] {
            var hitOnce = false
            for k in 0..<40 where !hitOnce {
                var s = RS.advanced(RS.state(r) { s in
                    s.commander.ship = CombatKit.playerShip(s, .wasp, weapons: [.morgansLaser, .morgansLaser, .morgansLaser])
                }, k)
                var e = EncounterState(type: .dragonflyAttack, opponent: s.specialShips.dragonfly)
                let before = s.specialShips.dragonfly
                _ = s.executeRound(&e)
                if e.opponent != before {
                    hitOnce = true
                    #expect((s.specialShips.dragonfly == before) == (r == .palm122))
                }
            }
            #expect(hitOnce)
        }
        // The monster's hull is stored when the player escapes (Beginner flee always escapes).
        var s = RS.state(.palm122, .beginner)
        var e = EncounterState(type: .spaceMonsterAttack, opponent: s.specialShips.spaceMonster)
        e.opponent.hull = 77
        e.cmdrFleeing = true
        _ = s.executeRound(&e)
        #expect(s.specialShips.spaceMonster.hull == 77)
    }

    @Test("RUL-111 Wild requires a real laser in Modern and Palm; Windows also accepts disruptors")
    func wildLaser() {
        for (r, disruptorOK) in [(RulesetID.windows201, true), (.modern, false), (.palm122, false)] {
            var s = RS.state(r) { boardWild(&$0) }
            s.commander.ship.weapons = [.photonDisruptor]
            #expect(s.hasWildQualifyingLaser == disruptorOK && s.wildWillLeave == !disruptorOK)
            for laser in [WeaponType.beamLaser, .militaryLaser, .morgansLaser] {
                s.commander.ship.weapons = [laser]
                #expect(s.hasWildQualifyingLaser && !s.wildWillLeave)
            }
            s.commander.ship.weapons = [.pulseLaser]
            #expect(!s.hasWildQualifyingLaser)
        }
    }
}
