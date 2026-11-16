// SPDX-License-Identifier: GPL-2.0-or-later
// Debt notices and the Palm 1.2.2 arrival pipeline (docs/specs/TRV.md §8, BNK debt notices).

extension GameState {
    /// Debt warning and loan reminder (BNK-034/036/037, MOD-018 `debtWarningAndReminder`).
    func debtNotices() -> [GameEvent] {
        var events: [GameEvent] = []
        let warn = commander.debt >= 75_000
        if warn { events.append(.debtWarning(debt: commander.debt)) }
        if !warn || ruleset.flags.travel.debtWarningAndReminder, commander.debt > 0, options.remindLoans, commander.days % 5 == 0 {
            events.append(.debtReminder(debt: commander.debt))
        }
        return events
    }

    /// Palm `Arrival()`: current system, status shuffle and quantities, prices, newspaper unpaid.
    mutating func arrivalMarket() {
        commander.currentSystem = warpSystem
        updatePressuresAndQuantities(arrival: commander.currentSystem)
        calculatePrices(for: commander.currentSystem)
        paidForNewspaper = false
    }

    /// Palm System Information on arrival (TRV-067): news flags, then the visited mark.
    mutating func palmSystemInformation() {
        addArrivalNews()
        galaxy.systems[commander.currentSystem].visited = true
    }

    /// Palm `EscapeWithPod` (it runs `Arrival()` first) for the meltdown path (TRV-061).
    mutating func palmEscapeWithPod() -> [GameEvent] {
        // The Palm pod sequence (POL-107) starts with its own Arrival(); only add one if that sequence is off.
        if !ruleset.flags.encounter.escapePodPalmSequence { arrivalMarket() }
        return escapeWithPod()
    }

    /// The arrival after an arrest or the escape pod: Palm runs only `Arrival()` (TRV-062), C# the full pipeline.
    mutating func arrivalAfterArrestOrPod(pod: Bool) -> [GameEvent] {
        guard ruleset.flags.travel.arrivalPipelineAfterArrest == .marketOnly else {
            return (pod ? escapeWithPod() : []) + arrival()
        }
        var events: [GameEvent] = []
        if pod {
            events += palmEscapeWithPod()
        } else if ruleset.flags.encounter.arrestSequence != .palm {
            // The Palm arrest sequence (RUL-137) already ran its Arrival().
            arrivalMarket()
        }
        palmSystemInformation()
        return events + [.arrived(system: commander.currentSystem)]
    }

    /// Palm arrival pipeline (TRV-060): debt → Arrival() → reactor → tracking → tribbles → repair → auto-buy → egg.
    mutating func palmArrival() -> [GameEvent] {
        var events = debtNotices()
        arrivalMarket()
        if [QuestStatus.Reactor.fuelOK + 1, QuestStatus.Reactor.date - 4, QuestStatus.Reactor.date - 2].contains(quests.reactor) {
            events.append(.reactorWarning(status: quests.reactor))
        }
        if quests.reactor == QuestStatus.Reactor.date {
            events.append(.reactorMeltdown)
            quests.reactor = QuestStatus.Reactor.notStarted
            guard commander.ship.escapePod else { return events + [endGame(.killed)] }
            events += palmEscapeWithPod()
            palmSystemInformation()
            return events + [.arrived(system: commander.currentSystem)]
        }
        if trackedSystem == commander.currentSystem, options.trackAutoOff { trackedSystem = nil }
        events += arrivalTribbles()
        events += arrivalRepairs()
        events += arrivalEasterEgg()
        commander.ship.cargo = commander.ship.cargo.map { max(0, $0) }
        palmSystemInformation()
        events.append(.arrived(system: commander.currentSystem))
        return events
    }
}
