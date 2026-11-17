// SPDX-License-Identifier: GPL-2.0-or-later
// The deterministic template flavor provider (docs/specs/LLM.md §2, LLM-006…010). Pure function of the request; never
// reads the game RNG or Swift's Hasher.
import ParsecEngine

/// LLM-009: the template groups; the raw value is the key's group part (`flavor.<group>.<n>`).
public enum FlavorGroup: String, Sendable, Equatable, CaseIterable {
    case arrivalQuiet = "arrival.quiet"
    case arrivalEventful = "arrival.eventful"
    case arrivalFirstVisit = "arrival.firstVisit"
    case arrivalWormhole = "arrival.wormhole"
    case encounterWon = "encounter.won"
    case encounterFled = "encounter.fled"
    case encounterSurrendered = "encounter.surrendered"
    case encounterLost = "encounter.lost"
    case encounterOther = "encounter.other"
    case questDragonfly = "quest.dragonfly"
    case questSpaceMonster = "quest.spaceMonster"
    case questScarab = "quest.scarab"
    case questJapori = "quest.japori"
    case questJarek = "quest.jarek"
    case questWild = "quest.wild"
    case questReactor = "quest.reactor"
    case questGemulon = "quest.gemulon"
    case questExperiment = "quest.experiment"
    case questArtifact = "quest.artifact"
    case questMoon = "quest.moon"
    case questTribbles = "quest.tribbles"
    case questSculpture = "quest.sculpture"
    case questPrincess = "quest.princess"
    case questGeneric = "quest.generic"
    case gameEndedKilled = "gameEnded.killed"
    case gameEndedRetired = "gameEnded.retired"
    case gameEndedMoon = "gameEnded.moon"
    case achievement

    /// LLM-007: a permanent code per group (1-based position; append new groups at the end).
    public var code: UInt32 {
        UInt32((Self.allCases.firstIndex(of: self) ?? 0) + 1)
    }

    /// LLM-009: variants per group (at least 3).
    public var variantCount: Int { 3 }

    /// LLM-009: the argument types every key of the group takes.
    public var argTypes: [FlavorArgType] {
        switch self {
        case .arrivalQuiet, .arrivalFirstVisit, .arrivalWormhole: [.system]
        case .arrivalEventful: [.system, .count]
        case .encounterWon, .encounterFled, .encounterSurrendered, .encounterLost, .encounterOther: [.ship]
        case .questDragonfly, .questSpaceMonster, .questScarab, .questJapori, .questJarek, .questWild, .questReactor,
             .questGemulon, .questExperiment, .questArtifact, .questMoon, .questTribbles, .questSculpture, .questPrincess,
             .questGeneric:
            [.system]
        case .gameEndedKilled, .gameEndedRetired, .gameEndedMoon, .achievement: []
        }
    }

    /// LLM-010: the chain of a special event (QST-INDEX §1), or `generic` for the one-offs.
    static func questGroup(_ event: SpecialEventType) -> FlavorGroup {
        switch event {
        case .dragonfly, .dragonflyBaratas, .dragonflyMelina, .dragonflyRegulas, .dragonflyDestroyed, .dragonflyShield:
            .questDragonfly
        case .spaceMonster, .spaceMonsterKilled: .questSpaceMonster
        case .scarab, .scarabDestroyed, .scarabUpgradeHull: .questScarab
        case .japori, .japoriDelivery: .questJapori
        case .jarek, .jarekGetsOut: .questJarek
        case .wild, .wildGetsOut: .questWild
        case .reactor, .reactorDelivered, .reactorLaser: .questReactor
        case .gemulon, .gemulonRescued, .gemulonFuel, .gemulonInvaded: .questGemulon
        case .experiment, .experimentStopped, .experimentFailed: .questExperiment
        case .artifact, .artifactDelivery: .questArtifact
        case .moon, .moonRetirement: .questMoon
        case .tribble, .tribbleBuyer: .questTribbles
        case .sculpture, .sculptureDelivered, .sculptureHiddenBays: .questSculpture
        case .princess, .princessCentauri, .princessInthara, .princessQonos, .princessReturned, .princessQuantum:
            .questPrincess
        case .cargoForSale, .eraseRecord, .skill, .lottery: .questGeneric
        }
    }
}

/// LLM-009: the declared type of a template argument.
public enum FlavorArgType: String, Sendable, Equatable, CaseIterable {
    case system, ship, item, count, credits, skill

    public func matches(_ arg: FlavorArg) -> Bool {
        switch (self, arg) {
        case (.system, .system), (.ship, .ship), (.item, .item), (.count, .count), (.credits, .credits), (.skill, .skill):
            true
        default:
            false
        }
    }
}

/// LLM-009: one catalog key with its argument types.
public struct FlavorCatalogEntry: Sendable, Equatable {
    public var key: String
    public var group: FlavorGroup
    public var argTypes: [FlavorArgType]
}

/// LLM-006: the deterministic provider.
public struct TemplateFlavorProvider: FlavorProvider {
    public init() {}

    public var source: FlavorSource { .template }

    /// LLM-009: every key with its argument types, in group order.
    public static let catalog: [FlavorCatalogEntry] = FlavorGroup.allCases.flatMap { group in
        (1...group.variantCount).map { FlavorCatalogEntry(key: "flavor.\(group.rawValue).\($0)", group: group, argTypes: group.argTypes) }
    }

    /// LLM-006 / LLM-007 / LLM-010: the template line for a request.
    public func line(for request: FlavorRequest) -> FlavorLine {
        let group = request.subject.group
        let variant = Int(FlavorSeed.make(request) % UInt64(group.variantCount)) + 1
        return FlavorLine(key: "flavor.\(group.rawValue).\(variant)", args: Self.args(request))
    }

    static func args(_ request: FlavorRequest) -> [FlavorArg] {
        switch request.subject {
        case let .arrival(system, _, _, _, count):
            request.subject.group == .arrivalEventful ? [.system(system), .count(count)] : [.system(system)]
        case let .encounter(_, opponent, _, _, _): [.ship(opponent)]
        case .quest: [.system(request.system)]
        case .gameEnded, .achievement: []
        }
    }

    public func flavor(for request: FlavorRequest) async -> FlavorText? {
        .template(line(for: request))
    }
}
