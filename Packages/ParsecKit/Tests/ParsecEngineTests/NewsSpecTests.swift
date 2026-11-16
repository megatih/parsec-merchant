// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Testing
@testable import ParsecEngine

// MARK: Helpers

/// A docked Windows state whose newspaper has no distant systems, no events, no pressure and a neutral record,
/// so only the canned step draws.
func quietNewsState(seed: UInt64 = 42, _ adjust: (inout GameState) -> Void = { _ in }) -> GameState {
    var s = makeEngine(seed: seed).state
    s.commander.ship.fuel = 0
    s.galaxy.wormholes = []
    s.galaxy.systems[s.commander.currentSystem].pressure = .none
    s.commander.policeRecordScore = 0
    s.newsEvents = []
    adjust(&s)
    return s
}

/// A state at the first wormhole with no fuel, so the only distant system in the paper is the far end `W`, which
/// is stripped of stories; `adjust` then decorates it.
func oneNeighbourState(_ adjust: (inout GameState, Int) -> Void) -> GameState {
    var s = makeEngine().state
    s.commander.currentSystem = s.galaxy.wormholes[0]
    s.commander.ship.fuel = 0
    s.galaxy.systems[s.commander.currentSystem].pressure = .none
    s.commander.policeRecordScore = 0
    let w = s.galaxy.wormholes[1]
    s.galaxy.systems[w].pressure = .none
    s.galaxy.systems[w].specialEvent = nil
    s.galaxy.systems[w].shipyard = nil
    adjust(&s, w)
    return s
}

/// The paper's seeded generator (C# `RandSeed(cur.id, days)`).
func seededRand(_ s: GameState) -> PieterRand {
    var r = PieterRand(variant: .csharp)
    r.seed(s.commander.currentSystem, s.commander.days)
    return r
}

/// C# canned step: `toShow` drawn once, then `toShow + 1` index draws, duplicates skipped.
func expectedCanned(_ r: inout PieterRand, _ gov: PoliticalSystemType) -> [Headline] {
    var shown = Set<Int>()
    var out: [Headline] = []
    let toShow = r.getRandom2(4)
    for _ in 0...toShow {
        let i = r.getRandom2(4)
        if shown.insert(i).inserted { out.append(.canned(government: gov, index: i)) }
    }
    return out
}

// MARK: §1 Cost, purchase and options

@Suite("News spec: cost and purchase (NEWS §1)")
struct NewsPurchaseSpecTests {
    @Test("NEWS-001 the paper costs difficulty + 1 credits")
    func cost() {
        for d in Difficulty.allCases {
            var e = makeEngine(difficulty: d) { $0.options.newsAutoPay = true }
            let cash = e.state.commander.cash
            #expect(e.state.newspaperCost == d.rawValue + 1)
            _ = e.perform(.readNewspaper)
            #expect(e.state.commander.cash == cash - (d.rawValue + 1))
        }
    }

    @Test("NEWS-002 paidForNewspaper: set by a purchase, cleared by every arrival (including the pod), saved")
    func paidFlag() throws {
        var e = makeEngine { $0.options.newsAutoPay = true }
        #expect(!e.state.paidForNewspaper)
        _ = e.perform(.readNewspaper)
        #expect(e.state.paidForNewspaper)
        let cash = e.state.commander.cash
        _ = e.perform(.readNewspaper)
        #expect(e.state.commander.cash == cash)
        let decoded = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(e.state))
        #expect(decoded.paidForNewspaper)
        // A normal arrival.
        let t = try #require(plainTarget(e.state))
        _ = e.perform(.selectTarget(t))
        _ = completeTrip(&e)
        #expect(!e.state.paidForNewspaper)
        // The arrival after an escape pod.
        var pod = makeEngine { armDepartureFreeze(&$0) }
        _ = pod.perform(.warp)
        pod.state.paidForNewspaper = true
        _ = pod.finishEncounter(.escapePod)
        #expect(!pod.state.paidForNewspaper)
    }

    @Test("NEWS-003 readNewspaper is accepted only while docked")
    func dockedOnly() {
        var e = makeEngine { $0.options.newsAutoPay = true }
        e.state.phase = .encounter(EncounterState(type: .policeIgnore, opponent: freshShip(.gnat, e.state)))
        let before = e.state
        #expect(e.perform(.readNewspaper).rejection == .notAllowedInPhase)
        #expect(e.state == before)
        e.state.phase = .gameOver(.killed)
        #expect(e.perform(.readNewspaper).rejection == .gameOver)
    }

    @Test("NEWS-004 an unaffordable paper is rejected with insufficientFunds, tested against cash (not cash to spend)")
    func unaffordable() {
        var e = makeEngine { s in s.commander.cash = 2; s.options.newsAutoPay = true }
        let before = e.state
        #expect(e.state.newspaperCost == 3)
        #expect(e.perform(.readNewspaper).rejection == .insufficientFunds)
        #expect(e.state == before)
        // Reserve money makes cash-to-spend negative, but the cash test passes.
        var r = makeEngine { s in
            s.commander.cash = 3
            s.commander.debt = 1_000
            s.options.reserveMoney = true
            s.options.newsAutoPay = true
        }
        #expect(r.state.cashToSpend < 3)
        #expect(r.perform(.readNewspaper).rejection == nil)
        #expect(r.state.commander.cash == 0)
    }

    @Test("NEWS-006 with auto-pay the cost is deducted, the flag set and the paper returned")
    func autoPay() {
        var e = makeEngine { $0.options.newsAutoPay = true }
        let cash = e.state.commander.cash
        let r = e.perform(.readNewspaper)
        #expect(r.rejection == nil && r.events.isEmpty)
        #expect(e.state.commander.cash == cash - 3 && e.state.paidForNewspaper)
        #expect(r.decision == .newspaper(e.state.newspaper))
    }

    @Test("NEWS-007 without auto-pay the purchase needs the buyNewspaper consent with the cost")
    func confirmation() {
        var e = makeEngine()
        let before = e.state
        let ask = e.perform(.readNewspaper)
        #expect(ask.decision == .confirm(Confirmation(.buyNewspaper, amounts: [3])) && ask.events.isEmpty)
        #expect(e.state == before)
        let r = e.perform(.readNewspaper, acknowledging: [.buyNewspaper])
        #expect(r.decision == .newspaper(e.state.newspaper))
        #expect(e.state.commander.cash == before.commander.cash - 3 && e.state.paidForNewspaper)
    }

    @Test("NEWS-008 an already paid paper is free, emits nothing and is returned")
    func alreadyPaid() {
        var e = makeEngine { s in s.paidForNewspaper = true; s.commander.cash = 0 }
        let before = e.state
        let r = e.perform(.readNewspaper)
        #expect(r.rejection == nil && r.events.isEmpty && r.decision == .newspaper(before.newspaper))
        #expect(e.state == before)
    }

    @Test("NEWS-009 the paper is an informational decision; newspaperPreview returns it once paid")
    func informational() {
        var e = makeEngine { $0.options.newsAutoPay = true }
        #expect(e.state.newspaperPreview == nil)
        let r = e.perform(.readNewspaper)
        guard case let .newspaper(paper) = r.decision else { Issue.record("no paper"); return }
        #expect(e.state.newspaperPreview == paper)
        #expect(e.state.phase == .docked)
        // It blocks nothing: the next command is accepted.
        setMarket(&e.state)
        #expect(e.perform(.buyCargo(.water, quantity: 1)).rejection == nil)
    }

    @Test("NEWS-010 composition is pure: re-reading yields identical headlines and leaves the state unchanged")
    func pure() {
        var e = makeEngine { $0.options.newsAutoPay = true }
        let first = e.perform(.readNewspaper)
        let state = e.state
        let rng = e.state.rng
        let second = e.perform(.readNewspaper)
        #expect(first.decision == second.decision)
        #expect(e.state == state && e.state.rng == rng)
        #expect(e.state.newspaper == e.state.newspaper)
    }

    @Test("NEWS-011 newsAutoPay and newsAutoShow default to off")
    func defaults() {
        let o = GameOptions()
        #expect(!o.newsAutoPay && !o.newsAutoShow)
        #expect(!makeEngine().state.options.newsAutoShow)
    }

    @Test("NEWS-012 auto-show after an arrival is the app sending readNewspaper; the purchase rules then apply")
    func autoShow() throws {
        func arrived(cash: Int, autoPay: Bool) throws -> GameEngine {
            var e = makeEngine { s in s.options.newsAutoShow = true; s.options.newsAutoPay = autoPay; s.paidForNewspaper = true }
            let t = try #require(plainTarget(e.state))
            _ = e.perform(.selectTarget(t))
            let trip = completeTrip(&e)
            #expect(trip.events.last == .arrived(system: t))
            #expect(!e.state.paidForNewspaper)
            e.state.commander.cash = cash
            return e
        }
        var a = try arrived(cash: 100, autoPay: true)
        let bought = a.perform(.readNewspaper)
        #expect(bought.decision == .newspaper(a.state.newspaper) && a.state.commander.cash == 97)
        var b = try arrived(cash: 100, autoPay: false)
        #expect(b.perform(.readNewspaper).decision == .confirm(Confirmation(.buyNewspaper, amounts: [3])))
        var c = try arrived(cash: 2, autoPay: true)
        #expect(c.perform(.readNewspaper).rejection == .insufficientFunds)
    }
}

// MARK: §2 Records and §3 composition

@Suite("News spec: records and composition (NEWS §2, §3)")
struct NewsCompositionSpecTests {
    @Test("NEWS-014 Newspaper record: system, government, masthead index 0…2 and ordered headlines")
    func record() {
        var s = makeEngine().state
        for i in s.galaxy.systems.indices {
            s.commander.currentSystem = i
            let p = s.newspaper
            #expect(p.system == i && p.government == s.galaxy.systems[i].politics)
            #expect((0...2).contains(p.mastheadIndex))
            #expect(!p.headlines.isEmpty)
        }
    }

    @Test("NEWS-015 NEWS-016 headline indices address the classic string tables; the app fills ^1…^3")
    func stringTables() throws {
        let t = try #require(TravelHarnessTests.strings)
        #expect(t.events.count == NewsEvent.allCases.count)
        #expect(t.internalPressure.count == SystemPressure.allCases.count)
        #expect(t.externalPressures.count == SystemPressure.allCases.count)
        #expect(t.villain.count == NewsTables.villainCount && t.hero.count == NewsTables.heroCount)
        #expect(t.external.count == NewsTables.externalTemplates)
        #expect(t.headlines.count == PoliticalSystemType.allCases.count && t.mastheads.count == PoliticalSystemType.allCases.count)
        #expect(t.headlines.allSatisfy { $0.count == NewsTables.cannedPerGovernment })
        #expect(t.mastheads.allSatisfy { $0.count == NewsTables.mastheadsPerGovernment })
        // Substitution: masthead ^1 = system; event ^1 commander, ^2 system, ^3 ship; hero/villain ^1, ^2.
        let sys = SystemID.og
        let paper = Newspaper(system: sys, government: .anarchy, mastheadIndex: 0,
                              headlines: [.event(.caughtLittering), .villain(index: 0), .moonForSale(system: SystemID.utopia),
                                          .externalPressure(template: 0, pressure: .war, system: SystemID.kravat),
                                          .canned(government: .anarchy, index: 3), .internalPressure(.plague)])
        let (head, text) = t.render(paper, commander: "Zed", shipType: .gnat)
        #expect(head == t.mastheads[0][0].replacingOccurrences(of: "^1", with: t.systems[sys]))
        let lines = text.components(separatedBy: "\n\n")
        #expect(lines.count == 6)
        #expect(lines[0] == t.events[NewsEvent.caughtLittering.rawValue].replacingOccurrences(of: "^1", with: "Zed"))
        #expect(lines[1] == "Police Warning: Zed Will Dock At \(t.systems[sys])!")
        #expect(lines[2] == t.moon.replacingOccurrences(of: "^1", with: t.systems[SystemID.utopia]))
        #expect(lines[3].contains(t.systems[SystemID.kravat]) && lines[3].contains(t.externalPressures[1]))
        #expect(lines[4] == t.headlines[0][3] && lines[5] == t.internalPressure[2])
    }

    @Test("NEWS-017 masthead: current government and system id mod 3")
    func masthead() {
        var s = makeEngine().state
        for i in [0, 1, 2, 3, 50, 70, 127] {
            s.commander.currentSystem = i
            #expect(s.newspaper.mastheadIndex == i % 3 && s.newspaper.government == s.galaxy.systems[i].politics)
        }
    }

    @Test("NEWS-018 NEWS-025 composition seeds PieterRand(cur, days); the canned step draws toShow once")
    func seedAndCanned() {
        for days in [1, 7, 33, 400] {
            let s = quietNewsState { $0.commander.days = days }
            var r = seededRand(s)
            #expect(s.newspaper.headlines == expectedCanned(&r, s.currentSystem.politics))
        }
        // System 0 (Acamar) and day 0 select the default seeds.
        let acamar = quietNewsState { s in s.commander.currentSystem = 0; s.commander.days = 0
            s.galaxy.systems[0].pressure = .none }
        var r = PieterRand(variant: .csharp)
        r.seed(Int(PieterRand.defSeedX), Int(PieterRand.defSeedY))
        #expect(acamar.newspaper.headlines == expectedCanned(&r, acamar.currentSystem.politics))
        // Canned count is 1…4.
        for days in 1...200 {
            let n = quietNewsState { $0.commander.days = days }.newspaper.headlines.count
            #expect((1...4).contains(n))
        }
    }

    @Test("NEWS-019 news events come first, one per element, in list order")
    func events() {
        let list: [NewsEvent] = [.gemulon, .japori, .gemulon, .caughtLittering]
        let s = quietNewsState { $0.newsEvents = list }
        #expect(Array(s.newspaper.headlines.prefix(4)) == list.map { .event($0) })
    }

    @Test("NEWS-020 the current system's pressure follows the events and draws nothing")
    func internalPressure() {
        let plain = quietNewsState { $0.newsEvents = [.japori] }
        let pressed = quietNewsState { s in s.newsEvents = [.japori]; s.galaxy.systems[s.commander.currentSystem].pressure = .drought }
        #expect(pressed.newspaper.headlines == [.event(.japori), .internalPressure(.drought)] + plain.newspaper.headlines.dropFirst())
    }

    @Test("NEWS-021 villain at record ≤ −70, else hero at ≥ 75, each with one draw")
    func heroVillain() {
        func paper(_ record: Int) -> (GameState, [Headline]) {
            let s = quietNewsState { $0.commander.policeRecordScore = record }
            return (s, s.newspaper.headlines)
        }
        for record in [-70, -100] {
            let (s, h) = paper(record)
            var r = seededRand(s)
            let v = r.getRandom2(4)
            #expect(h == [.villain(index: v)] + expectedCanned(&r, s.currentSystem.politics))
        }
        for record in [75, 200] {
            let (s, h) = paper(record)
            var r = seededRand(s)
            let v = r.getRandom2(3)
            #expect(h == [.hero(index: v)] + expectedCanned(&r, s.currentSystem.politics))
        }
        for record in [-69, 0, 74] {
            let (s, h) = paper(record)
            var r = seededRand(s)
            #expect(h == expectedCanned(&r, s.currentSystem.politics))
        }
    }

    @Test("NEWS-022 NEWS-023 distant systems in range: moon or tribble buyer, shipyard, then a drawn pressure story")
    func distant() {
        // Moon + shipyard + pressure.
        let s = oneNeighbourState { s, w in
            s.galaxy.systems[w].specialEvent = .moon
            s.galaxy.systems[w].shipyard = .corellian
            s.galaxy.systems[w].pressure = .war
        }
        let w = s.galaxy.wormholes[1]
        var r = seededRand(s)
        var expected: [Headline] = [.moonForSale(system: w), .shipyard(system: w)]
        let threshold = 6 * s.currentSystem.techLevel.rawValue + 10 * (5 - s.difficulty.rawValue)
        if r.getRandom2(100) <= threshold {
            expected.append(.externalPressure(template: r.getRandom2(6), pressure: .war, system: w))
        } else {
            expected += expectedCanned(&r, s.currentSystem.politics)
        }
        #expect(s.newspaper.headlines == expected)
        // Tribble buyer, no pressure: no draw, no real news (canned follows from the first draw).
        let t = oneNeighbourState { s, w in s.galaxy.systems[w].specialEvent = .tribbleBuyer }
        var rt = seededRand(t)
        #expect(t.newspaper.headlines == [.tribbleBuyer(system: w)] + expectedCanned(&rt, t.currentSystem.politics))
        // Out of range systems are ignored.
        let none = oneNeighbourState { s, w in s.galaxy.wormholes = []; s.galaxy.systems[w].shipyard = .kuat }
        var rn = seededRand(none)
        #expect(none.newspaper.headlines == expectedCanned(&rn, none.currentSystem.politics))
    }

    @Test("NEWS-024 story threshold 6 × TL + 10 × (5 − D): a draw equal to it passes, one above fails")
    func threshold() throws {
        let cases: [(TechLevel, Difficulty, Int)] = [(.hiTech, .normal, 72), (.preAgricultural, .impossible, 10), (.hiTech, .beginner, 92)]
        for (tl, d, limit) in cases {
            for (draw, passes) in [(limit, true), (limit + 1, false)] {
                var s = oneNeighbourState { s, w in
                    s.galaxy.systems[s.commander.currentSystem].techLevel = tl
                    s.difficulty = d
                    s.galaxy.systems[w].pressure = .plague
                }
                var day = 1
                while true {
                    var r = PieterRand(variant: .csharp)
                    r.seed(s.commander.currentSystem, day)
                    if r.getRandom2(100) == draw { break }
                    day += 1
                    try #require(day < 200_000)
                }
                s.commander.days = day
                let hasStory = s.newspaper.headlines.contains { if case .externalPressure = $0 { true } else { false } }
                #expect(hasStory == passes, "TL \(tl) D \(d) draw \(draw)")
            }
        }
    }

    @Test("NEWS-026 example: toShow 2 and index draws 3, 3, 0 give canned 3 then 0")
    func cannedExample() throws {
        var s = quietNewsState()
        var day = 1
        while true {
            var r = PieterRand(variant: .csharp)
            r.seed(s.commander.currentSystem, day)
            if r.getRandom2(4) == 2, r.getRandom2(4) == 3, r.getRandom2(4) == 3, r.getRandom2(4) == 0 { break }
            day += 1
            try #require(day < 200_000)
        }
        s.commander.days = day
        let g = s.currentSystem.politics
        #expect(s.newspaper.headlines == [.canned(government: g, index: 3), .canned(government: g, index: 0)])
    }

    @Test("NEWS-027 every headline is kept: no page-length limit in Windows and Modern")
    func noPageLimit() {
        for ruleset in [RulesetID.windows201, .modern] {
            var s = makeEngine(ruleset).state
            s.newsEvents = Array(repeating: .gemulon, count: 40)
            #expect(s.newspaper.headlines.filter { $0 == .event(.gemulon) }.count == 40)
        }
    }
}

// MARK: §4 News-event list

@Suite("News spec: news-event list (NEWS §4)")
struct NewsEventListSpecTests {
    @Test("NEWS-029 newsEvents is ordered, allows duplicates and is saved")
    func list() throws {
        var s = makeEngine().state
        s.newsEvents = [.gemulon, .japori, .gemulon]
        let d = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(s))
        #expect(d.newsEvents == [.gemulon, .japori, .gemulon])
    }

    @Test("NEWS-030 the list is cleared at every departure; arrival events stay until the next one")
    func clearedAtDeparture() throws {
        var e = makeEngine { s in armDepartureFreeze(&s); s.newsEvents = [.caughtLittering, .japori] }
        _ = e.perform(.warp)
        guard case .encounter = e.state.phase else { Issue.record("not frozen"); return }
        #expect(e.state.newsEvents.isEmpty)
        // Arrival news remains while docked and is cleared by the next departure.
        var a = makeEngine()
        let t = try #require(plainTarget(a.state))
        a.state.galaxy.systems[t].specialEvent = .gemulon
        _ = a.perform(.selectTarget(t))
        _ = completeTrip(&a)
        #expect(a.state.newsEvents == [.gemulon])
        a.state.commander.ship.fuel = a.state.commander.ship.fuelTanks(a.ruleset)
        let next = try #require(plainTarget(a.state))
        _ = a.perform(.selectTarget(next))
        _ = completeTrip(&a)
        #expect(!a.state.newsEvents.contains(.gemulon))
    }

    @Test("NEWS-031 news is added by littering, famous-captain attacks, arrests, pods, IncDays and arrivals")
    func addSources() throws {
        // IncDays: the experiment.
        var s = makeEngine().state
        s.newsEvents = [.japori]
        s.quests.experiment = QuestStatus.Experiment.date
        _ = s.incDays(1)
        #expect(s.newsEvents == [.japori, .experimentPerformed])
        // Escape pod and arrest with Wild aboard.
        var pod = makeEngine().state
        pod.commander.ship.crew.append(CrewID.wild)
        _ = pod.escapeWithPod()
        #expect(pod.newsEvents.contains(.wildArrested))
        var jail = makeEngine().state
        jail.commander.ship.crew.append(CrewID.wild)
        _ = jail.arrested()
        #expect(jail.newsEvents.first == .wildArrested)
        // Attacking a famous captain.
        for (type, event) in [(EncounterType.captainAhab, NewsEvent.captAhabAttacked), (.captainConrad, .captConradAttacked),
                              (.captainHuie, .captHuieAttacked)] {
            var e = makeEngine()
            e.state.phase = .encounter(EncounterState(type: type, opponent: freshShip(.wasp, e.state)))
            e.state.encounterTransit = TransitState(destination: 1, clicksRemaining: 5, viaWormhole: false)
            _ = e.perform(.encounter(.attack), acknowledging: [.attackCaptain])
            #expect(e.state.newsEvents.first == event)
        }
        // Caught littering.
        var l = makeEngine()
        l.state.phase = .encounter(EncounterState(type: .policeIgnore, opponent: freshShip(.gnat, l.state)))
        l.state.commander.ship.cargo[0] = 5
        while true {
            var peek = l.state.rng
            if peek.next(below: 10) < l.state.difficulty.rawValue + 1 { break }
            _ = l.state.rng.next(below: 2)
        }
        _ = l.perform(.jettisonCargo(.water, quantity: 1), acknowledging: [.litteringWarning])
        #expect(l.state.newsEvents == [.caughtLittering])
        // Arrival.
        var a = makeEngine().state
        a.warpSystem = try #require(plainTarget(a))
        a.galaxy.systems[a.warpSystem].specialEvent = .scarab
        _ = a.arrival()
        #expect(a.newsEvents == [.scarab])
    }

    @Test("NEWS-032 destroying a famous captain turns its latest attacked event into the destroyed event")
    func replace() {
        for (attacked, destroyed) in [(NewsEvent.captAhabAttacked, NewsEvent.captAhabDestroyed),
                                      (.captConradAttacked, .captConradDestroyed), (.captHuieAttacked, .captHuieDestroyed)] {
            var s = makeEngine().state
            s.newsEvents = [.gemulon, attacked]
            var enc = EncounterState(type: .famousCaptainAttack, opponent: freshShip(.wasp, s))
            _ = s.encounterWon(&enc)
            #expect(s.newsEvents == [.gemulon, destroyed])
        }
        // An empty list stays empty (the C# code would index −1).
        var s = makeEngine().state
        var enc = EncounterState(type: .famousCaptainAttack, opponent: freshShip(.wasp, s))
        _ = s.encounterWon(&enc)
        #expect(s.newsEvents.isEmpty)
    }

    @Test("NEWS-033 NEWS-034 arrival events by the system's special event and quest status, at most one")
    func arrivalEvents() {
        typealias QS = QuestStatus
        let table: [(SpecialEventType, (inout GameState) -> Void, NewsEvent?)] = [
            (.artifactDelivery, { $0.quests.artifact = QS.Artifact.onBoard }, .artifactDelivery),
            (.artifactDelivery, { _ in }, nil),
            (.dragonfly, { _ in }, .dragonfly),
            (.dragonflyBaratas, { $0.quests.dragonfly = QS.Dragonfly.flyBaratas }, .dragonflyBaratas),
            (.dragonflyBaratas, { $0.quests.dragonfly = QS.Dragonfly.flyMelina }, nil),
            (.dragonflyMelina, { $0.quests.dragonfly = QS.Dragonfly.flyMelina }, .dragonflyMelina),
            (.dragonflyRegulas, { $0.quests.dragonfly = QS.Dragonfly.flyRegulas }, .dragonflyRegulas),
            (.dragonflyDestroyed, { $0.quests.dragonfly = QS.Dragonfly.flyZalkon }, .dragonflyZalkon),
            (.dragonflyDestroyed, { $0.quests.dragonfly = QS.Dragonfly.destroyed }, .dragonflyDestroyed),
            (.dragonflyDestroyed, { $0.quests.dragonfly = QS.Dragonfly.done }, nil),
            (.experimentFailed, { _ in }, .experimentFailed),
            (.experimentStopped, { $0.quests.experiment = 5 }, .experimentStopped),
            (.experimentStopped, { $0.quests.experiment = QS.Experiment.performed }, nil),
            (.gemulon, { _ in }, .gemulon),
            (.gemulonRescued, { $0.quests.gemulon = 3 }, .gemulonRescued),
            (.gemulonRescued, { $0.quests.gemulon = QS.Gemulon.tooLate }, .gemulonInvaded),
            (.gemulonRescued, { _ in }, nil),
            (.japori, { _ in }, .japori),
            (.japori, { $0.quests.japori = QS.Japori.inTransit }, nil),
            (.japoriDelivery, { $0.quests.japori = QS.Japori.inTransit }, .japoriDelivery),
            (.jarekGetsOut, { $0.commander.ship.crew.append(CrewID.jarek) }, .jarekGetsOut),
            (.jarekGetsOut, { _ in }, nil),
            (.princess, { _ in }, .princess),
            (.princessCentauri, { $0.quests.princess = QS.Princess.flyCentauri }, .princessCentauri),
            (.princessInthara, { $0.quests.princess = QS.Princess.flyInthara }, .princessInthara),
            (.princessQonos, { $0.quests.princess = QS.Princess.flyQonos }, .princessQonos),
            (.princessQonos, { $0.quests.princess = QS.Princess.rescued }, .princessRescued),
            (.princessReturned, { $0.quests.princess = QS.Princess.returned }, .princessReturned),
            (.princessReturned, { $0.quests.princess = QS.Princess.done }, nil),
            (.scarab, { _ in }, .scarab),
            (.scarabDestroyed, { $0.quests.scarab = QS.Scarab.hunting }, .scarabHarass),
            (.scarabDestroyed, { $0.quests.scarab = QS.Scarab.destroyed }, .scarabDestroyed),
            (.scarabDestroyed, { $0.quests.scarab = QS.Scarab.done }, .scarabDestroyed),
            (.sculpture, { _ in }, .sculptureStolen),
            (.sculptureDelivered, { _ in }, .sculptureTracked),
            (.spaceMonsterKilled, { $0.quests.spaceMonster = QS.SpaceMonster.atAcamar }, .spaceMonster),
            (.spaceMonsterKilled, { $0.quests.spaceMonster = QS.SpaceMonster.destroyed }, .spaceMonsterKilled),
            (.spaceMonsterKilled, { _ in }, nil),
            (.wildGetsOut, { $0.commander.ship.crew.append(CrewID.wild) }, .wildGetsOut),
            (.wildGetsOut, { _ in }, nil),
            (.moon, { _ in }, nil),
            (.lottery, { _ in }, nil),
        ]
        for (event, adjust, expected) in table {
            var s = makeEngine().state
            s.galaxy.systems[s.commander.currentSystem].specialEvent = event
            adjust(&s)
            s.addArrivalNews()
            #expect(s.newsEvents == (expected.map { [$0] } ?? []), "\(event)")
        }
    }
}
