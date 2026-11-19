// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecArt
import ParsecEngine
import ParsecPersistence
import Testing
@testable import ParsecMerchant

/// ART-FACE: how the app derives portraits from saved state (docs/PRD-UI-Revamp.md §5.2).
@MainActor
@Suite("Portrait seeds (ART-FACE)")
struct PortraitSeedTests {
    static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Packages/ParsecKit/Tests/Fixtures/saves/v1")

    @Test("ART-FACE-005 portraits are stable across saves: every crew id keeps its seed and genome after a save round trip",
          arguments: ["modern", "windows201", "palm122"])
    func stableAcrossSaves(ruleset: String) throws {
        let data = try Data(contentsOf: Self.fixtures.appendingPathComponent("\(ruleset).parsecsave"))
        let first = try SaveCodec.decode(data)
        let second = try SaveCodec.decode(try SaveCodec.encode(first))
        for id in 0..<CrewID.count {
            #expect(ArtAdapters.portraitSeed(crewID: id, state: first.state) == ArtAdapters.portraitSeed(crewID: id, state: second.state))
            #expect(ArtAdapters.portraitGenome(crewID: id, state: first.state) == ArtAdapters.portraitGenome(crewID: id, state: second.state))
        }
    }

    @Test("ART-FACE-005 the commander's portrait depends on the galaxy seed and the name; crew portraits only on the seed and id")
    func commanderName() throws {
        let state = try #require(try TestSessions.playing(seed: 1001).state)
        var renamed = state
        renamed.commander.name = state.commander.name + "x"
        #expect(ArtAdapters.portraitSeed(crewID: CrewID.commander, state: state) != ArtAdapters.portraitSeed(crewID: CrewID.commander, state: renamed))
        #expect(ArtAdapters.portraitSeed(crewID: 5, state: state) == ArtAdapters.portraitSeed(crewID: 5, state: renamed))
        #expect(ArtAdapters.portraitSeed(crewID: 5, state: state) == ArtSeed.crew(galaxySeed: state.seed, crewID: 5))
        // The name hash is a fixed function (FNV-1a), not the per-process standard hash.
        #expect(ArtAdapters.nameHash("") == 0xCBF2_9CE4_8422_2325 && ArtAdapters.nameHash("a") == 0xAF63_DC4C_8601_EC8C)
    }

    @Test("ART-FACE-002 in a real game all portraits differ: commander, crew, passengers and the famous captains")
    func uniqueInAGame() throws {
        for seed in [UInt64(1), 7, 1001] {
            let state = try #require(try TestSessions.playing(seed: seed).state)
            var genomes = (0..<CrewID.count).map { ArtAdapters.portraitGenome(crewID: $0, state: state) }
            genomes += [PortraitRole.ahab, .conrad, .huie].map { PortraitGenome.fixed($0) }
            // Ids that are not characters (opponent slots, quest ships) still get a face; all must be distinct.
            #expect(Set(genomes).count == genomes.count)
        }
        #expect(ArtAdapters.portraitRole(crewID: CrewID.wild) == .wild && ArtAdapters.portraitRole(crewID: CrewID.zeethibal) == .zeethibal)
        #expect(ArtAdapters.portraitRole(.captainAhab) == .ahab && ArtAdapters.portraitRole(.marieCeleste) == nil)
    }

    @Test("ART-FACE-009 the portrait style decision is recorded with both review scores")
    func styleDecision() throws {
        let adr = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/adr/0005-portrait-style.md")
        let text = try String(contentsOf: adr, encoding: .utf8)
        #expect(text.contains("Decision") && text.contains("Self review") && text.contains("Independent review"))
    }
}
