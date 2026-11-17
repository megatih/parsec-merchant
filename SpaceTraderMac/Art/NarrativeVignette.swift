// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecArt
import ParsecEngine
import SwiftUI

/// ART-040: which vignette illustrates each special event (an exhaustive table over `SpecialEventType`).
nonisolated enum NarrativeVignette {
    enum Subject: Equatable, Sendable {
        case planet
        case ship(ShipType)
        case object(VignetteObject)
    }

    static func kind(for type: SpecialEventType) -> Subject {
        switch type {
        case .artifact, .artifactDelivery: .object(.artifact)
        case .dragonfly, .dragonflyBaratas, .dragonflyDestroyed, .dragonflyMelina, .dragonflyRegulas, .dragonflyShield: .ship(.dragonfly)
        case .experiment, .experimentFailed, .experimentStopped: .object(.experimentRip)
        case .gemulon, .gemulonFuel, .gemulonInvaded, .gemulonRescued: .object(.gemulonFleet)
        case .japori: .object(.japoriMedicine)
        case .japoriDelivery: .object(.antidote)
        case .moon, .moonRetirement: .object(.moonDeed)
        case .reactor, .reactorDelivered, .reactorLaser: .object(.reactor)
        case .scarab, .scarabDestroyed, .scarabUpgradeHull: .ship(.scarab)
        case .skill: .object(.tonicBottle)
        case .spaceMonster, .spaceMonsterKilled: .ship(.spaceMonster)
        case .sculpture, .sculptureDelivered, .sculptureHiddenBays: .object(.jewels)
        case .princess, .princessCentauri, .princessInthara, .princessQonos: .ship(.scorpion)
        case .cargoForSale, .eraseRecord, .jarek, .jarekGetsOut, .lottery, .tribble, .tribbleBuyer, .wild, .wildGetsOut, .princessQuantum,
             .princessReturned:
            .planet
        }
    }

    /// The ParsecArt input: the event's system (the current one) for planets, the quest ship's portrait for ships.
    static func input(for type: SpecialEventType, state: GameState) -> VignetteKind {
        switch kind(for: type) {
        case .planet: .planet(ArtAdapters.planetInput(system: state.commander.currentSystem, state: state, showPressure: false))
        case let .ship(ship): .ship(ArtAdapters.typeInput(ship, ruleset: state.ruleset))
        case let .object(object): .object(object)
        }
    }
}

/// UI-ENC-075, ART-040: the drawn vignette of the narrative offer page.
struct NarrativeVignetteView: View {
    let type: SpecialEventType
    let state: GameState

    var body: some View {
        Vignette(kind: NarrativeVignette.input(for: type, state: state), seed: state.seed)
            .frame(width: 96, height: 72)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(NarrativeVignette.kind(for: type).isShip ? Text("Ship") : Text("Illustration"))
            .accessibilityAddTraits(.isImage)
    }
}

extension NarrativeVignette.Subject {
    var isShip: Bool {
        if case .ship = self { return true }
        return false
    }
}
