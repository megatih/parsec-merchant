// SPDX-License-Identifier: GPL-2.0-or-later
// The escape pod, the Flea, and mercenaries lost with the old ship (POL §9, RUL-099/116, CRW-051).

extension GameState {
    /// C# `EscapeWithPod`.
    mutating func escapeWithPod() -> [GameEvent] {
        if ruleset.flags.encounter.escapePodPalmSequence { return escapeWithPodPalm() }
        var events: [GameEvent] = []
        if ruleset.flags.encounter.escapePodLosesHullUpgrade, quests.scarab == QuestStatus.Scarab.done {
            quests.scarab = QuestStatus.Scarab.notStarted // RUL-099
        }
        if reactorOnBoard { quests.reactor = QuestStatus.Reactor.done }
        if quests.japori == QuestStatus.Japori.inTransit { quests.japori = QuestStatus.Japori.notStarted }
        if artifactOnBoard { quests.artifact = QuestStatus.Artifact.done }
        if jarekOnBoard { quests.jarek = QuestStatus.Jarek.notStarted }
        if princessOnBoard { quests.princess = QuestStatus.Princess.notStarted }
        if wildOnBoard {
            commander.policeRecordScore -= 4
            addNewsEvent(.wildArrested)
            quests.wild = QuestStatus.Wild.notStarted
        }
        var payout = 0
        if commander.insurance {
            payout = baseWorth(of: commander.ship, forInsurance: true)
            commander.cash += payout
        }
        if commander.cash > 500 {
            commander.cash -= 500
        } else {
            commander.debt += 500 - commander.cash
            commander.cash = 0
        }
        events.append(.escapePodUsed(insurancePayout: payout))
        events += incDays(3)
        createFlea()
        return events
    }

    /// MOD-016 (RUL-116, CRW-051): mercenaries lost to jail or the escape pod relocate like fired ones, in ascending
    /// slot order, measured from the system where the commander arrives.
    mutating func relocateLostMercenaries(_ ids: [Int]) {
        guard ruleset.flags.economy.lostMercenariesRelocate else { return }
        let special: Set<Int> = [CrewID.commander, CrewID.jarek, CrewID.princess, CrewID.wild]
        for id in ids where !special.contains(id) { relocateMercenary(id, near: warpSystem) }
    }

    /// CRW-039: `GetRandom(systems)` until the floor distance to `systemID` is < 20.
    mutating func relocateMercenary(_ id: Int, near systemID: Int) {
        let here = galaxy.systems[systemID]
        var candidate: Int
        repeat {
            candidate = rng.next(below: galaxy.systems.count)
        } while GalaxyGenerator.distance(galaxy.systems[candidate], here, rule: ruleset.flags.distance) >= 20
        mercenaries[id].systemID = candidate
    }

    /// POL-107: Palm's `EscapeWithPod` (RUL-099 Scarab reset, short Arrival first, reactor and artifact lost).
    mutating func escapeWithPodPalm() -> [GameEvent] {
        var events: [GameEvent] = []
        if ruleset.flags.encounter.escapePodLosesHullUpgrade, quests.scarab == QuestStatus.Scarab.done {
            quests.scarab = QuestStatus.Scarab.notStarted
        }
        shortArrival()
        if reactorOnBoard { quests.reactor = QuestStatus.Reactor.notStarted }
        if quests.japori == QuestStatus.Japori.inTransit { quests.japori = QuestStatus.Japori.notStarted }
        if artifactOnBoard { quests.artifact = QuestStatus.Artifact.notStarted }
        if jarekOnBoard { quests.jarek = QuestStatus.Jarek.notStarted }
        if wildOnBoard {
            commander.policeRecordScore -= 4
            newsEvents.append(.wildArrested)
            quests.wild = QuestStatus.Wild.notStarted
        }
        commander.ship.tribbles = 0
        var payout = 0
        if commander.insurance {
            payout = baseWorth(of: commander.ship, forInsurance: true)
            commander.cash += payout
        }
        if commander.cash > 500 {
            commander.cash -= 500
        } else {
            commander.debt += 500 - commander.cash
            commander.cash = 0
        }
        events.append(.escapePodUsed(insurancePayout: payout))
        events += incDays(3)
        createFlea()
        // The caller appends `.arrived` after the Palm System Information step (TRV-060/062).
        return events
    }

    /// C# `CreateFlea`.
    mutating func createFlea() {
        let lost = commander.ship.crew.dropFirst().compactMap { $0 }
        defer { relocateLostMercenaries(lost) }
        var flea = Ship(type: .flea, spec: ruleset.tables.ship(.flea))
        flea.crew[0] = CrewID.commander
        commander.ship = flea
        commander.insurance = false
        commander.noClaim = 0
        if ruleset.flags.resetPriceCargoOnHoldClear { commander.priceCargo = Array(repeating: 0, count: 10) }
    }
}
