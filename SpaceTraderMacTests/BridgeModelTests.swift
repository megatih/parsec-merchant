// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import ParsecInsights
import ParsecPersistence
import SwiftUI
import Testing
@testable import ParsecMerchant

/// UI-BRG, UI-FAIR: the models and rules behind the Bridge (docs/PRD-UI-Revamp.md §4.2, §4.16).
@MainActor
@Suite("Bridge models (UI-BRG, UI-FAIR)")
struct BridgeModelTests {
    static let appRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("SpaceTraderMac")
    static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Packages/ParsecKit/Tests/Fixtures/saves/v1")

    static func cargo(_ state: GameState) -> BridgeCargoModel {
        let book = IntelBook(systems: Array(repeating: SystemIntel(), count: state.galaxy.systems.count))
        let snapshot = IntelSnapshot(state)
        let intel = MarketIntelModel.make(book: book, snapshot: snapshot, target: state.warpSystem,
                                          breakdowns: TradeItemType.allCases.map(state.priceBreakdown))
        return BridgeCargoModel.make(state: state, intel: intel, book: book)
    }

    static func accepted(_ command: Command, in state: GameState) -> Bool {
        var engine = GameEngine(state: state)
        return engine.perform(command).rejection == nil
    }

    @Test("UI-BRG-001 UI-BRG-009 ten rows in table order in every ruleset; the two contraband goods carry the Illegal mark")
    func rows() throws {
        for ruleset in RulesetID.allCases {
            let session = try BridgeFixtures.session(ruleset: ruleset, .newGame)
            let cargo = try #require(session.bridgeCargo)
            #expect(cargo.rows.map(\.item) == TradeItemType.allCases && cargo.rows.count == 10)
            #expect(cargo.rows.filter(\.market.isIllegal).map(\.item) == [.firearms, .narcotics])
            let state = try #require(session.state)
            #expect(cargo.usedBays == state.filledCargoBays && cargo.freeBays == state.marketFreeBays && cargo.cashToSpend == state.cashToSpend)
        }
        let panel = try String(contentsOf: Self.appRoot.appendingPathComponent("Views/Bridge/BridgeCargoPanel.swift"), encoding: .utf8)
        #expect(panel.contains("Label { Text(\"Illegal\") } icon: { Image(systemName: \"exclamationmark.triangle.fill\")"), "the symbol and the word")
    }

    @Test("UI-BRG-002 UI-BRG-003 Buy and Sell send the typed quantity; Max and All take theirs from the engine checks; blockers are the engine's")
    func commands() throws {
        for ruleset in RulesetID.allCases {
            var state = try #require(try BridgeFixtures.session(ruleset: ruleset, .newGame).state)
            state.commander.cash = 3_000
            state.commander.ship.cargo[TradeItemType.water.rawValue] = 2
            for row in Self.cargo(state).rows {
                let buyCheck = state.marketBuyCheck(row.item)
                if case let .failure(error) = buyCheck {
                    #expect(row.market.buyBlocker == error && row.buyCommand(text: "") == nil && row.maxCommand == nil)
                } else if case let .success(maximum) = buyCheck, maximum > 0 {
                    #expect(row.maxCommand == .buyCargo(row.item, quantity: maximum) && Self.accepted(.buyCargo(row.item, quantity: maximum), in: state))
                    #expect(row.buyCommand(text: "3") == .buyCargo(row.item, quantity: 3), "the quantity as typed")
                    #expect(row.buyCommand(text: "abc") == nil && row.buyCommand(text: "0") == nil)
                }
                if row.market.isDumpMode {
                    #expect(row.sellCommand(text: "1") == nil && row.allCommand == nil && row.allBlocker == .marketNotInterested)
                } else if case let .success(maximum) = state.marketSellCheck(row.item, dump: false), maximum > 0 {
                    #expect(row.allCommand == .sellCargo(row.item, quantity: maximum) && row.sellCommand(text: "") == .sellCargo(row.item, quantity: 1))
                } else {
                    #expect(row.sellBlocker != nil && row.sellCommand(text: "1") == nil && row.allCommand == nil)
                }
            }
        }
        // The engine's rejection of a typed quantity reaches the status bar's message slot (the session's last rejection).
        let session = try TestSessions.playing(seed: 11)
        let row = try #require(session.bridgeCargo?.rows.first { $0.market.buyBlocker == nil })
        session.send(try #require(row.buyCommand(text: "9999")))
        let bought = session.state?.commander.ship.cargo[row.item.rawValue] ?? 0
        #expect(session.lastRejection != nil || bought > 0, "the engine decides: it rejects or clamps, the view never does")
    }

    @Test("UI-BRG-004 Sell All Cargo: the same state as the sales sent one by one; disabled with a reason when nothing can be sold")
    func sellAll() throws {
        for ruleset in RulesetID.allCases {
            let session = try BridgeFixtures.session(ruleset: ruleset, .fullHold)
            let before = try #require(session.state)
            let plan = SellAllCargo.make(state: before)
            #expect(!plan.commands.isEmpty && plan.blocker == nil)
            var engine = GameEngine(state: before)
            for command in plan.commands { #expect(engine.perform(command).rejection == nil) }
            let sold = session.sellAllCargo()
            #expect(sold == plan.commands.count && session.state == engine.state, "\(ruleset)")
            #expect((session.state?.commander.cash ?? 0) - before.commander.cash == plan.proceeds)
            // Only goods without a sell price here stay aboard.
            let after = try #require(session.state)
            for row in after.marketRows where row.held > 0 { #expect(row.sellPrice <= 0, "\(row.item)") }
        }
        let empty = try #require(try TestSessions.playing(seed: 11).state)
        let none = SellAllCargo.make(state: empty)
        #expect(none.commands.isEmpty && none.blocker == .cargoNoneToSell && none.proceeds == 0)
        var debt = try #require(try BridgeFixtures.session(ruleset: .modern, .fullHold).state)
        debt.commander.debt = 1_000_000
        if case let .failure(error) = debt.marketSellCheck(.water, dump: false) { #expect(SellAllCargo.make(state: debt).blocker == error) }
    }

    @Test("UI-BRG-005 UI-BRG-006 every Target cell is TradeIntel's quote for the Target System, in each ruleset's saved game; no target, no number",
          arguments: ["modern", "windows201", "palm122"])
    func targetCells(ruleset: String) throws {
        let saved = try SaveCodec.decode(try Data(contentsOf: Self.fixtures.appendingPathComponent("\(ruleset).parsecsave")))
        var state = saved.state
        let book = IntelBook(systems: Array(repeating: SystemIntel(), count: state.galaxy.systems.count))
        for target in state.galaxy.systems.indices where target != state.commander.currentSystem && target % 7 == 0 {
            state.warpSystem = target
            let snapshot = IntelSnapshot(state)
            let cargo = Self.cargo(state)
            for row in cargo.rows {
                let quote = TradeIntel.quote(item: row.item, system: target, book: book, snapshot: snapshot)
                #expect(row.quote == quote && row.targetPrice == quote.sell, "\(ruleset) \(target) \(row.item)")
                if let price = quote.sell, let reference = row.reference {
                    let difference: Int = price - reference
                    let bold: Bool = difference > 0 && row.market.row.stock > 0
                    #expect(row.delta == difference)
                    #expect(row.deltaIsBold == bold)
                } else {
                    #expect(row.delta == nil && !row.deltaIsBold)
                }
                #expect(row.reference == (row.market.buyPrice ?? row.market.sellPrice))
            }
            #expect(cargo.holdAtTarget == TradeIntel.holdValue(at: target, book: book, snapshot: snapshot))
            let starred: Set<TradeItemType> = Set(cargo.rows.filter(\.bestBuy).map(\.item))
            let best: Set<TradeItemType> = Set(TradeIntel.bestBuys(for: target, book: book, snapshot: snapshot).map(\.item))
            #expect(starred == best)
        }
        state.warpSystem = state.commander.currentSystem
        let here = Self.cargo(state)
        #expect(here.rows.allSatisfy { $0.quote == nil && $0.targetPrice == nil && $0.delta == nil } && here.holdAtTarget == nil && here.targetName == nil)
        // A number from another system always carries its tag, and the header carries the original's disclaimer.
        let panel = try String(contentsOf: Self.appRoot.appendingPathComponent("Views/Bridge/BridgeCargoPanel.swift"), encoding: .utf8)
        #expect(panel.contains("Text(verbatim: IntelText.age(quote))") && panel.contains("Average price at the target. Estimates carry no guarantee"))
        let model = try String(contentsOf: Self.appRoot.appendingPathComponent("Session/BridgeCargoModel.swift"), encoding: .utf8)
        #expect(!model.contains("buyPrices[") && !model.contains("sellPrices[") && !model.contains("standardPrice"), "no price formula in the model")
    }

    @Test("UI-BRG-005 the Target column follows the Target System in the same step")
    func targetFollows() throws {
        let session = try TestSessions.playing(seed: 11)
        #expect(session.bridgeCargo?.targetName == nil)
        session.send(.selectNextTarget(forward: true))
        let state = try #require(session.state)
        #expect(session.bridgeCargo?.targetName == Names.system(state.warpSystem, in: state))
        #expect(session.bridgeCargo?.rows.contains { $0.quote?.system == state.warpSystem } == true)
        session.send(.selectNextTarget(forward: true))
        #expect(session.bridgeCargo?.rows.allSatisfy { $0.quote?.system == session.state?.warpSystem } == true)
    }

    @Test("UI-BRG-020 UI-BRG-021 UI-BRG-023 the Target panel is never empty: current system, in range, out of range, via wormhole; public facts only")
    func target() throws {
        let session = try TestSessions.playing(seed: 11)
        var state = try #require(session.state)
        let here = BridgeTargetModel.make(state: state, isModal: false)
        #expect(here.status == .current && here.isCurrent && here.costs.total == 0 && here.distance == 0 && !here.warp.isEnabled)
        #expect(here.system.index == state.commander.currentSystem && here.fuelAfter == state.commander.ship.fuel)
        state.warpSystem = try #require(state.destinations.first)
        let near = BridgeTargetModel.make(state: state, isModal: false)
        let preview = state.warpTargetPreview(state.warpSystem)
        #expect(near.status == (preview.viaWormhole ? .viaWormhole : .inRange) && near.distance == preview.distance && near.warp.isEnabled)
        #expect(near.costs.total == preview.costs.total && near.fuelAfter == preview.fuelAfter)
        #expect(!BridgeTargetModel.make(state: state, isModal: true).warp.isEnabled, "a dialog blocks Warp")
        let far = try #require(state.galaxy.systems.indices.first { $0 != state.commander.currentSystem && !state.destinationOK($0) })
        state.warpSystem = far
        state.galaxy.systems[far].pressure = .war
        state.galaxy.systems[far].visited = false
        let out = BridgeTargetModel.make(state: state, isModal: false)
        #expect(out.status == .outOfRange && !out.warp.isEnabled && !out.warp.help.isEmpty)
        #expect(out.system.pressure == nil && out.system.resource == nil, "no pressure and no unvisited resource of another system")
        state.trackedSystem = far
        #expect(BridgeTargetModel.make(state: state, isModal: false).isTracked)
        let wormhole = try #require(try BridgeFixtures.session(ruleset: .modern, .wormhole).state)
        var through = wormhole
        through.warpSystem = try #require(wormhole.galaxy.wormholeDestination(from: wormhole.commander.currentSystem))
        #expect(BridgeTargetModel.make(state: through, isModal: false).status == .viaWormhole)
        let panel = try String(contentsOf: Self.appRoot.appendingPathComponent("Views/Bridge/BridgeTargetPanel.swift"), encoding: .utf8)
        #expect(panel.contains("Select a target system on the chart") && panel.contains(".probed(BridgeID.Target.note)"))
        #expect(panel.components(separatedBy: "session.send(.warp)").count == 2, "UI-BRG-022: one Warp control")
        #expect(!panel.contains(".keyboardShortcut(.defaultAction)"))
    }

    @Test("UI-BRG-022 Warp is the only Warp control in the Bridge's game area")
    func oneWarp() throws {
        var count = 0
        for file in try FileManager.default.contentsOfDirectory(atPath: Self.appRoot.appendingPathComponent("Views/Bridge").path) {
            let text = try String(contentsOf: Self.appRoot.appendingPathComponent("Views/Bridge/\(file)"), encoding: .utf8)
            count += text.components(separatedBy: "session.send(.warp)").count - 1
        }
        #expect(count == 1)
    }

    @Test("UI-BRG-010 UI-BRG-011 UI-BRG-012 UI-BRG-013 the Short-Range Chart: target word, tracked label, best-destination diamonds; one click targets")
    func chart() throws {
        let session = try BridgeFixtures.session(ruleset: .modern, .fullHold)
        let best = try #require(session.bridgeIntel?.intel.bestDestinations)
        let state = try #require(session.state)
        let snapshot = IntelSnapshot(state)
        let book = session.journal?.intel ?? IntelBook(systems: [])
        #expect(best == TradeIntel.bestDestinations(book: book, snapshot: snapshot))
        let renderer = try String(contentsOf: Self.appRoot.appendingPathComponent("Map/GalaxyMapRenderer.swift"), encoding: .utf8)
        #expect(renderer.contains("bridge.bestDestinations.contains(i)") && renderer.contains("bridge.targetLabel") && renderer.contains("trackedLabel"))
        // One click on a system selects it as the target, in range or not; a wormhole can be selected.
        let map = MapSnapshot.make(state: state, generation: 0, route: nil)
        let other = try #require(map.systems.indices.first { $0 != map.currentSystem && !state.destinationOK($0) })
        #expect(MapActions.action(for: .system(other), gesture: .click, snapshot: map, isModal: false) == .send(.selectTarget(other)))
        let hole = try #require(try BridgeFixtures.session(ruleset: .modern, .wormhole).state)
        let holeMap = MapSnapshot.make(state: hole, generation: 0, route: nil)
        if case .send = MapActions.action(for: .wormhole(hole.commander.currentSystem), gesture: .click, snapshot: holeMap, isModal: false) {} else {
            Issue.record("a click on the wormhole selects it")
        }
        session.openGalacticChartAtTarget()
        #expect(session.selectedSection == .galaxy && session.map.focusRequest?.system == state.warpSystem)
        // INT-038: the setting hides the stars and the diamonds.
        session.defaults.set(false, forKey: AppSettingsKey.showRecommendations)
        session.send(.selectNextTarget(forward: true))
        #expect(session.bridgeIntel?.intel.bestDestinations.isEmpty == true && session.bridgeCargo?.rows.contains(where: \.bestBuy) == false)
    }

    @Test("UI-BRG-030 the Bridge's sources contain no scroll or collapsing container, no sheet, and no truncation or shrinking of text")
    func noScrollContainers() throws {
        let banned = ["ScrollView", "List(", "Table(", "Form {", "Form(", "LazyVStack", "LazyVGrid", "DisclosureGroup", "TabView", ".sheet(",
                      "ViewThatFits", ".lineLimit(", ".minimumScaleFactor(", "TimelineView("]
        let directory = Self.appRoot.appendingPathComponent("Views/Bridge")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".swift") }
        #expect(files.count >= 6)
        for file in files {
            let text = try String(contentsOf: directory.appendingPathComponent(file), encoding: .utf8)
            for word in banned { #expect(!text.contains(word), "\(file) contains \(word)") }
        }
    }

    @Test("UI-BRG-042 after a trip the status bar's message slot holds the arrival summary; the sheet style opens the full report")
    func arrivalSummary() throws {
        var summarized = false
        for seed in UInt64(1)...40 where !summarized {
            let session = try TestSessions.playing(seed: seed)
            session.send(.selectNextTarget(forward: true))
            session.send(.warp)
            var guardCount = 0
            while session.state?.phase != .docked, guardCount < 200 {
                guardCount += 1
                if session.presentation != nil { TestSessions.resolvePresentation(session) } else if case .encounter = session.state?.phase {
                    session.send(.encounter(.flee))
                } else { break }
            }
            guard session.state?.phase == .docked, let report = session.arrivalCard else { continue }
            #expect(report.summary.contains(Names.system(report.system, in: try #require(session.state))))
            #expect(session.selectedSection == .bridge)
            summarized = true
        }
        #expect(summarized)
        let bar = try String(contentsOf: Self.appRoot.appendingPathComponent("Views/Shell/StatusBarView.swift"), encoding: .utf8)
        #expect(bar.contains("session.present(.sheet(.report(.arrival(arrival))))") && bar.contains("Text(verbatim: arrival.summary)"))
        // Critical reports and the "sheet" style still open as sheets (UI-ENC-056 is unchanged).
        #expect(ArrivalReportStyle.allCases.count == 2)
    }

    @Test("UI-FAIR-001 views and models read other systems only through the intel layer: no hidden field of another system is named")
    func fairSources() throws {
        // Where a hidden-information name is allowed, and why.
        let allowed: [(file: String, text: String, why: String)] = [
            ("Session/BridgeModels.swift", "s.visited ? s.specialResource : nil", "the resource only once visited (ECO-007)"),
            ("Session/BridgeModels.swift", "index == state.commander.currentSystem && s.pressure != .none ? s.pressure : nil", "the current system only"),
            ("Views/Bridge/BridgeSystemPanel.swift", "model.pressure", "the current system's card"),
            ("Views/Market/SystemIntelSheet.swift", "hint.pressure", "a pressure the player read in a newspaper (INT-016)"),
            ("Views/Market/SystemIntelSheet.swift", "SystemIntelText.pressure(hint)", "the same hint"),
            ("Session/MarketIntelModel.swift", "hint.pressure", "the same hint"),
            ("Session/BridgeModels.swift", "var command: Command { .specialEvent }", "a command, not a field"),
        ]
        let hidden = [".pressure", ".specialResource", ".tradeItems", ".countDown", ".specialEvent", ".newspaper"]
        var files: [String] = []
        for folder in ["Views", "Design"] {
            let enumerator = FileManager.default.enumerator(at: Self.appRoot.appendingPathComponent(folder), includingPropertiesForKeys: nil)
            while let url = enumerator?.nextObject() as? URL {
                if url.pathExtension == "swift" { files.append(String(url.path.dropFirst(Self.appRoot.path.count + 1))) }
            }
        }
        files += try FileManager.default.contentsOfDirectory(atPath: Self.appRoot.appendingPathComponent("Session").path)
            .filter { $0.hasSuffix("Models.swift") || $0.hasSuffix("Model.swift") }.map { "Session/\($0)" }
        #expect(files.count > 60)
        for file in files {
            let text = try String(contentsOf: Self.appRoot.appendingPathComponent(file), encoding: .utf8)
            for (n, line) in text.components(separatedBy: "\n").enumerated() {
                let code = line.components(separatedBy: "//").first ?? line
                for word in hidden where code.range(of: NSRegularExpression.escapedPattern(for: word) + "\\b", options: .regularExpression) != nil {
                    // Enum cases of the same spelling (a sheet route, an options group, a command) are not state fields.
                    let isCase = code.contains("case " + word) || code.contains("case let " + word) || code.contains("(" + word + "(")
                        || code.contains("== " + word) || code.contains(": [" + word)
                    let ok = isCase || allowed.contains { $0.file == file && code.contains($0.text) }
                    #expect(ok, "\(file):\(n + 1) names \(word): \(code.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
    }

    @Test("UI-BRG-008 the row's context menu repeats the row's buttons and adds Price Details…; the sheet shows the breakdown and the history")
    func priceDetails() throws {
        let session = try TestSessions.playing(seed: 11)
        session.showPriceDetails(.ore)
        #expect(session.presentation == .sheet(.priceDetails(.ore)) && session.marketSelection == .ore)
        #expect(SheetKeys.table(for: .priceDetails(.ore)) == SheetKeyRoles(defaultAction: .done, escapeAction: .done))
        let row = try #require(session.bridgeIntel?.intel.row(.ore))
        #expect(row.explanation?.steps.isEmpty == false, "docked: the breakdown of the current system's price")
        session.dismissPresentation()
        // Game › Price Details… needs a selected good on the Bridge.
        #expect(MenuRules.availability(of: .priceDetails, in: MenuContext.make(session: session)).isEnabled)
        session.marketSelection = nil
        #expect(MenuRules.availability(of: .priceDetails, in: MenuContext.make(session: session)) == .disabled(.noCargoSelection))
        let panel = try String(contentsOf: Self.appRoot.appendingPathComponent("Views/Bridge/BridgeCargoPanel.swift"), encoding: .utf8)
        for item in ["Button(\"Buy\")", "Button(\"Buy Maximum\")", "Button(\"Sell\")", "Button(\"Sell All\")", "Button(\"Dump…\")",
                     "Button(\"Price Details…\")"] {
            #expect(panel.contains(item), "\(item)")
        }
        let sheet = try String(contentsOf: Self.appRoot.appendingPathComponent("Views/Market/BridgeSheets.swift"), encoding: .utf8)
        #expect(sheet.contains("PriceExplanationPanel(item: item") && sheet.contains("PriceSparkline(item: item"))
        // Sell All Cargo and the amount sheets are menu commands too.
        #expect(MenuCatalog.items(in: .trade).contains(.sellAllCargo) && MenuCatalog.items(in: .trade).contains(.buyFuelAmount))
        session.showServiceAmount(.fuel)
        #expect(session.presentation == .sheet(.serviceAmount(.fuel)))
    }

    @Test("UI-NAV-006 a page opens another page only through the dock bar, a menu command, Esc, or a control that names the destination")
    func pageLinks() throws {
        // Every assignment of the page in the views, and the words that name where it leads.
        let allowed: [String: [String]] = [
            "Views/Shell/DockBarView.swift": ["session.selectedSection = section"],
            "Views/Shell/GameShellView.swift": ["Section.restored("],
            "Views/Pages/PageParts.swift": ["onBack: { session.selectedSection = .bridge }"],
            "Views/Logbook/LogbookView.swift": ["onBack: ended ? nil : { session.selectedSection = .bridge }"],
            "Views/Pages/ShipyardPage.swift": ["session.selectedSection = .bank"],
            "Views/Pages/BankPage.swift": ["session.selectedSection = .shipyard"],
            "Views/Pages/StatusPage.swift": ["Button { session.selectedSection = .quests } label: {"],
            "Views/Bridge/BridgeSystemPanel.swift": ["session.selectedSection = .crew", "session.selectedSection = .quests"],
        ]
        var found = 0
        let enumerator = FileManager.default.enumerator(at: Self.appRoot.appendingPathComponent("Views"), includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let file = String(url.path.dropFirst(Self.appRoot.path.count + 1))
            for line in try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n") where line.contains("selectedSection = ") {
                found += 1
                #expect(allowed[file]?.contains { line.contains($0) } == true, "\(file): \(line.trimmingCharacters(in: .whitespaces))")
                #expect(!line.contains("send("), "\(file): a link changes the page only")
            }
        }
        #expect(found >= 6)
        // The Bridge's two notices name their page in the help tag of the active notice.
        let session = try BridgeFixtures.session(ruleset: .modern, .notices)
        let notices = BridgeNoticesModel.make(state: try #require(session.state))
        #expect(notices.mercenaries != nil && notices.nearestDeadline != nil && notices.special != nil)
    }

    @Test("UI-FAIR-002 the fairness tests of the intel layer are frozen with the game logic")
    func fairnessFrozen() throws {
        let root = Self.appRoot.deletingLastPathComponent()
        let script = try String(contentsOf: root.appendingPathComponent("scripts/logic-frozen.sh"), encoding: .utf8)
        #expect(script.contains("$PKG/Tests/ParsecInsightsTests") && script.contains("$PKG/Sources/ParsecInsights"))
        let tests = try String(contentsOf: root.appendingPathComponent("Packages/ParsecKit/Tests/ParsecInsightsTests/IntelSpecTests.swift"), encoding: .utf8)
        #expect(tests.contains("INT-001") && tests.contains("INT-013"))
    }
}
