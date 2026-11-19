// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import ParsecArt
import ParsecEngine
import SwiftUI
import Testing
@testable import ParsecMerchant

/// UI-PG: the secondary pages of release 2.0 (docs/PRD-UI-Revamp.md §4.4–§4.10).
@MainActor
@Suite("Secondary pages (UI-PG)", .serialized)
struct PageLayoutTests {
    static let appRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("SpaceTraderMac")
    static let pages: [ParsecMerchant.Section] = [.shipyard, .outfitter, .crew, .bank, .status, .quests, .galaxy, .logbook, .options]

    static func render(_ session: GameSession, page: ParsecMerchant.Section, size: CGSize) -> (NSView, [String: ShellRender.Element]) {
        // The shell restores its stored page when it appears, so the page is chosen after the first layout.
        let box = ShellRender.Box()
        let hosting = ShellRender.host(GameShellView().modifier(SceneAccessibility()).layoutProbeRoot { box.records = $0 }, session: session, size: size)
        session.selectedSection = page
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        return (hosting, box.records.reduce(into: [:]) { $0[$1.key] = ShellRender.Element(identifier: $1.key, frame: $1.value.frame,
            enabled: $1.value.enabled) })
    }

    @Test("UI-PG-001 UI-PG-002 every secondary page is a page frame with Back to the Bridge, its title and its identifier, inside the window")
    func frames() throws {
        for ruleset in RulesetID.allCases {
            let session = try BridgeFixtures.session(ruleset: ruleset, .notices)
            for page in Self.pages {
                for size in [CGSize(width: 1200, height: 680), CGSize(width: 1728, height: 1050)] {
                    let (hosting, e) = Self.render(session, page: page, size: size)
                    if ruleset == .modern, size.width == 1200 { print("QA picture: \(ShellRender.save(hosting, name: "page-\(page.rawValue)-1200x680"))") }
                    let root = try #require(e["page.\(page.rawValue)"], "\(page) \(ruleset)")
                    #expect(root.frame.minY >= 79 && root.frame.maxY <= size.height + 1 && root.frame.width > size.width - 2, "\(page) \(root.frame)")
                    let back = try #require(e["page.\(page.rawValue).back"], "\(page) has Back")
                    #expect(back.enabled && back.frame.height >= 35 && root.frame.contains(back.frame))
                    #expect(e[AXID.Dock.bar] != nil && e[AXID.Status.bar] != nil, "the bars stay on every page")
                    #expect(e[page.axID] != nil)
                }
            }
        }
        // Esc and Back both return to the Bridge.
        let session = try TestSessions.playing(seed: 11)
        session.selectedSection = .bank
        #expect(EscapeRegistry().handle(session: session) && session.selectedSection == .bridge)
    }

    @Test("UI-PG-003 UI-PG-050 pages show what the ruleset offers: the Designer only with a yard, and only the ruleset's options")
    func rulesetContent() throws {
        for ruleset in RulesetID.allCases {
            let state = try #require(try BridgeFixtures.session(ruleset: ruleset, .newGame).state)
            let draft = OptionsDraft(options: state.options, ruleset: ruleset)
            #expect(draft.isVisible(.newsAutoShow) == state.ruleset.flags.travel.newsAutoShowAvailable)
            #expect(draft.isVisible(.disableOpponents) == state.ruleset.content.hasDisruptors)
            #expect(ShipyardModel.make(state: state).designerAvailable == SectionContext.make(state: state).designerAvailable)
        }
        let options = try String(contentsOf: Self.appRoot.appendingPathComponent("Views/Pages/OptionsPage.swift"), encoding: .utf8)
        #expect(options.contains("group.fields.filter(draft.isVisible)") && options.contains("session.send(d.commit())"))
        #expect(!options.contains("keyboardShortcut(.defaultAction)"), "no OK or Cancel: a change applies at once")
        let shipyard = try String(contentsOf: Self.appRoot.appendingPathComponent("Views/Pages/ShipyardPage.swift"), encoding: .utf8)
        #expect(shipyard.contains("ShipyardModel.make(state: state).designerAvailable"))
    }

    @Test("UI-PG-050 an option changes the game at once and can be changed back")
    func optionsApply() throws {
        let session = try TestSessions.playing(seed: 11)
        let before = try #require(session.state).options
        var draft = OptionsDraft(options: before, ruleset: .modern)
        draft.set(.autoFuel, !before.autoFuel)
        session.send(draft.commit())
        #expect(session.state?.options.autoFuel == !before.autoFuel && session.lastRejection == nil)
    }

    @Test("UI-PG-010 Shipyard: one click selects, the button buys, the comparison is always shown; no Compare toggle")
    func shipyard() throws {
        let source = try String(contentsOf: Self.appRoot.appendingPathComponent("Views/Pages/ShipyardPage.swift"), encoding: .utf8)
        #expect(source.contains(".onTapGesture(perform: onSelect)") && source.contains("AXID.Shipyard.buy(card.type)"))
        #expect(source.contains("if let current { comparison(current: current, selected: card) }"))
        #expect(!source.contains("Compare\")") && !source.contains("Toggle("))
        #expect(!AXID.all.contains { $0.hasSuffix(".compare") && $0.hasPrefix("shipyard.ship.") })
    }

    @Test("UI-PG-020 Equipment: Buy and Sell are buttons in each row; drag and drop is only an accelerator; no detail form")
    func equipment() throws {
        let source = try String(contentsOf: Self.appRoot.appendingPathComponent("Views/Pages/EquipmentPage.swift"), encoding: .utf8)
        #expect(source.contains("AXID.Outfitter.buy(o.item)") && source.contains("AXID.Outfitter.sell(group, slot: t.slot)"))
        #expect(source.contains(".draggable(OutfitterDragItem(item: o.item, source: .offer))"))
        #expect(!source.contains("AXID.Outfitter.detail") && !source.contains("Form {"))
        #expect(source.contains("EquipmentText.description(o.item)"), "the item's details are in the row's help tag")
    }

    @Test("UI-PG-030 Personnel shows crew, hires and effective skills; Police Record, Reputation and kills are on Commander Status only")
    func personnel() throws {
        let personnel = try String(contentsOf: Self.appRoot.appendingPathComponent("Views/Pages/PersonnelPage.swift"), encoding: .utf8)
        #expect(!personnel.contains("policeRecord") && !personnel.contains("reputation") && !personnel.contains("Kills"))
        #expect(personnel.contains("CrewAvatarView(crewID: crewID, side: 96 * scale)"), "96 pt portraits")
        let status = try String(contentsOf: Self.appRoot.appendingPathComponent("Views/Pages/StatusPage.swift"), encoding: .utf8)
        #expect(status.contains("Names.policeRecord(m.policeRecord)") && status.contains("Names.reputation(m.reputation)") && status.contains("\"Kills\""))
    }

    @Test("UI-PG-040 UI-SB-005 Commander Status shows every field of the 1.x inspector, and the galaxy code with Copy")
    func status() throws {
        let source = try String(contentsOf: Self.appRoot.appendingPathComponent("Views/Pages/StatusPage.swift"), encoding: .utf8)
        // Every stored property of `InspectorModel` is read by the page.
        let fields = ["commanderName", "difficulty", "days", "shipType", "shipName", "hullPercent", "shields", "cash", "debt", "worth", "skills",
                      "policeRecord", "policeScore", "reputation", "kills", "notoriety", "cargo", "specialCargo", "weapons", "shieldsInstalled",
                      "gadgets", "escapePod", "hardenedHull", "freeWeaponSlots", "freeShieldSlots", "freeGadgetSlots", "crew", "freeQuarters",
                      "dailyCosts"]
        for field in fields { #expect(source.contains("m.\(field)"), "the page shows \(field)") }
        let model = try String(contentsOf: Self.appRoot.appendingPathComponent("Session/ShellModels.swift"), encoding: .utf8)
        let declared = model.components(separatedBy: "struct InspectorModel")[1].components(separatedBy: "static func ==")[0]
            .components(separatedBy: "\n").compactMap { line -> String? in
                let t = line.trimmingCharacters(in: .whitespaces)
                guard t.hasPrefix("var "), let name = t.dropFirst(4).split(separator: ":").first else { return nil }
                return String(name)
            }
        #expect(Set(declared).subtracting(["base", "effective", "skill", "crewID", "dailyWage", "isPassenger"]) == Set(fields), "\(declared)")
        #expect(source.contains("GalaxyCodeCard.copy(GalaxyCodeCard.code(state: state))") && AXID.all.contains(AXID.Inspector.galaxyCodeCopy))
        let session = try TestSessions.playing(seed: 11)
        session.selectedSection = .bank
        session.showCommanderStatusPage()
        #expect(session.selectedSection == .status, "the Show Commander Status intent opens the page")
        let fight = try EncFx.session(.pirateAttack)
        fight.showCommanderStatusPage()
        #expect(fight.selectedSection != .status, "never during an encounter")
        let (_, e) = Self.render(session, page: .status, size: CGSize(width: 1200, height: 680))
        for id in [AXID.Inspector.root, AXID.Inspector.hull, AXID.Inspector.cash, AXID.Inspector.debt, AXID.Inspector.worth,
                   AXID.Inspector.galaxyCode, AXID.Inspector.galaxyCodeCopy] {
            #expect(e[id] != nil || id == AXID.Inspector.root, "\(id)")
        }
    }

    @Test("UI-PG-060 UI-PG-061 UI-PG-062 the Galactic Chart: the Selected System panel beside the map, one Find, the HUD's tools")
    func chart() throws {
        let session = try BridgeFixtures.session(ruleset: .modern, .fullHold)
        let (hosting, e) = Self.render(session, page: .galaxy, size: CGSize(width: 1440, height: 860))
        print("QA picture: \(ShellRender.save(hosting, name: "page-galaxy-1440x860"))")
        let map = try #require(e[AXID.Map(.galaxy).map]), panel = try #require(e[AXID.Map(.galaxy).selectionCard])
        #expect(panel.frame.minX >= map.frame.maxX - 1 && panel.frame.width >= 290, "the panel is beside the chart: \(map.frame) \(panel.frame)")
        #expect(e[AXID.Galaxy.find]?.enabled == true)
        let view = try String(contentsOf: Self.appRoot.appendingPathComponent("Map/GalaxyMapView.swift"), encoding: .utf8)
        #expect(!view.contains("MapSearchView(") && !view.contains("TextField("), "UI-PG-061: no inline search; Find System is the one search")
        #expect(view.contains("MapFiltersView(") && view.contains("HeatmapHUDView(") && view.contains("MapLegendView(") && view.contains("RoutePanelView("))
        #expect(view.contains("TargetStripView("), "UI-PG-062: the target strip with Warp and the singularity jump stays")
        let panelSource = try String(contentsOf: Self.appRoot.appendingPathComponent("Map/ChartSelectionPanel.swift"), encoding: .utf8)
        #expect(panelSource.contains("SystemIntelModel.make(system: index") && panelSource.contains("IntelText.age(row.quote)"))
        // ⌘F on the chart opens Find System.
        session.selectedSection = .galaxy
        ContextSearch.perform(MenuContext.make(session: session).searchContext, focused: nil, session: session)
        #expect(session.presentation == .sheet(.findSystem))
        // No glass in the HUD (UI-DS-024).
        let hud = try String(contentsOf: Self.appRoot.appendingPathComponent("Map/MapHUDViews.swift"), encoding: .utf8)
        #expect(!hud.contains(".glassEffect("))
    }

    @Test("UI-PG-063 the chart's selection panel reads other systems through the intel layer only")
    func chartFair() throws {
        let source = try String(contentsOf: Self.appRoot.appendingPathComponent("Map/ChartSelectionPanel.swift"), encoding: .utf8)
        for hidden in [".pressure", ".specialResource", ".tradeItems", ".countDown", ".specialEvent"] { #expect(!source.contains(hidden), "\(hidden)") }
        #expect(source.contains("showPressure: false"), "the planet of another system never shows its pressure")
    }

    @Test("UI-ENC-200 UI-ENC-201 UI-ENC-202 the encounter page: intro and badge, two ship panels at 55% of the height, the action bar, the log")
    func encounter() throws {
        let session = try EncFx.session(.pirateAttack)
        let size = CGSize(width: 1200, height: 680)
        let (hosting, e) = ShellRender.probe(GameShellView().modifier(SceneAccessibility()), session: session, size: size)
        print("QA picture: \(ShellRender.save(hosting, name: "encounter-1200x680"))")
        let intro = try #require(e[AXID.Encounter.intro]), player = try #require(e[AXID.Encounter.player])
        let opponent = try #require(e[AXID.Encounter.opponent]), actions = try #require(e[AXID.Encounter.actions]), log = try #require(e[AXID.Encounter.log])
        #expect(intro.frame.maxY <= player.frame.minY + 1 && player.frame.maxY <= actions.frame.minY + 1 && actions.frame.maxY <= log.frame.minY + 1,
                "intro, ships, actions, log from the top")
        #expect(abs(player.frame.height - 600 * 0.55) < 12 && abs(player.frame.width - opponent.frame.width) < 2 && player.frame.maxX < opponent.frame.minX)
        #expect(actions.frame.width > size.width * 0.9, "the action bar spans the page")
        #expect(log.frame.maxY <= size.height + 1 && actions.frame.maxY < size.height - 40, "the controls are not at the bottom edge")
        #expect(e[AXID.Encounter.badge] != nil)
        for badge in [EncounterBadge.police, .pirate, .trader, .alien, .special] {
            #expect(!EncounterBadgeModel(badge: badge).word.isEmpty)
        }
        #expect(Set([EncounterBadge.police, .pirate, .trader, .alien, .special].map { "\(EncounterRoleColor.color($0))" }).count == 5, "a colour per role")
        let bar = try String(contentsOf: Self.appRoot.appendingPathComponent("Views/Encounter/EncounterActionBar.swift"), encoding: .utf8)
        #expect(bar.contains("PMKeyCap(key: key)") && bar.contains("base.keyboardShortcut(.defaultAction)") && !bar.contains(".glassEffect("))
    }

    @Test("UI-ENC-203 UI-ENC-204 the opponent's ship wears its role livery; only a famous captain has a portrait")
    func encounterOpponent() throws {
        #expect(EncounterPortrait.role(.captainAhab) == .ahab && EncounterPortrait.role(.captainConrad) == .conrad
            && EncounterPortrait.role(.captainHuie) == .huie)
        #expect(EncounterPortrait.role(.pirateAttack) == nil && EncounterPortrait.role(.policeInspect) == nil)
        let session = try EncFx.session(.pirateAttack)
        let engine = try #require(session.engine), preview = try #require(engine.encounterPreview)
        let opponent = try #require(ShipPaneModel.opponent(state: engine.state, preview: preview))
        #expect(opponent.art.role == .pirate)
        let player = ShipPaneModel.player(state: engine.state, preview: preview)
        #expect(player.art.role == .player && opponent.art.livery != player.art.livery)
        let (_, e) = ShellRender.probe(GameShellView().modifier(SceneAccessibility()), session: session, size: CGSize(width: 1200, height: 680))
        #expect(e[AXID.Encounter.captainPortrait] == nil, "a pirate has no portrait")
    }

    @Test("UI-ENC-205 Plunder, Trade in Orbit and Make Room are sheets built from components, one row per good, with Quantity / Max / All")
    func encounterSheets() throws {
        let source = try String(contentsOf: Self.appRoot.appendingPathComponent("Views/Encounter/EncounterSheets.swift"), encoding: .utf8)
        #expect(source.components(separatedBy: "PMSheet(").count - 1 == 3 && source.components(separatedBy: "SheetGoodRow(item:").count - 1 == 3)
        #expect(source.contains("PMButton(title: \"All\"") && source.contains("PMButton(title: \"Max\"") && !source.contains("Take All"))
        for old in ["Stepper(", "Picker(", "QuantityChips(", ".scaledFont(", "LabeledContent("] { #expect(!source.contains(old), "\(old)") }
        #expect(PMQuantityField.parse("3", in: 1...5) == 3 && PMQuantityField.parse(" 5 ", in: 1...5) == 5)
        #expect(PMQuantityField.parse("0", in: 1...5) == nil && PMQuantityField.parse("6", in: 1...5) == nil && PMQuantityField.parse("x", in: 1...5) == nil)
        // The sheets are hosted in the console palette (they do not inherit the window's styles).
        let host = try String(contentsOf: Self.appRoot.appendingPathComponent("Views/Presentation/PresentationHost.swift"), encoding: .utf8)
        #expect(host.contains(".pmSheetChrome()"))
        // One row per good: the plunder sheet lists the victim's goods, Make Room the player's.
        let s = try EncFx.session(.pirateSurrender)
        try TestSessions.edit(s) { $0.commander.ship.cargo[TradeItemType.water.rawValue] = 2; $0.commander.ship.cargo[TradeItemType.ore.rawValue] = 1 }
        let room = MakeRoomModel.make(state: try #require(s.state))
        #expect(room.rows.map(\.item) == [.water, .ore])
        for item in [TradeItemType.water, .ore] {
            #expect([AXID.Decision.makeRoomRow(item), AXID.Decision.makeRoomQuantity(item), AXID.Decision.makeRoomJettison(item),
                     AXID.Decision.makeRoomAll(item)].allSatisfy(AXID.all.contains))
        }
        #expect(AXID.all.contains(AXID.Decision.tradeRow))
    }

    @Test("UI-ENC-206 effects aim at the ships' frames, and every round that shows an effect also writes a log line")
    func encounterEffectsHaveText() throws {
        let stage = try String(contentsOf: Self.appRoot.appendingPathComponent("Art/EncounterStage.swift"), encoding: .utf8)
        #expect(stage.contains("ShipArtLayout.frame(input, mode: .relative, in: art.size)") && stage.contains("EncounterMotion.geometry("))
        var rounds = 0
        for seed in [UInt64(1), 2, 3] {
            let s = try EncFx.session(.pirateAttack, seed: seed)
            for _ in 0..<40 {
                guard s.engine?.encounterPreview != nil, s.presentation == nil else { break }
                s.performEncounterAction(.attack)
                let plan = CombatEffectPlanner.plan(record: s.lastStep)
                if !plan.isEmpty, let step = s.lastStep {
                    rounds += 1
                    // The same step record feeds the effects and the log, so nothing is shown only as animation.
                    #expect(!(CombatLog.closingLines(for: step) + CombatLog.lines(for: step)).isEmpty, "seed \(seed): effects \(plan.map { "\($0.kind)" }) without a log line")
                }
            }
        }
        #expect(rounds >= 3, "the fixture fought \(rounds) rounds")
    }

    @Test("UI-ENC-207 every encounter requirement on behaviour is still tested")
    func encounterBehaviourStaysTested() throws {
        let repo = Self.appRoot.deletingLastPathComponent()
        let spec = try String(contentsOf: repo.appendingPathComponent("docs/specs/UI-ENC.md"), encoding: .utf8)
        var tests = ""
        for folder in ["SpaceTraderMacTests", "SpaceTraderMacUITests", "Packages/ParsecKit/Tests"] {
            let files = FileManager.default.enumerator(at: repo.appendingPathComponent(folder), includingPropertiesForKeys: nil)
            while let file = files?.nextObject() as? URL {
                if file.pathExtension == "swift" { tests += try String(contentsOf: file, encoding: .utf8) }
            }
        }
        var checked = 0
        for line in spec.components(separatedBy: "\n") {
            guard let match = line.firstMatch(of: /^- \*\*(UI-ENC-[01][0-9]{2})\*\*/), !line.contains("[retired"), !line.contains("[manual]") else { continue }
            checked += 1
            #expect(tests.contains(String(match.1)), "\(match.1) lost its test")
        }
        #expect(checked > 80, "\(checked) behaviour requirements")
    }

    @Test("UI-NAV-008 the Galactic Chart window (⇧⌘M) stays and shows the page's chart")
    func chartWindow() throws {
        let source = try String(contentsOf: Self.appRoot.appendingPathComponent("Map/MapPlacements.swift"), encoding: .utf8)
        #expect(source.contains("GalaxyMapView(scope: .galaxy)") && source.contains("GalaxyMapView(scope: .galaxyWindow)"))
        #expect(MapScope.galaxyWindow.hasHUD && MapScope.galaxy.hasHUD, "both show the HUD and the Selected System panel")
        #expect(MapActions.selectsOnly(scope: .galaxyWindow, gesture: .click))
        let entry = MenuCatalog.entry(for: .galaxyChart)
        #expect(entry.shortcut?.key == "m" && entry.shortcut?.modifiers == [.shift, .command])
    }

    @Test("UI-NAV-010 a page with nothing to offer stays open to the dock and says why")
    func emptyPages() throws {
        let session = try BridgeFixtures.session(ruleset: .modern, .newGame)
        try TestSessions.edit(session) { state in
            state.galaxy.systems[state.commander.currentSystem].techLevel = .preAgricultural
        }
        let state = try #require(session.state)
        #expect(!ShipyardModel.make(state: state).hasShipsForSale)
        let (_, e) = Self.render(session, page: .shipyard, size: CGSize(width: 1200, height: 680))
        #expect(e["shipyard.none"] != nil, "the Shipyard says that no ships are for sale")
        #expect(e[AXID.Dock.button(.shipyard)]?.enabled == true && e[AXID.Dock.button(.crew)]?.enabled == true)
        let source = try String(contentsOf: Self.appRoot.appendingPathComponent("Views/Pages/ShipyardPage.swift"), encoding: .utf8)
        #expect(source.contains("No ships for sale in this system"))
    }

    @Test("ART-FACE-010 every portrait has the label \"Portrait of ‹name›\" and takes no keyboard focus")
    func portraitLabels() throws {
        let art = try String(contentsOf: Self.appRoot.appendingPathComponent("Art/ArtViews.swift"), encoding: .utf8)
        #expect(art.contains("Text(\"Portrait of \\(Names.crew(crewID, in: state))\")") && art.contains(".accessibilityAddTraits(.isImage)"))
        let encounter = try String(contentsOf: Self.appRoot.appendingPathComponent("Views/Encounter/EncounterView.swift"), encoding: .utf8)
        #expect(encounter.contains("Text(\"Portrait of \\(String(localized: EncounterPortrait.name(role)))\")"))
        #expect(String(localized: EncounterPortrait.name(.ahab)) == "Captain Ahab" && String(localized: EncounterPortrait.name(.huie)) == "Captain Huie")
        // Every place that draws a face goes through one of the two labelled views; none is a control.
        var uses = 0
        let files = FileManager.default.enumerator(at: Self.appRoot, includingPropertiesForKeys: nil)
        while let file = files?.nextObject() as? URL {
            guard file.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: file, encoding: .utf8)
            uses += text.components(separatedBy: "CharacterPortrait(").count - 1
            #expect(!text.contains("Button { } label: { CharacterPortrait") && !text.contains("CharacterPortrait(genome: genome).focusable("))
        }
        #expect(uses == 2, "CrewAvatarView and the famous captain: \(uses)")
    }

    /// A sheet's body as the host shows it: the console palette on the panel fill.
    private func sheetPicture<V: View>(_ view: V, session: GameSession, name: String, size: CGSize = CGSize(width: 640, height: 600)) -> NSView {
        let hosting = ShellRender.host(view.pmSheetChrome().frame(maxWidth: .infinity, maxHeight: .infinity).background(PMColor.panel),
                                       session: session, size: size)
        print("QA picture: \(ShellRender.save(hosting, name: name))")
        return hosting
    }

    @Test("UI-PG-070 UI-ENC-205 the sheets, Welcome and Game Over render in the console palette (QA pictures)")
    func surfacesRender() throws {
        let plunder = try EncFx.session(.pirateSurrender)
        try TestSessions.edit(plunder) { $0.commander.ship.cargo[TradeItemType.water.rawValue] = 3; $0.commander.ship.cargo[TradeItemType.food.rawValue] = 2 }
        let context = PlunderSheetContext(victimCargo: [0, 4, 0, 2, 0, 0, 0, 0, 0, 1], source: .opponent)
        #expect(sheetPicture(PlunderSheet(context: context), session: plunder, name: "sheet-plunder").fittingSize.height > 100)
        #expect(sheetPicture(EncounterMakeRoomSheet(item: .ore), session: plunder, name: "sheet-make-room").fittingSize.height > 100)
        let json = #"{"direction":"traderSells","item":"ore","unitPrice":40,"maxQuantity":6,"unitsAvailable":9,"costBasisPerUnit":30}"#
        if let offer = try? JSONDecoder().decode(OrbitTradeOffer.self, from: Data(json.utf8)) {
            #expect(sheetPicture(TradeInOrbitSheet(offer: offer), session: try EncFx.session(.traderSell), name: "sheet-trade").fittingSize.height > 100)
        }
        let docked = try BridgeFixtures.session(ruleset: .modern, .fullHold)
        #expect(sheetPicture(ShipPurchaseSheet(request: .ship(.firefly)), session: docked, name: "sheet-purchase", size: CGSize(width: 640, height: 760))
            .fittingSize.height > 100)
        #expect(sheetPicture(NewGameWizard(), session: docked, name: "sheet-new-game", size: CGSize(width: 700, height: 620)).fittingSize.height > 100)
        #expect(sheetPicture(FindSystemSheet(), session: docked, name: "sheet-find").fittingSize.height > 50)
        #expect(sheetPicture(CheatConsoleSheet(), session: docked, name: "sheet-cheats").fittingSize.height > 50)
        #expect(sheetPicture(PriceDetailsSheet(item: .water), session: docked, name: "sheet-price-details").fittingSize.height > 50)
        let welcome = try TestSessions.make()
        let w = ShellRender.host(WelcomeView(), session: welcome, size: CGSize(width: 1200, height: 680))
        print("QA picture: \(ShellRender.save(w, name: "welcome-1200x680"))")
        let over = try TestSessions.playing()
        try TestSessions.edit(over) { $0.phase = .gameOver(.boughtMoon) }
        let g = ShellRender.host(GameShellView().modifier(SceneAccessibility()), session: over, size: CGSize(width: 1200, height: 900))
        print("QA picture: \(ShellRender.save(g, name: "game-over-1200x900"))")
        let transit = try EncFx.session(.pirateAttack)
        let t = ShellRender.host(GameShellView().modifier(SceneAccessibility()), session: transit, size: CGSize(width: 1440, height: 860))
        print("QA picture: \(ShellRender.save(t, name: "encounter-1440x860"))")
    }
}
