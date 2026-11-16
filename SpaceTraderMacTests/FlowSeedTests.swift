// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import Testing
@testable import ParsecMerchant

/// Mirrors `UITestFixtures.flowSeed` and `.flowGalaxyCode` of the UI-test target (flows 1 and 3), which cannot import
/// the engine; keep the two files in step.
enum FlowFixtures {
    static let flowSeed: UInt64 = 11
    static let flowGalaxyCode = "M2-B-S"
}

@MainActor
@Suite("UI flow fixtures")
struct FlowSeedTests {
    /// Plays flow 1's path; returns the final state when it ends docked after an uneventful trip on day 1.
    static func playFlow(seed: UInt64) throws -> (GameState, [GameEvent])? {
        let s = try TestSessions.make(seed: seed)
        var draft = NewGameDraft(commanderName: "Flow", seed: seed)
        draft.balance()
        #expect(s.startNewGame(draft.config) == nil)
        let st = try #require(s.state)
        guard let item = TradeItemType.allCases.first(where: { st.currentSystem.tradeItems[$0.rawValue] > 0 && st.buyPrices[$0.rawValue] > 0 })
        else { return nil }
        s.send(.buyCargo(item, quantity: 1))
        s.send(.selectNextTarget(forward: true))
        let target = s.state?.warpSystem
        s.send(.warp)
        guard let end = s.state, end.phase == .docked, end.commander.currentSystem == target else { return nil }
        let events = s.feed.compactMap(\.event)
        return (end, events)
    }

    @Test("UI-SHELL-129 the flow seed: buy one unit, next target, warp → docked at the target, uneventful, day 1")
    func flowSeed() throws {
        let result = try #require(try Self.playFlow(seed: FlowFixtures.flowSeed))
        #expect(result.0.commander.days == 1)
        #expect(result.1.contains(.uneventfulTrip))
    }

    @Test("UI-SHELL-124 the galaxy code flow 1 checks in the wizard is the engine's code for Modern, Normal, the flow seed")
    func flowGalaxyCode() {
        #expect(FlowFixtures.flowGalaxyCode == GalaxyCode(ruleset: .modern, difficulty: .normal, seed: FlowFixtures.flowSeed).string)
        var draft = NewGameDraft(commanderName: "Flow", seed: FlowFixtures.flowSeed)
        draft.balance()
        #expect(draft.galaxyCodeText == FlowFixtures.flowGalaxyCode)
    }

    @Test("UI-SHELL-013 bare debug flags never leave a word over for AppKit to open as a document")
    func unknownArgumentsAreNotOpened() {
        #expect(UserDefaults.standard.string(forKey: LaunchOptions.treatUnknownArgumentsAsOpenKey) == "NO")
    }
}
