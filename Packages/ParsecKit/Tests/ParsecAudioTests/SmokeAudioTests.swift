// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecAudio

@Test("ParsecAudio module loads")
func smokeAudio() {
    #expect(!ParsecAudioInfo.version.isEmpty)
}
