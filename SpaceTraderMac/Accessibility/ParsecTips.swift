// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import SwiftUI
import TipKit

/// The three first-run tips (A11Y-043), shown only inline (never `.popoverTip`, PRD §6.5).
nonisolated enum TipID: String, CaseIterable, Sendable {
    case market, galaxy, warp

    var identifier: String { "tip.\(rawValue)" }
    var learnMoreIdentifier: String { "tip.\(rawValue).learnMore" }
    var closeIdentifier: String { "tip.\(rawValue).close" }
    /// The Help topic "Learn More" opens.
    var helpTopic: HelpTopic { self == .market ? .howPricesWork : .travel }

    var title: LocalizedStringResource {
        switch self {
        case .market: "Read the Target Column"
        case .galaxy: "Plan on the Chart"
        case .warp: "Warp to Your Target"
        }
    }

    var message: LocalizedStringResource {
        switch self {
        case .market:
            "Target shows what each item is estimated to fetch at your target system. The strip above the table suggests the best trades."
        case .galaxy: "Click to target, ⌥-click to track, right-click to plot a route."
        case .warp: "Warp (⌘J) flies to the target in one go. Its help tag lists the fuel and costs of the trip."
        }
    }

    var systemImage: String {
        switch self {
        case .market: "chart.line.uptrend.xyaxis"
        case .galaxy: "map"
        case .warp: "arrow.up.forward.circle"
        }
    }

    static let learnMoreActionID = "learnMore"
    static var learnMoreTitle: LocalizedStringResource { "Learn More" }
}

// MARK: TipKit tips

/// INT-044.
struct MarketTip: Tip {
    @Parameter static var isVisible: Bool = false
    var id: String { TipID.market.identifier }
    var title: Text { Text(TipID.market.title) }
    var message: Text? { Text(TipID.market.message) }
    var image: Image? { Image(systemName: TipID.market.systemImage) }
    var actions: [Action] { [Action(id: TipID.learnMoreActionID, title: String(localized: TipID.learnMoreTitle))] }
    var rules: [Rule] { [#Rule(Self.$isVisible) { $0 == true }] }
}

/// MAP-098.
struct GalaxyTip: Tip {
    @Parameter static var isVisible: Bool = false
    var id: String { TipID.galaxy.identifier }
    var title: Text { Text(TipID.galaxy.title) }
    var message: Text? { Text(TipID.galaxy.message) }
    var image: Image? { Image(systemName: TipID.galaxy.systemImage) }
    var actions: [Action] { [Action(id: TipID.learnMoreActionID, title: String(localized: TipID.learnMoreTitle))] }
    var rules: [Rule] { [#Rule(Self.$isVisible) { $0 == true }] }
}

/// UX-VISION §11: shown while the target is in range and nothing has warped yet.
struct WarpTip: Tip {
    @Parameter static var isVisible: Bool = false
    static let didWarp = Tips.Event(id: "didWarp")
    var id: String { TipID.warp.identifier }
    var title: Text { Text(TipID.warp.title) }
    var message: Text? { Text(TipID.warp.message) }
    var image: Image? { Image(systemName: TipID.warp.systemImage) }
    var actions: [Action] { [Action(id: TipID.learnMoreActionID, title: String(localized: TipID.learnMoreTitle))] }
    var rules: [Rule] {
        [#Rule(Self.$isVisible) { $0 == true }, #Rule(Self.didWarp) { $0.donations.count == 0 }]
    }
}

// MARK: Triggers (A11Y-044)

/// One call the triggers make on the tip center.
nonisolated enum TipCall: Equatable, Sendable {
    case show(TipID)
    case hide(TipID)
    case invalidate(TipID)
    case donateDidWarp
}

/// Receives the tip calls (A11Y-044) and runs the launch sequence (A11Y-045). TipKit in the app; tests record.
@MainActor
protocol TipCenter: AnyObject {
    func apply(_ call: TipCall)
    func resetDatastore()
    func hideAllForTesting()
    func showAllForTesting()
    func configure()
}

/// Sessions built without TipKit (unit tests).
final class NoTipCenter: TipCenter {
    func apply(_ call: TipCall) {}
    func resetDatastore() {}
    func hideAllForTesting() {}
    func showAllForTesting() {}
    func configure() {}
}

/// When tips show and go (A11Y-044). Pure.
enum TipTriggers {
    /// The calls for a docked game showing `section` after `step` (nil: a visibility change only).
    static func apply(step: StepRecord?, section: Section, docked: Bool, targetInRange: Bool) -> [TipCall] {
        var calls: [TipCall] = []
        calls.append(section == .market && docked ? .show(.market) : .hide(.market))
        calls.append(section == .galaxy ? .show(.galaxy) : .hide(.galaxy))
        calls.append(section == .bridge && docked && targetInRange ? .show(.warp) : .hide(.warp))
        guard let step else { return calls }
        let traded = step.contains {
            switch $0 {
            case .boughtCargo, .soldCargo: true
            default: false
            }
        }
        if traded { calls.append(.invalidate(.market)) }
        let targetedFromMap = switch step.command {
        case .selectTarget, .selectWormhole: section == .galaxy
        default: false
        }
        if targetedFromMap { calls.append(.invalidate(.galaxy)) }
        let warped = step.contains { if case .departed = $0 { true } else { false } }
        if warped {
            calls.append(.invalidate(.warp))
            calls.append(.donateDidWarp)
        }
        return calls
    }

    /// A11Y-045 / A11Y-046: reset (when asked) before configure; `-PMTips` before configure too.
    static func launch(options: LaunchOptions, defaults: UserDefaults, center: any TipCenter) {
        if options.resetState || defaults.bool(forKey: TipDefaultsKey.resetPending) {
            center.resetDatastore()
            defaults.removeObject(forKey: TipDefaultsKey.resetPending)
        }
        switch options.tips {
        case .off: center.hideAllForTesting()
        case .all: center.showAllForTesting()
        case nil: break
        }
        center.configure()
    }

    /// A11Y-046: Settings › Advanced › Reset Tips.
    static func requestReset(defaults: UserDefaults) {
        defaults.set(true, forKey: TipDefaultsKey.resetPending)
    }
}

nonisolated enum TipDefaultsKey {
    static let resetPending = "tips.resetPending"
}

/// The production center: TipKit.
final class TipKitCenter: TipCenter {
    func apply(_ call: TipCall) {
        switch call {
        case let .show(id): setVisible(id, true)
        case let .hide(id): setVisible(id, false)
        case let .invalidate(id):
            switch id {
            case .market: MarketTip().invalidate(reason: .actionPerformed)
            case .galaxy: GalaxyTip().invalidate(reason: .actionPerformed)
            case .warp: WarpTip().invalidate(reason: .actionPerformed)
            }
        case .donateDidWarp:
            WarpTip.didWarp.sendDonation()
        }
    }

    private func setVisible(_ id: TipID, _ visible: Bool) {
        switch id {
        case .market: if MarketTip.isVisible != visible { MarketTip.isVisible = visible }
        case .galaxy: if GalaxyTip.isVisible != visible { GalaxyTip.isVisible = visible }
        case .warp: if WarpTip.isVisible != visible { WarpTip.isVisible = visible }
        }
    }

    func resetDatastore() { try? Tips.resetDatastore() }
    func hideAllForTesting() { Tips.hideAllTipsForTesting() }
    func showAllForTesting() { Tips.showAllTipsForTesting() }
    func configure() {
        try? Tips.configure([.displayFrequency(.immediate), .datastoreLocation(.applicationDefault)])
    }
}

// MARK: Presentation

/// An inline tip with the app's identifiers (A11Y-043): title, message, image, Learn More and close.
struct InlineTipView<T: Tip>: View {
    let tip: T
    let id: TipID
    /// Space around the tip while it shows (none when it is hidden).
    var margin: CGFloat = 0
    @Environment(\.openWindow) private var openWindow
    @Environment(HelpRouter.self) private var helpRouter

    var body: some View {
        TipView(tip) { action in
            if action.id == TipID.learnMoreActionID { openHelp() }
        }
        .tipViewStyle(ParsecTipViewStyle(id: id, margin: margin, learnMore: openHelp))
        // TipView names its container "TipView"; the outer identifier replaces it (a hidden tip has no element).
        .accessibilityIdentifier(id.identifier)
    }

    private func openHelp() {
        helpRouter.topic = id.helpTopic
        openWindow(id: AppWindowID.help)
    }
}

/// Draws the tip with labelled, identified controls.
struct ParsecTipViewStyle: TipViewStyle {
    let id: TipID
    var margin: CGFloat = 0
    let learnMore: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: id.systemImage)
                .scaledFont(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(id.title).scaledFont(.headline).accessibilityAddTraits(.isHeader)
                Text(id.message).fixedSize(horizontal: false, vertical: true)
                Button(String(localized: TipID.learnMoreTitle), action: learnMore)
                    .buttonStyle(.link)
                    .accessibilityIdentifier(id.learnMoreIdentifier)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                configuration.tip.invalidate(reason: .tipClosed)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help(Text("Close this tip"))
            .accessibilityLabel(Text("Close Tip"))
            .accessibilityIdentifier(id.closeIdentifier)
        }
        .padding(12)
        // A labelled container (only drawn while the tip shows); the controls keep their own identifiers.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(id.title))
        .padding(margin)
    }
}
