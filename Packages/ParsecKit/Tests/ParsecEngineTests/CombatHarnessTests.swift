// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecEngine

struct HarnessCombat: Decodable {
    struct Round: Decodable {
        let result, type: Int
        let disabled: Bool
        let cmdrHull, oppHull, cash, record, reputation: Int
        let cmdrCharges, oppCharges: [Int]
        let contAttack, contFlee: Bool
    }
    struct Fight: Decodable {
        let warp, oppType, encounterType, variant: Int
        let flee: Bool
        let rounds: [Round]
    }
    let seed: Int32
    let difficulty: Int
    let fights: [Fight]
}

// Bit-exact agreement with C# EncounterExecuteAction verifies the combat round (CMB): firing order, to-hit,
// damage with shields/engineer/hull cap, disabling with disruptors, flee/escape formulas, encounter-type updates,
// continuous-attack flags, kills/record/reputation/bounty on victory and the scoop roll draws.
@Suite("Combat rounds vs C# harness (Windows 2.01)")
struct CombatHarnessTests {
    static let runs: [HarnessCombat] = (try? Fixtures.decode([HarnessCombat].self, "harness/combat-windows201.json")) ?? []

    @Test("Combat rounds match C# round by round", arguments: 0..<9)
    func replay(_ index: Int) throws {
        try #require(index < Self.runs.count)
        let run = Self.runs[index]
        var s = GameState(config: NewGameConfig(commanderName: "Harness", difficulty: Difficulty(rawValue: run.difficulty) ?? .normal,
                                                ruleset: .windows201, seed: UInt64(UInt32(bitPattern: run.seed))))
        for (n, f) in run.fights.enumerated() {
            s.warpSystem = f.warp
            let type: ShipType = f.variant >= 3 ? .wasp : .hornet
            var ship = Ship(type: type, spec: s.ruleset.tables.ship(type))
            ship.crew[0] = CrewID.commander
            ship.weapons = Array(repeating: f.variant == 5 ? .photonDisruptor : .beamLaser, count: s.ruleset.tables.ship(type).weaponSlots)
            ship.shields = Array(repeating: ShieldInstance(type: .energy, charge: 100), count: s.ruleset.tables.ship(type).shieldSlots)
            s.commander.ship = ship
            s.commander.cash = 5_000
            s.commander.policeRecordScore = 0
            s.options.disableOpponents = f.variant == 5
            s.options.continuousAttack = f.variant == 2
            let opp = s.generateOpponent(OpponentType(rawValue: f.oppType) ?? .pirate)
            var enc = EncounterState(type: EncounterType(rawValue: f.encounterType) ?? .pirateAttack, opponent: opp)
            enc.cmdrFleeing = f.flee
            for (k, expected) in f.rounds.enumerated() {
                let (result, _) = s.executeRound(&enc)
                let tag = "seed \(run.seed) diff \(run.difficulty) fight \(n) round \(k)"
                let resultCode: Int = switch result {
                case .continue: 0
                case .normal: 1
                case .killed: 2
                case .escapePod: 3
                case .arrested: 4
                }
                #expect(resultCode == expected.result, "\(tag) result")
                #expect(enc.type.rawValue == expected.type, "\(tag) type")
                #expect(enc.opponentDisabled == expected.disabled, "\(tag) disabled")
                #expect(s.commander.ship.hull == expected.cmdrHull, "\(tag) cmdr hull")
                #expect(s.commander.ship.shields.map(\.charge) == expected.cmdrCharges, "\(tag) cmdr shields")
                #expect(enc.opponent.hull == expected.oppHull, "\(tag) opp hull")
                #expect(enc.opponent.shields.map(\.charge) == expected.oppCharges, "\(tag) opp shields")
                #expect(s.commander.cash == expected.cash, "\(tag) cash")
                #expect(s.commander.policeRecordScore == expected.record, "\(tag) record")
                #expect(s.commander.reputationScore == expected.reputation, "\(tag) reputation")
                #expect(enc.continueAttacking == expected.contAttack && enc.continueFleeing == expected.contFlee, "\(tag) continue")
                enc.continueAttacking = false
                enc.continueFleeing = false
                s.pendingScoop = nil
                if s.commander.ship.hull != expected.cmdrHull || enc.opponent.hull != expected.oppHull { return }
            }
        }
    }
}
