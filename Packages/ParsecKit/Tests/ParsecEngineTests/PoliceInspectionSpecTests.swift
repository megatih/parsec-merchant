// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecEngine

private let firearms = TradeItemType.firearms.rawValue
private let narcotics = TradeItemType.narcotics.rawValue

@Suite("POL §4: police inspection")
struct PoliceInspectionSpecTests {
    @Test("POL-050 an inspection offers attack, flee, submit and bribe, never ignore")
    func inspectionActions() {
        #expect(EncounterType.policeInspect.actions == [.attack, .flee, .submit, .bribe])
        var e = Pol.engine(.policeInspect)
        let before = e.state
        #expect(e.perform(.encounter(.ignore)).rejection == .encounterActionUnavailable)
        #expect(e.state == before)
    }

    @Test("POL-051 detectable illegal cargo exceeds the hidden bays; special cargo is Wild, reactor or sculpture")
    func detectable() {
        var s = makeEngine().state
        s.commander.ship.gadgets = [.hiddenCargoBays]
        s.commander.ship.cargo[firearms] = 3
        s.commander.ship.cargo[narcotics] = 2
        #expect(!s.detectableIllegalCargo && !s.detectableIllegalCargoOrPassengers)
        s.commander.ship.cargo[narcotics] = 3
        #expect(s.detectableIllegalCargo && s.detectableIllegalCargoOrPassengers)
        var t = makeEngine().state
        #expect(!t.illegalSpecialCargo)
        t.quests.reactor = 5
        #expect(t.illegalSpecialCargo && t.detectableIllegalCargoOrPassengers && !t.detectableIllegalCargo)
        t.quests.reactor = 0
        t.quests.sculpture = QuestStatus.Sculpture.inTransit
        #expect(t.illegalSpecialCargo)
        t.quests.sculpture = 0
        t.commander.ship.crew.append(CrewID.wild)
        #expect(t.illegalSpecialCargo)
    }

    @Test("POL-053 with nothing illegal, attack and bribe ask submitWithNothingIllegal and flee asks fleeInspection")
    func nothingIllegal() {
        var e = Pol.engine(.policeInspect)
        let before = e.state
        #expect(e.perform(.encounter(.attack)).decision == .confirm(Confirmation(.submitWithNothingIllegal)))
        #expect(e.perform(.encounter(.bribe)).decision == .confirm(Confirmation(.submitWithNothingIllegal)))
        #expect(e.perform(.encounter(.flee)).decision == .confirm(Confirmation(.fleeInspection)))
        let amount = e.state.bribeAmount ?? -1
        #expect(e.perform(.encounter(.bribe), acknowledging: [.submitWithNothingIllegal]).decision
                == .confirm(Confirmation(.bribe, amounts: [amount])))
        #expect(e.state == before)
    }

    @Test("POL-055 submit with anything detectable needs submitInspection; declining changes nothing; clean submit asks nothing")
    func submitConfirmation() {
        for adjust: (inout GameState) -> Void in [{ $0.commander.ship.cargo[firearms] = 1 }, { $0.quests.sculpture = QuestStatus.Sculpture.inTransit }] {
            var e = Pol.engine(.policeInspect) { adjust(&$0) }
            let before = e.state
            #expect(e.perform(.encounter(.submit)).decision == .confirm(Confirmation(.submitInspection)))
            #expect(e.state == before)
        }
        var e = Pol.engine(.policeInspect)
        let r = e.perform(.encounter(.submit))
        #expect(r.decision == nil && r.events.contains(.inspectionClean))
    }

    @Test("POL-056 submitting detectable goods: all illegal units removed (hidden too), basis 0, fine, shortfall to debt, −1")
    func submitFine() {
        var e = Pol.engine(.policeInspect) { s in
            s.commander.ship.gadgets = [.hiddenCargoBays]
            s.commander.ship.cargo[firearms] = 4
            s.commander.ship.cargo[narcotics] = 3
            s.commander.priceCargo[firearms] = 500
            s.commander.priceCargo[narcotics] = 900
            s.commander.ship.cargo[0] = 2
            s.commander.priceCargo[0] = 60
            s.commander.cash = 100
            s.commander.policeRecordScore = 2
        }
        // Worth 10100 on Normal: ceil(10100 / 40 / 50) × 50 = 300.
        #expect(e.state.inspectionFine == 300)
        let r = e.perform(.encounter(.submit), acknowledging: Pol.yes)
        #expect(r.events.first == .fined(300))
        let s = e.state
        #expect(s.commander.ship.cargo[firearms] == 0 && s.commander.ship.cargo[narcotics] == 0)
        #expect(s.commander.priceCargo[firearms] == 0 && s.commander.priceCargo[narcotics] == 0)
        #expect(s.commander.ship.cargo[0] == 2 && s.commander.priceCargo[0] == 60)
        #expect(s.commander.cash == 0 && s.commander.debt == 200)
        #expect(s.commander.policeRecordScore == 1)
    }

    @Test("POL-057 fine examples: divisor 40 on Normal, 60 Beginner, 20 Impossible; clamp 100…10000")
    func fineExamples() {
        func fine(_ w: Int, _ d: Difficulty = .normal) -> Int {
            var s = makeEngine(difficulty: d).state
            Pol.setWorth(&s, w)
            return s.inspectionFine
        }
        #expect(fine(11_000) == 300)
        #expect(fine(10_001) == 300)
        #expect(fine(3_000) == 100)
        #expect(fine(1_000_000) == 10_000)
        #expect(fine(0) == 100)
        #expect(fine(-4_000) == 100)
        #expect(fine(11_000, .beginner) == 200) // 183.3 / 50 → 4
        #expect(fine(11_000, .impossible) == 550) // 550 / 50 = 11
    }

    @Test("POL-058 a clean submit: +1, inspectionClean, hidden goods stay with their basis")
    func cleanSubmit() {
        var e = Pol.engine(.policeInspect) { s in
            s.commander.ship.gadgets = [.hiddenCargoBays]
            s.commander.ship.cargo[narcotics] = 5
            s.commander.priceCargo[narcotics] = 1_500
            s.commander.policeRecordScore = -2
        }
        let r = e.perform(.encounter(.submit))
        #expect(r.events.first == .inspectionClean)
        #expect(e.state.commander.policeRecordScore == -1)
        #expect(e.state.commander.ship.cargo[narcotics] == 5 && e.state.commander.priceCargo[narcotics] == 1_500)
    }

    @Test("POL-059 a submit with special cargo ends in arrest after the fine and −1; without, it ends normally")
    func submitArrest() {
        var e = Pol.engine(.policeInspect) { s in
            s.quests.sculpture = QuestStatus.Sculpture.inTransit
            s.commander.ship.cargo[firearms] = 2
            s.commander.cash = 50_000
            s.commander.policeRecordScore = 20
        }
        let r = e.perform(.encounter(.submit), acknowledging: Pol.yes)
        let fineIndex = r.events.firstIndex { if case .fined = $0 { true } else { false } }
        let arrestIndex = r.events.firstIndex { if case .arrested = $0 { true } else { false } }
        #expect(fineIndex != nil && arrestIndex != nil)
        if let fineIndex, let arrestIndex {
            #expect(fineIndex < arrestIndex)
            // −1 made the record 19, so the arrest term is max(30, −19) = 30 days; then rec = −5.
            if case let .arrested(term, _, _) = r.events[arrestIndex] { #expect(term == 30) }
        }
        #expect(e.state.commander.policeRecordScore == -5 && e.state.phase == .docked)
        e = Pol.engine(.policeInspect) { $0.commander.ship.cargo[firearms] = 2 }
        let r2 = e.perform(.encounter(.submit), acknowledging: Pol.yes)
        #expect(!r2.events.contains { if case .arrested = $0 { true } else { false } })
        #expect(e.state.phase == .docked && r2.events.contains(.arrived(system: e.state.warpSystem)))
    }

    @Test("POL-063 a completed submit resumes transit; the trip's inspected flag keeps further inspections away")
    func inspectedFlag() {
        var e = Pol.engine(.policeInspect, clicks: 5)
        _ = e.perform(.encounter(.submit))
        if case let .encounter(next) = e.state.phase { #expect(next.clicks < 5) } else { #expect(e.state.phase == .docked) }
        var s = makeEngine().state
        s.galaxy.systems[s.warpSystem].politics = .military
        s.commander.policeRecordScore = -1
        s.inspected = false
        var inspections = 0
        for _ in 0..<400 {
            inspections += s.determineRandomEncounter(clicks: 10)?.type == .policeInspect ? 1 : 0
        }
        #expect(inspections == 1 && s.inspected)
    }
}

@Suite("POL §5-6: bribe and customs yield")
struct PoliceBribeSpecTests {
    @Test("POL-065 bribe checks: customs → bribeNotAccepted, bribe level 0 → bribeNotPossible, then nothing illegal; level table")
    func bribeChecks() {
        var e = Pol.engine(.marieCelestePolice)
        #expect(e.perform(.encounter(.bribe)).rejection == .bribeNotAccepted)
        e = Pol.engine(.policeInspect) { s in s.galaxy.systems[s.warpSystem].politics = .cybernetic }
        #expect(e.perform(.encounter(.bribe)).rejection == .bribeNotPossible)
        e = Pol.engine(.policeInspect)
        #expect(e.perform(.encounter(.bribe)).decision == .confirm(Confirmation(.submitWithNothingIllegal)))
        let levels: [PoliticalSystemType: Int] = [
            .anarchy: 7, .capitalist: 1, .communist: 5, .confederacy: 3, .corporate: 2, .cybernetic: 0, .democracy: 2,
            .dictatorship: 2, .fascist: 0, .feudal: 6, .military: 0, .monarchy: 4, .pacifist: 1, .socialist: 6, .satori: 0,
            .technocracy: 2, .theocracy: 0,
        ]
        for (gov, level) in levels { #expect(Ruleset.windows201.tables.politics(gov).bribeLevel == level, "\(gov)") }
    }

    @Test("POL-066 bribe = clamp(ceil(W / level / diffMod / 100) × 100 × passMod); confirmation carries the amount")
    func bribeFormula() {
        func bribe(_ w: Int, _ d: Difficulty, gov: PoliticalSystemType = .capitalist, _ adjust: (inout GameState) -> Void = { _ in }) -> Int? {
            var s = makeEngine(difficulty: d).state
            s.galaxy.systems[s.warpSystem].politics = gov
            adjust(&s)
            Pol.setWorth(&s, w)
            return s.bribeAmount
        }
        #expect(bribe(50_000, .normal, gov: .confederacy) == 900) // 50000/3/20/100 = 8.33 → 9
        #expect(bribe(50_000, .beginner, gov: .anarchy) == 300) // 50000/7/30/100 = 2.38 → 3
        let wild: (inout GameState) -> Void = { $0.commander.ship.crew.append(CrewID.wild) }
        #expect(bribe(11_000, .easy, wild) == 1_000) // diffMod 25: 4.4 → 5 → 500 × 2
        #expect(bribe(11_000, .impossible, wild) == 3_300) // diffMod 10: 11 → 1100 × 3
        #expect(bribe(1_000, .normal) == 100)
        #expect(bribe(10_000_000, .normal) == 10_000)
        var e = Pol.engine(.policeInspect) { $0.commander.ship.cargo[firearms] = 1 }
        let amount = e.state.bribeAmount ?? -1
        #expect(e.perform(.encounter(.bribe)).decision == .confirm(Confirmation(.bribe, amounts: [amount])))
    }

    @Test("POL-068 bribe examples (Normal, level 1; Hard with the reactor; sculpture multiplies)")
    func bribeExamples() {
        func bribe(_ w: Int, _ d: Difficulty, _ adjust: (inout GameState) -> Void = { _ in }) -> Int? {
            var s = makeEngine(difficulty: d).state
            s.galaxy.systems[s.warpSystem].politics = .capitalist
            adjust(&s)
            Pol.setWorth(&s, w)
            return s.bribeAmount
        }
        #expect(bribe(11_000, .normal) == 600)
        #expect(bribe(10_001, .normal) == 600)
        #expect(bribe(30_000, .hard) { $0.quests.reactor = 3 } == 6_000)
        #expect(bribe(11_000, .normal) { $0.quests.sculpture = QuestStatus.Sculpture.inTransit } == 1_200)
    }

    @Test("POL-069 a bribe above cash is rejected; otherwise cash −= bribe, bribed event, encounter ends, record unchanged")
    func bribePayment() {
        var e = Pol.engine(.policeInspect) { s in s.commander.ship.cargo[narcotics] = 1; s.commander.cash = 50 }
        let before = e.state
        #expect(e.perform(.encounter(.bribe), acknowledging: Pol.yes).rejection == .insufficientFunds)
        #expect(e.state == before)
        e = Pol.engine(.policeInspect) { s in s.commander.ship.cargo[narcotics] = 1; s.commander.policeRecordScore = 3 }
        let amount = e.state.bribeAmount ?? -1
        #expect(amount == 800) // worth 15000: ceil(7.5) × 100
        let r = e.perform(.encounter(.bribe), acknowledging: Pol.yes)
        #expect(r.events.first == .bribed(800))
        #expect(e.state.commander.cash == 4_200 && e.state.commander.policeRecordScore == 3)
        #expect(e.state.phase == .docked && e.state.commander.ship.cargo[narcotics] == 1)
    }

    @Test("POL-071 yield with special cargo needs surrenderToPolice and then arrests")
    func yieldArrest() {
        for adjust: (inout GameState) -> Void in [{ $0.commander.ship.crew.append(CrewID.wild) }, { $0.quests.reactor = 4 },
                                                  { $0.quests.sculpture = QuestStatus.Sculpture.inTransit }] {
            var e = Pol.engine(.marieCelestePolice) { s in adjust(&s); s.commander.cash = 50_000 }
            let before = e.state
            #expect(e.perform(.encounter(.yield)).decision == .confirm(Confirmation(.surrenderToPolice)))
            #expect(e.state == before)
            let r = e.perform(.encounter(.yield), acknowledging: [.surrenderToPolice])
            #expect(r.events.contains { if case .arrested = $0 { true } else { false } })
            #expect(e.state.commander.policeRecordScore == -5 && e.state.phase == .docked)
        }
    }

    @Test("POL-072 yield without special cargo: submitInspection, rec = min(rec, −5), illegal goods and basis removed")
    func yieldGoods() {
        for (rec, expected) in [(10, -5), (-20, -20)] {
            var e = Pol.engine(.marieCelestePolice) { s in
                s.commander.policeRecordScore = rec
                s.commander.ship.gadgets = [.hiddenCargoBays]
                s.commander.ship.cargo[narcotics] = 4
                s.commander.priceCargo[narcotics] = 3_000
                s.commander.ship.cargo[3] = 2
                s.commander.priceCargo[3] = 700
            }
            #expect(e.perform(.encounter(.yield)).decision == .confirm(Confirmation(.submitInspection)))
            let r = e.perform(.encounter(.yield), acknowledging: [.submitInspection])
            #expect(r.events.first == .yielded)
            let s = e.state
            #expect(s.commander.policeRecordScore == expected)
            #expect(s.commander.ship.cargo[narcotics] == 0 && s.commander.priceCargo[narcotics] == 0)
            #expect(s.commander.ship.cargo[3] == 2 && s.commander.priceCargo[3] == 700)
            #expect(s.phase == .docked)
        }
    }
}
