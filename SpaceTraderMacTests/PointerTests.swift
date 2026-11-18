// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import SwiftUI
import Testing
@testable import ParsecMerchant

@MainActor
@Suite("Pointer and touch first (UI-POINTER)")
struct PointerTests {
    static let appRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("SpaceTraderMac")

    static func source(_ file: String) throws -> String { try String(contentsOf: appRoot.appendingPathComponent(file), encoding: .utf8) }

    @Test("UI-PTR-001 the keyboard path is unchanged: the binding table still has every market, map and encounter action")
    func principle() throws {
        // Modifier clicks are accelerators of visible controls; the key table itself is pinned by UI-KEYS-003.
        #expect(MarketKeyAction.make(characters: "B", modifiers: []) != nil && MarketKeyAction.make(characters: "S", modifiers: .shift) == .sellAll)
        #expect(EncounterKeys.keyCap(for: .resolve) == "R")
        // Key hints are not in primary UI: no ⌘-digit in sidebar rows, no key cap in encounter button labels.
        #expect(!(try Self.source("Views/Shell/SidebarView.swift")).contains("shortcutDigit)\")"))
        let bar = try Self.source("Views/Encounter/EncounterActionBar.swift")
        #expect(!bar.contains("button.keyCap") && bar.contains(".controlSize(.large)"))
    }

    @Test("UI-PTR-002 UI-PTR-003 the shared modifiers: a 36 pt minimum target and a hover tint that changes no layout")
    func modifiers() throws {
        #expect(PointerTarget.minimum == 36)
        #expect(HoverHighlight.opacity > 0 && HoverHighlight.opacity < 0.3)
        let source = try Self.source("Accessibility/PointerTarget.swift")
        #expect(source.contains(".frame(minWidth: minimum, minHeight: minimum)") && source.contains(".contentShape(Rectangle())"))
        #expect(source.contains(".onHover { hovering = $0 }") && source.contains(".allowsHitTesting(false)"))
        // A small sprite keeps its size inside the target: the frame grows, not the picture.
        let size = AppArtSnapshot.render(Color.red.frame(width: 22, height: 22).pointerTarget().background(Color.blue), size: CGSize(width: 60, height: 60))
        var blue = 0, red = 0
        for i in stride(from: 0, to: size.count, by: 4) where size[i + 3] > 0 {
            if size[i + 2] > size[i] { blue += 1 } else { red += 1 }
        }
        #expect(red == 22 * 22 && blue + red == 36 * 36)
    }

    @Test("UI-PTR-003 UI-PTR-004 source audit: tappable cards react to hover; no small buttons; accelerators have visible twins")
    func audit() throws {
        var files: [(name: String, text: String)] = []
        let enumerator = FileManager.default.enumerator(at: Self.appRoot, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            files.append((String(url.path.dropFirst(Self.appRoot.path.count + 1)), try String(contentsOf: url, encoding: .utf8)))
        }
        #expect(files.count > 100)
        var taps = 0
        for f in files where f.text.contains(".onTapGesture") {
            taps += 1
            #expect(f.text.contains(".hoverHighlight("), "\(f.name) takes taps without hover feedback")
        }
        #expect(taps >= 2)
        // Small and mini control sizes shrink targets; the only ones left are not buttons.
        let allowed = ["Map/MapHUDViews.swift": "ProgressView().controlSize(.small)"]
        for f in files {
            for line in f.text.components(separatedBy: "\n") where line.contains(".controlSize(.small)") || line.contains(".controlSize(.mini)") {
                #expect(allowed[f.name].map(line.contains) == true, "\(f.name): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        // Every place that reads the held modifiers sits beside a visible control that does the same without them.
        let twins = ["Views/Sections/MarketSectionView.swift": "AXID.Market.chip(",        // chips choose what ⇧/⌘/⌥ accelerate
                     "Views/Sections/ShipyardSectionView.swift": "AXID.Shipyard.compareToggle(",  // Compare toggle for ⌘-click
                     "Map/GalaxyMapView.swift": "ids.selection(item.kind)",                // card buttons for ⌥-click and ⌘-scroll
                     "Session/MarketModels.swift": "enum TradeChip"]
        for f in files where f.text.contains("NSEvent.modifierFlags") || f.text.contains("event.modifierFlags") {
            let twin = try #require(twins[f.name], "\(f.name) reads modifier keys but is not in the accelerator table")
            #expect(f.text.contains(twin), "\(f.name)")
        }
        // Hover reveals nothing a click does not: the map's hover card has the pinned selection card.
        let map = try Self.source("Map/GalaxyMapView.swift")
        #expect(map.contains("if scope.hasHUD { ui.pinnedHit = hit }") && map.contains(".allowsHitTesting(pinned)"))
    }

    @Test("UI-PTR-007 UI-PTR-008 quantity chips: 1, 5, 20, Max; a modifier is an accelerator that overrides the chip")
    func chips() throws {
        #expect(TradeChip.allCases == [.one, .five, .twenty, .max])
        #expect(TradeChip.allCases.map(\.idSuffix) == ["1", "5", "20", "max"])
        #expect(TradeChip.allCases.map { $0.quantity(maximum: 50) } == [1, 5, 20, 50])
        #expect(TradeChip.allCases.map { $0.quantity(maximum: 3) } == [1, 3, 3, 3])
        #expect(TradeChip.allCases.map { $0.quantity(maximum: 0) } == [0, 0, 0, 0] && TradeChip.max.quantity(maximum: -5) == 0)
        let mods: [EventModifiers] = [[], .shift, .command, [.shift, .command], .option, .control]
        for chip in TradeChip.allCases {
            for m in mods {
                let expected = m.isEmpty || m == .control ? chip.quantity(maximum: 500) : TradeQuantity.resolve(modifiers: m, maximum: 500)
                #expect(TradeQuantity.resolve(chip: chip, modifiers: m, maximum: 500) == expected, "\(chip) \(m)")
            }
        }
        let s = MapFx.state(.modern, seed: 11)
        let r = try #require(MarketRowModel.rows(state: s).first { $0.row.maxBuy > 6 })
        #expect(r.buyCommand(chip: .one) == .buyCargo(r.item, quantity: 1))
        #expect(r.buyCommand(chip: .five) == .buyCargo(r.item, quantity: 5))
        #expect(r.buyCommand(chip: .max) == r.buyMaxCommand, "Max then Buy is Buy Max: no more clicks than before")
        #expect(r.buyCommand(chip: .one, modifiers: .shift) == .buyCargo(r.item, quantity: 5))
        #expect(r.sellCommand(chip: .five) == nil, "nothing held: nothing to sell")
        #expect(AXID.Market.chip(.water, .twenty) == "market.row.water.chip.20" && AXID.all.contains(AXID.Market.chip(.robots, .max)))
        // The row shows chips, Buy, Sell, the typed amount with the same buttons as its submit, and a visible disposal button.
        let view = try Self.source("Views/Sections/MarketSectionView.swift")
        for needle in ["AXID.Market.chip(r.item, c)", "trade(r, sell: true, chip: chip, typed: typed)", "trade(r, sell: false, chip: chip, typed: typed)",
                       "if !typed.isEmpty {", "CargoDisposal.jettison(r) ?? CargoDisposal.dump(r)", ".contextMenu { rowMenu(r) }"] {
            #expect(view.contains(needle), "\(needle)")
        }
        #expect(MarketText.menuBuy(.max, maximum: 12) == "Buy Max (12)" && MarketText.menuSell(.max, maximum: 7, dump: true) == "Dump All (7)")
    }

    @Test("UI-PTR-005 UI-PTR-006 UI-PTR-009 context menus mirror the visible actions; double-click is a card's primary action; Compare is a toggle")
    func menusAndCards() throws {
        for (file, needles) in [
            ("Views/Sections/MarketSectionView.swift", ["Button(\"Why This Price?\")", "Button(\"Jettison…\")"]),
            ("Views/Sections/ShipyardSectionView.swift", [".contextMenu {", "\"Remove from Compare\"",
                                                          ".onTapGesture(count: 2) { if card.canOpenPurchase { onBuy() } }",
                                                          "AXID.Shipyard.compareToggle(card.type)", ".toggleStyle(.button)"]),
            ("Views/Sections/OutfitterSectionView.swift", [".contextMenu {",
                                                           ".onTapGesture(count: 2) { if o.buyBlocker == nil { session.send(o.item.buyCommand) } }"]),
            ("Views/Sections/CrewSectionView.swift", [".contextMenu {", "Button(\"Hire\", action: hire)"]),
            ("Views/Sections/QuestsSectionView.swift", [".contextMenu {"]),
            ("Views/Sections/BridgeSectionView.swift", [".contextMenu {", "Button(\"Plot Route…\") { session.plotRouteToTarget() }"]),
            ("Map/GalaxyMapView.swift", [".contextMenu { contextMenuItems(snapshot) }"])
        ] {
            let text = try Self.source(file)
            for n in needles { #expect(text.contains(n), "\(file): \(n)") }
        }
        #expect(AXID.Shipyard.compareToggle(.gnat) == "shipyard.ship.gnat.compare" && AXID.all.contains(AXID.Shipyard.compareToggle(.wasp)))
        var selection = ShipSelection()
        selection.click(.gnat, command: true)
        selection.click(.wasp, command: true)
        #expect(selection.isComparing && selection.contains(.gnat))
        selection.click(.gnat, command: true)
        #expect(!selection.contains(.gnat))
    }

    @Test("UI-PTR-010 Outfitter drops: an offer on a free slot of its kind buys; an installed item on the sell well sells; the rest does nothing")
    func outfitterDrops() throws {
        let laser = OutfitterDragItem(item: .weapon(.pulseLaser), source: .offer)
        #expect(OutfitterDrop.group(of: .weapon(.beamLaser)) == .weapons && OutfitterDrop.group(of: .shield(.energy)) == .shields
            && OutfitterDrop.group(of: .gadget(.extraCargoBays)) == .gadgets)
        #expect(OutfitterDrop.action(for: laser, onto: .slot(.weapons, free: true), buyBlocked: false) == .buy(.weapon(.pulseLaser)))
        #expect(OutfitterDrop.action(for: laser, onto: .slot(.weapons, free: false), buyBlocked: false) == .none, "the slot is taken")
        #expect(OutfitterDrop.action(for: laser, onto: .slot(.shields, free: true), buyBlocked: false) == .none, "a weapon on a shield slot")
        #expect(OutfitterDrop.action(for: laser, onto: .slot(.weapons, free: true), buyBlocked: true) == .none, "the buy check blocks it")
        #expect(OutfitterDrop.action(for: laser, onto: .sellWell, buyBlocked: false) == .none)
        let installed = OutfitterDragItem(item: .shield(.energy), source: .installed(slot: 1))
        #expect(OutfitterDrop.action(for: installed, onto: .sellWell, buyBlocked: false) == .sell(.shield(.energy), slot: 1))
        #expect(OutfitterDrop.action(for: installed, onto: .slot(.shields, free: true), buyBlocked: false) == .none)
        // The payload survives the pasteboard.
        let data = try JSONEncoder().encode(installed)
        #expect(try JSONDecoder().decode(OutfitterDragItem.self, from: data) == installed)
        let view = try Self.source("Views/Sections/OutfitterSectionView.swift")
        #expect(view.contains(".draggable(OutfitterDragItem(item: o.item, source: .offer))") && view.contains(".dropDestination(for: OutfitterDragItem.self)"))
        #expect(view.contains("AXID.Outfitter.sellWell") && AXID.all.contains(AXID.Outfitter.sellWell))
        // The buttons remain the tap path.
        #expect(view.contains("AXID.Outfitter.buy(o.item)") && view.contains("AXID.Outfitter.sell(group, slot: t.slot)"))
    }

    @Test("UI-PTR-011 UI-PTR-012 the map: a click pins a card with buttons; a plain wheel zooms, two fingers pan")
    func map() throws {
        #expect(MapScroll.action(deltaX: 0, deltaY: 1, precise: false, command: false) == .zoom(steps: 1))
        #expect(MapScroll.action(deltaX: 0, deltaY: -2, precise: false, command: true) == .zoom(steps: -2))
        #expect(MapScroll.action(deltaX: 3, deltaY: -7, precise: true, command: false) == .pan(CGSize(width: 3, height: -7)))
        #expect(MapScroll.action(deltaX: 3, deltaY: 20, precise: true, command: true) == .zoom(steps: 2))
        let ui = MapViewModel(scope: .galaxy)
        ui.pinnedHit = .system(3)
        ui.closeCard()
        #expect(ui.pinnedHit == nil, "pan, zoom, Esc and a new state unpin the card")
        let ids = AXID.Map(.galaxy)
        #expect(ids.selectionCard == "galaxy.selectionCard" && ids.selection(.setTarget) == "galaxy.selection.setTarget"
            && ids.selection(.track) == "galaxy.selection.track" && ids.selection(.plotRoute) == "galaxy.selection.plotRoute"
            && ids.selection(.useWormhole) == "galaxy.selection.useWormhole")
        #expect(AXID.all.contains(ids.selectionCard) && AXID.all.contains(AXID.Galaxy.miniChartOpen))
        // The card's buttons are the context menu's items, so both follow the same rules (MAP-053).
        let s = MapFx.state(.modern, seed: 11)
        let snapshot = MapSnapshot.make(state: s, generation: 0, route: nil)
        let other = try #require(snapshot.systems.indices.first { $0 != snapshot.currentSystem })
        let items = MapContextMenu.items(for: .system(other), snapshot: snapshot, isModal: false)
        #expect(items.contains { $0.kind == .setTarget } && items.contains { $0.kind == .track } && items.contains { $0.kind == .plotRoute })
        let view = try Self.source("Map/GalaxyMapView.swift")
        #expect(view.contains("MapContextMenu.items(for: hit, snapshot: snapshot, isModal: session.isInputLocked) : []"))
        #expect(view.contains("if scope == .miniChart { session.selectedSection = .galaxy }") && view.contains("AXID.Galaxy.miniChartOpen"))
    }

    @Test("UI-PTR-014 UI-PTR-015 sheet chips 1 / 5 / All and the money slider's step")
    func sheetsAndSliders() throws {
        #expect(SheetChip.allCases.map { $0.quantity(in: 1...12) } == [1, 5, 12])
        #expect(SheetChip.allCases.map { $0.quantity(in: 1...3) } == [1, 3, 3])
        #expect(SheetChip.allCases.map { $0.quantity(in: 2...2) } == [2, 2, 2])
        #expect(AXID.quantityChip("decision.trade.quantity", .all) == "decision.trade.quantity.chip.all")
        let sheets = try Self.source("Views/Encounter/EncounterSheets.swift")
        #expect(sheets.components(separatedBy: "QuantityChips(").count - 1 == 3, "plunder, trade in orbit and make room")
        #expect((try Self.source("Views/Sections/MarketSectionView.swift")).contains("QuantityChips(value: $quantity"))
        #expect([0, 50, 100, 101, 1000, 1001, 25000, 100_000, 1_000_000].map(BankSlider.step(limit:)) == [1, 1, 1, 10, 10, 10, 1000, 1000, 10000])
        for limit in [7, 480, 12_345, 987_654] {
            let step = BankSlider.step(limit: limit)
            #expect(limit / step <= 100 && (step == 1 || limit / (step / 10) > 100))
        }
        #expect((try Self.source("Views/Sections/BankSectionView.swift")).contains("step: Double(BankSlider.step(limit: limit))"))
        // Small custom targets carry the modifier.
        for (file, needle) in [("Views/Encounter/EncounterView.swift", ".pointerTarget()  // UI-PTR-015"),
                               ("Map/MapHUDViews.swift", ".pointerTarget()  // UI-PTR-013"),
                               ("Accessibility/ParsecTips.swift", "Image(systemName: \"xmark\").pointerTarget()"),
                               ("Views/NewGame/NewGameWizard.swift", "Image(systemName: \"minus\").pointerTarget()")] {
            #expect((try Self.source(file)).contains(needle), "\(file)")
        }
    }

    @Test("UI-PTR-016 UI-PTR-017 standard gestures only; hover content has a tap twin; the SDK has no touch-native switch to adopt")
    func touch() throws {
        var gestures = Set<String>()
        let enumerator = FileManager.default.enumerator(at: Self.appRoot, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            for name in ["DragGesture(", "MagnifyGesture(", "RotateGesture(", "LongPressGesture(", "SpatialTapGesture(", "NSIsTouchNative",
                         "directTouchSystemGesturesDisabled"] where text.contains(name) && !url.path.hasSuffix("Tests.swift") {
                gestures.insert(name)
            }
        }
        // Drag pans the map, pinch zooms it; nothing rotates, long-presses (the system's touch and hold opens context menus) or
        // overrides the system's touch gestures.
        #expect(gestures == ["DragGesture(", "MagnifyGesture("], "\(gestures)")
        // A disabled control's reason is in its help tag (hover) and in its accessibility hint or on-screen text (tap, VoiceOver).
        let crew = try Self.source("Views/Sections/CrewSectionView.swift")
        #expect(crew.contains("Text(ReasonText.text(for: blocker)).scaledFont(.caption)"))
    }
}
