// SPDX-License-Identifier: GPL-2.0-or-later
// Docked services: fuel, repairs, escape pod, bank, insurance, crew, equipment, ship purchase.
// docs/specs/SHP.md, BNK.md, CRW.md.

/// Unique items that can follow the player to a new ship (SHP-038), in decision order.
public enum TransferItem: String, Codable, Sendable, CaseIterable {
    case morgansLaser, quantumDisruptor, lightningShield, fuelCompactor, hiddenCargoBays, escapePod
}

/// A ship-purchase quote (SHP-034…040).
public struct ShipQuote: Sendable, Equatable {
    public var type: ShipType
    public var netPrice: Int
    /// Transfer candidates in decision order with their prices.
    public var candidates: [(item: TransferItem, price: Int)]
    /// Unique items that will be lost because the new ship has no slot of their type.
    public var lost: [TransferItem]

    public static func == (a: ShipQuote, b: ShipQuote) -> Bool {
        a.type == b.type && a.netPrice == b.netPrice && a.lost == b.lost
            && a.candidates.map(\.item) == b.candidates.map(\.item) && a.candidates.map(\.price) == b.candidates.map(\.price)
    }
}

public extension GameState {
    // MARK: Fuel & repairs (SHP-051…054)
    var fuelCapacity: Int { commander.ship.fuelTanks(ruleset) }
    var fullTankCost: Int { (fuelCapacity - commander.ship.fuel) * commander.ship.spec(ruleset).fuelCost }
    var fullRepairCost: Int {
        (commander.ship.hullStrength(ruleset) - commander.ship.hull) * commander.ship.spec(ruleset).repairCost
    }

    // MARK: Bank (BNK-011, BNK-060)
    var maxLoan: Int {
        commander.policeRecordScore >= 0 ? min(25_000, max(1_000, worth / 5_000 * 500)) : 500
    }
    var availableToBorrow: Int { max(0, maxLoan - commander.debt) }
    var maxRepay: Int { min(commander.debt, commander.cash) }

    // MARK: Escape pod (SHP-049)
    var escapePodOffered: Bool {
        // SHP-050: Palm tests ToSpend() instead of cash.
        let money = ruleset.flags.economy.escapePodPurchaseUsesToSpend ? cashToSpend : commander.cash
        return !commander.ship.escapePod && currentSystem.techLevel >= .earlyIndustrial && money >= 2_000
    }

    // MARK: Crew (CRW-027)
    var mercenariesForHire: [Int] {
        let here = (1..<mercenaries.count).filter {
            mercenaries[$0].systemID == commander.currentSystem && !commander.ship.hasCrew($0)
        }
        // CRW-028: Palm offers only the lowest-index mercenary of the system.
        guard let limit = ruleset.flags.economy.mercenariesOfferedPerSystem else { return here }
        return Array(here.prefix(limit))
    }

    /// Special crew aboard (Commander, Jarek, Princess, Wild) — C# `Ship.SpecialCrew` restricted to passengers + commander.
    var specialCrewCount: Int {
        commander.ship.crew.compactMap { $0 }.filter { [CrewID.commander, CrewID.jarek, CrewID.princess, CrewID.wild].contains($0) }.count
    }

    // MARK: Equipment prices (SHP-011…013)
    func equipmentBuyPrice(weapon w: WeaponType) -> Int {
        let s = ruleset.tables.weapon(w)
        return buyPrice(basePrice: s.price, minTech: s.minTechLevel)
    }
    func equipmentBuyPrice(shield s: ShieldType) -> Int {
        let spec = ruleset.tables.shield(s)
        return buyPrice(basePrice: spec.price, minTech: spec.minTechLevel)
    }
    func equipmentBuyPrice(gadget g: GadgetType) -> Int {
        let spec = ruleset.tables.gadget(g)
        return buyPrice(basePrice: spec.price, minTech: spec.minTechLevel)
    }

    func transferPrice(_ item: TransferItem) -> Int {
        let t = ruleset.tables
        // RUL-053: Palm's fixed transfer prices.
        if ruleset.flags.economy.shipTradeFlow == .palm {
            switch item {
            case .lightningShield: return 30_000
            case .fuelCompactor: return 20_000
            case .morgansLaser: return 33_333
            default: break
            }
        }
        func tp(_ base: Int) -> Int { base * 3 / 4 * 110 / 90 }
        switch item {
        case .morgansLaser: return tp(t.weapon(.morgansLaser).price)
        case .quantumDisruptor: return tp(t.weapon(.quantumDisruptor).price)
        case .lightningShield: return tp(t.shield(.lightning).price)
        case .fuelCompactor: return tp(t.gadget(.fuelCompactor).price)
        case .hiddenCargoBays: return tp(t.gadget(.hiddenCargoBays).price)
        case .escapePod: return 200
        }
    }

    /// SHP-034: net price of buying `type` (list price minus current ship worth including cargo cost basis).
    func shipQuote(_ type: ShipType) -> ShipQuote {
        let newSpec = ruleset.tables.ship(type)
        return shipQuote(type, spec: newSpec, netPrice: shipNetPrice(newSpec))
    }

    /// SHP-034/SHP-035 (RUL-052): `Price − tradeIn`; Palm `Price × (100 − Trader)/100 − tradeIn`, where 0 becomes 1.
    func shipNetPrice(_ newSpec: ShipSpec) -> Int {
        guard ruleset.flags.economy.shipTraderDiscount else { return newSpec.price - shipWorth(forInsurance: false) }
        let net = newSpec.price * (100 - skill(.trader)) / 100 - shipWorth(forInsurance: false)
        return net == 0 ? 1 : net
    }

    /// SHP-038: transfer candidates and lost items for a new ship with `newSpec`.
    func shipQuote(_ type: ShipType, spec newSpec: ShipSpec, netPrice net: Int) -> ShipQuote {
        var candidates: [(TransferItem, Int)] = []
        var lost: [TransferItem] = []
        let ship = commander.ship
        let palm = ruleset.flags.economy.shipTradeFlow == .palm
        // SHP-042: Palm offers Lightning, Compactor, Morgan's in that order; the pod is never a candidate (SHP-043).
        let installed: [(TransferItem, Bool, Int)] = palm ? [
            (.lightningShield, ship.has(.lightning), newSpec.shieldSlots),
            (.fuelCompactor, ship.has(.fuelCompactor), newSpec.gadgetSlots),
            (.morgansLaser, ship.has(.morgansLaser), newSpec.weaponSlots),
        ] : [
            (.morgansLaser, ship.has(.morgansLaser), newSpec.weaponSlots),
            (.quantumDisruptor, ship.has(.quantumDisruptor), newSpec.weaponSlots),
            (.lightningShield, ship.has(.lightning), newSpec.shieldSlots),
            (.fuelCompactor, ship.has(.fuelCompactor), newSpec.gadgetSlots),
            (.hiddenCargoBays, ship.has(.hiddenCargoBays), newSpec.gadgetSlots),
        ]
        for (item, has, slots) in installed where has {
            if slots == 0 { lost.append(item) } else { candidates.append((item, transferPrice(item))) }
        }
        if ship.escapePod, !palm { candidates.append((.escapePod, 200)) }
        return ShipQuote(type: type, netPrice: net, candidates: candidates, lost: lost)
    }

    /// SHP-033: ship types offered here.
    var shipsForSale: [ShipType] {
        guard currentSystem.techLevel >= .earlyIndustrial else { return [] }
        return ShipType.buyable.filter { ruleset.tables.ship($0).minTechLevel <= currentSystem.techLevel && $0 != commander.ship.type }
    }
}

extension GameEngine {
    var docked: Bool { if case .docked = state.phase { true } else { false } }

    // MARK: Fuel & repairs
    mutating func buyFuel(credits: Int) -> StepResult {
        guard docked else { return .rejected(.notAllowedInPhase) }
        let cost = state.commander.ship.spec(ruleset).fuelCost
        guard state.fuelCapacity - state.commander.ship.fuel > 0 else { return .rejected(.tankFull) }
        let amount = min(credits, state.fullTankCost, state.commander.cash)
        let units = amount / max(1, cost)
        guard units > 0 else { return .rejected(.invalidAmount) }
        state.commander.ship.fuel += units
        state.commander.cash -= units * cost
        return StepResult(events: [.boughtFuel(units: units, cost: units * cost)])
    }

    mutating func repairHull(credits: Int) -> StepResult {
        guard docked else { return .rejected(.notAllowedInPhase) }
        let cost = state.commander.ship.spec(ruleset).repairCost
        guard state.commander.ship.hullStrength(ruleset) - state.commander.ship.hull > 0 else {
            return .rejected(.noRepairsNeeded)
        }
        let amount = min(credits, state.fullRepairCost, state.commander.cash)
        let points = amount / max(1, cost)
        guard points > 0 else { return .rejected(.invalidAmount) }
        state.commander.ship.hull += points
        state.commander.cash -= points * cost
        return StepResult(events: [.repairedHull(points: points, cost: points * cost)])
    }

    // MARK: Escape pod & insurance
    mutating func buyEscapePod(_ ack: Set<WarningID>) -> StepResult {
        guard docked else { return .rejected(.notAllowedInPhase) }
        if state.commander.ship.escapePod { return .rejected(.alreadyHaveEscapePod) }
        guard state.escapePodOffered else {
            return .rejected(state.commander.cash < 2_000 ? .insufficientFunds : .escapePodNotAvailable)
        }
        guard ack.contains(.buyEscapePod) else { return .needsConfirmation(Confirmation(.buyEscapePod, amounts: [2_000])) }
        state.commander.cash -= 2_000
        state.commander.ship.escapePod = true
        return StepResult(events: [.boughtEscapePod(price: 2_000)])
    }

    mutating func buyInsurance() -> StepResult {
        if !state.commander.ship.escapePod { return .rejected(.insuranceRequiresEscapePod) }
        if state.commander.insurance { return .rejected(.insuranceAlreadyActive) }
        state.commander.insurance = true
        // RUL-046: Palm keeps the no-claim counter when buying (only stopping resets it).
        if ruleset.flags.economy.buyInsuranceResetsNoClaim { state.commander.noClaim = 0 }
        return StepResult(events: [.insuranceBought])
    }

    mutating func stopInsurance(_ ack: Set<WarningID>) -> StepResult {
        if !state.commander.insurance { return .rejected(.insuranceNotActive) }
        guard ack.contains(.stopInsurance) else { return .needsConfirmation(Confirmation(.stopInsurance)) }
        state.commander.insurance = false
        state.commander.noClaim = 0
        return StepResult(events: [.insuranceStopped])
    }

    // MARK: Loans
    mutating func borrow(_ amount: Int) -> StepResult {
        if state.commander.debt >= state.maxLoan { return .rejected(.debtTooLargeForLoan) }
        if amount < 1 { return .rejected(.invalidAmount) }
        if amount > state.maxLoan - state.commander.debt { return .rejected(.exceedsAvailableLoan) }
        state.commander.cash += amount
        state.commander.debt += amount
        return StepResult(events: [.borrowed(amount: amount)])
    }

    mutating func repay(_ amount: Int) -> StepResult {
        if state.commander.debt == 0 { return .rejected(.noDebt) }
        if amount < 1 { return .rejected(.invalidAmount) }
        if amount > state.maxRepay { return .rejected(.exceedsRepayable) }
        state.commander.cash -= amount
        state.commander.debt -= amount
        return StepResult(events: [.repaid(amount: amount)])
    }

    // MARK: Crew
    mutating func hire(_ id: Int) -> StepResult {
        guard docked else { return .rejected(.notAllowedInPhase) }
        guard state.mercenariesForHire.contains(id), state.dailyRate(of: id) > 0 || id == CrewID.zeethibal else {
            return .rejected(.notForHire)
        }
        guard let slot = state.commander.ship.crew.firstIndex(where: { $0 == nil }) else { return .rejected(.noFreeQuarters) }
        state.commander.ship.crew[slot] = id
        recalculateBuyPrices()
        return StepResult(events: [.hired(crewID: id)])
    }

    mutating func fire(_ id: Int, _ ack: Set<WarningID>) -> StepResult {
        guard let slot = state.commander.ship.crew.firstIndex(of: id), slot > 0 else { return .rejected(.notInCrew) }
        if [CrewID.wild, CrewID.jarek, CrewID.princess].contains(id) { return .rejected(.cannotFireSpecialPassenger) }
        guard ack.contains(.fireMercenary) else { return .needsConfirmation(Confirmation(.fireMercenary, amounts: [id])) }
        var crew = state.commander.ship.crew
        crew.remove(at: slot)
        crew.append(nil)
        state.commander.ship.crew = crew
        // CRW-039: a fired mercenary moves to a random system within distance < 20 of the current one (C#);
        // Palm leaves it in its system (RUL-060, CRW-040).
        if ruleset.flags.economy.firedMercenaryRelocates {
            state.relocateMercenary(id, near: state.commander.currentSystem)
        }
        recalculateBuyPrices()
        return StepResult(events: [.fired(crewID: id)])
    }

    /// C# `RecalculateBuyPrices` after the trader skill changes.
    mutating func recalculateBuyPrices() {
        state.buyPrices = Pricing.buyPrices(sell: state.sellPrices, in: state.currentSystem,
                                            criminal: state.commander.policeRecordScore < -5,
                                            traderSkill: state.skill(.trader), ruleset: ruleset)
    }

    // MARK: Equipment (SHP-020…026)
    mutating func buyEquipment(weapon: WeaponType? = nil, shield: ShieldType? = nil, gadget: GadgetType? = nil,
                               _ ack: Set<WarningID>) -> StepResult {
        guard docked else { return .rejected(.notAllowedInPhase) }
        let r = ruleset
        let price: Int
        let freeSlots: Int
        if let weapon {
            price = state.equipmentBuyPrice(weapon: weapon)
            freeSlots = state.commander.ship.freeWeaponSlots(r)
        } else if let shield {
            price = state.equipmentBuyPrice(shield: shield)
            freeSlots = state.commander.ship.freeShieldSlots(r)
        } else if let gadget {
            if gadget != .extraCargoBays, state.commander.ship.has(gadget) { return .rejected(.equipmentAlreadyOwned) }
            price = state.equipmentBuyPrice(gadget: gadget)
            freeSlots = state.commander.ship.freeGadgetSlots(r)
        } else {
            return .rejected(.invalidArgument)
        }
        if price <= 0 { return .rejected(.notSoldHere) }
        if state.commander.debt > 0 { return .rejected(.inDebt) }
        if price > state.cashToSpend { return .rejected(.insufficientFunds) }
        if freeSlots <= 0 { return .rejected(.noFreeSlot) }
        guard ack.contains(.buyEquipment) else { return .needsConfirmation(Confirmation(.buyEquipment, amounts: [price])) }
        if let weapon { state.commander.ship.weapons.append(weapon) }
        if let shield { state.commander.ship.shields.append(ShieldInstance(type: shield, charge: r.tables.shield(shield).power)) }
        if let gadget {
            state.commander.ship.gadgets.append(gadget)
            if r.tables.gadget(gadget).skillBonus == .trader { recalculateBuyPrices() }
        }
        state.commander.cash -= price
        return StepResult(events: [.boughtEquipment(price: price)])
    }

    mutating func sellEquipment(weaponIndex: Int? = nil, shieldIndex: Int? = nil, gadgetIndex: Int? = nil,
                                _ ack: Set<WarningID>) -> StepResult {
        guard docked else { return .rejected(.notAllowedInPhase) }
        let t = ruleset.tables
        var ship = state.commander.ship
        let price: Int
        if let i = weaponIndex, ship.weapons.indices.contains(i) {
            price = t.weapon(ship.weapons[i]).price * 3 / 4
            ship.weapons.remove(at: i)
        } else if let i = shieldIndex, ship.shields.indices.contains(i) {
            price = t.shield(ship.shields[i].type).price * 3 / 4
            ship.shields.remove(at: i)
        } else if let i = gadgetIndex, ship.gadgets.indices.contains(i) {
            let g = ship.gadgets[i]
            if g == .extraCargoBays || g == .hiddenCargoBays, state.freeCargoBays < 5 { return .rejected(.extraBaysInUse) }
            price = t.gadget(g).price * 3 / 4
            ship.gadgets.remove(at: i)
        } else {
            return .rejected(.invalidArgument)
        }
        guard ack.contains(.sellEquipment) else { return .needsConfirmation(Confirmation(.sellEquipment, amounts: [price])) }
        state.commander.ship = ship
        state.commander.cash += price
        recalculateBuyPrices()
        return StepResult(events: [.soldEquipment(price: price)])
    }

    // MARK: Ship purchase (SHP-033…048)
    mutating func buyShip(_ type: ShipType, accepting wanted: [TransferItem], _ ack: Set<WarningID>) -> StepResult {
        guard docked else { return .rejected(.notAllowedInPhase) }
        guard state.shipsForSale.contains(type) else {
            return .rejected(type == state.commander.ship.type ? .alreadyOwnThisShipType : .notSoldHere)
        }
        let spec = ruleset.tables.ship(type)
        return tradeShip(type, spec: spec, netPrice: state.shipNetPrice(spec), accepting: wanted, ack)
    }

    /// SHP-075: builds a designed ship through the TradeShip flow.
    mutating func buildDesign(_ design: ShipDesign, accepting wanted: [TransferItem], _ ack: Set<WarningID>) -> StepResult {
        guard docked else { return .rejected(.notAllowedInPhase) }
        guard let quote = state.designQuote(design) else { return .rejected(.notSoldHere) }
        if let blocker = quote.blocker { return .rejected(blocker) }
        let result = tradeShip(.custom, spec: quote.spec, netPrice: quote.totalCost, accepting: wanted, ack)
        guard result.rejection == nil, result.decision == nil, let yard = state.currentSystem.shipyard else { return result }
        state.commander.shipName = quote.design.name
        var r = result
        r.events.append(.customShipBuilt(shipyard: yard))
        return r
    }

    /// C# `Commander.TradeShip` (SHP-036…048) for a stock or custom spec.
    mutating func tradeShip(_ type: ShipType, spec newSpec: ShipSpec, netPrice net: Int, accepting wanted: [TransferItem],
                            _ ack: Set<WarningID>) -> StepResult {
        let quote = state.shipQuote(type, spec: newSpec, netPrice: net)
        let palm = ruleset.flags.economy.shipTradeFlow == .palm
        if net > 0, state.commander.debt > 0 { return .rejected(.inDebt) }
        if net > state.cashToSpend { return .rejected(.insufficientFunds) }
        if newSpec.crewQuarters < state.specialCrewCount { return .rejected(.passengersNeedQuarters) }
        // SHP-037: Palm checks the reactor before the crew count, and counts hired crew (commander + mercenaries)
        // without the passengers.
        let passengers = [CrewID.jarek, CrewID.wild].filter { state.commander.ship.hasCrew($0) }.count
        let hired = state.commander.ship.crewCount - (ruleset.flags.economy.passengersAsCrew ? 0 : passengers)
        if palm, state.reactorOnBoard { return .rejected(.reactorOnBoard) }
        if newSpec.crewQuarters < hired { return .rejected(.notEnoughQuarters) }
        if state.reactorOnBoard { return .rejected(.reactorOnBoard) }

        var events: [GameEvent] = quote.lost.map { .cannotTransfer($0) }
        // SHP-042: Palm's pre-check also adds items that cannot be transferred.
        let precheck = quote.candidates.reduce(0) { $0 + $1.price }
            + (palm ? quote.lost.reduce(0) { $0 + state.transferPrice($1) } : 0)
        if net + precheck > state.cashToSpend, !(quote.candidates.isEmpty && (!palm || quote.lost.isEmpty)) {
            events.append(.cannotAffordAllTransfers)
        }
        var extra = 0
        var accepted: [TransferItem] = []
        for (item, price) in quote.candidates {
            // SHP-042: Palm does not include the item's own price in the affordability test.
            if net + extra + (palm ? 0 : price) > state.cashToSpend {
                events.append(.cannotAffordTransfer(item))
            } else if wanted.contains(item) {
                extra += price
                accepted.append(item)
            }
        }
        guard ack.contains(.buyShip) else {
            return .needsConfirmation(Confirmation(.buyShip, amounts: [net, extra]))
        }
        let old = state.commander.ship
        var ship = Ship(type: type, spec: newSpec)
        if type == .custom { ship.customSpec = newSpec }
        for j in 0..<min(old.crew.count, ship.crew.count) { ship.crew[j] = old.crew[j] }
        for item in accepted {
            switch item {
            case .morgansLaser: ship.weapons.append(.morgansLaser)
            case .quantumDisruptor: ship.weapons.append(.quantumDisruptor)
            case .lightningShield:
                // RUL-055: Palm's transferred Lightning shield is uncharged until the next recharge.
                let charge = palm ? 0
                    : old.shields.first { $0.type == .lightning }?.charge ?? ruleset.tables.shield(.lightning).power
                ship.shields.append(ShieldInstance(type: .lightning, charge: charge))
            case .fuelCompactor: ship.gadgets.append(.fuelCompactor)
            case .hiddenCargoBays: ship.gadgets.append(.hiddenCargoBays)
            case .escapePod: ship.escapePod = true
            }
        }
        // RUL-054/SHP-043: Palm keeps the escape pod and insurance for free.
        if palm { ship.escapePod = old.escapePod }
        if !ship.escapePod, state.commander.insurance {
            state.commander.insurance = false
            state.commander.noClaim = 0
        }
        state.commander.ship = ship
        state.commander.cash -= net + extra
        if ruleset.flags.resetPriceCargoOnHoldClear || palm {
            state.commander.priceCargo = Array(repeating: 0, count: TradeItemType.allCases.count)
        }
        if state.quests.scarab == QuestStatus.Scarab.done { state.quests.scarab = QuestStatus.Scarab.notStarted }
        recalculateBuyPrices()
        events.append(.boughtShip(type: type, netPrice: net + extra))
        return StepResult(events: events)
    }
}
