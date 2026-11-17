// SPDX-License-Identifier: GPL-2.0-or-later
// LOG (docs/specs/LOG.md): the journal, entries, recording, the encounter ledger and reading the log.
import Foundation
import Testing
import ParsecEngine
@testable import ParsecInsights

/// A docked state and the same state mid-encounter.
private func docked() -> GameState { freshState(.windows201, seed: 7) }

private func inEncounter(_ s: GameState) -> GameState {
    var e = s
    e.phase = .encounter(EncounterState(type: .pirateAttack, opponent: Ship(type: .gnat, spec: s.ruleset.tables.ship(.gnat))))
    return e
}

private func step(_ events: [GameEvent], command: Command = .warp, before: GameState, after: GameState,
                  decision: PendingDecision? = nil) -> JournalStep {
    JournalStep(command: command, before: before, result: StepResult(events: events, decision: decision), after: after)
}

/// A journal with an open ledger.
private func journalWithLedger(_ s: GameState) -> GameJournal {
    var j = GameJournal.start(state: s)
    JournalRecorder.record(step([.encounterStarted(type: .pirateAttack, opponent: .gnat, clicks: 5, playerCloaked: false)],
                                before: s, after: inEncounter(s)), into: &j)
    return j
}

private func canonical(_ j: GameJournal) throws -> Data {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys]
    return try enc.encode(j)
}

/// LOG §3a: what one event does to a journal with an open encounter ledger.
private struct Disposition {
    var entries: [LogCategory]
    var folds: Bool
}

private let t = TradeItemType.ore
private let eventFixtures: [(GameEvent, [LogCategory], Bool)] = [
    (.gameStarted(ruleset: .modern, seed: 1), [], false),
    (.boughtCargo(item: t, quantity: 1, total: 10), [.trade], false),
    (.soldCargo(item: t, quantity: 1, total: 10, profit: 2), [.trade], false),
    (.dumpedCargo(item: t, quantity: 1, cost: 5), [.trade], false),
    (.jettisonedCargo(item: t, quantity: 1), [.trade], false),
    (.caughtLittering(newRecord: -2), [.police], false),
    (.boughtFuel(units: 2, cost: 4), [.ship], false),
    (.repairedHull(points: 3, cost: 6), [.ship], false),
    (.boughtEquipment(price: 100), [.ship], false),
    (.soldEquipment(price: 50), [], false),
    (.boughtShip(type: .gnat, netPrice: 100), [.ship], false),
    (.cannotTransfer(.escapePod), [], false),
    (.cannotAffordTransfer(.escapePod), [], false),
    (.cannotAffordAllTransfers, [], false),
    (.customShipBuilt(shipyard: .kuat), [.ship], false),
    (.combatRound(round: 1, playerHit: true, opponentHit: false, playerHull: 40, opponentHull: 10), [], true),
    (.playerDestroyed, [], true),
    (.bothDestroyed, [], true),
    (.opponentDestroyed(.gnat), [], true),
    (.opponentDisabled(.gnat), [], true),
    (.playerEscaped(wasHit: false), [], true),
    (.opponentEscaped, [], true),
    (.encounterChanged(.pirateFlee), [], true),
    (.bountyPaid(100), [], true),
    (.departed(from: 0, to: 1, viaWormhole: false), [.travel], false),
    (.fabricRip(newDestination: 2), [.travel], false),
    (.encounterStarted(type: .policeInspect, opponent: .gnat, clicks: 3, playerCloaked: false), [.encounter], false),
    (.uneventfulTrip, [], false),
    (.arrived(system: 1), [.encounter, .travel], false),
    (.debtWarning(debt: 80_000), [.finance], false),
    (.debtReminder(debt: 2_000), [.finance], false),
    (.reactorWarning(status: 5), [.quest], false),
    (.reactorMeltdown, [.quest], false),
    (.tribblesChanged(from: 1, to: 2), [.quest], false),
    (.tribblesDied(.allFromReactor), [.quest], false),
    (.tribblesAteFood(eaten: 3), [.quest], false),
    (.tribbleInspectorWarning(count: 100), [.quest], false),
    (.passengerConcerned(crewID: 33), [.crew], false),
    (.passengerImpatient(crewID: 33), [.crew], false),
    (.autoFuelFailed, [.ship], false),
    (.autoRepairFailed, [.ship], false),
    (.easterEgg, [.quest], false),
    (.easterEggNoShieldSlot, [.quest], false),
    (.escapePodUsed(insurancePayout: 0), [.encounter, .ship], false),
    (.wildLeftShip, [.quest], false),
    (.singularityLost, [.travel], false),
    (.departureBlocked(.cannotPayMercenaries), [], false),
    (.gemulonInvaded, [.quest], false),
    (.experimentPerformed, [.quest], false),
    (.playerAttacked, [], true),
    (.playerFled, [], true),
    (.artifactRelinquished, [], true),
    (.preciousHidden, [], true),
    (.sculptureTaken, [], true),
    (.blackmailed(10), [], true),
    (.looted(units: 3), [], true),
    (.wildJoinedPirates, [], true),
    (.bribed(100), [], true),
    (.fined(50), [], true),
    (.inspectionClean, [], true),
    (.reactorConfiscated, [.police], true),
    (.yielded, [], true),
    (.tonicConsumed(good: true), [], true),
    (.captainTraining(skill: .pilot), [], true),
    (.plundered(item: t, quantity: 2), [.trade], true),
    (.scooped(t), [.trade], true),
    (.scoopNoRoom, [], true),
    (.arrested(term: 30, fine: 0, shipSold: false), [.encounter, .police], false),
    (.boughtEscapePod(price: 2_000), [.ship], false),
    (.hired(crewID: 4), [.crew], false),
    (.fired(crewID: 4), [.crew], false),
    (.borrowed(amount: 100), [.finance], false),
    (.repaid(amount: 100), [.finance], false),
    (.insuranceBought, [.finance], false),
    (.insuranceStopped, [.finance], false),
    (.optionsChanged, [], false),
    (.orbitTradeCompleted(direction: .traderBuys, item: t, quantity: 1, total: 30), [.trade], true),
    (.specialEventCompleted(.lottery), [.quest], false),
    (.specialEventRefused(.sculptureHiddenBays, reason: .noFreeSlot), [.quest], false),
    (.sealedCanisters(t), [.trade], false),
    (.gameEnded(.retired, score: 10), [.encounter, .game], false),
    (.cheatUsed, [.game], false),
    (.cheatReadout(.remainingVeryRare([])), [], false),
]

@Suite("LOG captain's log")
struct JournalSpecTests {
    // MARK: §1 where the log lives

    @Test("LOG-002 GameJournal holds entries, nextEntryID, intel and the open encounter; Codable, Sendable, Equatable")
    func journalShape() throws {
        let j = journalWithLedger(docked())
        let raw = try #require(JSONSerialization.jsonObject(with: canonical(j)) as? [String: Any])
        #expect(Set(raw.keys) == ["entries", "nextEntryID", "intel", "openEncounter"])
        let decoded = try JSONDecoder().decode(GameJournal.self, from: canonical(j))
        #expect(decoded == j)
        // No floating-point numbers anywhere in the encoding.
        let text = try #require(String(data: canonical(j), encoding: .utf8))
        #expect(text.range(of: #"\d\.\d"#, options: .regularExpression) == nil)
    }

    @Test("LOG-005 start: journalStarted first (day, system), cheatsEnabled for cheated states, intel observes the start")
    func start() throws {
        let s = docked()
        let j = GameJournal.start(state: s)
        let first = try #require(j.entries.first)
        guard case let .journalStarted(info) = first.kind else { Issue.record("not a start entry"); return }
        #expect(first.id == 1 && first.day == s.commander.days && first.system == s.commander.currentSystem && first.worth == s.worth)
        #expect(info.origin == .newGame && info.rulesetID == .windows201 && info.difficulty == s.difficulty)
        #expect(info.systemCount == s.galaxy.systems.count && info.startSystem == s.commander.currentSystem)
        #expect(info.visitedSystems.contains(s.commander.currentSystem) && info.kills == s.commander.kills)
        #expect(j.entries.count == 1 && j.nextEntryID == 2 && j.openEncounter == nil)
        let home = j.intel.systems[s.commander.currentSystem]
        #expect(home.visitCount == 1 && home.lastVisitDay == s.commander.days && home.history.count == 1)
        var cheated = s
        cheated.cheatsUsed = true
        let cj = GameJournal.start(state: cheated)
        #expect(cj.entries.map(\.kind) == [first.kind, .cheatsEnabled] && cj.entries[1].id == 2)
    }

    @Test("LOG-006 bootstrap: origin resumed, every visited system, partial history")
    func bootstrap() throws {
        var g = RecordedGame(.modern, seed: 3)
        g.fuzz(150, seed: 3)
        let s = g.state
        let j = GameJournal.bootstrap(from: s)
        guard case let .journalStarted(info) = j.entries.first?.kind else { Issue.record("no start"); return }
        #expect(info.origin == .resumed)
        #expect(info.visitedSystems == s.galaxy.systems.indices.filter { s.galaxy.systems[$0].visited })
        #expect(CareerStats.fold(j.entries).isPartial)
    }

    // MARK: §2 entries

    @Test("LOG-008 entry ids start at 1, never reused, strictly increasing; day/system/worth from the state after the step")
    func entryStamps() throws {
        var g = RecordedGame(.windows201, seed: 11)
        g.fuzz(300, seed: 11)
        let ids = g.journal.entries.map(\.id)
        #expect(ids.first == 1 && ids == ids.sorted() && Set(ids).count == ids.count && g.journal.nextEntryID == ids.count + 1)
        var h = RecordedGame(.windows201, seed: 11)
        let before = h.state
        h.send(.buyCargo(.water, quantity: 1))
        let entry = try #require(h.journal.entries.last)
        #expect(entry.day == h.state.commander.days && entry.system == h.state.commander.currentSystem && entry.worth == h.state.worth)
        #expect(entry.kind == .trade(TradeEntry(action: .buy, item: .water, quantity: 1,
                                                total: before.commander.cash - h.state.commander.cash)))
    }

    @Test("LOG-009 every LogEntryKind case and payload round-trips through Codable")
    func kindsCodable() throws {
        for (kind, _) in kindFixtures {
            let e = LogEntry(id: 1, day: 2, system: 3, worth: 4, kind: kind, flavor: .generated(text: "Zoë \"/\\"))
            #expect(try JSONDecoder().decode(LogEntry.self, from: JSONEncoder().encode(e)) == e)
        }
        let extra: [LogEntryKind] = [
            .police(.caughtLittering), .police(.reactorConfiscated), .finance(.repaid(amount: 1, remainingDebt: 0)),
            .finance(.insuranceBought), .finance(.insuranceStopped), .finance(.debtWarning(debt: 1)), .finance(.debtReminder(debt: 1)),
            .ship(.boughtShip(.gnat, netPrice: 1)), .ship(.customShipBuilt(.kuat)), .ship(.equipment(.soldShield(.energy), price: 1)),
            .ship(.boughtEscapePod(price: 1)), .ship(.repair(points: 1, cost: 1)), .ship(.autoFuelFailed), .ship(.autoRepairFailed),
            .ship(.escapePodUsed(insurancePayout: 1)), .crew(.fired(crewID: 1)), .crew(.passengerConcerned(crewID: 1)),
            .crew(.passengerImpatient(crewID: 1)), .quest(.refused(.sculptureHiddenBays)), .quest(.tribbles(from: 1, to: 2)),
            .quest(.tribblesDied(.narcotics(converted: 3))), .quest(.tribblesAteFood(eaten: 1)), .quest(.tribbleInspectorWarning(count: 1)),
            .quest(.reactorWarning(status: 1)), .quest(.reactorMeltdown), .quest(.gemulonInvaded), .quest(.experimentPerformed),
            .quest(.wildLeftShip), .quest(.easterEgg(shieldInstalled: false)), .status(.reputation(from: .harmless, to: .poor)),
        ]
        for kind in extra {
            let e = LogEntry(id: 9, day: 1, system: 0, worth: 0, kind: kind)
            #expect(try JSONDecoder().decode(LogEntry.self, from: JSONEncoder().encode(e)) == e)
        }
    }

    @Test("LOG-010 every kind maps to exactly one category")
    func categories() {
        for (kind, category) in kindFixtures { #expect(kind.category == category, "\(kind)") }
        #expect(Set(kindFixtures.map(\.1)) == Set(LogCategory.allCases))
    }

    @Test("LOG-011 flavorSubject is non-nil exactly for arrivals, encounters, completed quests, endings and achievements")
    func flavorSubjects() {
        for (kind, _) in kindFixtures {
            let expected: Bool = switch kind {
            case .arrived, .encounter, .quest(.completed), .gameEnded, .achievementUnlocked: true
            default: false
            }
            #expect((kind.flavorSubject != nil) == expected, "\(kind)")
        }
        #expect(LogEntryKind.quest(.refused(.sculpture)).flavorSubject == nil)
    }

    @Test("LOG-012 engine types inside entries use their engine Codable form")
    func engineCodable() throws {
        let kind = LogEntryKind.news(NewsEntry(headlines: [.externalPressure(template: 1, pressure: .war, system: 4)], cost: 1))
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let data = try enc.encode(kind)
        let headline = try enc.encode(Headline.externalPressure(template: 1, pressure: .war, system: 4))
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains(try #require(String(data: headline, encoding: .utf8))))
    }

    // MARK: §3 recording

    @Test("LOG-013 rejected steps and confirmation requests record nothing; a step records events, intel, unlocks, flavor")
    func recording() throws {
        var g = RecordedGame(.modern, seed: 5)
        let count = g.journal.entries.count
        let snapshot = g.journal
        g.send(.sellCargo(.robots, quantity: 1))  // rejected: none held
        #expect(g.journal == snapshot && g.outputs.last == JournalStepOutput())
        let before = g.state
        let confirm = g.engine.perform(.retire)
        var j = g.journal
        let out = JournalRecorder.record(JournalStep(command: .retire, before: before, result: confirm, after: g.state), into: &j)
        #expect(out == JournalStepOutput() && j.entries.count == count)
        // A profitable sale: trade entry, then the First Profit unlock with template flavor.
        var s = before
        s.commander.ship.cargo[TradeItemType.water.rawValue] = 1
        s.commander.priceCargo[TradeItemType.water.rawValue] = 1
        var h = RecordedGame(s)
        h.send(.sellCargo(.water, quantity: 1))
        let output = try #require(h.outputs.last)
        #expect(output.newEntries.map(\.kind.category) == [.trade, .achievement])
        #expect(output.unlocked == [.firstProfit] && output.newEntries == Array(h.journal.entries.suffix(2)))
        #expect(output.newEntries[1].flavor?.source == .template && output.newEntries[0].flavor == nil)
    }

    @Test("LOG-014 recording is deterministic: the same seed and commands give byte-identical journals (50 games per ruleset)",
          arguments: RulesetID.allCases)
    func determinism(_ ruleset: RulesetID) throws {
        for game in 0..<50 {
            let seed = 900 + UInt64(game)
            var a = RecordedGame(ruleset, seed: seed)
            var b = RecordedGame(ruleset, seed: seed)
            a.fuzz(60, seed: seed)
            b.fuzz(60, seed: seed)
            #expect(try canonical(a.journal) == canonical(b.journal))
        }
    }

    @Test("LOG-015 every GameEvent has a disposition (one fixture per case)")
    func dispositions() throws {
        #expect(eventFixtures.count == 83)
        let labels = Set(eventFixtures.map { String(describing: $0.0).prefix { $0 != "(" } })
        #expect(labels.count == 83)
        let s = docked()
        let enc = inEncounter(s)
        for (event, categories, folds) in eventFixtures {
            var j = journalWithLedger(s)
            let n = j.entries.count
            let before = j.openEncounter?.events.count ?? 0
            let cmd: Command = if case .boughtEquipment = event { .buyGadget(.navigatingSystem) } else { .warp }
            JournalRecorder.record(step([event], command: cmd, before: s, after: enc), into: &j)
            let added = j.entries[n...].filter { $0.kind.category != .achievement }.map(\.kind.category)
            #expect(added == categories, "\(event)")
            if folds { #expect(j.openEncounter?.events.count == before + 1, "\(event)") }
        }
    }

    @Test("LOG-016 reading the newspaper appends the headlines and the price paid")
    func newspaper() throws {
        var g = RecordedGame(.windows201, seed: 21)
        let cash = g.state.commander.cash
        let result = g.send(.readNewspaper)
        guard case let .newspaper(paper)? = result.decision else { Issue.record("no paper: \(result)"); return }
        let news = g.journal.entries.compactMap { if case let .news(n) = $0.kind { n } else { nil } }
        #expect(news == [NewsEntry(headlines: paper.headlines, cost: cash - g.state.commander.cash)])
    }

    @Test("LOG-017 police record and reputation changes append status entries after the event entries")
    func statusChanges() {
        let s = docked()
        var a = s
        a.commander.policeRecordScore = -10
        a.commander.reputationScore = 50
        var j = GameJournal.start(state: s)
        JournalRecorder.record(step([.caughtLittering(newRecord: -10)], command: .warp, before: s, after: a), into: &j)
        #expect(j.entries.dropFirst().map(\.kind) == [
            .police(.caughtLittering), .status(.policeRecord(from: .clean, to: .crook)),
            .status(.reputation(from: .harmless, to: .average)),
        ])
    }

    @Test("LOG-018 arrivals: firstVisit from the state before, encounterCount since the departure, uneventful folded in")
    func arrivals() throws {
        let s = docked()
        let to = (s.commander.currentSystem + 1) % s.galaxy.systems.count
        var j = GameJournal.start(state: s)
        var a = s
        a.commander.currentSystem = to
        JournalRecorder.record(step([.departed(from: s.commander.currentSystem, to: to, viaWormhole: true),
                                     .encounterStarted(type: .traderIgnore, opponent: .gnat, clicks: 2, playerCloaked: false)],
                                    before: s, after: inEncounter(s)), into: &j)
        JournalRecorder.record(step([.arrived(system: to)], command: .encounter(.ignore), before: inEncounter(s), after: a), into: &j)
        let arrival = try #require(j.entries.compactMap { if case let .arrived(x) = $0.kind { x } else { nil } }.first)
        #expect(arrival == TripArrival(system: to, from: s.commander.currentSystem, viaWormhole: true,
                                       firstVisit: !s.galaxy.systems[to].visited, uneventful: false, encounterCount: 1))
        guard case let .departed(_, _, _, parsecs)? = j.entries.first(where: { $0.kind.category == .travel })?.kind else { return }
        #expect(parsecs == 0)
        var k = GameJournal.start(state: s)
        JournalRecorder.record(step([.departed(from: s.commander.currentSystem, to: to, viaWormhole: false), .uneventfulTrip,
                                     .arrived(system: to)], before: s, after: a), into: &k)
        let quiet = try #require(k.entries.compactMap { if case let .arrived(x) = $0.kind { x } else { nil } }.first)
        #expect(quiet.uneventful && quiet.encounterCount == 0 && !quiet.viaWormhole)
        let d = GalaxyGenerator.distance(s.galaxy.systems[s.commander.currentSystem], s.galaxy.systems[to], rule: s.ruleset.flags.distance)
        #expect(k.entries.contains { $0.kind == .departed(from: s.commander.currentSystem, to: to, viaWormhole: false, parsecs: d) })
    }

    // MARK: §4 encounter ledger

    @Test("LOG-019 the ledger opens, counts rounds and the lowest hull, records surrender, closes with a record")
    func ledger() throws {
        let s = docked()
        let e = inEncounter(s)
        var j = journalWithLedger(s)
        let ledger = try #require(j.openEncounter)
        #expect(ledger.type == .pirateAttack && ledger.clicks == 5 && ledger.playerHullStrength == s.commander.ship.hullStrength(s.ruleset))
        let strength = ledger.playerHullStrength
        JournalRecorder.record(step([.combatRound(round: 1, playerHit: true, opponentHit: true, playerHull: strength / 2,
                                                  opponentHull: 5),
                                     .combatRound(round: 2, playerHit: true, opponentHit: true, playerHull: strength / 4, opponentHull: 5)],
                                    command: .encounter(.attack), before: e, after: e), into: &j)
        #expect(j.openEncounter?.rounds == 2 && j.openEncounter?.minPlayerHull == strength / 4)
        // A game saved mid-encounter resumes the same ledger.
        let resumed = try JSONDecoder().decode(GameJournal.self, from: canonical(j))
        #expect(resumed.openEncounter == j.openEncounter)
        var after = s
        after.commander.kills.pirates = 3
        JournalRecorder.record(step([.looted(units: 2)], command: .encounter(.surrender), before: e, after: after), into: &j)
        #expect(j.openEncounter == nil)
        guard case let .encounter(r)? = j.entries.last?.kind else { Issue.record("no record"); return }
        #expect(r.rounds == 2 && r.minHullPercent == (strength / 4) * 100 / strength && r.killsAfter.pirates == 3)
        #expect(r.surrendered && r.outcome == .raided(units: 2) && r.result == .surrendered)
    }

    @Test("LOG-020 the outcome follows the UI-ENC-052 precedence, one fixture per case")
    func outcomes() {
        let cases: [([GameEvent], EncounterOutcomeKind)] = [
            ([.opponentDestroyed(.wasp), .escapePodUsed(insurancePayout: 0)], .escapePod),
            ([.opponentDestroyed(.wasp), .bothDestroyed], .killed),
            ([.playerDestroyed], .killed),
            ([.fined(5), .arrested(term: 1, fine: 1, shipSold: false)], .arrested),
            ([.opponentDestroyed(.wasp), .bountyPaid(10)], .destroyed(.wasp)),
            ([.opponentDisabled(.gnat), .plundered(item: .ore, quantity: 1)], .plundered),
            ([.opponentDisabled(.gnat)], .disabled),
            ([.playerEscaped(wasHit: true)], .escaped),
            ([.opponentEscaped], .opponentEscaped),
            ([.orbitTradeCompleted(direction: .traderSells, item: .ore, quantity: 1, total: 5)], .traded),
            ([.bribed(9)], .bribed(9)),
            ([.fined(8)], .fined(8)),
            ([.inspectionClean], .inspectedClean),
            ([.yielded], .yielded),
            ([.reactorConfiscated], .yielded),
            ([.looted(units: 3), .blackmailed(5)], .raided(units: 3)),
            ([.wildJoinedPirates], .raided(units: 0)),
            ([.artifactRelinquished], .artifactSurrendered),
            ([.tonicConsumed(good: false)], .drank(good: false)),
            ([.captainTraining(skill: .fighter)], .trained(.fighter)),
            ([.encounterChanged(.pirateIgnore)], .passed),
        ]
        for (events, expected) in cases { #expect(EncounterLedger.outcome(of: events) == expected, "\(events)") }
    }

    @Test("LOG-021 result classes: won, fled, surrendered, lost, other")
    func resultClasses() {
        #expect(record(.destroyed(.gnat)).result == .won && record(.disabled).result == .won)
        #expect(record(.escaped).result == .fled)
        #expect(record(.raided(units: 1)).result == .surrendered && record(.artifactSurrendered).result == .surrendered)
        #expect(record(.arrested, surrendered: true).result == .surrendered && record(.passed, surrendered: true).result == .surrendered)
        #expect(record(.killed).result == .lost && record(.escapePod).result == .lost && record(.arrested).result == .lost)
        #expect(record(.passed).result == .other && record(.bribed(3)).result == .other)
    }

    // MARK: §5 reading

    @Test("LOG-022 groups by consecutive day and system, newest first; category filter and text predicate")
    func groups() {
        var b = EntryBuilder(start: EntryBuilder.start())
        b.add(.trade(TradeEntry(action: .buy, item: .ore, quantity: 1, total: 5)))
        b.add(.departed(from: 0, to: 2, viaWormhole: false, parsecs: 3), day: 1)
        b.add(.arrived(TripArrival(system: 2, from: 0, viaWormhole: false, firstVisit: true, uneventful: true, encounterCount: 0)),
              system: 2)
        b.add(.trade(TradeEntry(action: .sell, item: .ore, quantity: 1, total: 9, profit: 4)))
        let groups = LogQuery.groups(b.entries)
        #expect(groups.map { [$0.day, $0.system] } == [[1, 2], [1, 0], [0, 0]])
        #expect(groups[0].entries.map(\.id) == [5, 4] && groups[2].entries.map(\.id) == [2, 1] && groups[2].id == 1)
        let trades = LogQuery.groups(b.entries, filter: LogFilter([.trade]))
        #expect(trades.flatMap(\.entries).map(\.id) == [5, 2])
        #expect(LogQuery.groups(b.entries, matching: { $0.id == 3 }).flatMap(\.entries).map(\.id) == [3])
        var f = LogFilter()
        #expect(f.isEmpty && f.includes(b.entries[0]))
        f.toggle(.travel)
        f.toggle(.trade)
        #expect(f.categories == [.trade, .travel])
        f.toggle(.trade)
        #expect(f == LogFilter([.travel]))
    }

    @Test("LOG-024 Markdown export: title, metadata, oldest-first day groups, bullets, italic flavor, escaping, one newline")
    func markdown() {
        var b = EntryBuilder(start: EntryBuilder.start())
        b.add(.trade(TradeEntry(action: .buy, item: .ore, quantity: 1, total: 5)))
        b.add(.arrived(TripArrival(system: 2, from: 0, viaWormhole: false, firstVisit: true, uneventful: true, encounterCount: 0)),
              day: 3, system: 2)
        let journal = GameJournal(entries: b.entries, nextEntryID: 4, intel: IntelBook(systemCount: 3))
        let header = LogMarkdownHeader(title: "Zoë's *Log*", metadata: ["Zoë", "Modern", "Normal", "W-1234"]) { "Day \($0) · S\($1)" }
        let md = LogMarkdown.render(journal: journal, header: header, text: { "Entry #\($0.id) [x]_y_" },
                                    flavor: { $0.id == 3 ? "Quiet `stars` <3" : nil })
        let expected = """
        # Zoë's \\*Log\\*
        Zoë · Modern · Normal · W-1234

        ## Day 0 · S0

        - Entry \\#1 \\[x\\]\\_y\\_
        - Entry \\#2 \\[x\\]\\_y\\_

        ## Day 3 · S2

        - Entry \\#3 \\[x\\]\\_y\\_
          *Quiet \\`stars\\` \\<3*

        """
        #expect(md == expected)
        #expect(header == LogMarkdownHeader(title: "Zoë's *Log*", metadata: ["Zoë", "Modern", "Normal", "W-1234"]) { _, _ in "" })
        let trades = LogMarkdown.render(journal: journal, header: header, filter: LogFilter([.travel]), text: { _ in "t" }, flavor: { _ in nil })
        #expect(trades == "# Zoë's \\*Log\\*\nZoë · Modern · Normal · W-1234\n\n## Day 3 · S2\n\n- t\n")
    }

    // MARK: §8 fuzzing

    @Test("LOG-037 journal invariants over fuzz games: ids, days, systems, visited systems, rejected steps",
          arguments: RulesetID.allCases)
    func fuzzInvariants(_ ruleset: RulesetID) throws {
        for game in 0..<12 {
            var g = RecordedGame(ruleset, seed: 4_000 + UInt64(game), difficulty: Difficulty(rawValue: game % 5) ?? .normal)
            var r = Xoshiro256StarStar(seed: UInt64(game) &+ 77)
            for _ in 0..<250 {
                if case .gameOver = g.state.phase { break }
                let count = g.journal.entries.count
                let result = g.send(InsightsFuzz.pickCommand(g.state, &r))
                if result.rejection != nil { #expect(g.journal.entries.count == count) }
            }
            let entries = g.journal.entries
            #expect(zip(entries, entries.dropFirst()).allSatisfy { $0.id < $1.id && $0.day <= $1.day })
            #expect(entries.allSatisfy { g.state.galaxy.systems.indices.contains($0.system) })
            var visited = Set(entries.compactMap { if case let .arrived(a) = $0.kind { a.system } else { nil } })
            if case let .journalStarted(start) = entries[0].kind { visited.formUnion(start.visitedSystems) }
            let truth = Set(g.state.galaxy.systems.indices.filter { g.state.galaxy.systems[$0].visited })
            #expect(visited == truth, "game \(game)")
            // Arrivals count the encounters since their departure.
            var since = 0
            for e in entries {
                switch e.kind {
                case .departed: since = 0
                case .encounter: since += 1
                case let .arrived(a):
                    #expect(a.encounterCount == since)
                    since = 0
                default: break
                }
            }
        }
    }
}
