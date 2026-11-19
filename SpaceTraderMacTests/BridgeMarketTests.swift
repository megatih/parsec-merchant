// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import Foundation
import ParsecEngine
import SwiftUI
import Testing
@testable import ParsecMerchant

@MainActor
@Suite("Bridge and Market")
struct BridgeMarketTests {
    static let appRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("SpaceTraderMac")

    private func fresh(_ ruleset: RulesetID = .modern, seed: UInt64 = 1) -> GameState {
        GameState(config: NewGameConfig(commanderName: "Trader", ruleset: ruleset, seed: seed))
    }

    /// True when the engine accepts `command` (or asks to confirm it) on a copy of `state`.
    private func accepted(_ command: Command, in state: GameState) -> Bool {
        var engine = GameEngine(state: state)
        return engine.perform(command).rejection == nil
    }

    private func rejection(_ command: Command, in state: GameState) -> CommandError? {
        var engine = GameEngine(state: state)
        return engine.perform(command).rejection
    }

    /// The first system that is not the current one and not in range.
    private func outOfRange(_ s: GameState) throws -> Int {
        try #require(s.galaxy.systems.indices.first { $0 != s.commander.currentSystem && !s.destinationOK($0) })
    }

    // MARK: Bridge (§7)

    @Test("UI-SHELL-054 system card: name, size, tech, government, resource or Unknown, activity dots and pressure tag")
    func systemCard() throws {
        for ruleset in RulesetID.allCases {
            let s = fresh(ruleset)
            let cur = s.commander.currentSystem
            let m = SystemCardModel.make(state: s, system: cur)
            let sys = s.galaxy.systems[cur]
            #expect(m.name == Names.system(cur, in: s) && m.size == sys.size && m.techLevel == sys.techLevel)
            #expect(m.government == sys.politics && m.resource == sys.specialResource)
            #expect(m.police == s.ruleset.tables.politics(sys.politics).activityPolice)
            #expect(m.pirates == s.ruleset.tables.politics(sys.politics).activityPirates)
            #expect(m.pressure == (sys.pressure == .none ? nil : sys.pressure))
            let unvisited = try #require(s.galaxy.systems.indices.first { !s.galaxy.systems[$0].visited })
            #expect(SystemCardModel.make(state: s, system: unvisited).resource == nil)
        }
        #expect(String(localized: SystemText.resource(nil)) == "Unknown")
        #expect(Activity.allCases.allSatisfy { (0...7).contains(SystemCardModel.dots($0)) })
        #expect(SystemCardModel.dots(.swarms) == 7 && SystemCardModel.dots(.absent) == 0)
        #expect(SystemPressure.allCases.allSatisfy { ($0 == .none) == (SystemText.pressure($0) == nil) })
        #expect(String(localized: SystemText.pressure(.plague) ?? "") == "Plague")
        for t in TechLevel.allCases { #expect(!String(localized: SystemText.techLevel(t)).isEmpty) }
        for p in PoliticalSystemType.allCases { #expect(!String(localized: SystemText.government(p)).isEmpty) }
        for r in SpecialResource.allCases { #expect(!String(localized: SystemText.resource(r)).isEmpty) }
        for a in Activity.allCases { #expect(!String(localized: SystemText.activity(a)).isEmpty) }
        for p in SystemPressure.allCases { #expect(!String(localized: SystemText.pressureDescription(p)).isEmpty) }
        #expect(AXID.all.contains(BridgeID.system))
    }

    @Test("UI-SHELL-055 fuel: Fill Up sends the full-tank cost, partial range 1…min(cost, cash), Tank full, Not enough cash")
    func fuelService() throws {
        for ruleset in RulesetID.allCases {
            var s = fresh(ruleset)
            s.commander.ship.fuel = s.fuelCapacity
            let full = DockServiceModel.fuel(state: s)
            #expect(full.isComplete && full.blocker == .tankFull && full.amountRange == nil)
            #expect(rejection(full.fullCommand, in: s) == .tankFull)
            s.commander.ship.fuel = 0
            let m = DockServiceModel.fuel(state: s)
            #expect(m.blocker == nil && m.fullCommand == .buyFuel(credits: s.fullTankCost))
            #expect(m.amountRange == 1...min(s.fullTankCost, s.commander.cash))
            var engine = GameEngine(state: s)
            #expect(engine.perform(m.fullCommand).rejection == nil)
            #expect(engine.state.commander.ship.fuel == s.fuelCapacity || engine.state.commander.cash < m.unitCost)
            let partial = try #require(m.partialCommand(credits: m.unitCost * 2))
            #expect(partial == .buyFuel(credits: m.unitCost * 2) && accepted(partial, in: s))
            #expect(m.partialCommand(credits: 10_000_000) == .buyFuel(credits: m.amountRange?.upperBound ?? 0))
            s.commander.cash = m.unitCost - 1
            let broke = DockServiceModel.fuel(state: s)
            #expect(broke.blocker == .insufficientFunds && broke.amountRange == nil)
            #expect(ReasonText.string(for: .insufficientFunds) == "Not enough cash.")
            #expect(rejection(broke.fullCommand, in: s) != nil)
        }
        #expect([BridgeID.System.fillTank, AXID.Bridge.fuelAmount, AXID.Bridge.fuelBuy].allSatisfy(AXID.all.contains))
    }

    @Test("UI-SHELL-056 hull: Repair sends the full repair cost, a partial amount, No repairs needed at full hull")
    func repairService() throws {
        for ruleset in RulesetID.allCases {
            var s = fresh(ruleset)
            let strength = s.commander.ship.hullStrength(s.ruleset)
            s.commander.ship.hull = strength
            #expect(DockServiceModel.hull(state: s).blocker == .noRepairsNeeded)
            #expect(DockServiceModel.hull(state: s).percent == 100)
            s.commander.ship.hull = strength / 2
            let m = DockServiceModel.hull(state: s)
            #expect(m.blocker == nil && m.fullCommand == .repairHull(credits: s.fullRepairCost))
            #expect(m.percent == (strength / 2) * 100 / strength)
            var engine = GameEngine(state: s)
            #expect(engine.perform(m.fullCommand).rejection == nil)
            #expect(engine.state.commander.ship.hull > strength / 2)
            let partial = try #require(m.partialCommand(credits: m.unitCost))
            #expect(accepted(partial, in: s))
        }
        #expect([BridgeID.System.repairHull, AXID.Bridge.repairAmount, AXID.Bridge.repairBuy].allSatisfy(AXID.all.contains))
    }

    /// A state offering `event` at the current system, if the event is shown there.
    private func offering(_ event: SpecialEventType, in base: GameState) -> GameState {
        var s = base
        s.galaxy.systems[s.commander.currentSystem].specialEvent = event
        return s
    }

    @Test("UI-SHELL-057 special-event card: title, story, price, Accept/Decline or Continue; Decline hides it for this visit")
    func specialEventCard() throws {
        let base = fresh()
        #expect(SpecialEventCardModel.make(state: base) == nil || base.specialEventAvailable != nil)
        let candidates = SpecialEventType.allCases.map { offering($0, in: base) }.filter { $0.specialEventAvailable != nil }
        #expect(!candidates.isEmpty)
        for s in candidates {
            let m = try #require(SpecialEventCardModel.make(state: s))
            let spec = try #require(s.specialEventSpec(m.type))
            #expect(m.price == spec.price && m.messageOnly == spec.messageOnly && m.command == .specialEvent)
            let token = SpecialEventCardModel.visitToken(gameID: "g", state: s)
            #expect(SpecialEventCardModel.visible(state: s, gameID: "g", declinedToken: "") != nil)
            #expect(SpecialEventCardModel.visible(state: s, gameID: "g", declinedToken: token) == nil)
            var later = s
            later.commander.days += 1
            #expect(SpecialEventCardModel.visible(state: later, gameID: "g", declinedToken: token) != nil)
        }
        #expect(candidates.contains { SpecialEventCardModel.make(state: $0)?.messageOnly == true })
        #expect(candidates.contains { SpecialEventCardModel.make(state: $0)?.messageOnly == false })
        for t in SpecialEventType.allCases {
            #expect(String(localized: SpecialEventText.story(t)).count > 40, "\(t)")
        }
        #expect(String(localized: SpecialEventText.story(.lottery)).hasPrefix("You are lucky!"))
        // Accept goes through the engine (a confirmation for priced offers, UI-SHELL-004).
        let session = try TestSessions.playing()
        let offer = try #require(candidates.first { SpecialEventCardModel.make(state: $0)?.messageOnly == false })
        try TestSessions.edit(session) { $0 = offer }
        session.send(.specialEvent)
        #expect(session.lastRejection == nil)
        #expect([BridgeID.System.special].allSatisfy(AXID.all.contains))
    }

    @Test("UI-SHELL-058 mercenary card: the name for one, the count for several, a button to Crew")
    func mercenaryCard() throws {
        var s = fresh()
        for i in s.mercenaries.indices where s.mercenaries[i].systemID == s.commander.currentSystem {
            s.mercenaries[i].systemID = nil
        }
        #expect(MercenaryCardModel.make(state: s) == nil)
        s.mercenaries[1].systemID = s.commander.currentSystem
        let one = try #require(MercenaryCardModel.make(state: s))
        #expect(one.singleName == Names.crew(1, in: s))
        s.mercenaries[2].systemID = s.commander.currentSystem
        let two = try #require(MercenaryCardModel.make(state: s))
        #expect(two.singleName == nil && String(localized: two.text) == "2 mercenaries for hire")
        let session = try TestSessions.playing()
        session.selectedSection = .crew
        #expect(session.selectedSection == .crew && AXID.all.contains(BridgeID.System.hire))
    }

    @Test("UI-SHELL-059 target card: facts, parsecs, fuel after, costs, Warp as MENU-030, ‹ ›, Track/Untrack, wormhole")
    func targetCard() throws {
        for ruleset in RulesetID.allCases {
            var s = fresh(ruleset)
            #expect(TargetCardModel.make(state: s, isModal: false) == nil)
            let dest = try #require(s.destinations.first)
            s.warpSystem = dest
            let m = try #require(TargetCardModel.make(state: s, isModal: false))
            let p = s.warpTargetPreview(dest)
            #expect(m.system == SystemCardModel.make(state: s, system: dest) && m.preview == p && m.canCycle)
            #expect(m.preview.fuelAfter == p.fuelAfter && m.preview.costs == s.dailyCosts(to: dest))
            #expect(m.warp.isEnabled == accepted(.warp, in: s))
            #expect(TargetCardModel.make(state: s, isModal: true)?.warp.isEnabled == false)
            #expect(!m.showsTrack)
            let far = try outOfRange(s)
            s.warpSystem = far
            let o = try #require(TargetCardModel.make(state: s, isModal: false))
            #expect(!o.preview.inRange && o.showsTrack && !o.warp.isEnabled && o.trackCommand == .track(far))
            #expect(!accepted(.warp, in: s))
            var engine = GameEngine(state: s)
            engine.perform(o.trackCommand)
            let tracked = try #require(TargetCardModel.make(state: engine.state, isModal: false))
            #expect(tracked.isTracked && tracked.trackCommand == .track(nil))
            // ‹ › select the next system in range.
            var cycle = GameEngine(state: fresh(ruleset))
            cycle.perform(.selectNextTarget(forward: true))
            #expect(cycle.state.warpSystem != cycle.state.commander.currentSystem)
        }
        // The wormhole target shows "Wormhole to X".
        let base = fresh()
        let start = try #require(base.galaxy.wormholes.first)
        var w = base
        w.commander.currentSystem = start
        let to = try #require(w.galaxy.wormholeDestination(from: start))
        w.warpSystem = to
        #expect(TargetCardModel.make(state: w, isModal: false)?.viaWormhole == true)
        #expect([BridgeID.Target.warp, BridgeID.Target.previous, BridgeID.Target.next, BridgeID.Target.track]
            .allSatisfy(AXID.all.contains))
    }

    @Test("UI-SHELL-060 Use Singularity: shown with canSuperWarp, enabled iff jumpPreview.available, warns about blocking")
    func singularity() throws {
        var s = fresh()
        #expect(TargetCardModel.make(state: s, isModal: false)?.jump == nil)
        s.quests.canSuperWarp = true
        let atHome = try #require(TargetCardModel.make(state: s, isModal: false)?.jump)
        #expect(!atHome.enabled && atHome.rejection == .singularityTargetIsCurrentSystem)
        s.warpSystem = try outOfRange(s)
        let j = try #require(TargetCardModel.make(state: s, isModal: false)?.jump)
        #expect(j.enabled == s.jumpPreview.available && j.enabled && j.destination == s.warpSystem && j.blocking == nil)
        s.commander.debt = 200_000
        let blocked = try #require(TargetCardModel.make(state: s, isModal: false)?.jump)
        #expect(blocked.enabled && blocked.blocking == .debtTooLargeToTravel)
        // Palm jumps to the tracked system.
        var palm = fresh(.palm122)
        palm.quests.canSuperWarp = true
        let far = try outOfRange(palm)
        palm.trackedSystem = far
        #expect(TargetCardModel.make(state: palm, isModal: false)?.jump?.destination == far)
        #expect(AXID.all.contains(AXID.Bridge.targetJump))
    }

    @Test("UI-SHELL-103 the galaxy code on Bridge with a Copy button that writes it to the pasteboard")
    func galaxyCode() throws {
        let s = fresh(.windows201, seed: 3_735_928_559)
        #expect(GalaxyCodeCard.code(state: s) == GalaxyCode(ruleset: .windows201, difficulty: s.difficulty, seed: 3_735_928_559).string)
        let board = NSPasteboard(name: NSPasteboard.Name("pm-tests-\(UUID().uuidString)"))
        #expect(GalaxyCodeCard.copy(GalaxyCodeCard.code(state: s), to: board))
        #expect(board.string(forType: .string) == GalaxyCodeCard.code(state: s))
        board.releaseGlobally()
    }

    @Test("UI-SHELL-041 target picker: destinations by distance then name, the wormhole entry, selectTarget")
    func targetPicker() throws {
        for ruleset in RulesetID.allCases {
            let s = fresh(ruleset)
            let entries = TargetPickerModel.entries(state: s)
            #expect(Set(entries.map(\.index)) == Set(s.destinations) && entries.count == s.destinations.count)
            for (a, b) in zip(entries, entries.dropFirst()) {
                #expect(a.distance < b.distance || (a.distance == b.distance && a.name <= b.name))
            }
            #expect(entries.allSatisfy { $0.distance == s.warpTargetPreview($0.index).distance })
            if let first = entries.first {
                var engine = GameEngine(state: s)
                engine.perform(.selectTarget(first.index))
                #expect(engine.state.warpSystem == first.index)
            }
        }
        var w = fresh()
        let start = try #require(w.galaxy.wormholes.first)
        w.commander.currentSystem = start
        let entry = try #require(TargetPickerModel.wormhole(state: w))
        #expect(entry.destination == w.galaxy.wormholeDestination(from: start) && entry.command == .selectWormhole(start))
        var none = fresh()
        none.commander.currentSystem = try #require(none.galaxy.systems.indices.first { !none.galaxy.wormholes.contains($0) })
        #expect(TargetPickerModel.wormhole(state: none) == nil)
    }

    // MARK: Market (§8)

    @Test("UI-SHELL-061 trade table rows: item, illegal badge, buy/sell or —, dump fee, stock, held with cost, P/L, target")
    func marketRows() throws {
        var s = fresh()
        let rows = MarketRowModel.rows(state: s)
        #expect(rows.map(\.item) == TradeItemType.allCases && rows.map(\.row) == s.marketRows)
        #expect(rows.filter(\.isIllegal).map(\.item) == [.firearms, .narcotics])
        for r in rows {
            #expect((r.buyPrice == nil) == (r.row.buyPrice <= 0) && (r.sellPrice == nil) == (r.row.sellPrice <= 0))
            #expect(r.profitPerUnit == nil && r.dumpCostShown == nil)
        }
        let item = try #require(rows.first { $0.row.maxBuy > 0 && $0.sellPrice != nil }).item
        var engine = GameEngine(state: s)
        engine.perform(.buyCargo(item, quantity: 2))
        s = engine.state
        let held = try #require(MarketRowModel.rows(state: s).first { $0.item == item })
        #expect(held.row.held == 2 && held.row.costBasisPerUnit == s.buyPrices[item.rawValue])
        #expect(held.profitPerUnit == s.sellPrices[item.rawValue] - s.buyPrices[item.rawValue])
        // Held and unsellable: "Dump N cr.".
        var dumpState = s
        dumpState.sellPrices[item.rawValue] = 0
        let dumpRow = try #require(MarketRowModel.rows(state: dumpState).first { $0.item == item })
        #expect(dumpRow.isDumpMode && dumpRow.dumpCostShown == dumpState.dumpCostPerUnit && dumpRow.profitPerUnit == nil)
        // Target columns: only for an in-range target, from the known resource; Δ and % as C# (integer).
        #expect(rows.allSatisfy { $0.target == nil })
        var t = fresh()
        t.warpSystem = try #require(t.destinations.first)
        for r in MarketRowModel.rows(state: t) {
            guard let q = r.target else { continue }
            #expect(q.price > 0)
            if r.row.buyPrice > 0 {
                #expect(q.difference == q.price - r.row.buyPrice && q.percent == 100 * (q.price - r.row.buyPrice) / r.row.buyPrice)
            } else {
                #expect(q.difference == nil)
            }
        }
        t.warpSystem = try outOfRange(t)
        #expect(MarketRowModel.rows(state: t).allSatisfy { $0.target == nil })
        #expect(TradeItemType.allCases.allSatisfy { AXID.all.contains(BridgeID.Cargo.row($0)) })
    }

    @Test("UI-SHELL-064 UI-BRG-007 keys: B buys, S sells, ⇧B Max, ⇧S All on the selected row; ⌘/⌥/⌃ ignored")
    func marketKeys() throws {
        #expect(MarketKeyAction.make(characters: "b", modifiers: []) == .buy)
        #expect(MarketKeyAction.make(characters: "s", modifiers: []) == .sell)
        #expect(MarketKeyAction.make(characters: "B", modifiers: .shift) == .buyMax)
        #expect(MarketKeyAction.make(characters: "S", modifiers: .shift) == .sellAll)
        #expect(MarketKeyAction.make(characters: "b", modifiers: .command) == nil)
        #expect(MarketKeyAction.make(characters: "B", modifiers: [.shift, .command]) == nil)
        #expect(MarketKeyAction.make(characters: "s", modifiers: .option) == nil)
        #expect(MarketKeyAction.make(characters: "x", modifiers: []) == nil)
        #expect(MarketKeyAction.make(characters: "b", modifiers: .control) == nil)
        let s = fresh()
        let r = try #require(MarketRowModel.rows(state: s).first { $0.row.maxBuy > 5 })
        #expect(MarketKeyAction.buy.command(for: r) == .buyCargo(r.item, quantity: 1))
        #expect(MarketKeyAction.buyMax.command(for: r) == r.buyMaxCommand)
        #expect(MarketKeyAction.sellAll.command(for: r) == nil)
        let panel = try String(contentsOf: Self.appRoot.appendingPathComponent("Views/Bridge/BridgeCargoPanel.swift"), encoding: .utf8)
        #expect(panel.contains("case .upArrow, .downArrow:") && panel.contains("MarketKeyAction.make(characters: press.characters"))
        #expect(panel.contains("if selected { Rectangle().fill(PMColor.accent).frame(width: 3 * scale) }"), "selection is a fill and an accent bar")
    }

    @Test("UI-SHELL-065 Dump when nobody buys the good: the quantity sheet's command, clamped to what the engine allows")
    func dump() throws {
        var s = fresh()
        s.commander.ship.cargo[TradeItemType.water.rawValue] = 3
        let docked = try #require(MarketRowModel.rows(state: s).first { $0.item == .water })
        #expect(CargoDisposal.jettison(docked) == nil && rejection(.jettisonCargo(.water, quantity: 1), in: s) == .notAllowedInPhase)
        #expect(CargoDisposal.dump(docked) == nil || docked.isDumpMode)
        var dumpState = s
        dumpState.sellPrices[TradeItemType.water.rawValue] = 0
        let dumpRow = try #require(MarketRowModel.rows(state: dumpState).first { $0.item == .water })
        let dump = try #require(CargoDisposal.dump(dumpRow))
        #expect(dump.maximum == dumpRow.row.maxSell && dump.command(quantity: 99) == .dumpCargo(.water, quantity: dump.maximum))
        #expect(dump.command(quantity: 0) == .dumpCargo(.water, quantity: 1))
        #expect(accepted(try #require(dump.command(quantity: 1)), in: dumpState))
        #expect(SheetKeys.surface(for: .cargoDisposal(dump)) == .dump)
        #expect([AXID.Market.disposalSheet, AXID.Market.disposalConfirm, AXID.Market.disposalCancel].allSatisfy(AXID.all.contains))
    }

    // MARK: Interim decision sheets (UI-SHELL-011)

    @Test("UI-SHELL-011 interim decision sheets: trade stepper and Trade/Decline, plunder rows, scoop, newspaper Close")
    func interimDecisionSheets() throws {
        let offerJSON = #"{"direction":"traderSells","item":3,"unitPrice":40,"maxQuantity":6,"unitsAvailable":9,"costBasisPerUnit":0}"#
        let offer = try JSONDecoder().decode(OrbitTradeOffer.self, from: Data(offerJSON.utf8))
        let trade = TradeOfferModel(offer: offer, cash: 1_000)
        #expect(trade.range == 0...6 && trade.initialQuantity == 6 && !trade.canAccept(0) && trade.canAccept(6) && !trade.canAccept(7))
        #expect(trade.acceptCommand(4) == .resolveTradeInOrbit(quantity: 4) && trade.acceptCommand(50) == .resolveTradeInOrbit(quantity: 6))
        #expect(TradeOfferModel.declineCommand == .resolveTradeInOrbit(quantity: 0))
        let plunderSession = try TestSessions.playing()
        var plunderState = try #require(plunderSession.state)
        plunderState.commander.ship.cargo = Array(repeating: 0, count: TradeItemType.allCases.count)
        let plunder = PlunderSheetModel.make(context: PlunderSheetContext(victimCargo: [0, 3, 0, 0, 0, 0, 0, 0, 0, 7], source: .opponent),
                                             state: plunderState)
        #expect(plunder.rows.map(\.item) == [.furs, .robots] && plunder.rows.map(\.available) == [3, 7])
        #expect(plunder.rows[0].takeAllCommand == .plunderTake(.furs, quantity: 3))
        #expect(plunder.rows[0].takeCommand(9) == .plunderTake(.furs, quantity: 3))
        #expect(PlunderSheetModel.doneCommand == .plunderDone)

        // The newspaper: Read → buyNewspaper confirmation → the newspaper sheet → Close.
        let session = try TestSessions.playing()
        session.send(NewspaperCardModel.make(state: try #require(session.state)).command)
        guard case let .confirmation(pending) = session.presentation else {
            Issue.record("reading the paper asks to pay first")
            return
        }
        #expect(pending.confirmation.warning == .buyNewspaper)
        session.confirm(pending)
        guard case let .sheet(.newspaper(paper)) = session.presentation else {
            Issue.record("the paper opens the newspaper sheet")
            return
        }
        let state = try #require(session.state)
        #expect(NewspaperCardModel.make(state: state).paid)
        #expect(NewspaperText.shownHeadlines(state: state).count == paper.headlines.count)
        session.dismissPresentation()
        #expect(session.presentation == nil)

        // A trader's offer in orbit is answered through the sheet's commands and resolves the decision.
        var traded = false
        for seed in UInt64(1)...150 where !traded {
            let s = try TestSessions.playing(seed: seed)
            s.send(.selectNextTarget(forward: true))
            s.send(.warp)
            guard let engine = s.engine, let preview = engine.encounterPreview,
                  preview.actions.contains(where: { $0.action == .trade && $0.enabled }) else { continue }
            s.send(.encounter(.trade))
            guard case let .sheet(.tradeInOrbit(o)) = s.presentation else { continue }
            #expect(TradeOfferModel.make(offer: o, state: try #require(s.state)).offer == o)
            s.dismissPresentation()
            s.send(TradeOfferModel.declineCommand)
            #expect(s.lastRejection == nil && s.state?.pendingOrbitTrade == nil)
            traded = true
        }
        #expect(traded)
        #expect(AXID.Decision.all.contains(AXID.Decision.tradeQuantity) && AXID.Decision.all.contains(AXID.Decision.newspaperClose))
        #expect(TradeItemType.allCases.allSatisfy { AXID.Decision.all.contains(AXID.Decision.plunderTake($0)) })
    }
}
