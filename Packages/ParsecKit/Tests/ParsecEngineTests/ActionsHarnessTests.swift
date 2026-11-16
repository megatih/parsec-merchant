// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecEngine

struct HarnessActions: Decodable {
    struct Snap: Decodable {
        let cash, debt, record, reputation, days, shipType, weapons, killsP, killsT, encType: Int
        let cargo, priceCargo, skills, oppCargo: [Int]
        let insurance: Bool
    }
    struct Case: Decodable {
        let kind: String
        let warp, oppType: Int
        let after: Snap
    }
    let seed: Int32
    let difficulty: Int
    let cases: [Case]
}

// Encounter actions vs C# (all dialogs answered Yes): submit (fine, goods removal), bribe (amount), surrender to
// pirates (sorted looting with hidden bays, blackmail) and police, Arrested (term, fine, confiscation, Flea, debt
// paydown, interest, IncDays), plunder record/bounty/kills, tonics, captain training, attack/flee verification.
@Suite("Encounter actions vs C# harness (Windows 2.01)")
struct ActionsHarnessTests {
    static let runs: [HarnessActions] = (try? Fixtures.decode([HarnessActions].self, "harness/actions-windows201.json")) ?? []
    static let yes: Set<WarningID> = Set(WarningID.allCases)

    @Test("Actions match C# case by case", arguments: 0..<6)
    func replay(_ index: Int) throws {
        try #require(index < Self.runs.count)
        let run = Self.runs[index]
        var e = GameEngine(config: NewGameConfig(commanderName: "Harness", difficulty: Difficulty(rawValue: run.difficulty) ?? .normal,
                                                 ruleset: .windows201, seed: UInt64(UInt32(bitPattern: run.seed))))
        for (k, c) in run.cases.enumerated() {
            e.state.warpSystem = c.warp
            var ship = Ship(type: .beetle, spec: e.ruleset.tables.ship(.beetle))
            ship.crew[0] = CrewID.commander
            ship.shields = [ShieldInstance(type: .reflective, charge: 200)]
            e.state.commander.ship = ship
            e.state.commander.priceCargo = Array(repeating: 0, count: 10)
            e.state.commander.ship.cargo[8] = 3 + k % 4; e.state.commander.priceCargo[8] = 9_000
            e.state.commander.ship.cargo[3] = 5 + k % 7; e.state.commander.priceCargo[3] = 1_750
            e.state.commander.ship.cargo[9] = k % 3; e.state.commander.priceCargo[9] = 4_000 * (k % 3)
            e.state.commander.cash = k % 2 == 0 ? 50_000 : 900
            e.state.commander.debt = k % 4 == 3 ? 2_000 : 0
            e.state.commander.policeRecordScore = [0, -8, -40, 12, -120][k % 5]
            e.state.commander.reputationScore = [0, 50, 400][k % 3]
            e.state.mercenaries[0].skills = [5, 5, 5, 5]
            let opp = e.state.generateOpponent(OpponentType(rawValue: c.oppType) ?? .pirate)
            var enc = EncounterState(type: .pirateAttack, opponent: opp)
            enc.opponentDisabled = c.kind == "plunderPirateDisabled"
            func act(_ type: EncounterType, _ action: EncounterAction) {
                enc.type = type
                e.state.phase = .encounter(enc)
                _ = e.perform(.encounter(action), acknowledging: Self.yes)
            }
            switch c.kind {
            case "submit": act(.policeInspect, .submit)
            case "bribe": act(.policeInspect, .bribe)
            case "surrenderPirate": act(.pirateAttack, .surrender)
            case "surrenderPolice":
                // C# EncounterVerifySurrender only *returns* Arrested; Arrested() runs later in Travel (covered by "arrest").
                enc.type = .policeAttack
                e.state.phase = .encounter(enc)
                let r = e.perform(.encounter(.surrender))
                let refused = e.state.commander.policeRecordScore <= -100
                #expect(refused ? r.rejection == .surrenderRefused : r.decision == .confirm(Confirmation(.surrenderToPolice)))
            case "arrest": _ = e.state.arrested()
            case "plunderTrader":
                act(.traderSurrender, .plunder)
                _ = e.perform(.plunderDone)
            case "plunderPirateDisabled":
                act(.pirateDisabled, .plunder)
                _ = e.perform(.plunderDone)
            case "drinkGood": act(.bottleGood, .drink)
            case "drinkOld": act(.bottleOld, .drink)
            case "meetAhab": act(.captainAhab, .meet)
            case "attackPolice":
                enc.type = .policeIgnore
                _ = e.verifyAttack(&enc, Self.yes)
            case "attackTrader":
                enc.type = .traderIgnore
                _ = e.verifyAttack(&enc, Self.yes)
            case "fleeInspect":
                enc.type = .policeInspect
                _ = e.verifyFlee(&enc, Self.yes)
            default: Issue.record("unknown kind \(c.kind)")
            }
            let s = e.state, a = c.after
            let tag = "seed \(run.seed) diff \(run.difficulty) case \(k) \(c.kind)"
            #expect(s.commander.cash == a.cash && s.commander.debt == a.debt, "\(tag) cash \(s.commander.cash)/\(a.cash) debt \(s.commander.debt)/\(a.debt)")
            #expect(s.commander.policeRecordScore == a.record, "\(tag) record \(s.commander.policeRecordScore) vs \(a.record)")
            #expect(s.commander.reputationScore == a.reputation && s.commander.days == a.days, "\(tag) reputation/days")
            #expect(s.commander.ship.cargo == a.cargo && s.commander.priceCargo == a.priceCargo, "\(tag) cargo/basis")
            #expect(s.commander.ship.type.rawValue == a.shipType, "\(tag) ship type")
            #expect(s.mercenaries[0].skills == a.skills, "\(tag) skills")
            #expect(s.commander.kills.pirates == a.killsP && s.commander.kills.traders == a.killsT, "\(tag) kills")
            if case let .encounter(now) = s.phase, ["attackPolice", "attackTrader", "fleeInspect"].contains(c.kind) {
                #expect(now.type.rawValue == a.encType, "\(tag) encounter type")
            }
            e.state.phase = .docked
        }
    }
}
