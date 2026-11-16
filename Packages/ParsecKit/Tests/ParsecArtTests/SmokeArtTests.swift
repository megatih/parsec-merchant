// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecArt

@Test("ParsecArt module loads")
func smokeArt() {
    #expect(!ParsecArtInfo.version.isEmpty)
}
