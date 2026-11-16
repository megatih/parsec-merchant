// SPDX-License-Identifier: GPL-2.0-or-later
// Combat rounds: C# EncounterExecuteAction / EncounterExecuteAttack / EncounterUpdateEncounterType / EncounterWon.
// docs/specs/CMB.md. RNG call order preserved.

/// Outcome of a combat round (C# `EncounterResult`).
public enum RoundResult: String, Codable, Sendable {
    case `continue`, normal, killed, escapePod, arrested
}

public extension GameState {
    /// Effective skills of any ship (opponents use the same function and the game difficulty: CRW-019).
    func skills(of ship: Ship) -> [Int] {
        Skills.shipSkills(ship, crew: mercenaries, difficulty: difficulty, ruleset: ruleset)
    }

    /// C# `Ship.Bounty()`: (list price + weapon & shield prices at the commander's discounted local price) scaled by
    /// opponent skills (2P + E + 3F)/60, /200, rounded down to 25, clamped 25…2500.
    func bounty(of ship: Ship) -> Int {
        let t = ruleset.tables
        var price = ship.spec(ruleset).price
        // RUL-094: Palm sums base equipment prices (C# uses the commander's discounted local price, 0 above the tech level).
        let base = ruleset.flags.encounter.bountyEquipmentBasePrice
        for w in ship.weapons { price += base ? t.weapon(w).price : buyPrice(basePrice: t.weapon(w).price, minTech: t.weapon(w).minTechLevel) }
        for s in ship.shields {
            price += base ? t.shield(s.type).price : buyPrice(basePrice: t.shield(s.type).price, minTech: t.shield(s.type).minTechLevel)
        }
        let sk = skills(of: ship)
        price = price * (2 * sk[0] + sk[3] + 3 * sk[1]) / 60
        return max(25, min(2_500, price / 200 / 25 * 25))
    }

    /// C# `Ship.Disableable` for the opponent.
    func disableable(_ ship: Ship) -> Bool {
        ship.type != .bottle && ship.type != .mantis && ship.type != .spaceMonster
    }

    /// C# `EncounterExecuteAttack`. Returns whether damage was dealt.
    mutating func executeAttack(commanderAttacks: Bool, fleeing: Bool, encounter enc: inout EncounterState) -> Bool {
        let r = ruleset
        let rules = r.flags.encounter
        let attacker = commanderAttacks ? commander.ship : enc.opponent
        var defender = commanderAttacks ? enc.opponent : commander.ship
        let aSkills = commanderAttacks ? shipSkills : skills(of: attacker)
        let dSkills = commanderAttacks ? skills(of: defender) : shipSkills
        var hit = false
        let defenderIsCommander = !commanderAttacks
        let beginnerFlee = difficulty == .beginner && defenderIsCommander && fleeing
        var hits = false
        if !beginnerFlee {
            if commanderAttacks, enc.opponentDisabled, attacker.has(.targetingSystem) {
                hits = true
            } else {
                hits = rng.next(below: aSkills[1] + defender.spec(r).size.rawValue)
                    >= (fleeing ? 2 : 1) * rng.next(below: 5 + dSkills[0] / 2)
            }
        }
        if hits {
            if commanderAttacks, enc.opponentDisabled {
                defender.hull = 0
            } else {
                var lasers = attacker.weaponStrength(r, from: .pulseLaser, to: .morgansLaser)
                var disruptors = attacker.weaponStrength(r, from: .photonDisruptor, to: .quantumDisruptor)
                if defender.type == .scarab {
                    // RUL-091: only the ruleset's Scarab-vulnerable weapons count.
                    let hurts = attacker.weapons.filter { rules.scarabVulnerableWeapons.contains($0) }
                    lasers = hurts.filter(\.isLaser).reduce(0) { $0 + r.tables.weapon($1).power }
                    disruptors = hurts.filter { !$0.isLaser }.reduce(0) { $0 + r.tables.weapon($1).power }
                }
                let weapons = lasers + disruptors
                let skill = aSkills[rules.damageSkill.rawValue] // RUL-090: Fighter (C#) or Engineer (Palm)
                var disrupt = 0
                let canDisable = !defenderIsCommander && disableable(defender)
                if canDisable, defender.shieldCharge == 0, !enc.opponentDisabled, options.disableOpponents, disruptors > 0 {
                    disrupt = rng.next(below: disruptors * (100 + 2 * skill) / 100)
                } else {
                    var damage = weapons == 0 ? 0 : rng.next(below: weapons * (100 + 2 * skill) / 100)
                    if damage > 0 {
                        hit = true
                        if defenderIsCommander, reactorOnBoard {
                            if r.flags.reactorDamageRealFactor {
                                let f = 1 + Double(difficulty.rawValue + 1) * (difficulty < .normal ? 0.25 : 0.33)
                                damage = Int(Double(damage) * f)
                            } else {
                                damage *= Int(1 + Double(difficulty.rawValue + 1) * (difficulty < .normal ? 0.25 : 0.33))
                            }
                        }
                        var i = 0
                        while i < defender.shields.count, damage > 0 {
                            let applied = min(defender.shields[i].charge, damage)
                            defender.shields[i].charge -= applied
                            damage -= applied
                            i += 1
                        }
                        if damage > 0 {
                            damage = max(1, damage - rng.next(below: dSkills[3]))
                            disrupt = damage * disruptors / weapons
                            damage -= disrupt
                            let divisor = defenderIsCommander ? max(1, Difficulty.impossible.rawValue - difficulty.rawValue) : 2
                            let hardened = quests.scarab == QuestStatus.Scarab.done
                            // CMB-030: Palm caps with the base hull, except the upgraded hull of a hardened player ship.
                            let capHull = rules.hullDamageCapUsesBaseHull && !(defenderIsCommander && hardened)
                                ? defender.spec(r).hullStrength : defender.hullStrength(r)
                            damage = min(damage, capHull / divisor)
                            // RUL-104: Palm never halves; Modern halves for the player only; Windows for every defender.
                            if hardened, rules.hardenedHullHalvesDamage, defenderIsCommander || !r.flags.hardenedHullProtectsPlayerOnly {
                                damage /= 2
                            }
                            defender.hull = max(0, defender.hull - damage)
                        }
                    }
                }
                if defender.hull > 0, canDisable, rng.next(below: 100) < disrupt * 3 * 100 / defender.hull {
                    enc.opponentDisabled = true
                }
                if defender.type == .scorpion, defender.hull == 0 {
                    defender.hull = 1
                    enc.opponentDisabled = true
                }
            }
        }
        if commanderAttacks {
            enc.opponent = defender
            commander.ship = attacker
        } else {
            commander.ship = defender
            enc.opponent = attacker
        }
        return hit
    }

    /// CMB-059: Palm's stance update; draws `rand(10)` only where a branch needs it and only after hull damage.
    mutating func updateEncounterTypeOnDemand(prevCmdrHull: Int, prevOppHull: Int, encounter enc: inout EncounterState) {
        let oppHull = enc.opponent.hull
        let cmdrHull = commander.ship.hull
        guard oppHull < prevOppHull else { return }
        switch enc.type {
        case .policeAttack, .policeFlee, .policeIgnore, .policeInspect:
            if oppHull < prevOppHull >> 1 {
                if cmdrHull < prevCmdrHull >> 1 {
                    if rng.next(below: 10) > 5 { enc.type = .policeFlee }
                } else {
                    enc.type = .policeFlee
                }
            }
        case .marieCelestePolice:
            enc.type = .policeAttack
        case .pirateAttack, .pirateFlee, .pirateSurrender, .pirateIgnore:
            if oppHull < (prevOppHull * 2) / 3 {
                if cmdrHull < (prevCmdrHull * 2) / 3 {
                    if rng.next(below: 10) > 3 { enc.type = .pirateFlee }
                } else {
                    enc.type = .pirateFlee
                    if rng.next(below: 10) > 8, enc.opponent.type != .mantis { enc.type = .pirateSurrender }
                }
            }
        case .traderAttack, .traderFlee, .traderSurrender, .traderIgnore:
            if oppHull < (prevOppHull * 2) / 3 {
                enc.type = rng.next(below: 10) > 3 ? .traderSurrender : .traderFlee
            } else if oppHull < (prevOppHull * 9) / 10 {
                if cmdrHull < (prevCmdrHull * 2) / 3 {
                    if rng.next(below: 10) > 7 { enc.type = .traderFlee }
                } else if cmdrHull < (prevCmdrHull * 9) / 10 {
                    if rng.next(below: 10) > 3 { enc.type = .traderFlee }
                } else {
                    enc.type = .traderFlee
                }
            }
        default:
            break // CMB-060: famous captains and quest ships never change stance
        }
    }

    /// C# `EncounterUpdateEncounterType`.
    mutating func updateEncounterType(prevCmdrHull: Int, prevOppHull: Int, encounter enc: inout EncounterState) {
        if ruleset.flags.encounter.stanceUpdateDrawsOnDemand {
            updateEncounterTypeOnDemand(prevCmdrHull: prevCmdrHull, prevOppHull: prevOppHull, encounter: &enc)
            return
        }
        let chance = rng.next(below: 100)
        let oppHull = enc.opponent.hull
        let cmdrHull = commander.ship.hull
        guard oppHull < prevOppHull || enc.opponentDisabled else { return }
        switch enc.type {
        case .famousCaptainAttack:
            if enc.opponentDisabled { enc.type = .famousCaptDisabled }
        case .pirateAttack, .pirateFlee, .pirateSurrender:
            if enc.opponentDisabled {
                enc.type = .pirateDisabled
            } else if oppHull < (prevOppHull * 2) / 3 {
                if cmdrHull < (prevCmdrHull * 2) / 3 {
                    if chance < 60 { enc.type = .pirateFlee }
                } else {
                    enc.type = chance < 10 && enc.opponent.type != .mantis ? .pirateSurrender : .pirateFlee
                }
            }
        case .policeAttack, .policeFlee:
            if enc.opponentDisabled {
                enc.type = .policeDisabled
            } else if oppHull < prevOppHull / 2, cmdrHull >= prevCmdrHull / 2 || chance < 40 {
                enc.type = .policeFlee
            }
        case .traderAttack, .traderFlee, .traderSurrender:
            if enc.opponentDisabled {
                enc.type = .traderDisabled
            } else if oppHull < (prevOppHull * 2) / 3 {
                enc.type = chance < 60 ? .traderSurrender : .traderFlee
            } else if oppHull < (prevOppHull * 9) / 10,
                      (cmdrHull < (prevCmdrHull * 2) / 3 && chance < 20) || (cmdrHull < (prevCmdrHull * 9) / 10 && chance < 60)
                        || cmdrHull >= (prevCmdrHull * 9) / 10 {
                enc.type = .traderFlee
            }
        default:
            break
        }
    }

    static func isSurrender(_ t: EncounterType) -> Bool { t == .pirateSurrender || t == .traderSurrender }

    static func isFleeOrSurrender(_ t: EncounterType) -> Bool {
        [.pirateFlee, .pirateSurrender, .policeFlee, .traderFlee, .traderSurrender].contains(t)
    }

    /// C# `EncounterExecuteAction`: one round after the player chose Attack (or Flee: `enc.cmdrFleeing == true`).
    mutating func executeRound(_ enc: inout EncounterState) -> (RoundResult, [GameEvent]) {
        // CMB-052: C# fights the shared Space Monster / Scarab / Dragonfly / Scorpion object, so damage persists.
        var playerEscaped = false
        defer { persistSpecialShip(enc.opponent, playerEscaped: playerEscaped) }
        var events: [GameEvent] = []
        let prevCmdrHull = commander.ship.hull
        let prevOppHull = enc.opponent.hull
        enc.cmdrHit = false
        enc.oppHit = false
        enc.oppFleeingPrev = enc.oppFleeing
        enc.oppFleeing = false
        enc.round += 1
        switch enc.type {
        case .dragonflyAttack, .famousCaptainAttack, .marieCelestePolice, .pirateAttack, .policeAttack, .scarabAttack,
             .scorpionAttack, .spaceMonsterAttack, .traderAttack:
            enc.cmdrHit = executeAttack(commanderAttacks: false, fleeing: enc.cmdrFleeing, encounter: &enc)
            enc.oppHit = !enc.cmdrFleeing && executeAttack(commanderAttacks: true, fleeing: false, encounter: &enc)
        case .pirateFlee, .pirateSurrender, .policeFlee, .traderFlee, .traderSurrender:
            // RUL-092: Palm shoots a surrendering ship with the normal to-hit modifier.
            let asFleeing = ruleset.flags.encounter.surrenderingTargetShotAsFleeing || !Self.isSurrender(enc.type)
            enc.oppHit = !enc.cmdrFleeing && executeAttack(commanderAttacks: true, fleeing: asFleeing, encounter: &enc)
            enc.oppFleeing = true
        default:
            enc.oppHit = !enc.cmdrFleeing && executeAttack(commanderAttacks: true, fleeing: false, encounter: &enc)
        }
        events.append(.combatRound(round: enc.round, playerHit: enc.cmdrHit, opponentHit: enc.oppHit,
                                   playerHull: commander.ship.hull, opponentHull: enc.opponent.hull))
        if commander.ship.hull <= 0 {
            if commander.ship.escapePod { return (.escapePod, events) }
            events.append(enc.opponent.hull <= 0 ? .bothDestroyed : .playerDestroyed)
            return (.killed, events)
        }
        if enc.opponentDisabled {
            if [.dragonfly, .scarab, .scorpion].contains(enc.opponent.type) {
                defeatSpecialShip(enc.opponent.type)
                commander.reputationScore += enc.opponent.type.rawValue / 2 + 1
                events.append(.opponentDisabled(enc.opponent.type))
                return (.normal, events)
            }
            updateEncounterType(prevCmdrHull: prevCmdrHull, prevOppHull: prevOppHull, encounter: &enc)
            enc.oppFleeing = false
            events.append(.opponentDisabled(enc.opponent.type))
            return (.continue, events)
        }
        if enc.opponent.hull <= 0 {
            events += encounterWon(&enc)
            return (.normal, events)
        }
        var escaped = false
        if enc.cmdrFleeing {
            if difficulty == .beginner {
                escaped = true
            } else {
                let lhs = (rng.next(below: 7) + shipSkills[0] / 3) * 2
                escaped = lhs >= rng.next(below: skills(of: enc.opponent)[0]) * (2 + difficulty.rawValue)
            }
            playerEscaped = escaped
            if escaped { events.append(.playerEscaped(wasHit: enc.cmdrHit)) }
        }
        // CMB-051: Palm checks the opponent's escape only when the player is not fleeing.
        if !escaped, enc.oppFleeing, !(ruleset.flags.encounter.opponentEscapeOnlyWhenPlayerStays && enc.cmdrFleeing) {
            if rng.next(below: shipSkills[0]) * 4 <= rng.next(below: 7 + skills(of: enc.opponent)[0] / 3) * 2 {
                escaped = true
                events.append(.opponentEscaped)
            }
        }
        if escaped { return (.normal, events) }
        let prev = enc.type
        updateEncounterType(prevCmdrHull: prevCmdrHull, prevOppHull: prevOppHull, encounter: &enc)
        enc.oppFleeing = Self.isFleeOrSurrender(enc.type)
        if ruleset.flags.encounter.continuousAttackRule == .palm {
            // CMB-069 / ENC-189: Attack sets AutoAttack, Flee sets AutoFlee; a type change keeps AutoAttack only for a
            // flee type and always clears AutoFlee.
            if options.continuousAttack || enc.forceContinuous {
                if enc.cmdrFleeing { enc.continueFleeing = true } else { enc.continueAttacking = true }
            }
            if enc.type != prev {
                if ![.traderFlee, .pirateFlee, .policeFlee].contains(enc.type) { enc.continueAttacking = false }
                enc.continueFleeing = false
                events.append(.encounterChanged(enc.type))
            }
            return (.continue, events)
        }
        let continuous = options.continuousAttack || enc.forceContinuous
        let continuousFleeing = options.continuousAttackFleeing || enc.forceContinuous
        if continuous, enc.cmdrFleeing || !enc.oppFleeing
            || (continuousFleeing && (enc.type == prev || (enc.type != .pirateSurrender && enc.type != .traderSurrender))) {
            if enc.cmdrFleeing { enc.continueFleeing = true } else { enc.continueAttacking = true }
        }
        if enc.type != prev { events.append(.encounterChanged(enc.type)) }
        return (.continue, events)
    }

    /// ENC-012 / CMB-052: writes a quest opponent back to `specialShips` (C# `Opponent` references the shared ship).
    /// RUL-173 (Palm, ENC-013): a copy is fought; only the monster's hull is written back, when the player escapes.
    mutating func persistSpecialShip(_ ship: Ship, playerEscaped: Bool = false) {
        if ruleset.flags.quest.specialShipDamagePersists == .monsterHullOnEscape {
            if ship.type == .spaceMonster, playerEscaped { specialShips.spaceMonster.hull = ship.hull }
            return
        }
        switch ship.type {
        case .spaceMonster: specialShips.spaceMonster = ship
        case .scarab: specialShips.scarab = ship
        case .dragonfly: specialShips.dragonfly = ship
        case .scorpion: specialShips.scorpion = ship
        default: break
        }
    }

    /// C# EncounterDefeatDragonfly / Scarab / Scorpion.
    mutating func defeatSpecialShip(_ type: ShipType) {
        commander.kills.pirates += 1
        commander.policeRecordScore += 1
        switch type {
        case .dragonfly: quests.dragonfly = QuestStatus.Dragonfly.destroyed
        case .scarab: quests.scarab = QuestStatus.Scarab.destroyed
        case .scorpion: quests.princess = QuestStatus.Princess.rescued
        default: break
        }
    }

    /// C# `EncounterWon`.
    mutating func encounterWon(_ enc: inout EncounterState) -> [GameEvent] {
        var events: [GameEvent] = []
        switch enc.type {
        case .famousCaptainAttack:
            if ruleset.flags.encounter.famousCaptainKillCountsTrader { commander.kills.traders += 1 } // RUL-095
            commander.reputationScore = commander.reputationScore < 300 ? 300 : commander.reputationScore + 100
            markFamousCaptainDestroyed()
        case .dragonflyAttack:
            defeatSpecialShip(.dragonfly)
        case .pirateAttack, .pirateFlee, .pirateSurrender:
            commander.kills.pirates += 1
            if enc.opponent.type != .mantis {
                if commander.policeRecordScore >= -5 || ruleset.flags.bountyCreditedRegardlessOfRecord {
                    let b = bounty(of: enc.opponent)
                    commander.cash += b
                    // CMB-072: Palm shows the bounty dialog only at record ≥ −5 even though it always credits.
                    if commander.policeRecordScore >= -5 || !ruleset.flags.encounter.bountyEventRequiresRecord {
                        events.append(.bountyPaid(b))
                    }
                }
                commander.policeRecordScore += 1
                scoopRoll(enc.opponent)
            }
        case .policeAttack, .policeFlee:
            commander.kills.police += 1
            commander.policeRecordScore -= 6
        case .scarabAttack:
            defeatSpecialShip(.scarab)
        case .spaceMonsterAttack:
            commander.kills.pirates += 1
            commander.policeRecordScore += 1
            quests.spaceMonster = QuestStatus.SpaceMonster.destroyed
        case .traderAttack, .traderFlee, .traderSurrender:
            commander.kills.traders += 1
            commander.policeRecordScore -= 4
            scoopRoll(enc.opponent)
        default:
            break
        }
        commander.reputationScore += enc.opponent.type.rawValue / 2 + 1
        events.insert(.opponentDestroyed(enc.opponent.type), at: 0)
        return events
    }

    /// C# `EncounterScoop` draws: success (100% below Normal, else 1/difficulty) and the cargo unit picked.
    /// Sets `pendingScoop` for the player to accept or decline.
    mutating func scoopRoll(_ victim: Ship) {
        if ruleset.flags.encounter.scoopSource == .cheapRandom {
            // RUL-097 / CMB-085: Palm triggers on `rand(D) == 1` and favours cheap goods; the victim's cargo is ignored.
            guard difficulty < .normal || rng.next(below: difficulty.rawValue) == 1 else { return }
            var d = rng.next(below: 10)
            if d >= 5 { d = rng.next(below: 10) }
            pendingScoop = TradeItemType(rawValue: d)
            return
        }
        let filled = victim.filledNormalCargoBays
        let lucky = difficulty < .normal || rng.next(below: difficulty.rawValue) == 0
        guard lucky, filled > 0 else { return }
        let index = rng.next(below: filled)
        var item = -1
        var sum = 0
        while sum <= index {
            item += 1
            sum += victim.cargo[item]
        }
        pendingScoop = TradeItemType(rawValue: item)
    }
}
