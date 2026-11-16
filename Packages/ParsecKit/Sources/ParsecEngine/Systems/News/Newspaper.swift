// SPDX-License-Identifier: GPL-2.0-or-later
// The newspaper (docs/specs/NEWS.md): typed headlines; the app formats the text from its string tables.
// C# Game.NewspaperHead / NewspaperText / ShowNewspaper.

/// One newspaper item. Indices refer to the classic string tables (Strings.cs), which the app owns.
public enum Headline: Codable, Sendable, Equatable {
    /// A news event of this trip (Strings.NewsEvent[event]).
    case event(NewsEvent)
    /// The current system's own pressure (Strings.NewsPressureInternal[pressure]).
    case internalPressure(SystemPressure)
    /// Villain story (Strings.NewsPoliceRecordPsychopath[index]).
    case villain(index: Int)
    /// Hero story (Strings.NewsPoliceRecordHero[index]).
    case hero(index: Int)
    case moonForSale(system: Int)
    case tribbleBuyer(system: Int)
    case shipyard(system: Int)
    /// A distant system's pressure (Strings.NewsPressureExternal[template] with NewsPressureExternalPressures[pressure]).
    case externalPressure(template: Int, pressure: SystemPressure, system: Int)
    /// A canned headline for the government (Strings.NewsHeadlines[government][index]).
    case canned(government: PoliticalSystemType, index: Int)
}

/// A composed newspaper.
public struct Newspaper: Codable, Sendable, Equatable {
    public var system: Int
    public var government: PoliticalSystemType
    /// Strings.NewsMastheads[government][mastheadIndex].
    public var mastheadIndex: Int
    public var headlines: [Headline]
}

public enum NewsTables {
    public static let villainCount = 4
    public static let heroCount = 3
    public static let externalTemplates = 6
    public static let cannedPerGovernment = 4
    public static let mastheadsPerGovernment = 3
}

public extension GameState {
    /// NEWS: the newspaper price (difficulty + 1), paid once per visit.
    var newspaperCost: Int { difficulty.rawValue + 1 }

    /// NEWS-009: the paper once paid for in this visit, else nil.
    var newspaperPreview: Newspaper? { paidForNewspaper ? newspaper : nil }

    /// C# `NewspaperHead`/`NewspaperText` (deterministic for a system and day); Palm `DrawNewspaperForm` per the
    /// news flags of RUL-144…148 and NEWS §5. Palm's page limit is applied separately (`newspaperHeadlines(measure:)`).
    var newspaper: Newspaper {
        let tr = ruleset.flags.travel
        let cur = currentSystem
        let seedSystem = tr.newsSeedSystem == .warpSystem ? warpSystem : cur.id
        var rand = PieterRand(variant: ruleset.newspaperRNG)
        rand.seed(seedSystem, commander.days)
        var items: [Headline] = tr.newsEventOrdering == .palmFixed ? palmEventHeadlines.map { .event($0) }
            : newsEvents.map { .event($0) }
        if cur.pressure != .none { items.append(.internalPressure(cur.pressure)) }
        let record = commander.policeRecordScore
        if record <= tr.newsVillainThreshold {
            items.append(.villain(index: rand.getRandom2(NewsTables.villainCount)))
        }
        if tr.newsHeroRule == .atLeast ? record >= 75 : record == 75 {
            items.append(.hero(index: rand.getRandom2(NewsTables.heroCount)))
        }
        // NEWS-043: Palm prints the littering story after the hero/villain step.
        if tr.newsEventOrdering == .palmFixed, newsEvents.contains(.caughtLittering) { items.append(.event(.caughtLittering)) }
        var realNews = false
        let threshold = 6 * cur.techLevel.rawValue + 10 * (5 - difficulty.rawValue)
        for i in galaxy.systems.indices where i != cur.id && distantNewsEligible(i) {
            let s = galaxy.systems[i]
            if s.specialEvent == .moon { items.append(.moonForSale(system: i)) }
            if s.specialEvent == .tribbleBuyer { items.append(.tribbleBuyer(system: i)) }
            if tr.newsDistantRange == .destinationOK, s.shipyard != nil { items.append(.shipyard(system: i)) }
            if s.pressure != .none, rand.getRandom2(100) <= threshold {
                let t = rand.getRandom2(NewsTables.externalTemplates)
                items.append(.externalPressure(template: t, pressure: s.pressure, system: i))
                realNews = true
            }
        }
        if !realNews {
            var shown = [Bool](repeating: false, count: NewsTables.cannedPerGovernment)
            func canned(_ index: Int) {
                guard !shown[index] else { return }
                items.append(.canned(government: cur.politics, index: index))
                shown[index] = true
            }
            switch tr.newsCannedBound {
            case .drawnOnce:
                let toShow = rand.getRandom2(NewsTables.cannedPerGovernment)
                for _ in 0...toShow { canned(rand.getRandom2(NewsTables.cannedPerGovernment)) }
            case .redrawnEachPass:
                var k = 0
                while k <= rand.getRandom2(NewsTables.cannedPerGovernment) {
                    canned(rand.getRandom2(NewsTables.cannedPerGovernment))
                    k += 1
                }
            }
        }
        return Newspaper(system: cur.id, government: cur.politics, mastheadIndex: seedSystem % NewsTables.mastheadsPerGovernment,
                         headlines: items)
    }

    /// RUL-146: C# `DestOk`; Palm base tank range or wormhole, and only systems with a status.
    private func distantNewsEligible(_ i: Int) -> Bool {
        switch ruleset.flags.travel.newsDistantRange {
        case .destinationOK:
            return destinationOK(i)
        case .baseTanksWithStatus:
            let d = GalaxyGenerator.distance(currentSystem, galaxy.systems[i], rule: ruleset.flags.distance)
            return (d <= commander.ship.spec(ruleset).fuelTanks || galaxy.wormholeExists(from: commander.currentSystem, to: i))
                && galaxy.systems[i].pressure != .none
        }
    }

    /// NEWS-041: Palm's fixed event-headline order; stored flags are tested for membership only.
    private var palmEventHeadlines: [NewsEvent] {
        let has = Set(newsEvents), q = quests, special = currentSystem.specialEvent
        var out: [NewsEvent] = []
        func add(_ e: NewsEvent, _ when: Bool? = nil) { if when ?? has.contains(e) { out.append(e) } }
        for e: NewsEvent in [.captHuieAttacked, .experimentPerformed, .captHuieDestroyed, .captAhabAttacked, .captAhabDestroyed,
                             .captConradAttacked, .captConradDestroyed, .spaceMonsterKilled, .wildArrested] { add(e) }
        add(.spaceMonster, special == .spaceMonsterKilled && q.spaceMonster == QuestStatus.SpaceMonster.atAcamar)
        add(.scarabHarass, special == .scarabDestroyed && q.scarab == QuestStatus.Scarab.hunting)
        for e: NewsEvent in [.experimentStopped, .experimentFailed, .dragonfly, .scarab, .dragonflyBaratas, .dragonflyMelina,
                             .dragonflyRegulas] { add(e) }
        add(.dragonflyZalkon, special == .dragonflyDestroyed && q.dragonfly == QuestStatus.Dragonfly.flyZalkon
            && !has.contains(.dragonflyDestroyed))
        for e: NewsEvent in [.dragonflyDestroyed, .scarabDestroyed, .japoriDelivery, .japori, .artifactDelivery, .jarekGetsOut,
                             .wildGetsOut, .gemulonRescued] { add(e) }
        add(.gemulonInvaded, special == .gemulonRescued && !has.contains(.gemulonRescued))
        add(.gemulon)
        add(.experimentArrival)
        return out
    }

    /// The headlines the reader sees: Palm drops what does not fit the page (RUL-148); `measure` comes from the app,
    /// which owns the text and its font metrics.
    func newspaperHeadlines(measure: (Headline) -> HeadlineMetrics) -> [Headline] {
        let paper = newspaper
        return ruleset.flags.travel.newsPageLimit ? paper.applyingPageLimit(measure) : paper.headlines
    }
}

/// How one headline lays out on the Palm page (NEWS-046).
public struct HeadlineMetrics: Sendable, Equatable {
    /// The text fits one line (148 px in Palm's font).
    public var fitsOneLine: Bool
    /// Character count (a two-line headline over 71 characters is dropped).
    public var length: Int

    public init(fitsOneLine: Bool, length: Int) {
        self.fitsOneLine = fitsOneLine
        self.length = length
    }
}

public extension Newspaper {
    /// Palm `DisplayHeadline` page rule (NEWS-046): y starts at 18; one line needs y ≤ 128 (+15), two lines need
    /// y ≤ 107 and ≤ 71 characters (+26). Dropped headlines change nothing else (their draws were already made).
    func applyingPageLimit(_ measure: (Headline) -> HeadlineMetrics) -> [Headline] {
        var y = 18
        var out: [Headline] = []
        for h in headlines {
            let m = measure(h)
            if m.fitsOneLine {
                guard y <= 128 else { continue }
                y += 15
            } else {
                guard y <= 107, m.length <= 71 else { continue }
                y += 26
            }
            out.append(h)
        }
        return out
    }
}

extension GameEngine {
    /// NEWS: buy (once per visit) and read the newspaper. Two-phase unless auto-pay is on.
    mutating func readNewspaper(_ ack: Set<WarningID>) -> StepResult {
        guard docked else { return .rejected(.notAllowedInPhase) }
        if !state.paidForNewspaper {
            let cost = state.newspaperCost
            let funds = ruleset.flags.travel.newspaperUsesCashToSpend ? state.cashToSpend : state.commander.cash
            if funds < cost { return .rejected(.insufficientFunds) }
            if !state.options.newsAutoPay, !ack.contains(.buyNewspaper) {
                return .needsConfirmation(Confirmation(.buyNewspaper, amounts: [cost]))
            }
            state.commander.cash -= cost
            state.paidForNewspaper = true
        }
        return StepResult(events: [], decision: .newspaper(state.newspaper), rejection: nil)
    }
}
