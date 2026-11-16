// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecEngine

@Suite("Ships & equipment details (SHP)")
struct ShipDetailTests {
    @Test("SHP-001 SHP-055 Windows ship table incl. C# fuel/repair cost columns")
    func shipTable() {
        let t = Ruleset.windows201.tables.ships
        #expect(t.count == 17)
        #expect(t.map(\.fuelCost) == [1, 1, 1, 1, 1, 1, 2, 3, 4, 5, 1, 1, 1, 1, 1, 0, 1])
        #expect(t.map(\.repairCost) == [1, 2, 3, 5, 7, 10, 15, 15, 20, 20, 1, 1, 1, 1, 1, 0, 1])
        #expect(t[9] == ShipSpec(.wasp, .huge, bays: 35, weapons: 3, shields: 2, gadgets: 2, crew: 3, fuel: 14, fuelCost: 5,
                                 hull: 200, repairCost: 20, price: 300_000, occurrence: 2, police: .many, pirates: .abundant,
                                 traders: .moderate, tech: .hiTech))
    }

    @Test("SHP-004 SHP-033 only Flea…Wasp are buyable; offered by tech and not the current type")
    func buyable() {
        #expect(ShipType.buyable.count == 10 && ShipType.buyable.last == .wasp)
        let hi = makeEngine { s in s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech }.state
        #expect(hi.shipsForSale == ShipType.buyable.filter { $0 != .gnat })
        let pre = makeEngine { s in s.galaxy.systems[s.commander.currentSystem].techLevel = .renaissance }.state
        #expect(pre.shipsForSale.isEmpty)
        let ei = makeEngine { s in s.galaxy.systems[s.commander.currentSystem].techLevel = .earlyIndustrial }.state
        #expect(ei.shipsForSale == [.flea])
    }

    @Test("SHP-005 SHP-007 equipment tables and the for-sale list")
    func equipmentTables() {
        let t = Ruleset.windows201.tables
        #expect(t.weapons.map(\.power) == [15, 25, 35, 85, 20, 60] && t.weapons.map(\.price) == [2_000, 12_500, 35_000, 50_000, 15_000, 50_000])
        #expect(t.shields.map(\.power) == [100, 200, 350])
        #expect(t.gadgets.map(\.price) == [2_500, 7_500, 15_000, 25_000, 100_000, 30_000, 60_000])
        let forSaleW = WeaponType.allCases.filter { t.weapon($0).minTechLevel != .unavailable }
        let forSaleS = ShieldType.allCases.filter { t.shield($0).minTechLevel != .unavailable }
        let forSaleG = GadgetType.allCases.filter { t.gadget($0).minTechLevel != .unavailable }
        #expect(forSaleW == [.pulseLaser, .beamLaser, .militaryLaser, .photonDisruptor])
        #expect(forSaleS == [.energy, .reflective])
        #expect(forSaleG == [.extraCargoBays, .autoRepairSystem, .navigatingSystem, .targetingSystem, .cloakingDevice])
    }

    @Test("SHP-009 skill gadgets add +3 (cloak boosts Pilot)")
    func gadgetSkills() {
        var s = makeEngine().state
        let base = s.shipSkills
        s.commander.ship.gadgets = [.navigatingSystem, .cloakingDevice]
        #expect(s.shipSkills[SkillType.pilot.rawValue] == base[SkillType.pilot.rawValue] + 6)
        s.commander.ship.gadgets = [.autoRepairSystem]
        #expect(s.shipSkills[SkillType.engineer.rawValue] == base[SkillType.engineer.rawValue] + 3)
    }

    @Test("SHP-013 transfer price = sell price × 110/90")
    func transferPrices() {
        let s = makeEngine().state
        #expect(s.transferPrice(.morgansLaser) == 37_500 * 110 / 90)
        #expect(s.transferPrice(.lightningShield) == 33_750 * 110 / 90)
        #expect(s.transferPrice(.hiddenCargoBays) == 45_000 * 110 / 90)
        #expect(s.transferPrice(.escapePod) == 200)
    }

    @Test("SHP-014 SHP-022 slots fill in order; removal shifts; weapons may repeat")
    func slots() {
        var e = makeEngine { s in
            s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech
            s.commander.cash = 500_000
            s.commander.ship = Ship(type: .wasp, spec: s.ruleset.tables.ship(.wasp))
            s.commander.ship.crew[0] = CrewID.commander
        }
        for w in [WeaponType.pulseLaser, .beamLaser, .pulseLaser] { _ = e.perform(.buyWeapon(w), acknowledging: [.buyEquipment]) }
        #expect(e.state.commander.ship.weapons == [.pulseLaser, .beamLaser, .pulseLaser])
        #expect(e.perform(.buyWeapon(.pulseLaser), acknowledging: [.buyEquipment]).rejection == .noFreeSlot)
        _ = e.perform(.sellWeapon(index: 0), acknowledging: [.sellEquipment])
        #expect(e.state.commander.ship.weapons == [.beamLaser, .pulseLaser])
        _ = e.perform(.buyGadget(.extraCargoBays), acknowledging: [.buyEquipment])
        _ = e.perform(.buyGadget(.extraCargoBays), acknowledging: [.buyEquipment])
        #expect(e.state.commander.ship.gadgets == [.extraCargoBays, .extraCargoBays])
    }

    @Test("SHP-015 SHP-061 SHP-062 cargo bays include extra/hidden bays and quest cargo")
    func bays() {
        var s = makeEngine().state
        s.commander.ship.gadgets = [.extraCargoBays, .hiddenCargoBays]
        #expect(s.commander.ship.cargoBays(s.ruleset) == 25)
        s.quests.japori = QuestStatus.Japori.inTransit
        #expect(s.filledCargoBays == 10)
        s.quests.reactor = 5
        #expect(s.filledCargoBays == 10 + 5 + 10 - 2)
        #expect(s.ruleset.tables.gadget(.extraCargoBays).price == 2_500 && s.ruleset.tables.gadget(.extraCargoBays).minTechLevel == .earlyIndustrial)
        #expect(s.ruleset.tables.gadget(.hiddenCargoBays).minTechLevel == .unavailable)
    }

    @Test("SHP-016 SHP-060 SHP-018 SHP-059 compactor +3 tanks; hull upgrade +50 lost on trade")
    func compactorAndHull() {
        var e = makeEngine { s in
            s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech
            s.commander.cash = 100_000
            s.commander.ship.gadgets = [.fuelCompactor]
            s.commander.ship.hullUpgraded = true
            s.quests.scarab = QuestStatus.Scarab.done
        }
        #expect(e.state.fuelCapacity == 17 && e.state.commander.ship.hullStrength(e.ruleset) == 150)
        #expect(e.ruleset.tables.gadget(.fuelCompactor).minTechLevel == .unavailable)
        _ = e.perform(.buyShip(.firefly, transfers: [.fuelCompactor]), acknowledging: [.buyShip])
        #expect(e.state.commander.ship.has(.fuelCompactor) && !e.state.commander.ship.hullUpgraded)
        #expect(e.state.quests.scarab == QuestStatus.Scarab.notStarted)
    }

    @Test("SHP-023 bought shields are at full charge; cash decreases by the price")
    func buyShield() {
        var e = makeEngine { s in
            s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech
            s.commander.cash = 100_000
            s.commander.ship = Ship(type: .firefly, spec: s.ruleset.tables.ship(.firefly))
            s.commander.ship.crew[0] = CrewID.commander
        }
        let price = e.state.equipmentBuyPrice(shield: .energy)
        _ = e.perform(.buyShield(.energy), acknowledging: [.buyEquipment])
        #expect(e.state.commander.ship.shields == [ShieldInstance(type: .energy, charge: 100)])
        #expect(e.state.commander.cash == 100_000 - price)
    }

    @Test("SHP-027 SHP-028 SHP-031 base worth, worth with cargo basis, commander worth (11000 at start)")
    func worth() {
        var s = makeEngine().state
        #expect(s.worth == 11_000)
        #expect(s.baseWorth(of: s.commander.ship, forInsurance: false) == 7_500 + 1_500)
        s.commander.ship.hull = 90
        s.commander.ship.fuel = 10
        #expect(s.baseWorth(of: s.commander.ship, forInsurance: false) == 9_000 - 10 * 2 - 4 * 1)
        s.commander.priceCargo[0] = 500
        #expect(s.shipWorth(forInsurance: false) == 8_976 + 500)
        s.commander.ship.tribbles = 5
        #expect(s.baseWorth(of: s.commander.ship, forInsurance: false) == 2_500 - 24 + 1_500)
        #expect(s.baseWorth(of: s.commander.ship, forInsurance: true) == 8_976)
    }

    @Test("SHP-038 SHP-039 SHP-040 SHP-041 SHP-048 SHP-080 transfers: lost items, affordability, order, confirmation")
    func transfers() {
        var e = makeEngine { s in
            s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech
            s.commander.ship = Ship(type: .hornet, spec: s.ruleset.tables.ship(.hornet))
            s.commander.ship.crew[0] = CrewID.commander
            s.commander.ship.weapons = [.morgansLaser]
            s.commander.ship.shields = [ShieldInstance(type: .lightning, charge: 350)]
            s.commander.ship.escapePod = true
            s.commander.cash = 0
        }
        // Buying a Beetle (no weapon slot): Morgan's laser is lost; the trade-in pays more than the Beetle costs.
        let q = e.state.shipQuote(.beetle)
        #expect(q.lost == [.morgansLaser] && q.candidates.map(\.item) == [.lightningShield, .escapePod])
        let before = e.state
        let needsOK = e.perform(.buyShip(.beetle, transfers: [.lightningShield, .escapePod]))
        #expect(needsOK.decision != nil && e.state == before)
        let r = e.perform(.buyShip(.beetle, transfers: [.lightningShield, .escapePod]), acknowledging: [.buyShip])
        #expect(r.events.first == .cannotTransfer(.morgansLaser))
        #expect(e.state.commander.ship.type == .beetle && e.state.commander.ship.has(.lightning) && e.state.commander.ship.escapePod)
        // With little cash, an expensive transfer is auto-declined.
        var f = makeEngine { s in
            s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech
            s.commander.ship.gadgets = [.fuelCompactor]
            s.commander.cash = 16_100
        }
        let rf = f.perform(.buyShip(.firefly, transfers: [.fuelCompactor]), acknowledging: [.buyShip])
        #expect(rf.events.contains(.cannotAffordTransfer(.fuelCompactor)) && rf.events.contains(.cannotAffordAllTransfers))
        #expect(!f.state.commander.ship.has(.fuelCompactor))
    }

    @Test("SHP-052 SHP-054 SHP-081 fuel/repair availability and full costs")
    func fuelRepairPreview() {
        var s = makeEngine().state
        #expect(s.fullTankCost == 0 && s.fullRepairCost == 0)
        s.commander.ship.fuel = 10
        s.commander.ship.hull = 75
        #expect(s.fullTankCost == 4 && s.fullRepairCost == 25 * 2)
        #expect(100 * s.commander.ship.hull / s.commander.ship.hullStrength(s.ruleset) == 75)
    }

    @Test("SHP-057 auto-fuel/auto-repair options exist (owned by TRV, all-or-nothing applied in M3)")
    func autoOptions() {
        let o = GameOptions()
        #expect(!o.autoFuel && !o.autoRepair)
    }

    @Test("SHP-082 escape pod blockers")
    func podBlockers() {
        var low = makeEngine { s in s.galaxy.systems[s.commander.currentSystem].techLevel = .renaissance; s.commander.cash = 5_000 }
        #expect(low.perform(.buyEscapePod).rejection == .escapePodNotAvailable)
        var poor = makeEngine { s in s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech; s.commander.cash = 1_999 }
        #expect(poor.perform(.buyEscapePod).rejection == .insufficientFunds)
        var has = makeEngine { s in s.commander.ship.escapePod = true }
        #expect(has.perform(.buyEscapePod).rejection == .alreadyHaveEscapePod)
    }

    @Test("SHP-077 SHP-078 SHP-079 SHP-084 previews and two-phase equipment commands map to classic alerts")
    func previews() {
        var e = makeEngine { s in s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech; s.commander.cash = 50_000 }
        let before = e.state
        let price = e.state.equipmentBuyPrice(gadget: .targetingSystem)
        #expect(e.perform(.buyGadget(.targetingSystem)).decision == .confirm(Confirmation(.buyEquipment, amounts: [price])))
        #expect(e.state == before)
        #expect(e.perform(.sellWeapon(index: 0)).decision != nil && e.state == before)
        #expect(e.state.shipQuote(.firefly).netPrice == 16_000)
        e.state.commander.debt = 1
        #expect(e.perform(.buyShip(.firefly, transfers: []), acknowledging: [.buyShip]).rejection == .inDebt)
    }

    @Test("SHP-085 invariants after random service commands")
    func invariants() {
        var e = makeEngine(seed: 9) { s in s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech; s.commander.cash = 200_000 }
        var rng = Xoshiro256StarStar(seed: 2)
        let cmds: [Command] = [.buyFuel(credits: 3), .repairHull(credits: 5), .buyWeapon(.beamLaser), .buyShield(.energy),
                               .buyGadget(.extraCargoBays), .sellWeapon(index: 0), .sellGadget(index: 0), .buyShip(.firefly, transfers: []),
                               .buyShip(.mosquito, transfers: []), .buyEscapePod]
        for _ in 0..<300 {
            _ = e.perform(cmds[rng.next(below: cmds.count)], acknowledging: [.buyEquipment, .sellEquipment, .buyShip, .buyEscapePod])
            let s = e.state, sh = s.commander.ship, r = s.ruleset
            #expect(sh.hull >= 0 && sh.hull <= sh.hullStrength(r) && sh.fuel >= 0 && sh.fuel <= sh.fuelTanks(r))
            #expect(sh.weapons.count <= sh.spec(r).weaponSlots && sh.shields.count <= sh.spec(r).shieldSlots && sh.gadgets.count <= sh.spec(r).gadgetSlots)
            #expect(sh.crewCount <= sh.spec(r).crewQuarters && s.commander.cash >= 0)
        }
    }
}

@Suite("Custom ship designer (SHP §12)")
struct DesignerTests {
    @Test("SHP-063 SHP-064 SHP-065 designer only at shipyards; sizes within ±2 of the specialty")
    func availability() {
        var s = makeEngine().state
        s.galaxy.systems[s.commander.currentSystem].shipyard = nil
        #expect(s.designQuote(Designer.minimumDesign(size: .large, yard: .corellian)) == nil)
        s.galaxy.systems[s.commander.currentSystem].shipyard = .corellian
        #expect(s.designQuote(Designer.minimumDesign(size: .large, yard: .corellian)) != nil)
        #expect(Designer.sizes(for: .corellian) == [.small, .medium, .large, .huge, .gargantuan])
        #expect(Designer.sizes(for: .sienar) == [.tiny, .small, .medium])
        #expect(DesignerTables.maxUnits == [50, 100, 150, 200, 250, 999] && DesignerTables.pricePerUnit[3] == 750)
    }

    @Test("SHP-066 SHP-067 SHP-068 SHP-069 SHP-070 worked example A (Corellian Large)")
    func exampleA() {
        let d = ShipDesign(name: "A", size: .large, cargoBays: 30, fuelTanks: 12, hull: 100, weaponSlots: 2, shieldSlots: 2, gadgetSlots: 2, crewQuarters: 2)
        let q = Designer.quote(d, yard: .corellian, tradeIn: 9_000)
        #expect(q.unitsUsed == 112 && q.percentOfMax == 56 && q.penalty == 0)
        #expect(q.basePrice == 84_000 && q.adjustedPrice == 75_600 && q.adjustedFee == 18_000)
        #expect(q.totalCost == 93_600 - 9_000)
    }

    @Test("SHP-068 SHP-070 worked example B (Sienar Tiny, crowding penalty)")
    func exampleB() {
        let d = ShipDesign(name: "B", size: .tiny, cargoBays: 10, fuelTanks: 15, hull: 10, weaponSlots: 1, shieldSlots: 0, gadgetSlots: 1, crewQuarters: 1)
        let q = Designer.quote(d, yard: .sienar, tradeIn: 0)
        #expect(q.unitsUsed == 48 && q.percentOfMax == 96)
        #expect(q.basePrice == 3_600 && q.penalty == 2_700)
        #expect(q.adjustedPrice == 3_240 && q.adjustedPenalty == 2_430 && q.adjustedFee == 1_800 && q.totalCost == 7_470)
    }

    @Test("SHP-067 fuel units round up after double division (Tiny, fuel 20 → 2 units)")
    func fuelRounding() {
        let d = ShipDesign(name: "F", size: .tiny, cargoBays: 0, fuelTanks: 20, hull: 10, weaponSlots: 0, shieldSlots: 0, gadgetSlots: 0, crewQuarters: 1)
        let q = Designer.quote(d, yard: .incom, tradeIn: 0)
        #expect(q.unitsUsed == 20 + 2)
    }

    @Test("SHP-071 the built custom spec: price = base + penalty, designer fuel/repair costs")
    func customSpec() {
        let d = ShipDesign(name: "B", size: .tiny, cargoBays: 10, fuelTanks: 15, hull: 10, weaponSlots: 1, shieldSlots: 0, gadgetSlots: 1, crewQuarters: 1)
        let spec = Designer.quote(d, yard: .sienar, tradeIn: 0).spec
        #expect(spec.price == 6_300 && spec.fuelCost == 1 && spec.repairCost == 1 && spec.minTechLevel == .unavailable && spec.occurrence == 0)
    }

    @Test("SHP-072 SHP-073 inputs are clamped and snapped to whole units")
    func snapping() {
        let d = Designer.normalized(ShipDesign(name: "S", size: .tiny, cargoBays: 2_000, fuelTanks: 16, hull: 11, weaponSlots: 9,
                                               shieldSlots: -1, gadgetSlots: 3, crewQuarters: 0), yard: .incom)
        #expect(d.cargoBays == 999 && d.fuelTanks == 18 && d.hull == 45 && d.weaponSlots == 5 && d.shieldSlots == 0 && d.crewQuarters == 1)
    }

    @Test("SHP-074 buildability: name required; truncated percentage may exceed max units")
    func buildability() {
        let over = ShipDesign(name: "O", size: .medium, cargoBays: 151 - 20, fuelTanks: 13, hull: 50,
                              weaponSlots: 0, shieldSlots: 0, gadgetSlots: 0, crewQuarters: 1)
        let q = Designer.quote(over, yard: .incom, tradeIn: 0)
        #expect(q.unitsUsed == 151 && q.percentOfMax == 100 && q.canBuild)
        var unnamed = over
        unnamed.name = " "
        #expect(Designer.quote(unnamed, yard: .incom, tradeIn: 0).blocker == .designNameEmpty)
        var big = over
        big.cargoBays = 200
        #expect(Designer.quote(big, yard: .incom, tradeIn: 0).blocker == .designOverCapacity)
    }

    @Test("SHP-075 SHP-083 building runs TradeShip with the custom spec and names the ship")
    func build() {
        var e = makeEngine { s in
            s.galaxy.systems[s.commander.currentSystem].shipyard = .sienar
            s.commander.cash = 50_000
        }
        let d = ShipDesign(name: "Folly", size: .tiny, cargoBays: 10, fuelTanks: 15, hull: 10, weaponSlots: 1, shieldSlots: 0, gadgetSlots: 1, crewQuarters: 1)
        let quote = e.state.designQuote(d)
        #expect(quote?.totalCost == 7_470 - 9_000)
        let r = e.perform(.buildDesign(d, transfers: []), acknowledging: [.buyShip])
        #expect(r.rejection == nil)
        #expect(e.state.commander.ship.type == .custom && e.state.commander.ship.customSpec?.cargoBays == 10)
        #expect(e.state.commander.shipName == "Folly" && e.state.commander.cash == 50_000 + 1_530)
    }

    @Test("SHP-076 templates: minimum design per size")
    func templates() {
        let m = Designer.minimumDesign(size: .huge, yard: .kuat)
        #expect(m.fuelTanks == 11 && m.hull == 150 && m.crewQuarters == 1 && m.cargoBays == 0)
        #expect(Designer.minimumDesign(size: .small, yard: .sorosuub).fuelTanks == 16)
    }
}
