// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import Testing
@testable import ParsecMerchant

/// Fixture states and steps for the arrival report (UI-ENC §8).
@MainActor
enum ArrivalFixtures {
    static let base: GameState = {
        var s = GameState(config: NewGameConfig(commanderName: "Arrival", seed: 5))
        s.commander.cash = 10_000
        return s
    }()

    static var destination: Int { base.destinations.first ?? 1 }

    static func encounter(_ clicks: Int, type: EncounterType = .pirateAttack, ship: ShipType = .gnat) -> GameState {
        var s = base
        s.phase = .encounter(EncounterState(type: type, opponent: Ship(type: ship, spec: s.ruleset.tables.ship(ship)), clicks: clicks))
        return s
    }

    static func docked(at system: Int, cash: Int = 10_000) -> GameState {
        var s = base
        s.commander.currentSystem = system
        s.commander.cash = cash
        return s
    }

    static func step(_ command: Command, _ before: GameState, _ after: GameState, _ events: [GameEvent]) -> StepRecord {
        StepRecord(command: command, acknowledged: [], before: before, result: StepResult(events: events), after: after)
    }

    static func departed() -> GameEvent { .departed(from: base.commander.currentSystem, to: destination, viaWormhole: false) }

    /// One step that departs and arrives without encounters.
    static func uneventfulTrip(extra: [GameEvent] = [], after: GameState? = nil) -> StepRecord {
        step(.warp, base, after ?? docked(at: destination, cash: 9_900),
             [departed(), .uneventfulTrip] + extra + [.arrived(system: destination)])
    }

    /// Folds `steps` and returns the finished trip.
    static func trip(_ steps: [StepRecord]) -> Trip? {
        var acc = TripAccumulator()
        var finished: Trip?
        for s in steps { finished = acc.fold(s, log: ["R1 log"]) ?? finished }
        return finished
    }
}

@MainActor
@Suite("Arrival report and event feed (UI-ENC §8–9)")
struct ArrivalFeedTests {
    // MARK: UI-ENC-051

    @Test("UI-ENC-051 departure costs are the warp preview of the state before the departing step")
    func departureCosts() throws {
        var before = ArrivalFixtures.base
        before.commander.debt = 5_000
        before.warpSystem = ArrivalFixtures.destination
        let costs = DepartureCosts.make(command: .warp, before: before)
        #expect(costs == before.warpTargetPreview(before.warpSystem).costs)
        #expect(costs.interest > 0 && costs.total == costs.interest + costs.mercenaries + costs.insurance + costs.wormholeTax)
        #expect(DepartureCosts.make(command: .jump, before: before) == before.dailyCosts(to: before.jumpPreview.destination))
        // A real warp: the trip keeps the costs captured before sending.
        let s = try TestSessions.playing()
        try TestSessions.edit(s) { $0.commander.debt = 2_000 }
        s.send(.selectNextTarget(forward: true))
        let snapshot = try #require(s.state)
        s.send(.warp)
        if let card = s.arrivalCard {
            let expected = ArrivalText.cost(.interest, snapshot.warpTargetPreview(snapshot.warpSystem).costs.interest)
            #expect(card.section(.costs)?.lines.contains(expected) == true)
        } else {
            #expect(s.tripAccumulator.trip?.departureCosts == snapshot.warpTargetPreview(snapshot.warpSystem).costs)
        }
    }

    // MARK: UI-ENC-052

    @Test("UI-ENC-052 EncounterOutcome.derive: one fixture event sequence per case")
    func outcomes() {
        let cases: [([GameEvent], EncounterOutcome)] = [
            ([.combatRound(round: 1, playerHit: false, opponentHit: true, playerHull: 100, opponentHull: 0), .opponentDestroyed(.gnat),
              .bountyPaid(250)], .destroyed(.gnat, bounty: 250)),
            ([.opponentDestroyed(.flea)], .destroyed(.flea, bounty: nil)),
            ([.opponentDisabled(.gnat)], .disabled),
            ([.playerFled, .playerEscaped(wasHit: true)], .escaped(wasHit: true)),
            ([.opponentEscaped], .opponentEscaped),
            ([.opponentDisabled(.gnat), .plundered(item: .furs, quantity: 3), .plundered(item: .furs, quantity: 1)], .plundered([.furs: 4])),
            ([.orbitTradeCompleted(direction: .traderSells, item: .ore, quantity: 5, total: 2_500)],
             .traded(direction: .traderSells, item: .ore, quantity: 5, total: 2_500)),
            ([.bribed(400)], .bribed(400)),
            ([.fined(900)], .fined(900)),
            ([.inspectionClean], .inspectedClean),
            ([.yielded], .yielded),
            ([.arrested(term: 30, fine: 500, shipSold: false)], .arrested),
            ([.looted(units: 6)], .raided(units: 6)),
            ([.blackmailed(300)], .raided(units: 0)),
            ([.artifactRelinquished], .artifactSurrendered),
            ([.tonicConsumed(good: true)], .drank(good: true)),
            ([.captainTraining(skill: .pilot)], .trained(.pilot)),
            ([.combatRound(round: 3, playerHit: true, opponentHit: false, playerHull: 0, opponentHull: 40), .escapePodUsed(insurancePayout: 0)],
             .escapePod),
            ([.playerDestroyed], .killed),
            ([.bothDestroyed], .killed),
            ([], .passed),
        ]
        for (events, expected) in cases {
            #expect(EncounterOutcome.derive(events: events, endedBy: .encounter(.attack)) == expected, "\(events)")
        }
        #expect(!ArrivalText.outcome(.destroyed(.gnat, bounty: 250)).isEmpty)
    }

    // MARK: UI-ENC-053

    @Test("UI-ENC-053 TripAccumulator folds an uneventful trip, two encounters, an arrest, a pod and a killed trip")
    func tripFold() throws {
        typealias Fx = ArrivalFixtures
        // Uneventful.
        let quiet = try #require(Fx.trip([Fx.uneventfulTrip()]))
        #expect(quiet.encounters.isEmpty && quiet.end == .arrived(system: Fx.destination))
        #expect(quiet.departureCosts == DepartureCosts.make(command: .warp, before: Fx.base))
        #expect(quiet.events.contains(.uneventfulTrip) && quiet.before == Fx.base)

        // Two encounters in one trip, each with its own outcome and frozen log.
        let e1 = Fx.encounter(14), e2 = Fx.encounter(5, type: .policeInspect, ship: .firefly)
        let steps = [
            Fx.step(.warp, Fx.base, e1, [Fx.departed(), .encounterStarted(type: .pirateAttack, opponent: .gnat, clicks: 14, playerCloaked: false)]),
            Fx.step(.encounter(.attack), e1, e1, [.combatRound(round: 1, playerHit: false, opponentHit: true, playerHull: 100, opponentHull: 10)]),
            Fx.step(.encounter(.attack), e1, e2, [.combatRound(round: 2, playerHit: false, opponentHit: true, playerHull: 100, opponentHull: 0),
                                                  .opponentDestroyed(.gnat),
                                                  .encounterStarted(type: .policeInspect, opponent: .firefly, clicks: 5, playerCloaked: false)]),
            Fx.step(.encounter(.submit), e2, Fx.docked(at: Fx.destination), [.inspectionClean, .boughtFuel(units: 2, cost: 8),
                                                                           .arrived(system: Fx.destination)]),
        ]
        var acc = TripAccumulator()
        for s in steps.dropLast() { #expect(acc.fold(s, log: ["R"]) == nil) }
        #expect(acc.isTripInProgress)
        let finished = acc.fold(steps[3], log: [])
        let two = try #require(finished)
        #expect(!acc.isTripInProgress)
        #expect(two.encounters.map(\.outcome) == [.destroyed(.gnat, bounty: nil), .inspectedClean])
        #expect(two.encounters.map(\.clicks) == [14, 5] && two.encounters.map(\.badge) == [.pirate, .police])
        #expect(two.encounters[0].log == ["R", "R", "R"] && two.encounters[1].log.isEmpty)
        #expect(two.events.contains(.boughtFuel(units: 2, cost: 8)) && !two.events.contains(.inspectionClean))

        // Arrest, pod and a killed trip.
        let arrest = try #require(Fx.trip([
            Fx.step(.warp, Fx.base, Fx.encounter(9, type: .policeAttack), [Fx.departed(),
                .encounterStarted(type: .policeAttack, opponent: .gnat, clicks: 9, playerCloaked: false)]),
            Fx.step(.encounter(.surrender), Fx.encounter(9, type: .policeAttack), Fx.docked(at: Fx.destination),
                   [.arrested(term: 30, fine: 500, shipSold: false), .arrived(system: Fx.destination)]),
        ]))
        #expect(arrest.encounters.map(\.outcome) == [.arrested])
        let pod = try #require(Fx.trip([
            Fx.step(.warp, Fx.base, Fx.encounter(3), [Fx.departed(), .encounterStarted(type: .pirateAttack, opponent: .gnat, clicks: 3, playerCloaked: false)]),
            Fx.step(.encounter(.attack), Fx.encounter(3), Fx.docked(at: Fx.destination),
                   [.escapePodUsed(insurancePayout: 0), .arrived(system: Fx.destination)]),
        ]))
        #expect(pod.encounters.map(\.outcome) == [.escapePod])
        var dead = Fx.base
        dead.phase = .gameOver(.killed)
        let killed = try #require(Fx.trip([
            Fx.step(.warp, Fx.base, Fx.encounter(3), [Fx.departed(), .encounterStarted(type: .pirateAttack, opponent: .gnat, clicks: 3, playerCloaked: false)]),
            Fx.step(.encounter(.attack), Fx.encounter(3), dead, [.playerDestroyed, .gameEnded(.killed, score: 10)]),
        ]))
        #expect(killed.end == .gameOver && killed.encounters.map(\.outcome) == [.killed])
        // Steps outside a trip are ignored.
        var idle = TripAccumulator()
        #expect(idle.fold(Fx.step(.buyFuel(credits: 5), Fx.base, Fx.base, [.boughtFuel(units: 1, cost: 5)])) == nil)
        #expect(!idle.isTripInProgress)
    }

    // MARK: UI-ENC-054

    @Test("UI-ENC-054 ArrivalReport.make: sections in UX order, empty ones omitted, each event in its section")
    func reportSections() throws {
        typealias Fx = ArrivalFixtures
        var before = Fx.base
        before.commander.debt = 4_000
        before.warpSystem = Fx.destination
        var after = Fx.docked(at: Fx.destination, cash: 9_000)
        after.commander.debt = 4_000
        after.commander.policeRecordScore = -40
        let extra: [GameEvent] = [.reactorWarning(status: 2), .tribblesChanged(from: 10, to: 20), .debtReminder(debt: 4_000),
                                  .repairedHull(points: 3, cost: 30), .caughtLittering(newRecord: -40), .passengerImpatient(crewID: CrewID.wild),
                                  .easterEgg]
        let step = Fx.step(.warp, before, after, [Fx.departed(), .fabricRip(newDestination: Fx.destination), .uneventfulTrip] + extra
                          + [.arrived(system: Fx.destination)])
        let trip = try #require(Fx.trip([step]))
        let r = ArrivalReport.make(trip: trip, after: after)
        #expect(r.sections.map(\.kind) == [.encounters, .news, .costs, .service, .tribbles, .reactor, .debt, .police, .quests])
        let order = ArrivalSectionKind.allCases
        #expect(r.sections.compactMap(\.kind) == order.filter { k in r.sections.contains { $0.kind == k } })
        #expect(r.fabricRip == ArrivalText.fabricRip(Names.system(Fx.destination, in: after)))
        #expect(r.section(.encounters)?.lines == [ArrivalText.uneventfulTrip])
        #expect(r.section(.reactor)?.lines.first?.hasPrefix("You notice the Ion Reactor") == true)
        #expect(r.section(.service)?.lines.count == 1 && r.section(.tribbles)?.lines.count == 1 && r.section(.debt)?.lines.count == 1)
        #expect(r.section(.police)?.lines.first?.hasPrefix("Police record:") == true)
        #expect(r.section(.quests)?.lines.contains { $0.hasPrefix("Ship's comm — ") } == true)
        #expect(r.section(.costs)?.lines.last == ArrivalText.cost(.total, trip.departureCosts.total))
        #expect(r.cashChange == -1_000 && r.summary.contains("Arrived at"))
        // A quiet trip omits everything but encounters, news and (non-zero) costs.
        let quiet = ArrivalReport.make(trip: try #require(Fx.trip([Fx.uneventfulTrip()])), after: Fx.docked(at: Fx.destination))
        #expect(Set(quiet.sections.compactMap(\.kind)).isSubset(of: [.encounters, .news, .costs]))
        // The quest list difference names added and closed quests.
        var questBefore = Fx.base
        questBefore.quests.japori = QuestStatus.Japori.inTransit
        let diff = QuestLogDiff.lines(before: questBefore, after: Fx.base)
        #expect(diff == [ArrivalText.questRemoved(QuestText.string(for: .japoriDeliver, state: questBefore))])
        #expect(QuestLogDiff.family(.gemulonInformDays(3)) == QuestLogDiff.family(.gemulonInformTomorrow))
    }

    // MARK: UI-ENC-055, -057, -061

    @Test("""
        UI-ENC-055 UI-ENC-061 the arrival card appears after the playback, never changes the section, has a status chip \
        off Bridge, and goes on Dismiss or the next departure
        """)
    func arrivalCardSession() throws {
        var found: GameSession?
        for seed in UInt64(1)...80 where found == nil {
            let s = try TransitFixtures.session(seed: seed)
            s.selectedSection = .bank
            s.send(.selectNextTarget(forward: true))
            s.send(.warp)
            if s.state?.phase == .docked, s.transitPlayback != nil, s.presentation == nil { found = s }
        }
        let s = try #require(found)
        // UI-ENC-061: nothing appears while the playback runs.
        #expect(s.arrivalCard == nil)
        TransitFixtures.play(s)
        let card = try #require(s.arrivalCard)
        #expect(card.summary.hasPrefix("Arrived at") && card.section(.encounters) != nil && card.section(.news) != nil)
        // UI-NAV-004: a trip always ends on the Bridge, where the card is. Dismiss clears the card.
        #expect(s.selectedSection == .bridge)
        #expect(s.arrivalCard != nil && !s.isInputLocked)
        s.dismissArrivalCard()
        #expect(s.arrivalCard == nil)
        let ids = [AXID.Arrival.card, AXID.Arrival.toggle, AXID.Arrival.dismiss, AXID.Arrival.encounter(0)]
            + ArrivalSectionKind.allCases.map(AXID.Arrival.section)
        #expect(ids.allSatisfy(AXID.all.contains))
        // The next departure clears a card that was not dismissed.
        let quick = try TestSessions.playing()
        quick.send(.selectNextTarget(forward: true))
        quick.send(.warp)
        if quick.state?.phase == .docked {
            #expect(quick.arrivalCard != nil)
            quick.consumeArrival(ArrivalFixtures.step(.warp, ArrivalFixtures.base, ArrivalFixtures.encounter(5), [ArrivalFixtures.departed()]))
            #expect(quick.arrivalCard == nil)
        }
    }

    @Test("UI-ENC-056 ArrivalPresentation.decide: critical events and the Sheet style give a report sheet, a game end the card")
    func decide() throws {
        typealias Fx = ArrivalFixtures
        let quiet = try #require(Fx.trip([Fx.uneventfulTrip()]))
        guard case .card = ArrivalPresentation.decide(trip: quiet, style: .card) else { Issue.record("card"); return }
        guard case .sheet(.arrival) = ArrivalPresentation.decide(trip: quiet, style: .sheet) else { Issue.record("sheet style"); return }
        func trip(_ events: [GameEvent], end: GameState? = nil) throws -> Trip {
            let tail: [GameEvent] = end == nil ? [.arrived(system: Fx.destination)] : [.gameEnded(.killed, score: 1)]
            let finished = Fx.trip([Fx.step(.warp, Fx.base, end ?? Fx.docked(at: Fx.destination), [Fx.departed()] + events + tail)])
            return try #require(finished)
        }
        let kinds: [(Trip, ReportSheet.Kind)] = [
            (try trip([.arrested(term: 30, fine: 500, shipSold: false)]), .arrest),
            (try trip([.escapePodUsed(insurancePayout: 5_000)]), .escapePod),
            (try trip([.reactorMeltdown, .escapePodUsed(insurancePayout: 0)]), .reactorMeltdown),
            (try trip([.reactorWarning(status: ReactorStatus.temperatureWarning)]), .arrival),
        ]
        for (t, kind) in kinds {
            guard case let .sheet(sheet) = ArrivalPresentation.decide(trip: t, style: .card) else {
                Issue.record("\(kind) is a sheet")
                continue
            }
            #expect(sheet.kind == kind && sheet.arrival != nil)
        }
        if case let .sheet(.arrival(r)) = ArrivalPresentation.decide(trip: try trip([.reactorWarning(status: 18)]), style: .card) {
            #expect(r.sections.first?.kind == .reactor)
        }
        var dead = Fx.base
        dead.phase = .gameOver(.killed)
        #expect(ArrivalPresentation.decide(trip: try trip([.reactorMeltdown], end: dead), style: .card) == .gameOver)
    }

    @Test("UI-ENC-057 UI-ENC-058 a critical trip shows the report sheet (critical sections first); Continue dismisses it")
    func reportSheetSession() throws {
        let s = try TestSessions.playing()
        try TestSessions.edit(s) { $0.warpSystem = $0.destinations.first ?? 1 }
        let before = try #require(s.state)
        var after = before
        after.commander.currentSystem = before.warpSystem
        let step = ArrivalFixtures.step(.warp, before, after, [.departed(from: before.commander.currentSystem, to: before.warpSystem, viaWormhole: false),
                                                               .arrested(term: 30, fine: 500, shipSold: true), .arrived(system: before.warpSystem)])
        s.consumeArrival(step)
        s.showPendingArrival()
        guard case let .sheet(.report(sheet)) = s.presentation else {
            Issue.record("the arrest opens the report sheet")
            return
        }
        #expect(sheet.kind == .arrest)
        #expect(sheet.criticalSections.first?.title == "Arrested" && sheet.criticalSections.map(\.title).contains("Ship Sold"))
        #expect(sheet.arrival?.sections.first?.kind == .encounters)
        #expect(s.arrivalCard == nil)
        s.dismissPresentation()
        #expect(s.presentation == nil && s.arrivalCard == nil)
        #expect(ReportSheet.Kind.allCases.map(\.rawValue) == ["arrival", "arrest", "escapePod", "reactorMeltdown"])
        #expect([AXID.Report.sheet, AXID.Report.continueButton].allSatisfy(AXID.all.contains))
        for kind in ReportSheet.Kind.allCases { #expect(!String(localized: ReportSheetText.title(kind)).isEmpty) }
    }

    // MARK: UI-ENC-059, -060

    @Test("UI-ENC-059 ArrestReport: one section per arrest-sequence row that applies, in C# order")
    func arrestReport() {
        var before = ArrivalFixtures.base
        before.commander.ship.gadgets = [.hiddenCargoBays]
        before.quests.reactor = QuestStatus.Reactor.fuelOK
        before.quests.sculpture = QuestStatus.Sculpture.inTransit
        before.quests.japori = QuestStatus.Japori.inTransit
        before.commander.ship.crew = [CrewID.commander, 5, CrewID.jarek, CrewID.princess, CrewID.wild]
        before.commander.ship.cargo[TradeItemType.narcotics.rawValue] = 4
        before.commander.insurance = true
        before.commander.ship.tribbles = 50
        var after = ArrivalFixtures.base
        after.quests.japori = QuestStatus.Japori.done
        after.commander.ship.crew = [CrewID.commander]
        let alerts = ArrestReport.alerts(before: before, after: after, events: [.arrested(term: 40, fine: 5_000, shipSold: true)])
        #expect(alerts == [.arrested, .convicted(term: 40, fine: 5_000), .hiddenCompartmentsRemoved, .reactorConfiscated,
                           .sculptureConfiscated, .wildArrested, .illegalGoodsImpounded, .insuranceLost, .mercenariesLeave,
                           .jarekTakenHome, .princessTakenHome, .antidoteTaken, .shipSold, .tribblesRemoved, .fleaBuilt])
        let report = ArrestReport.make(before: before, after: after, events: [.arrested(term: 40, fine: 5_000, shipSold: true)])
        #expect(report.sections[1].lines == ["You are convicted to 40 days in prison and a fine of 5,000 credits."])
        // Only the conviction when nothing else applies.
        #expect(ArrestReport.alerts(before: ArrivalFixtures.base, after: ArrivalFixtures.base,
                                    events: [.arrested(term: 30, fine: 500, shipSold: false)]) == [.arrested, .convicted(term: 30, fine: 500)])
        #expect(ArrestReport.alerts(before: ArrivalFixtures.base, after: ArrivalFixtures.base, events: []).isEmpty)
    }

    @Test("UI-ENC-060 EscapePodReport and ReactorReport: pod, payoff, Flea and the losses from the state difference")
    func podAndReactorReports() {
        var before = ArrivalFixtures.base
        before.quests.sculpture = QuestStatus.Sculpture.inTransit
        before.quests.reactor = QuestStatus.Reactor.fuelOK
        before.quests.japori = QuestStatus.Japori.inTransit
        before.quests.artifact = QuestStatus.Artifact.onBoard
        before.commander.ship.crew = [CrewID.commander, CrewID.jarek, CrewID.princess, CrewID.wild]
        before.commander.ship.tribbles = 9
        var after = ArrivalFixtures.base
        after.quests.sculpture = QuestStatus.Sculpture.inTransit
        after.quests.artifact = QuestStatus.Artifact.done
        let events: [GameEvent] = [.escapePodUsed(insurancePayout: 7_000)]
        let alerts = EscapePodReport.alerts(before: before, after: after, events: events)
        #expect(alerts.first == .escapePodActivated && alerts.last == .fleaBuilt)
        #expect(alerts.contains(.sculptureSaved) && alerts.contains(.reactorDestroyed) && alerts.contains(.tribblesKilled))
        #expect(alerts.contains(.artifactLost) && alerts.contains(.jarekTakenHome) && alerts.contains(.princessTakenHome))
        #expect(alerts.contains(.wildArrested) && alerts.contains(.insurancePayoff(7_000)))
        #expect(alerts.contains { if case .antidoteDestroyed = $0 { true } else { false } })
        #expect(!EscapePodReport.alerts(before: ArrivalFixtures.base, after: ArrivalFixtures.base,
                                        events: [.escapePodUsed(insurancePayout: 0)]).contains(.insurancePayoff(0)))
        // Meltdown: the meltdown first, then the pod (without a second reactor line), or the destroyed ship.
        let melt = ReactorReport.alerts(before: before, after: after, events: [.reactorMeltdown] + events)
        #expect(melt.first == .reactorMeltdown && melt[1] == .escapePodActivated && !melt.contains(.reactorDestroyed))
        #expect(ReactorReport.alerts(before: before, after: after, events: [.reactorMeltdown]) == [.reactorMeltdown, .shipDestroyed])
        #expect(ReportText.section(.reactorMeltdown).title == "Reactor Meltdown!")
    }

    // MARK: UI-ENC-062, -063

    @Test("UI-ENC-062 newspaper auto-show after an arrival and on a new game; not in Palm")
    func newsAutoShow() throws {
        var shown = false
        for seed in UInt64(1)...60 where !shown {
            let s = try TestSessions.playing(seed: seed)
            try TestSessions.edit(s) { $0.options.newsAutoShow = true }
            s.send(.selectNextTarget(forward: true))
            s.send(.warp)
            guard s.state?.phase == .docked, s.arrivalCard != nil else { continue }
            // Auto-pay is off: the buyNewspaper confirmation is the offer.
            guard case let .confirmation(pending) = s.presentation else {
                Issue.record("the paper is offered after the arrival card")
                return
            }
            #expect(pending.confirmation.warning == .buyNewspaper)
            s.confirm(pending)
            guard case .sheet(.newspaper) = s.presentation else {
                Issue.record("the paid paper opens the newspaper sheet")
                return
            }
            shown = true
        }
        #expect(shown)
        // A new game with auto-show and auto-pay opens the paper at once.
        let s = try TestSessions.make()
        var config = s.quickStartConfig()
        var options = config.options ?? GameOptions()
        options.newsAutoShow = true
        options.newsAutoPay = true
        config.options = options
        s.startNewGame(config)
        guard case .sheet(.newspaper) = s.presentation else {
            Issue.record("a new game shows the paper")
            return
        }
        // Palm has no auto-show (NEWS-013).
        var palm = ArrivalFixtures.base
        palm.options.newsAutoShow = true
        #expect(GameSession.newsAutoShows(palm))
        let palmState = GameState(config: NewGameConfig(commanderName: "P", ruleset: .palm122, seed: 2))
        var p = palmState
        p.options.newsAutoShow = true
        #expect(!GameSession.newsAutoShows(p))
    }

    @Test("UI-ENC-063 the news teaser shows the price until the paper is paid, then its first headline")
    func newsTeaser() throws {
        var s = ArrivalFixtures.base
        s.paidForNewspaper = false
        let unpaid = NewsTeaser.make(state: s)
        #expect(unpaid.headline == nil && unpaid.text == "The local paper costs \(s.newspaperCost) cr.")
        s.paidForNewspaper = true
        let paid = NewsTeaser.make(state: s)
        let first = try #require(s.newspaper.headlines.first)
        #expect(paid.headline == NewspaperText.headline(first, state: s) && paid.text == paid.headline)
        #expect([AXID.Arrival.news, AXID.Arrival.newsRead].allSatisfy(AXID.all.contains))
    }

    // MARK: UI-ENC-064 … 067

    @Test("UI-ENC-064 FeedStyle.classify: every event and note; critical is exactly the ALR critical set")
    func feedClassify() throws {
        for kind in GameEventKind.allCases {
            let style = FeedStyle.classify(.event(kind.fixture))
            #expect(!style.symbol.isEmpty && FeedCategory.allCases.contains(style.category))
        }
        // The critical rows' events are critical; no other event kind is (reactorWarning only at the temperature status).
        var criticalKinds: Set<GameEventKind> = []
        for row in ALRCatalog.rows where row.alertClass == .critical {
            let sample = try #require(ALRCatalog.sampleEvent(for: row))
            #expect(FeedStyle.classify(sample).severity == .critical, "row \(row.number)")
            criticalKinds.insert(GameEventKind(sample))
        }
        for kind in GameEventKind.allCases where FeedStyle.classify(kind.fixture).severity == .critical {
            #expect(criticalKinds.contains(kind), "\(kind)")
        }
        for row in ALRCatalog.rows where row.alertClass != .critical && row.presentation.eventKind == .reactorWarning {
            #expect(FeedStyle.classify(try #require(ALRCatalog.sampleEvent(for: row))).severity != .critical, "row \(row.number)")
        }
        let critical: [GameEvent] = [.arrested(term: 1, fine: 1, shipSold: false), .escapePodUsed(insurancePayout: 0), .reactorMeltdown,
                                     .reactorWarning(status: ReactorStatus.temperatureWarning), .playerDestroyed, .bothDestroyed,
                                     .gameEnded(.retired, score: 1)]
        #expect(critical.allSatisfy { FeedStyle.classify($0).severity == .critical })
        let others = GameEventKind.allCases.map(\.fixture).filter { !critical.map(GameEventKind.init).contains(GameEventKind($0)) }
        #expect(others.allSatisfy { FeedStyle.classify($0).severity != .critical })
        #expect(FeedStyle.classify(.reactorWarning(status: 2)).severity == .warning)
        #expect(FeedStyle.classify(.passengerConcerned(crewID: CrewID.jarek)).category == .comm)
        #expect(FeedStyle.classify(FeedItem.Entry.note(.gameSaved)).category == .system)
        #expect(FeedSeverity.critical.badgeSymbol != nil && FeedSeverity.warning.badgeSymbol != nil && FeedSeverity.info.badgeSymbol == nil)
    }

    @Test("UI-ENC-065 feed groups by day and system, collapses consecutive combat rounds, newest first")
    func feedGroups() {
        func item(_ id: Int, day: Int, system: Int, _ e: GameEvent) -> FeedItem {
            FeedItem(id: id, day: day, systemIndex: system, entry: .event(e))
        }
        let round = GameEvent.combatRound(round: 1, playerHit: true, opponentHit: false, playerHull: 90, opponentHull: 40)
        let feed = [
            item(0, day: 1, system: 3, .boughtCargo(item: .water, quantity: 1, total: 30)),
            item(1, day: 1, system: 3, .departed(from: 3, to: 4, viaWormhole: false)),
            item(2, day: 1, system: 3, .encounterStarted(type: .pirateAttack, opponent: .gnat, clicks: 9, playerCloaked: false)),
            item(3, day: 1, system: 3, round), item(4, day: 1, system: 3, round), item(5, day: 1, system: 3, round),
            item(6, day: 1, system: 3, .opponentDestroyed(.gnat)),
            item(7, day: 2, system: 4, .arrived(system: 4)),
        ]
        let groups = FeedGroup.make(feed)
        #expect(groups.map(\.id) == ["2.4", "1.3"])
        #expect(groups[1].rows.map(\.id) == [6, 3, 2, 1, 0])
        guard case let .rounds(items, opponent) = groups[1].rows[1] else {
            Issue.record("three rounds collapse into one row")
            return
        }
        #expect(items.map(\.id) == [3, 4, 5] && opponent == .gnat)
        #expect(AXID.Feed.group(day: 2, systemIndex: 4) == "status.feed.group.2.4" && AXID.Feed.rounds(3) == "status.feed.rounds.3")
        // A single round stays a plain row.
        let single = FeedGroup.make([item(0, day: 1, system: 1, round)])
        #expect(single.first?.rows == [.item(item(0, day: 1, system: 1, round))])
    }

    @Test("UI-ENC-066 passenger chatter is a Ship's comm line with the C# texts (all six)")
    func passengerComm() {
        let s = ArrivalFixtures.base
        let expected: [(Int, Bool, String)] = [
            (CrewID.jarek, false, "Commander? Jarek here. Do you require any assitance in charting a course to Devidia?"),
            (CrewID.princess, false, "[Ziyal] Oh Captain? (giggles) Would it help if I got out and pushed?"),
            (CrewID.wild, false, "Bridge? This is Jonathan. Are we there yet? Heh, heh. Sorry, I couldn't resist."),
            (CrewID.jarek, true, "Captain! This is the Ambassador speaking. We should have been there by now?!"),
            (CrewID.princess, true, "Sir! Are you taking me home or merely taking the place of my previous captors?!"),
            (CrewID.wild, true, "Commander! Wild here. What's taking us so long?!"),
        ]
        for (id, impatient, text) in expected {
            let line = PassengerComm.line(crewID: id, impatient: impatient, state: s)
            #expect(line == "Ship's comm — \(Names.crew(id, in: s)): \(text)")
            let event: GameEvent = impatient ? .passengerImpatient(crewID: id) : .passengerConcerned(crewID: id)
            #expect(FeedText.text(for: .event(event), state: s) == line)
            #expect(FeedStyle.classify(event).category == .comm)
        }
    }

    @Test("UI-ENC-067 new feed items never open the overlay in the Encounter or Transit view")
    func feedPolicy() {
        let playback = TransitPlayback(destination: 1, viaWormhole: false, fromClick: 20, toClick: 0, end: .arrival)
        for mode in [DetailMode.transit(playback), .encounter, .section(.bridge), .gameOver(.killed)] {
            #expect(!FeedOverlayPolicy.opensAutomatically(for: mode))
        }
        #expect(AXID.all.contains(AXID.Status.feed) && AXID.all.contains(AXID.Status.feedList))
    }
}
