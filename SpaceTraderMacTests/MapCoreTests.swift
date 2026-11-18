// SPDX-License-Identifier: GPL-2.0-or-later
import CoreGraphics
import Foundation
import ParsecEngine
import ParsecInsights
import Testing
@testable import ParsecMerchant

/// Fixtures for the galaxy chart's pure core (MAP §1–§15).
@MainActor
enum MapFx {
    static func state(_ r: RulesetID = .modern, seed: UInt64 = 1) -> GameState {
        GameState(config: NewGameConfig(commanderName: "Map", ruleset: r, seed: seed))
    }

    static func snapshot(_ st: GameState, generation: Int = 0, route: Route? = nil) -> MapSnapshot {
        MapSnapshot.make(state: st, generation: generation, route: route)
    }

    static let view = CGSize(width: 800, height: 600)

    static func projected(_ s: MapSnapshot, zoom: Double = 1, size: CGSize = view) -> ProjectedMap {
        ProjectedMap.make(snapshot: s, viewport: MapViewport.fitGalaxy(MapBounds(s)).with(zoom: zoom), viewSize: size)
    }

    /// A hand-placed snapshot: systems at the given coordinates, the first one current.
    static func placed(_ points: [(Int, Int)], wormholes: [Int] = [], fuel: Int = 14) -> MapSnapshot {
        var s = snapshot(state())
        s.systems = points.enumerated().map { i, p in
            var m = s.systems[i]
            m.index = i
            m.x = p.0
            m.y = p.1
            m.size = .medium
            m.wormholeDestination = nil
            return m
        }
        s.wormholes = wormholes
        for (k, w) in wormholes.enumerated() { s.systems[w].wormholeDestination = wormholes[(k + 1) % wormholes.count] }
        s.currentSystem = 0
        s.warpSystem = 0
        s.trackedSystem = nil
        s.targetWormhole = nil
        s.fuel = fuel
        return s
    }
}

extension MapViewport {
    func with(zoom z: Double) -> MapViewport { MapViewport(zoom: z, center: center) }
}

@MainActor
@Suite("Galaxy chart: snapshot, projection, viewport")
struct MapSnapshotViewportTests {
    @Test("MAP-001 the snapshot carries the state's map facts")
    func snapshotFields() {
        var st = MapFx.state()
        st.warpSystem = st.destinations[0]
        st.trackedSystem = 5
        let s = MapFx.snapshot(st, generation: 7)
        #expect(s.generation == 7 && s.galaxyWidth == 154 && s.galaxyHeight == 110 && s.distanceRule == .floor)
        #expect(s.systems.count == st.galaxy.systems.count && s.wormholes == st.galaxy.wormholes)
        #expect(s.currentSystem == st.commander.currentSystem && s.warpSystem == st.warpSystem && s.trackedSystem == 5)
        #expect(s.fuel == st.commander.ship.fuel && s.fuelCapacity == st.fuelCapacity && s.isDocked && s.route == nil)
        #expect(s.wormholeSelectionScope == .anyWormhole)
        #expect(MapFx.snapshot(MapFx.state(.palm122)).wormholeSelectionScope == .currentSystemOnly)
        for (i, sys) in s.systems.enumerated() {
            #expect(sys.name == st.ruleset.tables.systemNames[i] && sys.x == st.galaxy.systems[i].x)
            #expect(sys.wormholeDestination == st.galaxy.wormholeDestination(from: i))
        }
    }

    @Test("MAP-002 fairness: hidden fields never change the snapshot")
    func fairness() throws {
        let a = MapFx.state()
        var b = a
        let hidden = try #require(b.galaxy.systems.indices.first { !b.galaxy.systems[$0].visited })
        b.galaxy.systems[hidden].specialResource = a.galaxy.systems[hidden].specialResource == .desert ? .lifeless : .desert
        b.galaxy.systems[hidden].specialEvent = .moon
        b.galaxy.systems[hidden].tradeItems = b.galaxy.systems[hidden].tradeItems.map { $0 + 7 }
        b.galaxy.systems[hidden].countDown += 3
        b.buyPrices = b.buyPrices.map { $0 + 1 }
        b.rng = RNGState(kind: b.ruleset.rngKind, seed: 999)
        #expect(MapFx.snapshot(a) == MapFx.snapshot(b))
        #expect(MapFx.snapshot(a).systems[hidden].knownResource == nil)
    }

    @Test("MAP-004 inRange equals destinationOK and distance the ruleset distance, for every fuel level")
    func inRangeMatchesEngine() {
        for r in RulesetID.allCases {
            var st = MapFx.state(r)
            for fuel in 0...st.fuelCapacity {
                st.commander.ship.fuel = fuel
                let s = MapFx.snapshot(st)
                #expect(s.systems.filter(\.inRange).map(\.index) == st.destinations)
                for i in s.systems.indices {
                    #expect(s.systems[i].distance == GalaxyGenerator.distance(st.galaxy.systems[i], st.currentSystem,
                                                                               rule: st.ruleset.flags.distance))
                }
            }
        }
    }

    @Test("MAP-005 projection round trips")
    func projectionRoundTrip() {
        var g = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let p = MapProjection(scale: Double.random(in: 0.5...60, using: &g),
                                  origin: CGPoint(x: Double.random(in: -10...150, using: &g), y: Double.random(in: -10...100, using: &g)))
            let pt = CGPoint(x: Double.random(in: -50...200, using: &g), y: Double.random(in: -50...200, using: &g))
            let back = p.toGalaxy(p.toView(pt))
            #expect(abs(back.x - pt.x) < 1e-9 && abs(back.y - pt.y) < 1e-9)
        }
        let p = MapProjection(scale: 2, origin: CGPoint(x: 1, y: 1))
        #expect(p.toView(CGPoint(x: 3, y: 5)) == CGPoint(x: 4, y: 8))
    }

    @Test("MAP-006 content rectangle per ruleset from the tables")
    func contentRect() {
        for r in RulesetID.allCases {
            let t = Ruleset.named(r).tables
            let c = MapBounds(galaxyWidth: t.galaxyWidth, galaxyHeight: t.galaxyHeight).content
            #expect(c == CGRect(x: -4, y: -4, width: Double(t.galaxyWidth) + 8, height: Double(t.galaxyHeight) + 8))
        }
        #expect(MapFx.snapshot(MapFx.state(.palm122)).galaxyWidth == 150)
    }

    @Test("MAP-007 fit scale golden values")
    func fitScale() {
        let modern = MapBounds(galaxyWidth: 154, galaxyHeight: 110).content
        #expect(abs(MapProjection.fitScale(viewSize: MapFx.view, content: modern) - 800.0 / 162) < 1e-12)
        let palm = MapBounds(galaxyWidth: 150, galaxyHeight: 110).content
        #expect(abs(MapProjection.fitScale(viewSize: MapFx.view, content: palm) - 800.0 / 158) < 1e-12)
    }

    @Test("MAP-008 resizing keeps zoom, centre and the galaxy point at the view centre")
    func resize() {
        let b = MapBounds(galaxyWidth: 154, galaxyHeight: 110)
        let v = MapViewport(zoom: 3, center: CGPoint(x: 40, y: 60))
        for size in [CGSize(width: 800, height: 600), CGSize(width: 1300, height: 700), CGSize(width: 640, height: 480)] {
            let p = v.projection(viewSize: size, bounds: b)
            let mid = p.toGalaxy(CGPoint(x: size.width / 2, y: size.height / 2))
            #expect(abs(mid.x - 40) < 1e-9 && abs(mid.y - 60) < 1e-9)
            #expect(abs(p.scale - MapProjection.fitScale(viewSize: size, content: b.content) * 3) < 1e-12)
        }
    }

    @Test("MAP-009 zoom and centre clamps")
    func clamps() {
        let b = MapBounds(galaxyWidth: 154, galaxyHeight: 110)
        #expect(MapViewport(zoom: 0.2, center: CGPoint(x: 10, y: 10)).clamped(b) == .fitGalaxy(b))
        #expect(MapViewport(zoom: 50, center: CGPoint(x: 10, y: 10)).clamped(b).zoom == 12)
        let c = MapViewport(zoom: 4, center: CGPoint(x: -30, y: 500)).clamped(b)
        #expect(c.center == CGPoint(x: 0, y: 110))
        #expect(MapViewport(zoom: 4, center: CGPoint(x: 200, y: -1)).clamped(b).center == CGPoint(x: 154, y: 0))
        #expect(MapViewport.fitGalaxy(b).center == CGPoint(x: 77, y: 55))
    }

    @Test("MAP-010 zoom keeps the anchor fixed; pan moves the centre by −delta / scale")
    func zoomAnchorAndPan() {
        let b = MapBounds(galaxyWidth: 154, galaxyHeight: 110)
        let v = MapViewport(zoom: 2, center: CGPoint(x: 70, y: 50))
        let anchor = CGPoint(x: 500, y: 250)
        let before = v.projection(viewSize: MapFx.view, bounds: b).toGalaxy(anchor)
        let z = v.zoomed(by: 1.5, anchor: anchor, viewSize: MapFx.view, bounds: b)
        let after = z.projection(viewSize: MapFx.view, bounds: b).toGalaxy(anchor)
        #expect(z.zoom == 3 && abs(before.x - after.x) < 1e-9 && abs(before.y - after.y) < 1e-9)
        let s = v.scale(viewSize: MapFx.view, bounds: b)
        let p = v.panned(byViewDelta: CGSize(width: 40, height: -20), viewSize: MapFx.view, bounds: b)
        #expect(abs(p.center.x - (70 - 40 / s)) < 1e-9 && abs(p.center.y - (50 + 20 / s)) < 1e-9)
    }

    @Test("MAP-011 Fit Galaxy and Fit Range")
    func fits() {
        var st = MapFx.state()
        st.commander.ship.fuel = 14
        let s = MapFx.snapshot(st)
        let v = MapViewport.fitRange(snapshot: s, viewSize: MapFx.view)
        let r = max(MapRange.ringRadius(s), 5)
        let scale = v.scale(viewSize: MapFx.view, bounds: MapBounds(s))
        #expect(abs(2 * r * 1.2 * scale - 600) < 1e-6)
        #expect(v.center == CGPoint(x: s.current.x, y: s.current.y) || v.zoom == 12)
        st.commander.ship.fuel = 0
        let empty = MapViewport.fitRange(snapshot: MapFx.snapshot(st), viewSize: MapFx.view)
        #expect(abs(2 * 5 * 1.2 * empty.scale(viewSize: MapFx.view, bounds: MapBounds(s)) - 600) < 1e-6)
        #expect(MapViewport.fitGalaxy(MapBounds(s)).zoom == 1)
    }

    @Test("MAP-012 centring raises the zoom to at least 3")
    func centred() {
        let s = MapFx.snapshot(MapFx.state())
        let v = MapViewport.fitGalaxy(MapBounds(s)).centered(on: 10, snapshot: s)
        #expect(v.zoom == 3 && v.center == CGPoint(x: s.systems[10].x, y: s.systems[10].y))
        #expect(MapViewport(zoom: 8, center: .zero).centered(on: 10, snapshot: s).zoom == 8)
    }
}

@MainActor
@Suite("Galaxy chart: hit testing, layers, glyphs, rings, wormholes")
struct MapDrawingTests {
    @Test("MAP-019 nearest candidate within its radius; ties go to systems then lower index")
    func hitGolden() {
        let s = MapFx.placed([(10, 10), (12, 10), (40, 40)], wormholes: [2])
        let p = MapProjection(scale: 10, origin: .zero)
        let m = GlyphMetrics(zoom: 1)
        let size = CGSize(width: 800, height: 600)
        #expect(MapHitTester.hit(at: CGPoint(x: 101, y: 100), snapshot: s, projection: p, metrics: m, viewSize: size) == .system(0))
        #expect(MapHitTester.hit(at: CGPoint(x: 118, y: 100), snapshot: s, projection: p, metrics: m, viewSize: size) == .system(1))
        let half = MapProjection(scale: 5, origin: .zero)
        #expect(MapHitTester.hit(at: CGPoint(x: 55, y: 50), snapshot: s, projection: half, metrics: m, viewSize: size) == .system(0))
        let w = MapGeometry.wormholeGlyphCenter(2, snapshot: s, projection: p, metrics: m)
        #expect(MapHitTester.hit(at: w, snapshot: s, projection: p, metrics: m, viewSize: size) == .wormhole(2))
    }

    @Test("MAP-020 UI-PTR-013 hit radii: the glyph plus a margin, never under 18 pt, so every glyph is a 36 pt target")
    func hitRadii() {
        #expect(GlyphMetrics.minimumHitRadius == 18)
        for zoom in [1.0, 2, 4, 8] {
            let m = GlyphMetrics(zoom: zoom)
            for size in SystemSize.allCases {
                #expect(m.systemHitRadius(size) == max(m.radius(size) + 4, 18))
                #expect(m.systemHitRadius(size) >= 18)
            }
            #expect(m.wormholeHitRadius == max(m.wormholeRadius + 3, 18))
        }
        let m = GlyphMetrics(zoom: 1)
        #expect(m.systemHitRadius(.tiny) == 18 && m.wormholeHitRadius == 18)
        // A glyph larger than the minimum keeps its own margin.
        let big = GlyphMetrics(zoom: 8)
        if big.radius(.huge) + 4 > 18 { #expect(big.systemHitRadius(.huge) == big.radius(.huge) + 4) }
    }

    @Test("MAP-021 property: every system and wormhole centre hits itself at Fit Galaxy", arguments: RulesetID.allCases)
    func hitProperty(_ r: RulesetID) {
        for seed in UInt64(1)...200 {
            let s = MapFx.snapshot(MapFx.state(r, seed: seed))
            let pm = MapFx.projected(s)
            for sys in s.systems {
                let hit = MapHitTester.hit(at: pm.centers[sys.index], snapshot: s, projection: pm.projection, metrics: pm.metrics,
                                           viewSize: MapFx.view)
                let same = s.systems.first { $0.x == sys.x && $0.y == sys.y }?.index
                #expect(hit == .system(same ?? sys.index))
            }
            for w in s.wormholes {
                let c = MapGeometry.wormholeGlyphCenter(w, snapshot: s, projection: pm.projection, metrics: pm.metrics)
                let hit = MapHitTester.hit(at: c, snapshot: s, projection: pm.projection, metrics: pm.metrics, viewSize: MapFx.view)
                if case let .system(i) = hit {
                    let d = hypot(pm.centers[i].x - c.x, pm.centers[i].y - c.y)
                    #expect(d < pm.metrics.wormholeHitRadius || d <= pm.metrics.systemHitRadius(s.systems[i].size))
                } else {
                    #expect(hit == .wormhole(w))
                }
            }
        }
    }

    @Test("MAP-022 outside the view or within no radius returns nil; the mini chart uses its own projection")
    func misses() {
        let s = MapFx.placed([(10, 10), (40, 40)])
        let p = MapProjection(scale: 10, origin: .zero)
        let m = GlyphMetrics(zoom: 1)
        #expect(MapHitTester.hit(at: CGPoint(x: -1, y: 5), snapshot: s, projection: p, metrics: m, viewSize: MapFx.view) == nil)
        #expect(MapHitTester.hit(at: CGPoint(x: 250, y: 250), snapshot: s, projection: p, metrics: m, viewSize: MapFx.view) == nil)
        let full = MapFx.snapshot(MapFx.state())
        let mini = MapViewModel.miniChartViewport(snapshot: full, viewSize: CGSize(width: 400, height: 240))
        let pm = ProjectedMap.make(snapshot: full, viewport: mini, viewSize: CGSize(width: 400, height: 240))
        #expect(MapHitTester.hit(at: pm.centers[full.currentSystem], snapshot: full, projection: pm.projection, metrics: pm.metrics,
                                 viewSize: CGSize(width: 400, height: 240)) == .system(full.currentSystem))
    }

    @Test("MAP-023 layer order, back to front")
    func layerOrder() {
        #expect(MapLayer.allCases == [.background, .heatmap, .searchDimming, .fullTankRing, .rangeRing, .wormholeLinks, .route,
                                      .trackedBearing, .systems, .wormholeGlyphs, .markers, .labels])
        #expect(!MapLayer.m8.contains(.heatmap) && MapLayer.m8.count == 11)
    }

    @Test("MAP-025 culling: glyphs wholly outside the view plus 16 pt are skipped")
    func culling() {
        let s = MapFx.snapshot(MapFx.state())
        #expect(MapFx.projected(s).visible.count == s.systems.count)
        let zoomed = ProjectedMap.make(snapshot: s, viewport: MapViewport(zoom: 8, center: CGPoint(x: s.current.x, y: s.current.y)),
                                       viewSize: MapFx.view)
        #expect(zoomed.visible.count < s.systems.count / 2 && zoomed.visible.contains(s.currentSystem))
        for i in zoomed.visible {
            let c = zoomed.centers[i]
            #expect(c.x > -60 && c.x < 860 && c.y > -60 && c.y < 660)
        }
    }

    @Test("MAP-026 label policy: priorities, zoom thresholds, captions and greedy collisions")
    func labels() throws {
        var st = MapFx.state()
        st.warpSystem = st.destinations[0]
        let far = try #require(st.galaxy.systems.indices.first { !st.destinationOK($0) && $0 != st.commander.currentSystem })
        st.trackedSystem = far
        let s = MapFx.snapshot(st)
        let p = MapFx.projected(s).projection
        let low = MapLabelPolicy.labels(snapshot: s, projection: p, zoom: 1, hovered: 3)
        #expect(Set(low.map(\.system)).isSubset(of: [s.currentSystem, s.warpSystem, st.trackedSystem ?? -1, 3]))
        #expect(low.first?.system == s.currentSystem && low.allSatisfy { $0.caption == nil })
        let mid = MapLabelPolicy.labels(snapshot: s, projection: p, zoom: 2, hovered: nil)
        #expect(mid.count > low.count)
        for (i, a) in mid.enumerated() { for b in mid[(i + 1)...] { #expect(!a.rect.intersects(b.rect)) } }
        #expect(MapLabelPolicy.labels(snapshot: s, projection: p, zoom: 2, hovered: nil) == mid)
        let high = MapLabelPolicy.labels(snapshot: s, projection: p, zoom: 6, hovered: nil)
        #expect(high.allSatisfy { $0.caption != nil })
    }

    @Test("MAP-028 glyph shape and radius by size, visit state and zoom")
    func glyphStyle() {
        var s = MapFx.placed([(10, 10), (20, 20)])
        for (size, r) in [(SystemSize.tiny, 2.5), (.small, 3), (.medium, 3.5), (.large, 4), (.huge, 4.5)] {
            s.systems[1].size = size
            s.systems[1].visited = true
            #expect(MapGlyphStyle.style(for: s.systems[1], in: s, differentiateWithoutColor: false).radius == r)
            #expect(MapGlyphStyle.style(for: s.systems[1], in: s, differentiateWithoutColor: false, zoom: 9).radius == r * 2)
            #expect(MapGlyphStyle.style(for: s.systems[1], in: s, differentiateWithoutColor: false).filled)
            s.systems[1].visited = false
            #expect(!MapGlyphStyle.style(for: s.systems[1], in: s, differentiateWithoutColor: false).filled)
        }
        #expect(GlyphMetrics(zoom: 2).multiplier == 2.0.squareRoot())
    }

    @Test("MAP-029 markers: current, target, tracked, quest; the origin wormhole of a wormhole target")
    func markers() {
        var s = MapFx.placed([(10, 10), (20, 20), (30, 30)], wormholes: [0, 2])
        s.warpSystem = 2
        s.targetWormhole = 0
        s.trackedSystem = 1
        s.systems[1].questKinds = [.japoriDeliver]
        let st = { (i: Int) in MapGlyphStyle.style(for: s.systems[i], in: s, differentiateWithoutColor: false).markers }
        #expect(st(0) == [.current] && st(1) == [.tracked, .quest] && st(2) == [.target])
        s.warpSystem = 0
        #expect(!st(0).contains(.target))
    }

    @Test("MAP-030 out of range at 55%; Differentiate Without Color adds a halo in range")
    func opacityAndHalo() {
        var s = MapFx.placed([(10, 10), (20, 20), (90, 90)])
        s.systems[1].inRange = true
        s.systems[2].inRange = false
        let g = { (i: Int, d: Bool) in MapGlyphStyle.style(for: s.systems[i], in: s, differentiateWithoutColor: d) }
        #expect(g(2, false).opacity == 0.55 && g(1, false).opacity == 1 && g(0, false).opacity == 1)
        #expect(g(1, true).halo && !g(1, false).halo && !g(2, true).halo)
    }

    @Test("MAP-031 tech level and government are in the caption and accessibility label, not the glyph")
    func techNotInGlyph() {
        var s = MapFx.placed([(10, 10), (20, 20)])
        let a = MapGlyphStyle.style(for: s.systems[1], in: s, differentiateWithoutColor: false)
        s.systems[1].techLevel = .hiTech
        s.systems[1].politics = .anarchy
        #expect(MapGlyphStyle.style(for: s.systems[1], in: s, differentiateWithoutColor: false) == a)
        #expect(MapAccessibility.label(for: 1, snapshot: s).contains("Hi-Tech") && MapAccessibility.label(for: 1, snapshot: s).contains("Anarchy"))
    }

    @Test("MAP-034 the range ring encloses exactly the systems in non-wormhole range")
    func rangeRing() {
        for r in RulesetID.allCases {
            for seed in UInt64(1)...20 {
                var st = MapFx.state(r, seed: seed)
                for fuel in [1, 7, st.fuelCapacity] {
                    st.commander.ship.fuel = fuel
                    let s = MapFx.snapshot(st)
                    let radius = MapRange.ringRadius(s)
                    for sys in s.systems where sys.index != s.currentSystem {
                        let d = Double(sys.squaredDistance).squareRoot()
                        let inside = d <= radius + 1e-9
                        #expect(inside == (sys.distance <= fuel), "system \(sys.index) fuel \(fuel) \(r)")
                    }
                }
                st.commander.ship.fuel = 0
                #expect(MapRange.ringRadius(MapFx.snapshot(st)) == 0)
            }
        }
    }

    @Test("MAP-035 deliberate deviation: radius is the true boundary, not the fuel value")
    func trueBoundary() {
        var st = MapFx.state()
        st.commander.ship.fuel = 14
        #expect(abs(MapRange.ringRadius(MapFx.snapshot(st)) - 224.0.squareRoot()) < 1e-12)
        var palm = MapFx.state(.palm122)
        palm.commander.ship.fuel = 14
        #expect(abs(MapRange.ringRadius(MapFx.snapshot(palm)) - 210.0.squareRoot()) < 1e-12)
    }

    @Test("MAP-036 the full-tank ring is hidden at a full tank")
    func fullTankRing() {
        var st = MapFx.state()
        st.commander.ship.fuel = st.fuelCapacity
        #expect(MapRange.fullTankRadius(MapFx.snapshot(st)) == nil)
        st.commander.ship.fuel = 3
        let cap = st.fuelCapacity
        #expect(MapRange.fullTankRadius(MapFx.snapshot(st)) == Double((cap + 1) * (cap + 1) - 1).squareRoot())
    }

    @Test("MAP-037 the vortex sits glyphRadius + 6 pt right of its system")
    func vortexPlacement() {
        let s = MapFx.placed([(10, 10), (30, 30)], wormholes: [0, 1])
        let p = MapProjection(scale: 5, origin: .zero)
        let m = GlyphMetrics(zoom: 1)
        #expect(MapGeometry.wormholeGlyphCenter(0, snapshot: s, projection: p, metrics: m) == CGPoint(x: 50 + 3.5 + 6, y: 50))
    }

    @Test("MAP-038 one link per ring step; arcs bow left of the travel direction")
    func links() {
        let st = MapFx.state()
        let s = MapFx.snapshot(st)
        let links = MapGeometry.wormholeLinks(s)
        #expect(links.count == st.galaxy.wormholes.count)
        for (k, l) in links.enumerated() {
            #expect(l.origin == st.galaxy.wormholes[k] && l.destination == st.galaxy.wormholeDestination(from: l.origin))
        }
        let a = MapGeometry.arc(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0))
        #expect(a.control == CGPoint(x: 50, y: -15))
        let back = MapGeometry.arc(from: CGPoint(x: 100, y: 0), to: CGPoint(x: 0, y: 0))
        #expect(back.control == CGPoint(x: 50, y: 15))
    }

    @Test("MAP-041 bearing geometry: dotted line in the galaxy, 25 pt triangle in the mini chart")
    func bearing() throws {
        var s = MapFx.placed([(10, 10), (40, 50)])
        #expect(MapGeometry.trackedBearing(s, projection: MapProjection(scale: 1, origin: .zero)) == nil)
        s.trackedSystem = 1
        let line = try #require(MapGeometry.trackedBearing(s, projection: MapProjection(scale: 1, origin: .zero)))
        #expect(line.0 == CGPoint(x: 10, y: 10) && line.1 == CGPoint(x: 40, y: 50))
        let tri = try #require(MapGeometry.bearingTriangle(from: CGPoint(x: 0, y: 0), toward: CGPoint(x: 30, y: 40)))
        #expect(abs(tri[0].x - 15) < 1e-9 && abs(tri[0].y - 20) < 1e-9)
        #expect(MapGeometry.bearingTriangle(from: .zero, toward: .zero) == nil)
        s.trackedSystem = 0
        #expect(MapGeometry.trackedBearing(s, projection: MapProjection(scale: 1, origin: .zero)) == nil)
    }

    @Test("MAP-066 route polyline points; a wormhole hop follows its link arc")
    func routeSegments() {
        var s = MapFx.placed([(10, 10), (20, 10), (60, 60)], wormholes: [1, 2])
        s.route = Route(from: 0, to: 2, objective: .fewestJumps,
                        hops: [RouteHop(from: 0, to: 1, viaWormhole: false, distance: 10, fuelBefore: 14, refuelUnits: 0, refuelCost: 0,
                                        cost: 10),
                               RouteHop(from: 1, to: 2, viaWormhole: true, distance: 64, fuelBefore: 4, refuelUnits: 0, refuelCost: 0,
                                        cost: 25)],
                        totalJumps: 2, totalParsecs: 10, estimatedCredits: 35, totalRefuelUnits: 0)
        let p = MapProjection(scale: 2, origin: .zero)
        let segs = MapGeometry.routeSegments(s, projection: p, metrics: GlyphMetrics(zoom: 1))
        #expect(segs.count == 2 && segs[0].start == CGPoint(x: 20, y: 20) && segs[0].end == CGPoint(x: 40, y: 20) && segs[0].control == nil)
        #expect(segs[0].isNext && !segs[1].isNext && segs[1].hop == 2 && segs[1].control != nil && segs[1].end == CGPoint(x: 120, y: 120))
        #expect(MapGeometry.routeStops(s) == [1, 2])
    }

    @Test("MAP-088 the projected map rebuilds on pan, zoom and selectTarget, never on hover")
    func projectedCache() throws {
        let session = try TestSessions.playing()
        let cache = ProjectedMapCache()
        let ui = MapViewModel(scope: .galaxy)
        var s = try #require(session.mapSnapshot)
        var v = MapViewport.fitGalaxy(MapBounds(s))
        _ = cache.map(snapshot: s, viewport: v, viewSize: MapFx.view)
        for k in 0..<20 { ui.hover(at: CGPoint(x: k, y: k), hit: .system(k)) }
        _ = cache.map(snapshot: s, viewport: v, viewSize: MapFx.view)
        #expect(cache.builds == 1)
        v = v.zoomed(by: 2, viewSize: MapFx.view, bounds: MapBounds(s))
        _ = cache.map(snapshot: s, viewport: v, viewSize: MapFx.view)
        v = v.panned(byViewDelta: CGSize(width: 30, height: 0), viewSize: MapFx.view, bounds: MapBounds(s))
        _ = cache.map(snapshot: s, viewport: v, viewSize: MapFx.view)
        #expect(cache.builds == 3)
        session.send(.selectTarget(s.systems.indices.first { $0 != s.currentSystem } ?? 0))
        s = try #require(session.mapSnapshot)
        _ = cache.map(snapshot: s, viewport: v, viewSize: MapFx.view)
        #expect(cache.builds == 4)
    }

    @Test("MAP-089 hover state lives in the view model, apart from the projected map")
    func hoverOverlaySeparate() {
        let ui = MapViewModel(scope: .galaxy)
        let before = ui.cache.builds
        ui.hover(at: CGPoint(x: 5, y: 5), hit: .system(3))
        #expect(ui.hoverHit == .system(3) && ui.cache.builds == before)
        ui.pulse(4)
        #expect(ui.pulseSystem == 4 && ui.cache.builds == before)
    }
}
