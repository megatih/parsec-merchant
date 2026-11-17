// SPDX-License-Identifier: GPL-2.0-or-later
// ACH (docs/specs/ACH.md §1, §2, §6): the catalog, progress, unlock transitions and cheats.
import Testing
import ParsecEngine
@testable import ParsecInsights

private typealias Build = (inout EntryBuilder) -> Void

private func won(_ end: GameEndType = .boughtMoon) -> Build { { $0.add(.gameEnded(end, score: 1)) } }

private func quest(_ e: SpecialEventType) -> Build { { $0.add(.quest(.completed(e))) } }

private func repeatAdd(_ n: Int, _ kind: @escaping (Int) -> LogEntryKind) -> Build {
    { b in for i in 0..<n { b.add(kind(i)) } }
}

private func visits(_ n: Int) -> Build {
    repeatAdd(n) { .arrived(TripArrival(system: $0, from: 0, viaWormhole: false, firstVisit: true, uneventful: true, encounterCount: 0)) }
}

private func items(_ n: Int) -> Build {
    repeatAdd(n) { .trade(TradeEntry(action: $0 % 2 == 0 ? .buy : .sell, item: TradeItemType(rawValue: $0) ?? .water, quantity: 1, total: 1,
                                     profit: $0 % 2 == 0 ? nil : 0)) }
}

private func encounters(_ n: Int, _ outcome: EncounterOutcomeKind = .passed, type: EncounterType = .pirateAttack,
                        bounty: Int = 0, hull: Int = 50) -> Build {
    repeatAdd(n) { _ in .encounter(record(outcome, type: type, hull: hull, bounty: bounty)) }
}

/// ACH-007: per catalog entry (ACH-030…065), entries that just meet and just miss the condition, and the start used.
private struct Case {
    var spec: String
    var id: AchievementID
    var meets: Build
    var misses: Build
    var start: JournalStart = EntryBuilder.start(systems: 120, visited: [])
}

private var cases: [Case] { [
    Case(spec: "ACH-030", id: .firstProfit,
         meets: { $0.add(.trade(TradeEntry(action: .orbitSell, item: .ore, quantity: 1, total: 9, profit: 1))) },
         misses: { $0.add(.trade(TradeEntry(action: .sell, item: .ore, quantity: 1, total: 9, profit: 0))) }),
    Case(spec: "ACH-031", id: .worth10k, meets: { $0.add(.singularityLost, worth: 10_000) },
         misses: { $0.add(.singularityLost, worth: 9_999) }),
    Case(spec: "ACH-032", id: .worth100k, meets: { $0.add(.singularityLost, worth: 100_000) }, misses: { $0.add(.singularityLost, worth: 99_999) }),
    Case(spec: "ACH-033", id: .worth1m, meets: { $0.add(.singularityLost, worth: 1_000_000) }, misses: { $0.add(.singularityLost, worth: 999_999) }),
    Case(spec: "ACH-034", id: .dragonfly, meets: quest(.dragonflyShield), misses: quest(.dragonflyDestroyed)),
    Case(spec: "ACH-035", id: .spaceMonster, meets: quest(.spaceMonsterKilled), misses: quest(.spaceMonster)),
    Case(spec: "ACH-036", id: .scarab, meets: quest(.scarabUpgradeHull), misses: quest(.scarabDestroyed)),
    Case(spec: "ACH-037", id: .japori, meets: quest(.japoriDelivery), misses: quest(.japori)),
    Case(spec: "ACH-038", id: .jarek, meets: quest(.jarekGetsOut), misses: quest(.jarek)),
    Case(spec: "ACH-039", id: .wild, meets: quest(.wildGetsOut), misses: quest(.wild)),
    Case(spec: "ACH-040", id: .reactor, meets: quest(.reactorLaser), misses: quest(.reactorDelivered)),
    Case(spec: "ACH-041", id: .gemulon, meets: quest(.gemulonFuel), misses: quest(.gemulonRescued)),
    Case(spec: "ACH-042", id: .experiment, meets: quest(.experimentStopped), misses: quest(.experimentFailed)),
    Case(spec: "ACH-043", id: .artifact, meets: quest(.artifactDelivery), misses: quest(.artifact)),
    Case(spec: "ACH-044", id: .sculpture, meets: quest(.sculptureHiddenBays), misses: quest(.sculptureDelivered)),
    Case(spec: "ACH-045", id: .princess, meets: quest(.princessQuantum), misses: quest(.princessReturned)),
    Case(spec: "ACH-046", id: .moon, meets: won(.boughtMoonGirl), misses: won(.retired)),
    Case(spec: "ACH-047", id: .waspKiller, meets: encounters(1, .destroyed(.wasp)), misses: encounters(1, .disabled, type: .pirateAttack)),
    Case(spec: "ACH-048", id: .closeCall, meets: encounters(1, .escaped, hull: 9), misses: { b in
        encounters(1, .escaped, hull: 10)(&b)
        encounters(1, .killed, hull: 0)(&b)
    }),
    Case(spec: "ACH-049", id: .hero, meets: { $0.add(.status(.policeRecord(from: .liked, to: .hero))) },
         misses: { $0.add(.status(.policeRecord(from: .trusted, to: .liked))) }),
    Case(spec: "ACH-050", id: .villain, meets: { $0.add(.status(.policeRecord(from: .criminal, to: .villain))) },
         misses: { $0.add(.status(.policeRecord(from: .crook, to: .criminal))) }),
    Case(spec: "ACH-051", id: .debtFree, meets: { $0.add(.finance(.repaid(amount: 5, remainingDebt: 0))) },
         misses: { $0.add(.finance(.repaid(amount: 5, remainingDebt: 1))) }),
    Case(spec: "ACH-052", id: .explorer50, meets: visits(50), misses: visits(49)),
    Case(spec: "ACH-053", id: .explorerAll, meets: visits(128), misses: visits(127), start: EntryBuilder.start(systems: 128, visited: [])),
    Case(spec: "ACH-054", id: .wormhole, meets: { $0.add(.departed(from: 0, to: 1, viaWormhole: true, parsecs: 0)) },
         misses: { $0.add(.departed(from: 0, to: 1, viaWormhole: false, parsecs: 3)) }),
    Case(spec: "ACH-055", id: .winHard, meets: won(), misses: won(), start: EntryBuilder.start(difficulty: .hard)),
    Case(spec: "ACH-056", id: .winImpossible, meets: won(), misses: won(), start: EntryBuilder.start(difficulty: .impossible)),
    Case(spec: "ACH-057", id: .allCommodities, meets: items(10), misses: items(9)),
    Case(spec: "ACH-058", id: .tribbleMax, meets: { $0.add(.quest(.tribbles(from: 50_000, to: 100_000))) },
         misses: { $0.add(.quest(.tribbles(from: 50_000, to: 99_999))) }),
    Case(spec: "ACH-059", id: .marieCeleste, meets: encounters(1, type: .marieCeleste), misses: encounters(1, type: .marieCelestePolice)),
    Case(spec: "ACH-060", id: .famousCaptains, meets: { b in
        for t in [EncounterType.captainAhab, .captainConrad, .captainHuie] { encounters(1, type: t)(&b) }
    }, misses: { b in
        for t in [EncounterType.captainAhab, .captainConrad, .famousCaptainAttack] { encounters(1, type: t)(&b) }
    }),
    Case(spec: "ACH-061", id: .escapePod, meets: { $0.add(.ship(.escapePodUsed(insurancePayout: 0))) },
         misses: { $0.add(.ship(.boughtEscapePod(price: 2_000))) }),
    Case(spec: "ACH-062", id: .designer, meets: { $0.add(.ship(.customShipBuilt(.kuat))) }, misses: { $0.add(.ship(.boughtShip(.wasp, netPrice: 1))) }),
    Case(spec: "ACH-063", id: .ironman, meets: won(.retired), misses: won(.killed), start: EntryBuilder.start(ironman: true)),
    Case(spec: "ACH-064", id: .bountyHunter, meets: encounters(10, .destroyed(.gnat), bounty: 1), misses: encounters(9, .destroyed(.gnat), bounty: 1)),
    Case(spec: "ACH-065", id: .bigScore, meets: { $0.add(.trade(TradeEntry(action: .sell, item: .robots, quantity: 9, total: 1, profit: 10_000))) },
         misses: { $0.add(.trade(TradeEntry(action: .sell, item: .robots, quantity: 9, total: 1, profit: 9_999))) }),
] }

private func stats(_ start: JournalStart, _ build: Build) -> CareerStats {
    var b = EntryBuilder(start: start)
    build(&b)
    return b.stats
}

@Suite("ACH achievements")
struct AchievementSpecTests {
    @Test("ACH-001 36 cases in catalog order with permanent lowerCamelCase raw values")
    func ids() {
        let raw = "firstProfit worth10k worth100k worth1m dragonfly spaceMonster scarab japori jarek wild reactor gemulon experiment "
            + "artifact sculpture princess moon waspKiller closeCall hero villain debtFree explorer50 explorerAll wormhole winHard "
            + "winImpossible allCommodities tribbleMax marieCeleste famousCaptains escapePod designer ironman bountyHunter bigScore"
        #expect(AchievementID.allCases.map(\.rawValue) == raw.split(separator: " ").map(String.init))
        #expect(AchievementID.allCases.count == 36)
    }

    @Test("ACH-002 definitions: threshold or flag over CareerStats")
    func definitions() {
        #expect(AchievementCatalog.definition(.worth10k).kind == .threshold(target: 10_000))
        #expect(AchievementCatalog.definition(.firstProfit).kind == .flag && AchievementKind.flag.target == 1)
        #expect(AchievementCatalog.definition(.explorerAll, ruleset: .palm122).kind == .threshold(target: Ruleset.palm122.tables.systemNames.count))
        #expect(AchievementCatalog.definition(.tribbleMax).kind == .threshold(target: AchievementCatalog.tribbleCap))
        for id in AchievementID.allCases { #expect(AchievementCatalog.definition(id).id == id) }
    }

    @Test("ACH-003 availability from content: every ruleset has at least 30; Palm 1.2.2 has 33")
    func availability() {
        for r in RulesetID.allCases {
            let ruleset = Ruleset.named(r)
            let available = AchievementCatalog.available(in: ruleset)
            #expect(available.count >= 30)
            #expect(available.contains(.sculpture) == ruleset.content.hasSculptureQuest)
            #expect(available.contains(.princess) == ruleset.content.hasPrincessQuest)
            #expect(available.contains(.designer) == ruleset.content.hasShipyards)
        }
        #expect(AchievementCatalog.available(in: .palm122).count == 33 && AchievementCatalog.available(in: .modern).count == 36)
    }

    @Test("ACH-004 evaluate: every available achievement in order, current clamped to the target")
    func evaluate() {
        let s = stats(EntryBuilder.start()) { $0.add(.singularityLost, worth: 50_000) }
        let p = AchievementCatalog.evaluate(s, ruleset: .palm122)
        #expect(p.map(\.id) == AchievementCatalog.available(in: .palm122))
        let w = p.first { $0.id == .worth10k }
        #expect(w == AchievementProgress(id: .worth10k, current: 10_000, target: 10_000, satisfied: true))
        #expect(p.first { $0.id == .worth100k } == AchievementProgress(id: .worth100k, current: 50_000, target: 100_000, satisfied: false))
        let negative = stats(EntryBuilder.start()) { $0.add(.singularityLost, worth: -5) }
        #expect(AchievementCatalog.evaluate(negative, ruleset: .modern).allSatisfy { $0.current >= 0 })
    }

    @Test("ACH-005 ACH-008 CHEAT-004 satisfied lists in catalog order and is empty for a cheated game")
    func satisfied() {
        let s = stats(EntryBuilder.start()) { b in
            b.add(.singularityLost, worth: 200_000)
            b.add(.departed(from: 0, to: 1, viaWormhole: true, parsecs: 0))
        }
        #expect(AchievementCatalog.satisfied(s, ruleset: .modern) == [.worth10k, .worth100k, .wormhole])
        let cheated = stats(EntryBuilder.start()) { b in
            b.add(.singularityLost, worth: 200_000)
            b.add(.cheatsEnabled)
        }
        #expect(AchievementCatalog.satisfied(cheated, ruleset: .modern).isEmpty)
        #expect(!AchievementCatalog.evaluate(cheated, ruleset: .modern).isEmpty)
    }

    @Test("ACH-006 unlocks are transitions: appended once, stamped like the step, never re-reported for a satisfied journal")
    func transitions() throws {
        var s = freshState(.modern, seed: 3)
        s.commander.ship.cargo[0] = 2
        s.commander.priceCargo[0] = 2
        var g = RecordedGame(s)
        g.send(.sellCargo(.water, quantity: 1))
        g.send(.sellCargo(.water, quantity: 1))
        let unlocks = g.journal.entries.filter { $0.kind == .achievementUnlocked(.firstProfit) }
        #expect(unlocks.count == 1 && g.outputs[0].unlocked == [.firstProfit] && g.outputs[1].unlocked.isEmpty)
        let trade = try #require(g.journal.entries.first { $0.kind.category == .trade })
        #expect(unlocks[0].day == trade.day && unlocks[0].system == trade.system && unlocks[0].worth == trade.worth)
        // A bootstrapped journal of a state already worth 10k reports nothing for that condition later.
        var rich = freshState(.modern, seed: 3)
        rich.commander.cash = 200_000
        var h = RecordedGame(rich)
        h.journal = GameJournal.bootstrap(from: rich)
        h.send(.buyFuel(credits: 10))
        #expect(!h.journal.entries.contains { $0.kind == .achievementUnlocked(.worth10k) })
        #expect(AchievementCatalog.newlyUnlocked(before: h.journal.stats, after: h.journal.stats, ruleset: .modern).isEmpty)
    }

    @Test("ACH-007 ACH-030…065 each catalog entry: entries that just meet satisfy it, entries that just miss do not")
    func catalogFolds() {
        #expect(cases.map(\.id) == AchievementID.allCases && cases.map(\.spec).count == 36)
        for c in cases {
            let d = AchievementCatalog.definition(c.id, ruleset: .modern)
            #expect(d.isSatisfied(by: stats(c.start, c.meets)), "\(c.spec) \(c.id) should be met")
            let missStart: JournalStart = switch c.id {
            case .winHard: EntryBuilder.start(difficulty: .normal)
            case .winImpossible: EntryBuilder.start(difficulty: .hard)
            case .ironman: EntryBuilder.start(ironman: true)
            default: c.start
            }
            #expect(!d.isSatisfied(by: stats(missStart, c.misses)), "\(c.spec) \(c.id) should be missed")
        }
        // Ironman needs an Ironman game.
        #expect(!AchievementCatalog.definition(.ironman).isSatisfied(by: stats(EntryBuilder.start(), won(.retired))))
    }

    @Test("ACH-007 each quest-chain achievement unlocks exactly once at its final reward step")
    func questChains() {
        let finals: [(AchievementID, SpecialEventType)] = [
            (.dragonfly, .dragonflyShield), (.spaceMonster, .spaceMonsterKilled), (.scarab, .scarabUpgradeHull),
            (.japori, .japoriDelivery), (.jarek, .jarekGetsOut), (.wild, .wildGetsOut), (.reactor, .reactorLaser),
            (.gemulon, .gemulonFuel), (.experiment, .experimentStopped), (.artifact, .artifactDelivery),
            (.sculpture, .sculptureHiddenBays), (.princess, .princessQuantum),
        ]
        let s = freshState(.modern, seed: 4)
        for (id, event) in finals {
            var j = GameJournal.start(state: s)
            for _ in 0..<2 {
                JournalRecorder.record(JournalStep(command: .specialEvent, before: s, result: StepResult(events: [.specialEventCompleted(event)]),
                                                   after: s), into: &j)
            }
            #expect(j.entries.filter { $0.kind == .achievementUnlocked(id) }.count == 1, "\(id)")
        }
    }

    @Test("ACH-008 a cheated journal unlocks nothing from the first cheat on, including scenario-style starts")
    func cheatedUnlocksNothing() {
        var s = freshState(.modern, seed: 5)
        s.cheatsUsed = true
        s.commander.ship.cargo[0] = 1
        s.commander.priceCargo[0] = 1
        var g = RecordedGame(s)
        g.send(.sellCargo(.water, quantity: 1))
        #expect(g.journal.entries.contains { $0.kind == .cheatsEnabled })
        #expect(!g.journal.entries.contains { $0.kind.category == .achievement })
    }

    @Test("ACH-009 CHEAT-004 unlocks before the first cheat stay; nothing unlocks after it")
    func cheatAfterUnlock() {
        var s = freshState(.windows201, seed: 6)
        s.commander.ship.cargo[0] = 1
        s.commander.priceCargo[0] = 1
        var g = RecordedGame(s)
        g.send(.sellCargo(.water, quantity: 1))
        g.send(.cheat(.enable))
        g.send(.borrow(100))
        g.send(.repay(g.state.commander.debt))
        g.send(.buyFuel(credits: 50))
        let unlocked = g.journal.entries.compactMap { if case let .achievementUnlocked(id) = $0.kind { id } else { nil } }
        #expect(unlocked == [.firstProfit])
        #expect(g.journal.stats.loansPaidOff == 1 && g.journal.stats.cheatsUsed)
    }
}
