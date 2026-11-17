// SPDX-License-Identifier: GPL-2.0-or-later
import CoreGraphics
import Foundation
import ParsecEngine
import ParsecInsights
import Testing
@testable import ParsecMerchant

@MainActor
@Suite("Galaxy chart: hover card, actions, search, accessibility")
struct MapInteractionTests {
    @Test("MAP-044 hover card placement stays inside the map at all four edges")
    func placement() {
        let b = CGRect(x: 0, y: 0, width: 800, height: 600)
        let card = CGSize(width: 250, height: 120)
        #expect(HoverCardPlacement.frame(anchor: CGPoint(x: 100, y: 100), cardSize: card, bounds: b).origin == CGPoint(x: 112, y: 112))
        #expect(HoverCardPlacement.frame(anchor: CGPoint(x: 700, y: 100), cardSize: card, bounds: b).origin == CGPoint(x: 438, y: 112))
        #expect(HoverCardPlacement.frame(anchor: CGPoint(x: 100, y: 550), cardSize: card, bounds: b).origin == CGPoint(x: 112, y: 418))
        #expect(HoverCardPlacement.frame(anchor: CGPoint(x: 5, y: 5), cardSize: card, bounds: b).minX >= 0)
        let tight = HoverCardPlacement.frame(anchor: CGPoint(x: 130, y: 70), cardSize: card, bounds: CGRect(x: 0, y: 0, width: 260, height: 140))
        #expect(CGRect(x: 0, y: 0, width: 260, height: 140).contains(tight))
    }

    @Test("MAP-044 the card shows after the rest and closes on exit and generation changes")
    func hoverDelay() async throws {
        let ui = MapViewModel(scope: .galaxy)
        ui.hover(at: CGPoint(x: 1, y: 1), hit: .system(2))
        #expect(ui.cardHit == nil)
        let start = ContinuousClock.now
        while ui.cardHit == nil, ContinuousClock.now - start < .seconds(10) { try await Task.sleep(for: .milliseconds(20)) }
        #expect(ui.cardHit == .system(2) && ContinuousClock.now - start >= MapViewModel.hoverDelay)
        ui.closeCard()
        #expect(ui.cardHit == nil)
        ui.hover(at: nil, hit: nil)
        #expect(ui.hoverHit == nil)
    }

    @Test("MAP-045 hover card rows for a system in range, out of range and unvisited")
    func cardRows() throws {
        var st = MapFx.state()
        let inRange = st.destinations[0]
        let far = try #require(st.galaxy.systems.indices.first { !st.destinationOK($0) && !st.galaxy.systems[$0].visited })
        st.warpSystem = inRange
        let s = MapFx.snapshot(st)
        let near = HoverCardModel.make(system: s.systems[inRange], snapshot: s, preview: st.warpTargetPreview(inRange), jumps: .count(1))
        #expect(near.title == s.systems[inRange].name && near.tags.contains("Target"))
        #expect(near.rows.contains(MapText.parsecs(s.systems[inRange].distance)))
        #expect(near.rows.contains { $0.hasPrefix("In range") } && near.rows.contains("1 jump"))
        #expect(near.rows.contains { $0.hasPrefix("Warp costs") })
        let out = HoverCardModel.make(system: s.systems[far], snapshot: s, preview: st.warpTargetPreview(far), jumps: .unreachable,
                                      questTitles: ["Q"])
        #expect(out.rows.contains("Out of range") && out.rows.contains("Unknown") && out.rows.contains("Not visited"))
        #expect(out.rows.contains("Can't be reached with a full tank") && out.tags == ["Q"] && !out.rows.contains { $0.hasPrefix("Warp costs") })
        #expect(HoverCardModel.make(system: s.systems[far], snapshot: s, preview: st.warpTargetPreview(far), jumps: .computing).rows.last == "…")
        #expect(HoverCardModel.make(system: s.systems[far], snapshot: s, preview: st.warpTargetPreview(far), jumps: .count(3)).rows.last == "3 jumps")
    }

    @Test("MAP-046 hover card for the current system and wormhole glyphs")
    func cardSpecial() throws {
        var st = MapFx.state()
        let s0 = MapFx.snapshot(st)
        let here = HoverCardModel.make(system: s0.current, snapshot: s0, preview: st.warpTargetPreview(s0.currentSystem), jumps: .count(0))
        #expect(here.rows.contains("You are here") && !here.rows.contains { $0.hasSuffix("parsecs") })
        let w = st.galaxy.wormholes[0]
        let dest = try #require(st.galaxy.wormholeDestination(from: w))
        let away = HoverCardModel.make(wormhole: w, snapshot: MapFx.snapshot(st), tax: 50)
        #expect(away.title == "Wormhole to \(st.ruleset.tables.systemNames[dest])")
        #expect(away.rows.contains("(from \(st.ruleset.tables.systemNames[w]) System)") || st.commander.currentSystem == w)
        st.commander.currentSystem = w
        let at = HoverCardModel.make(wormhole: w, snapshot: MapFx.snapshot(st), tax: 50)
        #expect(at.rows.contains("No fuel used · tax 50 cr."))
        st.commander.currentSystem = st.galaxy.systems.indices.first { !st.galaxy.wormholes.contains($0) } ?? 0
        #expect(HoverCardModel.make(wormhole: w, snapshot: MapFx.snapshot(st), tax: 50).rows.contains { $0.hasPrefix("Usable only from") })
    }

    @Test("MAP-042 track command: track, stop tracking, nothing for the current system")
    func trackCommand() {
        var s = MapFx.placed([(10, 10), (20, 20)])
        #expect(MapActions.trackCommand(for: 1, snapshot: s) == .track(1))
        s.trackedSystem = 1
        #expect(MapActions.trackCommand(for: 1, snapshot: s) == .track(nil))
        #expect(MapActions.trackCommand(for: 0, snapshot: s) == nil)
    }

    @Test("MAP-048 table: every hit kind × gesture × docked/locked")
    func actionTable() {
        let base = MapFx.placed([(10, 10), (20, 20), (30, 30)], wormholes: [0, 2])
        for hit in [MapHit.system(1), .wormhole(0), .wormhole(2), .system(0)] {
            for g in MapGesture.allCases {
                for (docked, modal) in [(true, false), (false, false), (true, true)] {
                    var s = base
                    s.isDocked = docked
                    let a = MapActions.action(for: hit, gesture: g, snapshot: s, isModal: modal)
                    if !docked || modal {
                        #expect(a == MapAction.none)
                        continue
                    }
                    switch g {
                    case .click: #expect(a == .send(MapActions.clickCommand(for: hit, snapshot: s)))
                    case .doubleClick: #expect(a == .sendAndFocusWarp(MapActions.clickCommand(for: hit, snapshot: s)))
                    case .optionClick:
                        #expect(a == (MapActions.trackCommand(for: hit.systemIndex, snapshot: s).map(MapAction.send) ?? MapAction.none))
                    }
                }
            }
        }
    }

    @Test("MAP-043 Palm uses the same pointer interaction: a second click never tracks")
    func palmGestures() {
        let s = MapFx.snapshot(MapFx.state(.palm122))
        let other = s.systems.indices.first { $0 != s.currentSystem } ?? 1
        #expect(MapActions.action(for: .system(other), gesture: .click, snapshot: s) == .send(.selectTarget(other)))
        var targeted = s
        targeted.warpSystem = other
        #expect(MapActions.action(for: .system(other), gesture: .click, snapshot: targeted) == .send(.selectTarget(other)))
        #expect(MapActions.action(for: .system(other), gesture: .optionClick, snapshot: targeted) == .send(.track(other)))
    }

    @Test("MAP-049 click on a system selects it, including the current system")
    func clickSystem() throws {
        let session = try TestSessions.playing()
        let s = try #require(session.mapSnapshot)
        let other = s.systems.indices.first { $0 != s.currentSystem } ?? 1
        #expect(MapActions.action(for: .system(other), gesture: .click, snapshot: s) == .send(.selectTarget(other)))
        #expect(MapActions.action(for: .system(s.currentSystem), gesture: .click, snapshot: s) == .send(.selectTarget(s.currentSystem)))
        session.send(.selectTarget(other))
        #expect(session.state?.warpSystem == other)
    }

    @Test("MAP-050 wormhole click follows wormholeSelectionScope and never produces a rejection")
    func clickWormhole() throws {
        for r in RulesetID.allCases {
            let st = MapFx.state(r)
            let s = MapFx.snapshot(st)
            for w in st.galaxy.wormholes {
                let cmd = MapActions.clickCommand(for: .wormhole(w), snapshot: s)
                if s.wormholeSelectionScope == .anyWormhole || w == s.currentSystem {
                    #expect(cmd == .selectWormhole(w))
                } else {
                    #expect(cmd == .selectTarget(w))
                }
                var e = GameEngine(state: st)
                #expect(e.perform(cmd).rejection == nil)
            }
        }
    }

    @Test("MAP-052 ⌥-click tracks and leaves the target; on a wormhole glyph it acts on its system")
    func optionClick() throws {
        let session = try TestSessions.playing()
        let s = try #require(session.mapSnapshot)
        let w = try #require(s.wormholes.first { $0 != s.currentSystem })
        #expect(MapActions.action(for: .wormhole(w), gesture: .optionClick, snapshot: s) == .send(.track(w)))
        let before = session.state?.warpSystem
        session.send(.track(w))
        #expect(session.state?.trackedSystem == w && session.state?.warpSystem == before)
    }

    @Test("MAP-053 context menu items for a hit, with disabled reasons; nothing for empty space")
    func contextMenu() {
        var s = MapFx.placed([(10, 10), (20, 20), (30, 30)], wormholes: [1, 2])
        #expect(MapContextMenu.items(for: nil, snapshot: s, isModal: false).isEmpty)
        let items = MapContextMenu.items(for: .wormhole(1), snapshot: s, isModal: false)
        #expect(items.map(\.kind) == [.setTarget, .track, .plotRoute, .useWormhole] && items.allSatisfy(\.isEnabled))
        #expect(items[1].title == "Track “\(s.systems[1].name)”" && items[2].destination == 1)
        let here = MapContextMenu.items(for: .system(0), snapshot: s, isModal: false)
        #expect(!here[1].isEnabled && !here[2].isEnabled && here[2].reason != nil && here.count == 3)
        s.isDocked = false
        #expect(MapContextMenu.items(for: .system(2), snapshot: s, isModal: false).allSatisfy { !$0.isEnabled && $0.reason != nil })
    }

    @Test("MAP-079 encounter lock: no actions, no enabled context items, Warp disabled; the snapshot still renders")
    func lock() throws {
        var s = MapFx.placed([(10, 10), (20, 20)])
        s.isDocked = false
        #expect(MapGesture.allCases.allSatisfy { MapActions.action(for: .system(1), gesture: $0, snapshot: s) == .none })
        #expect(MapContextMenu.items(for: .system(1), snapshot: s, isModal: true).allSatisfy { !$0.isEnabled })
        let st = MapFx.state()
        var transit = st
        transit.phase = .gameOver(.retired)
        #expect(!WarpButtonModel.make(state: transit, isModal: false).isEnabled)
        #expect(MapActions.isLocked(MapFx.snapshot(st), isModal: true))
        #expect(ProjectedMap.make(snapshot: s, viewport: .fitGalaxy(MapBounds(s)), viewSize: MapFx.view).visible.count == 2)
    }

    @Test("MAP-071 search: case and diacritic insensitive, prefix first, galaxy order, empty query with filters by distance")
    func search() {
        var s = MapFx.placed([(10, 10), (20, 20), (30, 30), (12, 12)])
        s.systems[0].name = "Sol"
        s.systems[1].name = "Absolom"
        s.systems[2].name = "Sölstice"
        s.systems[3].name = "Rest"
        for i in s.systems.indices { s.systems[i].distance = [0, 14, 28, 2][i] }
        #expect(SystemSearch.results(query: "sol", filters: [], snapshot: s) == [0, 2, 1])
        #expect(SystemSearch.results(query: "", filters: [], snapshot: s).isEmpty)
        #expect(SystemSearch.results(query: "", filters: [.unvisited, .visited], snapshot: s).isEmpty)
        s.systems = s.systems.map { var m = $0; m.visited = true; return m }
        #expect(SystemSearch.results(query: "", filters: [.visited], snapshot: s) == [0, 3, 1, 2])
        #expect(SystemSearch.suggestionLimit == 8)
    }

    @Test("MAP-072 filter membership")
    func filters() {
        var s = MapFx.placed([(10, 10), (20, 20), (30, 30)], wormholes: [1, 2])
        s.systems[0].visited = true
        s.systems[0].hasShipyard = true
        s.systems[1].inRange = true
        s.systems[2].questKinds = [.moon]
        let m = { (f: SystemSearchFilter) in s.systems.filter { f.matches($0, in: s) }.map(\.index) }
        #expect(m(.visited) == [0] && m(.unvisited) == [1, 2] && m(.inRange) == [1] && m(.questHere) == [2])
        #expect(m(.hasShipyard) == [0] && m(.wormhole) == [1, 2])
        s.hasShipyards = false
        #expect(!SystemSearchFilter.offered(s).contains(.hasShipyard))
        #expect(SystemSearch.dimmed(filters: [.inRange], snapshot: s) == [0, 2])
    }

    @Test("MAP-080 accessibility label and value")
    func axText() throws {
        var st = MapFx.state()
        let t = st.destinations[0]
        st.warpSystem = t
        st.trackedSystem = t
        let s = MapFx.snapshot(st)
        let label = MapAccessibility.label(for: t, snapshot: s)
        #expect(label.hasPrefix("\(s.systems[t].name), not visited, \(MapText.parsecs(s.systems[t].distance)), "))
        #expect(MapAccessibility.label(for: s.currentSystem, snapshot: s).contains("visited, current system"))
        #expect(MapAccessibility.value(for: t, snapshot: s).hasPrefix("target, tracked, in range"))
        #expect(MapAccessibility.order(s).first == s.currentSystem && MapAccessibility.order(s).count == s.systems.count)
    }

    @Test("MAP-083 rotor membership and order")
    func rotors() throws {
        var st = MapFx.state()
        st.quests.japori = QuestStatus.Japori.inTransit
        let s = MapFx.snapshot(st)
        let inRange = MapRotor.members(.inRange, snapshot: s)
        #expect(Set(inRange) == Set(st.destinations) && inRange == s.byDistance(inRange))
        #expect(MapRotor.members(.wormholes, snapshot: s) == st.galaxy.wormholes)
        #expect(!MapRotor.members(.questLocations, snapshot: s).isEmpty)
        #expect(MapRotor.members(.visited, snapshot: s).allSatisfy { s.systems[$0].visited && $0 != s.currentSystem })
        #expect(MapRotor.members(.unvisited, snapshot: s).count + MapRotor.members(.visited, snapshot: s).count == s.systems.count - 1)
        #expect(MapRotor.allCases.count == 5)
    }

    @Test("MAP-085 the target announcement")
    func announcement() {
        var st = MapFx.state()
        #expect(MapAccessibility.targetAnnouncement(MapFx.snapshot(st)) == nil)
        st.warpSystem = st.destinations[0]
        let s = MapFx.snapshot(st)
        #expect(MapAccessibility.targetAnnouncement(s) == "Target \(s.systems[st.warpSystem].name), \(MapText.parsecs(s.systems[st.warpSystem].distance))")
        st.warpSystem = st.galaxy.systems.indices.first { !st.destinationOK($0) && $0 != st.commander.currentSystem } ?? 0
        #expect(MapAccessibility.targetAnnouncement(MapFx.snapshot(st))?.hasSuffix("out of range") == true)
    }

    @Test("MAP-099 identifiers for all three scopes are in AXID.all, unique and scheme-conformant")
    func identifiers() {
        let all = AXID.all
        #expect(Set(all).count == all.count)
        for scope in MapScope.allCases {
            let ids = AXID.Map(scope)
            for id in [ids.map, ids.hoverCard, ids.zoomIn, ids.searchField, ids.routePanel, ids.system(119), ids.routeHop(1)] {
                #expect(all.contains(id) && id.range(of: AXID.pattern, options: .regularExpression) != nil)
            }
        }
        #expect(AXID.Map(.miniChart).map == AXID.Galaxy.miniChartMap && all.contains(AXID.Galaxy.windowRoot))
        #expect(all.contains("galaxy.root") && all.contains("sidebar.galaxy") && all.contains(AXID.Galaxy.bridgePlotRoute))
    }
}
