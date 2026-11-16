// SPDX-License-Identifier: GPL-2.0-or-later
// Travel: warp, departure, resumable transit, encounter determination, arrival pipeline, IncDays.
// C# Game.Warp / NormalDeparture / Travel / Determine*Encounter / Arrival / IncDays (docs/specs/TRV.md, ENC.md).
import Foundation

public extension GameState {
    /// C# `Ship.Cloaked` for the commander: cloaking device and engineer skill above the opponent's.
    var commanderCloaked: Bool {
        guard commander.ship.has(.cloakingDevice), let opp = lastOpponent else { return false }
        return shipSkills[3] > skills(of: opp)[3]
    }

    /// C# `Ship.Cloaked` for an opponent ship.
    func opponentCloaked(_ opp: Ship) -> Bool {
        opp.has(.cloakingDevice) && skills(of: opp)[3] > shipSkills[3]
    }

    /// C# `PoliceRecord.GetPoliceRecordFromScore` for the commander.
    var policeRecord: PoliceRecordType {
        let mins = [-100, -70, -30, -10, -5, 0, 5, 10, 25, 75]
        var i = 0
        while i < mins.count, commander.policeRecordScore >= mins[i] { i += 1 }
        return PoliceRecordType(rawValue: max(0, i - 1)) ?? .psychopath
    }

    /// C# `StarSystem.DestOk`.
    func destinationOK(_ target: Int) -> Bool {
        target != commander.currentSystem
            && (GalaxyGenerator.distance(galaxy.systems[target], currentSystem, rule: ruleset.flags.distance) <= commander.ship.fuel
                || galaxy.wormholeExists(from: commander.currentSystem, to: target))
    }

    /// C# `Game.Destinations`: systems reachable now, in index order.
    var destinations: [Int] { galaxy.systems.indices.filter(destinationOK) }

    /// BNK-057: warp affordability checks in source order.
    func warpBlocker() -> CommandError? {
        if commander.debt > 100_000 { return .debtTooLargeToTravel }
        if commander.cash < mercenaryCosts { return .cannotPayMercenaries }
        if commander.cash < mercenaryCosts + insuranceCosts { return .cannotPayInsurance }
        if commander.cash < mercenaryCosts + insuranceCosts + wormholeCosts { return .cannotPayWormholeTax }
        return nil
    }

    /// C# `Game.IncDays`.
    mutating func incDays(_ n: Int) -> [GameEvent] {
        var events: [GameEvent] = []
        commander.days += n
        if commander.insurance { setNoClaim(commander.noClaim + n) }
        if commander.policeRecordScore > 0 {
            commander.policeRecordScore = max(0, commander.policeRecordScore - n / 3)
        } else if commander.policeRecordScore < -5 {
            commander.policeRecordScore = min(-5, commander.policeRecordScore + n / (difficulty <= .normal ? 1 : difficulty.rawValue))
        }
        let monsterMax = specialShips.spaceMonster.hullStrength(ruleset)
        if specialShips.spaceMonster.hull < monsterMax {
            specialShips.spaceMonster.hull = min(monsterMax, Int(Double(specialShips.spaceMonster.hull) * pow(1.05, Double(n))))
        }
        if quests.gemulon > QuestStatus.Gemulon.notStarted, quests.gemulon < QuestStatus.Gemulon.tooLate {
            quests.gemulon = min(quests.gemulon + n, QuestStatus.Gemulon.tooLate)
            if quests.gemulon == QuestStatus.Gemulon.tooLate {
                galaxy.systems[SystemID.gemulon].specialEvent = .gemulonInvaded
                galaxy.systems[SystemID.gemulon].techLevel = .preAgricultural
                galaxy.systems[SystemID.gemulon].politics = .anarchy
                events.append(.gemulonInvaded)
            }
        }
        if reactorOnBoard { quests.reactor = min(quests.reactor + n, QuestStatus.Reactor.date) }
        if quests.experiment > QuestStatus.Experiment.notStarted, quests.experiment < QuestStatus.Experiment.performed {
            quests.experiment = min(quests.experiment + n, QuestStatus.Experiment.performed)
            if quests.experiment == QuestStatus.Experiment.performed {
                quests.fabricRipProbability = 25
                galaxy.systems[SystemID.daled].specialEvent = .experimentFailed
                newsEvents.append(.experimentPerformed)
                events.append(.experimentPerformed)
            }
        } else if quests.experiment == QuestStatus.Experiment.performed, quests.fabricRipProbability > 0 {
            quests.fabricRipProbability -= n
        }
        for (onBoard, id) in [(jarekOnBoard, CrewID.jarek), (princessOnBoard, CrewID.princess), (wildOnBoard, CrewID.wild)] where onBoard {
            impatience(id)
        }
        return events
    }

    /// Passenger impatience steps of IncDays (Jarek, Princess, Wild): skills drop to 0 one step before impatient.
    private mutating func impatience(_ id: Int) {
        switch id {
        case CrewID.jarek:
            if quests.jarek == QuestStatus.Jarek.impatient - 1 { mercenaries[id].skills = [0, 0, 0, 0] }
            if quests.jarek < QuestStatus.Jarek.impatient { quests.jarek += 1 }
        case CrewID.princess:
            if quests.princess == QuestStatus.Princess.impatient - 1 { mercenaries[id].skills = [0, 0, 0, 0] }
            if quests.princess < QuestStatus.Princess.impatient { quests.princess += 1 }
        default:
            if quests.wild == QuestStatus.Wild.impatient - 1 { mercenaries[id].skills = [0, 0, 0, 0] }
            if quests.wild < QuestStatus.Wild.impatient { quests.wild += 1 }
        }
    }

    /// C# `Ship.PerformRepairs` for the commander's ship (each click).
    mutating func performClickRepairs() {
        var repairs = rng.next(below: shipSkills[3])
        let strength = commander.ship.hullStrength(ruleset)
        if repairs > 0 {
            let used = min(repairs, strength - commander.ship.hull)
            commander.ship.hull += used
            repairs -= used
        }
        if repairs > 0 {
            repairs *= 2
            var i = 0
            while i < commander.ship.shields.count, repairs > 0 {
                let power = ruleset.tables.shield(commander.ship.shields[i].type).power
                let used = min(repairs, power - commander.ship.shields[i].charge)
                commander.ship.shields[i].charge += used
                repairs -= used
                i += 1
            }
        }
    }

    // MARK: Encounter determination (ENC)

    /// C# `DetermineNonRandomEncounter`.
    mutating func determineFixedEncounter(clicks: Int) -> EncounterState? {
        let warp = warpSystem
        func start(_ ship: Ship, attack: EncounterType, ignore: EncounterType) -> EncounterState {
            lastOpponent = ship
            return EncounterState(type: commanderCloaked ? ignore : attack, opponent: ship, clicks: clicks)
        }
        if clicks == 1, warp == SystemID.acamar, quests.spaceMonster == QuestStatus.SpaceMonster.atAcamar {
            return start(specialShips.spaceMonster, attack: .spaceMonsterAttack, ignore: .spaceMonsterIgnore)
        }
        if arrivedViaWormhole, clicks == 20, galaxy.systems[warp].specialEvent == .scarabDestroyed,
           quests.scarab == QuestStatus.Scarab.hunting {
            return start(specialShips.scarab, attack: .scarabAttack, ignore: .scarabIgnore)
        }
        if clicks == 1, warp == SystemID.zalkon, quests.dragonfly == QuestStatus.Dragonfly.flyZalkon {
            return start(specialShips.dragonfly, attack: .dragonflyAttack, ignore: .dragonflyIgnore)
        }
        if clicks == 1, warp == SystemID.qonos, quests.princess == QuestStatus.Princess.flyQonos {
            return start(specialShips.scorpion, attack: .scorpionAttack, ignore: .scorpionIgnore)
        }
        if clicks == 1, quests.justLootedMarie {
            let opp = generateOpponent(.police)
            lastOpponent = opp
            quests.justLootedMarie = false
            return EncounterState(type: .marieCelestePolice, opponent: opp, clicks: clicks)
        }
        return nil
    }

    /// C# `DetermineRandomEncounter` (+ pirate/police/trader/very-rare). Returns the encounter if it is shown.
    mutating func determineRandomEncounter(clicks: Int) -> EncounterState? {
        let gov = ruleset.tables.politics(galaxy.systems[warpSystem].politics)
        var mantis = false, pirate = false, police = false, trader = false
        if warpSystem == SystemID.gemulon, quests.gemulon == QuestStatus.Gemulon.tooLate {
            if rng.next(below: 10) > 4 { mantis = true }
        } else {
            var roll = rng.next(below: 44 - 2 * difficulty.rawValue)
            let policeMod = max(1, 3 - policeRecord.rawValue)
            if commander.ship.type == .flea { roll *= 2 }
            let pir = gov.activityPirates.rawValue, pol = gov.activityPolice.rawValue, tra = gov.activityTraders.rawValue
            if roll < pir {
                pirate = !raided
            } else if roll < pir + pol * policeMod {
                police = true
            } else if roll < pir + pol * policeMod + tra {
                trader = true
            } else if wildOnBoard, warpSystem == SystemID.kravat {
                police = rng.next(below: 100) < 100 / max(2, min(4, 5 - difficulty.rawValue))
            } else if artifactOnBoard, rng.next(below: 20) <= 3 {
                mantis = true
            }
        }
        if police { return determinePolice(clicks: clicks) }
        if pirate || mantis { return determinePirate(mantis: mantis, clicks: clicks) }
        if trader { return determineTrader(clicks: clicks) }
        if commander.days > 10, rng.next(below: 1000) < chanceOfVeryRareEncounter, !veryRareEncounters.isEmpty {
            return determineVeryRare(clicks: clicks)
        }
        return nil
    }

    private mutating func determinePirate(mantis: Bool, clicks: Int) -> EncounterState? {
        let opp: Ship
        var type: EncounterType
        if mantis {
            opp = generateOpponent(.mantis)
            lastOpponent = opp
            type = .pirateAttack
        } else {
            opp = generateOpponent(.pirate)
            lastOpponent = opp
            if commanderCloaked {
                type = .pirateIgnore
            } else if opp.type.rawValue > commander.ship.type.rawValue || opp.type.rawValue >= ShipType.grasshopper.rawValue
                        || rng.next(below: 1_500) > (commander.reputationScore * 4) / (1 + opp.type.rawValue) {
                type = .pirateAttack
            } else {
                type = .pirateFlee
            }
        }
        let shown = type == .pirateAttack || !(opponentCloaked(opp) || options.alwaysIgnorePirates)
        return shown ? EncounterState(type: type, opponent: opp, clicks: clicks) : nil
    }

    private mutating func determinePolice(clicks: Int) -> EncounterState? {
        let opp = generateOpponent(.police)
        lastOpponent = opp
        var type: EncounterType = .policeIgnore
        if !commanderCloaked {
            if commander.policeRecordScore < -5 {
                if (opp.weaponStrength(ruleset) > 0
                    && (commander.reputationScore < 40 || rng.next(below: 1_500) > commander.reputationScore / (1 + opp.type.rawValue)))
                    || opp.type.rawValue > commander.ship.type.rawValue {
                    type = commander.policeRecordScore >= -30 ? .policeSurrender : .policeAttack
                } else if opponentCloaked(opp) {
                    type = .policeIgnore
                } else {
                    type = .policeFlee
                }
            } else if !inspected, commander.policeRecordScore < 0
                        || (commander.policeRecordScore < 5 && rng.next(below: 12 - difficulty.rawValue) < 1)
                        || (commander.policeRecordScore >= 5 && rng.next(below: 40) == 0) {
                type = .policeInspect
                inspected = true
            }
        }
        let shown = type == .policeAttack || type == .policeInspect || !(opponentCloaked(opp) || options.alwaysIgnorePolice)
        return shown ? EncounterState(type: type, opponent: opp, clicks: clicks) : nil
    }

    private mutating func determineTrader(clicks: Int) -> EncounterState? {
        let opp = generateOpponent(.trader)
        lastOpponent = opp
        var type: EncounterType = .traderIgnore
        if !commanderCloaked {
            if commander.policeRecordScore <= -30,
               rng.next(below: 1_500) <= (commander.reputationScore * 10) / (1 + opp.type.rawValue) {
                type = .traderFlee
            } else if let orbit = tradeInOrbitRoll(trader: opp) {
                type = orbit
            }
        }
        let ignoredByOption = options.alwaysIgnoreTraders && (type == .traderIgnore || type == .traderFlee)
        let ignoredTrade = (type == .traderBuy || type == .traderSell) && options.alwaysIgnoreTradeInOrbit
        let shown = !opponentCloaked(opp) && !ignoredByOption && !ignoredTrade
        return shown ? EncounterState(type: type, opponent: opp, clicks: clicks) : nil
    }

    private mutating func determineVeryRare(clicks: Int) -> EncounterState? {
        let pick = veryRareEncounters[rng.next(below: veryRareEncounters.count)]
        let cmdrRaw = mercenaries[CrewID.commander].skills
        func remove(_ v: VeryRareEncounter) { veryRareEncounters.removeAll { $0 == v } }
        switch pick {
        case .marieCeleste:
            let here = ruleset.flags.marieCelesteChecksDestination ? warpSystem : commander.currentSystem
            guard clicks > 1, here != SystemID.acamar, here != SystemID.zalkon, here != SystemID.qonos else { return nil }
            remove(.marieCeleste)
            var opp = generateOpponent(.trader)
            opp.cargo = Array(repeating: 0, count: 10)
            opp.cargo[TradeItemType.narcotics.rawValue] = min(opp.cargoBays(ruleset), 5)
            lastOpponent = opp
            return EncounterState(type: .marieCeleste, opponent: opp, clicks: clicks)
        case .captainAhab:
            guard commander.ship.has(.reflective), cmdrRaw[0] < 10, commander.policeRecordScore > -30 else { return nil }
            remove(.captainAhab)
            return famous(.captainAhab, clicks)
        case .captainConrad:
            guard commander.ship.has(.militaryLaser), cmdrRaw[3] < 10, commander.policeRecordScore > -30 else { return nil }
            remove(.captainConrad)
            return famous(.captainConrad, clicks)
        case .captainHuie:
            guard commander.ship.has(.militaryLaser), cmdrRaw[2] < 10, commander.policeRecordScore > -30 else { return nil }
            remove(.captainHuie)
            return famous(.captainHuie, clicks)
        case .bottleOld, .bottleGood:
            remove(pick)
            let opp = generateOpponent(.bottle)
            lastOpponent = opp
            return EncounterState(type: pick == .bottleOld ? .bottleOld : .bottleGood, opponent: opp, clicks: clicks)
        }
    }

    private mutating func famous(_ type: EncounterType, _ clicks: Int) -> EncounterState {
        let opp = generateOpponent(.famousCaptain)
        lastOpponent = opp
        return EncounterState(type: type, opponent: opp, clicks: clicks)
    }

    // MARK: Arrival (TRV)

    /// C# `NewsAddEventsOnArrival`.
    mutating func addArrivalNews() {
        guard let ev = currentSystem.specialEvent else { return }
        if let add = arrivalNewsQuests(ev) ?? arrivalNewsOthers(ev) { newsEvents.append(add) }
    }

    /// Arrival news for the Dragonfly, Experiment, Gemulon, Japori and Jarek chains.
    private func arrivalNewsQuests(_ ev: SpecialEventType) -> NewsEvent? {
        let q = quests
        switch ev {
        case .dragonfly: return .dragonfly
        case .dragonflyBaratas: return q.dragonfly == QuestStatus.Dragonfly.flyBaratas ? .dragonflyBaratas : nil
        case .dragonflyMelina: return q.dragonfly == QuestStatus.Dragonfly.flyMelina ? .dragonflyMelina : nil
        case .dragonflyRegulas: return q.dragonfly == QuestStatus.Dragonfly.flyRegulas ? .dragonflyRegulas : nil
        case .dragonflyDestroyed:
            if q.dragonfly == QuestStatus.Dragonfly.flyZalkon { return .dragonflyZalkon }
            return q.dragonfly == QuestStatus.Dragonfly.destroyed ? .dragonflyDestroyed : nil
        case .experimentFailed: return .experimentFailed
        case .experimentStopped:
            return q.experiment > QuestStatus.Experiment.notStarted && q.experiment < QuestStatus.Experiment.performed ? .experimentStopped : nil
        case .gemulon: return .gemulon
        case .gemulonRescued:
            guard q.gemulon > QuestStatus.Gemulon.notStarted else { return nil }
            return q.gemulon < QuestStatus.Gemulon.tooLate ? .gemulonRescued : .gemulonInvaded
        case .japori: return q.japori == QuestStatus.Japori.notStarted ? .japori : nil
        case .japoriDelivery: return q.japori == QuestStatus.Japori.inTransit ? .japoriDelivery : nil
        case .jarekGetsOut: return jarekOnBoard ? .jarekGetsOut : nil
        default: return nil
        }
    }

    /// Arrival news for the Artifact, Princess, Scarab, Sculpture, Space Monster and Wild chains.
    private func arrivalNewsOthers(_ ev: SpecialEventType) -> NewsEvent? {
        let q = quests
        switch ev {
        case .artifactDelivery: return artifactOnBoard ? .artifactDelivery : nil
        case .princess: return .princess
        case .princessCentauri: return q.princess == QuestStatus.Princess.flyCentauri ? .princessCentauri : nil
        case .princessInthara: return q.princess == QuestStatus.Princess.flyInthara ? .princessInthara : nil
        case .princessQonos:
            if q.princess == QuestStatus.Princess.flyQonos { return .princessQonos }
            return q.princess == QuestStatus.Princess.rescued ? .princessRescued : nil
        case .princessReturned: return q.princess == QuestStatus.Princess.returned ? .princessReturned : nil
        case .scarab: return .scarab
        case .scarabDestroyed:
            if q.scarab == QuestStatus.Scarab.hunting { return .scarabHarass }
            return q.scarab >= QuestStatus.Scarab.destroyed ? .scarabDestroyed : nil
        case .sculpture: return .sculptureStolen
        case .sculptureDelivered: return .sculptureTracked
        case .spaceMonsterKilled:
            if q.spaceMonster == QuestStatus.SpaceMonster.atAcamar { return .spaceMonster }
            return q.spaceMonster >= QuestStatus.SpaceMonster.destroyed ? .spaceMonsterKilled : nil
        case .wildGetsOut: return wildOnBoard ? .wildGetsOut : nil
        default: return nil
        }
    }

    /// C# `ArrivalCheckTribbles`.
    mutating func arrivalTribbles() -> [GameEvent] {
        let before = commander.ship.tribbles
        guard before > 0 else { return [] }
        let narc = TradeItemType.narcotics.rawValue, food = TradeItemType.food.rawValue
        if reactorOnBoard {
            commander.ship.tribbles = commander.ship.tribbles < 20 ? 0 : commander.ship.tribbles / 2
        } else if commander.ship.cargo[narc] > 0 {
            let held = commander.ship.cargo[narc]
            let dead = min(1 + rng.next(below: 3), held)
            commander.priceCargo[narc] = commander.priceCargo[narc] * (held - dead) / held
            commander.ship.cargo[narc] -= dead
            commander.ship.cargo[TradeItemType.furs.rawValue] += dead
            commander.ship.tribbles -= min(dead * (rng.next(below: 5) + 98), commander.ship.tribbles - 1)
        } else {
            if commander.ship.cargo[food] > 0, commander.ship.tribbles < 100_000 {
                let held = commander.ship.cargo[food]
                let eaten = held - rng.next(below: held)
                commander.priceCargo[food] -= commander.priceCargo[food] * eaten / held
                commander.ship.cargo[food] -= eaten
                commander.ship.tribbles += eaten * 100
            }
            if commander.ship.tribbles < 100_000 {
                commander.ship.tribbles += 1 + rng.next(below: commander.ship.cargo[food] > 0 ? commander.ship.tribbles : commander.ship.tribbles / 2)
            }
            if commander.ship.tribbles > 100_000 { commander.ship.tribbles = 100_000 }
        }
        tribbleMessage = false
        return [.tribblesChanged(from: before, to: commander.ship.tribbles)]
    }

    /// C# `ArrivalPerformRepairs` (auto fuel/repair all-or-nothing).
    mutating func arrivalRepairs() -> [GameEvent] {
        var events: [GameEvent] = []
        let r = ruleset
        let strength = commander.ship.hullStrength(r)
        if commander.ship.hull < strength {
            commander.ship.hull += min(strength - commander.ship.hull, rng.next(below: shipSkills[3]))
        }
        for i in commander.ship.shields.indices {
            commander.ship.shields[i].charge = r.tables.shield(commander.ship.shields[i].type).power
        }
        let spec = commander.ship.spec(r)
        var fuelOK = true, repairOK = true
        let fuelNeed = commander.ship.fuelTanks(r) - commander.ship.fuel
        if options.autoFuel, fuelNeed > 0 {
            if commander.cash >= fuelNeed * spec.fuelCost {
                commander.ship.fuel += fuelNeed
                commander.cash -= fuelNeed * spec.fuelCost
            } else {
                fuelOK = false
            }
        }
        let hullNeed = commander.ship.hullStrength(r) - commander.ship.hull
        if options.autoRepair, hullNeed > 0 {
            if commander.cash >= hullNeed * spec.repairCost {
                commander.ship.hull += hullNeed
                commander.cash -= hullNeed * spec.repairCost
            } else {
                repairOK = false
            }
        }
        if !fuelOK { events.append(.autoFuelFailed) }
        if !repairOK { events.append(.autoRepairFailed) }
        return events
    }

    /// C# `ArrivalCheckEasterEgg` (Og: exactly one unit of every good and a free shield slot → Lightning shield).
    mutating func arrivalEasterEgg() -> [GameEvent] {
        guard commander.currentSystem == SystemID.og, commander.ship.cargo.allSatisfy({ $0 == 1 }),
              commander.ship.freeShieldSlots(ruleset) > 0 else { return [] }
        commander.ship.shields.append(ShieldInstance(type: .lightning, charge: ruleset.tables.shield(.lightning).power))
        commander.ship.cargo = Array(repeating: 0, count: 10)
        commander.priceCargo = Array(repeating: 0, count: 10)
        return [.easterEgg]
    }

    /// C# `EscapeWithPod`.
    mutating func escapeWithPod() -> [GameEvent] {
        var events: [GameEvent] = []
        if reactorOnBoard { quests.reactor = QuestStatus.Reactor.done }
        if quests.japori == QuestStatus.Japori.inTransit { quests.japori = QuestStatus.Japori.notStarted }
        if artifactOnBoard { quests.artifact = QuestStatus.Artifact.done }
        if jarekOnBoard { quests.jarek = QuestStatus.Jarek.notStarted }
        if princessOnBoard { quests.princess = QuestStatus.Princess.notStarted }
        if wildOnBoard {
            commander.policeRecordScore -= 4
            newsEvents.append(.wildArrested)
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

    /// C# `CreateFlea`.
    mutating func createFlea() {
        var flea = Ship(type: .flea, spec: ruleset.tables.ship(.flea))
        flea.crew[0] = CrewID.commander
        commander.ship = flea
        commander.insurance = false
        commander.noClaim = 0
        if ruleset.flags.resetPriceCargoOnHoldClear { commander.priceCargo = Array(repeating: 0, count: 10) }
    }

    /// C# `Arrival` (the reactor meltdown path may end the game).
    mutating func arrival() -> [GameEvent] {
        var events: [GameEvent] = []
        commander.currentSystem = warpSystem
        galaxy.systems[warpSystem].visited = true
        paidForNewspaper = false
        if trackedSystem == commander.currentSystem, options.trackAutoOff { trackedSystem = nil }
        // ArrivalCheckReactor
        if quests.reactor == QuestStatus.Reactor.date {
            events.append(.reactorMeltdown)
            quests.reactor = QuestStatus.Reactor.notStarted
            if commander.ship.escapePod {
                events += escapeWithPod()
            } else {
                phase = .gameOver(.killed)
                return events
            }
        } else if [QuestStatus.Reactor.fuelOK + 1, QuestStatus.Reactor.date - 4, QuestStatus.Reactor.date - 2].contains(quests.reactor) {
            events.append(.reactorWarning(status: quests.reactor))
        }
        events += arrivalTribbles()
        if commander.debt >= 75_000 {
            events.append(.debtWarning(debt: commander.debt))
        } else if commander.debt > 0, options.remindLoans, commander.days % 5 == 0 {
            events.append(.debtReminder(debt: commander.debt))
        }
        events += arrivalRepairs()
        updatePressuresAndQuantities(arrival: commander.currentSystem)
        events += arrivalEasterEgg()
        calculatePrices(for: commander.currentSystem)
        addArrivalNews()
        events.append(.arrived(system: commander.currentSystem))
        return events
    }
}

extension GameEngine {
    /// C# `Game.Warp` (TRV): checks, departure, then transit until an encounter or arrival.
    mutating func warp(viaSingularity: Bool, _ ack: Set<WarningID>) -> StepResult {
        guard docked else { return .rejected(.notAllowedInPhase) }
        let target = state.warpSystem
        if viaSingularity {
            guard state.quests.canSuperWarp else { return .rejected(.noSingularity) }
            guard target != state.commander.currentSystem else { return .rejected(.destinationOutOfRange) }
        } else {
            guard state.destinationOK(target) else { return .rejected(.destinationOutOfRange) }
        }
        if let blocker = state.warpBlocker() { return .rejected(blocker) }
        var events: [GameEvent] = []
        if state.wildOnBoard, !state.commander.ship.has(.beamLaser, exact: false) {
            guard ack.contains(.wildLeavesWithoutLaser) else {
                return .needsConfirmation(Confirmation(.wildLeavesWithoutLaser))
            }
            state.quests.wild = QuestStatus.Wild.notStarted
            events.append(.wildLeftShip)
        }
        let from = state.commander.currentSystem
        state.arrivedViaWormhole = state.galaxy.wormholeExists(from: from, to: target)
        if viaSingularity {
            state.newsEvents.append(.experimentArrival)
            state.quests.canSuperWarp = false
        } else {
            let distance = state.arrivedViaWormhole ? 0
                : GalaxyGenerator.distance(state.galaxy.systems[from], state.galaxy.systems[target], rule: ruleset.flags.distance)
            state.commander.cash -= state.mercenaryCosts + state.insuranceCosts + state.wormholeCosts
            state.commander.ship.fuel -= distance
            state.payInterest()
            events += state.incDays(1)
        }
        state.setDepartureCountdown()
        state.newsEvents.removeAll()
        state.calculatePrices(for: target)
        events.append(.departed(from: from, to: target, viaWormhole: state.arrivedViaWormhole))
        // Travel(): fabric rip
        if state.quests.experiment == QuestStatus.Experiment.performed, state.quests.fabricRipProbability > 0,
           state.quests.fabricRipProbability == 25 || state.rng.next(below: 100) < state.quests.fabricRipProbability {
            state.warpSystem = state.rng.next(below: state.galaxy.systems.count)
            events.append(.fabricRip(newDestination: state.warpSystem))
        }
        state.raided = false
        state.inspected = false
        state.litterWarning = false
        state.phase = .inTransit(TransitState(destination: state.warpSystem, clicksRemaining: 20, viaWormhole: state.arrivedViaWormhole))
        events += continueTransit()
        return StepResult(events: events)
    }

    /// Runs transit clicks until an encounter is shown or the ship arrives (C# `Travel` loop + `Arrival`).
    mutating func continueTransit() -> [GameEvent] {
        guard case var .inTransit(t) = state.phase else { return [] }
        var events: [GameEvent] = []
        while t.clicksRemaining > 0 {
            state.performClickRepairs()
            let clicks = t.clicksRemaining
            if let enc = state.determineFixedEncounter(clicks: clicks) ?? state.determineRandomEncounter(clicks: clicks) {
                t.hadEncounter = true
                state.phase = .inTransit(t)
                state.encounterTransit = t
                state.phase = .encounter(enc)
                events.append(.encounterStarted(type: enc.type, opponent: enc.opponent.type, clicks: clicks))
                return events
            }
            t.clicksRemaining -= 1
        }
        if !t.hadEncounter { events.append(.uneventfulTrip) }
        state.phase = .docked
        events += state.arrival()
        return events
    }

    /// Ends the current encounter and resumes transit (C# `Clicks--` after the encounter form closes).
    mutating func finishEncounter(_ result: RoundResult) -> [GameEvent] {
        guard case .encounter = state.phase, var t = state.encounterTransit else { return [] }
        state.encounterTransit = nil
        switch result {
        case .killed:
            state.phase = .gameOver(.killed)
            return []
        case .escapePod:
            var events = state.escapeWithPod()
            state.phase = .docked
            events += state.arrival()
            return events
        case .arrested:
            state.phase = .docked
            return state.arrival()
        case .normal, .continue:
            t.clicksRemaining -= 1
            state.phase = .inTransit(t)
            return continueTransit()
        }
    }
}
