// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

/// Smoke flows; real flows (PRD §8.2) arrive in M7+.
final class LaunchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunches() throws {
        // covers: APP-002
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
    }
}
