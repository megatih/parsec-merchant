// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecMerchant

@MainActor @Test("APP-001 app target links ParsecEngine")
func appLinksEngine() {
    #expect(AppInfo.engineVersion == "0.1.0")
}
