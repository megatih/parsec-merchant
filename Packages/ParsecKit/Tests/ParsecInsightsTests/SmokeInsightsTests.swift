// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecInsights

@Test("ParsecInsights module loads")
func smokeInsights() {
    #expect(!ParsecInsightsInfo.version.isEmpty)
}
