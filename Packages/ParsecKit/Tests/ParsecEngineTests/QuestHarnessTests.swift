// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecEngine

struct HarnessQuests: Decodable {
    struct Snap: Decodable {
        let cash, record, hull, tribbles, sysEvent, zSystem: Int
        let cargo, priceCargo, crew, weapons, shields, gadgets, quests, skills, zSkills, buy, sell: [Int]
        let hullUpgraded, canSuperWarp: Bool
        let end: Int?
    }
    struct Event: Decodable {
        let ev, v: Int
        let shown: Bool
        let after: Snap
    }
    let seed: Int32
    let events: [Event]
}

/// Builds the harness setup for special event `ev` under ship variant `v` (see harness/Driver.cs Quests()).
func questScenario(seed: Int32, ev: Int, v: Int) -> GameEngine {
    var e = GameEngine(config: NewGameConfig(commanderName: "Harness", difficulty: .normal, ruleset: .windows201,
                                             seed: UInt64(UInt32(bitPattern: seed))))
    let t = SpecialEventType(rawValue: ev) ?? .artifact
    if v > 0 {
        var ship = Ship(type: .wasp, spec: e.ruleset.tables.ship(.wasp))
        ship.crew[0] = CrewID.commander
        ship.weapons = [.beamLaser]
        e.state.commander.ship = ship
    }
    if v == 2 { e.state.quests.reactor = 1 }
    if v == 3 { e.state.hireCrew(CrewID.wild); e.state.quests.wild = 1 }
    e.state.commander.cash = 600_000
    e.state.commander.reputationScore = 40
    e.state.commander.policeRecordScore = [.eraseRecord, .wild, .reactor, .sculpture].contains(t) ? -10 : 10
    switch t {
    case .artifactDelivery: e.state.quests.artifact = 1
    case .dragonflyBaratas: e.state.quests.dragonfly = 1
    case .dragonflyMelina: e.state.quests.dragonfly = 2
    case .dragonflyRegulas: e.state.quests.dragonfly = 3
    case .dragonflyDestroyed: e.state.quests.dragonfly = 5
    case .experimentStopped: e.state.quests.experiment = 1
    case .gemulonRescued: e.state.quests.gemulon = 1
    case .japoriDelivery: e.state.quests.japori = 1
    case .jarekGetsOut: e.state.hireCrew(CrewID.jarek); e.state.quests.jarek = 1
    case .moonRetirement: e.state.quests.moon = 1
    case .princessCentauri: e.state.quests.princess = 1
    case .princessInthara: e.state.quests.princess = 2
    case .princessQonos: e.state.quests.princess = 4
    case .princessReturned: e.state.hireCrew(CrewID.princess); e.state.quests.princess = 4
    case .reactorDelivered: e.state.quests.reactor = 1
    case .scarabDestroyed, .scarabUpgradeHull: e.state.quests.scarab = 2
    case .sculptureDelivered: e.state.quests.sculpture = 1
    case .spaceMonsterKilled: e.state.quests.spaceMonster = 2
    case .tribbleBuyer: e.state.commander.ship.tribbles = 500
    case .wildGetsOut: if v != 3 { e.state.hireCrew(CrewID.wild); e.state.quests.wild = 1 }
    default: break
    }
    e.state.galaxy.systems[e.state.commander.currentSystem].specialEvent = t
    return e
}

// Every special event × four ship setups vs C# HandleSpecialEvent (dialogs answered Yes): ShowSpecialButton, price,
// effects on cash/record/cargo/crew/equipment/hull/tribbles/quest statuses, event replacement or removal, Zeethibal,
// prices after record changes, and the moon ending.
@Suite("Special events vs C# harness (Windows 2.01)")
struct QuestHarnessTests {
    static let runs: [HarnessQuests] = (try? Fixtures.decode([HarnessQuests].self, "harness/quests-windows201.json")) ?? []

    @Test("Special events match C# event by event", arguments: 0..<2)
    func replay(_ index: Int) throws {
        try #require(index < Self.runs.count)
        let run = Self.runs[index]
        for c in run.events {
            var e = questScenario(seed: run.seed, ev: c.ev, v: c.v)
            let tag = "seed \(run.seed) event \(SpecialEventType(rawValue: c.ev).map { "\($0)" } ?? "?") v\(c.v)"
            #expect((e.state.specialEventAvailable != nil) == c.shown, "\(tag) shown")
            _ = e.perform(.specialEvent, acknowledging: Set(WarningID.allCases))
            let s = e.state, a = c.after, ship = s.commander.ship
            #expect(s.commander.cash == a.cash && s.commander.policeRecordScore == a.record, "\(tag) cash/record")
            #expect(ship.cargo == a.cargo && s.commander.priceCargo == a.priceCargo, "\(tag) cargo")
            #expect(ship.crew.map { $0 ?? -1 } == a.crew, "\(tag) crew \(ship.crew) vs \(a.crew)")
            #expect(ship.weapons.map(\.rawValue) == a.weapons, "\(tag) weapons")
            #expect(ship.shields.flatMap { [$0.type.rawValue, $0.charge] } == a.shields, "\(tag) shields")
            #expect(ship.gadgets.map(\.rawValue) == a.gadgets, "\(tag) gadgets")
            #expect(ship.hull == a.hull && ship.hullUpgraded == a.hullUpgraded && ship.tribbles == a.tribbles, "\(tag) hull/tribbles")
            let q = s.quests
            #expect([q.artifact, q.dragonfly, q.experiment, q.gemulon, q.japori, q.jarek, q.moon, q.princess, q.reactor, q.scarab,
                     q.sculpture, q.spaceMonster, q.wild] == a.quests, "\(tag) quests")
            #expect(q.canSuperWarp == a.canSuperWarp, "\(tag) singularity")
            #expect((s.currentSystem.specialEvent?.rawValue ?? -1) == a.sysEvent, "\(tag) system event")
            #expect(s.mercenaries[CrewID.commander].skills == a.skills, "\(tag) skills")
            #expect(s.mercenaries[CrewID.zeethibal].skills == a.zSkills, "\(tag) Zeethibal skills")
            #expect((s.mercenaries[CrewID.zeethibal].systemID ?? -1) == a.zSystem, "\(tag) Zeethibal system")
            #expect(s.buyPrices == a.buy && s.sellPrices == a.sell, "\(tag) prices")
            let ended: Int? = if case let .gameOver(t) = s.phase { t.rawValue } else { nil }
            #expect(ended == a.end, "\(tag) end")
        }
    }
}
