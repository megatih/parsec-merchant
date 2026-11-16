// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecEngine

@Suite("Alert mapping: singularity jump (ALR-019…021)")
struct AlertJumpM3Tests {
    @Test("ALR-019 ChartJump → useSingularity confirmation carrying the destination")
    func chartJump() throws {
        var e = makeEngine { $0.quests.canSuperWarp = true }
        let t = try #require(plainTarget(e.state))
        _ = e.perform(.selectTarget(t))
        let before = e.state
        let r = e.perform(.jump)
        #expect(r.decision == .confirm(Confirmation(.useSingularity, amounts: [t])))
        #expect(e.state == before)
    }

    @Test("ALR-020 ChartJumpCurrent → singularityTargetIsCurrentSystem, state unchanged")
    func chartJumpCurrent() {
        var e = makeEngine { $0.quests.canSuperWarp = true }
        _ = e.perform(.selectTarget(e.state.commander.currentSystem))
        let before = e.state
        #expect(e.perform(.jump, acknowledging: [.useSingularity]).rejection == .singularityTargetIsCurrentSystem)
        #expect(e.state.jumpPreview.rejection == .singularityTargetIsCurrentSystem)
        #expect(e.state == before)
    }

    @Test("ALR-021 ChartJumpNoSystemSelected cannot occur: warpSystem always names a valid system")
    func chartJumpNoTarget() {
        var e = makeEngine { $0.quests.canSuperWarp = true }
        let count = e.state.galaxy.systems.count
        #expect(e.state.galaxy.systems.indices.contains(e.state.warpSystem))
        let before = e.state.warpSystem
        #expect(e.perform(.selectTarget(-1)).rejection != nil)
        #expect(e.perform(.selectTarget(count)).rejection != nil)
        #expect(e.state.warpSystem == before)
    }
}
