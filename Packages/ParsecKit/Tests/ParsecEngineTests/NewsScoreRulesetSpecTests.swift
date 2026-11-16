// SPDX-License-Identifier: GPL-2.0-or-later
// NEWS and SCORE {M5}, RUL-144…150: Palm newspaper, Palm score, Modern moon-girl ending (docs/specs/NEWS.md, SCORE.md).
import Testing
@testable import ParsecEngine

// MARK: Helpers

/// A docked state whose newspaper has no pressure stories and no event headlines unless a test adds them.
private func quietPaper(_ id: RulesetID, _ adjust: (inout GameState) -> Void = { _ in }) -> GameState {
    var s = makeEngine(id).state
    for i in s.galaxy.systems.indices {
        s.galaxy.systems[i].pressure = .none
        s.galaxy.systems[i].specialEvent = nil
        s.galaxy.systems[i].shipyard = nil
    }
    s.commander.policeRecordScore = 0
    s.newsEvents = []
    adjust(&s)
    return s
}

private func events(_ p: Newspaper) -> [NewsEvent] {
    p.headlines.compactMap { if case let .event(e) = $0 { e } else { nil } }
}

/// An engine in an encounter of `type` against a fresh `opponent` for `ruleset`, resuming a one-click transit afterwards.
private func encounterEngine(_ id: RulesetID, _ type: EncounterType, opponent: ShipType = .gnat,
                             _ adjust: (inout GameState, inout Ship) -> Void = { _, _ in }) -> GameEngine {
    makeEngine(id) { s in
        var opp = Ship(type: opponent, spec: s.ruleset.tables.ship(opponent))
        opp.crew[0] = CrewID.opponent
        adjust(&s, &opp)
        s.lastOpponent = opp
        s.warpSystem = plainTarget(s) ?? 1
        s.encounterTransit = TransitState(destination: s.warpSystem, clicksRemaining: 1, viaWormhole: false, hadEncounter: true)
        s.phase = .encounter(EncounterState(type: type, opponent: opp, clicks: 1))
    }
}

/// A docked state with the given ruleset, difficulty, day and worth (ship value per RUL-119 + cash − debt).
private func scored(_ id: RulesetID, _ d: Difficulty, days: Int = 1, worth: Int) -> GameState {
    var s = makeEngine(id, difficulty: d).state
    s.commander.days = days
    // The ship's contribution follows the ruleset's worth rule (RUL-119: list price or trade-in value).
    s.commander.cash = 0
    s.commander.debt = 0
    let base = s.worth
    s.commander.cash = max(0, worth - base)
    s.commander.debt = max(0, base - worth)
    #expect(s.worth == worth)
    return s
}

// MARK: Purchase and options

@Suite("News rulesets: purchase, flags store (NEWS {M5})")
struct NewsRulesetStoreTests {
    @Test("NEWS-005 Palm checks the price against cash to spend (reserve money can block it); Windows against cash")
    func palmPrice() {
        func setup(_ s: inout GameState) {
            // A paid mercenary is reserved by Palm's ToSpend (BNK-055); interest and debt are not.
            var ship = Ship(type: .beetle, spec: s.ruleset.tables.ship(.beetle))
            ship.crew[0] = CrewID.commander
            ship.crew[1] = 1
            s.commander.ship = ship
            s.commander.cash = s.mercenaryCosts + s.newspaperCost - 1
            s.options.reserveMoney = true
        }
        var palm = makeEngine(.palm122, setup)
        #expect(palm.state.cashToSpend < palm.state.newspaperCost)
        let before = palm.state
        #expect(palm.perform(.readNewspaper).rejection == .insufficientFunds)
        #expect(palm.state == before)
        var win = makeEngine(.windows201, setup)
        #expect(win.perform(.readNewspaper).decision == .confirm(Confirmation(.buyNewspaper, amounts: [win.state.newspaperCost])))
    }

    @Test("NEWS-013 Palm has auto-pay but no auto-show option")
    func autoShow() {
        #expect(!Ruleset.palm122.flags.travel.newsAutoShowAvailable)
        #expect(Ruleset.windows201.flags.travel.newsAutoShowAvailable && Ruleset.modern.flags.travel.newsAutoShowAvailable)
        var e = makeEngine(.palm122) { $0.options.newsAutoPay = true }
        let r = e.perform(.readNewspaper)
        #expect(r.rejection == nil && e.state.paidForNewspaper)
        if case .newspaper = r.decision {} else { Issue.record("auto-pay shows the paper without a confirmation") }
    }

    @Test("NEWS-035 Palm stores at most 4 news flags; later ones are ignored; a departure clears them")
    func capacity() {
        var s = makeEngine(.palm122).state
        for e: NewsEvent in [.japori, .dragonfly, .scarab, .gemulon, .wildArrested] { s.addNewsEvent(e) }
        #expect(s.newsEvents == [.japori, .dragonfly, .scarab, .gemulon])
        s.warpSystem = plainTarget(s) ?? 1
        _ = s.depart(viaSingularity: false)
        #expect(s.newsEvents.isEmpty)
        var w = makeEngine().state
        for e: NewsEvent in [.japori, .dragonfly, .scarab, .gemulon, .wildArrested] { w.addNewsEvent(e) }
        #expect(w.newsEvents.count == 5)
    }

    @Test("NEWS-036 Palm destroying a famous captain replaces every stored copy of the latest flag with latest + 10")
    func replaceLatest() {
        var s = makeEngine(.palm122).state
        s.newsEvents = [.captHuieAttacked, .wildArrested, .captHuieAttacked]
        s.markFamousCaptainDestroyed()
        #expect(s.newsEvents == [.captHuieDestroyed, .wildArrested, .captHuieDestroyed])
        // WILDARRESTED (90) + 10 is CAPTAINHUIEATTACKED (100).
        s.newsEvents = [.wildArrested]
        s.markFamousCaptainDestroyed()
        #expect(s.newsEvents == [.captHuieAttacked])
        // C# replaces only the last stored event.
        var w = makeEngine().state
        w.newsEvents = [.captHuieAttacked, .wildArrested, .captHuieAttacked]
        w.markFamousCaptainDestroyed()
        #expect(w.newsEvents == [.captHuieAttacked, .wildArrested, .captHuieDestroyed])
    }

    @Test("NEWS-037 Palm flag sources: littering, captain attacked, Wild arrested (pod), experiment, singularity")
    func flagSources() throws {
        var exp = makeEngine(.palm122).state
        exp.quests.experiment = QuestStatus.Experiment.date
        _ = exp.incDays(1)
        #expect(exp.newsEvents == [.experimentPerformed])
        var pod = makeEngine(.palm122).state
        pod.commander.ship = freshShip(.bumblebee, pod)
        pod.hireCrew(CrewID.wild)
        pod.quests.wild = QuestStatus.Wild.started
        _ = pod.escapeWithPod()
        #expect(pod.newsEvents == [.wildArrested])
        var jump = makeEngine(.palm122).state
        jump.warpSystem = plainTarget(jump) ?? 1
        _ = jump.depart(viaSingularity: true)
        #expect(jump.newsEvents == [.experimentArrival])
        var capt = encounterEngine(.palm122, .captainHuie)
        _ = capt.perform(.encounter(.attack), acknowledging: [.attackCaptain])
        #expect(capt.state.newsEvents.first == .captHuieAttacked)
        let litter = encounterEngine(.palm122, .pirateIgnore) { s, _ in
            s.commander.ship.cargo[TradeItemType.water.rawValue] = 1
            s.litterWarning = true
        }
        let (_, caught) = try #require(m4Scan(litter, { $0.perform(.jettisonCargo(.water, quantity: 1), acknowledging: [.jettisonAll]) },
                                              until: { r, _ in r.events.contains { if case .caughtLittering = $0 { true } else { false } } }))
        #expect(caught.state.newsEvents == [.caughtLittering])
    }

    @Test("NEWS-038 Palm arrival flags: an else-if chain on the system's special event with status tests (first match only)")
    func arrivalChain() {
        func flag(_ ev: SpecialEventType, _ adjust: (inout GameState) -> Void = { _ in }) -> [NewsEvent] {
            var s = makeEngine(.palm122).state
            s.galaxy.systems[s.commander.currentSystem].specialEvent = ev
            adjust(&s)
            s.addArrivalNews()
            return s.newsEvents
        }
        #expect(flag(.spaceMonsterKilled) { $0.quests.spaceMonster = QuestStatus.SpaceMonster.destroyed } == [.spaceMonsterKilled])
        #expect(flag(.spaceMonsterKilled) { $0.quests.spaceMonster = QuestStatus.SpaceMonster.atAcamar }.isEmpty)
        #expect(flag(.dragonfly) == [.dragonfly])
        #expect(flag(.scarab) == [.scarab])
        #expect(flag(.scarabDestroyed) { $0.quests.scarab = QuestStatus.Scarab.destroyed } == [.scarabDestroyed])
        #expect(flag(.scarabDestroyed) { $0.quests.scarab = QuestStatus.Scarab.hunting }.isEmpty)
        #expect(flag(.dragonflyMelina) { $0.quests.dragonfly = QuestStatus.Dragonfly.flyMelina } == [.dragonflyMelina])
        #expect(flag(.dragonflyDestroyed) { $0.quests.dragonfly = QuestStatus.Dragonfly.flyZalkon }.isEmpty)
        #expect(flag(.dragonflyDestroyed) { $0.quests.dragonfly = QuestStatus.Dragonfly.destroyed } == [.dragonflyDestroyed])
        #expect(flag(.japoriDelivery) { $0.quests.japori = QuestStatus.Japori.inTransit } == [.japoriDelivery])
        #expect(flag(.japori) == [.japori])
        #expect(flag(.artifactDelivery) { $0.quests.artifact = QuestStatus.Artifact.onBoard } == [.artifactDelivery])
        #expect(flag(.jarekGetsOut) { $0.quests.jarek = QuestStatus.Jarek.started } == [.jarekGetsOut])
        #expect(flag(.wildGetsOut) { $0.quests.wild = QuestStatus.Wild.started } == [.wildGetsOut])
        #expect(flag(.gemulonRescued) { $0.quests.gemulon = 3 } == [.gemulonRescued])
        #expect(flag(.gemulonRescued).isEmpty)
        #expect(flag(.gemulon) == [.gemulon])
        #expect(flag(.experimentStopped) { $0.quests.experiment = 5 } == [.experimentStopped])
        #expect(flag(.experimentFailed) == [.experimentFailed])
        // Windows adds derived events Palm only prints from conditions (e.g. dragonflyZalkon).
        var w = makeEngine().state
        w.galaxy.systems[w.commander.currentSystem].specialEvent = .dragonflyDestroyed
        w.quests.dragonfly = QuestStatus.Dragonfly.flyZalkon
        w.addArrivalNews()
        #expect(w.newsEvents == [.dragonflyZalkon])
    }

    @Test("NEWS-039 the engine adds the Palm arrival flags once, at the end of the arrival step")
    func flagsOnce() {
        var s = makeEngine(.palm122).state
        s.warpSystem = plainTarget(s) ?? 1
        s.galaxy.systems[s.warpSystem].specialEvent = .gemulon
        _ = s.arrival()
        #expect(s.newsEvents == [.gemulon])
    }
}

// MARK: Composition

@Suite("News rulesets: Palm composition (NEWS {M5}, RUL-144…148)")
struct NewsRulesetCompositionTests {
    @Test("NEWS-040 Palm masthead is warpSystem % 3 and the paper is seeded with (warpSystem, days)")
    func palmSeed() {
        var s = quietPaper(.palm122) { $0.commander.policeRecordScore = -40 }
        let cur = s.commander.currentSystem
        for target in [cur, (cur + 1) % s.galaxy.systems.count, (cur + 2) % s.galaxy.systems.count] {
            s.warpSystem = target
            var rand = PieterRand(variant: .palm)
            rand.seed(target, s.commander.days)
            let paper = s.newspaper
            #expect(paper.mastheadIndex == target % 3 && paper.system == cur)
            #expect(paper.headlines.first == .villain(index: rand.getRandom2(NewsTables.villainCount)))
        }
        var w = quietPaper(.windows201)
        w.warpSystem = (w.commander.currentSystem + 1) % w.galaxy.systems.count
        #expect(w.newspaper.mastheadIndex == w.commander.currentSystem % 3)
    }

    @Test("NEWS-041 Palm prints event headlines in its fixed order, with condition-only headlines; C# in insertion order")
    func fixedOrder() {
        let stored: [NewsEvent] = [.gemulon, .dragonfly, .captHuieAttacked, .experimentPerformed]
        let palm = quietPaper(.palm122) { s in
            s.newsEvents = stored
            s.galaxy.systems[s.commander.currentSystem].specialEvent = .spaceMonsterKilled
            s.quests.spaceMonster = QuestStatus.SpaceMonster.atAcamar
        }
        #expect(events(palm.newspaper) == [.captHuieAttacked, .experimentPerformed, .spaceMonster, .dragonfly, .gemulon])
        let gem = quietPaper(.palm122) { $0.galaxy.systems[$0.commander.currentSystem].specialEvent = .gemulonRescued }
        #expect(events(gem.newspaper) == [.gemulonInvaded])
        let win = quietPaper(.windows201) { $0.newsEvents = stored }
        #expect(events(win.newspaper) == stored)
    }

    @Test("NEWS-042 RUL-144 RUL-145 Palm villain at record ≤ −30, hero only at exactly 75; C# −70 and ≥ 75")
    func heroVillain() {
        func kinds(_ id: RulesetID, _ record: Int) -> (villain: Bool, hero: Bool) {
            let p = quietPaper(id) { $0.commander.policeRecordScore = record }.newspaper
            return (p.headlines.contains { if case .villain = $0 { true } else { false } },
                    p.headlines.contains { if case .hero = $0 { true } else { false } })
        }
        #expect(kinds(.palm122, -30) == (true, false))
        #expect(kinds(.palm122, -29) == (false, false))
        #expect(kinds(.palm122, 75) == (false, true))
        #expect(kinds(.palm122, 76) == (false, false))
        #expect(kinds(.windows201, -30) == (false, false))
        #expect(kinds(.windows201, -70) == (true, false))
        #expect(kinds(.windows201, 76) == (false, true))
        #expect(kinds(.modern, 76) == (false, true))
    }

    @Test("NEWS-043 Palm prints the littering headline after the villain story; C# among the events")
    func litteringPosition() {
        let palm = quietPaper(.palm122) { $0.commander.policeRecordScore = -40; $0.newsEvents = [.caughtLittering] }.newspaper
        #expect(palm.headlines.count >= 2)
        if case .villain = palm.headlines[0] {} else { Issue.record("villain first") }
        #expect(palm.headlines[1] == .event(.caughtLittering))
        let win = quietPaper(.windows201) { $0.commander.policeRecordScore = -80; $0.newsEvents = [.caughtLittering] }.newspaper
        #expect(win.headlines.first == .event(.caughtLittering))
    }

    @Test("NEWS-044 RUL-146 Palm distant stories: base tank range or wormhole, status > 0 for every story, no shipyards")
    func distantRange() throws {
        /// A system within the base tank range that is not a wormhole end.
        func nearby(_ id: RulesetID) throws -> Int {
            let probe = quietPaper(id)
            let cur = probe.commander.currentSystem
            let tanks = probe.commander.ship.spec(probe.ruleset).fuelTanks
            return try #require(probe.galaxy.systems.indices.first { j in
                j != cur && !probe.galaxy.wormholeExists(from: cur, to: j)
                    && GalaxyGenerator.distance(probe.galaxy.systems[cur], probe.galaxy.systems[j], rule: probe.ruleset.flags.distance) <= tanks
            })
        }
        let palmI = try nearby(.palm122), winI = try nearby(.windows201)
        let tanks = makeEngine().state.commander.ship.spec(Ruleset.windows201).fuelTanks
        func paper(_ id: RulesetID, fuel: Int, pressure: SystemPressure) -> [Headline] {
            let i = id == .palm122 ? palmI : winI
            return quietPaper(id) { s in
                s.commander.ship.fuel = fuel
                s.galaxy.systems[i].specialEvent = .moon
                s.galaxy.systems[i].shipyard = .corellian
                s.galaxy.systems[i].pressure = pressure
            }.newspaper.headlines
        }
        // Palm ignores the current fuel but needs a status.
        #expect(!paper(.palm122, fuel: 0, pressure: .none).contains(.moonForSale(system: palmI)))
        let palmWar = paper(.palm122, fuel: 0, pressure: .war)
        #expect(palmWar.contains(.moonForSale(system: palmI)) && !palmWar.contains(.shipyard(system: palmI)))
        // C#: current fuel decides; moon and shipyard stories need no status.
        #expect(!paper(.windows201, fuel: 0, pressure: .none).contains(.moonForSale(system: winI)))
        let win = paper(.windows201, fuel: tanks, pressure: .none)
        #expect(win.contains(.moonForSale(system: winI)) && win.contains(.shipyard(system: winI)))
    }

    @Test("NEWS-045 RUL-147 Palm canned loop re-draws its bound on every test; C# draws it once")
    func cannedBound() {
        var differs = false
        for day in 1...40 {
            let s = quietPaper(.palm122) { $0.commander.days = day }
            let gov = s.currentSystem.politics
            func replica(redraw: Bool) -> [Headline] {
                var rand = PieterRand(variant: .palm)
                rand.seed(s.warpSystem, day)
                var shown = [false, false, false, false], out: [Headline] = []
                func show(_ j: Int) { if !shown[j] { out.append(.canned(government: gov, index: j)); shown[j] = true } }
                if redraw {
                    var k = 0
                    while k <= rand.getRandom2(4) { show(rand.getRandom2(4)); k += 1 }
                } else {
                    let n = rand.getRandom2(4)
                    for _ in 0...n { show(rand.getRandom2(4)) }
                }
                return out
            }
            #expect(s.newspaper.headlines == replica(redraw: true))
            if replica(redraw: true) != replica(redraw: false) { differs = true }
        }
        #expect(differs)
        // Windows: drawn once (C# MWC generator, seeded with the current system).
        let w = quietPaper(.windows201)
        var rand = PieterRand(variant: .csharp)
        rand.seed(w.commander.currentSystem, w.commander.days)
        var shown = [false, false, false, false], out: [Headline] = []
        let n = rand.getRandom2(4)
        for _ in 0...n {
            let j = rand.getRandom2(4)
            if !shown[j] { out.append(.canned(government: w.currentSystem.politics, index: j)); shown[j] = true }
        }
        #expect(w.newspaper.headlines == out)
    }

    @Test("NEWS-046 RUL-148 Palm page limit: one line needs y ≤ 128, two lines y ≤ 107 and ≤ 71 characters; C# prints all")
    func pageLimit() {
        let items = (0..<10).map { Headline.canned(government: .anarchy, index: $0 % 4) }
        let paper = Newspaper(system: 0, government: .anarchy, mastheadIndex: 0, headlines: items)
        // One-liners: y = 18, 33, …, 123 print (8 headlines); y = 138 is dropped.
        #expect(paper.applyingPageLimit { _ in HeadlineMetrics(fitsOneLine: true, length: 20) }.count == 8)
        // Two-liners: y = 18, 44, 70, 96 print; y = 122 > 107 is dropped.
        #expect(paper.applyingPageLimit { _ in HeadlineMetrics(fitsOneLine: false, length: 60) }.count == 4)
        // Over 71 characters a two-line headline is dropped without moving y.
        let mixed = Newspaper(system: 0, government: .anarchy, mastheadIndex: 0,
                              headlines: [.hero(index: 0), .villain(index: 1), .hero(index: 2)])
        let kept = mixed.applyingPageLimit { h in
            h == .villain(index: 1) ? HeadlineMetrics(fitsOneLine: false, length: 72) : HeadlineMetrics(fitsOneLine: true, length: 10)
        }
        #expect(kept == [.hero(index: 0), .hero(index: 2)])
        let tight: (Headline) -> HeadlineMetrics = { _ in HeadlineMetrics(fitsOneLine: true, length: 10) }
        let crowded = quietPaper(.palm122) { s in
            s.newsEvents = [.japori, .dragonfly, .scarab, .gemulon]
            s.commander.policeRecordScore = -40
            s.galaxy.systems[s.commander.currentSystem].pressure = .war
        }
        #expect(crowded.newspaperHeadlines(measure: tight) == crowded.newspaper.applyingPageLimit(tight))
        let win = quietPaper(.windows201) { s in s.newsEvents = Array(NewsEvent.allCases.prefix(12)) }
        #expect(win.newspaperHeadlines(measure: tight) == win.newspaper.headlines)
        #expect(win.newspaper.headlines.count > 8)
    }
}

// MARK: Score

@Suite("Score rulesets: Palm formula and endings (SCORE {M5}, RUL-149, RUL-150)")
struct ScoreRulesetTests {
    @Test("SCORE-004 Palm killed in combat: both destroyed → pod if owned, else bothDestroyed and the killed ending")
    func palmKilled() throws {
        let base = encounterEngine(.palm122, .pirateAttack) { s, opp in
            s.commander.ship.hull = 1
            s.commander.ship.weapons = [.militaryLaser]
            opp.weapons = [.militaryLaser, .militaryLaser]
            opp.hull = 1
        }
        let (r, e) = try #require(m4Scan(base, { $0.perform(.encounter(.attack)) }, until: { r, _ in r.events.contains(.bothDestroyed) }))
        #expect(e.state.phase == .gameOver(.killed))
        #expect(r.events.last == .gameEnded(.killed, score: e.state.score(for: .killed)))
        var podded = base
        podded.state.commander.ship.escapePod = true
        let (pr, pe) = try #require(m4Scan(podded, { $0.perform(.encounter(.attack)) }, until: { r, _ in
            r.events.contains { if case .escapePodUsed = $0 { true } else { false } }
        }))
        #expect(!pr.events.contains { if case .gameEnded = $0 { true } else { false } })
        #expect(pe.state.phase == .docked && pe.state.commander.ship.type == .flea)
    }

    @Test("SCORE-008 RUL-006 Modern moon claim after the Princess quest ends as boughtMoonGirl with the moon score; others boughtMoon")
    func moonGirl() {
        for (id, girl) in [(RulesetID.modern, true), (.windows201, false), (.palm122, false)] {
            var e = makeEngine(id) { s in
                s.commander.currentSystem = SystemID.utopia
                s.galaxy.systems[SystemID.utopia].specialEvent = .moonRetirement
                s.quests.moon = QuestStatus.Moon.bought
                s.quests.princess = QuestStatus.Princess.done
            }
            let r = e.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
            let end: GameEndType = girl ? .boughtMoonGirl : .boughtMoon
            #expect(e.state.phase == .gameOver(end))
            #expect(r.events.last == .gameEnded(end, score: e.state.score(for: .boughtMoon)))
            #expect(e.state.score(for: .boughtMoonGirl) == e.state.score(for: .boughtMoon))
        }
        var plain = makeEngine(.modern) { s in
            s.commander.currentSystem = SystemID.utopia
            s.galaxy.systems[SystemID.utopia].specialEvent = .moonRetirement
            s.quests.moon = QuestStatus.Moon.bought
        }
        _ = plain.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        #expect(plain.state.phase == .gameOver(.boughtMoon))
    }

    @Test("SCORE-020 RUL-149 Palm GetScore: killed ×90/50000, retired ×95/50000, moon (W' + dm×1000)/500, times D+1")
    func palmFormula() {
        let s = scored(.palm122, .hard, days: 100, worth: 3_000_000)
        let w = 1_200_000
        #expect(s.score(for: .killed) == 4 * (w * 90 / 50_000))
        #expect(s.score(for: .retired) == 4 * (w * 95 / 50_000))
        #expect(s.score(for: .boughtMoon) == 4 * ((w + 300 * 1_000) / 500))
        // 32-bit wrap of W' × 95 from W' = 22,605,092 (worth 217,050,920); one less still fits.
        let big = scored(.palm122, .normal, worth: 217_050_920)
        let wrapped = Int(Int32(truncatingIfNeeded: 22_605_092 * 95)) / 50_000
        #expect(big.score(for: .retired) == 3 * wrapped && wrapped < 0)
        let fits = scored(.palm122, .normal, worth: 217_050_910)
        #expect(fits.score(for: .retired) == 3 * (22_605_091 * 95 / 50_000))
    }

    @Test("SCORE-025 RUL-149 Palm display tenths = score / 5 (C truncation, negative too); C# tenths are the score")
    func palmTenths() {
        let s = scored(.palm122, .normal, worth: 11_000)
        #expect(s.scoreTenths(for: .killed) == s.score(for: .killed) / 5)
        let neg = scored(.palm122, .normal, worth: -500_000)
        #expect(neg.score(for: .killed) < 0 && neg.scoreTenths(for: .killed) == neg.score(for: .killed) / 5)
        // Palm's display a/50 "." (a%50)/5 equals (a/5)/10 "." (a/5)%10.
        for a in [-1_234, -7, 0, 57, 4_500, 56_050] {
            let t = a / 5
            #expect(a / 50 == t / 10 && (a % 50) / 5 == t % 10)
        }
        let w = scored(.windows201, .normal, worth: 11_000)
        #expect(w.scoreTenths(for: .retired) == w.score(for: .retired))
    }

    @Test("SCORE-028 Palm worked examples")
    func palmExamples() {
        #expect(scored(.palm122, .normal, worth: 11_000).score(for: .killed) == 57)
        #expect(scored(.palm122, .normal, worth: 11_000).scoreTenths(for: .killed) == 11)
        #expect(scored(.palm122, .normal, worth: 11_000).score(for: .retired) == 60)
        #expect(scored(.palm122, .normal, worth: 11_000).scoreTenths(for: .retired) == 12)
        let moon = scored(.palm122, .normal, days: 150, worth: 600_000)
        #expect(moon.score(for: .boughtMoon) == 4_500 && moon.scoreTenths(for: .boughtMoon) == 900)
        let trunc = scored(.palm122, .normal, worth: 6_612)
        #expect(trunc.score(for: .killed) == 33 && trunc.scoreTenths(for: .killed) == 6)
        #expect(scored(.windows201, .normal, worth: 6_612).score(for: .killed) == 7)
        let rich = scored(.palm122, .impossible, worth: 50_000_000)
        #expect(rich.score(for: .retired) == 56_050 && rich.scoreTenths(for: .retired) == 11_210)
    }

    @Test("RUL-150 highScoreBlock: cheats block everywhere (PRD §8.3); Palm also blocks a reloaded game, C# does not")
    func highScoreBlock() {
        for id in RulesetID.allCases {
            var s = makeEngine(id).state
            #expect(!s.highScoreBlocked)
            s.cheatsUsed = true
            #expect(s.highScoreBlocked)
            s.cheatsUsed = false
            s.reloadCount = 1
            #expect(s.highScoreBlocked == (id == RulesetID.palm122))
        }
    }
}
