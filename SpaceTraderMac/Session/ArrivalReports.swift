// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// UI-ENC-054/055: the arrival report's sections, in UX order (identifier `arrival.section.<rawValue>`).
enum ArrivalSectionKind: String, CaseIterable, Sendable {
    case encounters, news, costs, service, tribbles, reactor, debt, police, quests
}

/// A titled list of report lines. `kind` is set for arrival sections; report-sheet sections leave it nil.
struct ReportSection: Equatable, Sendable {
    var title: String
    var lines: [String]
    var kind: ArrivalSectionKind?
}

/// UI-ENC-054: the arrival report (sections in UX order, empty ones omitted). Built by `make(trip:after:)`.
struct ArrivalReport: Equatable, Sendable {
    var system = 0
    var systemName = ""
    /// ALR-165: the fabric rip, the report's first line.
    var fabricRip: String?
    var encounters: [EncounterSummary] = []
    var sections: [ReportSection] = []
    /// Cash after the trip minus cash before it.
    var cashChange = 0

    var summary: String { ArrivalText.summary(system: systemName, encounters: encounters.count, cashChange: cashChange) }

    func section(_ kind: ArrivalSectionKind) -> ReportSection? { sections.first { $0.kind == kind } }

    static func make(trip: Trip, after: GameState) -> ArrivalReport {
        var r = ArrivalReport()
        r.system = trip.destination
        r.systemName = Names.system(trip.destination, in: after)
        r.fabricRip = trip.fabricRip.map { ArrivalText.fabricRip(Names.system($0, in: after)) }
        r.encounters = trip.encounters
        r.cashChange = after.commander.cash - trip.before.commander.cash
        func add(_ kind: ArrivalSectionKind, _ lines: [String]) {
            guard !lines.isEmpty else { return }
            r.sections.append(ReportSection(title: ArrivalText.sectionTitle(kind), lines: lines, kind: kind))
        }
        func lines(_ test: (GameEvent) -> Bool) -> [String] {
            trip.events.filter(test).map { ArrivalText.eventLine($0, state: after) }
        }
        // 1. Encounters (ALR-168 when there were none).
        add(.encounters, trip.encounters.isEmpty ? [ArrivalText.uneventfulTrip] : trip.encounters.map(ArrivalText.encounterLine))
        // 2. News teaser (UI-ENC-063).
        add(.news, [NewsTeaser.make(state: after).text])
        // 3. Departure costs (UI-ENC-051).
        let c = trip.departureCosts
        var costs: [String] = []
        if c.mercenaries > 0 { costs.append(ArrivalText.cost(.mercenaries, c.mercenaries)) }
        if c.insurance > 0 { costs.append(ArrivalText.cost(.insurance, c.insurance)) }
        if c.interest > 0 { costs.append(ArrivalText.cost(.interest, c.interest)) }
        if c.wormholeTax > 0 { costs.append(ArrivalText.cost(.wormholeTax, c.wormholeTax)) }
        if c.total > 0 { costs.append(ArrivalText.cost(.total, c.total)) }
        add(.costs, costs)
        // 4. Automatic repairs and fuel (ALR-007, -008, -010).
        add(.service, lines {
            switch $0 {
            case .boughtFuel, .repairedHull, .autoFuelFailed, .autoRepairFailed: true
            default: false
            }
        })
        // 5. Tribbles (ALR-169, 170, 172, 174, 177).
        add(.tribbles, lines {
            switch $0 {
            case .tribblesChanged, .tribblesDied, .tribblesAteFood, .tribbleInspectorWarning: true
            default: false
            }
        })
        // 6. Reactor (ALR-131…133).
        add(.reactor, lines { if case .reactorWarning = $0 { true } else { false } })
        // 7. Debt (ALR-029, -033).
        add(.debt, lines {
            switch $0 {
            case .debtWarning, .debtReminder: true
            default: false
            }
        })
        // 8. Police record.
        var police: [String] = []
        let recordBefore = trip.before.policeRecord, recordAfter = after.policeRecord
        if recordBefore != recordAfter { police.append(ArrivalText.policeRecord(from: recordBefore, to: recordAfter)) }
        police += lines { if case .caughtLittering = $0 { true } else { false } }
        let repBefore = trip.before.reputation, repAfter = after.reputation
        if repBefore != repAfter { police.append(ArrivalText.reputation(from: repBefore, to: repAfter)) }
        add(.police, police)
        // 9. Quest progress: quest events, then the quest list difference (UI-SHELL-121).
        var quests = lines {
            switch $0 {
            case .gemulonInvaded, .experimentPerformed, .wildLeftShip, .easterEgg, .easterEggNoShieldSlot, .passengerConcerned,
                 .passengerImpatient:
                true
            default: false
            }
        }
        quests += QuestLogDiff.lines(before: trip.before, after: after)
        add(.quests, quests)
        return r
    }

    /// The report with the reactor section first (the critical temperature warning, ALR-133).
    func reactorFirst() -> ArrivalReport {
        var r = self
        if let i = r.sections.firstIndex(where: { $0.kind == .reactor }) {
            let reactor = r.sections.remove(at: i)
            r.sections.insert(reactor, at: 0)
        }
        return r
    }
}

/// The quest list's difference across a trip: entries added and closed (UI-ENC-054 item 9).
enum QuestLogDiff {
    static func lines(before: GameState, after: GameState) -> [String] {
        let old = Dictionary(before.questLog.map { (family($0.kind), $0.kind) }, uniquingKeysWith: { a, _ in a })
        let new = Dictionary(after.questLog.map { (family($0.kind), $0.kind) }, uniquingKeysWith: { a, _ in a })
        let added = after.questLog.filter { old[family($0.kind)] == nil }
            .map { ArrivalText.questAdded(QuestText.string(for: $0.kind, state: after)) }
        let removed = before.questLog.filter { new[family($0.kind)] == nil }
            .map { ArrivalText.questRemoved(QuestText.string(for: $0.kind, state: before)) }
        return added + removed
    }

    /// The quest an entry belongs to, ignoring day counts and impatience (so a ticking deadline is not a change).
    static func family(_ kind: QuestLogKind) -> String {
        var name = String(describing: kind)
        if let paren = name.firstIndex(of: "(") { name = String(name[..<paren]) }
        for suffix in ["Impatient", "Tomorrow", "Days"] where name.hasSuffix(suffix) { name.removeLast(suffix.count) }
        return name
    }
}

/// UI-ENC-063: the news teaser. It shows a headline only when the paper of this visit is paid.
struct NewsTeaser: Equatable, Sendable {
    var headline: String?
    var price: Int

    var text: String { headline ?? ArrivalText.newspaperPrice(price) }

    static func make(state: GameState) -> NewsTeaser {
        let first = state.newspaperPreview.flatMap { _ in NewspaperText.shownHeadlines(state: state).first }
        return NewsTeaser(headline: first.map { NewspaperText.headline($0, state: state) }, price: state.newspaperCost)
    }
}

/// The ALR rows a report sheet can show (one `ReportSection` each, C# texts in `ReportText`).
enum ReportAlert: Equatable, Sendable {
    case arrested, convicted(term: Int, fine: Int), hiddenCompartmentsRemoved, reactorConfiscated, sculptureConfiscated
    case wildArrested, illegalGoodsImpounded, insuranceLost, mercenariesLeave, jarekTakenHome, princessTakenHome
    case antidoteTaken, shipSold, tribblesRemoved, fleaBuilt
    case escapePodActivated, sculptureSaved, reactorDestroyed, tribblesKilled, antidoteDestroyed(system: String), artifactLost
    case insurancePayoff(Int), reactorMeltdown, shipDestroyed, reactorWarningTemperature
}

/// Mercenaries aboard (crew other than the commander and the special passengers).
private func mercenaryCount(_ s: GameState) -> Int {
    let special: Set<Int> = [CrewID.commander, CrewID.jarek, CrewID.princess, CrewID.wild]
    return s.commander.ship.crew.compactMap { $0 }.filter { !special.contains($0) }.count
}

/// UI-ENC-059: the arrest report (one section per arrest-sequence ALR row that applies, C# order), then the arrival.
struct ArrestReport: Equatable, Sendable {
    var sections: [ReportSection] = []
    var arrival: ArrivalReport?

    static func alerts(before: GameState, after: GameState, events: [GameEvent]) -> [ReportAlert] {
        guard let (term, fine, shipSold) = events.lazy.compactMap({ e -> (Int, Int, Bool)? in
            if case let .arrested(term, fine, sold) = e { return (term, fine, sold) }
            return nil
        }).first else { return [] }
        var a: [ReportAlert] = [.arrested, .convicted(term: term, fine: fine)]
        if before.commander.ship.has(.hiddenCargoBays), !after.commander.ship.has(.hiddenCargoBays) { a.append(.hiddenCompartmentsRemoved) }
        if before.reactorOnBoard, !after.reactorOnBoard { a.append(.reactorConfiscated) }
        if before.sculptureOnBoard, !after.sculptureOnBoard { a.append(.sculptureConfiscated) }
        if before.wildOnBoard, !after.wildOnBoard { a.append(.wildArrested) }
        if before.commander.ship.illegalCargoUnits > 0, after.commander.ship.illegalCargoUnits == 0 { a.append(.illegalGoodsImpounded) }
        if before.commander.insurance, !after.commander.insurance { a.append(.insuranceLost) }
        if mercenaryCount(before) > 0, mercenaryCount(after) == 0 { a.append(.mercenariesLeave) }
        if before.jarekOnBoard, !after.jarekOnBoard { a.append(.jarekTakenHome) }
        if before.princessOnBoard, !after.princessOnBoard { a.append(.princessTakenHome) }
        if before.quests.japori == QuestStatus.Japori.inTransit, after.quests.japori != QuestStatus.Japori.inTransit {
            a.append(.antidoteTaken)
        }
        if shipSold {
            a.append(.shipSold)
            if before.commander.ship.tribbles > 0, after.commander.ship.tribbles == 0 { a.append(.tribblesRemoved) }
            a.append(.fleaBuilt)
        }
        return a
    }

    static func make(before: GameState, after: GameState, events: [GameEvent]) -> ArrestReport {
        ArrestReport(sections: alerts(before: before, after: after, events: events).map(ReportText.section))
    }
}

/// UI-ENC-060: the escape-pod report (C# `EscapeWithPod` order), then the arrival.
struct EscapePodReport: Equatable, Sendable {
    var sections: [ReportSection] = []
    var arrival: ArrivalReport?

    static func alerts(before: GameState, after: GameState, events: [GameEvent]) -> [ReportAlert] {
        guard let payout = events.lazy.compactMap({ e -> Int? in
            if case let .escapePodUsed(p) = e { return p }
            return nil
        }).first else { return [] }
        let meltdown = events.contains(.reactorMeltdown)
        var a: [ReportAlert] = [.escapePodActivated]
        if before.sculptureOnBoard { a.append(.sculptureSaved) }
        // After a meltdown the reactor is already gone; the meltdown section tells it (ALR-130).
        if before.reactorOnBoard, !meltdown { a.append(.reactorDestroyed) }
        if before.commander.ship.tribbles > 0, after.commander.ship.tribbles == 0 { a.append(.tribblesKilled) }
        if before.quests.japori == QuestStatus.Japori.inTransit, after.quests.japori != QuestStatus.Japori.inTransit {
            let system = after.galaxy.systems.firstIndex { $0.specialEvent == .japori }.map { Names.system($0, in: after) } ?? ""
            a.append(.antidoteDestroyed(system: system))
        }
        if before.artifactOnBoard, !after.artifactOnBoard { a.append(.artifactLost) }
        if before.jarekOnBoard, !after.jarekOnBoard { a.append(.jarekTakenHome) }
        if before.princessOnBoard, !after.princessOnBoard { a.append(.princessTakenHome) }
        if before.wildOnBoard, !after.wildOnBoard { a.append(.wildArrested) }
        if payout > 0 { a.append(.insurancePayoff(payout)) }
        a.append(.fleaBuilt)
        return a
    }

    static func make(before: GameState, after: GameState, events: [GameEvent]) -> EscapePodReport {
        EscapePodReport(sections: alerts(before: before, after: after, events: events).map(ReportText.section))
    }
}

/// UI-ENC-060: the reactor meltdown (ALR-130), then the escape-pod sections, or the destroyed ship when the game ended.
struct ReactorReport: Equatable, Sendable {
    var sections: [ReportSection] = []
    var arrival: ArrivalReport?

    static func alerts(before: GameState, after: GameState, events: [GameEvent]) -> [ReportAlert] {
        guard events.contains(.reactorMeltdown) else { return [] }
        let pod = EscapePodReport.alerts(before: before, after: after, events: events)
        return [.reactorMeltdown] + (pod.isEmpty ? [.shipDestroyed] : pod)
    }

    static func make(before: GameState, after: GameState, events: [GameEvent]) -> ReactorReport {
        ReactorReport(sections: alerts(before: before, after: after, events: events).map(ReportText.section))
    }
}

/// UI-ENC-056: how a finished trip is shown.
enum ArrivalPresentation: Equatable, Sendable {
    /// The non-modal card at the top of Bridge (UI-ENC-055).
    case card(ArrivalReport)
    /// A report sheet: a critical event, or the "Sheet" arrival style (UI-ENC-057).
    case sheet(ReportSheet)
    /// The trip ended the game: the game-over card takes over (UI-ENC-082).
    case gameOver

    static func decide(trip: Trip, style: ArrivalReportStyle) -> ArrivalPresentation {
        if trip.end == .gameOver { return .gameOver }
        let arrival = ArrivalReport.make(trip: trip, after: trip.after)
        let events = trip.allEvents
        if events.contains(.reactorMeltdown) {
            var r = ReactorReport.make(before: trip.before, after: trip.after, events: events)
            r.arrival = arrival
            return .sheet(.reactorMeltdown(r))
        }
        if trip.contains({ if case .escapePodUsed = $0 { true } else { false } }) {
            var r = EscapePodReport.make(before: trip.before, after: trip.after, events: events)
            r.arrival = arrival
            return .sheet(.escapePod(r))
        }
        if trip.contains({ if case .arrested = $0 { true } else { false } }) {
            var r = ArrestReport.make(before: trip.before, after: trip.after, events: events)
            r.arrival = arrival
            return .sheet(.arrest(r))
        }
        if events.contains(.reactorWarning(status: ReactorStatus.temperatureWarning)) {
            return .sheet(.arrival(arrival.reactorFirst()))
        }
        return style == .sheet ? .sheet(.arrival(arrival)) : .card(arrival)
    }
}

extension ReportSheet {
    /// The sections a report sheet shows: the critical sections first, then the arrival sections (UI-ENC-057).
    var criticalSections: [ReportSection] {
        switch self {
        case .arrival: []
        case let .arrest(r): r.sections
        case let .escapePod(r): r.sections
        case let .reactorMeltdown(r): r.sections
        }
    }

    var arrival: ArrivalReport? {
        switch self {
        case let .arrival(r): r
        case let .arrest(r): r.arrival
        case let .escapePod(r): r.arrival
        case let .reactorMeltdown(r): r.arrival
        }
    }
}
