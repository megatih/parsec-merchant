// SPDX-License-Identifier: GPL-2.0-or-later
// Opponent generation: C# `Ship(OpponentType)` (Ship.cs:56-480), RNG call order preserved. docs/specs/ENC.md.

public extension GameState {
    /// C# `PoliticalSystem.ShipTypeLikely` for the warp (destination) system's government.
    func shipTypeLikely(_ type: ShipType, _ opp: OpponentType, government: PoliticalSystemSpec) -> Bool {
        let diffMod = max(0, difficulty.rawValue - Difficulty.normal.rawValue)
        let spec = ruleset.tables.ship(type)
        switch opp {
        case .pirate: return government.activityPirates.rawValue + diffMod >= spec.pirates.rawValue
        case .police: return government.activityPolice.rawValue + diffMod >= spec.police.rawValue
        case .trader: return government.activityTraders.rawValue + diffMod >= spec.traders.rawValue
        default: return false
        }
    }

    /// Generates an opponent ship for an encounter on the way to `warpSystem` (C# `new Ship(oppType)`).
    /// Like the source, it overwrites the skills of the shared "Opponent" crew member (id 31).
    mutating func generateOpponent(_ opp: OpponentType) -> Ship {
        let r = ruleset
        switch opp {
        case .famousCaptain:
            var ship = Ship(type: .wasp, spec: r.tables.ship(.wasp))
            // RUL-082: Palm fits 3 reflective shields regardless of the Wasp's slot count.
            ship.shields = Array(repeating: ShieldInstance(type: .reflective, charge: r.tables.shield(.reflective).power),
                                 count: r.flags.encounter.famousCaptainShieldCount ?? r.tables.ship(.wasp).shieldSlots)
            ship.weapons = Array(repeating: .militaryLaser, count: r.tables.ship(.wasp).weaponSlots)
            ship.gadgets = [.navigatingSystem, .targetingSystem]
            ship.crew[0] = CrewID.famousCaptain
            return ship
        case .bottle:
            return Ship(type: .bottle, spec: r.tables.ship(.bottle))
        default:
            break
        }
        let tries = opp == .mantis ? difficulty.rawValue + 1
            : max(1, worth / 150_000 + difficulty.rawValue - Difficulty.normal.rawValue)
        var ship = generateOpponentShip(opp)
        switch r.flags.encounter.opponentGenerationOrder {
        case .typeCrewGadgetsShieldsWeaponsHullCargo:
            generateOpponentCrew(&ship)
            addOpponentGadgets(&ship, tries: tries)
            addOpponentShields(&ship, tries: tries)
            addOpponentWeapons(&ship, tries: tries)
            if opp != .mantis { setOpponentHull(&ship) }
            if opp != .police { addOpponentCargo(&ship, opp: opp) }
        case .typeGadgetsCargoWeaponsShieldsHullCrew:
            // RUL-084 / ENC-084: Palm order; fuel takes no draw and the Mantis hull is forced full after its draws.
            addOpponentGadgets(&ship, tries: tries)
            addOpponentCargo(&ship, opp: opp)
            addOpponentWeapons(&ship, tries: tries)
            addOpponentShields(&ship, tries: tries)
            setOpponentHull(&ship)
            if opp == .mantis { ship.hull = ship.hullStrength(r) }
            generateOpponentCrew(&ship)
        }
        return ship
    }

    /// RUL-075: the base police ship-quality tries before the difficulty adjustment.
    func policeBaseTries() -> Int {
        let k = ruleset.flags.encounter.policeConstants
        let rec = commander.policeRecordScore
        switch ruleset.flags.encounter.policeTries {
        case .psychopathFirst:
            if rec < k.psychopath || wildOnBoard { return 5 }
            return rec < k.villain ? 3 : 1
        case .villainFirst:
            if rec < k.villain, !wildOnBoard { return 3 }
            return rec < k.psychopath || wildOnBoard ? 5 : 1
        }
    }

    /// C# `GenerateOpponentShip`.
    mutating func generateOpponentShip(_ opp: OpponentType) -> Ship {
        let r = ruleset
        let palmRoll = r.flags.encounter.opponentShipRoll == .cumulativeRedraw
        if opp == .mantis, !palmRoll { return Ship(type: .mantis, spec: r.tables.ship(.mantis)) }
        let gov = r.tables.politics(galaxy.systems[warpSystem].politics)
        var tries = 1
        switch opp {
        case .pirate:
            tries = max(1, 1 + worth / 100_000 + difficulty.rawValue - Difficulty.normal.rawValue)
        case .police:
            tries = max(1, policeBaseTries() + difficulty.rawValue - Difficulty.normal.rawValue)
        case .mantis:
            tries = difficulty.rawValue + 1
        default:
            break
        }
        var best: ShipType = opp == .trader ? .flea : .gnat
        if palmRoll {
            // RUL-076 / ENC-067: `rand(100)` over every type's cumulative occurrence; a disallowed type is redrawn
            // without using a try. The Mantis draws unfiltered and is then overwritten.
            let types = ShipType.buyable
            for _ in 0..<tries {
                var i = 0
                repeat {
                    let d = rng.next(below: 100)
                    i = 0
                    var sum = r.tables.ship(types[0]).occurrence
                    while sum < d, i < types.count - 1 {
                        i += 1
                        sum += r.tables.ship(types[i]).occurrence
                    }
                } while opp != .mantis && !shipTypeLikely(types[i], opp, government: gov)
                if i > best.rawValue { best = types[i] }
            }
            if opp == .mantis { best = .mantis }
            return Ship(type: best, spec: r.tables.ship(best))
        }
        let maxIndex = r.flags.waspOpponentReachable ? 10 : 9
        var total = 0
        for i in 0..<maxIndex {
            let t = ShipType.buyable[i]
            if shipTypeLikely(t, opp, government: gov) { total += r.tables.ship(t).occurrence }
        }
        for _ in 0..<tries {
            let x = rng.next(below: total)
            var sum = -1
            var j = -1
            repeat {
                j += 1
                let t = ShipType.buyable[j]
                if shipTypeLikely(t, opp, government: gov) {
                    sum = sum > 0 ? sum + r.tables.ship(t).occurrence : r.tables.ship(t).occurrence
                }
            } while sum < x && j < 9   // C# `j < Consts.MaxShip`; the weight total decides whether 9 is reachable
            if j > best.rawValue { best = ShipType.buyable[j] }
        }
        return Ship(type: best, spec: r.tables.ship(best))
    }

    /// C# `GenerateOpponentAddCrew`.
    mutating func generateOpponentCrew(_ ship: inout Ship) {
        let opp = CrewID.opponent
        mercenaries[opp].skills[0] = 1 + rng.next(below: 10)
        mercenaries[opp].skills[1] = 1 + rng.next(below: 10)
        mercenaries[opp].skills[2] = 1 + rng.next(below: 10)
        let wildCheck = ruleset.flags.kravatEngineerChecksPlayerWild ? wildOnBoard : ship.hasCrew(CrewID.wild)
        let palm = ruleset.flags.encounter.opponentGenerationOrder == .typeGadgetsCargoWeaponsShieldsHullCrew
        if palm {
            // ENC-073: Palm draws the engineer first and then the Kravat check.
            mercenaries[opp].skills[3] = 1 + rng.next(below: 10)
            if warpSystem == SystemID.kravat, wildCheck, rng.next(below: 10) < difficulty.rawValue + 1 { mercenaries[opp].skills[3] = 10 }
        } else if warpSystem == SystemID.kravat, wildCheck, rng.next(below: 10) < difficulty.rawValue + 1 {
            mercenaries[opp].skills[3] = 10
        } else {
            mercenaries[opp].skills[3] = 1 + rng.next(below: 10)
        }
        ship.crew[0] = opp
        let quarters = ship.crew.count
        var numCrew: Int
        if difficulty == .impossible {
            numCrew = quarters
        } else {
            numCrew = 1 + rng.next(below: quarters)
            if difficulty == .hard, numCrew < quarters { numCrew += 1 }
        }
        let special: Set<Int> = [CrewID.commander, CrewID.dragonfly, CrewID.famousCaptain, CrewID.jarek, CrewID.opponent,
                                 CrewID.princess, CrewID.scarab, CrewID.scorpion, CrewID.spaceMonster, CrewID.wild]
        var i = 1
        while i < numCrew {
            var pick: Int
            if ruleset.flags.encounter.opponentExtraCrew == .anySlot {
                pick = rng.next(below: min(31, mercenaries.count)) // RUL-085: Palm `rand(MAXCREWMEMBER)`, any slot
            } else {
                repeat {
                    pick = rng.next(below: mercenaries.count)
                } while special.contains(pick)
            }
            ship.crew[i] = pick
            i += 1
        }
    }

    /// Weighted pick over a chance table (C#: `x = GetRandom(100)`, walk while `sum < x`).
    private mutating func weightedIndex(_ chances: [Int]) -> Int {
        if ruleset.flags.encounter.opponentEquipmentRollBug {
            // RUL-077: Palm walks while `k < sum` over the buyable types, so a draw yields the first or the last type.
            let k = rng.next(below: 100)
            let last = chances.lastIndex { $0 > 0 } ?? 0
            var sum = chances[0]
            var j = 0
            while k < sum, j < last {
                j += 1
                sum += chances[j]
            }
            return j
        }
        let x = rng.next(below: 100)
        var sum = chances[0]
        var k = 0
        while sum < x, k <= chances.count - 1 {
            k += 1
            sum += chances[k]
        }
        return k
    }

    mutating func addOpponentGadgets(_ ship: inout Ship, tries: Int) {
        let slots = ship.spec(ruleset).gadgetSlots
        guard slots > 0 else { return }
        var count: Int
        if difficulty == .impossible {
            count = slots
        } else {
            count = rng.next(below: slots + 1)
            if count < slots, tries > 4 || (tries > 2 && rng.next(below: 2) > 0) { count += 1 }
        }
        let chances = ruleset.tables.gadgets.map(\.chance)
        for _ in 0..<count {
            var best = 0
            for _ in 0..<tries {
                let k = weightedIndex(chances)
                if !ship.has(GadgetType.allCases[k]), k > best { best = k }
            }
            ship.gadgets.append(GadgetType.allCases[best])
        }
    }

    mutating func addOpponentShields(_ ship: inout Ship, tries: Int) {
        let slots = ship.spec(ruleset).shieldSlots
        guard slots > 0 else { return }
        var count: Int
        if difficulty == .impossible {
            count = slots
        } else {
            count = rng.next(below: slots + 1)
            if count < slots, tries > 3 || (tries > 1 && rng.next(below: 2) > 0) { count += 1 }
        }
        let chances = ruleset.tables.shields.map(\.chance)
        let repeatable = ruleset.flags.encounter.opponentWeaponsShieldsMayRepeat // RUL-078
        for _ in 0..<count {
            var best = 0
            for _ in 0..<tries {
                let k = weightedIndex(chances)
                if repeatable || !ship.has(ShieldType.allCases[k]), k > best { best = k }
            }
            let type = ShieldType.allCases[best]
            let power = ruleset.tables.shield(type).power
            var charge = 0
            for _ in 0..<5 { charge = max(charge, 1 + rng.next(below: power)) }
            ship.shields.append(ShieldInstance(type: type, charge: charge))
        }
    }

    mutating func addOpponentWeapons(_ ship: inout Ship, tries: Int) {
        let slots = ship.spec(ruleset).weaponSlots
        guard slots > 0 else { return }
        var count: Int
        if difficulty == .impossible {
            count = slots
        } else if slots == 1 {
            count = 1
        } else {
            count = 1 + rng.next(below: slots)
            if ruleset.flags.encounter.opponentWeaponCountDifficulty {
                // RUL-079: Palm also adds a weapon with difficulty ≥ Hard.
                let hard = difficulty >= .hard
                if count < slots, (tries > 4 && hard) || ((tries > 3 || hard) && rng.next(below: 2) > 0) { count += 1 }
            } else if count < slots, tries > 4 || (tries > 3 && rng.next(below: 2) > 0) {
                count += 1
            }
        }
        let chances = ruleset.tables.weapons.map(\.chance)
        let repeatable = ruleset.flags.encounter.opponentWeaponsShieldsMayRepeat // RUL-078
        for _ in 0..<count {
            var best = 0
            for _ in 0..<tries {
                let k = weightedIndex(chances)
                if repeatable || !ship.has(WeaponType.allCases[k], exact: true), k > best { best = k }
            }
            ship.weapons.append(WeaponType.allCases[best])
        }
    }

    mutating func setOpponentHull(_ ship: inout Ship) {
        if ruleset.flags.encounter.opponentHullRoll == .fullIfShieldedSeventyPercent {
            // RUL-083: Palm keeps the full hull when shielded and `rand(10) ≤ 7`, else the best of five.
            if !ship.shields.isEmpty, rng.next(below: 10) <= 7 { return }
            let strength = ship.hullStrength(ruleset)
            var hull = 0
            for _ in 0..<5 { hull = max(hull, 1 + rng.next(below: strength)) }
            ship.hull = hull
            return
        }
        if ship.shieldStrength(ruleset) == 0 || rng.next(below: 5) == 0 {
            let strength = ship.hullStrength(ruleset)
            var hull = 0
            for _ in 0..<5 { hull = max(hull, 1 + rng.next(below: strength)) }
            ship.hull = hull
        }
    }

    mutating func addOpponentCargo(_ ship: inout Ship, opp: OpponentType) {
        let rules = ruleset.flags.encounter
        let bays = ship.cargoBays(ruleset)
        guard bays > rules.opponentCargoMinBays else { return } // RUL-080
        var toFill = bays
        if difficulty >= .normal { toFill = min(15, 3 + rng.next(below: toFill - 5)) }
        if opp == .police { toFill = 0 }
        if opp == .pirate {
            toFill = difficulty < .normal ? toFill * 4 / 5 : (rules.policeCargoMinimum ? toFill / difficulty.rawValue : max(1, toFill / difficulty.rawValue))
        }
        if rules.policeCargoMinimum { toFill = max(1, toFill) } // RUL-081: Palm's minimum of one unit applies to all
        var i = 0
        while i < toFill {
            let item = rng.next(below: 10)
            let amount = min(toFill - i, 1 + rng.next(below: 10 - item))
            ship.cargo[item] += amount
            i += amount
        }
    }
}
