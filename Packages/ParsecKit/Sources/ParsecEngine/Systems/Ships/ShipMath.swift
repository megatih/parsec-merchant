// SPDX-License-Identifier: GPL-2.0-or-later
// Derived ship/commander quantities (C# Ship/ShipSpec/Commander properties). docs/specs/SHP.md, BNK.md.

public extension Ship {
    /// The static spec for this ship (custom designs carry their own spec).
    func spec(_ ruleset: Ruleset) -> ShipSpec {
        if type == .custom, let customSpec { return customSpec }
        var s = ruleset.tables.ship(type)
        // RUL-117 (MOD-017): Modern reads the C# table's swapped fuel/repair columns back in Palm order.
        if ruleset.flags.economy.swapFuelAndRepairColumns { (s.fuelCost, s.repairCost) = (s.repairCost, s.fuelCost) }
        return s
    }

    func count(_ g: GadgetType) -> Int { gadgets.filter { $0 == g }.count }
    func has(_ g: GadgetType) -> Bool { gadgets.contains(g) }
    func has(_ s: ShieldType) -> Bool { shields.contains { $0.type == s } }
    /// C# `HasWeapon(type, exactCompare)`: with `exact == false`, any weapon of a higher type also counts.
    func has(_ w: WeaponType, exact: Bool = true) -> Bool {
        weapons.contains { $0 == w || (!exact && $0 > w) }
    }
    func hasCrew(_ id: Int) -> Bool { crew.contains(id) }

    var crewCount: Int { crew.compactMap { $0 }.count }
    var freeQuarters: Int { crew.filter { $0 == nil }.count }

    /// C# `Ship.HiddenCargoBays`: 5 per hidden-bays gadget.
    var hiddenCargoBays: Int { 5 * count(.hiddenCargoBays) }
    /// Bays added by extra-bays gadgets.
    var extraCargoBays: Int { 5 * count(.extraCargoBays) }
    var filledNormalCargoBays: Int { cargo.reduce(0, +) }

    func cargoBays(_ ruleset: Ruleset) -> Int { spec(ruleset).cargoBays + extraCargoBays + hiddenCargoBays }
    func freeWeaponSlots(_ ruleset: Ruleset) -> Int { spec(ruleset).weaponSlots - weapons.count }
    func freeShieldSlots(_ ruleset: Ruleset) -> Int { spec(ruleset).shieldSlots - shields.count }
    func freeGadgetSlots(_ ruleset: Ruleset) -> Int { spec(ruleset).gadgetSlots - gadgets.count }

    /// C# `Ship.FuelTanks`: spec tanks + 3 with a fuel compactor; Palm `GetFuelTanks`: 18 with a compactor (RUL-047).
    func fuelTanks(_ ruleset: Ruleset) -> Int {
        guard has(.fuelCompactor) else { return spec(ruleset).fuelTanks }
        switch ruleset.flags.economy.fuelCompactorRule {
        case .addsThree: return spec(ruleset).fuelTanks + 3
        case .setsEighteen: return 18
        }
    }
    /// C# `Ship.HullStrength`: spec hull + 50 when upgraded.
    func hullStrength(_ ruleset: Ruleset) -> Int { spec(ruleset).hullStrength + (hullUpgraded ? 50 : 0) }

    var shieldCharge: Int { shields.reduce(0) { $0 + $1.charge } }
    func shieldStrength(_ ruleset: Ruleset) -> Int { shields.reduce(0) { $0 + ruleset.tables.shield($1.type).power } }

    func weaponStrength(_ ruleset: Ruleset, from lo: WeaponType = .pulseLaser, to hi: WeaponType = .quantumDisruptor) -> Int {
        weapons.filter { $0 >= lo && $0 <= hi }.reduce(0) { $0 + ruleset.tables.weapon($1).power }
    }

    var illegalCargoUnits: Int {
        TradeItemType.allCases.filter(\.isIllegal).reduce(0) { $0 + cargo[$1.rawValue] }
    }
}

public extension GameState {
    /// Bays taken by quest cargo on the commander's ship (Japori antidote: 10; reactor: 5 + 10 − (status−1)/2).
    var questCargoBays: Int {
        var bays = 0
        if quests.japori == QuestStatus.Japori.inTransit { bays += 10 }
        if reactorOnBoard { bays += 5 + 10 - (quests.reactor - 1) / 2 }
        return bays
    }

    var reactorOnBoard: Bool {
        quests.reactor > QuestStatus.Reactor.notStarted && quests.reactor < QuestStatus.Reactor.delivered
    }
    var artifactOnBoard: Bool { quests.artifact == QuestStatus.Artifact.onBoard }
    var sculptureOnBoard: Bool { quests.sculpture == QuestStatus.Sculpture.inTransit }
    var hagglingComputer: Bool { quests.jarek == QuestStatus.Jarek.done }
    var wildOnBoard: Bool { commander.ship.hasCrew(CrewID.wild) }
    var jarekOnBoard: Bool { commander.ship.hasCrew(CrewID.jarek) }
    var princessOnBoard: Bool { commander.ship.hasCrew(CrewID.princess) }

    /// C# `Ship.FilledCargoBays` for the commander's ship.
    var filledCargoBays: Int { commander.ship.filledNormalCargoBays + questCargoBays }
    /// C# `Ship.FreeCargoBays` for the commander's ship.
    var freeCargoBays: Int { commander.ship.cargoBays(ruleset) - filledCargoBays }

    /// Effective ship skills of the commander's ship (Pilot, Fighter, Trader, Engineer).
    var shipSkills: [Int] {
        Skills.shipSkills(commander.ship, crew: mercenaries, difficulty: difficulty, ruleset: ruleset,
                          haggling: hagglingComputer)
    }
    func skill(_ s: SkillType) -> Int {
        switch ruleset.flags.economy.skillComputation {
        case .adjustThenGadgets: shipSkills[s.rawValue] + (s == .trader && hagglingComputer ? 1 : 0)
        // RUL-051: Palm adds the haggling bonus before the difficulty adjustment (inside `palmSkill`).
        case .gadgetsThenAdjust: shipSkills[s.rawValue]
        }
    }

    /// C# `Equipment.Price` for the commander: base × (100 − trader)/100, or 0 if the current system's tech is too low.
    func buyPrice(basePrice: Int, minTech: TechLevel) -> Int {
        currentSystem.techLevel >= minTech ? basePrice * (100 - skill(.trader)) / 100 : 0
    }

    /// C# `Ship.BaseWorth(forInsurance)` for a ship (equipment counted at 3/4 base price).
    func baseWorth(of ship: Ship, forInsurance: Bool) -> Int {
        let r = ruleset
        let spec = ship.spec(r)
        // RUL-056: Palm subtracts (type base tanks − min(fuel, tanks)) × fuel cost.
        let missingFuel = switch r.flags.economy.tradeInFuelTerm {
        case .actualTanks: ship.fuelTanks(r) - ship.fuel
        case .baseTanks: spec.fuelTanks - min(ship.fuel, ship.fuelTanks(r))
        }
        var price = spec.price * (ship.tribbles > 0 && !forInsurance ? 1 : 3) / 4
            - (ship.hullStrength(r) - ship.hull) * spec.repairCost
            - missingFuel * spec.fuelCost
        for w in ship.weapons { price += r.tables.weapon(w).price * 3 / 4 }
        for s in ship.shields { price += r.tables.shield(s.type).price * 3 / 4 }
        for g in ship.gadgets { price += r.tables.gadget(g).price * 3 / 4 }
        return price
    }

    /// C# `Ship.Worth(forInsurance)` for the commander's ship: base worth + cargo cost basis.
    func shipWorth(forInsurance: Bool) -> Int {
        baseWorth(of: commander.ship, forInsurance: forInsurance) + commander.priceCargo.reduce(0, +)
    }

    /// C# `Commander.Worth` (Commander.cs:389): ship list price + cash − debt (+ moon). With MOD-019 (RUL-119) and in
    /// Palm (`CurrentWorth`) the ship counts at its trade-in value plus the cargo cost basis.
    var worth: Int {
        let ship = ruleset.flags.economy.worthUsesTradeInValue
            ? shipWorth(forInsurance: false) : commander.ship.spec(ruleset).price
        return ship + commander.cash - commander.debt
            + (quests.moon > QuestStatus.Moon.notStarted ? QuestStatus.moonCost : 0)
    }

    /// C# `CrewMember.Rate`: (P+F+T+E)×3, free for special crew and Zeethibal (Palm pays Zeethibal: RUL-059).
    func dailyRate(of id: Int) -> Int {
        var free: Set<Int> = [CrewID.commander, CrewID.wild, CrewID.jarek, CrewID.princess, CrewID.zeethibal,
                              CrewID.dragonfly, CrewID.famousCaptain, CrewID.opponent, CrewID.scarab, CrewID.scorpion,
                              CrewID.spaceMonster]
        if ruleset.flags.economy.zeethibalPaid { free.remove(CrewID.zeethibal) }
        return free.contains(id) ? 0 : mercenaries[id].skills.reduce(0, +) * 3
    }

    /// C# `Game.MercenaryCosts` (Game.cs:3872): sums `Rate` from crew slot 1 up to the first vacancy; Palm
    /// `MercenaryMoney` skips vacancies (CRW-033).
    var mercenaryCosts: Int {
        var total = 0
        for slot in commander.ship.crew.indices.dropFirst() {
            guard let id = commander.ship.crew[slot] else {
                if ruleset.flags.economy.mercenaryCostSkipsVacancies { continue }
                break
            }
            total += dailyRate(of: id)
        }
        return total
    }

    /// C# `Game.InsuranceCosts`: max(1, BaseWorth(true) × 0.25% × (100 − noClaim)/100) when insured.
    var insuranceCosts: Int {
        guard commander.insurance else { return 0 }
        return insurancePremium(noClaim: commander.noClaim)
    }

    /// C# `Commander` interest: max(1, debt × 10%) when in debt.
    var interestCosts: Int { commander.debt > 0 ? max(1, Int(Double(commander.debt) * 0.1)) : 0 }

    /// C# `Game.WormholeCosts`: 25 × fuel cost when warping through a wormhole to the selected system.
    var wormholeCosts: Int {
        galaxy.wormholeExists(from: commander.currentSystem, to: warpSystem)
            ? 25 * commander.ship.spec(ruleset).fuelCost : 0
    }

    /// C# `Game.CurrentCosts`.
    var currentCosts: Int { insuranceCosts + interestCosts + mercenaryCosts + wormholeCosts }

    /// C# `Commander.CashToSpend`: cash, minus current costs when "reserve money" is on.
    /// Palm `ToSpend` (ECO-043): max(0, cash − mercenaries − insurance) when reserving.
    var cashToSpend: Int {
        guard options.reserveMoney else { return commander.cash }
        switch ruleset.flags.economy.cashToSpend {
        case .reserveAllCosts: return commander.cash - currentCosts
        case .reserveCrewAndInsurance: return max(0, commander.cash - mercenaryCosts - insuranceCosts)
        }
    }
}
