// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// Sidebar badges (UI-SHELL-036). Pure over the state.
struct SidebarBadges: Equatable, Sendable {
    static let debtWarningThreshold = 75_000

    var bridgeSpecial: Bool
    var crewForHire: Int
    var bankDebtWarning: Bool

    static func make(state: GameState?) -> SidebarBadges {
        guard let state else { return SidebarBadges(bridgeSpecial: false, crewForHire: 0, bankDebtWarning: false) }
        return SidebarBadges(bridgeSpecial: state.specialEventAvailable != nil,
                             crewForHire: state.phase == .docked ? state.mercenariesForHire.count : 0,
                             bankDebtWarning: state.commander.debt >= debtWarningThreshold)
    }

    /// The badge shown on a section row, if any.
    func badge(for section: Section) -> Badge? {
        switch section {
        case .bridge: bridgeSpecial ? .special : nil
        case .crew: crewForHire > 0 ? .count(crewForHire) : nil
        case .bank: bankDebtWarning ? .debtWarning : nil
        case .market, .shipyard, .outfitter, .galaxy, .quests, .logbook: nil
        }
    }

    enum Badge: Equatable, Sendable {
        case special
        case count(Int)
        case debtWarning

        var accessibilityLabel: LocalizedStringResource {
            switch self {
            case .special: "Special offer here"
            case let .count(n): "\(n) mercenaries for hire"
            case .debtWarning: "Debt warning"
            }
        }
    }
}

/// The sidebar's lock while not docked (UI-SHELL-037).
enum SidebarLock: Equatable, Sendable {
    case none
    case inTransit
    case inEncounter

    /// `transitPlaying`: a running transit playback locks the sidebar as "In transit" (UI-ENC-009).
    static func make(phase: GamePhase?, transitPlaying: Bool = false) -> SidebarLock {
        if transitPlaying { return .inTransit }
        return switch phase {
        case .inTransit: .inTransit
        case .encounter: .inEncounter
        case .docked, .gameOver, nil: .none
        }
    }

    var label: LocalizedStringResource? {
        switch self {
        case .none: nil
        case .inTransit: "In transit"
        case .inEncounter: "In encounter"
        }
    }
}

/// The bottom status bar (UI-SHELL-044).
struct StatusBarModel: Equatable, Sendable {
    var filledBays: Int
    var totalBays: Int
    var fuel: Int
    var fuelCapacity: Int
    var hullPercent: Int
    var latestFeed: FeedItem?

    static func make(state: GameState, feed: [FeedItem]) -> StatusBarModel {
        let ship = state.commander.ship
        let r = state.ruleset
        let strength = ship.hullStrength(r)
        return StatusBarModel(filledBays: state.filledCargoBays, totalBays: ship.cargoBays(r), fuel: ship.fuel,
                              fuelCapacity: state.fuelCapacity, hullPercent: strength > 0 ? ship.hull * 100 / strength : 0,
                              latestFeed: feed.last)
    }

    /// The newest items for the feed overlay, newest first.
    static func overlayItems(_ feed: [FeedItem], limit: Int = 50) -> [FeedItem] {
        Array(feed.suffix(limit).reversed())
    }
}

/// Everything the ship-status inspector shows (UI-SHELL-046…053). Pure over the state.
struct InspectorModel: Equatable, Sendable {
    struct SkillRow: Equatable, Sendable {
        var skill: SkillType
        var base: Int
        var effective: Int
    }

    enum Notoriety: Equatable, Sendable {
        case none
        case bounty(Int)
        case angryKingpins(Int)
    }

    enum SpecialCargo: Equatable, Sendable {
        case tribblesInfestation
        case tribbles(Int)
        case antidote
        case artifact
        case hagglingComputer
        case reactor(enrichedFuelBays: Int)
        case sculpture
        case singularity
    }

    struct CrewRow: Equatable, Sendable {
        var crewID: Int
        var dailyWage: Int
        var isPassenger: Bool
    }

    static let maxTribbles = 100_000

    var commanderName: String
    var difficulty: Difficulty
    var days: Int
    var shipType: ShipType
    var shipName: String?
    var hullPercent: Int
    /// Summed charge and power, nil when the ship has no shields.
    var shields: (charge: Int, power: Int)?
    var cash: Int
    var debt: Int
    var worth: Int
    var skills: [SkillRow]
    var policeRecord: PoliceRecordType
    var policeScore: Int
    var reputation: ReputationType
    var kills: Int
    var notoriety: Notoriety
    var cargo: [(item: TradeItemType, units: Int, averageCost: Int)]
    var specialCargo: [SpecialCargo]
    var weapons: [(type: WeaponType, count: Int)]
    var shieldsInstalled: [(type: ShieldType, count: Int, charge: Int)]
    var gadgets: [(type: GadgetType, count: Int)]
    var escapePod: Bool
    var hardenedHull: Bool
    var freeWeaponSlots: Int
    var freeShieldSlots: Int
    var freeGadgetSlots: Int
    var crew: [CrewRow]
    var freeQuarters: Int
    var dailyCosts: DailyCosts

    static func == (a: InspectorModel, b: InspectorModel) -> Bool {
        a.commanderName == b.commanderName && a.days == b.days && a.cash == b.cash && a.debt == b.debt && a.worth == b.worth
            && a.hullPercent == b.hullPercent && a.skills == b.skills && a.specialCargo == b.specialCargo && a.crew == b.crew
            && a.notoriety == b.notoriety && a.cargo.map(\.units) == b.cargo.map(\.units) && a.dailyCosts == b.dailyCosts
    }

    static func make(state s: GameState) -> InspectorModel {
        let r = s.ruleset
        let ship = s.commander.ship
        let strength = ship.hullStrength(r)
        let power = ship.shieldStrength(r)
        let base = s.mercenaries.indices.contains(CrewID.commander) ? s.mercenaries[CrewID.commander].skills : [0, 0, 0, 0]
        let effective = s.shipSkills
        let score = s.commander.policeRecordScore
        let notoriety: Notoriety = score <= PoliceRecordType.crook.minScore ? .bounty(-1_000 * score)
            : score >= PoliceRecordType.trusted.minScore ? .angryKingpins(score / 5) : .none
        let cargo = TradeItemType.allCases.compactMap { item -> (item: TradeItemType, units: Int, averageCost: Int)? in
            let units = ship.cargo[item.rawValue]
            guard units > 0 else { return nil }
            return (item, units, s.commander.priceCargo[item.rawValue] / units)
        }
        let kills = s.commander.kills
        return InspectorModel(
            commanderName: s.commander.name, difficulty: s.difficulty, days: s.commander.days, shipType: ship.type,
            shipName: s.commander.shipName, hullPercent: strength > 0 ? ship.hull * 100 / strength : 0,
            shields: ship.shields.isEmpty ? nil : (ship.shieldCharge, power),
            cash: s.commander.cash, debt: s.commander.debt, worth: s.worth,
            skills: SkillType.allCases.map { SkillRow(skill: $0, base: base[$0.rawValue], effective: effective[$0.rawValue]) },
            policeRecord: s.policeRecord, policeScore: score, reputation: s.reputation,
            kills: kills.pirates + kills.police + kills.traders, notoriety: notoriety, cargo: cargo,
            specialCargo: specialCargo(s),
            weapons: WeaponType.allCases.compactMap { w in
                let n = ship.weapons.filter { $0 == w }.count
                return n > 0 ? (w, n) : nil
            },
            shieldsInstalled: ShieldType.allCases.compactMap { t in
                let list = ship.shields.filter { $0.type == t }
                return list.isEmpty ? nil : (t, list.count, list.reduce(0) { $0 + $1.charge })
            },
            gadgets: GadgetType.allCases.compactMap { g in
                let n = ship.count(g)
                return n > 0 ? (g, n) : nil
            },
            escapePod: ship.escapePod, hardenedHull: ship.hullUpgraded,
            freeWeaponSlots: max(0, ship.freeWeaponSlots(r)), freeShieldSlots: max(0, ship.freeShieldSlots(r)),
            freeGadgetSlots: max(0, ship.freeGadgetSlots(r)),
            crew: crewRows(s), freeQuarters: max(0, ship.freeQuarters - s.passengersOutsideCrew),
            dailyCosts: s.dailyCosts(to: s.warpSystem))
    }

    /// C# DisplaySpecialCargo order (Form_ViewShip.cs:273-307).
    static func specialCargo(_ s: GameState) -> [SpecialCargo] {
        var out: [SpecialCargo] = []
        let tribbles = s.commander.ship.tribbles
        if tribbles > 0 { out.append(tribbles >= maxTribbles ? .tribblesInfestation : .tribbles(tribbles)) }
        if s.quests.japori == QuestStatus.Japori.inTransit { out.append(.antidote) }
        if s.artifactOnBoard { out.append(.artifact) }
        if s.hagglingComputer { out.append(.hagglingComputer) }
        if s.reactorOnBoard { out.append(.reactor(enrichedFuelBays: 10 - (s.quests.reactor - 1) / 2)) }
        if s.sculptureOnBoard { out.append(.sculpture) }
        if s.quests.canSuperWarp { out.append(.singularity) }
        return out
    }

    static func crewRows(_ s: GameState) -> [CrewRow] {
        let passengers: Set<Int> = [CrewID.wild, CrewID.jarek, CrewID.princess]
        var rows = s.commander.ship.crew.compactMap { $0 }.filter { $0 != CrewID.commander }.map { id in
            CrewRow(crewID: id, dailyWage: passengers.contains(id) ? 0 : s.dailyRate(of: id), isPassenger: passengers.contains(id))
        }
        // Palm passengers sit outside the crew array (CRW-044).
        if !s.ruleset.flags.economy.passengersAsCrew {
            if s.jarekOnBoard { rows.append(CrewRow(crewID: CrewID.jarek, dailyWage: 0, isPassenger: true)) }
            if s.wildOnBoard { rows.append(CrewRow(crewID: CrewID.wild, dailyWage: 0, isPassenger: true)) }
        }
        return rows
    }
}

/// The interim encounter panel's content (UI-SHELL-010). Pure over the engine.
struct InterimEncounterModel: Equatable, Sendable {
    var preview: EncounterPreview
    var clicks: Int
    var destination: Int?

    static func make(engine: GameEngine) -> InterimEncounterModel? {
        guard let preview = engine.encounterPreview, case let .encounter(enc) = engine.state.phase else { return nil }
        return InterimEncounterModel(preview: preview, clicks: enc.clicks, destination: engine.state.transitPreview?.destination)
    }

    /// The command Return sends (ENC-132), when there is a default action that is enabled.
    var returnCommand: Command? {
        guard let a = preview.defaultAction, preview.actions.contains(where: { $0.action == a && $0.enabled }) else { return nil }
        return .encounter(a)
    }
}
