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
            ship.shields = Array(repeating: ShieldInstance(type: .reflective, charge: r.tables.shield(.reflective).power),
                                 count: r.tables.ship(.wasp).shieldSlots)
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
        generateOpponentCrew(&ship)
        addOpponentGadgets(&ship, tries: tries)
        addOpponentShields(&ship, tries: tries)
        addOpponentWeapons(&ship, tries: tries)
        if opp != .mantis { setOpponentHull(&ship) }
        if opp != .police { addOpponentCargo(&ship, pirate: opp == .pirate) }
        return ship
    }

    /// C# `GenerateOpponentShip`.
    private mutating func generateOpponentShip(_ opp: OpponentType) -> Ship {
        let r = ruleset
        if opp == .mantis { return Ship(type: .mantis, spec: r.tables.ship(.mantis)) }
        let gov = r.tables.politics(galaxy.systems[warpSystem].politics)
        var tries = 1
        switch opp {
        case .pirate:
            tries = max(1, 1 + worth / 100_000 + difficulty.rawValue - Difficulty.normal.rawValue)
        case .police:
            if commander.policeRecordScore < -100 || wildOnBoard {
                tries = 5
            } else if commander.policeRecordScore < -70 {
                tries = 3
            }
            tries = max(1, tries + difficulty.rawValue - Difficulty.normal.rawValue)
        default:
            break
        }
        var best: ShipType = opp == .trader ? .flea : .gnat
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
    private mutating func generateOpponentCrew(_ ship: inout Ship) {
        let opp = CrewID.opponent
        mercenaries[opp].skills[0] = 1 + rng.next(below: 10)
        mercenaries[opp].skills[1] = 1 + rng.next(below: 10)
        mercenaries[opp].skills[2] = 1 + rng.next(below: 10)
        let wildCheck = ruleset.flags.kravatEngineerChecksPlayerWild ? wildOnBoard : ship.hasCrew(CrewID.wild)
        if warpSystem == SystemID.kravat, wildCheck, rng.next(below: 10) < difficulty.rawValue + 1 {
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
            repeat {
                pick = rng.next(below: mercenaries.count)
            } while special.contains(pick)
            ship.crew[i] = pick
            i += 1
        }
    }

    /// Weighted pick over a chance table (C#: `x = GetRandom(100)`, walk while `sum < x`).
    private mutating func weightedIndex(_ chances: [Int]) -> Int {
        let x = rng.next(below: 100)
        var sum = chances[0]
        var k = 0
        while sum < x, k <= chances.count - 1 {
            k += 1
            sum += chances[k]
        }
        return k
    }

    private mutating func addOpponentGadgets(_ ship: inout Ship, tries: Int) {
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

    private mutating func addOpponentShields(_ ship: inout Ship, tries: Int) {
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
        for _ in 0..<count {
            var best = 0
            for _ in 0..<tries {
                let k = weightedIndex(chances)
                if !ship.has(ShieldType.allCases[k]), k > best { best = k }
            }
            let type = ShieldType.allCases[best]
            let power = ruleset.tables.shield(type).power
            var charge = 0
            for _ in 0..<5 { charge = max(charge, 1 + rng.next(below: power)) }
            ship.shields.append(ShieldInstance(type: type, charge: charge))
        }
    }

    private mutating func addOpponentWeapons(_ ship: inout Ship, tries: Int) {
        let slots = ship.spec(ruleset).weaponSlots
        guard slots > 0 else { return }
        var count: Int
        if difficulty == .impossible {
            count = slots
        } else if slots == 1 {
            count = 1
        } else {
            count = 1 + rng.next(below: slots)
            if count < slots, tries > 4 || (tries > 3 && rng.next(below: 2) > 0) { count += 1 }
        }
        let chances = ruleset.tables.weapons.map(\.chance)
        for _ in 0..<count {
            var best = 0
            for _ in 0..<tries {
                let k = weightedIndex(chances)
                if !ship.has(WeaponType.allCases[k], exact: true), k > best { best = k }
            }
            ship.weapons.append(WeaponType.allCases[best])
        }
    }

    private mutating func setOpponentHull(_ ship: inout Ship) {
        if ship.shieldStrength(ruleset) == 0 || rng.next(below: 5) == 0 {
            let strength = ship.hullStrength(ruleset)
            var hull = 0
            for _ in 0..<5 { hull = max(hull, 1 + rng.next(below: strength)) }
            ship.hull = hull
        }
    }

    private mutating func addOpponentCargo(_ ship: inout Ship, pirate: Bool) {
        let bays = ship.cargoBays(ruleset)
        guard bays > 0 else { return }
        var toFill = bays
        if difficulty >= .normal { toFill = min(15, 3 + rng.next(below: toFill - 5)) }
        if pirate {
            toFill = difficulty < .normal ? toFill * 4 / 5 : max(1, toFill / difficulty.rawValue)
        }
        var i = 0
        while i < toFill {
            let item = rng.next(below: 10)
            let amount = min(toFill - i, 1 + rng.next(below: 10 - item))
            ship.cargo[item] += amount
            i += amount
        }
    }
}
