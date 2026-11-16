// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecEngine

private let firearms = TradeItemType.firearms.rawValue
private let narcotics = TradeItemType.narcotics.rawValue

private func isArrest(_ e: GameEvent) -> Bool { if case .arrested = e { true } else { false } }

@Suite("POL §7: surrender")
struct PoliceSurrenderSpecTests {
    @Test("POL-075 surrender to police: refused at rec ≤ −100, else surrenderToPolice then arrest")
    func surrenderPolice() {
        for type in [EncounterType.policeAttack, .policeSurrender] {
            var e = Pol.engine(type) { $0.commander.policeRecordScore = -100 }
            #expect(e.perform(.encounter(.surrender), acknowledging: Pol.yes).rejection == .surrenderRefused)
            e = Pol.engine(type) { s in s.commander.policeRecordScore = -99; s.commander.cash = 50_000 }
            let before = e.state
            #expect(e.perform(.encounter(.surrender)).decision == .confirm(Confirmation(.surrenderToPolice, amounts: [])))
            #expect(e.state == before)
            let r = e.perform(.encounter(.surrender), acknowledging: [.surrenderToPolice])
            let fine: Int = (1 + 60_000 * 80 / 50_000) * 500 // worth 60000, factor 80
            #expect(r.events.first == .arrested(term: 99, fine: fine, shipSold: false))
        }
    }

    @Test("POL-078 surrender to pirates: no confirmation, raided, hidden bays or sculpture step, then loot, encounter ends")
    func surrenderPirates() {
        var e = Pol.engine(.pirateAttack) { s in
            s.quests.sculpture = QuestStatus.Sculpture.inTransit
            s.commander.ship.cargo[0] = 2
        }
        let r = e.perform(.encounter(.surrender))
        #expect(r.decision == nil && r.rejection == nil)
        #expect(Array(r.events.prefix(2)) == [.sculptureTaken, .looted(units: 2)])
        #expect(e.state.raided && e.state.quests.sculpture == QuestStatus.Sculpture.notStarted)
        #expect(e.state.phase == .docked)
        e = Pol.engine(.scarabAttack, opponent: .scarab) { s in
            s.quests.sculpture = QuestStatus.Sculpture.inTransit
            s.commander.ship.gadgets = [.hiddenCargoBays]
            s.commander.ship.cargo[0] = 9
        }
        let r2 = e.perform(.encounter(.surrender))
        #expect(Array(r2.events.prefix(2)) == [.preciousHidden, .looted(units: 5)]) // 5 − 1 (sculpture) = 4 protected
        #expect(e.state.quests.sculpture == QuestStatus.Sculpture.inTransit && e.state.raided)
    }

    @Test("POL-079 stealable list sorted by trade-item index descending; hidden bays minus Princess/sculpture protect the first units")
    func stealableOrder() {
        var e = Pol.engine(.pirateAttack) { s in
            s.commander.ship.gadgets = [.hiddenCargoBays]
            s.quests.sculpture = QuestStatus.Sculpture.inTransit
            s.commander.ship.cargo[0] = 3
            s.commander.priceCargo[0] = 30
            s.commander.ship.cargo[3] = 2
            s.commander.ship.cargo[narcotics] = 1
            s.commander.ship.cargo[TradeItemType.robots.rawValue] = 2
        }
        // List: R R N O O W W W; protected 5 − 1 = 4 → ore and three waters are stolen.
        _ = e.perform(.encounter(.surrender))
        #expect(e.state.commander.ship.cargo == [0, 0, 0, 1, 0, 0, 0, 0, 1, 2])
        #expect(e.state.commander.priceCargo[0] == 0)
        if case let .encounter(enc) = e.state.phase { Issue.record("still in encounter \(enc.type)") }
        e = Pol.engine(.pirateAttack) { s in
            s.commander.ship.cargo[0] = 4
            s.commander.ship.cargo[TradeItemType.robots.rawValue] = 1
            s.commander.ship.crew.append(CrewID.princess)
            s.commander.ship.gadgets = [.hiddenCargoBays]
        }
        // Princess aboard with hidden bays: protected 5 − 1 = 4 → only the last water is stolen.
        _ = e.perform(.encounter(.surrender))
        #expect(e.state.commander.ship.cargo[0] == 3 && e.state.commander.ship.cargo[TradeItemType.robots.rawValue] == 1)
    }

    @Test("POL-080 Windows: protection beyond the cargo aborts the surrender after the hidden-bays step; encounter stays")
    func surrenderAbort() {
        var e = Pol.engine(.pirateAttack) { $0.commander.ship.gadgets = [.hiddenCargoBays] }
        let cash = e.state.commander.cash
        let r = e.perform(.encounter(.surrender))
        #expect(r.events == [.preciousHidden])
        #expect(e.state.raided && e.state.commander.cash == cash && e.state.commander.debt == 0)
        #expect(Pol.encounter(e).type == .pirateAttack)
        // Modern clamps instead (MOD-012) and charges blackmail.
        e = Pol.engine(.pirateAttack, .modern) { $0.commander.ship.gadgets = [.hiddenCargoBays] }
        let r2 = e.perform(.encounter(.surrender))
        #expect(r2.events.contains(.blackmailed(750)) && e.state.phase == .docked)
    }

    @Test("POL-082 blackmail clamp(W/20, 500, 25000) with the shortfall to debt; looting limited by the pirate's free bays")
    func blackmailAndLoot() {
        func blackmail(_ w: Int) -> (GameEvent?, Int, Int) {
            var e = Pol.engine(.pirateAttack) { Pol.setWorth(&$0, w) }
            let r = e.perform(.encounter(.surrender))
            return (r.events.first, e.state.commander.cash, e.state.commander.debt)
        }
        #expect(blackmail(15_000) == (.blackmailed(750), 4_250, 0))
        #expect(blackmail(10_100) == (.blackmailed(505), 0, 405))
        #expect(blackmail(1_000_000).0 == .blackmailed(25_000))
        #expect(blackmail(5_000).0 == .blackmailed(500))
        var e = Pol.engine(.pirateAttack) { s in
            s.commander.ship.cargo[2] = 4
            s.commander.ship.cargo[7] = 1
            if case var .encounter(enc) = s.phase { enc.opponent.cargo[0] = 13; s.phase = .encounter(enc) }
        }
        let r = e.perform(.encounter(.surrender))
        #expect(r.events.first == .looted(units: 2))
        #expect(e.state.commander.ship.cargo[7] == 0 && e.state.commander.ship.cargo[2] == 3)
    }

    @Test("POL-086 Windows/Modern looting basis: P − P/c (10, 3 → 7)")
    func lootBasis() {
        var e = Pol.engine(.pirateAttack) { s in
            s.commander.ship.cargo[1] = 3
            s.commander.priceCargo[1] = 10
            if case var .encounter(enc) = s.phase { enc.opponent.cargo[0] = 14; s.phase = .encounter(enc) }
        }
        _ = e.perform(.encounter(.surrender))
        #expect(e.state.commander.ship.cargo[1] == 2 && e.state.commander.priceCargo[1] == 7)
    }
}

@Suite("POL §8: arrest")
struct PoliceArrestSpecTests {
    @Test("POL-088 an arrest ends the encounter and the transit: no further clicks run")
    func arrestEndsTransit() {
        var e = Pol.engine(.policeAttack, clicks: 15) { s in s.commander.cash = 50_000 }
        let r = e.perform(.encounter(.surrender), acknowledging: Pol.yes)
        #expect(r.events.contains(where: isArrest))
        #expect(!r.events.contains { if case .encounterStarted = $0 { true } else { false } })
        #expect(e.state.phase == .docked && e.state.encounterTransit == nil)
    }

    @Test("POL-089 term = max(30, −rec); fine = (1 + W·min(80, −rec)/50000)·500 in Int32; ×1.05 with Wild")
    func termAndFine() {
        var s = makeEngine().state
        Pol.setWorth(&s, 11_000)
        s.commander.policeRecordScore = -45
        #expect(s.arrestTerm == 45 && s.arrestFine == (1 + 11_000 * 45 / 50_000) * 500)
        s.commander.ship.crew.append(CrewID.wild)
        #expect(s.arrestFine == Int(Double((1 + 11_000 * 45 / 50_000) * 500) * 1.05))
        // Int32 wrap: 30,000,000 × 80 = 2,400,000,000 wraps to −1,894,967,296 → (1 − 37899) × 500.
        var big = makeEngine().state
        Pol.setWorth(&big, 30_000_000)
        big.commander.policeRecordScore = -80
        #expect(big.arrestFine == -18_949_000)
        #expect(big.arrestFine == Int((1 &+ Int32(30_000_000) &* 80 / 50_000) &* 500))
    }

    @Test("POL-092 fine examples: Windows can be 0 or negative (cash grows); Modern floors at 500; term caps the factor at 80")
    func fineExamples() {
        func arrest(_ rec: Int, _ r: RulesetID = .windows201, wild: Bool = false) -> (term: Int, fine: Int, cash: Int) {
            var s = makeEngine(r).state
            Pol.setWorth(&s, 11_000)
            s.commander.policeRecordScore = rec
            if wild { s.commander.ship.crew.append(CrewID.wild) }
            let events = s.arrested()
            guard case let .arrested(term, fine, _) = events.first else { return (0, 0, 0) }
            return (term, fine, s.commander.cash)
        }
        #expect(arrest(-10).term == 30 && arrest(-10).fine == 1_500)
        #expect(arrest(-10, wild: true).fine == 1_575)
        #expect(arrest(5).fine == 0)
        #expect(arrest(10).fine == -500 && arrest(10).cash == 1_000 + 500)
        #expect(arrest(5, .modern).fine == 500 && arrest(10, .modern).fine == 500)
        #expect(arrest(-200).term == 200 && arrest(-200).fine == (1 + 11_000 * 80 / 50_000) * 500)
    }

    @Test("POL-093 arrest sequence: hidden bays, reactor, sculpture, goods, insurance, antidote, fine, debt and interest, rec −5, IncDays")
    func arrestSequence() {
        var s = makeEngine().state
        s.commander.ship.gadgets = [.hiddenCargoBays, .hiddenCargoBays]
        s.quests.reactor = 6
        s.quests.sculpture = QuestStatus.Sculpture.inTransit
        s.quests.japori = QuestStatus.Japori.inTransit
        s.commander.ship.cargo[firearms] = 3
        s.commander.priceCargo[firearms] = 400
        s.commander.ship.cargo[0] = 1
        s.commander.priceCargo[0] = 20
        s.commander.insurance = true
        s.commander.noClaim = 12
        s.commander.policeRecordScore = -40
        s.commander.cash = 10_000
        s.commander.debt = 30_000
        let days = s.commander.days
        let events = s.arrested()
        // W = 10000 + 10000 − 30000 = −10000 → fine (1 − 8) × 500 = −3500; cash 13500 pays debt down to 16500.
        #expect(events.first == .arrested(term: 40, fine: -3_500, shipSold: false))
        #expect(!s.commander.ship.has(.hiddenCargoBays))
        #expect(s.quests.reactor == 0 && s.quests.sculpture == 0 && s.quests.japori == QuestStatus.Japori.done)
        #expect(s.commander.ship.cargo[firearms] == 0 && s.commander.priceCargo[firearms] == 0)
        #expect(s.commander.ship.cargo[0] == 1 && s.commander.priceCargo[0] == 20)
        #expect(!s.commander.insurance && s.commander.noClaim == 0)
        var debt = 16_500
        for _ in 0..<40 { debt += max(1, Int(Double(debt) * 0.1)) }
        #expect(s.commander.cash == 0 && s.commander.debt == debt)
        #expect(s.commander.policeRecordScore == -5 && s.commander.days == days + 40)
    }

    @Test("POL-094 mercenaries leave only with two or more non-special crew, and then every slot from 1 is cleared")
    func mercenariesLeave() {
        func crewAfter(_ crew: [Int?]) -> [Int?] {
            var s = makeEngine().state
            s.commander.cash = 100_000
            s.commander.ship.crew = crew
            _ = s.arrested()
            return s.commander.ship.crew
        }
        #expect(crewAfter([0, 1, 2]) == [0, nil, nil])
        #expect(crewAfter([0, 1, CrewID.wild]) == [0, 1, CrewID.wild])
        #expect(crewAfter([0, 1, nil]) == [0, 1, nil])
        #expect(crewAfter([0, 1, 2, CrewID.wild]) == [0, nil, nil, nil])
    }

    @Test("POL-096 fine from cash, or the ship is sold (worth after confiscation) and replaced by a Flea; Modern resets the basis")
    func shipSold() {
        var paid = makeEngine().state
        paid.commander.cash = 9_000
        paid.commander.policeRecordScore = -10
        let fine = paid.arrestFine
        _ = paid.arrested()
        #expect(paid.commander.cash == 9_000 - fine && paid.commander.ship.type == .gnat)
        for ruleset in [RulesetID.windows201, .modern] {
            var s = makeEngine(ruleset).state
            s.commander.ship.gadgets = [.hiddenCargoBays]
            s.commander.ship.escapePod = true
            s.commander.ship.crew = [0, 1, 2]
            s.commander.ship.cargo[narcotics] = 2
            s.commander.priceCargo[narcotics] = 900
            s.commander.ship.cargo[0] = 1
            s.commander.priceCargo[0] = 50
            s.commander.cash = 100
            s.commander.policeRecordScore = -10
            var sale = s
            sale.commander.ship.gadgets = []
            sale.commander.priceCargo[narcotics] = 0
            let expectedCash = max(0, 100 + sale.shipWorth(forInsurance: true) - 1_500)
            let events = s.arrested()
            #expect(events.first == .arrested(term: 30, fine: 1_500, shipSold: true))
            let flea = s.commander.ship
            #expect(s.commander.cash == expectedCash)
            #expect(flea.type == .flea && flea.hull == 25 && flea.fuel == 20 && !flea.escapePod && flea.crew == [0])
            #expect(!s.commander.insurance && s.commander.noClaim == 0)
            #expect(s.commander.priceCargo[0] == (ruleset == .windows201 ? 50 : 0))
        }
    }

    @Test("POL-097 IncDays(term) runs after rec = −5: no drift, days and quest timers advance, no-claim stays 0")
    func jailDays() {
        var s = makeEngine().state
        s.commander.cash = 100_000
        s.commander.policeRecordScore = -50
        s.commander.insurance = true
        s.commander.noClaim = 30
        s.specialShips.spaceMonster.hull = 100
        s.quests.gemulon = QuestStatus.Gemulon.started
        let days = s.commander.days
        _ = s.arrested()
        #expect(s.commander.policeRecordScore == -5 && s.commander.days == days + 50)
        #expect(s.commander.noClaim == 0 && s.specialShips.spaceMonster.hull > 100)
        #expect(s.quests.gemulon == QuestStatus.Gemulon.tooLate)
    }

    @Test("POL-101 the arrest is one engine step returning the arrest event and the arrival report")
    func arrestOneStep() {
        var e = Pol.engine(.policeSurrender) { $0.commander.cash = 50_000 }
        let r = e.perform(.encounter(.surrender), acknowledging: [.surrenderToPolice])
        #expect(r.decision == nil && r.rejection == nil)
        #expect(r.events.first.map(isArrest) == true)
        #expect(r.events.last == .arrived(system: e.state.warpSystem))
    }

    @Test("POL-109 after the jail days the normal arrival runs and joins the same report")
    func arrivalAfterJail() {
        var e = Pol.engine(.policeAttack) { s in
            s.commander.policeRecordScore = -40
            s.commander.cash = 2_000
            s.commander.debt = 80_000
        }
        let r = e.perform(.encounter(.surrender), acknowledging: Pol.yes)
        let arrest = r.events.firstIndex(where: isArrest)
        let warning = r.events.firstIndex { if case .debtWarning = $0 { true } else { false } }
        let arrived = r.events.firstIndex(of: .arrived(system: e.state.warpSystem))
        #expect(arrest != nil && warning != nil && arrived != nil)
        if let arrest, let warning, let arrived { #expect(arrest < warning && warning < arrived) }
        #expect(e.state.commander.debt >= 75_000)
    }

    @Test("POL-111 after an arrest or the pod the current system is the trip's destination")
    func destinationAfterArrest() {
        func run(_ type: EncounterType, _ action: EncounterAction, pod: Bool) -> (Int, Int, Int) {
            var e = Pol.engine(type, clicks: 8) { s in
                let from = s.commander.currentSystem
                s.warpSystem = (from + 1) % s.galaxy.systems.count
                s.encounterTransit?.destination = s.warpSystem
                s.commander.cash = 50_000
                if pod { s.commander.ship.escapePod = true; s.commander.ship.hull = 0 }
            }
            let from = e.state.commander.currentSystem
            _ = e.perform(.encounter(action), acknowledging: Pol.yes)
            return (from, e.state.commander.currentSystem, e.state.warpSystem)
        }
        for (type, action, pod) in [(EncounterType.policeAttack, EncounterAction.surrender, false), (.pirateAttack, .attack, true)] {
            let (from, now, dest) = run(type, action, pod: pod)
            #expect(now == dest && now != from)
        }
    }
}

@Suite("POL §9: escape pod")
struct PoliceEscapePodSpecTests {
    @Test("POL-103 the pod fires when the hull reaches 0 in combat with a pod aboard")
    func podFires() {
        var e = Pol.engine(.pirateAttack) { s in s.commander.ship.hull = 0; s.commander.ship.escapePod = true }
        var enc = Pol.encounter(e)
        #expect(e.state.executeRound(&enc).0 == .escapePod)
        e = Pol.engine(.pirateAttack) { $0.commander.ship.hull = 0 }
        enc = Pol.encounter(e)
        #expect(e.state.executeRound(&enc).0 == .killed)
        e = Pol.engine(.pirateAttack) { s in s.commander.ship.hull = 0; s.commander.ship.escapePod = true }
        let r = e.perform(.encounter(.attack))
        #expect(r.events.contains(.escapePodUsed(insurancePayout: 0)))
        #expect(e.state.phase == .docked && e.state.commander.ship.type == .flea)
    }

    @Test("POL-104 pod sequence: reactor done, antidote/artifact/Jarek/Princess/Wild, insurance payout, 500 charge, IncDays(3), Flea")
    func podSequence() {
        var s = makeEngine().state
        s.commander.ship.hull = 0
        s.commander.ship.escapePod = true
        s.commander.ship.tribbles = 40
        s.commander.ship.crew = [0, 1, CrewID.wild]
        s.quests.reactor = 7
        s.quests.japori = QuestStatus.Japori.inTransit
        s.quests.artifact = QuestStatus.Artifact.onBoard
        s.commander.insurance = true
        s.commander.cash = 300
        s.commander.policeRecordScore = -20
        let payout = s.baseWorth(of: s.commander.ship, forInsurance: true)
        let days = s.commander.days
        let events = s.escapeWithPod()
        #expect(events.first == .escapePodUsed(insurancePayout: payout))
        #expect(s.quests.reactor == QuestStatus.Reactor.done && s.quests.japori == QuestStatus.Japori.notStarted)
        #expect(s.quests.artifact == QuestStatus.Artifact.done && s.newsEvents.last == .wildArrested)
        #expect(s.commander.policeRecordScore == -24 + 3) // −4 for Wild, then IncDays(3) drift on Normal
        #expect(s.commander.cash == 300 + payout - 500 && s.commander.days == days + 3)
        let flea = s.commander.ship
        #expect(flea.type == .flea && flea.crew == [0] && !flea.escapePod && flea.tribbles == 0)
        #expect(!s.commander.insurance && s.commander.noClaim == 0)
        for (cash, expectedDebt) in [(500, 0), (200, 300)] {
            var t = makeEngine().state
            t.commander.cash = cash
            _ = t.escapeWithPod()
            #expect(t.commander.cash == 0 && t.commander.debt == expectedDebt)
        }
    }

    @Test("POL-106 the Scarab quest status survives the pod")
    func scarabSurvives() {
        var s = makeEngine().state
        s.quests.scarab = QuestStatus.Scarab.done
        s.commander.ship.hullUpgraded = true
        _ = s.escapeWithPod()
        #expect(s.quests.scarab == QuestStatus.Scarab.done && !s.commander.ship.hullUpgraded)
    }
}

@Suite("POL §11: engine API")
struct PoliceAPISpecTests {
    @Test("POL-113 police commands only in their encounter types; confirmations never change state; first missing ack first")
    func commandGating() {
        var docked = makeEngine()
        #expect(docked.perform(.encounter(.submit)).rejection == .notAllowedInPhase)
        for (type, action) in [(EncounterType.policeAttack, EncounterAction.submit), (.policeIgnore, .bribe), (.policeInspect, .yield),
                               (.pirateAttack, .submit), (.policeInspect, .surrender)] {
            var e = Pol.engine(type)
            #expect(e.perform(.encounter(action), acknowledging: Pol.yes).rejection == .encounterActionUnavailable, "\(type) \(action)")
        }
        var e = Pol.engine(.policeInspect)
        let before = e.state
        #expect(e.perform(.encounter(.bribe)).decision == .confirm(Confirmation(.submitWithNothingIllegal)))
        #expect(e.perform(.encounter(.bribe), acknowledging: [.bribe]).decision == .confirm(Confirmation(.submitWithNothingIllegal)))
        #expect(e.perform(.encounter(.bribe), acknowledging: [.submitWithNothingIllegal]).decision?.isBribe == true)
        #expect(e.state == before)
    }

    @Test("POL-114 WarningID cases used by POL")
    func warnings() {
        func ask(_ type: EncounterType, _ action: EncounterAction, opponent: ShipType = .gnat,
                 _ adjust: @escaping (inout GameState) -> Void = { _ in }) -> WarningID? {
            var e = Pol.engine(type, opponent: opponent) { adjust(&$0) }
            if case let .confirm(c) = e.perform(.encounter(action)).decision { return c.warning }
            return nil
        }
        let illegal: (inout GameState) -> Void = { $0.commander.ship.cargo[firearms] = 1 }
        #expect(ask(.policeIgnore, .attack) == .attackPolice)
        #expect(ask(.traderIgnore, .attack) == .attackTrader)
        #expect(ask(.captainAhab, .attack) == .attackCaptain)
        #expect(ask(.policeInspect, .flee) == .fleeInspection)
        #expect(ask(.marieCelestePolice, .flee) == .fleeMariePolice)
        #expect(ask(.policeInspect, .attack) == .submitWithNothingIllegal)
        #expect(ask(.policeAttack, .surrender) == .surrenderToPolice)
        #expect(ask(.policeInspect, .bribe, illegal) == .bribe)
        #expect(ask(.policeInspect, .submit, illegal) == .submitInspection)
        #expect(ask(.pirateAttack, .surrender, opponent: .mantis) { $0.quests.artifact = QuestStatus.Artifact.onBoard } == .surrenderArtifact)
    }

    @Test("POL-115 CommandError cases used by POL")
    func errors() {
        func reject(_ type: EncounterType, _ action: EncounterAction, opponent: ShipType = .gnat,
                    _ adjust: @escaping (inout GameState) -> Void = { _ in }) -> CommandError? {
            var e = Pol.engine(type, opponent: opponent) { adjust(&$0) }
            return e.perform(.encounter(action), acknowledging: Pol.yes).rejection
        }
        #expect(reject(.policeInspect, .bribe) { s in s.galaxy.systems[s.warpSystem].politics = .military } == .bribeNotPossible)
        #expect(reject(.marieCelestePolice, .bribe) == .bribeNotAccepted)
        #expect(reject(.policeInspect, .bribe) { $0.commander.cash = 0 } == .insufficientFunds)
        #expect(reject(.policeAttack, .surrender) { $0.commander.policeRecordScore = -150 } == .surrenderRefused)
        #expect(reject(.pirateAttack, .surrender, opponent: .mantis) == .surrenderRefused)
        #expect(reject(.pirateAttack, .surrender) { $0.commander.ship.crew.append(CrewID.princess) } == .surrenderPrincess)
    }

    @Test("POL-116 GameEvent cases emitted by police actions; the engine emits no strings")
    func events() {
        func first(_ type: EncounterType, _ action: EncounterAction, _ adjust: @escaping (inout GameState) -> Void = { _ in }) -> GameEvent? {
            var e = Pol.engine(type) { adjust(&$0) }
            return e.perform(.encounter(action), acknowledging: Pol.yes).events.first
        }
        #expect(first(.policeInspect, .submit) { $0.commander.ship.cargo[narcotics] = 1 } == .fined(400))
        #expect(first(.policeInspect, .submit) == .inspectionClean)
        #expect(first(.policeInspect, .bribe) == .bribed(800))
        #expect(first(.marieCelestePolice, .yield) == .yielded)
        #expect(first(.pirateAttack, .surrender) { $0.commander.ship.cargo[0] = 1 } == .looted(units: 1))
        #expect(first(.pirateAttack, .surrender) == .blackmailed(750))
        #expect(first(.pirateAttack, .surrender) { $0.commander.ship.gadgets = [.hiddenCargoBays]; $0.commander.ship.cargo[0] = 6 } == .preciousHidden)
        #expect(first(.pirateAttack, .surrender) { $0.quests.sculpture = QuestStatus.Sculpture.inTransit } == .sculptureTaken)
        #expect(first(.policeAttack, .surrender) == .arrested(term: 30, fine: 500, shipSold: false))
        var pod = Pol.engine(.pirateAttack) { $0.commander.ship.hull = 0; $0.commander.ship.escapePod = true }
        #expect(pod.perform(.encounter(.attack)).events.contains(.escapePodUsed(insurancePayout: 0)))
    }

    @Test("POL-117 policeStatus is pure and reports record, reputation, kills and the inspection costs")
    func policeStatus() {
        var e = Pol.engine(.policeInspect) { s in
            s.commander.policeRecordScore = -12
            s.commander.reputationScore = 160
            s.commander.kills.pirates = 3
            s.commander.ship.cargo[narcotics] = 2
        }
        let before = e.state
        let st = e.policeStatus
        #expect(e.state == before)
        #expect(st.record == -12 && st.recordType == .criminal && st.reputation == 160 && st.reputationType == .competent)
        #expect(st.kills.pirates == 3)
        let insp = st.inspection
        #expect(insp?.bribe == e.state.bribeAmount && insp?.bribeRejection == nil)
        #expect(insp?.submitFine == e.state.inspectionFine && insp?.submitLeadsToArrest == false)
        #expect(insp?.arrestTerm == 30 && insp?.arrestFine == e.state.arrestFine)
        // The preview agrees with what the commands then do.
        var copy = e
        #expect(copy.perform(.encounter(.submit), acknowledging: Pol.yes).events.first == .fined(insp?.submitFine ?? -1))
        copy = e
        #expect(copy.perform(.encounter(.bribe), acknowledging: Pol.yes).events.first == .bribed(insp?.bribe ?? -1))
        e = Pol.engine(.marieCelestePolice) { $0.quests.reactor = 2 }
        #expect(e.policeStatus.inspection?.bribeRejection == .bribeNotAccepted)
        #expect(e.policeStatus.inspection?.submitLeadsToArrest == true && e.policeStatus.inspection?.submitFine == nil)
        #expect(makeEngine().policeStatus.inspection == nil)
    }
}

private extension PendingDecision {
    var isBribe: Bool { if case let .confirm(c) = self { c.warning == .bribe } else { false } }
}
