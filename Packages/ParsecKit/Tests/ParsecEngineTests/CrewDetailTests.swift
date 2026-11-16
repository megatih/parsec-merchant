// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecEngine

@Suite("Crew details (CRW)")
struct CrewDetailTests {
    @Test("CRW-001 CRW-002 CRW-003 four skills per crew member; raw skills capped at 10; identity fields")
    func basics() {
        let s = makeEngine().state
        #expect(SkillType.allCases == [.pilot, .fighter, .trader, .engineer])
        #expect(s.mercenaries.allSatisfy { $0.skills.count == 4 && $0.skills.allSatisfy { (1...10).contains($0) } || $0.id >= 34 })
        #expect(s.commander.name == "Test" && s.difficulty == .normal)
    }

    @Test("CRW-004 CRW-007 CRW-008 CRW-009 CRW-069 new-commander validation and preview")
    func newCommander() {
        #expect(CommanderRules.validate(NewGameConfig(commanderName: "", seed: 1)) == .commanderNameRequired)
        #expect(CommanderRules.validate(NewGameConfig(commanderName: "A", skills: [10, 10, 1, 1], seed: 1)) == .invalidSkillAllocation)
        #expect(CommanderRules.validate(NewGameConfig(commanderName: "A", skills: [11, 7, 1, 1], seed: 1)) == .invalidSkillAllocation)
        #expect(CommanderRules.validate(NewGameConfig(commanderName: "A", skills: [8, 8, 2, 2], seed: 1)) == nil)
        for d in Difficulty.allCases {
            #expect(CommanderRules.validate(NewGameConfig(commanderName: "A", difficulty: d, skills: [5, 5, 5, 5], seed: 1)) == nil)
        }
        #expect(NewGameConfig(commanderName: "A", seed: 1).difficulty == .normal)
        if case let .failure(e) = GameEngine.newGame(NewGameConfig(commanderName: " ", seed: 1)) {
            #expect(e == .commanderNameRequired)
        } else {
            Issue.record("accepted empty name")
        }
        let p = CommanderRules.preview(name: "A", skills: [1, 1, 1, 1])
        #expect(p.pointsRemaining == 16 && p.maxima == [10, 10, 10, 10] && p.error == .invalidSkillAllocation)
        #expect(CommanderRules.preview(name: "A", skills: [6, 5, 4, 3]).maxima == [8, 7, 6, 5])
    }

    @Test("CRW-006 the cosmetic ship name survives trades and affects nothing")
    func shipName() {
        var e = makeEngine { s in s.commander.shipName = "Folly"; s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech; s.commander.cash = 30_000 }
        let other = makeEngine { s in s.galaxy.systems[s.commander.currentSystem].techLevel = .hiTech; s.commander.cash = 30_000 }
        #expect(e.state.worth == other.state.worth && e.state.rng == other.state.rng)
        _ = e.perform(.buyShip(.firefly, transfers: []), acknowledging: [.buyShip])
        #expect(e.state.commander.shipName == "Folly")
    }

    @Test("CRW-010 CRW-043 the commander sits in slot 0; quarters = crew slots")
    func commanderSlot() {
        let s = makeEngine().state
        #expect(s.commander.ship.crew[0] == CrewID.commander && s.commander.ship.crew.count == 1 && s.commander.ship.freeQuarters == 0)
    }

    @Test("CRW-011 CRW-012 CRW-015 CRW-017 CRW-019 effective skills: max crew, difficulty, gadgets (+3, cloak Pilot)")
    func effectiveSkills() {
        #expect(Skills.adjustForDifficulty(5, .beginner) == 6 && Skills.adjustForDifficulty(5, .easy) == 6)
        #expect(Skills.adjustForDifficulty(5, .normal) == 5 && Skills.adjustForDifficulty(5, .hard) == 4 && Skills.adjustForDifficulty(5, .impossible) == 4)
        var s = makeEngine(difficulty: .hard).state
        s.mercenaries[CrewID.commander].skills = [5, 1, 1, 1]
        s.commander.ship.gadgets = [.navigatingSystem, .cloakingDevice]
        #expect(s.shipSkills[0] == 10)
        s.mercenaries[CrewID.commander].skills = [1, 1, 1, 1]
        s.commander.ship.gadgets = []
        #expect(s.shipSkills == [1, 1, 1, 1])
        // Opponent / special ships use the same function and game difficulty.
        let monster = s.specialShips.spaceMonster
        let skills = Skills.shipSkills(monster, crew: s.mercenaries, difficulty: .hard, ruleset: s.ruleset)
        #expect(skills[0] == s.mercenaries[CrewID.spaceMonster].skills[0] - 1)
    }

    @Test("CRW-018 CRW-020 haggling computer +1 trader; passengers add their skills")
    func hagglingAndPassengers() {
        var s = makeEngine().state
        let t = s.skill(.trader)
        s.quests.jarek = QuestStatus.Jarek.done
        #expect(s.skill(.trader) == t + 1)
        s.commander.ship.crew = [CrewID.commander, CrewID.wild]
        #expect(s.shipSkills[SkillType.fighter.rawValue] == 10)
    }

    @Test("CRW-029 CRW-030 CRW-032 CRW-034 wages: (P+F+T+E)×3; specials free; sum stops at first vacancy")
    func wages() {
        var s = makeEngine().state
        let m = 5
        s.mercenaries[m].skills = [4, 7, 3, 6]
        #expect(s.dailyRate(of: m) == 60)
        #expect(s.dailyRate(of: CrewID.zeethibal) == 0 && s.dailyRate(of: CrewID.wild) == 0)
        s.commander.ship.crew = [CrewID.commander, nil, m]
        #expect(s.mercenaryCosts == 0)
        s.commander.ship.crew = [CrewID.commander, m, nil]
        #expect(s.mercenaryCosts == 60)
    }

    @Test("CRW-038 CRW-039 specials cannot be fired; a fired mercenary relocates within 20 parsecs")
    func firing() {
        var e = makeEngine { s in s.commander.ship.crew = [CrewID.commander, CrewID.jarek, 7] }
        #expect(e.perform(.fire(crewID: CrewID.jarek), acknowledging: [.fireMercenary]).rejection == .cannotFireSpecialPassenger)
        _ = e.perform(.fire(crewID: 7), acknowledging: [.fireMercenary])
        let home = e.state.galaxy.systems[e.state.mercenaries[7].systemID ?? 0]
        #expect(GalaxyGenerator.distance(home, e.state.currentSystem, rule: .floor) < 20)
        #expect(e.state.commander.ship.crew == [CrewID.commander, CrewID.jarek, nil])
        var z = makeEngine { s in s.commander.ship.crew = [CrewID.commander, CrewID.zeethibal] }
        #expect(z.perform(.fire(crewID: CrewID.zeethibal), acknowledging: [.fireMercenary]).rejection == nil)
    }

    @Test("CRW-041 CRW-062 hiring/firing and random skill changes recalculate buy prices when Trader changes")
    func priceRecalc() {
        var s = makeEngine { s in setMarket(&s, buy: 500, sell: 400) }.state
        s.mercenaries[CrewID.commander].skills = [1, 1, 9, 1]
        s.changeRandomSkill(-1)
        #expect(s.mercenaries[CrewID.commander].skills == [1, 1, 8, 1])
        let expected = 400 * (103 + 10 - s.skill(.trader)) / 100
        let traded = s.ruleset.tables.tradeItems.enumerated().filter { Pricing.itemTraded($1, in: s.currentSystem, ruleset: s.ruleset) }.map(\.offset)
        for i in traded { #expect(s.buyPrices[i] == expected) }
        #expect(!traded.isEmpty)
    }

    @Test("CRW-052 Windows random increases stop at 9; Modern reaches 10")
    func randomIncrease() {
        var w = makeEngine().state
        w.mercenaries[CrewID.commander].skills = [9, 9, 9, 9]
        w.changeRandomSkill(1)
        #expect(w.mercenaries[CrewID.commander].skills == [9, 9, 9, 9])
        var m = makeEngine(.modern).state
        m.mercenaries[CrewID.commander].skills = [9, 9, 9, 9]
        m.changeRandomSkill(1)
        #expect(m.mercenaries[CrewID.commander].skills.reduce(0, +) == 37)
    }

    @Test("CRW-068 crew preview breaks down effective skills")
    func preview() {
        var s = makeEngine().state
        s.commander.ship.gadgets = [.targetingSystem]
        let p = s.crewPreview
        #expect(p.gadgetBonus == [0, 3, 0, 0] && p.difficultyAdjustment == 0 && p.freeQuarters == 0)
        #expect(p.effectiveSkills[1] == p.crewMaximum[1] + 3)
    }
}
