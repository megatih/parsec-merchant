// SPDX-License-Identifier: GPL-2.0-or-later
// Special events and quest steps at a docked system (docs/specs/QST-*.md).
// C# StarSystem.ShowSpecialButton, Form_SpaceTrader.btnSpecial_Click and Game.HandleSpecialEvent.

public extension GameState {
    /// The special-event table row for an event type.
    func specialEventSpec(_ type: SpecialEventType) -> SpecialEventSpec? {
        ruleset.tables.specialEvents.first { $0.type == type }
    }

    /// QST-INDEX: C# `ShowSpecialButton` for the current system (nil when no special event is offered).
    var specialEventAvailable: SpecialEventType? {
        guard case .docked = phase, let type = currentSystem.specialEvent else { return nil }
        return specialEventShown(type) ? type : nil
    }

    internal func specialEventShown(_ type: SpecialEventType) -> Bool {
        let record = commander.policeRecordScore
        let reputation = commander.reputationScore
        let dubious = -5, lawful = 5, average = 40
        let q = quests
        switch type {
        case .artifact, .dragonfly, .experiment, .jarek: return record >= dubious
        case .artifactDelivery: return artifactOnBoard
        case .cargoForSale: return freeCargoBays >= 3
        case .dragonflyBaratas: return q.dragonfly > 0 && q.dragonfly < QuestStatus.Dragonfly.destroyed
        case .dragonflyDestroyed: return q.dragonfly == QuestStatus.Dragonfly.destroyed
        case .dragonflyMelina: return q.dragonfly > QuestStatus.Dragonfly.flyBaratas && q.dragonfly < QuestStatus.Dragonfly.destroyed
        case .dragonflyRegulas: return q.dragonfly > QuestStatus.Dragonfly.flyMelina && q.dragonfly < QuestStatus.Dragonfly.destroyed
        case .dragonflyShield, .experimentFailed, .gemulon, .gemulonFuel, .gemulonInvaded, .lottery, .reactorLaser,
             .princessQuantum, .sculptureHiddenBays, .skill, .spaceMonster, .tribble:
            return true
        case .eraseRecord, .wild: return record < dubious
        case .experimentStopped: return q.experiment > 0 && q.experiment < QuestStatus.Experiment.performed
        case .gemulonRescued: return q.gemulon > 0 && q.gemulon < QuestStatus.Gemulon.tooLate
        case .japori: return q.japori == QuestStatus.Japori.notStarted && record >= dubious
        case .japoriDelivery: return q.japori == QuestStatus.Japori.inTransit
        case .jarekGetsOut: return jarekOnBoard
        case .moon: return q.moon == QuestStatus.Moon.notStarted && worth > QuestStatus.moonCost * 4 / 5
        case .moonRetirement: return q.moon == QuestStatus.Moon.bought
        case .princess: return record >= lawful && reputation >= average
        case .princessCentauri: return q.princess >= QuestStatus.Princess.flyCentauri && q.princess <= QuestStatus.Princess.flyQonos
        case .princessInthara: return q.princess >= QuestStatus.Princess.flyInthara && q.princess <= QuestStatus.Princess.flyQonos
        case .princessQonos: return q.princess == QuestStatus.Princess.rescued && !princessOnBoard
        case .princessReturned: return princessOnBoard
        case .reactor: return q.reactor == QuestStatus.Reactor.notStarted && record < dubious && reputation >= average
        case .reactorDelivered: return reactorOnBoard
        case .scarab: return q.scarab == QuestStatus.Scarab.notStarted && reputation >= average
        case .scarabDestroyed, .scarabUpgradeHull: return q.scarab == QuestStatus.Scarab.destroyed
        case .sculpture: return q.sculpture == QuestStatus.Sculpture.notStarted && record < dubious && reputation >= average
        case .sculptureDelivered: return q.sculpture == QuestStatus.Sculpture.inTransit
        case .spaceMonsterKilled: return q.spaceMonster == QuestStatus.SpaceMonster.destroyed
        case .tribbleBuyer: return commander.ship.tribbles > 0
        case .wildGetsOut: return wildOnBoard
        }
    }

    /// C# `Ship.Hire`: first free crew slot; buy prices follow a changed Trader skill.
    internal mutating func hireCrew(_ id: Int) {
        guard let slot = commander.ship.crew.firstIndex(where: { $0 == nil }) else { return }
        let before = skill(.trader)
        commander.ship.crew[slot] = id
        if skill(.trader) != before { recalculateBuyPricesHere() }
    }

    /// C# `Ship.Fire` for a special passenger (no relocation draw): later crew shift up one slot.
    internal mutating func removeSpecialCrew(_ id: Int) {
        guard let slot = commander.ship.crew.firstIndex(of: id) else { return }
        let before = skill(.trader)
        var crew = commander.ship.crew
        crew.remove(at: slot)
        crew.append(nil)
        commander.ship.crew = crew
        if skill(.trader) != before { recalculateBuyPricesHere() }
    }

    internal mutating func recalculateBuyPricesHere() {
        buyPrices = Pricing.buyPrices(sell: sellPrices, in: currentSystem, criminal: commander.policeRecordScore < -5,
                                      traderSkill: skill(.trader), ruleset: ruleset)
    }

    /// C# `Commander.NthLowestSkill(n)` (bubble sort of skill ids; ties keep id order).
    internal func nthLowestSkill(_ n: Int) -> Int {
        let skills = mercenaries[CrewID.commander].skills
        var ids = [0, 1, 2, 3]
        for j in 0..<3 {
            for i in 0..<(3 - j) where skills[ids[i]] > skills[ids[i + 1]] { ids.swapAt(i, i + 1) }
        }
        return ids[n - 1]
    }
}

/// The result of one special-event handler: whether the event is removed afterwards and what it emitted, or an early
/// return (rejection, confirmation, or a committed refusal) that skips the price and removal.
enum SpecialStep {
    case done(remove: Bool, events: [GameEvent])
    case stop(StepResult)
    static let removed = SpecialStep.done(remove: true, events: [])
    static let kept = SpecialStep.done(remove: false, events: [])
}

extension GameEngine {
    /// QST-INDEX: `Command.specialEvent` (C# btnSpecial_Click + HandleSpecialEvent).
    mutating func specialEvent(_ ack: Set<WarningID>) -> StepResult {
        guard let type = state.specialEventAvailable, let spec = state.specialEventSpec(type) else {
            return .rejected(.noSpecialEvent)
        }
        if !spec.messageOnly, !ack.contains(.acceptSpecialEvent) {
            return .needsConfirmation(Confirmation(.acceptSpecialEvent, amounts: [spec.price]))
        }
        if state.cashToSpend < spec.price { return .rejected(.insufficientFunds) }
        let step = questShipEvent(type) ?? passengerEvent(type, ack) ?? deliveryEvent(type) ?? oneOffEvent(type, spec)
        switch step {
        case let .stop(result):
            return result
        case let .done(remove, events):
            if spec.price != 0 { state.commander.cash -= spec.price }
            if remove { state.galaxy.systems[state.commander.currentSystem].specialEvent = nil }
            return StepResult(events: events + [.specialEventCompleted(type)])
        }
    }

    /// Replaces the current system's event (C# `curSys.SpecialEventType = …; remove = false`).
    private mutating func replaceEvent(with next: SpecialEventType) -> SpecialStep {
        state.galaxy.systems[state.commander.currentSystem].specialEvent = next
        return .kept
    }

    /// Dragonfly, Space Monster, Scarab and their rewards.
    private mutating func questShipEvent(_ type: SpecialEventType) -> SpecialStep? {
        let r = ruleset
        switch type {
        case .dragonfly, .dragonflyBaratas, .dragonflyMelina, .dragonflyRegulas:
            state.quests.dragonfly += 1
        case .dragonflyDestroyed:
            return replaceEvent(with: .dragonflyShield)
        case .dragonflyShield:
            guard state.commander.ship.freeShieldSlots(r) > 0 else { return .stop(.rejected(.noFreeSlot)) }
            state.commander.ship.shields.append(ShieldInstance(type: .lightning, charge: r.tables.shield(.lightning).power))
            state.quests.dragonfly = QuestStatus.Dragonfly.done
        case .spaceMonster: state.quests.spaceMonster = QuestStatus.SpaceMonster.atAcamar
        case .spaceMonsterKilled: state.quests.spaceMonster = QuestStatus.SpaceMonster.done
        case .scarab: state.quests.scarab = QuestStatus.Scarab.hunting
        case .scarabDestroyed:
            state.quests.scarab = QuestStatus.Scarab.destroyed
            return replaceEvent(with: .scarabUpgradeHull)
        case .scarabUpgradeHull:
            state.commander.ship.hullUpgraded = true
            state.commander.ship.hull += 50
            state.quests.scarab = QuestStatus.Scarab.done
            return .kept
        default:
            return nil
        }
        return .removed
    }

    /// Jarek, Wild, the Princess, and the reactor pickup (which Wild refuses to share a ship with).
    private mutating func passengerEvent(_ type: SpecialEventType, _ ack: Set<WarningID>) -> SpecialStep? {
        let hasQuarters = state.commander.ship.crew.contains { $0 == nil }
        switch type {
        case .jarek:
            guard hasQuarters else { return .stop(.rejected(.noFreeQuarters)) }
            state.hireCrew(CrewID.jarek)
            state.quests.jarek = QuestStatus.Jarek.started
        case .jarekGetsOut:
            state.quests.jarek = QuestStatus.Jarek.done
            state.removeSpecialCrew(CrewID.jarek)
        case .wild:
            guard hasQuarters else { return .stop(.rejected(.noFreeQuarters)) }
            guard state.commander.ship.has(.beamLaser, exact: false) else { return .stop(.rejected(.wildRequiresLaser)) }
            guard !state.reactorOnBoard else { return .stop(.rejected(.wildRefusesReactor)) }
            state.hireCrew(CrewID.wild)
            state.quests.wild = QuestStatus.Wild.started
        case .wildGetsOut:
            // Zeethibal: 10 in the commander's lowest skill, 8 in the next lowest, 5 elsewhere.
            state.mercenaries[CrewID.zeethibal].systemID = SystemID.kravat
            let lowest1 = state.nthLowestSkill(1), lowest2 = state.nthLowestSkill(2)
            state.mercenaries[CrewID.zeethibal].skills = (0..<4).map { $0 == lowest1 ? 10 : ($0 == lowest2 ? 8 : 5) }
            state.quests.wild = QuestStatus.Wild.done
            let wasCriminal = state.commander.policeRecordScore < -5
            // RUL-037: Palm raises the record to at least 0 (a hero keeps his record).
            switch state.ruleset.flags.economy.wildDeliveredRecord {
            case .setToZero: state.commander.policeRecordScore = 0
            case .raiseToZero: state.commander.policeRecordScore = max(state.commander.policeRecordScore, 0)
            }
            state.removeSpecialCrew(CrewID.wild)
            // RUL-115 (MOD-015): Modern only if the record was criminal before; Palm never after Wild.
            switch state.ruleset.flags.economy.sellPriceRecalc {
            case .always: state.recalculateSellPrices()
            case .onlyIfWasCriminal: if wasCriminal { state.recalculateSellPrices() }
            case .eraseRecordOnly: break
            }
        case .reactor:
            guard state.freeCargoBays >= 15 else { return .stop(.rejected(.noEmptyBays)) }
            var events: [GameEvent] = []
            if state.wildOnBoard {
                guard ack.contains(.wildLeavesForReactor) else {
                    return .stop(.needsConfirmation(Confirmation(.wildLeavesForReactor)))
                }
                // C# resets Wild's status but leaves him in the crew (kept quirk, QST-REACTOR).
                state.quests.wild = QuestStatus.Wild.notStarted
                events.append(.wildLeftShip)
            }
            state.quests.reactor = QuestStatus.Reactor.fuelOK
            return .done(remove: true, events: events)
        case .princess:
            state.quests.princess += 1
            return replaceEvent(with: .princessReturned)
        case .princessCentauri, .princessInthara:
            state.quests.princess += 1
        case .princessQonos:
            guard hasQuarters else { return .stop(.rejected(.noFreeQuarters)) }
            state.hireCrew(CrewID.princess)
        case .princessQuantum:
            guard state.commander.ship.freeWeaponSlots(ruleset) > 0 else { return .stop(.rejected(.noFreeSlot)) }
            state.commander.ship.weapons.append(.quantumDisruptor)
            state.quests.princess = QuestStatus.Princess.done
        case .princessReturned:
            state.removeSpecialCrew(CrewID.princess)
            state.quests.princess = QuestStatus.Princess.returned
            return replaceEvent(with: .princessQuantum)
        default:
            return nil
        }
        return .removed
    }

    /// Delivery quests: artifact, Japori, reactor, Gemulon, experiment, sculpture, moon.
    private mutating func deliveryEvent(_ type: SpecialEventType) -> SpecialStep? {
        let r = ruleset
        switch type {
        case .artifact: state.quests.artifact = QuestStatus.Artifact.onBoard
        case .artifactDelivery: state.quests.artifact = QuestStatus.Artifact.done
        case .japori:
            // The Japori quest is never removed: it can fail and start again.
            guard state.freeCargoBays >= 10 else { return .stop(.rejected(.noEmptyBays)) }
            state.quests.japori = QuestStatus.Japori.inTransit
            return .kept
        case .japoriDelivery:
            state.quests.japori = QuestStatus.Japori.done
            state.changeRandomSkill(1)
            state.changeRandomSkill(1)
        case .reactorDelivered:
            state.quests.reactor = QuestStatus.Reactor.delivered
            return replaceEvent(with: .reactorLaser)
        case .reactorLaser:
            guard state.commander.ship.freeWeaponSlots(r) > 0 else { return .stop(.rejected(.noFreeSlot)) }
            state.commander.ship.weapons.append(.morgansLaser)
            state.quests.reactor = QuestStatus.Reactor.done
        case .gemulon: state.quests.gemulon = QuestStatus.Gemulon.started
        case .gemulonRescued:
            state.quests.gemulon = QuestStatus.Gemulon.fuel
            return replaceEvent(with: .gemulonFuel)
        case .gemulonFuel:
            guard state.commander.ship.freeGadgetSlots(r) > 0 else { return .stop(.rejected(.noFreeSlot)) }
            state.commander.ship.gadgets.append(.fuelCompactor)
            state.quests.gemulon = QuestStatus.Gemulon.done
        case .experiment: state.quests.experiment = QuestStatus.Experiment.started
        case .experimentStopped:
            state.quests.experiment = QuestStatus.Experiment.cancelled
            state.quests.canSuperWarp = true
        case .sculpture: state.quests.sculpture = QuestStatus.Sculpture.inTransit
        case .sculptureDelivered:
            state.quests.sculpture = QuestStatus.Sculpture.delivered
            return replaceEvent(with: .sculptureHiddenBays)
        case .sculptureHiddenBays:
            // C# marks the quest done before the slot check, so a refusal still commits the status.
            state.quests.sculpture = QuestStatus.Sculpture.done
            guard state.commander.ship.freeGadgetSlots(r) > 0 else {
                return .stop(StepResult(events: [.specialEventRefused(type, reason: .noFreeSlot)]))
            }
            state.commander.ship.gadgets.append(.hiddenCargoBays)
        case .moon: state.quests.moon = QuestStatus.Moon.bought
        case .moonRetirement:
            state.quests.moon = QuestStatus.Moon.done
            return .stop(StepResult(events: [.specialEventCompleted(type), state.endGame(.boughtMoon)]))
        default:
            return nil
        }
        return .removed
    }

    /// The reactor pickup, one-offs and message-only events.
    private mutating func oneOffEvent(_ type: SpecialEventType, _ spec: SpecialEventSpec) -> SpecialStep {
        switch type {
        case .cargoForSale:
            let item = state.rng.next(below: TradeItemType.allCases.count)
            state.commander.ship.cargo[item] += 3
            state.commander.priceCargo[item] += spec.price
            return .done(remove: true, events: [.sealedCanisters(TradeItemType(rawValue: item) ?? .water)])
        case .eraseRecord:
            let wasCriminal = state.commander.policeRecordScore < -5
            state.commander.policeRecordScore = 0
            // RUL-115 (MOD-015): Modern recalculates only if the record was criminal before.
            if state.ruleset.flags.economy.sellPriceRecalc != .onlyIfWasCriminal || wasCriminal {
                state.recalculateSellPrices()
            }
        case .skill: state.changeRandomSkill(1)
        case .tribble: state.commander.ship.tribbles = 1
        case .tribbleBuyer:
            state.commander.cash += state.commander.ship.tribbles / 2
            state.commander.ship.tribbles = 0
        default:
            break
        }
        return .removed
    }
}
