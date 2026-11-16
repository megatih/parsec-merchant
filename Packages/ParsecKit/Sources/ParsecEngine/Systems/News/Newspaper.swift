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

    /// C# `NewspaperHead`/`NewspaperText`: deterministic for a system and day (PieterRand seeded with system, days).
    var newspaper: Newspaper {
        let cur = currentSystem
        var rand = PieterRand(variant: ruleset.newspaperRNG)
        rand.seed(cur.id, commander.days)
        var items: [Headline] = newsEvents.map { .event($0) }
        if cur.pressure != .none { items.append(.internalPressure(cur.pressure)) }
        if commander.policeRecordScore <= -70 {
            items.append(.villain(index: rand.getRandom2(NewsTables.villainCount)))
        } else if commander.policeRecordScore >= 75 {
            items.append(.hero(index: rand.getRandom2(NewsTables.heroCount)))
        }
        var realNews = false
        let threshold = 6 * cur.techLevel.rawValue + 10 * (5 - difficulty.rawValue)
        for i in galaxy.systems.indices where destinationOK(i) && i != cur.id {
            let s = galaxy.systems[i]
            if s.specialEvent == .moon { items.append(.moonForSale(system: i)) }
            if s.specialEvent == .tribbleBuyer { items.append(.tribbleBuyer(system: i)) }
            if s.shipyard != nil { items.append(.shipyard(system: i)) }
            if s.pressure != .none, rand.getRandom2(100) <= threshold {
                let t = rand.getRandom2(NewsTables.externalTemplates)
                items.append(.externalPressure(template: t, pressure: s.pressure, system: i))
                realNews = true
            }
        }
        if !realNews {
            var shown = [Bool](repeating: false, count: NewsTables.cannedPerGovernment)
            let toShow = rand.getRandom2(NewsTables.cannedPerGovernment)
            for _ in 0...toShow {
                let index = rand.getRandom2(NewsTables.cannedPerGovernment)
                if !shown[index] {
                    items.append(.canned(government: cur.politics, index: index))
                    shown[index] = true
                }
            }
        }
        return Newspaper(system: cur.id, government: cur.politics, mastheadIndex: cur.id % NewsTables.mastheadsPerGovernment,
                         headlines: items)
    }
}

extension GameEngine {
    /// NEWS: buy (once per visit) and read the newspaper. Two-phase unless auto-pay is on.
    mutating func readNewspaper(_ ack: Set<WarningID>) -> StepResult {
        guard docked else { return .rejected(.notAllowedInPhase) }
        if !state.paidForNewspaper {
            let cost = state.newspaperCost
            if state.commander.cash < cost { return .rejected(.insufficientFunds) }
            if !state.options.newsAutoPay, !ack.contains(.buyNewspaper) {
                return .needsConfirmation(Confirmation(.buyNewspaper, amounts: [cost]))
            }
            state.commander.cash -= cost
            state.paidForNewspaper = true
        }
        return StepResult(events: [], decision: .newspaper(state.newspaper), rejection: nil)
    }
}
