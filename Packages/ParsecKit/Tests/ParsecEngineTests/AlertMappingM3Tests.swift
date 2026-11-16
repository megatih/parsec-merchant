// SPDX-License-Identifier: GPL-2.0-or-later
import Testing
@testable import ParsecEngine

/// An engine in an encounter of `type` against a fresh `opponent` ship, with a one-click transit to resume afterwards.
private func encounterEngine(_ type: EncounterType, opponent: ShipType = .gnat, difficulty: Difficulty = .normal,
                             _ adjust: (inout GameState, inout Ship) -> Void = { _, _ in }) -> GameEngine {
    makeEngine(difficulty: difficulty) { s in
        var opp = Ship(type: opponent, spec: s.ruleset.tables.ship(opponent))
        opp.crew[0] = CrewID.opponent
        adjust(&s, &opp)
        s.lastOpponent = opp
        s.encounterTransit = TransitState(destination: s.warpSystem, clicksRemaining: 1, viaWormhole: false, hadEncounter: true)
        s.phase = .encounter(EncounterState(type: type, opponent: opp, clicks: 1))
    }
}

/// Runs `body` on copies of `base` whose RNG is advanced by 0, 1, 2… draws and returns the first accepted outcome.
private func scan(_ base: GameEngine, limit: Int = 3_000, _ body: (inout GameEngine) -> StepResult,
                  until accept: (StepResult, GameEngine) -> Bool) -> (StepResult, GameEngine)? {
    var start = base
    for _ in 0..<limit {
        var e = start
        let r = body(&e)
        if accept(r, e) { return (r, e) }
        _ = start.state.rng.next(below: 1_000)
    }
    return nil
}

/// The warning of a confirmation request, if the step is one.
private func warning(_ r: StepResult) -> WarningID? {
    if case let .confirm(c) = r.decision, r.events.isEmpty { return c.warning }
    return nil
}

/// A government whose bribe level is (or is not) zero.
private func government(bribable: Bool) -> PoliticalSystemType {
    PoliticalSystemType.allCases.first { (Ruleset.windows201.tables.politics($0).bribeLevel > 0) == bribable } ?? .anarchy
}

/// Engine side of the {M3} alert mappings (ALR.md): each classic alert's trigger yields the mapped typed value.
@Suite("Alert mappings, engine side (ALR {M3})")
struct AlertMappingM3Tests {
    // MARK: Arrival, newspaper and departure

    @Test("ALR-006 ALR-009 newspaper: buy confirmation with the cost, auto-pay skips it, unaffordable is insufficientFunds")
    func newspaper() {
        var e = makeEngine { s in s.commander.cash = 100 }
        let cost = e.state.newspaperCost
        #expect(cost == e.state.difficulty.rawValue + 1)
        #expect(e.perform(.readNewspaper).decision == .confirm(Confirmation(.buyNewspaper, amounts: [cost])))   // ArrivalBuyNewspaper
        #expect(e.state.commander.cash == 100 && !e.state.paidForNewspaper)
        var auto = e
        auto.state.options.newsAutoPay = true
        guard case .newspaper = auto.perform(.readNewspaper).decision else { Issue.record("auto-pay did not show the paper"); return }
        #expect(auto.state.commander.cash == 100 - cost)
        e.state.commander.cash = cost - 1
        #expect(e.perform(.readNewspaper).rejection == .insufficientFunds)                                      // ArrivalIFNewspaper
    }

    @Test("ALR-007 ALR-008 ALR-010 automatic fuel and repairs that cannot complete for lack of cash")
    func arrivalRepairs() {
        var s = makeEngine { s in s.commander.cash = 0; s.options.autoFuel = true; s.options.autoRepair = true }.state
        var fuelOnly = s
        fuelOnly.commander.ship.fuel = 0
        #expect(fuelOnly.arrivalRepairs() == [.autoFuelFailed])                                                // ArrivalIFFuel
        var repairOnly = s
        repairOnly.commander.ship.hull = 1
        #expect(repairOnly.arrivalRepairs() == [.autoRepairFailed])                                            // ArrivalIFRepairs
        s.commander.ship.fuel = 0
        s.commander.ship.hull = 1
        #expect(s.arrivalRepairs() == [.autoFuelFailed, .autoRepairFailed])                                    // ArrivalIFFuelRepairs
        var paid = makeEngine { s in s.commander.cash = 10_000; s.options.autoFuel = true; s.commander.ship.fuel = 0 }.state
        #expect(paid.arrivalRepairs().isEmpty)
    }

    @Test("ALR-029 ALR-033 debt warning (≥ 75000) and the 5-day loan reminder on arrival")
    func debtAlerts() {
        func arrive(debt: Int, days: Int, remind: Bool = true) -> [GameEvent] {
            var s = makeEngine { s in s.commander.debt = debt; s.commander.days = days; s.options.remindLoans = remind }.state
            return s.arrival().filter {
                if case .debtWarning = $0 { return true }
                if case .debtReminder = $0 { return true }
                return false
            }
        }
        #expect(arrive(debt: 75_000, days: 7) == [.debtWarning(debt: 75_000)])                                // DebtWarning
        #expect(arrive(debt: 80_000, days: 10) == [.debtWarning(debt: 80_000)])                                // Windows: warning only
        #expect(arrive(debt: 1_000, days: 10) == [.debtReminder(debt: 1_000)])                                 // DebtReminder
        #expect(arrive(debt: 1_000, days: 11).isEmpty)
        #expect(arrive(debt: 1_000, days: 10, remind: false).isEmpty)
    }

    @Test("ALR-030 ALR-116 ALR-117 ALR-118 departure blocked by debt, mercenaries, insurance and wormhole tax")
    func departureBlocked() throws {
        var e = makeEngine { s in
            s.commander.debt = 100_001
            s.commander.ship = Ship(type: .beetle, spec: s.ruleset.tables.ship(.beetle))
            s.commander.ship.crew[0] = CrewID.commander
        }
        let dest = try #require(e.state.destinations.first)
        e.state.warpSystem = dest
        #expect(e.perform(.warp).rejection == .debtTooLargeToTravel)                                           // DebtTooLargeGrounded
        e.state.commander.debt = 0
        e.state.commander.ship.crew[1] = 1
        let merc = e.state.mercenaryCosts
        #expect(merc > 0)
        e.state.commander.cash = merc - 1
        #expect(e.perform(.warp).rejection == .cannotPayMercenaries)                                           // LeavingIFMercenaries
        e.state.commander.insurance = true
        e.state.commander.cash = merc
        #expect(e.state.insuranceCosts > 0)
        #expect(e.perform(.warp).rejection == .cannotPayInsurance)                                             // LeavingIFInsurance
        let from = e.state.galaxy.wormholes[0]
        e.state.commander.currentSystem = from
        e.state.warpSystem = try #require(e.state.galaxy.wormholeDestination(from: from))
        e.state.commander.cash = merc + e.state.insuranceCosts
        #expect(e.state.wormholeCosts > 0)
        #expect(e.perform(.warp).rejection == .cannotPayWormholeTax)                                           // LeavingIFWormholeTax
        e.state.commander.cash += e.state.wormholeCosts
        #expect(e.perform(.warp).rejection == nil)
    }

    @Test("ALR-168 an encounter-free trip reports an uneventful trip; a trip with an encounter never does")
    func uneventfulTrip() throws {
        let base = makeEngine()
        let dest = try #require(base.state.destinations.first)
        var start = base
        start.state.warpSystem = dest
        let calm = try #require(scan(start, { $0.perform(.warp) }, until: { r, _ in r.events.contains(.uneventfulTrip) }))
        #expect(!calm.0.events.contains { if case .encounterStarted = $0 { return true }; return false })
        #expect(calm.1.state.phase == .docked && calm.0.events.last == .arrived(system: dest))
        let busy = try #require(scan(start, { $0.perform(.warp) }, until: { _, e in
            if case let .encounter(enc) = e.state.phase { return enc.type.actions.contains(.ignore) }
            return false
        }))
        var e = busy.1
        var events = busy.0.events
        while case let .encounter(enc) = e.state.phase, enc.type.actions.contains(.ignore) {
            events += e.perform(.encounter(.ignore)).events
        }
        #expect(!events.contains(.uneventfulTrip))                                                            // TravelUneventfulTrip
    }

    // MARK: Attack verification

    @Test("ALR-037 ALR-039 ALR-040 ALR-041 ALR-042 attack checks: weapons, lasers, police, trader, famous captain")
    func attackChecks() {
        var none = encounterEngine(.pirateAttack) { s, _ in s.commander.ship.weapons = [] }
        #expect(none.perform(.encounter(.attack)).rejection == .noWeapons)                                     // EncounterAttackNoWeapons
        var disruptorOnly = encounterEngine(.pirateAttack, opponent: .mantis) { s, _ in s.commander.ship.weapons = [.photonDisruptor] }
        #expect(disruptorOnly.perform(.encounter(.attack)).rejection == .noLasers)                             // EncounterAttackNoLasers
        var police = encounterEngine(.policeInspect) { s, _ in s.commander.ship.cargo[TradeItemType.narcotics.rawValue] = 1 }
        #expect(warning(police.perform(.encounter(.attack))) == .attackPolice)                                 // EncounterAttackPolice
        var criminal = encounterEngine(.policeInspect) { s, _ in
            s.commander.ship.cargo[TradeItemType.narcotics.rawValue] = 1
            s.commander.policeRecordScore = -30
        }
        #expect(warning(criminal.perform(.encounter(.attack))) == nil)
        var trader = encounterEngine(.traderIgnore)
        #expect(warning(trader.perform(.encounter(.attack))) == .attackTrader)                                 // EncounterAttackTrader
        var dubious = encounterEngine(.traderIgnore) { s, _ in s.commander.policeRecordScore = -1 }
        #expect(warning(dubious.perform(.encounter(.attack))) == nil)
        for captain in [EncounterType.captainAhab, .captainConrad, .captainHuie] {
            var famous = encounterEngine(captain, opponent: .wasp)
            #expect(warning(famous.perform(.encounter(.attack))) == .attackCaptain)                            // EncounterAttackCaptain
        }
    }

    // MARK: Police

    @Test("ALR-060 ALR-061 ALR-062 ALR-053 bribe: offer with amount, impossible, low cash, refused by customs")
    func bribe() throws {
        var e = encounterEngine(.policeInspect) { s, _ in
            s.galaxy.systems[s.warpSystem].politics = government(bribable: true)
            s.commander.ship.cargo[TradeItemType.narcotics.rawValue] = 1
        }
        let amount = try #require(e.state.bribeAmount)
        #expect(e.perform(.encounter(.bribe)).decision == .confirm(Confirmation(.bribe, amounts: [amount])))   // EncounterPoliceBribe
        e.state.commander.cash = amount - 1
        #expect(e.perform(.encounter(.bribe), acknowledging: [.bribe]).rejection == .insufficientFunds)        // EncounterPoliceBribeLowCash
        e.state.commander.cash = amount
        #expect(e.perform(.encounter(.bribe), acknowledging: [.bribe]).events.first == .bribed(amount))
        var honest = encounterEngine(.policeInspect) { s, _ in s.galaxy.systems[s.warpSystem].politics = government(bribable: false) }
        #expect(honest.perform(.encounter(.bribe)).rejection == .bribeNotPossible)                             // EncounterPoliceBribeCant
        var customs = encounterEngine(.marieCelestePolice) { s, _ in s.galaxy.systems[s.warpSystem].politics = government(bribable: true) }
        #expect(customs.perform(.encounter(.bribe)).rejection == .bribeNotAccepted)                            // EncounterMarieCelesteNoBribe
    }

    @Test("ALR-065 ALR-069 nothing-illegal warnings at an inspection, and fleeing the customs police")
    func resistWarnings() {
        var e = encounterEngine(.policeInspect) { s, _ in s.galaxy.systems[s.warpSystem].politics = government(bribable: true) }
        #expect(warning(e.perform(.encounter(.attack))) == .submitWithNothingIllegal)                          // via attack
        #expect(warning(e.perform(.encounter(.bribe))) == .submitWithNothingIllegal)                           // via bribe
        #expect(warning(e.perform(.encounter(.flee))) == .fleeInspection)                                      // via flee
        var smuggler = encounterEngine(.policeInspect) { s, _ in s.commander.ship.cargo[TradeItemType.firearms.rawValue] = 1 }
        #expect(warning(smuggler.perform(.encounter(.flee))) == nil)
        var customs = encounterEngine(.marieCelestePolice)
        #expect(warning(customs.perform(.encounter(.flee))) == .fleeMariePolice)                               // EncounterPostMarieFlee
    }

    @Test("ALR-066 ALR-067 ALR-063 ALR-064 submit / surrender confirmations, fine and clean inspection")
    func submitAndSurrender() {
        let narcotics = TradeItemType.narcotics.rawValue
        var dirty = encounterEngine(.policeInspect) { s, _ in s.commander.ship.cargo[narcotics] = 2 }
        #expect(warning(dirty.perform(.encounter(.submit))) == .submitInspection)                              // EncounterPoliceSubmit
        let fine = dirty.state.inspectionFine
        let fined = dirty.perform(.encounter(.submit), acknowledging: [.submitInspection])
        #expect(fined.events.first == .fined(fine) && dirty.state.commander.ship.cargo[narcotics] == 0)        // EncounterPoliceFine
        var clean = encounterEngine(.policeInspect)
        let record = clean.state.commander.policeRecordScore
        #expect(clean.perform(.encounter(.submit)).events.first == .inspectionClean)                           // EncounterPoliceNothingFound
        #expect(clean.state.commander.policeRecordScore == record + 1)
        var customs = encounterEngine(.marieCelestePolice) { s, _ in s.commander.ship.cargo[narcotics] = 3 }
        #expect(warning(customs.perform(.encounter(.yield))) == .submitInspection)                             // yield (post-Marie)
        var attacked = encounterEngine(.policeAttack)
        #expect(warning(attacked.perform(.encounter(.surrender))) == .surrenderToPolice)                       // EncounterPoliceSurrender
        var wild = encounterEngine(.marieCelestePolice) { s, _ in
            s.commander.ship = Ship(type: .beetle, spec: s.ruleset.tables.ship(.beetle))
            s.commander.ship.crew[0] = CrewID.commander
            s.commander.ship.crew[1] = CrewID.wild
        }
        #expect(warning(wild.perform(.encounter(.yield))) == .surrenderToPolice)                               // yield with illegal special cargo
    }

    @Test("ALR-073 surrender refused by the Mantis without the artifact and by police at score ≤ −100")
    func surrenderRefused() {
        var mantis = encounterEngine(.pirateAttack, opponent: .mantis)
        #expect(mantis.perform(.encounter(.surrender)).rejection == .surrenderRefused)
        var psycho = encounterEngine(.policeAttack) { s, _ in s.commander.policeRecordScore = -100 }
        #expect(psycho.perform(.encounter(.surrender)).rejection == .surrenderRefused)
        psycho.state.commander.policeRecordScore = -99
        #expect(warning(psycho.perform(.encounter(.surrender))) == .surrenderToPolice)
    }

    // MARK: Arrest

    @Test("ALR-036 ALR-108 ALR-110 ALR-111 ALR-112 ALR-113 arrest: first event carries term and fine; jail removals")
    func arrest() throws {
        var e = encounterEngine(.policeAttack) { s, _ in
            s.commander.cash = 200_000
            s.commander.policeRecordScore = -40
            s.commander.ship = Ship(type: .beetle, spec: s.ruleset.tables.ship(.beetle))
            s.commander.ship.crew[0] = CrewID.commander
            s.commander.ship.crew[1] = 1
            s.commander.ship.crew[2] = 2
            s.commander.ship.gadgets = [.hiddenCargoBays]
            s.commander.ship.cargo[TradeItemType.narcotics.rawValue] = 4
            s.commander.ship.escapePod = true
            s.commander.insurance = true
            s.commander.noClaim = 7
        }
        try #require(e.state.commander.ship.crew.count >= 3)
        let days = e.state.commander.days
        let r = e.perform(.encounter(.surrender), acknowledging: [.surrenderToPolice])
        guard case let .arrested(term, fine, shipSold) = r.events.first else { Issue.record("arrest is not the first event"); return }
        #expect(term == 40 && fine > 0 && !shipSold)                                                           // EncounterArrested, JailConvicted
        #expect(e.state.commander.days == days + term && e.state.phase == .docked)
        #expect(!e.state.commander.ship.has(.hiddenCargoBays))                                                 // JailHiddenCargoBaysRemoved
        #expect(e.state.commander.ship.cargo[TradeItemType.narcotics.rawValue] == 0)                           // JailIllegalGoodsImpounded
        #expect(!e.state.commander.insurance && e.state.commander.noClaim == 0)                                // JailInsuranceLost
        #expect(e.state.commander.ship.crew.dropFirst().allSatisfy { $0 == nil })                              // JailMercenariesLeave
    }

    @Test("ALR-114 ALR-093 a fine above cash sells the ship and provides a Flea")
    func arrestShipSold() {
        var e = encounterEngine(.policeAttack) { s, _ in s.commander.cash = 0; s.commander.policeRecordScore = -40 }
        let r = e.perform(.encounter(.surrender), acknowledging: [.surrenderToPolice])
        guard case let .arrested(_, _, shipSold) = r.events.first else { Issue.record("no arrest"); return }
        #expect(shipSold)                                                                                      // JailShipSold
        #expect(e.state.commander.ship.type == .flea)                                                          // FleaBuilt (jail)
    }

    // MARK: Combat outcomes

    @Test("ALR-043 ALR-077 both destroyed / player destroyed end the game")
    func destroyed() throws {
        let base = encounterEngine(.pirateAttack) { s, opp in
            s.commander.ship.hull = 1
            s.commander.ship.weapons = [.militaryLaser, .militaryLaser]
            opp.weapons = [.militaryLaser, .militaryLaser]
            opp.hull = 1
        }
        let both = try #require(scan(base, { $0.perform(.encounter(.attack)) }, until: { r, _ in r.events.contains(.bothDestroyed) }))
        #expect(both.1.state.phase == .gameOver(.killed) && !both.0.events.contains(.playerDestroyed))         // EncounterBothDestroyed
        var tough = base
        tough.state.phase = .encounter(EncounterState(type: .pirateAttack, opponent: {
            var o = Ship(type: .wasp, spec: base.ruleset.tables.ship(.wasp)); o.weapons = [.militaryLaser]; return o
        }(), clicks: 1))
        let lost = try #require(scan(tough, { $0.perform(.encounter(.flee)) }, until: { r, _ in r.events.contains(.playerDestroyed) }))
        #expect(lost.1.state.phase == .gameOver(.killed))                                                      // EncounterYouLose
    }

    @Test("ALR-048 ALR-049 ALR-054 player escapes (hit or not) and opponent escapes")
    func escapes() throws {
        let base = encounterEngine(.pirateAttack) { _, opp in opp.weapons = [.pulseLaser] }
        let missed = try #require(scan(base, { $0.perform(.encounter(.flee)) }, until: { r, _ in r.events.contains(.playerEscaped(wasHit: false)) }))
        #expect(missed.0.events.contains { if case .combatRound(_, false, _, _, _) = $0 { return true }; return false })  // EncounterEscaped
        let hit = try #require(scan(base, { $0.perform(.encounter(.flee)) }, until: { r, _ in r.events.contains(.playerEscaped(wasHit: true)) }))
        #expect(hit.0.events.contains { if case .combatRound(_, true, _, _, _) = $0 { return true }; return false })    // EncounterEscapedHit
        let fleeing = encounterEngine(.pirateFlee)
        let gone = try #require(scan(fleeing, { $0.perform(.encounter(.attack)) }, until: { r, _ in r.events.contains(.opponentEscaped) }))
        #expect(gone.1.state.phase == .docked)                                                                 // EncounterOpponentEscaped
    }

    @Test("ALR-055 ALR-078 ALR-070 ALR-071 ALR-072 destroyed pirate: bounty, canister scoop, no-room handling")
    func wonAndScoop() throws {
        let water = TradeItemType.water
        let base = encounterEngine(.pirateAttack, difficulty: .beginner) { s, opp in
            s.commander.ship.weapons = [.militaryLaser]
            opp.hull = 1
            opp.cargo[water.rawValue] = 3
        }
        let won = try #require(scan(base, { $0.perform(.encounter(.attack)) }, until: { r, _ in r.decision == .scoop(water) }))
        let bounty = base.state.bounty(of: { var o = Ship(type: .gnat, spec: base.ruleset.tables.ship(.gnat)); o.crew[0] = CrewID.opponent; return o }())
        #expect(won.0.events.contains(.opponentDestroyed(.gnat)))                                              // EncounterYouWin
        #expect(won.0.events.contains(.bountyPaid(bounty)))                                                    // EncounterPiratesBounty
        var take = won.1
        #expect(take.perform(.resolveScoop(accept: true)).events.first == .scooped(water))                     // EncounterScoop
        // No room: the same decision while the hold is full; Make Room = jettison while the scoop is pending.
        var full = won.1
        full.state.commander.ship.cargo[TradeItemType.ore.rawValue] = full.state.freeCargoBays
        #expect(full.state.freeCargoBays == 0)
        var noScoop = full
        #expect(noScoop.perform(.resolveScoop(accept: true)).events.first == .scoopNoRoom)                     // EncounterScoopNoScoop
        var makeRoom = full
        #expect(makeRoom.perform(.jettisonCargo(.ore, quantity: 1), acknowledging: [.litteringWarning]).rejection == nil)
        #expect(makeRoom.perform(.resolveScoop(accept: true)).events.first == .scooped(water))                 // EncounterScoopNoRoom
        // A destroyed trader pays no bounty but is still reported.
        let trader = encounterEngine(.traderAttack, difficulty: .beginner) { s, opp in s.commander.ship.weapons = [.militaryLaser]; opp.hull = 1 }
        let killed = try #require(scan(trader, { $0.perform(.encounter(.attack)) }, until: { r, _ in r.events.contains(.opponentDestroyed(.gnat)) }))
        #expect(!killed.0.events.contains { if case .bountyPaid = $0 { return true }; return false })
    }

    @Test("ALR-050 ALR-106 ALR-093 escape pod: event with the insurance payout, then the 500 cr Flea")
    func escapePod() throws {
        let base = encounterEngine(.pirateAttack) { s, opp in
            s.commander.ship.hull = 1
            s.commander.ship.escapePod = true
            s.commander.cash = 1_000
            opp.weapons = [.militaryLaser, .militaryLaser]
        }
        func podded(_ r: StepResult) -> Int? {
            for ev in r.events { if case let .escapePodUsed(p) = ev { return p } }
            return nil
        }
        let plain = try #require(scan(base, { $0.perform(.encounter(.flee)) }, until: { r, _ in podded(r) != nil }))
        #expect(podded(plain.0) == 0)                                                                          // EncounterEscapePodActivated
        #expect(plain.1.state.commander.ship.type == .flea && plain.1.state.commander.cash == 500)            // FleaBuilt (pod)
        var insuredBase = base
        insuredBase.state.commander.insurance = true
        let insured = try #require(scan(insuredBase, { $0.perform(.encounter(.flee)) }, until: { r, _ in podded(r) != nil }))
        let payout = try #require(podded(insured.0))
        #expect(payout > 0)                                                                                    // InsurancePayoff
        #expect(insured.1.state.commander.cash == 1_000 + payout - 500 && !insured.1.state.commander.insurance)
    }

    // MARK: Pirates, very rare encounters, trade

    @Test("ALR-051 ALR-057 surrendering to pirates: looting, or blackmail when nothing can be stolen")
    func pirates() {
        var loot = encounterEngine(.pirateAttack) { s, _ in s.commander.ship.cargo[TradeItemType.water.rawValue] = 5 }
        #expect(loot.perform(.encounter(.surrender)).events.first == .looted(units: 5))                        // EncounterLooting
        var empty = encounterEngine(.pirateAttack)
        let blackmail = min(25_000, max(500, empty.state.worth / 20))
        #expect(empty.perform(.encounter(.surrender)).events.first == .blackmailed(blackmail))                 // EncounterPiratesFindNoCargo
    }

    @Test("ALR-045 ALR-074 ALR-075 bottle: drink confirmation, good and strange tonic")
    func tonic() {
        var good = encounterEngine(.bottleGood)
        #expect(warning(good.perform(.encounter(.drink))) == .drinkTonic)                                      // EncounterDrinkContents
        #expect(good.perform(.encounter(.drink), acknowledging: [.drinkTonic]).events.first == .tonicConsumed(good: true))
        var old = encounterEngine(.bottleOld)
        #expect(old.perform(.encounter(.drink), acknowledging: [.drinkTonic]).events.first == .tonicConsumed(good: false))
    }

    @Test("ALR-119 ALR-120 ALR-121 ALR-166 famous captains: meet confirmation, then training completed")
    func captains() {
        let cases: [(EncounterType, SkillType)] = [(.captainAhab, .pilot), (.captainConrad, .engineer), (.captainHuie, .trader)]
        for (type, skill) in cases {
            var e = encounterEngine(type, opponent: .wasp) { s, _ in
                s.commander.ship.weapons = [.militaryLaser]
                s.commander.ship.shields = [ShieldInstance(type: .reflective, charge: 0)]
            }
            #expect(warning(e.perform(.encounter(.meet))) == .meetCaptain)                                     // MeetCaptain*
            #expect(e.perform(.encounter(.meet), acknowledging: [.meetCaptain]).events.first == .captainTraining(skill: skill))
        }
    }

    @Test("ALR-047 ALR-052 ALR-076 littering warning, boarding the Marie Celeste, in-orbit trade completed")
    func misc() {
        var e = encounterEngine(.pirateIgnore) { s, _ in s.commander.ship.cargo[TradeItemType.ore.rawValue] = 3 }
        #expect(warning(e.perform(.jettisonCargo(.ore, quantity: 1))) == .litteringWarning)                    // EncounterDumpWarning
        #expect(e.perform(.jettisonCargo(.ore, quantity: 1), acknowledging: [.litteringWarning]).rejection == nil)
        #expect(e.state.litterWarning && warning(e.perform(.jettisonCargo(.ore, quantity: 1))) == nil)
        var dubious = encounterEngine(.pirateIgnore) { s, _ in s.commander.ship.cargo[0] = 1; s.commander.policeRecordScore = -5 }
        #expect(warning(dubious.perform(.jettisonCargo(.water, quantity: 1))) == nil)
        var marie = encounterEngine(.marieCeleste) { _, opp in opp.cargo[TradeItemType.narcotics.rawValue] = 5 }
        #expect(warning(marie.perform(.encounter(.board))) == .boardMarieCeleste)                              // EncounterMarieCeleste
        guard case .plunder = marie.perform(.encounter(.board), acknowledging: [.boardMarieCeleste]).decision else {
            Issue.record("no plunder after boarding"); return
        }
        var trade = makeEngine { s in setMarket(&s); s.commander.cash = 1_000; traderEncounter(&s, cargo: [.food: 30]) }
        guard case let .tradeInOrbit(offer) = trade.perform(.encounter(.trade)).decision else { Issue.record("no offer"); return }
        #expect(trade.perform(.resolveTradeInOrbit(quantity: 1)).events
                == [.orbitTradeCompleted(direction: .traderSells, item: .food, quantity: 1, total: offer.unitPrice)])  // EncounterTradeCompleted
    }
}
