// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecEngine

/// Shared builders for the CMB spec tests.
enum CombatKit {
    static let yes: Set<WarningID> = Set(WarningID.allCases)

    static func state(_ difficulty: Difficulty = .normal, seed: UInt64 = 7, ruleset: RulesetID = .windows201) -> GameState {
        GameState(config: NewGameConfig(commanderName: "Combat", difficulty: difficulty, ruleset: ruleset, seed: seed))
    }

    /// A commander ship with the given equipment; the commander is the only crew member.
    static func playerShip(_ s: GameState, _ type: ShipType, weapons: [WeaponType] = [], shields: [ShieldInstance] = [],
                           gadgets: [GadgetType] = []) -> Ship {
        var ship = Ship(type: type, spec: s.ruleset.tables.ship(type))
        ship.crew[0] = CrewID.commander
        ship.weapons = weapons
        ship.shields = shields
        ship.gadgets = gadgets
        return ship
    }

    /// An opponent ship crewed by the shared "Opponent" crew member (id 31) whose skills are set to `skills`.
    static func opponent(_ s: inout GameState, _ type: ShipType, weapons: [WeaponType] = [], shields: [ShieldInstance] = [],
                         skills: [Int] = [5, 5, 5, 5]) -> Ship {
        var ship = Ship(type: type, spec: s.ruleset.tables.ship(type))
        if !ship.crew.isEmpty { ship.crew[0] = CrewID.opponent }
        ship.weapons = weapons
        ship.shields = shields
        s.mercenaries[CrewID.opponent].skills = skills
        return ship
    }

    /// An engine in the middle of an encounter on a one-click transit, so finishing the encounter docks at arrival.
    static func engine(_ type: EncounterType, difficulty: Difficulty = .normal, seed: UInt64 = 7,
                       setup: (inout GameState) -> Ship) -> GameEngine {
        var s = state(difficulty, seed: seed)
        s.commander.ship = playerShip(s, .hornet, weapons: [.beamLaser, .beamLaser], shields: [ShieldInstance(type: .energy, charge: 100)])
        s.mercenaries[CrewID.commander].skills = [6, 6, 6, 6]
        let opp = setup(&s)
        s.encounterTransit = TransitState(destination: s.warpSystem, clicksRemaining: 1, viaWormhole: false)
        s.phase = .encounter(EncounterState(type: type, opponent: opp, clicks: 1))
        return GameEngine(state: s)
    }

    static func encounter(_ e: GameEngine) -> EncounterState? {
        if case let .encounter(enc) = e.state.phase { enc } else { nil }
    }
}

/// Deterministic configuration chooser (SplitMix64), independent of the game RNG.
struct Mix {
    var x: UInt64
    mutating func next(_ n: Int) -> Int {
        x &+= 0x9E37_79B9_7F4A_7C15
        var z = x
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return n <= 0 ? 0 : Int(z % UInt64(n))
    }
    mutating func flip(_ oneIn: Int = 2) -> Bool { next(oneIn) == 0 }
}

/// Spec model of the Windows 2.01 combat round, written from docs/specs/CMB.md (§2–§9), drawing from the game RNG in
/// the order CMB-094 states. Tests compare it with `GameState.executeRound`.
enum CombatModel {
    /// CMB-017 weapon powers.
    static let power: [WeaponType: Int] = [.pulseLaser: 15, .beamLaser: 25, .militaryLaser: 35, .morgansLaser: 85,
                                           .photonDisruptor: 20, .quantumDisruptor: 60]
    /// CMB-010 (a) and (b).
    static let opponentFires: Set<EncounterType> = [.dragonflyAttack, .famousCaptainAttack, .marieCelestePolice, .pirateAttack,
                                                    .policeAttack, .scarabAttack, .scorpionAttack, .spaceMonsterAttack, .traderAttack]
    static let opponentFleeing: Set<EncounterType> = [.pirateFlee, .pirateSurrender, .policeFlee, .traderFlee, .traderSurrender]

    /// CMB-038.
    static func disableable(_ ship: Ship, isPlayer: Bool) -> Bool {
        !isPlayer && ![.bottle, .mantis, .spaceMonster].contains(ship.type)
    }

    static func sum(_ weapons: [WeaponType], _ range: ClosedRange<Int>) -> Int {
        weapons.filter { range.contains($0.rawValue) }.reduce(0) { $0 + (power[$1] ?? 0) }
    }

    /// One shot (CMB-014, -017, -018, -020…-022, -024, -026, -027, -029, -031, -034, -039). Returns whether it hit.
    static func shot(_ s: inout GameState, _ enc: inout EncounterState, playerFires: Bool, fleeing: Bool) -> Bool {
        let d = s.difficulty.rawValue
        let att = playerFires ? s.commander.ship : enc.opponent
        var def = playerFires ? enc.opponent : s.commander.ship
        let fAtt = (playerFires ? s.shipSkills : s.skills(of: att))[1]
        let defSkills = playerFires ? s.skills(of: def) : s.shipSkills
        defer { if playerFires { enc.opponent = def } else { s.commander.ship = def } }
        if d == 0, !playerFires, fleeing { return false }
        if !(playerFires && enc.opponentDisabled && att.gadgets.contains(.targetingSystem)) {
            let left = s.rng.next(below: fAtt + s.ruleset.tables.ship(def.type).size.rawValue)
            let right = s.rng.next(below: 5 + defSkills[0] / 2)
            if left < (fleeing ? 2 : 1) * right { return false }
        }
        if playerFires, enc.opponentDisabled {
            def.hull = 0
            return false
        }
        var lasers = sum(att.weapons, 0...3)
        var disruptors = sum(att.weapons, 4...5)
        if def.type == .scarab {
            lasers -= sum(att.weapons, 1...2)
            disruptors -= sum(att.weapons, 4...4)
        }
        let weapons = lasers + disruptors
        let canDisable = disableable(def, isPlayer: !playerFires)
        var disrupt = 0
        var hit = false
        if canDisable, def.shieldCharge == 0, !enc.opponentDisabled, s.options.disableOpponents, disruptors > 0 {
            disrupt = s.rng.next(below: disruptors * (100 + 2 * fAtt) / 100)
        } else {
            var damage = weapons == 0 ? 0 : s.rng.next(below: weapons * (100 + 2 * fAtt) / 100)
            if damage > 0 {
                hit = true
                if !playerFires, s.reactorOnBoard { damage *= [1, 1, 1, 2, 2][d] }
                for i in def.shields.indices where damage > 0 {
                    let applied = min(def.shields[i].charge, damage)
                    def.shields[i].charge -= applied
                    damage -= applied
                }
                if damage > 0 {
                    damage = max(1, damage - s.rng.next(below: defSkills[3]))
                    disrupt = damage * disruptors / weapons
                    damage -= disrupt
                    let hullStrength = s.ruleset.tables.ship(def.type).hullStrength + (def.hullUpgraded ? 50 : 0)
                    damage = min(damage, hullStrength / (playerFires ? 2 : [4, 3, 2, 1, 1][d]))
                    if s.quests.scarab == QuestStatus.Scarab.done { damage /= 2 }
                    def.hull = max(0, def.hull - damage)
                }
            }
        }
        if def.hull > 0, canDisable, s.rng.next(below: 100) < disrupt * 3 * 100 / def.hull { enc.opponentDisabled = true }
        return hit
    }

    /// CMB-054…CMB-058.
    static func update(_ s: inout GameState, _ enc: inout EncounterState, prevPlayer: Int, prevOpp: Int) {
        let chance = s.rng.next(below: 100)
        let opp = enc.opponent.hull, me = s.commander.ship.hull, off = enc.opponentDisabled
        guard opp < prevOpp || off else { return }
        switch enc.type {
        case .pirateAttack, .pirateFlee, .pirateSurrender:
            if off {
                enc.type = .pirateDisabled
            } else if opp < prevOpp * 2 / 3 {
                if me < prevPlayer * 2 / 3 {
                    if chance < 60 { enc.type = .pirateFlee }
                } else {
                    enc.type = chance < 10 && enc.opponent.type != .mantis ? .pirateSurrender : .pirateFlee
                }
            }
        case .policeAttack, .policeFlee:
            if off {
                enc.type = .policeDisabled
            } else if opp < prevOpp / 2, me >= prevPlayer / 2 || chance < 40 {
                enc.type = .policeFlee
            }
        case .traderAttack, .traderFlee, .traderSurrender:
            if off {
                enc.type = .traderDisabled
            } else if opp < prevOpp * 2 / 3 {
                enc.type = chance < 60 ? .traderSurrender : .traderFlee
            } else if opp < prevOpp * 9 / 10 {
                let a = me < prevPlayer * 2 / 3 && chance < 20
                let b = me < prevPlayer * 9 / 10 && chance < 60
                if a || b || me >= prevPlayer * 9 / 10 { enc.type = .traderFlee }
            }
        case .famousCaptainAttack:
            if off { enc.type = .famousCaptDisabled }
        default:
            break
        }
    }

    struct Outcome {
        var result: RoundResult
        var events: [GameEvent]
        var state: GameState
        var enc: EncounterState
        /// True when the opponent was destroyed (EncounterWon follows; its effects are not modelled here).
        var won = false
    }

    /// One round (CMB-010, -013, -044, -046, -049, -050, -052, -053, -061, -064, -097). Not for disabled special ships.
    static func round(_ s0: GameState, _ e0: EncounterState) -> Outcome {
        var s = s0, enc = e0
        let prevPlayer = s.commander.ship.hull, prevOpp = enc.opponent.hull, start = enc.type
        enc.cmdrHit = false
        enc.oppHit = false
        enc.oppFleeingPrev = enc.oppFleeing
        enc.oppFleeing = false
        enc.round += 1
        if opponentFires.contains(start) {
            enc.cmdrHit = shot(&s, &enc, playerFires: false, fleeing: enc.cmdrFleeing)
            if !enc.cmdrFleeing { enc.oppHit = shot(&s, &enc, playerFires: true, fleeing: false) }
        } else if opponentFleeing.contains(start) {
            if !enc.cmdrFleeing { enc.oppHit = shot(&s, &enc, playerFires: true, fleeing: true) }
            enc.oppFleeing = true
        } else if !enc.cmdrFleeing {
            enc.oppHit = shot(&s, &enc, playerFires: true, fleeing: false)
        }
        var events: [GameEvent] = [.combatRound(round: enc.round, playerHit: enc.cmdrHit, opponentHit: enc.oppHit,
                                                playerHull: s.commander.ship.hull, opponentHull: enc.opponent.hull)]
        if s.commander.ship.hull <= 0 {
            if s.commander.ship.escapePod { return Outcome(result: .escapePod, events: events, state: s, enc: enc) }
            events.append(enc.opponent.hull <= 0 ? .bothDestroyed : .playerDestroyed)
            return Outcome(result: .killed, events: events, state: s, enc: enc)
        }
        if enc.opponentDisabled {
            update(&s, &enc, prevPlayer: prevPlayer, prevOpp: prevOpp)
            enc.oppFleeing = false
            events.append(.opponentDisabled(enc.opponent.type))
            return Outcome(result: .continue, events: events, state: s, enc: enc)
        }
        if enc.opponent.hull <= 0 { return Outcome(result: .normal, events: events, state: s, enc: enc, won: true) }
        let d = s.difficulty.rawValue
        let pMe = s.shipSkills[0], pOpp = s.skills(of: enc.opponent)[0]
        var escaped = false
        if enc.cmdrFleeing {
            escaped = d == 0 || (s.rng.next(below: 7) + pMe / 3) * 2 >= s.rng.next(below: pOpp) * (2 + d)
            if escaped { events.append(.playerEscaped(wasHit: enc.cmdrHit)) }
        }
        if !escaped, enc.oppFleeing, s.rng.next(below: pMe) * 4 <= s.rng.next(below: 7 + pOpp / 3) * 2 {
            escaped = true
            events.append(.opponentEscaped)
        }
        if escaped { return Outcome(result: .normal, events: events, state: s, enc: enc) }
        update(&s, &enc, prevPlayer: prevPlayer, prevOpp: prevOpp)
        enc.oppFleeing = opponentFleeing.contains(enc.type)
        let cont = s.options.continuousAttack || enc.forceContinuous
        let contFleeing = s.options.continuousAttackFleeing || enc.forceContinuous
        let surrendering = enc.type == .pirateSurrender || enc.type == .traderSurrender
        if cont, enc.cmdrFleeing || !enc.oppFleeing || (contFleeing && (enc.type == start || !surrendering)) {
            if enc.cmdrFleeing { enc.continueFleeing = true } else { enc.continueAttacking = true }
        }
        if enc.type != start { events.append(.encounterChanged(enc.type)) }
        return Outcome(result: .continue, events: events, state: s, enc: enc)
    }

    /// One fresh Windows 2.01 game per difficulty (galaxy generation is the expensive part of a new state).
    static let bases: [GameState] = Difficulty.allCases.map { CombatKit.state($0) }

    /// A random Windows 2.01 combat situation (pirates, police, traders, the Mantis or a famous captain).
    static func randomSituation(_ seed: UInt64) -> (GameState, EncounterState) {
        var m = Mix(x: seed)
        var s = bases[m.next(bases.count)]
        s.rng = RNGState(kind: s.ruleset.rngKind, seed: seed)
        let types: [ShipType] = [.gnat, .firefly, .mosquito, .bumblebee, .hornet, .grasshopper, .termite, .wasp]
        let type = types[m.next(types.count)]
        let spec = s.ruleset.tables.ship(type)
        var ship = CombatKit.playerShip(s, type)
        ship.weapons = (0..<m.next(spec.weaponSlots + 1)).map { _ in WeaponType.allCases[m.next(6)] }
        ship.shields = (0..<m.next(spec.shieldSlots + 1)).map { _ in
            let t: ShieldType = m.flip() ? .energy : .reflective
            return ShieldInstance(type: t, charge: m.next(s.ruleset.tables.shield(t).power + 1))
        }
        if spec.gadgetSlots > 0, m.flip(3) { ship.gadgets = [.targetingSystem] }
        ship.hullUpgraded = m.flip(5)
        ship.hull = 1 + m.next(ship.hullStrength(s.ruleset))
        ship.escapePod = m.flip()
        s.commander.ship = ship
        s.mercenaries[CrewID.commander].skills = (0..<4).map { _ in 1 + m.next(10) }
        if m.flip(3) { s.quests.reactor = 5 }
        if m.flip(4) { s.quests.scarab = QuestStatus.Scarab.done }
        s.options.disableOpponents = m.flip()
        s.options.continuousAttack = m.flip()
        s.options.continuousAttackFleeing = m.flip()
        let kinds: [OpponentType] = [.pirate, .police, .trader, .pirate, .police, .trader, .mantis, .famousCaptain]
        let kind = kinds[m.next(kinds.count)]
        var opp = s.generateOpponent(kind)
        opp.hull = 1 + m.next(opp.hullStrength(s.ruleset))
        if m.flip() { for i in opp.shields.indices { opp.shields[i].charge = 0 } }
        let encTypes: [EncounterType] = switch kind {
        case .pirate: [.pirateAttack, .pirateFlee, .pirateSurrender, .pirateDisabled, .pirateIgnore]
        case .police: [.policeAttack, .policeFlee, .policeSurrender, .policeDisabled, .policeInspect, .marieCelestePolice]
        case .trader: [.traderAttack, .traderFlee, .traderSurrender, .traderDisabled, .traderBuy, .traderIgnore]
        case .mantis: [.pirateAttack, .pirateFlee]
        default: [.famousCaptainAttack, .famousCaptDisabled, .captainAhab]
        }
        var enc = EncounterState(type: encTypes[m.next(encTypes.count)], opponent: opp)
        let disabledTypes: [EncounterType] = [.pirateDisabled, .policeDisabled, .traderDisabled, .famousCaptDisabled]
        enc.opponentDisabled = disabledTypes.contains(enc.type) || (disableable(opp, isPlayer: false) && m.flip(6))
        enc.cmdrFleeing = m.flip()
        enc.oppFleeing = m.flip()
        enc.forceContinuous = m.flip(8)
        return (s, enc)
    }
}
