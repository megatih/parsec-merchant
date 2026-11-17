// SPDX-License-Identifier: GPL-2.0-or-later
// UI-ENC §15 engine additions: the tactical readout, the special-event preview and the newspaper wording pack.
import Testing
@testable import ParsecEngine

private func eventEngine(_ event: SpecialEventType, record: Int = 10, _ adjust: (inout GameState) -> Void = { _ in }) -> GameEngine {
    makeEngine { s in
        var ship = freshShip(.wasp, s)
        ship.weapons = [.beamLaser]
        s.commander.ship = ship
        s.commander.cash = 600_000
        s.commander.policeRecordScore = record
        s.commander.reputationScore = 40
        s.galaxy.systems[s.commander.currentSystem].specialEvent = event
        adjust(&s)
    }
}

@Suite("UI-ENC §15: engine queries for the encounter and event UX")
struct EncounterUIQueriesSpecTests {
    /// Brute force over the draws of CMB-049 for one opponent pilot value.
    private func bruteForce(playerPilot: Int, opponentPilot: Int, difficulty: Difficulty) -> (Int, Int) {
        let n = max(1, opponentPilot)
        var hits = 0
        for a in 0..<7 {
            for b in 0..<n where (a + playerPilot / 3) * 2 >= b * (2 + difficulty.rawValue) { hits += 1 }
        }
        return (hits, 7 * n)
    }

    @Test("UI-ENC-104 tacticalReadout: nil outside encounters; visible weapons and shields; flee odds equal brute force")
    func readout() throws {
        #expect(EncSpec.engine().tacticalReadout == nil)
        for difficulty in Difficulty.allCases {
            for pilot in 1...10 {
                let e = EncSpec.encounter(.pirateAttack, difficulty, with: { $0.mercenaries[CrewID.commander].skills[0] = pilot },
                                          opponent: { s in
                                              var o = EncSpec.gnat(s)
                                              o.shields = [ShieldInstance(type: .energy, charge: 10)]
                                              return o
                                          })
                let r = try #require(e.tacticalReadout)
                #expect(r.opponentType == .gnat && r.weapons == [.pulseLaser] && r.shields == [.energy])
                let fraction = try #require(e.fleeProbability)
                if difficulty == .beginner {
                    #expect(fraction == ExactFraction(numerator: 1, denominator: 1) && r.fleeOdds == FleeOdds.good)
                    continue
                }
                // Average of the brute-force probabilities over the generator's pilot values (exact, via cross-multiply).
                let playerPilot = e.state.shipSkills[0]
                let values = e.opponentPilotValues(try #require(EncSpec.current(e)).opponent)
                #expect(values.count == 10)
                var num = 0.0
                for p in values {
                    let (h, t) = bruteForce(playerPilot: playerPilot, opponentPilot: p, difficulty: difficulty)
                    num += Double(h) / Double(t)
                }
                let mean = num / Double(values.count)
                #expect(abs(Double(fraction.numerator) / Double(fraction.denominator) - mean) < 1e-12)
                let word: FleeOdds = mean >= 2.0 / 3.0 - 1e-12 ? .good : (mean >= 1.0 / 3.0 - 1e-12 ? .fair : .poor)
                #expect(r.fleeOdds == word, "pilot \(pilot) \(difficulty)")
            }
        }
    }

    @Test("UI-ENC-104 flee odds words, nil without Flee, fixed crews use their table pilot")
    func oddsWordsAndFixedCrews() throws {
        #expect(FleeOdds.word(numerator: 2, denominator: 3) == .good)
        #expect(FleeOdds.word(numerator: 1, denominator: 3) == .fair)
        #expect(FleeOdds.word(numerator: 1, denominator: 4) == .poor)
        let ignore = EncSpec.encounter(.traderIgnore)
        #expect(try #require(ignore.tacticalReadout).fleeOdds == nil)
        let captain = EncSpec.encounter(.famousCaptainAttack, opponent: { s in
            var o = EncSpec.ship(s, .wasp)
            o.crew[0] = CrewID.famousCaptain
            return o
        })
        let captainShip = try #require(EncSpec.current(captain)).opponent
        let values = captain.opponentPilotValues(captainShip)
        #expect(values == [Skills.shipSkills(captainShip, crew: captain.state.mercenaries,
                                             difficulty: .normal, ruleset: captain.ruleset)[0]])
        #expect(try #require(captain.tacticalReadout).fleeOdds != nil)
    }

    @Test("UI-ENC-044 UI-ENC-104 the readout ignores the opponent's crew, cargo and RNG and draws nothing")
    func fairness() throws {
        let base = EncSpec.encounter(.pirateAttack)
        var other = base
        other.state.mercenaries[CrewID.opponent].skills = [10, 10, 10, 10]
        other.state.rng = EncSpec.engine(seed: 99).state.rng
        if case var .encounter(enc) = other.state.phase {
            enc.opponent.cargo[0] = 5
            other.state.phase = .encounter(enc)
        }
        #expect(base.tacticalReadout == other.tacticalReadout)
        #expect(base.fleeProbability == other.fleeProbability)
        let before = base.state
        _ = base.tacticalReadout
        #expect(base.state == before)
    }

    @Test("UI-ENC-105 specialEventPreview: blocker equals the accepted command's rejection; follow-up consents are no blocker")
    func specialPreview() throws {
        #expect(EncSpec.engine().specialEventPreview == nil || EncSpec.engine().state.specialEventAvailable != nil)
        let cases: [(GameEngine, CommandError?)] = [
            (eventEngine(.moon) { $0.commander.cash = 400_000 }, .insufficientFunds),
            (eventEngine(.jarek) { s in s.commander.ship.crew = [CrewID.commander, 1, 2] }, .noFreeQuarters),
            (eventEngine(.wild, record: -10) { $0.commander.ship.weapons = [.pulseLaser] }, .wildRequiresLaser),
            (eventEngine(.wild, record: -10) { $0.quests.reactor = 3 }, .wildRefusesReactor),
            (eventEngine(.reactor, record: -10) { s in s.hireCrew(CrewID.wild); s.quests.wild = QuestStatus.Wild.started }, nil),
            (eventEngine(.moon), nil),
        ]
        for (engine, expected) in cases {
            let before = engine.state
            let preview = try #require(engine.specialEventPreview)
            #expect(preview.blocker == expected)
            var probe = engine
            #expect(probe.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).rejection == expected)
            #expect(engine.state == before)
            let spec = try #require(engine.state.specialEventSpec(preview.type))
            #expect(preview.price == spec.price && preview.messageOnly == spec.messageOnly)
        }
    }

    @Test("UI-ENC-106 ContentPacks.newsWording is .csharp for Modern and Windows 2.01 and .palm for Palm 1.2.2")
    func newsWording() {
        #expect(Ruleset.modern.content.newsWording == .csharp)
        #expect(Ruleset.windows201.content.newsWording == .csharp)
        #expect(Ruleset.palm122.content.newsWording == .palm)
    }
}
