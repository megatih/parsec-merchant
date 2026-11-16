// SPDX-License-Identifier: GPL-2.0-or-later
// QST {M5} and the quest RUL rows (docs/specs/QST-*.md, docs/specs/RUL.md): Palm and Modern quest rules per ruleset.
// Palm setups are explicit (scenario states), so they hold whatever Palm content table is installed.
import Testing
@testable import ParsecEngine

/// A docked game of `ruleset` with record 0, reputation 40, plenty of cash, no debt and `event` at the current system.
func questEngine(_ ruleset: RulesetID, _ event: SpecialEventType? = nil, difficulty: Difficulty = .normal,
                 _ adjust: (inout GameState) -> Void = { _ in }) -> GameEngine {
    makeEngine(ruleset, difficulty: difficulty) { s in
        s.commander.policeRecordScore = 0
        s.commander.reputationScore = 40
        s.commander.cash = 200_000
        s.commander.debt = 0
        s.galaxy.systems[s.commander.currentSystem].specialEvent = event
        adjust(&s)
    }
}

let allRulesets: [RulesetID] = [.windows201, .modern, .palm122]

/// A record that satisfies the C# visibility predicate of each capped quest start.
private func recordFor(_ event: SpecialEventType) -> Int {
    [.wild, .reactor].contains(event) ? -10 : 0
}

/// Four open quests that do not interfere with any start predicate: monster, moon, Morgan's laser waiting, tribbles.
private func fourOpen(_ s: inout GameState, tribbles: Int = 5) {
    s.quests.spaceMonster = QuestStatus.SpaceMonster.atAcamar
    s.quests.moon = QuestStatus.Moon.bought
    if let other = s.galaxy.systems.indices.first(where: {
        $0 != s.commander.currentSystem && s.galaxy.systems[$0].specialEvent == nil
    }) {
        s.galaxy.systems[other].specialEvent = .reactorLaser
    }
    s.commander.ship.tribbles = tribbles
}

@Suite("Quest rulesets: Palm open-quest cap and availability (RUL-141, QST-004)")
struct QuestRulesetCapSpecTests {
    @Test("RUL-141 openQuests counts Palm OpenQuests conditions one by one from a fresh game")
    func openQuestCount() {
        let base = questEngine(.palm122).state
        #expect(base.openQuests == 0)
        let adjustments: [(inout GameState) -> Void] = [
            { $0.quests.spaceMonster = 1 }, { $0.quests.dragonfly = 3 },
            { $0.galaxy.systems[SystemID.zalkon].specialEvent = .dragonflyShield },
            { $0.quests.japori = 1 }, { $0.quests.artifact = 1 }, { $0.quests.wild = 1 }, { $0.quests.jarek = 1 },
            { $0.quests.gemulon = 6 }, { $0.galaxy.systems[SystemID.gemulon].specialEvent = .gemulonFuel },
            { $0.quests.experiment = 10 }, { $0.quests.reactor = 20 - 1 },
            { $0.galaxy.systems[SystemID.nix].specialEvent = .reactorLaser }, { $0.quests.scarab = 1 },
            { $0.commander.ship.tribbles = 1 }, { $0.quests.moon = 1 },
        ]
        for (i, adjust) in adjustments.enumerated() {
            var s = base
            adjust(&s)
            #expect(s.openQuests == 1, "condition \(i)")
        }
        // Closed or finished statuses do not count.
        let closed: [(inout GameState) -> Void] = [
            { $0.quests.spaceMonster = 2 }, { $0.quests.dragonfly = 5 }, { $0.quests.japori = 2 }, { $0.quests.artifact = 2 },
            { $0.quests.wild = QuestStatus.Wild.done }, { $0.quests.gemulon = 7 }, { $0.quests.experiment = 11 },
            { $0.quests.reactor = 21 }, { $0.quests.scarab = 2 }, { $0.quests.moon = 2 },
        ]
        for (i, adjust) in closed.enumerated() {
            var s = base
            adjust(&s)
            #expect(s.openQuests == 0, "closed \(i)")
        }
    }

    // RUL-141 QST-ARTIFACT-002 QST-DRAGONFLY-005 QST-EXPERIMENT-002 QST-GEMULON-003 QST-JAPORI-004 QST-JAREK-005
    // QST-MONSTER-004 QST-REACTOR-004 QST-SCARAB-004 QST-TRIBBLES-002 QST-WILD-005: each of the 11 starts.
    @Test("RUL-141 QST-TRIBBLES-002 Palm hides the 11 quest starts while more than 3 quests are open (T > 0 counts)")
    func cap() {
        let starts: [SpecialEventType] = [.tribble, .spaceMonster, .dragonfly, .japori, .artifact, .jarek, .gemulon,
                                          .experiment, .wild, .reactor, .scarab]
        #expect(GameState.cappedQuestStarts == Set(starts))
        for event in starts {
            for ruleset in allRulesets {
                // Tribbles (T > 0) are the fourth open quest: 3 open shows, 4 open hides in Palm only.
                let three = questEngine(ruleset, event) { s in
                    fourOpen(&s, tribbles: 0)
                    s.commander.policeRecordScore = recordFor(event)
                }.state
                let four = questEngine(ruleset, event) { s in
                    fourOpen(&s)
                    s.commander.policeRecordScore = recordFor(event)
                }.state
                #expect(three.openQuests == 3 && four.openQuests == 4)
                #expect(three.specialEventAvailable == event, "\(event) \(ruleset)")
                #expect((four.specialEventAvailable == event) == (ruleset != .palm122), "\(event) \(ruleset)")
            }
        }
        // Non-start events are never capped (e.g. the Japori delivery, Erase Record).
        let delivery = questEngine(.palm122, .japoriDelivery) { s in fourOpen(&s); s.quests.japori = 1 }.state
        #expect(delivery.openQuests == 5 && delivery.specialEventAvailable == .japoriDelivery)
    }

    @Test("QST-JAREK-005 QST-WILD-005 Palm shows jarekGetsOut / wildGetsOut while the passenger is aboard (status 1)")
    func getsOut() {
        for (event, id, status) in [(SpecialEventType.jarekGetsOut, CrewID.jarek, 1), (.wildGetsOut, CrewID.wild, 1)] {
            let aboard = questEngine(.palm122, event) { s in
                s.commander.ship = QuestTrip.ship(.wasp, s, weapons: [.beamLaser])
                s.hireCrew(id)
                if id == CrewID.jarek { s.quests.jarek = status } else { s.quests.wild = status }
            }.state
            #expect(aboard.specialEventAvailable == event)
            #expect(questEngine(.palm122, event).state.specialEventAvailable == nil)
        }
    }

    @Test("QST-004 QST-DRAGONFLY-005 Palm Dragonfly and monster follow-ups match C# for every status at which the event exists")
    func followUpEquivalence() {
        // Waypoints exist only until visited, so statuses past them are unreachable while the event is present.
        let reachable: [(SpecialEventType, ClosedRange<Int>)] = [
            (.dragonflyBaratas, 0...1), (.dragonflyMelina, 0...2), (.dragonflyRegulas, 0...3), (.dragonflyDestroyed, 0...5),
        ]
        for (event, statuses) in reachable {
            for status in statuses {
                let palm = questEngine(.palm122, event) { $0.quests.dragonfly = status }.state.specialEventAvailable
                let win = questEngine(.windows201, event) { $0.quests.dragonfly = status }.state.specialEventAvailable
                #expect(palm == win, "\(event) \(status)")
                // Palm: shown iff status ≥ 1 / ≥ 2 / ≥ 3 / ≥ 5.
                let palmMin = [SpecialEventType.dragonflyBaratas: 1, .dragonflyMelina: 2, .dragonflyRegulas: 3][event] ?? 5
                #expect((palm == event) == (status >= palmMin))
            }
        }
        for status in 0...2 {
            let palm = questEngine(.palm122, .spaceMonsterKilled) { $0.quests.spaceMonster = status }.state
            #expect((palm.specialEventAvailable == .spaceMonsterKilled) == (status >= 2))
        }
    }

    @Test("QST-004 RUL-141 the Sculpture and Princess events are hidden when the content pack lacks the quest")
    func contentGuards() {
        let s = questEngine(.windows201) { s in
            s.commander.policeRecordScore = -10
            s.quests.princess = QuestStatus.Princess.flyQonos
        }.state
        var noQuests = Ruleset.palm122
        noQuests.content.hasSculptureQuest = false
        noQuests.content.hasPrincessQuest = false
        let cases: [SpecialEventType] = [.sculpture, .princessCentauri, .princessInthara, .sculptureHiddenBays, .princessQuantum]
        for event in cases {
            #expect(s.specialEventShown(event, rules: .windows201), "\(event)")
            #expect(!s.specialEventShown(event, rules: noQuests), "\(event)")
        }
        #expect(GameState.sculptureEvents.count == 3 && GameState.princessEvents.count == 6)
        // Shared events are unaffected by the guards.
        #expect(s.specialEventShown(.skill, rules: noQuests))
    }

    @Test("QST-SCARAB-004 with no scarab event placed the quest never starts and the end-point encounter never fires")
    func noScarabEvent() {
        var e = questEngine(.palm122)
        for i in e.state.galaxy.systems.indices where e.state.galaxy.systems[i].specialEvent == .scarab {
            e.state.galaxy.systems[i].specialEvent = nil
        }
        for i in e.state.galaxy.systems.indices {
            QSTKit.dock(&e, at: i)
            #expect(e.state.specialEventAvailable != .scarab)
        }
        #expect(e.state.quests.scarab == 0)
        let end = e.state.galaxy.wormholes[0]
        e.state.galaxy.systems[end].specialEvent = .scarabDestroyed
        e.state.warpSystem = end
        e.state.arrivedViaWormhole = true
        #expect(e.state.determineFixedEncounter(clicks: 20) == nil)
    }
}

@Suite("Quest rulesets: moon, price timing, endings (RUL-006, RUL-142, RUL-143)")
struct QuestRulesetMoonPriceSpecTests {
    private func moonState(_ ruleset: RulesetID, worth: Int) -> GameState {
        questEngine(ruleset, .moon) { s in
            s.commander.cash += worth - s.worth
        }.state
    }

    @Test("RUL-142 QST-MOON-003 the moon offer: worth > 400000 (Windows, Modern) or ≥ 400000 (Palm)")
    func moonThreshold() {
        for ruleset in allRulesets {
            #expect(moonState(ruleset, worth: 400_000).worth == 400_000)
            #expect((moonState(ruleset, worth: 400_000).specialEventAvailable == .moon) == (ruleset == .palm122), "\(ruleset)")
            #expect(moonState(ruleset, worth: 400_001).specialEventAvailable == .moon)
            #expect(moonState(ruleset, worth: 399_999).specialEventAvailable == nil)
        }
        #expect(QuestRules.palm122.moonOfferThreshold == .atLeastFourFifths)
        #expect(QuestRules.modern.moonOfferThreshold == QuestRules.windows201.moonOfferThreshold)
    }

    /// A ship whose shield slots are all filled.
    private func noShieldSlot(_ s: inout GameState) {
        while s.commander.ship.freeShieldSlots(s.ruleset) > 0 {
            s.commander.ship.shields.append(ShieldInstance(type: .energy, charge: 0))
        }
    }

    @Test("RUL-143 QST-011 Palm charges the price before the effect and keeps it on a refusal; C# charges after")
    func priceTiming() throws {
        let priced = SpecialEventSpec(type: .dragonflyShield, price: 1_000, occurrence: 0, messageOnly: false)
        // Refusal (no free shield slot).
        var palm = questEngine(.palm122, .dragonflyShield, noShieldSlot)
        let palmResult = palm.handleSpecialEvent(.dragonflyShield, spec: priced, [.acceptSpecialEvent])
        #expect(palmResult.rejection == nil)
        #expect(palmResult.events == [.specialEventRefused(.dragonflyShield, reason: .noFreeSlot)])
        #expect(palm.state.commander.cash == 199_000 && palm.state.currentSystem.specialEvent == .dragonflyShield)
        var win = questEngine(.windows201, .dragonflyShield, noShieldSlot)
        #expect(win.handleSpecialEvent(.dragonflyShield, spec: priced, [.acceptSpecialEvent]).rejection == .noFreeSlot)
        #expect(win.state.commander.cash == 200_000 && win.state.currentSystem.specialEvent == .dragonflyShield)
        // Success: same total charge in every ruleset (Erase Record).
        for ruleset in allRulesets {
            var e = questEngine(ruleset, .eraseRecord) { $0.commander.policeRecordScore = -10 }
            let price = try #require(e.state.specialEventSpec(.eraseRecord)).price
            #expect(e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).rejection == nil)
            #expect(e.state.commander.cash == 200_000 - price && e.state.commander.policeRecordScore == 0)
        }
        // Every shipped refusable event costs 0, so the timing difference never shows with the real tables.
        for ruleset in allRulesets {
            let s = questEngine(ruleset).state
            for event in [SpecialEventType.jarek, .wild, .reactor, .japori, .dragonflyShield, .reactorLaser, .gemulonFuel,
                          .princessQonos, .princessQuantum, .sculptureHiddenBays] {
                if let spec = s.specialEventSpec(event) { #expect(spec.price == 0, "\(event) \(ruleset)") }
            }
        }
        // Palm refusal with a free event is a plain rejection that keeps the event (nothing charged).
        var free = questEngine(.palm122, .dragonflyShield, noShieldSlot)
        #expect(free.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).rejection == .noFreeSlot)
        #expect(free.state.currentSystem.specialEvent == .dragonflyShield)
    }

    @Test("RUL-006 QST-MOON-012 QST-PRINCESS-015 Modern retires to the moon-girl ending after the Princess quest; same score")
    func moonGirl() {
        for ruleset in allRulesets {
            for princess in [QuestStatus.Princess.returned, QuestStatus.Princess.done] {
                var e = questEngine(ruleset, .moonRetirement) { s in
                    s.quests.moon = QuestStatus.Moon.bought
                    s.quests.princess = princess
                }
                let r = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
                let girl = ruleset == .modern && princess == QuestStatus.Princess.done
                let end: GameEndType = girl ? .boughtMoonGirl : .boughtMoon
                #expect(e.state.phase == .gameOver(end), "\(ruleset) \(princess)")
                #expect(r.events.last == .gameEnded(end, score: e.state.score(for: .boughtMoon)))
                #expect(e.state.score(for: .boughtMoonGirl) == e.state.score(for: .boughtMoon))
            }
        }
        #expect(QuestRules.modern.moonGirlEnding && !QuestRules.windows201.moonGirlEnding && !QuestRules.palm122.moonGirlEnding)
    }
}

@Suite("Quest rulesets: Japori, Gemulon, statuses and pod outcomes (RUL-171, RUL-172)")
struct QuestRulesetChainSpecTests {
    @Test("RUL-171 QST-JAPORI-008 Palm removes the Japori pickup once accepted; C# keeps it; a bay refusal keeps it")
    func japoriPickup() {
        for ruleset in allRulesets {
            var e = questEngine(ruleset, .japori)
            #expect(e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).rejection == nil)
            #expect(e.state.quests.japori == QuestStatus.Japori.inTransit)
            #expect((e.state.currentSystem.specialEvent == .japori) == (ruleset != .palm122), "\(ruleset)")
            var full = questEngine(ruleset, .japori) { s in
                s.commander.ship.cargo[0] = s.commander.ship.spec(s.ruleset).cargoBays
            }
            #expect(full.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).rejection == .noEmptyBays)
            #expect(full.state.currentSystem.specialEvent == .japori)
        }
        #expect(QuestRules.modern.japoriPickupPersists && !QuestRules.palm122.japoriPickupPersists)
    }

    @Test("QST-JAPORI-011 Palm arrest sets Japori 2; the pod sets 0 and, the pickup gone, the quest cannot restart")
    func japoriFailures() {
        var start = questEngine(.palm122, .japori)
        _ = start.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        let pickup = start.state.commander.currentSystem
        var arrested = start
        _ = arrested.state.arrested()
        #expect(arrested.state.quests.japori == QuestStatus.Japori.done)
        var pod = start
        pod.state.commander.ship.escapePod = true
        _ = pod.state.escapeWithPod()
        #expect(pod.state.quests.japori == QuestStatus.Japori.notStarted)
        QSTKit.dock(&pod, at: pickup)
        #expect(pod.state.specialEventAvailable == nil)
        #expect(pod.state.galaxy.systems[pickup].specialEvent == nil)
        // Windows: the pod failure leaves the pickup offered again.
        var win = questEngine(.windows201, .japori)
        let winPickup = win.state.commander.currentSystem
        _ = win.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        win.state.commander.ship.escapePod = true
        _ = win.state.escapeWithPod()
        QSTKit.dock(&win, at: winPickup)
        #expect(win.state.quests.japori == QuestStatus.Japori.notStarted)
        #expect(win.state.currentSystem.specialEvent == .japori)
        #expect(win.state.specialEventAvailable == .japori)
    }

    @Test("RUL-172 QST-GEMULON-012 Palm rescue → Fuel Compactor; installing it fills the tank (Palm only)")
    func gemulonReward() {
        for ruleset in allRulesets {
            var e = questEngine(ruleset, .gemulonRescued) { $0.quests.gemulon = 3 }
            #expect(e.perform(.specialEvent).rejection == nil)
            #expect(e.state.currentSystem.specialEvent == .gemulonFuel)
            // The rescued status (engine 9; Palm 0 + the waiting compactor) still counts one open quest and no longer ticks.
            #expect(e.state.openQuests == 1)
            let status = e.state.quests.gemulon
            _ = e.state.incDays(5)
            #expect(e.state.quests.gemulon == status)
            e.state.commander.ship.fuel = 1
            #expect(e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent]).rejection == nil)
            #expect(e.state.commander.ship.gadgets.contains(.fuelCompactor))
            let tanks = e.state.commander.ship.fuelTanks(e.ruleset)
            #expect(e.state.commander.ship.fuel == (ruleset == .palm122 ? tanks : 1), "\(ruleset)")
        }
    }

    @Test("QST-DRAGONFLY-011 QST-MONSTER-007 QST-REACTOR-016 Palm rewards store the same done statuses as C# (6, 3, 22)")
    func doneStatuses() {
        for ruleset in allRulesets {
            var d = questEngine(ruleset, .dragonflyShield) { s in
                s.commander.ship = QuestTrip.ship(.wasp, s)
                s.quests.dragonfly = 5
            }
            _ = d.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
            #expect(d.state.quests.dragonfly == 6 && d.state.commander.ship.has(.lightning))
            var m = questEngine(ruleset, .spaceMonsterKilled) { $0.quests.spaceMonster = 2 }
            _ = m.perform(.specialEvent)
            #expect(m.state.quests.spaceMonster == 3 && m.state.commander.cash == 215_000)
            var r = questEngine(ruleset, .reactorLaser) { s in
                s.commander.ship = QuestTrip.ship(.wasp, s)
                s.quests.reactor = 21
            }
            _ = r.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
            #expect(r.state.quests.reactor == 22 && r.state.commander.ship.weapons.contains(.morgansLaser))
            // No rule reads the difference: none of the finished quests is open or re-offered.
            for s in [d.state, m.state, r.state] { #expect(s.openQuests == 0 && s.specialEventAvailable == nil) }
        }
    }

    @Test("QST-SCARAB-010 Palm hull upgrade: hull +50, status 3, strength spec + 50 while upgraded, event kept")
    func scarabHull() {
        var e = questEngine(.palm122, .scarabUpgradeHull) { $0.quests.scarab = 2 }
        let hull = e.state.commander.ship.hull, spec = e.state.commander.ship.spec(e.ruleset).hullStrength
        _ = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(e.state.commander.ship.hull == hull + 50 && e.state.quests.scarab == 3)
        #expect(e.state.commander.ship.hullStrength(e.ruleset) == spec + 50)
        #expect(e.state.currentSystem.specialEvent == .scarabUpgradeHull && e.state.specialEventAvailable == nil)
    }

    @Test("QST-ARTIFACT-009 Palm pod: the artifact is no longer aboard, not open, not deliverable, and cannot be picked up again")
    func artifactPod() {
        var e = questEngine(.palm122, .artifact)
        _ = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        let pickup = e.state.commander.currentSystem
        #expect(e.state.artifactOnBoard && e.state.openQuests == 1 && e.state.currentSystem.specialEvent == nil)
        e.state.commander.ship.escapePod = true
        _ = e.state.escapeWithPod()
        #expect(!e.state.artifactOnBoard && e.state.openQuests == 0)
        e.state.galaxy.systems[pickup].specialEvent = .artifactDelivery
        QSTKit.dock(&e, at: pickup)
        #expect(e.state.specialEventAvailable == nil)
        #expect(e.state.galaxy.systems[pickup].specialEvent == .artifactDelivery)
        e.state.galaxy.systems[pickup].specialEvent = nil
        #expect(e.state.specialEventAvailable == nil)
    }
}

@Suite("Quest rulesets: Wild and Erase Record (RUL-037, RUL-111, RUL-115)")
struct QuestRulesetWildSpecTests {
    private func wildAboard(_ ruleset: RulesetID, record: Int, weapons: [WeaponType] = [.beamLaser]) -> GameEngine {
        questEngine(ruleset, .wildGetsOut) { s in
            s.commander.ship = QuestTrip.ship(.wasp, s, weapons: weapons)
            s.hireCrew(CrewID.wild)
            s.quests.wild = QuestStatus.Wild.started
            s.commander.policeRecordScore = record
            s.sellPrices = Array(repeating: 90, count: 10)
        }
    }

    @Test("RUL-037 QST-WILD-020 delivery record: 0 in C#, max(record, 0) in Palm; Palm adds Zeethibal and no sell recalculation")
    func delivery() {
        for ruleset in allRulesets {
            for record in [-10, 50] {
                var e = wildAboard(ruleset, record: record)
                _ = e.perform(.specialEvent)
                let expected = ruleset == .palm122 ? max(record, 0) : 0
                #expect(e.state.commander.policeRecordScore == expected, "\(ruleset) \(record)")
                #expect(e.state.quests.wild == QuestStatus.Wild.done && !e.state.wildOnBoard)
                #expect(e.state.mercenaries[CrewID.zeethibal].systemID == SystemID.kravat)
                #expect(e.state.mercenaries[CrewID.zeethibal].skills.sorted() == [5, 5, 8, 10])
                if ruleset == .palm122 { #expect(e.state.sellPrices == Array(repeating: 90, count: 10)) }
            }
        }
    }

    @Test("RUL-115 QST-WILD-019 Wild delivery recalculates sell prices: always (Windows), only if criminal (Modern), never (Palm)")
    func wildSellRecalc() {
        for ruleset in allRulesets {
            for record in [-10, 0] {
                var e = wildAboard(ruleset, record: record)
                _ = e.perform(.specialEvent)
                let recalc = ruleset == .windows201 || (ruleset == .modern && record < -5)
                #expect(e.state.sellPrices == Array(repeating: recalc ? 100 : 90, count: 10), "\(ruleset) \(record)")
            }
        }
    }

    @Test("RUL-115 QST-ONEOFF-006 Erase Record recalculates in every ruleset: it is offered only while record < −5")
    func eraseRecordRecalc() {
        for ruleset in allRulesets {
            #expect(questEngine(ruleset, .eraseRecord) { $0.commander.policeRecordScore = -5 }.state.specialEventAvailable == nil)
            var e = questEngine(ruleset, .eraseRecord) { s in
                s.commander.policeRecordScore = -6
                s.sellPrices = Array(repeating: 90, count: 10)
            }
            _ = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
            #expect(e.state.sellPrices == Array(repeating: 100, count: 10), "\(ruleset)")
        }
        #expect(QuestRules.modern.sellPriceRecalc == .onlyIfCriminal && QuestRules.palm122.sellPriceRecalc == .eraseRecordOnly)
    }

    @Test("RUL-111 QST-WILD-007 Wild boards and stays only with Beam/Military/Morgan's in Modern and Palm; disruptors count in Windows")
    func realLaser() {
        for ruleset in allRulesets {
            let strict = ruleset != .windows201
            for weapon in WeaponType.allCases {
                let qualifies = strict ? [.beamLaser, .militaryLaser, .morgansLaser].contains(weapon) : weapon >= .beamLaser
                var board = questEngine(ruleset, .wild) { s in
                    s.commander.ship = QuestTrip.ship(.wasp, s, weapons: [weapon])
                    s.commander.policeRecordScore = -10
                }
                let r = board.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
                #expect((r.rejection == nil) == qualifies, "\(ruleset) \(weapon)")
                if !qualifies { #expect(r.rejection == .wildRequiresLaser) }
                let stay = wildAboard(ruleset, record: -10, weapons: [weapon]).state
                #expect(stay.wildWillLeave == !qualifies, "\(ruleset) \(weapon)")
            }
        }
    }
}

@Suite("Quest rulesets: quest-ship damage between meetings (RUL-173)")
struct QuestRulesetSpecialShipSpecTests {
    /// One fleeing round on Beginner (escape is certain) against `ship`, whose hull was cut to `hull`.
    private func fleeRound(_ ruleset: RulesetID, _ type: EncounterType, _ pick: (GameState) -> Ship, hull: Int) -> GameState {
        var s = questEngine(ruleset, difficulty: .beginner).state
        s.commander.ship.hull = 100_000
        var opp = pick(s)
        opp.hull = hull
        var enc = EncounterState(type: type, opponent: opp, clicks: 1)
        enc.cmdrFleeing = true
        let (_, events) = s.executeRound(&enc)
        #expect(events.contains { if case .playerEscaped = $0 { true } else { false } })
        return s
    }

    @Test("RUL-173 C# keeps quest-ship damage; Palm fights a copy and writes back only the monster's hull on escape")
    func damagePersistence() {
        for ruleset in allRulesets {
            let palm = ruleset == .palm122
            let fresh = questEngine(ruleset).state.specialShips
            let dragon = fleeRound(ruleset, .dragonflyAttack, { $0.specialShips.dragonfly }, hull: 7)
            #expect(dragon.specialShips.dragonfly.hull == (palm ? fresh.dragonfly.hull : 7), "\(ruleset)")
            let scarab = fleeRound(ruleset, .scarabAttack, { $0.specialShips.scarab }, hull: 9)
            #expect(scarab.specialShips.scarab.hull == (palm ? fresh.scarab.hull : 9), "\(ruleset)")
            let monster = fleeRound(ruleset, .spaceMonsterAttack, { $0.specialShips.spaceMonster }, hull: 123)
            #expect(monster.specialShips.spaceMonster.hull == 123, "\(ruleset)")
            // Without an escape (plunder/surrender write-back at the end of an encounter) Palm keeps nothing.
            var s = questEngine(ruleset).state
            var damaged = s.specialShips.spaceMonster
            damaged.hull = 11
            s.persistSpecialShip(damaged)
            #expect(s.specialShips.spaceMonster.hull == (palm ? fresh.spaceMonster.hull : 11))
        }
        #expect(QuestRules.palm122.specialShipDamagePersists == .monsterHullOnEscape && QuestRules.modern.specialShipDamagePersists == .allShips)
    }
}
