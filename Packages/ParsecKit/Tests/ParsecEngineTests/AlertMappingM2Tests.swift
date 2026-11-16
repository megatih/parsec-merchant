// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecEngine

/// Engine side of the {M2} alert mappings (ALR.md): each classic alert's trigger yields the mapped typed value.
@Suite("Alert mappings, engine side (ALR {M2})")
struct AlertMappingM2Tests {
    @Test("ALR-013 ALR-014 ALR-015 ALR-016 ALR-017 ALR-032 cargo alerts")
    func cargo() {
        var e = makeEngine { s in setMarket(&s); s.commander.cash = 10 }
        #expect(e.perform(.buyCargo(.water, quantity: 1)).rejection == .insufficientFunds)          // CargoIF
        e.state.commander.cash = 10_000
        e.state.commander.ship.cargo[1] = 15
        #expect(e.perform(.buyCargo(.water, quantity: 1)).rejection == .noEmptyBays)                // CargoNoEmptyBays
        e.state.commander.ship.cargo[1] = 0
        e.state.galaxy.systems[e.state.commander.currentSystem].tradeItems[0] = 0
        #expect(e.perform(.buyCargo(.water, quantity: 1)).rejection == .cargoNoneAvailable)         // CargoNoneAvailable
        #expect(e.perform(.sellCargo(.ore, quantity: 1)).rejection == .cargoNoneToSell)             // CargoNoneToSell
        e.state.commander.ship.cargo[3] = 1
        e.state.sellPrices[3] = 0
        #expect(e.perform(.sellCargo(.ore, quantity: 1)).rejection == .marketNotInterested)         // CargoNotInterested
        e.state.commander.debt = 100_001
        #expect(e.perform(.buyCargo(.food, quantity: 1)).rejection == .debtTooLargeToTrade)         // DebtTooLargeTrade
    }

    @Test("ALR-025 ALR-026 crew alerts")
    func crew() {
        var e = makeEngine { s in s.commander.ship.crew = [CrewID.commander, 5] }
        #expect(e.perform(.fire(crewID: 5)).decision == .confirm(Confirmation(.fireMercenary, amounts: [5])))  // CrewFireMercenary
        for seed in 1...60 {
            var f = makeEngine(seed: UInt64(seed))
            guard let m = f.state.mercenariesForHire.first(where: { f.state.dailyRate(of: $0) > 0 }) else { continue }
            #expect(f.perform(.hire(crewID: m)).rejection == .noFreeQuarters)                     // CrewNoQuarters
            return
        }
    }

    @Test("ALR-027 ALR-028 ALR-031 ALR-105 ALR-107 bank and debt alerts")
    func bank() {
        var e = makeEngine { s in s.commander.debt = 1; s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech; s.commander.cash = 90_000 }
        #expect(e.perform(.buyGadget(.navigatingSystem), acknowledging: [.buyEquipment]).rejection == .inDebt)  // DebtNoBuy
        e.state.commander.debt = 0
        #expect(e.perform(.repay(1)).rejection == .noDebt)                                          // DebtNone
        e.state.commander.debt = e.state.maxLoan
        #expect(e.perform(.borrow(1)).rejection == .debtTooLargeForLoan)                           // DebtTooLargeLoan
        #expect(e.perform(.buyInsurance).rejection == .insuranceRequiresEscapePod)                 // InsuranceNoEscapePod
        e.state.commander.insurance = true
        #expect(e.perform(.stopInsurance).decision == .confirm(Confirmation(.stopInsurance)))       // InsuranceStop
    }

    @Test("ALR-079 ALR-080 ALR-081 ALR-082 ALR-085 ALR-088 ALR-090 equipment alerts")
    func equipment() {
        var e = makeEngine { s in s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech; s.commander.cash = 200_000 }
        _ = e.perform(.buyGadget(.cloakingDevice), acknowledging: [.buyEquipment])
        e.state.commander.ship = Ship(type: .beetle, spec: e.ruleset.tables.ship(.beetle))
        e.state.commander.ship.crew[0] = CrewID.commander
        e.state.commander.ship.gadgets = [.cloakingDevice]
        #expect(e.perform(.buyGadget(.cloakingDevice)).rejection == .equipmentAlreadyOwned)        // EquipmentAlreadyOwn
        #expect(e.perform(.buyWeapon(.pulseLaser)).rejection == .noFreeSlot)                        // EquipmentNotEnoughSlots
        let shieldPrice = e.state.equipmentBuyPrice(shield: .energy)
        #expect(e.perform(.buyShield(.energy)).decision == .confirm(Confirmation(.buyEquipment, amounts: [shieldPrice])))  // EquipmentBuy
        #expect(e.perform(.sellGadget(index: 0)).decision == .confirm(Confirmation(.sellEquipment, amounts: [75_000])))      // EquipmentSell
        e.state.commander.cash = 1_000
        #expect(e.perform(.buyShield(.energy)).rejection == .insufficientFunds)                     // EquipmentIF
        e.state.commander.ship.gadgets = [.extraCargoBays]
        e.state.commander.ship.cargo[0] = 52
        #expect(e.perform(.sellGadget(index: 0), acknowledging: [.sellEquipment]).rejection == .extraBaysInUse)  // EquipmentExtraBaysInUse
        e.state.commander.cash = 5_000
        #expect(e.perform(.buyEscapePod).decision == .confirm(Confirmation(.buyEscapePod, amounts: [2_000])))   // EquipmentEscapePod
    }

    @Test("ALR-137 ALR-138 ALR-139 ALR-140 ALR-141 ALR-143 ALR-144 ALR-145 ALR-146 ship purchase alerts")
    func shipPurchase() {
        func engine(_ adjust: (inout GameState) -> Void) -> GameEngine {
            makeEngine { s in s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech; adjust(&s) }
        }
        var a = engine { $0.commander.cash = 0 }
        #expect(a.perform(.buyShip(.firefly, transfers: [])).rejection == .insufficientFunds)        // ShipBuyIF
        var b = engine { s in
            s.commander.cash = 100_000
            s.commander.ship = Ship(type: .beetle, spec: s.ruleset.tables.ship(.beetle))
            s.commander.ship.crew = [CrewID.commander, 5, 6]
        }
        #expect(b.perform(.buyShip(.firefly, transfers: [])).rejection == .notEnoughQuarters)         // ShipBuyCrewQuarters
        b.state.commander.ship.crew = [CrewID.commander, CrewID.wild, CrewID.jarek]
        #expect(b.perform(.buyShip(.firefly, transfers: [])).rejection == .passengersNeedQuarters)   // ShipBuyPassengerQuarters
        var c = engine { s in s.commander.cash = 100_000; s.quests.reactor = 3 }
        #expect(c.perform(.buyShip(.firefly, transfers: [])).rejection == .reactorOnBoard)            // ShipBuyReactor
        var d = engine { s in s.commander.cash = 100_000; s.commander.ship.weapons = [.morgansLaser] }
        let confirm = d.perform(.buyShip(.beetle, transfers: []))
        if case let .confirm(c)? = confirm.decision { #expect(c.warning == .buyShip) } else { Issue.record("no confirm") }  // ShipBuyConfirm
        let done = d.perform(.buyShip(.beetle, transfers: []), acknowledging: [.buyShip])
        #expect(done.events.contains(.cannotTransfer(.morgansLaser)))                                 // ShipBuyNoSlots
        var f = engine { s in s.commander.cash = 16_100; s.commander.ship.gadgets = [.fuelCompactor] }
        #expect(f.state.shipQuote(.firefly).candidates.map(\.item) == [.fuelCompactor])               // ShipBuyTransfer
        let r = f.perform(.buyShip(.firefly, transfers: [.fuelCompactor]), acknowledging: [.buyShip])
        #expect(r.events.contains(.cannotAffordAllTransfers))                                         // ShipBuyIFTransfer
        #expect(r.events.contains(.cannotAffordTransfer(.fuelCompactor)))                             // ShipBuyNoTransfer
    }

    @Test("ALR-148 building a custom design emits customShipBuilt")
    func designThanks() {
        var e = makeEngine { s in s.galaxy.systems[s.commander.currentSystem].shipyard = .kuat; s.commander.cash = 500_000 }
        let d = Designer.minimumDesign(size: .huge, yard: .kuat)
        var named = d
        named.name = "Kuat One"
        let r = e.perform(.buildDesign(named, transfers: []), acknowledging: [.buyShip])
        #expect(r.events.last == .customShipBuilt(shipyard: .kuat))
    }
}
