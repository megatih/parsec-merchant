// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// UI-ENC-064: the feed's category of an entry.
enum FeedCategory: String, CaseIterable, Sendable {
    case trade, travel, encounter, combat, police, quest, comm, finance, crew, ship, news, system

    /// The SF Symbol shown before a row of this category (UI-ENC-065).
    var symbol: String {
        switch self {
        case .trade: "cart"
        case .travel: "airplane"
        case .encounter: "binoculars"
        case .combat: "scope"
        case .police: "shield.lefthalf.filled"
        case .quest: "sparkles"
        case .comm: "antenna.radiowaves.left.and.right"
        case .finance: "banknote"
        case .crew: "person.2"
        case .ship: "wrench.and.screwdriver"
        case .news: "newspaper"
        case .system: "gearshape"
        }
    }
}

/// UI-ENC-064: how loud a feed entry is. `critical` is exactly the ALR "GameEvent (critical)" set.
enum FeedSeverity: Int, CaseIterable, Comparable, Sendable {
    case info, notice, warning, critical

    static func < (a: FeedSeverity, b: FeedSeverity) -> Bool { a.rawValue < b.rawValue }

    /// The extra symbol of a `warning` or `critical` row (color is never the only signal, UX-VISION §1.7).
    var badgeSymbol: String? {
        switch self {
        case .info, .notice: nil
        case .warning: "exclamationmark.triangle"
        case .critical: "exclamationmark.octagon.fill"
        }
    }
}

/// UI-ENC-064: the presentation class of one feed entry.
struct FeedStyle: Equatable, Sendable {
    var category: FeedCategory
    var severity: FeedSeverity
    var symbol: String { category.symbol }

    init(_ category: FeedCategory, _ severity: FeedSeverity = .info) {
        self.category = category
        self.severity = severity
    }

    static func classify(_ entry: FeedItem.Entry) -> FeedStyle {
        switch entry {
        case let .event(e): classify(e)
        case let .note(n): classify(n)
        }
    }

    static func classify(_ note: FeedNote) -> FeedStyle {
        switch note {
        case .gameSaved: FeedStyle(.system)
        case .recoveredFromBackup: FeedStyle(.system, .warning)
        }
    }

    static func classify(_ event: GameEvent) -> FeedStyle {
        switch event {
        // Critical (ALR §2 "GameEvent (critical)").
        case .arrested: return FeedStyle(.police, .critical)
        case .escapePodUsed, .playerDestroyed, .bothDestroyed: return FeedStyle(.combat, .critical)
        case .reactorMeltdown: return FeedStyle(.quest, .critical)
        case let .reactorWarning(status):
            return FeedStyle(.quest, status == ReactorStatus.temperatureWarning ? .critical : .warning)
        case .gameEnded: return FeedStyle(.system, .critical)
        // Trade.
        case .boughtCargo, .soldCargo, .dumpedCargo, .jettisonedCargo, .orbitTradeCompleted, .plundered, .scooped:
            return FeedStyle(.trade)
        case .scoopNoRoom, .cannotAffordAllTransfers: return FeedStyle(.trade, .notice)
        // Travel.
        case .departed, .arrived, .uneventfulTrip: return FeedStyle(.travel)
        case .fabricRip, .singularityLost: return FeedStyle(.travel, .warning)
        case .departureBlocked: return FeedStyle(.travel, .notice)
        // Encounters and combat.
        case .encounterStarted, .encounterChanged: return FeedStyle(.encounter, .notice)
        case .tonicConsumed, .captainTraining: return FeedStyle(.encounter)
        case .combatRound, .playerAttacked, .playerFled, .opponentEscaped, .playerEscaped, .opponentDisabled:
            return FeedStyle(.combat)
        case .opponentDestroyed, .bountyPaid: return FeedStyle(.combat, .notice)
        case .looted, .blackmailed, .sculptureTaken, .wildJoinedPirates, .artifactRelinquished: return FeedStyle(.combat, .warning)
        case .preciousHidden: return FeedStyle(.combat)
        // Police.
        case .bribed, .inspectionClean, .yielded: return FeedStyle(.police)
        case .fined, .caughtLittering, .reactorConfiscated: return FeedStyle(.police, .warning)
        // Finance.
        case .borrowed, .repaid, .insuranceBought, .insuranceStopped: return FeedStyle(.finance)
        case .debtReminder: return FeedStyle(.finance, .notice)
        case .debtWarning, .autoFuelFailed, .autoRepairFailed: return FeedStyle(.finance, .warning)
        // Crew and passengers.
        case .hired, .fired: return FeedStyle(.crew)
        case .passengerConcerned: return FeedStyle(.comm, .notice)
        case .passengerImpatient: return FeedStyle(.comm, .warning)
        // Ship and equipment.
        case .boughtFuel, .repairedHull, .boughtEquipment, .soldEquipment, .boughtShip, .customShipBuilt, .boughtEscapePod:
            return FeedStyle(.ship)
        case .cannotTransfer, .cannotAffordTransfer: return FeedStyle(.ship, .notice)
        // Quests and special events.
        case .tribblesChanged, .tribblesAteFood, .gemulonInvaded, .experimentPerformed, .wildLeftShip, .easterEgg,
             .easterEggNoShieldSlot, .specialEventCompleted, .sealedCanisters:
            return FeedStyle(.quest)
        case .tribblesDied, .tribbleInspectorWarning, .specialEventRefused: return FeedStyle(.quest, .notice)
        // System.
        case .gameStarted, .optionsChanged, .cheatReadout: return FeedStyle(.system)
        case .cheatUsed: return FeedStyle(.system, .warning)
        }
    }
}

/// UI-ENC-066: passenger chatter as a "Ship's comm" line (the C# `SpecialPassenger…` alert texts).
enum PassengerComm {
    static func message(crewID: Int, impatient: Bool) -> LocalizedStringResource {
        switch (crewID, impatient) {
        case (CrewID.jarek, false): "Commander? Jarek here. Do you require any assitance in charting a course to Devidia?"
        case (CrewID.princess, false): "[Ziyal] Oh Captain? (giggles) Would it help if I got out and pushed?"
        case (CrewID.wild, false): "Bridge? This is Jonathan. Are we there yet? Heh, heh. Sorry, I couldn't resist."
        case (CrewID.jarek, true): "Captain! This is the Ambassador speaking. We should have been there by now?!"
        case (CrewID.princess, true): "Sir! Are you taking me home or merely taking the place of my previous captors?!"
        case (CrewID.wild, true): "Commander! Wild here. What's taking us so long?!"
        case (_, false): "Are we there yet?"
        case (_, true): "What's taking us so long?!"
        }
    }

    /// "Ship's comm — <name>: …".
    static func line(crewID: Int, impatient: Bool, state: GameState) -> String {
        let name = Names.crew(crewID, in: state)
        let text = String(localized: message(crewID: crewID, impatient: impatient))
        return String(localized: "Ship's comm — \(name): \(text)")
    }
}

/// The feed's text of an entry: `EventText`, except passenger chatter, which is a comm line (UI-ENC-066).
enum FeedText {
    static func text(for entry: FeedItem.Entry, state: GameState) -> String {
        switch entry {
        case let .event(.passengerConcerned(id)): PassengerComm.line(crewID: id, impatient: false, state: state)
        case let .event(.passengerImpatient(id)): PassengerComm.line(crewID: id, impatient: true, state: state)
        default: String(localized: EventText.text(for: entry, state: state))
        }
    }
}

/// UI-ENC-065: the feed overlay's rows: "Day N · <system>" groups, newest first, with consecutive combat rounds of one
/// encounter collapsed into one expandable row.
struct FeedGroup: Equatable, Sendable, Identifiable {
    enum Row: Equatable, Sendable, Identifiable {
        case item(FeedItem)
        /// Consecutive `combatRound` items (oldest first); `opponent` is the encounter's ship when known.
        case rounds([FeedItem], opponent: ShipType?)

        var id: Int {
            switch self {
            case let .item(i): i.id
            case let .rounds(items, _): items.first?.id ?? -1
            }
        }
    }

    var day: Int
    var systemIndex: Int
    var rows: [Row]

    var id: String { "\(day).\(systemIndex)" }

    /// Groups `feed` (oldest first) into day/system groups, newest group first and newest row first within a group.
    static func make(_ feed: [FeedItem], limit: Int = 200) -> [FeedGroup] {
        let items = Array(feed.suffix(limit))
        // Opponent of each item: the last `encounterStarted` before it (the feed keeps every event in order).
        var opponent: ShipType?
        var groups: [FeedGroup] = []
        var pendingRounds: [FeedItem] = []
        var pendingOpponent: ShipType?

        func flushRounds() {
            guard !pendingRounds.isEmpty else { return }
            let row: Row = pendingRounds.count == 1 ? .item(pendingRounds[0]) : .rounds(pendingRounds, opponent: pendingOpponent)
            groups[groups.count - 1].rows.append(row)
            pendingRounds = []
        }

        for item in items {
            if groups.last.map({ $0.day != item.day || $0.systemIndex != item.systemIndex }) ?? true {
                if !groups.isEmpty { flushRounds() }
                groups.append(FeedGroup(day: item.day, systemIndex: item.systemIndex, rows: []))
            }
            switch item.event {
            case let .encounterStarted(_, ship, _, _)?:
                flushRounds()
                opponent = ship
                groups[groups.count - 1].rows.append(.item(item))
            case .combatRound?:
                if pendingRounds.isEmpty { pendingOpponent = opponent }
                pendingRounds.append(item)
            default:
                flushRounds()
                groups[groups.count - 1].rows.append(.item(item))
            }
        }
        if !groups.isEmpty { flushRounds() }
        return groups.reversed().map { FeedGroup(day: $0.day, systemIndex: $0.systemIndex, rows: $0.rows.reversed()) }
    }
}

/// UI-ENC-067: new feed items never open the overlay or take focus while the Encounter or Transit view is shown; the
/// overlay opens only from a click on `status.feed`.
enum FeedOverlayPolicy {
    static func opensAutomatically(for detail: DetailMode) -> Bool {
        switch detail {
        case .transit, .encounter, .gameOver, .section: false
        }
    }
}
