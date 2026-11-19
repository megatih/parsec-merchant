// SPDX-License-Identifier: GPL-2.0-or-later
import CryptoKit
import Foundation
import ParsecArt
import ParsecEngine
import Testing
@testable import ParsecMerchant

/// PROT-003: the app's mapping from a star system to its planet input is frozen for release 2.0. The literal was
/// recorded at M18 on the 1.1.0 mapping; it is never re-recorded.
@MainActor
@Suite("Planet input mapping is frozen (PROT)")
struct PlanetInputFrozenTests {
    @Test("PROT-003 planet inputs of the first systems of galaxy seed 1001 are unchanged")
    func planetInputs() throws {
        let state = try #require(try TestSessions.playing(seed: 1001).state)
        var lines: [String] = []
        for index in 0..<12 {
            for showPressure in [false, true] {
                let i = ArtAdapters.planetInput(system: index, state: state, showPressure: showPressure)
                lines.append("\(index)|\(i.seed)|\(i.sizeClass)|\(i.tech)|\(i.government)|\(i.resource ?? -1)|\(i.pressure ?? -1)|\(i.phase)")
            }
        }
        let digest = SHA256.hash(data: Data(lines.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
        #expect(digest == "8e0b103d7b2dafb91fe5fd5577a928d39a0b909deb05bb474f3c5837e5b7afb9", "now \(digest)")
    }
}
