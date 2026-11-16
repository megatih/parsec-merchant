// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Testing
@testable import ParsecEngine

/// An engine in an encounter of `type` against a fresh `opponent`; with `transit`, finishing resumes a one-click trip.
private func encounterEngine(_ type: EncounterType, opponent: ShipType = .gnat, difficulty: Difficulty = .normal,
                             transit: Bool = true, _ adjust: (inout GameState, inout Ship) -> Void = { _, _ in }) -> GameEngine {
    makeEngine(difficulty: difficulty) { s in
        var opp = Ship(type: opponent, spec: s.ruleset.tables.ship(opponent))
        opp.crew[0] = CrewID.opponent
        adjust(&s, &opp)
        s.lastOpponent = opp
        if transit {
            s.encounterTransit = TransitState(destination: s.warpSystem, clicksRemaining: 1, viaWormhole: false, hadEncounter: true)
        }
        s.phase = .encounter(EncounterState(type: type, opponent: opp, clicks: 1))
    }
}

/// Gives the commander a Beetle (three quarters) crewed by the commander plus `crew`.
private func beetle(_ s: inout GameState, crew: [Int] = []) {
    s.commander.ship = Ship(type: .beetle, spec: s.ruleset.tables.ship(.beetle))
    s.commander.ship.crew[0] = CrewID.commander
    for (i, id) in crew.enumerated() { s.commander.ship.crew[i + 1] = id }
}

/// `PayInterest` applied `n` times to (cash, debt), as BNK-020/BNK-022 specify.
private func interest(cash: Int, debt: Int, times n: Int) -> (cash: Int, debt: Int) {
    var c = cash, d = debt
    for _ in 0..<n where d > 0 {
        let i = max(1, d / 10)
        if c > i { c -= i } else { d += i - c; c = 0 }
    }
    return (c, d)
}

@Suite("Bank, crew and travel costs (BNK/CRW/GAL/RNG {M3})")
struct BankCrewTravelM3Tests {
    // MARK: Departure costs and interest

    @Test("BNK-024 BNK-059 departure deducts mercenaries + insurance + tax, then fuel, then interest, then the day")
    func departureOrder() throws {
        var e = makeEngine { s in
            beetle(&s, crew: [1])
            s.commander.insurance = true
            s.commander.noClaim = 4
            s.commander.debt = 1_000
        }
        let dest = try #require(e.state.destinations.first)
        e.state.warpSystem = dest
        let costs = e.state.mercenaryCosts + e.state.insuranceCosts + e.state.wormholeCosts
        let distance = GalaxyGenerator.distance(e.state.galaxy.systems[dest], e.state.currentSystem, rule: e.ruleset.flags.distance)
        // 50 cr left after the costs: interest (100) is then short by 50, which goes to debt. Paying interest first
        // would leave the costs unpaid instead.
        e.state.commander.cash = costs + 50
        let (days, fuel) = (e.state.commander.days, e.state.commander.ship.fuel)
        #expect(e.perform(.warp).rejection == nil)
        #expect(e.state.commander.cash == 0 && e.state.commander.debt == 1_050)
        #expect(e.state.commander.ship.fuel == fuel - distance)
        #expect(e.state.commander.days == days + 1 && e.state.commander.noClaim == 5)
        // A singularity jump charges nothing: no costs, no interest, no day.
        var j = makeEngine { s in
            beetle(&s, crew: [1])
            s.commander.insurance = true
            s.commander.debt = 1_000
            s.commander.cash = 5_000
            s.quests.canSuperWarp = true
        }
        j.state.warpSystem = (j.state.commander.currentSystem + 64) % j.state.galaxy.systems.count
        let jFuel = j.state.commander.ship.fuel
        #expect(j.perform(.jump, acknowledging: [.useSingularity]).rejection == nil)
        #expect(j.state.commander.cash == 5_000 && j.state.commander.debt == 1_000)
        #expect(j.state.commander.days == 0 && j.state.commander.ship.fuel == jFuel && !j.state.quests.canSuperWarp)
    }

    @Test("BNK-028 BNK-057 BNK-062 warp affordability: debt > 100000, mercenaries, insurance, wormhole tax, then Wild")
    func affordability() throws {
        var e = makeEngine { s in beetle(&s, crew: [1]); s.commander.insurance = true }
        let from = e.state.galaxy.wormholes[0]
        e.state.commander.currentSystem = from
        e.state.warpSystem = try #require(e.state.galaxy.wormholeDestination(from: from))
        let merc = e.state.mercenaryCosts, ins = e.state.insuranceCosts, tax = e.state.wormholeCosts
        #expect(merc > 0 && ins > 0 && tax > 0)
        func check(_ expected: CommandError?) {
            let before = e.state
            #expect(e.state.warpBlocker() == expected)                       // BNK-062: the preview query
            #expect(e.state == before)
            let r = e.perform(.warp)
            if let expected {
                #expect(r.rejection == expected && e.state == before)        // BNK-062: perform returns the same error
            }
        }
        e.state.commander.debt = 100_001
        e.state.commander.cash = 0
        check(.debtTooLargeToTravel)                                         // BNK-028: strictly greater
        e.state.commander.debt = 100_000
        check(.cannotPayMercenaries)                                         // 100000 is allowed past check 1
        e.state.commander.cash = merc
        check(.cannotPayInsurance)
        e.state.commander.cash = merc + ins
        check(.cannotPayWormholeTax)
        // Interest (10000 here) is not part of the affordability checks.
        e.state.commander.cash = merc + ins + tax
        #expect(e.state.warpBlocker() == nil)
        // The Wild consent comes after the cost checks.
        var w = makeEngine { s in beetle(&s, crew: [CrewID.wild]); s.quests.wild = QuestStatus.Wild.started; s.commander.cash = 0 }
        w.state.warpSystem = try #require(w.state.destinations.first)
        w.state.commander.debt = 100_001
        #expect(w.perform(.warp).rejection == .debtTooLargeToTravel)
        w.state.commander.debt = 0
        #expect(w.perform(.warp).decision == .confirm(Confirmation(.wildLeavesWithoutLaser)))
    }

    @Test("GAL-032 wormhole tax = 25 × the ship's fuel cost, only through a wormhole")
    func wormholeTax() throws {
        var s = makeEngine().state
        let from = s.galaxy.wormholes[0]
        s.commander.currentSystem = from
        s.warpSystem = try #require(s.galaxy.wormholeDestination(from: from))
        #expect(s.wormholeCosts == 25 * s.commander.ship.spec(s.ruleset).fuelCost)
        #expect(s.wormholeCosts > 0)
        s.warpSystem = try #require(s.galaxy.systems.indices.first { $0 != from && !s.galaxy.wormholeExists(from: from, to: $0) })
        #expect(s.wormholeCosts == 0)
    }

    // MARK: Jail, fines, escape pod

    @Test("BNK-025 BNK-046 jail: fine, debt paydown from cash, interest × term, insurance cancelled, then the days")
    func jailMoney() {
        var s = makeEngine { s in
            s.commander.policeRecordScore = -30
            s.commander.cash = 30_000
            s.commander.debt = 28_000
            s.commander.insurance = true
            s.commander.noClaim = 9
            s.commander.ship.escapePod = true
        }.state
        let days = s.commander.days
        let fine = (1 + s.worth * 30 / 50_000) * 500
        let events = s.arrested()
        #expect(events.first == .arrested(term: 30, fine: fine, shipSold: false))
        let afterFine = 30_000 - fine
        let paydown = min(afterFine, 28_000)
        let expected = interest(cash: afterFine - paydown, debt: 28_000 - paydown, times: 30)
        #expect(28_000 - paydown > 0)
        #expect(s.commander.cash == expected.cash && s.commander.debt == expected.debt)
        #expect(s.commander.days == days + 30 && s.commander.policeRecordScore == -5)
        #expect(!s.commander.insurance && s.commander.noClaim == 0)                                // BNK-046
    }

    @Test("BNK-027 unpaid inspection fine and pirate blackmail: cash first, remainder to debt")
    func shortfallToDebt() {
        var police = encounterEngine(.policeInspect) { s, _ in s.commander.ship.cargo[TradeItemType.narcotics.rawValue] = 1; s.commander.cash = 40 }
        let fine = police.state.inspectionFine
        _ = police.perform(.encounter(.submit), acknowledging: [.submitInspection])
        #expect(police.state.commander.cash == 0 && police.state.commander.debt == fine - 40)
        var pirates = encounterEngine(.pirateAttack) { s, _ in s.commander.cash = 100 }
        let blackmail = min(25_000, max(500, pirates.state.worth / 20))
        _ = pirates.perform(.encounter(.surrender))
        #expect(pirates.state.commander.cash == 0 && pirates.state.commander.debt == blackmail - 100)
    }

    @Test("BNK-047 escape pod: insurance payout, then the 500 cr Flea charge (shortfall to debt), 3 days, insurance ends")
    func escapePodMoney() {
        var s = makeEngine { s in s.commander.insurance = true; s.commander.cash = 100; s.commander.noClaim = 6 }.state
        s.commander.ship.hull = 0
        let payout = s.baseWorth(of: s.commander.ship, forInsurance: true)
        let days = s.commander.days
        #expect(s.escapeWithPod().contains(.escapePodUsed(insurancePayout: payout)))
        #expect(s.commander.cash == 100 + payout - 500 && s.commander.debt == 0)
        #expect(s.commander.days == days + 3 && s.commander.ship.type == .flea)
        #expect(!s.commander.insurance && s.commander.noClaim == 0)
        var poor = makeEngine { s in s.commander.cash = 200 }.state
        #expect(poor.escapeWithPod().contains(.escapePodUsed(insurancePayout: 0)))
        #expect(poor.commander.cash == 0 && poor.commander.debt == 300)
        var exact = makeEngine { s in s.commander.cash = 500 }.state
        _ = exact.escapeWithPod()
        #expect(exact.commander.cash == 0 && exact.commander.debt == 0)    // `cash > 500` is false: 500 - 500 goes to debt (0)
    }

    // MARK: Debt warnings

    @Test("BNK-033 BNK-034 RemindLoans defaults on; warning at debt ≥ 75000, otherwise the 5-day reminder (Windows)")
    func debtWarnings() {
        #expect(GameOptions().remindLoans && makeEngine().state.options.remindLoans)
        func debtEvents(debt: Int, days: Int, remind: Bool = true) -> [GameEvent] {
            var s = makeEngine { s in s.commander.debt = debt; s.commander.days = days; s.options.remindLoans = remind }.state
            return s.arrival().filter {
                switch $0 {
                case .debtWarning, .debtReminder: true
                default: false
                }
            }
        }
        #expect(debtEvents(debt: 74_999, days: 3).isEmpty)
        #expect(debtEvents(debt: 74_999, days: 5) == [.debtReminder(debt: 74_999)])
        #expect(debtEvents(debt: 75_000, days: 5) == [.debtWarning(debt: 75_000)])     // never both
        #expect(debtEvents(debt: 75_000, days: 3) == [.debtWarning(debt: 75_000)])
        #expect(debtEvents(debt: 1, days: 0) == [.debtReminder(debt: 1)])
        #expect(debtEvents(debt: 1, days: 0, remind: false).isEmpty)
        #expect(debtEvents(debt: 0, days: 0).isEmpty)
    }

    @Test("BNK-035 the debt check runs in the arrival after arrest and after the escape pod, using the later day")
    func debtCheckAfterJailAndPod() throws {
        var jail = encounterEngine(.policeAttack) { s, _ in
            s.commander.policeRecordScore = -30
            s.commander.cash = 30_000
            s.commander.debt = 28_000
        }
        let r = jail.perform(.encounter(.surrender), acknowledging: [.surrenderToPolice])
        let arrested = try #require(r.events.firstIndex { if case .arrested = $0 { return true }; return false })
        let reminder = try #require(r.events.firstIndex(of: .debtReminder(debt: jail.state.commander.debt)))
        #expect(jail.state.commander.days == 30 && jail.state.commander.debt > 0 && jail.state.commander.debt < 75_000)
        #expect(arrested < reminder)
        var pod = encounterEngine(.pirateAttack) { s, _ in s.commander.days = 2; s.commander.debt = 1_000; s.commander.cash = 5_000 }
        let events = pod.finishEncounter(.escapePod)
        #expect(pod.state.commander.days == 5 && events.contains(.debtReminder(debt: 1_000)))
    }

    // MARK: Crew

    @Test("CRW-046 Wild 'leaves' (warp without a Beam laser, or joins raiding pirates) but stays in the crew array")
    func wildLeavesButStays() throws {
        var e = makeEngine { s in beetle(&s, crew: [CrewID.wild]); s.quests.wild = QuestStatus.Wild.started; s.commander.cash = 10_000 }
        e.state.warpSystem = try #require(e.state.destinations.first)
        let r = e.perform(.warp, acknowledging: [.wildLeavesWithoutLaser])
        #expect(r.events.first == .wildLeftShip && e.state.commander.ship.hasCrew(CrewID.wild))
        // The status was reset before the departure day; because Wild is still aboard, IncDays(1) then counts it up again.
        #expect(e.state.quests.wild == QuestStatus.Wild.notStarted + 1)
        var p = encounterEngine(.pirateAttack, opponent: .beetle) { s, _ in beetle(&s, crew: [CrewID.wild]); s.quests.wild = QuestStatus.Wild.started }
        #expect(p.perform(.encounter(.surrender)).events.contains(.wildJoinedPirates))
        #expect(p.state.quests.wild == QuestStatus.Wild.notStarted && p.state.commander.ship.hasCrew(CrewID.wild))
    }

    @Test("CRW-047 CRW-050 arrest clears the crew only with two or more mercenaries; they keep their system id")
    func arrestCrew() throws {
        var one = makeEngine { s in beetle(&s, crew: [1]); s.commander.cash = 50_000; s.commander.policeRecordScore = -30 }.state
        _ = one.arrested()
        #expect(one.commander.ship.crew[1] == 1)
        var two = makeEngine { s in beetle(&s, crew: [1, 2]); s.commander.cash = 50_000; s.commander.policeRecordScore = -30 }.state
        let home = try #require(two.mercenaries[1].systemID)
        _ = two.arrested()
        #expect(two.commander.ship.crew.dropFirst().allSatisfy { $0 == nil })
        #expect(two.mercenaries[1].systemID == home)
        two.commander.currentSystem = home
        #expect(two.mercenariesForHire.contains(1))
    }

    @Test("CRW-049 CRW-050 the escape pod's Flea has one quarter: every mercenary is lost, keeping its system id")
    func podCrew() throws {
        var s = makeEngine { s in beetle(&s, crew: [1, 2]); s.commander.cash = 5_000 }.state
        let home = try #require(s.mercenaries[2].systemID)
        _ = s.escapeWithPod()
        #expect(s.commander.ship.type == .flea && s.commander.ship.crew == [CrewID.commander])
        #expect(s.mercenaries[2].systemID == home)
    }

    @Test("CRW-056 CRW-057 tonics: good raises 2 skills (1 above Normal); strange shuffles below Hard, +1 +1 −3 on Hard")
    func tonics() {
        func drink(_ type: EncounterType, _ difficulty: Difficulty, skills: [Int]) -> (before: [Int], after: [Int]) {
            var e = encounterEngine(type, difficulty: difficulty, transit: false) { s, _ in s.mercenaries[CrewID.commander].skills = skills }
            _ = e.perform(.encounter(.drink), acknowledging: [.drinkTonic])
            return (skills, e.state.mercenaries[CrewID.commander].skills)
        }
        for d in [Difficulty.beginner, .easy, .normal] {
            let g = drink(.bottleGood, d, skills: [3, 3, 3, 3])
            #expect(g.after.reduce(0, +) == 14)
            let s = drink(.bottleOld, d, skills: [3, 3, 3, 3])
            #expect(s.after != s.before && s.after.reduce(0, +) == 12)
        }
        for d in [Difficulty.hard, .impossible] {
            #expect(drink(.bottleGood, d, skills: [3, 3, 3, 3]).after.reduce(0, +) == 13)
            #expect(drink(.bottleOld, d, skills: [5, 5, 5, 5]).after.reduce(0, +) == 19)
        }
    }

    @Test("CRW-059 CRW-060 famous captains take their item and train a skill (+2 / +1 above Normal, max 10); no price recalc")
    func captainTraining() {
        let cases: [(EncounterType, SkillType)] = [(.captainAhab, .pilot), (.captainConrad, .engineer), (.captainHuie, .trader)]
        for (type, skill) in cases {
            for (difficulty, start, gain) in [(Difficulty.normal, 4, 2), (.hard, 4, 1), (.easy, 9, 1)] {
                var e = encounterEngine(type, opponent: .wasp, difficulty: difficulty, transit: false) { s, _ in
                    s.commander.ship.weapons = [.militaryLaser, .pulseLaser]
                    s.commander.ship.shields = [ShieldInstance(type: .reflective, charge: 0)]
                    s.mercenaries[CrewID.commander].skills[skill.rawValue] = start
                    s.buyPrices = Array(1...10)
                }
                _ = e.perform(.encounter(.meet), acknowledging: [.meetCaptain])
                let ship = e.state.commander.ship
                #expect(e.state.mercenaries[CrewID.commander].skills[skill.rawValue] == start + gain)
                if type == .captainAhab {
                    #expect(ship.shields.isEmpty && ship.weapons == [.militaryLaser, .pulseLaser])
                } else {
                    #expect(ship.shields.count == 1 && ship.weapons == [.pulseLaser])
                }
                #expect(e.state.buyPrices == Array(1...10))                  // CRW-060: not recalculated (Huie trains Trader)
            }
        }
    }

    // MARK: Markets and the newspaper RNG

    @Test("GAL-066 arrival: each system in order draws r(100) < 15 to flip its pressure, interleaved with its quantity update")
    func pressureFlips() {
        var s = makeEngine().state
        let r = s.ruleset
        for i in s.galaxy.systems.indices { s.galaxy.systems[i].countDown = 0 }
        let drifting = 5
        s.galaxy.systems[drifting].countDown = 2
        let arrival = s.commander.currentSystem
        #expect(SystemPressure.war.rawValue == 1 && SystemPressure.employment.rawValue + 1 == 8)
        var rng = s.rng
        var pressures = s.galaxy.systems.map(\.pressure)
        var items = s.galaxy.systems[drifting].tradeItems
        for i in s.galaxy.systems.indices {
            if rng.next(below: 100) < 15 {
                pressures[i] = pressures[i] == .none ? SystemPressure(rawValue: rng.next(in: 1, 8)) ?? .none : .none
            }
            if i == drifting {
                for (j, item) in r.tables.tradeItems.enumerated() where Pricing.itemTraded(item, in: s.galaxy.systems[arrival], ruleset: r) {
                    items[j] = max(0, items[j] + rng.next(in: -4, 5))
                }
            }
        }
        let original = s.galaxy.systems.map(\.pressure)
        s.updatePressuresAndQuantities(arrival: arrival)
        #expect(pressures != original)
        #expect(s.galaxy.systems.map(\.pressure) == pressures)
        #expect(s.galaxy.systems[drifting].tradeItems == items && s.galaxy.systems[drifting].countDown == 1)
        #expect(s.rng == rng)
    }

    @Test("RNG-025 the newspaper reseeds PieterRand(system, days) per composition, never touches the game RNG, is not saved")
    func newspaperRNG() throws {
        var e = makeEngine { s in s.commander.policeRecordScore = -80; s.options.newsAutoPay = true; s.commander.cash = 100 }
        let rng = e.state.rng
        guard case let .newspaper(paper) = e.perform(.readNewspaper).decision else { Issue.record("no paper"); return }
        #expect(e.state.rng == rng)
        var other = e.state
        _ = other.rng.next(below: 1_000)
        #expect(other.newspaper == paper && e.state.newspaper == paper)       // reseeded: game draws do not move it
        for days in 0..<12 {
            var s = e.state
            s.commander.days = days
            var p = PieterRand(variant: .csharp)
            p.seed(s.commander.currentSystem, days)
            #expect(s.newspaper.headlines.contains(.villain(index: p.getRandom2(NewsTables.villainCount))))
        }
        let json = try #require(String(data: try JSONEncoder().encode(e.state), encoding: .utf8))
        #expect(!json.contains("seedX") && !json.contains("seedY"))
    }
}
