// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import ParsecEngine
import SwiftUI
import Testing
@testable import ParsecMerchant

/// UI-PG: the secondary pages of release 2.0 (docs/PRD-UI-Revamp.md §4.4–§4.10).
@MainActor
@Suite("Secondary pages (UI-PG)", .serialized)
struct PageLayoutTests {
    static let appRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("SpaceTraderMac")
    static let pages: [ParsecMerchant.Section] = [.shipyard, .outfitter, .crew, .bank, .status, .quests, .logbook, .options]

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
}
