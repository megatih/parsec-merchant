// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecArt
import ParsecEngine
import ParsecPersistence
import Testing
@testable import ParsecMerchant

/// ART-SHIP: how the app gives ships their role and livery (docs/PRD-UI-Revamp.md §5.1).
@MainActor
@Suite("Ship liveries in the app (ART-SHIP)")
struct ShipLiveryTests {
    @Test("ART-SHIP-010 an opponent's livery seed is the same across rounds and after a save round trip")
    func stableOpponent() throws {
        let session = try EncFx.session(.pirateAttack, opponent: .gnat)
        let before = try #require(session.state)
        guard case let .encounter(first) = before.phase else {
            Issue.record("no encounter")
            return
        }
        let seed = ArtAdapters.opponentLiverySeed(before, encounter: first)
        let input = ArtAdapters.opponentShipInput(before, encounter: first)
        // A round of combat changes hull, shields and the round counter, not the livery.
        session.send(.encounter(.attack))
        if let after = session.state, case let .encounter(second) = after.phase {
            #expect(ArtAdapters.opponentLiverySeed(after, encounter: second) == seed)
            #expect(ArtAdapters.opponentShipInput(after, encounter: second).livery == input.livery)
        }
        // A save round trip keeps it.
        let envelope = SaveEnvelope(state: before, appVersion: "test", gameID: "g")
        let loaded = try SaveCodec.decode(try SaveCodec.encode(envelope)).state
        guard case let .encounter(reloaded) = loaded.phase else {
            Issue.record("no encounter after loading")
            return
        }
        #expect(ArtAdapters.opponentLiverySeed(loaded, encounter: reloaded) == seed)
        #expect(ArtAdapters.playerLiverySeed(loaded) == ArtAdapters.playerLiverySeed(before))
    }

    @Test("ART-SHIP-013 encounters pass the role and both seeds; an opponent is never painted like the player's ship")
    func roles() throws {
        let cases: [(EncounterType, ShipType, ShipRole)] = [
            (.policeInspect, .gnat, .police), (.pirateAttack, .gnat, .pirate), (.traderSell, .gnat, .trader), (.captainAhab, .wasp, .famousCaptain),
            (.captainConrad, .wasp, .famousCaptain), (.captainHuie, .wasp, .famousCaptain), (.marieCeleste, .firefly, .trader),
            (.pirateAttack, .mantis, .alien), (.spaceMonsterAttack, .spaceMonster, .alien),
        ]
        for (type, ship, role) in cases {
            let state = try EncFx.state(type, opponent: ship)
            guard case let .encounter(enc) = state.phase else { continue }
            let input = ArtAdapters.opponentShipInput(state, encounter: enc)
            #expect(input.role == role, "\(type)")
            #expect(input.playerLiverySeed == ArtAdapters.playerLiverySeed(state) && input.facing == .left)
            #expect(input.derelict == (type == .marieCeleste))
            let player = ArtAdapters.playerShipInput(state)
            #expect(player.role == ShipRole.player && player.liverySeed == ArtAdapters.playerLiverySeed(state))
            if [.pirate, .trader, .famousCaptain, .police].contains(role) {
                #expect(input.livery.signature != player.livery.signature)
                #expect(input.livery != ShipLivery.make(role: .player, seed: ArtAdapters.playerLiverySeed(state)))
            }
        }
        // The three captains fly three different, fixed liveries.
        let captains = try [EncounterType.captainAhab, .captainConrad, .captainHuie].map { type -> ShipLivery in
            let state = try EncFx.state(type, opponent: .wasp)
            guard case let .encounter(enc) = state.phase else { throw CancellationError() }
            return ArtAdapters.opponentShipInput(state, encounter: enc).livery
        }
        #expect(Set(captains).count == 3)
        // Shipyard listings and the designer show the player's own colours.
        let state = try #require(try TestSessions.playing(seed: 7).state)
        let yard = ArtAdapters.specInput(.wasp, spec: state.ruleset.tables.ship(.wasp), liverySeed: ArtAdapters.playerLiverySeed(state))
        #expect(yard.livery == ArtAdapters.playerShipInput(state).livery)
    }
}
