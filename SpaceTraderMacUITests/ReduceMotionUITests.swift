// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

/// A11Y-017: Reduce Motion end to end, forced with `-PMA11y reduceMotion` and without `-PMFastTravel`.
final class ReduceMotionUITests: ParsecUITestCase {
    override var launchArguments: [String] { UITestFixtures.playbackArguments + ["-PMA11y", "reduceMotion"] }

    @MainActor
    func testWarpSkipsThePlaybackAndFitGalaxyJumps() throws {
        // covers: A11Y-017, A11Y-016, A11Y-001, A11Y-002
        click(AXID.Welcome.quickStart)
        expect("the Quick Start game runs") { subtitle.hasPrefix("Day 0") }
        openPage("bridge")
        click(AXID.Bridge.targetNext)
        let start = Date()
        type("j")
        let card = element(AXID.Arrival.card)
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the arrival card shows")
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 2.5, "no transit playback under Reduce Motion (arrival card after \(elapsed) s)")
        XCTAssertFalse(element(AXID.Transit.view).exists, "the Transit view never showed")

        openPage("galaxy")
        let g = AXID.Galaxy.section
        waitFor(g.map)
        click(g.zoomIn)
        click(g.zoomIn)
        let zoom = element(g.zoomOut)
        let before = zoomValue()
        click(g.fitGalaxy)
        let first = zoomValue()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        let settled = zoomValue()
        XCTAssertNotEqual(before, first, "Fit Galaxy changed the viewport")
        XCTAssertEqual(first, settled, "the zoom reads its final value on the first poll (no intermediate frames)")
        XCTAssertTrue(zoom.exists)
        openPage("bridge")
    }

    /// The viewport as the position of a system element (its frame moves with every viewport frame).
    private func zoomValue() -> String {
        return "\(element(AXID.Galaxy.section.system(0)).frame)"
    }
}
