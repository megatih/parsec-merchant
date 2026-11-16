// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import Testing
@testable import ParsecMerchant

@MainActor
@Suite("Shipyard and Outfitter")
struct ShipyardOutfitterTests {
    /// A docked Quick Start game at a Hi-Tech system with `cash`, edited further by `change`.
    private func session(cash: Int = 200_000, _ change: (inout GameState) -> Void = { _ in }) throws -> GameSession {
        let s = try TestSessions.playing()
        try TestSessions.edit(s) { st in
            st.galaxy.systems[st.commander.currentSystem].techLevel = .hiTech
            st.commander.cash = cash
            st.commander.debt = 0
            change(&st)
        }
        return s
    }

    private func state(_ s: GameSession) throws -> GameState { try #require(s.state) }

    // MARK: Ship list

    @Test("UI-SHELL-068 a card per ship for sale plus the current ship, with net price, blocker and identifiers")
    func shipCards() throws {
        let st = try state(session(cash: 1_000))
        let m = ShipyardModel.make(state: st)
        #expect(m.cards.map(\.type) == st.shipsForSale + [st.commander.ship.type])
        #expect(m.cards.filter(\.isYours).map(\.type) == [st.commander.ship.type])
        for card in m.cards where !card.isYours {
            let q = st.shipQuote(card.type)
            #expect(card.price == ShipPriceLabel(netPrice: q.netPrice))
            #expect(card.blocker == q.blocker)
            #expect(card.spec == st.ruleset.tables.ship(card.type))
            #expect(AXID.all.contains(AXID.Shipyard.ship(card.type)) && AXID.all.contains(AXID.Shipyard.buy(card.type)))
        }
        #expect(m.cards.contains { $0.blocker == .insufficientFunds })
        #expect(ShipPriceLabel(netPrice: -1_500) == .receive(1_500))
        #expect(ShipPriceLabel(netPrice: 2_000) == .pay(2_000))
        #expect(ShipStatField.fuelTanks.value(st.ruleset.tables.ship(.flea)) == 20)
    }

    @Test("UI-SHELL-039 Shipyard and Outfitter say so in place when nothing is for sale")
    func nothingForSale() throws {
        let s = try session { st in st.galaxy.systems[st.commander.currentSystem].techLevel = .preAgricultural }
        let st = try state(s)
        #expect(!ShipyardModel.make(state: st).hasShipsForSale)
        #expect(ShipyardModel.make(state: st).cards.count == 1)
        #expect(!OutfitterModel.make(state: st).hasEquipmentForSale)
        #expect(OutfitterModel.make(state: try state(session())).hasEquipmentForSale)
    }

    @Test("UI-SHELL-069 the Designer tab exists iff the ruleset has shipyards and the system has one; never in Palm")
    func designerTab() throws {
        let plain = try session { st in st.galaxy.systems[st.commander.currentSystem].shipyard = nil }
        #expect(!ShipyardModel.make(state: try state(plain)).designerAvailable)
        let yard = try session { st in st.galaxy.systems[st.commander.currentSystem].shipyard = .kuat }
        let m = ShipyardModel.make(state: try state(yard))
        #expect(m.designerAvailable && m.yard == .kuat)
        var palm = GameState(config: NewGameConfig(commanderName: "P", ruleset: .palm122, seed: 3))
        palm.galaxy.systems[palm.commander.currentSystem].shipyard = .kuat
        #expect(!ShipyardModel.make(state: palm).designerAvailable)
        #expect(AXID.all.contains(AXID.Shipyard.designer))
    }

    @Test("UI-SHELL-070 click selects, ⌘-click builds a comparison with deltas against the current ship, Esc clears")
    func compare() throws {
        let st = try state(session())
        let m = ShipyardModel.make(state: st)
        var sel = ShipSelection()
        sel.click(.flea, command: false)
        #expect(sel.selected == [.flea] && !sel.isComparing)
        sel.click(.wasp, command: true)
        sel.click(.firefly, command: true)
        #expect(sel.isComparing)
        let rows = ShipCompare.rows(m, selection: sel)
        let current = st.commander.ship.spec(st.ruleset)
        let bays = try #require(rows.first { $0.field == .cargoBays })
        #expect(bays.current == current.cargoBays)
        #expect(bays.cells.map(\.type) == m.cards.map(\.type).filter { [.flea, .wasp, .firefly].contains($0) })
        let wasp = try #require(bays.cells.first { $0.type == .wasp })
        #expect(wasp.delta == 35 - current.cargoBays)
        #expect(ShipCompare.deltaText(5) == "+5 ▲" && ShipCompare.deltaText(-3) == "−3 ▼" && ShipCompare.deltaText(0) == "±0")
        sel.click(.wasp, command: true)
        sel.click(.firefly, command: true)
        #expect(!sel.isComparing)
        sel.click(.wasp, command: true)
        sel.clear()
        #expect(sel.selected.isEmpty)
        sel.click(.gnat, command: true)
        sel.click(.wasp, command: true)
        sel.prune(to: [.wasp])
        #expect(sel.selected == [.wasp])
        #expect(AXID.all.contains(AXID.Shipyard.compare))
    }

    // MARK: Purchase review

    /// A Gnat with Morgan's laser and a fuel compactor: buying a Firefly offers two transfer candidates.
    private func twoCandidates(cash: Int) throws -> GameSession {
        try session(cash: cash) { st in
            st.commander.ship.weapons = [.morgansLaser]
            st.commander.ship.gadgets = [.fuelCompactor]
        }
    }

    @Test("UI-SHELL-071 the review lists prices, transfer candidates (default on, Can't afford past cash), lost items and the cost")
    func purchaseReview() throws {
        let s = try twoCandidates(cash: 200_000)
        let st = try state(s)
        let m = try #require(ShipPurchaseModel.make(request: .ship(.firefly), state: st))
        let q = st.shipQuote(.firefly)
        #expect(m.listPrice == st.ruleset.tables.ship(.firefly).price)
        #expect(m.tradeIn == st.shipWorth(forInsurance: false) && m.netPrice == q.netPrice)
        #expect(m.transfers.map(\.item) == [.morgansLaser, .fuelCompactor] && m.transfers.allSatisfy(\.accepted))
        #expect(m.finalCost == q.netPrice + q.candidates.reduce(0) { $0 + $1.price })
        #expect(m.blocker == nil && m.canBuy)
        let declined = try #require(ShipPurchaseModel.make(request: .ship(.firefly), state: st, declined: [.morgansLaser]))
        #expect(declined.accepted == [.fuelCompactor] && declined.finalCost == q.netPrice + q.candidates[1].price)
        // A Flea has no weapon or gadget slots: both items are lost.
        let flea = try #require(ShipPurchaseModel.make(request: .ship(.flea), state: st))
        #expect(flea.transfers.isEmpty && flea.lost == [.morgansLaser, .fuelCompactor])
        // Just enough for the ship and the first item: the second shows "Can't afford".
        let tight = try twoCandidates(cash: 0)
        let tq = try state(tight).shipQuote(.firefly)
        try TestSessions.edit(tight) { $0.commander.cash = tq.netPrice + tq.candidates[0].price }
        let t = try #require(ShipPurchaseModel.make(request: .ship(.firefly), state: try state(tight)))
        #expect(t.transfers.map(\.affordable) == [true, false] && t.accepted == [.morgansLaser])
        // Insurance ends without a pod transfer; blocked purchases carry the reason.
        let insured = try session { st in st.commander.ship.escapePod = true; st.commander.insurance = true }
        let keep = try #require(ShipPurchaseModel.make(request: .ship(.firefly), state: try state(insured)))
        #expect(keep.insurance == .kept && keep.transfers.map(\.item) == [.escapePod])
        let drop = try #require(ShipPurchaseModel.make(request: .ship(.firefly), state: try state(insured), declined: [.escapePod]))
        #expect(drop.insurance == .ends)
        let poor = try #require(ShipPurchaseModel.make(request: .ship(.wasp), state: try state(session(cash: 10))))
        #expect(poor.blocker == .insufficientFunds && !poor.canBuy)
        for item in TransferItem.allCases { #expect(AXID.all.contains(AXID.ShipPurchase.transfer(item))) }
        #expect(AXID.all.contains(AXID.ShipPurchase.buy) && AXID.all.contains(AXID.ShipPurchase.cancel))
    }

    @Test("UI-SHELL-072 the review is the .buyShip confirmation: Buy Ship sends the checked transfers acknowledging .buyShip")
    func purchaseFlow() throws {
        let s = try twoCandidates(cash: 200_000)
        s.send(.buyShip(.firefly, transfers: []))
        #expect(s.presentation == .sheet(.shipPurchase(.ship(.firefly))))
        let m = try #require(ShipPurchaseModel.make(request: .ship(.firefly), state: try state(s), declined: [.morgansLaser]))
        #expect(m.command == .buyShip(.firefly, transfers: [.fuelCompactor]))
        s.dismissPresentation()
        s.send(m.command, acknowledging: [.buyShip])
        let st = try state(s)
        #expect(s.presentation == nil)
        #expect(st.commander.ship.type == .firefly && st.commander.ship.gadgets == [.fuelCompactor] && st.commander.ship.weapons.isEmpty)
        #expect(s.feed.contains { if case .boughtShip(.firefly, _)? = $0.event { true } else { false } })
        // Unaffordable transfers end in the feed as events.
        let tight = try twoCandidates(cash: 0)
        let tq = try state(tight).shipQuote(.firefly)
        try TestSessions.edit(tight) { $0.commander.cash = tq.netPrice }
        let t = try #require(ShipPurchaseModel.make(request: .ship(.firefly), state: try state(tight)))
        tight.send(.buyShip(.firefly, transfers: [.morgansLaser, .fuelCompactor]), acknowledging: [.buyShip])
        #expect(t.accepted.isEmpty)
        #expect(tight.feed.contains { $0.event == .cannotAffordTransfer(.morgansLaser) })
        #expect(tight.feed.contains { $0.event == .cannotAffordAllTransfers })
    }

    @Test("UI-SHELL-073 escape pod strip: offered, blocked with its reason, bought through the ALR-081 confirmation")
    func escapePod() throws {
        let s = try session(cash: 5_000)
        let strip = EscapePodStrip.make(state: try state(s))
        #expect(strip.canBuy && !strip.installed && !strip.insured)
        s.send(.buyEscapePod)
        guard case let .confirmation(pending)? = s.presentation else { Issue.record("no confirmation"); return }
        #expect(pending.confirmation.warning == .buyEscapePod)
        s.confirm(pending)
        let after = EscapePodStrip.make(state: try state(s))
        #expect(after.installed && !after.canBuy)
        let poor = EscapePodStrip.make(state: try state(session(cash: 1_000)))
        #expect(poor.blocker == .insufficientFunds && !poor.canBuy)
        let low = try session(cash: 5_000) { st in st.galaxy.systems[st.commander.currentSystem].techLevel = .agricultural }
        #expect(EscapePodStrip.make(state: try state(low)).blocker == .escapePodNotAvailable)
        #expect(AXID.all.contains(AXID.Shipyard.escapePodBuy))
    }

    // MARK: Designer

    @Test("UI-SHELL-074 steppers pass through Designer.normalized; the units bar bands at 80/90/100%")
    func designerSteppers() throws {
        var d = DesignerDraft(yard: .kuat, design: Designer.minimumDesign(size: .huge, yard: .kuat))
        #expect(d.sizes == Designer.sizes(for: .kuat))
        let hull = d.value(.hull)
        #expect(!d.canDecrement(.hull) && d.canIncrement(.hull))
        d.increment(.hull)
        #expect(d.value(.hull) == hull + DesignerTables.perUnitHull[SystemSize.huge.rawValue] + 5)
        d.decrement(.hull)
        #expect(d.value(.hull) == hull)
        for _ in 0..<7 { d.increment(.weaponSlots) }
        #expect(d.value(.weaponSlots) == 5 && !d.canIncrement(.weaponSlots))
        #expect(!d.canDecrement(.crewQuarters))
        d.size = .medium
        #expect(d.design == Designer.normalized(d.design, yard: .kuat))
        // Fuel steps by one fuel unit (3 parsecs on a Tiny ship at Sienar).
        var tiny = DesignerDraft(yard: .sienar, design: Designer.minimumDesign(size: .tiny, yard: .sienar))
        let fuel = tiny.value(.fuelTanks)
        tiny.increment(.fuelTanks)
        #expect(tiny.value(.fuelTanks) == min(20, fuel + 3))
        #expect(UnitsLevel(percent: 79) == .normal && UnitsLevel(percent: 80) == .caution)
        #expect(UnitsLevel(percent: 90) == .warning && UnitsLevel(percent: 100) == .warning && UnitsLevel(percent: 101) == .over)
        let st = try state(session { st in st.galaxy.systems[st.commander.currentSystem].shipyard = .kuat })
        let q = try #require(st.designQuote(d.design))
        #expect(q.totalCost == q.adjustedPrice + q.adjustedPenalty + q.adjustedFee - q.tradeIn)
        for f in DesignerField.allCases {
            #expect(AXID.all.contains(AXID.ShipDesigner.increment(f)) && AXID.all.contains(AXID.ShipDesigner.value(f)))
        }
    }

    @Test("UI-SHELL-075 Construct needs DesignQuote.canBuild and builds through the review with acknowledging .buyShip")
    func construct() throws {
        let s = try session(cash: 500_000) { st in st.galaxy.systems[st.commander.currentSystem].shipyard = .kuat }
        var d = DesignerDraft(yard: .kuat, design: Designer.minimumDesign(size: .huge, yard: .kuat))
        let unnamed = try #require(try state(s).designQuote(d.design))
        #expect(!unnamed.canBuild && unnamed.blocker == .designNameEmpty)
        d.name = "Kuat One"
        for _ in 0..<5 { d.increment(.weaponSlots); d.increment(.shieldSlots) }
        for _ in 0..<200 { d.increment(.cargoBays) }
        let over = try #require(try state(s).designQuote(d.design))
        #expect(over.percentOfMax > 100 && over.blocker == .designOverCapacity && !over.canBuild)
        d.apply(Designer.minimumDesign(size: .huge, yard: .kuat))
        #expect(d.name == "Kuat One")
        let ok = try #require(try state(s).designQuote(d.design))
        #expect(ok.canBuild)
        let m = try #require(ShipPurchaseModel.make(request: .design(ok.design), state: try state(s)))
        #expect(m.netPrice == ok.totalCost && m.command == .buildDesign(ok.design, transfers: []))
        s.send(m.command, acknowledging: [.buyShip])
        let st = try state(s)
        #expect(st.commander.ship.type == .custom && st.commander.shipName == "Kuat One")
        #expect(s.feed.contains { $0.event == .customShipBuilt(shipyard: .kuat) })
        // Trade-ship blockers show once the design passes its own checks.
        let poor = try session(cash: 0) { st in st.galaxy.systems[st.commander.currentSystem].shipyard = .kuat }
        #expect(try state(poor).designQuote(d.design)?.blocker == .insufficientFunds)
    }

    @Test("UI-SHELL-076 templates: current ship, minimum sizes, stock types and saved designs of available sizes; JSON store")
    func templates() throws {
        let st = try state(session())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pm-designs-\(UUID().uuidString)")
        let store = DesignTemplateStore(root: root)
        var saved = Designer.minimumDesign(size: .huge, yard: .kuat)
        saved.name = "Big/Hauler"
        let url = try store.save(saved)
        #expect(url.lastPathComponent == "Big_Hauler.json" && url.deletingLastPathComponent().lastPathComponent == "Designs")
        let text = try #require(String(data: Data(contentsOf: url), encoding: .utf8))
        let keys = text.split(separator: "\n").compactMap { $0.split(separator: "\"").dropFirst().first.map(String.init) }
        #expect(keys.count == 9 && keys == keys.sorted())
        var tiny = Designer.minimumDesign(size: .tiny, yard: .sienar)
        tiny.name = "Speck"
        try store.save(tiny)
        try Data("not json".utf8).write(to: store.directory.appendingPathComponent("broken.json"))
        let loaded = store.load()
        #expect(Set(loaded.map(\.name)) == ["Big/Hauler", "Speck"])
        let list = DesignTemplates.list(state: st, yard: .kuat, saved: loaded)
        let sizes = Designer.sizes(for: .kuat)
        #expect(list.first?.kind == .currentShip)
        #expect(list.filter { if case .minimum = $0.kind { true } else { false } }.count == sizes.count)
        let stock = list.compactMap { if case let .stock(t) = $0.kind { t } else { nil } }
        #expect(stock == ShipType.buyable.filter { sizes.contains(st.ruleset.tables.ship($0).size) })
        #expect(list.compactMap { if case let .saved(n) = $0.kind { n } else { nil } } == ["Big/Hauler"])
        #expect(DesignTemplateStore.fileName(for: "  ") == "Design.json")
        #expect(AXID.all.contains(AXID.ShipDesigner.template) && AXID.all.contains(AXID.ShipDesigner.saveTemplate))
    }

    // MARK: Outfitter

    @Test("UI-SHELL-077 three groups with slot tiles (free, no slots) and the items sold here; unique items only when installed")
    func outfitterGroups() throws {
        let s = try session { st in
            st.commander.ship = Ship(type: .firefly, spec: st.ruleset.tables.ship(.firefly))
            st.commander.ship.weapons = [.morgansLaser]
        }
        let st = try state(s)
        let m = OutfitterModel.make(state: st)
        #expect(m.groups.map(\.group) == [.weapons, .shields, .gadgets])
        let weapons = m.groups[0]
        #expect(weapons.tiles.count == 1 && weapons.tiles[0].installed?.item == .weapon(.morgansLaser))
        #expect(!weapons.offers.contains { $0.item == .weapon(.morgansLaser) })
        #expect(weapons.offers.map(\.item) == st.equipmentMarket.offers.filter { $0.buyPrice > 0 && $0.item.group == .weapons }.map(\.item))
        #expect(m.groups[1].tiles.count == 1 && m.groups[1].tiles[0].installed == nil)
        let flea = try session { st in st.commander.ship = Ship(type: .flea, spec: st.ruleset.tables.ship(.flea)) }
        #expect(OutfitterModel.make(state: try state(flea)).groups.allSatisfy { $0.tiles.isEmpty })
        for g in OutfitterGroup.allCases { #expect(AXID.all.contains(AXID.Outfitter.group(g))) }
    }

    @Test("UI-SHELL-078 detail pane prices and comparison; Buy and Sell send the commands behind ALR-080/ALR-090")
    func outfitterDetail() throws {
        let s = try session { st in
            st.commander.ship = Ship(type: .gnat, spec: st.ruleset.tables.ship(.gnat))
            st.commander.ship.weapons = [.pulseLaser]
        }
        var st = try state(s)
        let t = st.ruleset.tables
        let beam = EquipmentDetail.make(item: .weapon(.beamLaser), installedSlot: nil, state: st)
        #expect(beam.sellPrice == t.weapon(.beamLaser).price * 3 / 4)
        #expect(beam.buyPrice == st.equipmentBuyPrice(.weapon(.beamLaser)))
        #expect(beam.comparison == .power(best: .weapon(.pulseLaser), delta: t.weapon(.beamLaser).power - t.weapon(.pulseLaser).power))
        #expect(EquipmentDetail.make(item: .shield(.energy), installedSlot: nil, state: st).comparison == .nothingInstalled)
        #expect(EquipmentDetail.make(item: .gadget(.navigatingSystem), installedSlot: nil, state: st).comparison == .owned(count: 0))
        // Buy: the gnat's only weapon slot is full, so buying a gadget instead.
        let gadget = EquipmentItem.gadget(.navigatingSystem)
        #expect(st.equipmentBuyBlocker(.weapon(.beamLaser)) == .noFreeSlot)
        s.send(gadget.buyCommand)
        guard case let .confirmation(buy)? = s.presentation else { Issue.record("no buy confirmation"); return }
        #expect(buy.confirmation.warning == .buyEquipment)
        s.confirm(buy)
        st = try state(s)
        #expect(st.commander.ship.gadgets == [.navigatingSystem])
        let installed = try #require(st.equipmentMarket.installed.first { $0.item == .weapon(.pulseLaser) })
        #expect(installed.sellCommand == .sellWeapon(index: 0))
        s.send(installed.sellCommand)
        guard case let .confirmation(sell)? = s.presentation else { Issue.record("no sell confirmation"); return }
        #expect(sell.confirmation.warning == .sellEquipment)
        s.confirm(sell)
        #expect(try state(s).commander.ship.weapons.isEmpty)
        #expect(AXID.all.contains(AXID.Outfitter.buy(gadget)) && AXID.all.contains(AXID.Outfitter.sell(.weapons, slot: 0)))
        #expect(AXID.all.contains(AXID.Outfitter.detail))
    }

    @Test("UI-SHELL-128 the Shipyard, purchase, Designer and Outfitter identifiers are unique and match the scheme")
    func identifiers() {
        let ids = AXID.shipyardArea
        #expect(Set(ids).count == ids.count)
        #expect(ids.allSatisfy { $0.range(of: AXID.pattern, options: .regularExpression) != nil })
        #expect(Set(AXID.all).isSuperset(of: ids))
    }
}
