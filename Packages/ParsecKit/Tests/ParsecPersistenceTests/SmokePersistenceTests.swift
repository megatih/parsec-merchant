// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecPersistence

@Test("ParsecPersistence module loads")
func smokePersistence() {
    #expect(!ParsecPersistenceInfo.version.isEmpty)
}
