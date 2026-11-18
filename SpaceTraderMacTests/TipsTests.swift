// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import Testing
import TipKit
@testable import ParsecMerchant

/// Records tip-center calls (A11Y-044…046).
@MainActor
final class RecordingTipCenter: TipCenter {
    enum Entry: Equatable {
        case call(TipCall), reset, hideAll, showAll, configure
    }

    var entries: [Entry] = []
    var calls: [TipCall] { entries.compactMap { if case let .call(c) = $0 { c } else { nil } } }
    func apply(_ call: TipCall) { entries.append(.call(call)) }
    func resetDatastore() { entries.append(.reset) }
    func hideAllForTesting() { entries.append(.hideAll) }
    func showAllForTesting() { entries.append(.showAll) }
    func configure() { entries.append(.configure) }
}

/// A11Y §11: TipKit tips, triggers, configuration and Reset Tips.
@MainActor
struct TipsTests {
    static func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "pm-tips-\(UUID().uuidString)"))
    }

    @Test("A11Y-043 three inline tips with ids, titles, messages, images and Learn More to their Help topics")
    func tips() {
        #expect(TipID.allCases == [.market, .galaxy, .warp])
        #expect(TipID.allCases.map(\.identifier) == ["tip.market", "tip.galaxy", "tip.warp"])
        #expect(TipID.allCases.map(\.learnMoreIdentifier) == ["tip.market.learnMore", "tip.galaxy.learnMore", "tip.warp.learnMore"])
        #expect(TipID.allCases.map(\.helpTopic) == [.howPricesWork, .travel, .travel])
        for id in TipID.allCases {
            #expect(!String(localized: id.title).isEmpty && !String(localized: id.message).isEmpty && !id.systemImage.isEmpty)
            #expect(AXID.all.contains(id.identifier) && AXID.all.contains(id.closeIdentifier))
        }
        #expect(String(localized: TipID.galaxy.message) == "Click a system to target it. Its card has Track and Plot Route.")
        #expect(MarketTip().id == "tip.market" && GalaxyTip().id == "tip.galaxy" && WarpTip().id == "tip.warp")
        #expect(MarketTip().actions.map(\.id) == [TipID.learnMoreActionID])
        #expect(String(localized: TipID.learnMoreTitle) == "Learn More")
    }

    @Test("A11Y-044 TipTriggers: show on visit, invalidate after the first trade, map target and warp")
    func triggers() throws {
        let market = TipTriggers.apply(step: nil, section: .market, docked: true, targetInRange: false)
        #expect(market == [.show(.market), .hide(.galaxy), .hide(.warp)])
        #expect(TipTriggers.apply(step: nil, section: .market, docked: false, targetInRange: false).first == .hide(.market))
        #expect(TipTriggers.apply(step: nil, section: .galaxy, docked: true, targetInRange: false)[1] == .show(.galaxy))
        #expect(TipTriggers.apply(step: nil, section: .bridge, docked: true, targetInRange: true)[2] == .show(.warp))
        #expect(TipTriggers.apply(step: nil, section: .bridge, docked: true, targetInRange: false)[2] == .hide(.warp))

        let s = try TestSessions.playing(seed: 11)
        let center = RecordingTipCenter()
        s.tipCenter = center
        s.selectedSection = .market
        s.updateTips()
        #expect(center.calls.contains(.show(.market)))
        s.send(.buyCargo(.water, quantity: 1))
        #expect(center.calls.contains(.invalidate(.market)))
        s.selectedSection = .galaxy
        let target = try #require(s.state).warpSystem
        s.send(.selectTarget(target == 0 ? 1 : 0))
        s.send(.selectNextTarget(forward: true))
        #expect(center.calls.contains(.invalidate(.galaxy)))
        s.selectedSection = .bridge
        s.send(.warp)
        #expect(center.calls.contains(.invalidate(.warp)) && center.calls.contains(.donateDidWarp))
    }

    @Test("A11Y-045 the launch resets (when asked) before configure, and -PMTips runs before configure")
    func launchSequence() throws {
        var reset = LaunchOptions()
        reset.resetState = true
        reset.tips = .off
        let c1 = RecordingTipCenter()
        TipTriggers.launch(options: reset, defaults: try Self.defaults(), center: c1)
        #expect(c1.entries == [.reset, .hideAll, .configure])

        var all = LaunchOptions()
        all.tips = .all
        let c2 = RecordingTipCenter()
        TipTriggers.launch(options: all, defaults: try Self.defaults(), center: c2)
        #expect(c2.entries == [.showAll, .configure])

        let c3 = RecordingTipCenter()
        TipTriggers.launch(options: LaunchOptions(), defaults: try Self.defaults(), center: c3)
        #expect(c3.entries == [.configure])
    }

    @Test("A11Y-046 Reset Tips sets the pending flag; the next launch resets before configure and clears it")
    func resetTipsRoundTrip() throws {
        let d = try Self.defaults()
        TipTriggers.requestReset(defaults: d)
        #expect(d.bool(forKey: TipDefaultsKey.resetPending))
        let c = RecordingTipCenter()
        TipTriggers.launch(options: LaunchOptions(), defaults: d, center: c)
        #expect(c.entries == [.reset, .configure])
        #expect(!d.bool(forKey: TipDefaultsKey.resetPending))
        #expect(AXID.Tips.resetTips == "settings.resetTips" && AXID.Tips.resetTipsStatus == "settings.resetTips.status")
    }
}
