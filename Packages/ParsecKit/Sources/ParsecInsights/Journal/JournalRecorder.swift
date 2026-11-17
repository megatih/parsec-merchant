// SPDX-License-Identifier: GPL-2.0-or-later
// Recording steps into the journal (docs/specs/LOG.md §3, LOG-013…018; INT-008…011; ACH-006; LLM-008).
// Pure: no RNG, no clock, no locale, no Hasher. The output depends only on the journal and the step.
import ParsecEngine

/// LOG-013: one accepted step (built from the app's `StepRecord`).
public struct JournalStep: Sendable, Equatable {
    public var command: Command
    public var before: GameState
    public var result: StepResult
    public var after: GameState

    public init(command: Command, before: GameState, result: StepResult, after: GameState) {
        self.command = command
        self.before = before
        self.result = result
        self.after = after
    }
}

/// LOG-013: what a step added.
public struct JournalStepOutput: Sendable, Equatable {
    public var newEntries: [LogEntry]
    public var unlocked: [AchievementID]

    public init(newEntries: [LogEntry] = [], unlocked: [AchievementID] = []) {
        self.newEntries = newEntries
        self.unlocked = unlocked
    }
}

/// LOG-013: the pure step recorder.
public enum JournalRecorder {
    /// LOG-013: records one step. Rejected steps and confirmation requests record nothing.
    @discardableResult
    public static func record(_ step: JournalStep, into journal: inout GameJournal) -> JournalStepOutput {
        if step.result.rejection != nil { return JournalStepOutput() }
        if case .confirm = step.result.decision, step.result.events.isEmpty { return JournalStepOutput() }
        let ruleset = step.after.ruleset
        let statsBefore = journal.stats
        let firstNew = journal.entries.count
        var context = Context(step: step)
        // (1) events, with the encounter ledger.
        if case .encounter(.surrender) = step.command { journal.openEncounter?.surrendered = true }
        for event in step.result.events {
            map(event, context: &context, journal: &journal)
        }
        if journal.openEncounter != nil, !isEncounter(step.after.phase) { closeEncounter(&journal, step: step) }
        // (2) derived entries.
        appendDerived(step, journal: &journal)
        // (3) intel.
        for case let .arrived(system) in step.result.events { journal.intel.visit(system, day: step.after.commander.days) }
        if case .readNewspaper = step.command, case let .newspaper(paper)? = step.result.decision {
            journal.intel.read(paper.headlines, day: step.after.commander.days)
        }
        journal.intel.observe(step.after)
        // (4) achievements (ACH-006); a step without entries leaves the statistics, and so the unlocks, unchanged.
        let unlocked = journal.entries.count == firstNew
            ? [] : AchievementCatalog.newlyUnlocked(before: statsBefore, after: journal.stats, ruleset: ruleset)
        for id in unlocked { journal.append(.achievementUnlocked(id), state: step.after) }
        // (5) template flavor (LLM-008).
        for i in firstNew..<journal.entries.count {
            guard let subject = journal.entries[i].kind.flavorSubject else { continue }
            let request = FlavorRequest(entryID: journal.entries[i].id, day: journal.entries[i].day,
                                        system: journal.entries[i].system, subject: subject)
            journal.entries[i].flavor = .template(TemplateFlavorProvider().line(for: request))
        }
        return JournalStepOutput(newEntries: Array(journal.entries[firstNew...]), unlocked: unlocked)
    }

    /// Per-step bookkeeping.
    struct Context {
        let step: JournalStep
        var uneventful = false
    }

    static func isEncounter(_ phase: GamePhase) -> Bool {
        if case .encounter = phase { return true }
        return false
    }

    static func closeEncounter(_ journal: inout GameJournal, step: JournalStep) {
        guard let ledger = journal.openEncounter else { return }
        journal.openEncounter = nil
        journal.append(.encounter(ledger.close(killsAfter: step.after.commander.kills)), state: step.after)
    }

    /// LOG-016 / LOG-017.
    static func appendDerived(_ step: JournalStep, journal: inout GameJournal) {
        let (before, after) = (step.before, step.after)
        if case .readNewspaper = step.command, case let .newspaper(paper)? = step.result.decision {
            journal.append(.news(NewsEntry(headlines: paper.headlines, cost: before.commander.cash - after.commander.cash)),
                           state: after)
        }
        if before.policeRecord != after.policeRecord {
            journal.append(.status(.policeRecord(from: before.policeRecord, to: after.policeRecord)), state: after)
        }
        if before.reputation != after.reputation {
            journal.append(.status(.reputation(from: before.reputation, to: after.reputation)), state: after)
        }
    }

    /// LOG-018: the last `departed` entry and the number of encounter records after it.
    static func tripSoFar(_ journal: GameJournal) -> (from: Int?, viaWormhole: Bool?, encounters: Int) {
        var encounters = 0
        for entry in journal.entries.reversed() {
            switch entry.kind {
            case .encounter: encounters += 1
            case let .departed(from, _, via, _): return (from, via, encounters)
            case .arrived, .journalStarted: return (nil, nil, encounters)
            default: continue
            }
        }
        return (nil, nil, encounters)
    }

    // swiftlint:disable cyclomatic_complexity
    /// LOG-015 / §3a: the disposition of every engine event (exhaustive, no default).
    static func map(_ event: GameEvent, context: inout Context, journal: inout GameJournal) {
        let step = context.step
        let after = step.after
        func add(_ kind: LogEntryKind) { journal.append(kind, state: after) }
        func fold() { journal.openEncounter?.fold(event) }
        switch event {
        // Trades.
        case let .boughtCargo(item, quantity, total):
            add(.trade(TradeEntry(action: .buy, item: item, quantity: quantity, total: total)))
        case let .soldCargo(item, quantity, total, profit):
            add(.trade(TradeEntry(action: .sell, item: item, quantity: quantity, total: total, profit: profit)))
        case let .dumpedCargo(item, quantity, cost):
            add(.trade(TradeEntry(action: .dump, item: item, quantity: quantity, total: cost)))
        case let .jettisonedCargo(item, quantity):
            add(.trade(TradeEntry(action: .jettison, item: item, quantity: quantity, total: 0)))
        case let .sealedCanisters(item):
            add(.trade(TradeEntry(action: .sealedCanisters, item: item, quantity: 3, total: 0)))
        case let .plundered(item, quantity):
            add(.trade(TradeEntry(action: .plunder, item: item, quantity: quantity, total: 0)))
            fold()
        case let .scooped(item):
            add(.trade(TradeEntry(action: .scoop, item: item, quantity: 1, total: 0)))
            fold()
        case let .orbitTradeCompleted(direction, item, quantity, total):
            switch direction {
            case .traderSells:
                add(.trade(TradeEntry(action: .orbitBuy, item: item, quantity: quantity, total: total)))
            case .traderBuys:
                let basis = step.before.commander.priceCargo[item.rawValue] - after.commander.priceCargo[item.rawValue]
                add(.trade(TradeEntry(action: .orbitSell, item: item, quantity: quantity, total: total, profit: total - basis)))
            }
            fold()
        // Encounter events.
        case .combatRound, .encounterChanged, .playerAttacked, .playerFled, .opponentDestroyed, .opponentDisabled,
             .playerEscaped, .opponentEscaped, .bountyPaid, .looted, .blackmailed, .bribed, .fined, .yielded,
             .inspectionClean, .artifactRelinquished, .preciousHidden, .sculptureTaken, .wildJoinedPirates, .tonicConsumed,
             .captainTraining, .scoopNoRoom, .playerDestroyed, .bothDestroyed:
            fold()
        case let .encounterStarted(type, opponent, clicks, _):
            closeEncounter(&journal, step: step)
            let ship = step.before.commander.ship
            journal.openEncounter = EncounterLedger(type: type, opponent: opponent, startDay: after.commander.days,
                                                    startSystem: after.commander.currentSystem, clicks: clicks,
                                                    minPlayerHull: ship.hull,
                                                    playerHullStrength: ship.hullStrength(step.before.ruleset))
        // Travel.
        case let .departed(from, to, via):
            let parsecs = via ? 0 : GalaxyGenerator.distance(step.before.galaxy.systems[from], step.before.galaxy.systems[to],
                                                             rule: step.before.ruleset.flags.distance)
            add(.departed(from: from, to: to, viaWormhole: via, parsecs: parsecs))
        case let .fabricRip(destination): add(.fabricRip(newDestination: destination))
        case .singularityLost: add(.singularityLost)
        case .uneventfulTrip: context.uneventful = true
        case let .arrived(system):
            closeEncounter(&journal, step: step)
            let trip = tripSoFar(journal)
            let first = step.before.galaxy.systems.indices.contains(system) && !step.before.galaxy.systems[system].visited
            add(.arrived(TripArrival(system: system, from: trip.from ?? step.before.commander.currentSystem,
                                     viaWormhole: trip.viaWormhole ?? after.arrivedViaWormhole, firstVisit: first,
                                     uneventful: context.uneventful, encounterCount: trip.encounters)))
            context.uneventful = false
        // Police.
        case let .arrested(term, fine, shipSold):
            fold()
            closeEncounter(&journal, step: step)
            add(.police(.arrested(term: term, fine: fine, shipSold: shipSold)))
        case .caughtLittering: add(.police(.caughtLittering))
        case .reactorConfiscated:
            fold()
            add(.police(.reactorConfiscated))
        // Finance.
        case let .borrowed(amount): add(.finance(.borrowed(amount: amount)))
        case let .repaid(amount): add(.finance(.repaid(amount: amount, remainingDebt: after.commander.debt)))
        case .insuranceBought: add(.finance(.insuranceBought))
        case .insuranceStopped: add(.finance(.insuranceStopped))
        case let .debtWarning(debt): add(.finance(.debtWarning(debt: debt)))
        case let .debtReminder(debt): add(.finance(.debtReminder(debt: debt)))
        // Ship.
        case let .boughtShip(type, net): add(.ship(.boughtShip(type, netPrice: net)))
        case let .customShipBuilt(yard): add(.ship(.customShipBuilt(yard)))
        case let .boughtEquipment(price), let .soldEquipment(price):
            if let change = equipmentChange(step) { add(.ship(.equipment(change, price: price))) }
        case let .boughtEscapePod(price): add(.ship(.boughtEscapePod(price: price)))
        case let .boughtFuel(units, cost): add(.ship(.fuel(units: units, cost: cost)))
        case let .repairedHull(points, cost): add(.ship(.repair(points: points, cost: cost)))
        case .autoFuelFailed: add(.ship(.autoFuelFailed))
        case .autoRepairFailed: add(.ship(.autoRepairFailed))
        case let .escapePodUsed(payout):
            fold()
            closeEncounter(&journal, step: step)
            add(.ship(.escapePodUsed(insurancePayout: payout)))
        // Crew.
        case let .hired(id): add(.crew(.hired(crewID: id)))
        case let .fired(id): add(.crew(.fired(crewID: id)))
        case let .passengerConcerned(id): add(.crew(.passengerConcerned(crewID: id)))
        case let .passengerImpatient(id): add(.crew(.passengerImpatient(crewID: id)))
        // Quests.
        case let .specialEventCompleted(type): add(.quest(.completed(type)))
        case let .specialEventRefused(type, _): add(.quest(.refused(type)))
        case let .tribblesChanged(from, to): add(.quest(.tribbles(from: from, to: to)))
        case let .tribblesDied(death): add(.quest(.tribblesDied(death)))
        case let .tribblesAteFood(eaten): add(.quest(.tribblesAteFood(eaten: eaten)))
        case let .tribbleInspectorWarning(count): add(.quest(.tribbleInspectorWarning(count: count)))
        case let .reactorWarning(status): add(.quest(.reactorWarning(status: status)))
        case .reactorMeltdown: add(.quest(.reactorMeltdown))
        case .gemulonInvaded: add(.quest(.gemulonInvaded))
        case .experimentPerformed: add(.quest(.experimentPerformed))
        case .wildLeftShip: add(.quest(.wildLeftShip))
        case .easterEgg: add(.quest(.easterEgg(shieldInstalled: true)))
        case .easterEggNoShieldSlot: add(.quest(.easterEgg(shieldInstalled: false)))
        // Game.
        case let .gameEnded(end, score):
            closeEncounter(&journal, step: step)
            add(.gameEnded(end, score: score))
        case .cheatUsed:
            if !step.before.cheatsUsed, !journal.containsCheatsEnabled { add(.cheatsEnabled) }
        case .gameStarted, .optionsChanged, .cheatReadout, .departureBlocked, .cannotTransfer, .cannotAffordTransfer,
             .cannotAffordAllTransfers:
            break
        }
    }
    // swiftlint:enable cyclomatic_complexity

    /// LOG-009: the bought or sold equipment, from the command (and the ship before a sale).
    static func equipmentChange(_ step: JournalStep) -> EquipmentChange? {
        let ship = step.before.commander.ship
        switch step.command {
        case let .buyWeapon(w): return .boughtWeapon(w)
        case let .buyShield(s): return .boughtShield(s)
        case let .buyGadget(g): return .boughtGadget(g)
        case let .sellWeapon(i): return ship.weapons.indices.contains(i) ? .soldWeapon(ship.weapons[i]) : nil
        case let .sellShield(i): return ship.shields.indices.contains(i) ? .soldShield(ship.shields[i].type) : nil
        case let .sellGadget(i): return ship.gadgets.indices.contains(i) ? .soldGadget(ship.gadgets[i]) : nil
        default: return nil
        }
    }
}

extension GameJournal {
    /// True once a `cheatsEnabled` entry was recorded.
    var containsCheatsEnabled: Bool {
        entries.contains { if case .cheatsEnabled = $0.kind { return true } else { return false } }
    }
}
