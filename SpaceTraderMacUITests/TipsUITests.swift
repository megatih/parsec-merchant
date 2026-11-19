// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

/// A11Y-047: the three tips under `-PMTips all`, their audit, close and Learn More; and the Market tip's first-visit life
/// cycle on a fresh TipKit store. Every other test launches with `-PMTips off` (`ParsecUITestCase.withTipsOff`).
final class TipsUITests: ParsecUITestCase {
    override var launchArguments: [String] { UITestFixtures.launchArguments + ["-PMTips", "all", "-PMAppearance", "light"] }

    @MainActor
    func testEveryTipShowsPassesTheAuditClosesAndLearnsMore() throws {
        // covers: A11Y-047, A11Y-043, A11Y-028, INT-044, MAP-098
        click(AXID.Welcome.quickStart)
        expect("the Quick Start game runs") { subtitle.hasPrefix("Day 0") }
        let recorder = AuditRecorder()

        openPage("bridge")
        let market = waitFor(AXID.A11y.tipMarket)
        XCTAssertTrue(market.buttons["Close Tip"].exists || element("tip.market.close").exists, "the Market tip has its close button")
        recorder.audit(app, surface: "tip-market", types: .all, windowFrame: mainWindow.frame,
                       scope: AuditScope.make(app: app, root: mainWindow))
        tipButton(market, id: "tip.market.close", label: "Close Tip").click()
        expect("the Market tip closes") { !market.exists }

        click(AXID.Bridge.targetNext)
        waitFor(AXID.A11y.tipWarp)
        recorder.audit(app, surface: "tip-warp", types: .all, windowFrame: mainWindow.frame,
                       scope: AuditScope.make(app: app, root: mainWindow))
        tipButton(element(AXID.A11y.tipWarp), id: "tip.warp.learnMore", label: "Learn More").click()
        waitFor(AXID.A11y.helpWindow)
        XCTAssertTrue(element(AXID.A11y.helpTopic("travel")).isSelected || element(AXID.A11y.helpContent).exists,
                      "Learn More opens Help at Travel")
        type("w")
        expect("the Help window closes") { !element(AXID.A11y.helpWindow).exists }

        openPage("galaxy")
        waitFor(AXID.A11y.tipGalaxy)
        recorder.audit(app, surface: "tip-galaxy", types: .all, windowFrame: mainWindow.frame,
                       scope: AuditScope.make(app: app, root: mainWindow))
        tipButton(element(AXID.A11y.tipGalaxy), id: "tip.galaxy.close", label: "Close Tip").click()
        expect("the Galaxy tip closes") { !element(AXID.A11y.tipGalaxy).exists }
        XCTAssertTrue(recorder.failures.isEmpty, "tip audit failures:\n" + recorder.failures.joined(separator: "\n"))
        openPage("bridge")
    }

    @MainActor
    func testTheMarketTipShowsOnTheFirstVisitAndGoesAfterOneBuy() throws {
        // covers: A11Y-047, A11Y-044, A11Y-045
        relaunch(UITestFixtures.launchArguments + ["-PMTips", "default"])  // TipKit's own rules on a reset store
        click(AXID.Welcome.quickStart)
        expect("the Quick Start game runs") { subtitle.hasPrefix("Day 0") }
        openPage("bridge")
        waitFor(AXID.A11y.tipMarket)
        click(AXID.Cargo.buy("water"))
        expect("the Market tip is gone after one buy") { !element(AXID.A11y.tipMarket).exists }
        openPage("bridge")
    }

    /// A tip's control by its identifier, else by its label (TipView may give its subtree the tip's identifier).
    private func tipButton(_ tip: XCUIElement, id: String, label: String) -> XCUIElement {
        let byID = element(id)
        if byID.waitForExistence(timeout: 2) { return byID }
        let byLabel = tip.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
        XCTAssertTrue(byLabel.waitForExistence(timeout: timeout), "\(id) or a control labelled \(label)")
        return byLabel
    }
}
