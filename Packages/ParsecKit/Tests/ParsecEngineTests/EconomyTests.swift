// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecEngine

/// Builds a docked engine with a known state for economy tests.
func makeEngine(_ ruleset: RulesetID = .windows201, seed: UInt64 = 42, difficulty: Difficulty = .normal,
                _ adjust: (inout GameState) -> Void = { _ in }) -> GameEngine {
    var e = GameEngine(config: NewGameConfig(commanderName: "Test", difficulty: difficulty, ruleset: ruleset, seed: seed))
    adjust(&e.state)
    return e
}

/// Forces a simple market in the current system: every item traded at known prices with stock 20.
func setMarket(_ s: inout GameState, buy: Int = 100, sell: Int = 90, stock: Int = 20) {
    s.buyPrices = Array(repeating: buy, count: 10)
    s.sellPrices = Array(repeating: sell, count: 10)
    s.galaxy.systems[s.commander.currentSystem].tradeItems = Array(repeating: stock, count: 10)
}

@Suite("Economy: market (ECO)")
struct MarketTests {
    @Test("ECO-045 buy checks run in order: debt, availability, bays, funds")
    func buyCheckOrder() {
        var e = makeEngine { s in setMarket(&s); s.commander.debt = 100_001 }
        #expect(e.perform(.buyCargo(.water, quantity: 1)).rejection == .debtTooLargeToTrade)
        e = makeEngine { s in setMarket(&s, stock: 0) }
        #expect(e.perform(.buyCargo(.water, quantity: 1)).rejection == .cargoNoneAvailable)
        e = makeEngine { s in setMarket(&s); s.commander.ship.cargo[1] = s.commander.ship.cargoBays(s.ruleset) }
        #expect(e.perform(.buyCargo(.water, quantity: 1)).rejection == .noEmptyBays)
        e = makeEngine { s in setMarket(&s); s.commander.cash = 50 }
        #expect(e.perform(.buyCargo(.water, quantity: 1)).rejection == .insufficientFunds)
    }

    @Test("ECO-046 ECO-047 max quantity = min(free bays − leaveEmpty, stock, cashToSpend / price)")
    func maxQuantity() throws {
        let e = makeEngine { s in setMarket(&s, buy: 100, stock: 20); s.commander.cash = 1_250; s.options.leaveEmpty = 2 }
        // Gnat: 15 bays − 2 = 13; stock 20; 1250/100 = 12
        #expect(try e.state.marketBuyCheck(.food).get() == 12)
    }

    @Test("ECO-048 buying moves stock, cash and cost basis")
    func buyEffects() {
        var e = makeEngine { s in setMarket(&s, buy: 100); s.commander.cash = 1_000 }
        let r = e.perform(.buyCargo(.ore, quantity: 3))
        #expect(r.rejection == nil)
        #expect(e.state.commander.ship.cargo[3] == 3)
        #expect(e.state.currentSystem.tradeItems[3] == 17)
        #expect(e.state.commander.cash == 700)
        #expect(e.state.commander.priceCargo[3] == 300)
        #expect(e.perform(.buyCargo(.ore, quantity: 0)).rejection == .invalidQuantity)
    }

    @Test("ECO-049 ECO-051 selling scales the cost basis with the pre-sale quantity")
    func sellEffects() {
        var e = makeEngine { s in setMarket(&s, sell: 150); s.commander.ship.cargo[2] = 4; s.commander.priceCargo[2] = 400 }
        #expect(e.perform(.sellCargo(.water, quantity: 1)).rejection == .cargoNoneToSell)
        let r = e.perform(.sellCargo(.food, quantity: 1))
        #expect(r.events == [.soldCargo(item: .food, quantity: 1, total: 150, profit: 50)])
        #expect(e.state.commander.priceCargo[2] == 300)
        #expect(e.state.commander.ship.cargo[2] == 3)
        e.state.sellPrices[2] = 0
        #expect(e.perform(.sellCargo(.food, quantity: 1)).rejection == .marketNotInterested)
    }

    @Test("ECO-052 ECO-053 dumping costs 5×(difficulty+1) per unit, capped by cash to spend")
    func dump() throws {
        var e = makeEngine(difficulty: .hard) { s in setMarket(&s, sell: 0); s.commander.ship.cargo[8] = 10; s.commander.cash = 45 }
        #expect(e.state.dumpCostPerUnit == 20)
        #expect(try e.state.marketSellCheck(.narcotics, dump: true).get() == 2)
        _ = e.perform(.dumpCargo(.narcotics, quantity: 2))
        #expect(e.state.commander.cash == 5)
        #expect(e.state.commander.ship.cargo[8] == 8)
    }

    @Test("ECO-056 ECO-080 jettison needs the littering warning once; declining changes nothing")
    func litteringWarning() {
        var e = makeEngine { s in s.commander.ship.cargo[0] = 5 }
        let before = e.state
        let r = e.perform(.jettisonCargo(.water, quantity: 1))
        #expect(r.decision == .confirm(Confirmation(.litteringWarning)))
        #expect(e.state == before)
        _ = e.perform(.jettisonCargo(.water, quantity: 1), acknowledging: [.litteringWarning])
        #expect(e.state.litterWarning)
        #expect(e.state.commander.ship.cargo[0] == 4)
        #expect(e.perform(.jettisonCargo(.water, quantity: 1)).decision == nil)
    }

    @Test("ECO-057 caught littering sets record to −5 (or −1 below) and adds news")
    func caughtLittering() {
        // Impossible: GetRandom(10) < 5 → caught half the time; run until caught.
        var caught = false
        for seed in 1...40 where !caught {
            var e = makeEngine(seed: UInt64(seed), difficulty: .impossible) { s in s.commander.ship.cargo[0] = 5; s.litterWarning = true }
            let r = e.perform(.jettisonCargo(.water, quantity: 1))
            if r.events.contains(.caughtLittering(newRecord: -5)) {
                caught = true
                #expect(e.state.commander.policeRecordScore == -5)
                #expect(e.state.newsEvents.contains(.caughtLittering))
            }
        }
        #expect(caught)
    }

    @Test("ECO-077 market preview lists all ten items")
    func marketPreview() {
        let e = makeEngine { s in setMarket(&s); s.commander.ship.cargo[0] = 2; s.commander.priceCargo[0] = 50; s.sellPrices[5] = 0 }
        let rows = e.state.marketRows
        #expect(rows.count == 10)
        #expect(rows[0].costBasisPerUnit == 25)
        #expect(rows[5].dumpCostPerUnit == 15)
    }
}

@Suite("Ships, equipment and services (SHP)")
struct ShipServiceTests {
    @Test("SHP-011 SHP-012 equipment buy price applies trader skill and tech; sell is 3/4")
    func equipmentPrices() {
        let e = makeEngine { s in s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech }
        let trader = e.state.skill(.trader)
        #expect(e.state.equipmentBuyPrice(weapon: .beamLaser) == 12_500 * (100 - trader) / 100)
        let low = makeEngine { s in s.galaxy.systems[s.commander.currentSystem].techLevel = .agricultural }
        #expect(low.state.equipmentBuyPrice(weapon: .pulseLaser) == 0)
        #expect(Windows201Tables.weapons[1].price * 3 / 4 == 9_375)
    }

    @Test("SHP-020 equipment buy checks: owned gadget, debt, funds, slot; then confirmation")
    func equipmentChecks() {
        var e = makeEngine { s in s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech; s.commander.cash = 100_000 }
        #expect(e.perform(.buyGadget(.navigatingSystem)).decision != nil)
        _ = e.perform(.buyGadget(.navigatingSystem), acknowledging: [.buyEquipment])
        #expect(e.perform(.buyGadget(.navigatingSystem), acknowledging: [.buyEquipment]).rejection == .equipmentAlreadyOwned)
        e.state.commander.debt = 1
        #expect(e.perform(.buyWeapon(.pulseLaser), acknowledging: [.buyEquipment]).rejection == .inDebt)
        e.state.commander.debt = 0
        // Gnat has 1 weapon slot, already holding the starting pulse laser.
        #expect(e.perform(.buyWeapon(.pulseLaser), acknowledging: [.buyEquipment]).rejection == .noFreeSlot)
    }

    @Test("SHP-024 SHP-025 selling equipment refunds 3/4; extra bays refused when fewer than 5 free")
    func sellEquipment() {
        var e = makeEngine { s in s.commander.ship.gadgets = [.extraCargoBays]; s.commander.ship.cargo[0] = 17 }
        #expect(e.perform(.sellGadget(index: 0), acknowledging: [.sellEquipment]).rejection == .extraBaysInUse)
        let cash = e.state.commander.cash
        _ = e.perform(.sellWeapon(index: 0), acknowledging: [.sellEquipment])
        #expect(e.state.commander.cash == cash + 1_500)
        #expect(e.state.commander.ship.weapons.isEmpty)
    }

    @Test("SHP-034 net ship price = list price − worth (Gnat + pulse laser → Firefly 16000)")
    func shipNetPrice() {
        let e = makeEngine { s in s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech }
        #expect(e.state.shipQuote(.firefly).netPrice == 25_000 - 9_000)
    }

    @Test("SHP-044 SHP-046 buying a ship keeps crew; Windows 2.01 keeps the stale cost basis (exploit)")
    func tradeShipWindows() {
        var e = makeEngine { s in
            s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech
            s.commander.cash = 50_000
            s.commander.ship.cargo[0] = 10
            s.commander.priceCargo[0] = 1_000
        }
        let r = e.perform(.buyShip(.firefly, transfers: []), acknowledging: [.buyShip])
        #expect(r.rejection == nil)
        #expect(e.state.commander.ship.type == .firefly)
        #expect(e.state.commander.ship.cargo.allSatisfy { $0 == 0 })
        #expect(e.state.commander.ship.crew[0] == CrewID.commander)
        #expect(e.state.commander.priceCargo[0] == 1_000)
    }

    @Test("SHP-047 Modern resets the cost basis when the hold is cleared")
    func tradeShipModern() {
        var e = makeEngine(.modern) { s in
            s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech
            s.commander.cash = 50_000
            s.commander.ship.cargo[0] = 10
            s.commander.priceCargo[0] = 1_000
        }
        _ = e.perform(.buyShip(.firefly, transfers: []), acknowledging: [.buyShip])
        #expect(e.state.commander.priceCargo.allSatisfy { $0 == 0 })
    }

    @Test("SHP-036 ship purchase refused in debt with a positive net price")
    func tradeShipChecks() {
        var e = makeEngine { s in s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech; s.commander.debt = 10 }
        #expect(e.perform(.buyShip(.firefly, transfers: []), acknowledging: [.buyShip]).rejection == .inDebt)
    }

    @Test("SHP-049 escape pod costs 2000 and needs confirmation")
    func escapePod() {
        var e = makeEngine { s in s.galaxy.systems[s.commander.currentSystem].techLevel = .industrial; s.commander.cash = 3_000 }
        #expect(e.perform(.buyEscapePod).decision != nil)
        _ = e.perform(.buyEscapePod, acknowledging: [.buyEscapePod])
        #expect(e.state.commander.ship.escapePod)
        #expect(e.state.commander.cash == 1_000)
    }

    @Test("SHP-051 SHP-053 fuel and repairs buy whole units capped by cash")
    func fuelAndRepairs() {
        var e = makeEngine { s in s.commander.ship.fuel = 4; s.commander.ship.hull = 60; s.commander.cash = 10_000 }
        // Gnat (Windows 2.01 columns): fuel cost 1, repair cost 2, 14 tanks, hull 100.
        _ = e.perform(.buyFuel(credits: 5))
        #expect(e.state.commander.ship.fuel == 9)
        _ = e.perform(.repairHull(credits: 15))
        #expect(e.state.commander.ship.hull == 67)
        #expect(e.state.commander.cash == 10_000 - 5 - 14)
        _ = e.perform(.buyFuel(credits: 1_000))
        #expect(e.state.commander.ship.fuel == 14)
        #expect(e.perform(.buyFuel(credits: 10)).rejection == .tankFull)
    }
}

@Suite("Bank (BNK)")
struct BankTests {
    @Test("BNK-011 max loan: clean record → min(25000, max(1000, worth/5000*500)); criminal → 500")
    func maxLoan() {
        let e = makeEngine()
        #expect(e.state.maxLoan == min(25_000, max(1_000, e.state.worth / 5_000 * 500)))
        let c = makeEngine { s in s.commander.policeRecordScore = -1 }
        #expect(c.state.maxLoan == 500)
    }

    @Test("BNK-015 BNK-016 borrowing limits")
    func borrow() {
        var e = makeEngine()
        let max = e.state.maxLoan
        #expect(e.perform(.borrow(0)).rejection == .invalidAmount)
        #expect(e.perform(.borrow(max + 1)).rejection == .exceedsAvailableLoan)
        _ = e.perform(.borrow(max))
        #expect(e.state.commander.debt == max)
        #expect(e.perform(.borrow(1)).rejection == .debtTooLargeForLoan)
    }

    @Test("BNK-017 BNK-018 repaying uses cash, at most min(debt, cash)")
    func repay() {
        var e = makeEngine()
        #expect(e.perform(.repay(1)).rejection == .noDebt)
        e.state.commander.debt = 3_000
        e.state.commander.cash = 1_000
        #expect(e.perform(.repay(1_001)).rejection == .exceedsRepayable)
        _ = e.perform(.repay(1_000))
        #expect(e.state.commander.debt == 2_000)
        #expect(e.state.commander.cash == 0)
    }

    @Test("BNK-038 BNK-039 insurance needs a pod; stopping is two-phase")
    func insurance() {
        var e = makeEngine()
        #expect(e.perform(.buyInsurance).rejection == .insuranceRequiresEscapePod)
        e.state.commander.ship.escapePod = true
        _ = e.perform(.buyInsurance)
        #expect(e.state.commander.insurance)
        #expect(e.perform(.buyInsurance).rejection == .insuranceAlreadyActive)
        #expect(e.perform(.stopInsurance).decision == .confirm(Confirmation(.stopInsurance)))
        _ = e.perform(.stopInsurance, acknowledging: [.stopInsurance])
        #expect(!e.state.commander.insurance)
    }
}

@Suite("Crew (CRW)")
struct CrewTests {
    @Test("CRW-027 CRW-035 hiring takes the first empty slot; CRW-037 firing is two-phase")
    func hireFire() throws {
        // Find a seed whose start system has a mercenary for hire and give the ship 3 quarters.
        var found = false
        for seed in 1...60 where !found {
            var e = makeEngine(seed: UInt64(seed))
            guard let merc = e.state.mercenariesForHire.first(where: { e.state.dailyRate(of: $0) > 0 }) else { continue }
            found = true
            e.state.commander.ship.crew = [CrewID.commander, nil, nil]
            _ = e.perform(.hire(crewID: merc))
            #expect(e.state.commander.ship.crew[1] == merc)
            #expect(e.state.mercenaryCosts == e.state.mercenaries[merc].skills.reduce(0, +) * 3)
            #expect(e.perform(.fire(crewID: merc)).decision == .confirm(Confirmation(.fireMercenary, amounts: [merc])))
            _ = e.perform(.fire(crewID: merc), acknowledging: [.fireMercenary])
            #expect(!e.state.commander.ship.hasCrew(merc))
            #expect(e.state.mercenaries[merc].systemID != nil)
        }
        #expect(found)
    }
}
