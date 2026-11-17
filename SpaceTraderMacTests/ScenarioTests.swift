// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import ParsecPersistence
import Testing
@testable import ParsecMerchant

/// Mirrors the flow-2 constants of `SpaceTraderMacUITests/UITestFixtures.swift` (the UI-test target cannot import the
/// app); keep the two files in step.
enum AmbushFixtures {
    static let ambushSeed: UInt64 = 292
    static let ambushTarget = 46
    static let ambushExpectedAttacks = 6
    static let ambushMaxAttacks = 12
}

@MainActor
@Suite("Scenario and developer tester (UI-ENC §14)")
struct ScenarioTests {
    private func isEncounterStart(_ e: GameEvent) -> Bool { if case .encounterStarted = e { true } else { false } }

    private func isFatal(_ e: GameEvent) -> Bool {
        switch e {
        case .playerDestroyed, .bothDestroyed, .escapePodUsed: true
        default: false
        }
    }

    @Test("UI-ENC-090 CHEAT-006 CHEAT-026 CHEAT-049 the pirateAmbush state is built by play: cheats, military laser, target")
    func scenarioState() {
        #expect(PirateAmbushScenario.seed == AmbushFixtures.ambushSeed && PirateAmbushScenario.target == AmbushFixtures.ambushTarget)
        #expect(PirateAmbushScenario.expectedAttacks == AmbushFixtures.ambushExpectedAttacks)
        #expect(PirateAmbushScenario.maxAttacks == AmbushFixtures.ambushMaxAttacks && AmbushFixtures.ambushMaxAttacks <= 30)
        let engine = PirateAmbushScenario.make()
        let fresh = GameEngine(config: NewGameConfig(commanderName: "Ambush", difficulty: .normal, skills: [5, 5, 5, 5],
                                                     ruleset: .modern, seed: AmbushFixtures.ambushSeed))
        let st = engine.state
        #expect(st.cheatsUsed && st.rulesetID == .modern && st.difficulty == .normal && st.commander.name == "Ambush")
        #expect(st.commander.ship.weapons.first == .militaryLaser)
        #expect(st.warpSystem == AmbushFixtures.ambushTarget && st.phase == .docked)
        // Neither cheat draws RNG.
        #expect(st.rng == fresh.state.rng)
    }

    @Test("UI-ENC-091 the constants: a pirate attack that Attack alone destroys in exactly ambushExpectedAttacks commands")
    func scenarioConstants() throws {
        var engine = PirateAmbushScenario.make()
        let warp = engine.perform(.warp)
        guard case let .encounter(enc) = engine.state.phase else {
            Issue.record("the warp ends in an encounter")
            return
        }
        #expect(enc.type == .pirateAttack && engine.encounterPreview?.badge == .pirate)
        #expect(warp.decision == nil && warp.events.filter(isEncounterStart).count == 1)
        if case let .encounterStarted(type, _, _, _)? = warp.events.first(where: isEncounterStart) { #expect(type == .pirateAttack) }
        var attacks = 0
        var last = StepResult()
        while case .encounter = engine.state.phase, attacks < AmbushFixtures.ambushMaxAttacks {
            last = engine.perform(.encounter(.attack))
            attacks += 1
            #expect(last.rejection == nil && last.decision == nil, "attack \(attacks)")
            #expect(!last.events.contains(where: isFatal))
        }
        #expect(attacks == AmbushFixtures.ambushExpectedAttacks)
        #expect(last.events.contains { if case .opponentDestroyed = $0 { true } else { false } })
        #expect(last.events.contains(.arrived(system: AmbushFixtures.ambushTarget)))
        #expect(!last.events.contains(where: isEncounterStart))
        #expect(engine.state.phase == .docked && engine.state.commander.currentSystem == AmbushFixtures.ambushTarget)
    }

    @Test("UI-ENC-093 CHEAT-049 pirateAmbush keeps the app running in the encounter; smoke and unknown names keep exit codes")
    func scenarioRunner() throws {
        // `-PMSeed` is ignored by the named scenario.
        let s = try TestSessions.make(seed: 5)
        #expect(ScenarioRunner.run("pirateAmbush", session: s) == nil)
        let st = try #require(s.state)
        #expect(st.seed == AmbushFixtures.ambushSeed && st.cheatsUsed)
        guard case let .encounter(enc) = st.phase else {
            Issue.record("the scenario warps into the encounter")
            return
        }
        #expect(enc.type == .pirateAttack && s.lastStep?.command == .warp)
        // The scenario game is written by the normal persistence trigger.
        #expect(try s.slotStore.list().contains { $0.isAutosave })
        // Attack until resolved through the session, as flow 2 does.
        var attacks = 0
        while case .encounter = s.state?.phase, attacks < AmbushFixtures.ambushMaxAttacks {
            s.send(.encounter(.attack))
            attacks += 1
        }
        #expect(attacks == AmbushFixtures.ambushExpectedAttacks)
        #expect(s.state?.phase == .docked && s.state?.commander.currentSystem == AmbushFixtures.ambushTarget)

        #expect(ScenarioRunner.run("smoke", session: try TestSessions.make()) == 0)
        #expect(ScenarioRunner.run("nope", session: try TestSessions.make()) == 2)
        // Scenarios other than smoke are Debug-only (CHEAT-047).
        #expect(LaunchOptions.parse(["-PMScenario", "pirateAmbush"], isDebug: false).scenario == nil)
        #expect(LaunchOptions.parse(["-PMScenario", "pirateAmbush"], isDebug: true).scenario == "pirateAmbush")
    }

    @Test("UI-ENC-096 encounter:<type> fixtures reach the plunder, trade and arrest-report sheets for the identifier walk")
    func encounterFixtures() throws {
        #expect(EncounterFixtureScenario.type(named: "encounter:pirateSurrender") == .pirateSurrender)
        #expect(EncounterFixtureScenario.type(named: "encounter:nope") == nil && EncounterFixtureScenario.type(named: "x") == nil)
        #expect(LaunchOptions.parse(["-PMScenario", "encounter:traderSell"], isDebug: false).scenario == nil)

        func session(_ type: EncounterType) throws -> GameSession {
            let s = try TestSessions.make()
            #expect(ScenarioRunner.run("encounter:\(type)", session: s) == nil)
            let st = try #require(s.state)
            #expect(st.cheatsUsed && EncFx.encounter(st)?.type == type)
            return s
        }
        let pirate = try session(.pirateSurrender)
        pirate.performEncounterAction(.plunder)
        guard case .sheet(.plunder) = pirate.presentation else {
            Issue.record("Plunder opens the plunder sheet (got \(String(describing: pirate.presentation)))")
            return
        }
        let trader = try session(.traderSell)
        trader.performEncounterAction(.trade)
        guard case .sheet(.tradeInOrbit) = trader.presentation else {
            Issue.record("Trade opens the trade-in-orbit sheet (got \(String(describing: trader.presentation)))")
            return
        }
        // A game installed in an encounter (as a loaded mid-encounter save is) resumes its trip, so the end of the
        // encounter still shows its report (UI-ENC-053, -061).
        let police = try session(.policeAttack)
        police.performEncounterAction(.surrender)
        if case let .confirmation(pending) = police.presentation { police.confirm(pending) }
        guard case let .sheet(.report(.arrest(report))) = police.presentation else {
            Issue.record("Surrendering to the police opens the arrest report (got \(String(describing: police.presentation)))")
            return
        }
        #expect(report.arrival?.encounters.map(\.outcome) == [.arrested])
        #expect(report.arrival?.section(.costs) == nil, "a resumed trip has no departure costs")

        // `specialEvent`: docked, the current system offers an available special event; Read opens the offer page.
        let special = try TestSessions.make()
        #expect(ScenarioRunner.run(EncounterFixtureScenario.specialEventName, session: special) == nil)
        let offered = try #require(special.state?.specialEventAvailable)
        #expect(special.state?.phase == .docked && special.state?.cheatsUsed == true)
        special.openSpecialEvent()
        #expect(special.presentation == .sheet(.narrative(.offer(offered))))
    }

    @Test("UI-ENC-092 CHEAT-038 Test opens the developer tester in Debug; it lists every ALR row and narrative page")
    func developerTester() throws {
        #expect(DeveloperTester.opens(after: .cheat(.test), isDebug: true))
        #expect(!DeveloperTester.opens(after: .cheat(.test), isDebug: false))
        #expect(!DeveloperTester.opens(after: .cheat(.enable), isDebug: true))

        let s = try TestSessions.playing()
        s.send(.cheat(.enable))
        let before = try #require(s.state)
        s.send(.cheat(.test))
        #expect(s.presentation == .sheet(.developerTester) || s.pendingPresentations.contains(.sheet(.developerTester)))
        #expect(s.state?.commander == before.commander && s.state?.rng == before.rng)

        #expect(DeveloperTester.items.count == 188 + SpecialEventType.allCases.count)
        let state = try #require(s.state)
        for row in ALRCatalog.rows {
            let sample = ALRCatalog.sample(for: row, state: state, session: s)
            #expect(!sample.surface.isEmpty && !sample.title.isEmpty && !sample.message.isEmpty, "row \(row.number)")
            if case let .confirmation(w) = row.presentation {
                #expect(sample.isDestructive == ConfirmationText.isDestructive(w))
            }
        }
        for type in SpecialEventType.allCases {
            let sample = ALRCatalog.narrativeSample(type)
            #expect(!sample.title.isEmpty && !sample.message.isEmpty, "\(type)")
        }
        #expect(AXID.DevTester.sheet == "devTester.sheet" && AXID.DevTester.alr(12) == "devTester.alr.12")
        #expect(AXID.DevTester.narrative(.moonRetirement) == "devTester.narrative.moonRetirement")
        #expect(AXID.DevTester.all.allSatisfy(AXID.all.contains))
        #expect(Presentation.sheet(.developerTester).id == "sheet.developerTester")
    }
}
