// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecEngine

@Test("ParsecEngine module loads")
func smokeScenario() {
    #expect(!ParsecEngineInfo.version.isEmpty)
}
