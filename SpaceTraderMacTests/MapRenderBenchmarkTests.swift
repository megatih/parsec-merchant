// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import ParsecInsights
import SwiftUI
import XCTest
@testable import ParsecMerchant

/// MAP-090: the Release map-render benchmark (run by scripts/bench-map.sh). Under Debug it is skipped.
@MainActor
final class MapRenderBenchmarkTests: XCTestCase {
    static let size = CGSize(width: 1320, height: 860)
    static let budget: Double = 0.008

    /// Modern, seed 11, mid-game: a three-hop route, a tracked system and a quest marker; every M8 layer on.
    static func fixture() throws -> MapSnapshot {
        var st = GameState(config: NewGameConfig(commanderName: "Bench", ruleset: .modern, seed: 11))
        st.quests.japori = QuestStatus.Japori.inTransit
        for i in st.galaxy.systems.indices where i % 3 == 0 { st.galaxy.systems[i].visited = true }
        st.commander.ship.fuel = 9
        let snapshot = RouteSnapshot(st)
        let cur = st.commander.currentSystem
        let target = try XCTUnwrap(st.galaxy.systems.indices.first {
            RoutePlanner.plan(from: cur, to: $0, in: snapshot)?.totalJumps == 3
        })
        st.trackedSystem = target
        st.warpSystem = st.destinations.first ?? cur
        let route = RoutePlanner.plan(from: cur, to: target, in: snapshot)
        return MapSnapshot.make(state: st, generation: 1, route: route)
    }

    /// One frame: the renderer through `ImageRenderer`.
    static func render(_ snapshot: MapSnapshot, zoom: Double) -> CGImage? {
        let s = snapshot.current
        let viewport = MapViewport(zoom: zoom, center: CGPoint(x: s.x, y: s.y)).clamped(MapBounds(snapshot))
        let projected = ProjectedMap.make(snapshot: snapshot, viewport: viewport, viewSize: size)
        let view = Canvas { ctx, _ in
            GalaxyMapRenderer.draw(in: &ctx, snapshot: snapshot, projected: projected, layers: MapLayer.m8,
                                   options: MapRenderOptions(dimmed: [1, 2, 3]))
        }
        .frame(width: size.width, height: size.height)
        return ImageRenderer(content: view).cgImage
    }

    /// Median and p90 (seconds) of 50 frames after 5 warm-up frames.
    static func timings(zoom: Double) throws -> (median: Double, p90: Double) {
        let snapshot = try fixture()
        for _ in 0..<5 { _ = render(snapshot, zoom: zoom) }
        let clock = ContinuousClock()
        var samples: [Double] = []
        for _ in 0..<50 {
            let d = clock.measure { _ = render(snapshot, zoom: zoom) }
            samples.append(Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18)
        }
        samples.sort()
        return (samples[25], samples[45])
    }

    func testRendersNonEmptyImage() throws {
        // MAP-024: the background fills the view; the image is produced at the benchmark size.
        let image = try XCTUnwrap(Self.render(try Self.fixture(), zoom: 1))
        XCTAssertEqual(image.width, Int(Self.size.width * (NSScreen.main?.backingScaleFactor ?? 1)), accuracy: 2 * image.width)
        XCTAssertGreaterThan(image.height, 0)
    }

    func testMapRenderMedianUnderBudget() throws {
        // covers: MAP-090
        #if DEBUG
        throw XCTSkip("MAP-090 runs in Release from scripts/bench-map.sh")
        #else
        for zoom in [1.0, 4.0] {
            let t = try Self.timings(zoom: zoom)
            print(String(format: "MAP-090 zoom %.0f median %.3f ms p90 %.3f ms", zoom, t.median * 1000, t.p90 * 1000))
            XCTAssertLessThan(t.median, Self.budget, "median frame at zoom \(zoom) is under 8 ms")
        }
        let snapshot = try Self.fixture()
        measure(metrics: [XCTClockMetric()]) {
            _ = Self.render(snapshot, zoom: 1)
            _ = Self.render(snapshot, zoom: 4)
        }
        #endif
    }
}
