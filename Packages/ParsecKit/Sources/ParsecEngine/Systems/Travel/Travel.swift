// SPDX-License-Identifier: GPL-2.0-or-later
// Travel: warp, departure, resumable transit, encounter determination, arrival pipeline, IncDays.
// C# Game.Warp / NormalDeparture / Travel / Determine*Encounter / Arrival / IncDays (docs/specs/TRV.md, ENC.md).
import Foundation

/// TRV-086: the warp panel for one target system.
public struct WarpTargetPreview: Sendable, Equatable {
    public var target: Int
    public var distance: Int
    public var viaWormhole: Bool
    /// C# `DestOk`.
    public var inRange: Bool
    public var fuelAfter: Int
    public var costs: DailyCosts
    /// The error `.warp` would return (range first, then BNK-057 affordability); the Wild consent is separate.
    public var blocking: CommandError?
    public var wildWillLeave: Bool
}

/// TRV-087: the singularity jump button.
public struct JumpPreview: Sendable, Equatable {
    public var destination: Int
    /// `noSingularity` or `singularityTargetIsCurrentSystem`; nil when the jump can be confirmed.
    public var rejection: CommandError?
    /// The departure check that would fail after consent (the singularity would then be lost, TRV-021).
    public var blocking: CommandError?
    public var wildWillLeave: Bool
    public var available: Bool { rejection == nil }
}

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
    var policeRecord: PoliceRecordType { PoliceRecordType(score: commander.policeRecordScore) }

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

    /// TRV-014: Wild leaves unless the ship carries a qualifying laser (`wildRequiresRealLaser`, RUL-111).
    var wildWillLeave: Bool { wildOnBoard && !hasWildQualifyingLaser }

    /// TRV-086 / TRV-017: everything the warp panel shows for `target`, without changing state.
    func warpTargetPreview(_ target: Int) -> WarpTargetPreview {
        let cur = commander.currentSystem
        let via = galaxy.wormholeExists(from: cur, to: target)
        let distance = GalaxyGenerator.distance(galaxy.systems[cur], galaxy.systems[target], rule: ruleset.flags.distance)
        var copy = self
        copy.warpSystem = target
        let inRange = destinationOK(target)
        return WarpTargetPreview(target: target, distance: distance, viaWormhole: via, inRange: inRange,
                                 fuelAfter: commander.ship.fuel - (via ? 0 : distance), costs: dailyCosts(to: target),
                                 blocking: inRange ? copy.warpBlocker() : .destinationOutOfRange, wildWillLeave: wildWillLeave)
    }

    /// TRV-087: whether a singularity jump to the current target is possible, and what it would hit after consent.
    /// The Palm jump uses the tracked system (TRV-020, `singularityTargetSource`).
    var jumpPreview: JumpPreview {
        let tracked = ruleset.flags.travel.singularityTargetSource == .trackedSystem
        let destination = tracked ? (trackedSystem ?? warpSystem) : warpSystem
        let rejection: CommandError? = !quests.canSuperWarp ? .noSingularity
            : tracked && trackedSystem == nil ? .singularityNoTarget
            : destination == commander.currentSystem ? .singularityTargetIsCurrentSystem : nil
        var copy = self
        copy.warpSystem = destination
        return JumpPreview(destination: destination, rejection: rejection, blocking: copy.warpBlocker(), wildWillLeave: wildWillLeave)
    }

    /// TRV-088: the trip in progress (also while an encounter interrupts it); nil when docked or the game is over.
    var transitPreview: TransitState? {
        switch phase {
        case let .inTransit(t): t
        case .encounter: encounterTransit
        default: nil
        }
    }

    /// C# `Game.IncDays`; Palm `IncDays` only advances days and the Gemulon, reactor and experiment counters (TRV-074).
    mutating func incDays(_ n: Int) -> [GameEvent] {
        var events: [GameEvent] = []
        let tr = ruleset.flags.travel
        commander.days += n
        if commander.insurance, tr.noClaimTiming == .perDay { setNoClaim(commander.noClaim + n) }
        if tr.policeRecordDecay == .perDayDivision {
            if commander.policeRecordScore > 0 {
                commander.policeRecordScore = max(0, commander.policeRecordScore - n / 3)
            } else if commander.policeRecordScore < -5 {
                commander.policeRecordScore = min(-5, commander.policeRecordScore + n / (difficulty <= .normal ? 1 : difficulty.rawValue))
            }
        }
        let monsterMax = specialShips.spaceMonster.hullStrength(ruleset)
        if tr.monsterRegeneration == .compoundPerDay, specialShips.spaceMonster.hull < monsterMax {
            specialShips.spaceMonster.hull = min(monsterMax, Int(Double(specialShips.spaceMonster.hull) * pow(1.05, Double(n))))
        }
        if quests.gemulon > QuestStatus.Gemulon.notStarted, quests.gemulon < QuestStatus.Gemulon.tooLate {
            // TRV-076: Palm keeps counting past 8 (`invasionStatusCapped`).
            quests.gemulon = tr.invasionStatusCapped ? min(quests.gemulon + n, QuestStatus.Gemulon.tooLate) : quests.gemulon + n
            if quests.gemulon >= QuestStatus.Gemulon.tooLate {
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
                addNewsEvent(.experimentPerformed)
                events.append(.experimentPerformed)
            }
        } else if quests.experiment == QuestStatus.Experiment.performed, quests.fabricRipProbability > 0 {
            quests.fabricRipProbability -= n
        }
        for (onBoard, id) in [(jarekOnBoard, CrewID.jarek), (princessOnBoard, CrewID.princess), (wildOnBoard, CrewID.wild)]
        where onBoard && tr.passengerImpatience {
            events += impatience(id)
        }
        return events
    }

    /// Passenger impatience steps of IncDays (Jarek, Princess, Wild; TRV-079/080): a notice at the halfway status, then
    /// one step before impatient the notice that their skills drop to 0; the status rises by one per call.
    private mutating func impatience(_ id: Int) -> [GameEvent] {
        let status: Int, impatient: Int, concerned: Int
        switch id {
        case CrewID.jarek:
            (status, impatient) = (quests.jarek, QuestStatus.Jarek.impatient)
            concerned = impatient / 2
        case CrewID.princess:
            (status, impatient) = (quests.princess, QuestStatus.Princess.impatient)
            concerned = (impatient + QuestStatus.Princess.rescued) / 2
        default:
            (status, impatient) = (quests.wild, QuestStatus.Wild.impatient)
            concerned = impatient / 2
        }
        var events: [GameEvent] = []
        if status == concerned {
            events.append(.passengerConcerned(crewID: id))
        } else if status == impatient - 1 {
            events.append(.passengerImpatient(crewID: id))
            mercenaries[id].skills = [0, 0, 0, 0]
        }
        if status < impatient {
            switch id {
            case CrewID.jarek: quests.jarek += 1
            case CrewID.princess: quests.princess += 1
            default: quests.wild += 1
            }
        }
        return events
    }

    /// C# `Ship.PerformRepairs` for the commander's ship (each click).
    mutating func performClickRepairs() {
        var repairs = rng.next(below: shipSkills[3])
        if ruleset.flags.travel.inFlightRepairHalved { repairs >>= 1 }
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

    mutating func determinePirate(mantis: Bool, clicks: Int) -> EncounterState? {
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

    mutating func determinePolice(clicks: Int) -> EncounterState? {
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

    mutating func determineTrader(clicks: Int) -> EncounterState? {
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

    mutating func determineVeryRare(clicks: Int) -> EncounterState? {
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

    /// C# `NewsAddEventsOnArrival`; Palm adds its else-if chain of flags (NEWS-038) when System Information opens.
    mutating func addArrivalNews() {
        guard let ev = currentSystem.specialEvent else { return }
        if ruleset.flags.travel.newsEventOrdering == .palmFixed {
            if let add = palmArrivalNews(ev) { addNewsEvent(add) }
            return
        }
        if let add = arrivalNewsQuests(ev) ?? arrivalNewsOthers(ev) { addNewsEvent(add) }
    }

    /// Palm `SystemInformationFormHandleEvent` news flags (NEWS-038): first match only, each with its status test.
    private func palmArrivalNews(_ ev: SpecialEventType) -> NewsEvent? {
        let q = quests
        switch ev {
        case .spaceMonsterKilled: return q.spaceMonster == QuestStatus.SpaceMonster.destroyed ? .spaceMonsterKilled : nil
        case .dragonfly: return .dragonfly
        case .scarab: return .scarab
        case .scarabDestroyed: return q.scarab == QuestStatus.Scarab.destroyed ? .scarabDestroyed : nil
        case .dragonflyBaratas: return q.dragonfly == QuestStatus.Dragonfly.flyBaratas ? .dragonflyBaratas : nil
        case .dragonflyMelina: return q.dragonfly == QuestStatus.Dragonfly.flyMelina ? .dragonflyMelina : nil
        case .dragonflyRegulas: return q.dragonfly == QuestStatus.Dragonfly.flyRegulas ? .dragonflyRegulas : nil
        case .dragonflyDestroyed: return q.dragonfly == QuestStatus.Dragonfly.destroyed ? .dragonflyDestroyed : nil
        case .japoriDelivery: return q.japori == QuestStatus.Japori.inTransit ? .japoriDelivery : nil
        case .artifactDelivery: return artifactOnBoard ? .artifactDelivery : nil
        case .japori: return q.japori == QuestStatus.Japori.notStarted ? .japori : nil
        case .jarekGetsOut: return q.jarek == QuestStatus.Jarek.started ? .jarekGetsOut : nil
        case .wildGetsOut: return q.wild == QuestStatus.Wild.started ? .wildGetsOut : nil
        case .gemulonRescued:
            return q.gemulon > QuestStatus.Gemulon.notStarted && q.gemulon < QuestStatus.Gemulon.tooLate ? .gemulonRescued : nil
        case .gemulon: return .gemulon
        case .experimentStopped:
            return q.experiment > QuestStatus.Experiment.notStarted && q.experiment < QuestStatus.Experiment.performed
                ? .experimentStopped : nil
        case .experimentFailed: return .experimentFailed
        default: return nil
        }
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

    /// C# `ArrivalCheckTribbles` (QST-TRIBBLES-005…010): branch notices, then `tribblesChanged`.
    mutating func arrivalTribbles() -> [GameEvent] {
        let before = commander.ship.tribbles
        guard before > 0 else { return [] }
        if ruleset.flags.travel.tribbleAlgorithm == .palm { return palmArrivalTribbles() }
        var events: [GameEvent] = []
        let narc = TradeItemType.narcotics.rawValue, food = TradeItemType.food.rawValue
        let maxTribbles = 100_000
        if reactorOnBoard {
            let all = commander.ship.tribbles < 20
            commander.ship.tribbles = all ? 0 : commander.ship.tribbles / 2
            events.append(.tribblesDied(all ? .allFromReactor : .halfFromReactor))
        } else if commander.ship.cargo[narc] > 0 {
            let held = commander.ship.cargo[narc]
            let dead = min(1 + rng.next(below: 3), held)
            commander.priceCargo[narc] = commander.priceCargo[narc] * (held - dead) / held
            commander.ship.cargo[narc] -= dead
            commander.ship.cargo[TradeItemType.furs.rawValue] += dead
            commander.ship.tribbles -= min(dead * (rng.next(below: 5) + 98), commander.ship.tribbles - 1)
            events.append(.tribblesDied(.narcotics(converted: dead)))
        } else {
            if commander.ship.cargo[food] > 0, commander.ship.tribbles < maxTribbles {
                let held = commander.ship.cargo[food]
                let eaten = held - rng.next(below: held)
                commander.priceCargo[food] -= commander.priceCargo[food] * eaten / held
                commander.ship.cargo[food] -= eaten
                commander.ship.tribbles += eaten * 100
                events.append(.tribblesAteFood(eaten: eaten))
            }
            if commander.ship.tribbles < maxTribbles {
                commander.ship.tribbles += 1 + rng.next(below: commander.ship.cargo[food] > 0 ? commander.ship.tribbles : commander.ship.tribbles / 2)
            }
            if commander.ship.tribbles > maxTribbles { commander.ship.tribbles = maxTribbles }
            let now = commander.ship.tribbles
            if [100, 1_000, 10_000, 50_000].contains(where: { before < $0 && now >= $0 }) || (before < maxTribbles && now == maxTribbles) {
                events.append(.tribbleInspectorWarning(count: now))
            }
        }
        tribbleMessage = false
        return events + [.tribblesChanged(from: before, to: commander.ship.tribbles)]
    }

    /// Palm tribble update (RUL-151): every branch then grows by `1 + rand(max(1, T >> (food eaten ? 0 : 1)))`.
    private mutating func palmArrivalTribbles() -> [GameEvent] {
        let before = commander.ship.tribbles
        var events: [GameEvent] = []
        let narc = TradeItemType.narcotics.rawValue, food = TradeItemType.food.rawValue
        let maxTribbles = 100_000
        var foodOnBoard = false
        if reactorOnBoard {
            commander.ship.tribbles /= 2
            let all = commander.ship.tribbles < 10
            if all { commander.ship.tribbles = 0 }
            events.append(.tribblesDied(all ? .allFromReactor : .halfFromReactor))
        } else if commander.ship.cargo[narc] > 0 {
            commander.ship.tribbles = 1 + rng.next(below: 3)
            let held = commander.ship.cargo[narc]
            let dead = min(1 + rng.next(below: 3), held)
            commander.priceCargo[narc] = commander.priceCargo[narc] * (held - dead) / held
            commander.ship.cargo[narc] -= dead
            commander.ship.cargo[TradeItemType.furs.rawValue] += dead
            events.append(.tribblesDied(.narcotics(converted: dead)))
        } else if commander.ship.cargo[food] > 0 {
            let held = commander.ship.cargo[food]
            commander.ship.tribbles += 100 + rng.next(below: held * 100)
            let left = rng.next(below: held)
            commander.priceCargo[food] = commander.priceCargo[food] * left / held
            commander.ship.cargo[food] = left
            events.append(.tribblesAteFood(eaten: held - left))
            foodOnBoard = true
        }
        let t = commander.ship.tribbles
        if t > 0, t < maxTribbles {
            commander.ship.tribbles += 1 + rng.next(below: max(1, t >> (foodOnBoard ? 0 : 1)))
        }
        commander.ship.tribbles = min(commander.ship.tribbles, maxTribbles)
        let now = commander.ship.tribbles
        if [100, 1_000, 10_000, 50_000].contains(where: { before < $0 && now >= $0 }) {
            events.append(.tribbleInspectorWarning(count: now))
        }
        tribbleMessage = false
        return events + [.tribblesChanged(from: before, to: now)]
    }

    /// C# `ArrivalPerformRepairs` (auto fuel/repair all-or-nothing); Palm repairs always draw, shields were recharged at
    /// departure and auto-buy is partial (TRV-063/064).
    mutating func arrivalRepairs() -> [GameEvent] {
        var events: [GameEvent] = []
        let r = ruleset, tr = r.flags.travel
        let strength = commander.ship.hullStrength(r)
        if tr.arrivalPipelineOrder == .palm {
            commander.ship.hull = min(strength, commander.ship.hull + rng.next(below: shipSkills[3]))
        } else if commander.ship.hull < strength {
            commander.ship.hull += min(strength - commander.ship.hull, rng.next(below: shipSkills[3]))
        }
        if tr.shieldRechargeTiming == .onArrival { rechargeShields() }
        if tr.arrivalAutoBuyPartial { return palmAutoBuy() }
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

    /// Every shield back to its power.
    mutating func rechargeShields() {
        for i in commander.ship.shields.indices {
            commander.ship.shields[i].charge = ruleset.tables.shield(commander.ship.shields[i].type).power
        }
    }

    /// Palm `BuyFuel(999)` / `BuyRepairs(9999)` on arrival (TRV-064): buys what cash allows.
    private mutating func palmAutoBuy() -> [GameEvent] {
        var events: [GameEvent] = []
        let r = ruleset, spec = commander.ship.spec(r)
        let tanks = commander.ship.fuelTanks(r), strength = commander.ship.hullStrength(r)
        var tryRepair = true
        if options.autoFuel {
            let amount = max(0, min(999, (tanks - commander.ship.fuel) * spec.fuelCost, commander.cash))
            let parsecs = amount / spec.fuelCost
            commander.ship.fuel += parsecs
            commander.cash -= parsecs * spec.fuelCost
            if commander.ship.fuel < tanks {
                if options.autoRepair, commander.ship.hull < strength {
                    events += [.autoFuelFailed, .autoRepairFailed]
                    tryRepair = false
                } else {
                    events.append(.autoFuelFailed)
                }
            }
        }
        if options.autoRepair, tryRepair {
            let amount = max(0, min(9_999, (strength - commander.ship.hull) * spec.repairCost, commander.cash))
            let points = amount / spec.repairCost
            commander.ship.hull += points
            commander.cash -= points * spec.repairCost
            if commander.ship.hull < strength { events.append(.autoRepairFailed) }
        }
        return events
    }

    /// C# `ArrivalCheckEasterEgg` (Og: exactly one unit of every good and a free shield slot → Lightning shield).
    /// Palm shows the message even without a free slot (TRV-066, `eggMessageWithoutSlot`).
    mutating func arrivalEasterEgg() -> [GameEvent] {
        guard commander.currentSystem == SystemID.og, commander.ship.cargo.allSatisfy({ $0 == 1 }) else { return [] }
        guard commander.ship.freeShieldSlots(ruleset) > 0 else {
            return ruleset.flags.travel.eggMessageWithoutSlot ? [.easterEggNoShieldSlot] : []
        }
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

    /// C# `CreateFlea`.
    mutating func createFlea() {
        var flea = Ship(type: .flea, spec: ruleset.tables.ship(.flea))
        flea.crew[0] = CrewID.commander
        commander.ship = flea
        commander.insurance = false
        commander.noClaim = 0
        if ruleset.flags.resetPriceCargoOnHoldClear { commander.priceCargo = Array(repeating: 0, count: 10) }
    }

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
    private mutating func palmEscapeWithPod() -> [GameEvent] {
        arrivalMarket()
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
        } else {
            arrivalMarket()
        }
        palmSystemInformation()
        return events + [.arrived(system: commander.currentSystem)]
    }

    /// Palm arrival pipeline (TRV-060): debt → Arrival() → reactor → tracking → tribbles → repair → auto-buy → egg.
    private mutating func palmArrival() -> [GameEvent] {
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

    /// C# `Arrival` (the reactor meltdown path may end the game); Palm order per `arrivalPipelineOrder`.
    mutating func arrival() -> [GameEvent] {
        if ruleset.flags.travel.arrivalPipelineOrder == .palm { return palmArrival() }
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
                return events + [endGame(.killed)]
            }
        } else if [QuestStatus.Reactor.fuelOK + 1, QuestStatus.Reactor.date - 4, QuestStatus.Reactor.date - 2].contains(quests.reactor) {
            events.append(.reactorWarning(status: quests.reactor))
        }
        events += arrivalTribbles()
        events += debtNotices()
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
    // MARK: Target selection (TRV-003/004/007)

    /// C# `SelectedSystemId` setter: any system, in range or not.
    mutating func selectTarget(_ s: Int) -> StepResult {
        guard docked else { return .rejected(.notAllowedInPhase) }
        guard state.galaxy.systems.indices.contains(s) else { return .rejected(.invalidArgument) }
        state.warpSystem = s
        state.targetWormhole = false
        return StepResult()
    }

    /// C# `TargetWormhole` setter: targets the far end of the wormhole at `w` (any wormhole system).
    mutating func selectWormhole(_ w: Int) -> StepResult {
        guard docked else { return .rejected(.notAllowedInPhase) }
        guard let k = state.galaxy.wormholes.firstIndex(of: w) else { return .rejected(.invalidArgument) }
        if ruleset.flags.travel.wormholeSelectionScope == .currentSystemOnly, w != state.commander.currentSystem {
            return .rejected(.wormholeNotAtCurrentSystem)
        }
        state.warpSystem = state.galaxy.wormholes[(k + 1) % state.galaxy.wormholes.count]
        state.targetWormhole = true
        return StepResult()
    }

    /// C# `Game.SelectNextSystemWithinRange`.
    mutating func selectNextTarget(forward: Bool) -> StepResult {
        guard docked else { return .rejected(.notAllowedInPhase) }
        if ruleset.flags.travel.nextTargetOrdering == .indexScan { return palmNextTarget(forward: forward) }
        let dest = state.destinations
        guard !dest.isEmpty else { return StepResult() }
        var index: Int
        if let i = dest.firstIndex(of: state.warpSystem) {
            index = (dest.count + i + (forward ? 1 : -1)) % dest.count
        } else {
            index = forward ? 0 : dest.count - 1
        }
        let cur = state.commander.currentSystem
        if state.galaxy.wormholeExists(from: cur, to: dest[index]) { return selectWormhole(cur) }
        return selectTarget(dest[index])
    }

    /// Palm `NextSystemWithinRange` (TRV-008): scan indices from the old target with wrap-around.
    private mutating func palmNextTarget(forward: Bool) -> StepResult {
        let n = state.galaxy.systems.count, start = state.warpSystem
        var i = start
        while true {
            i = (i + (forward ? 1 : -1) + n) % n
            if i == start { return StepResult() }
            if state.destinationOK(i) { break }
        }
        let cur = state.commander.currentSystem
        if state.galaxy.wormholeExists(from: cur, to: i) { return selectWormhole(cur) }
        return selectTarget(i)
    }

    // MARK: Warp and jump

    /// C# `Game.Warp` / Palm `DoWarp` (TRV): checks, departure, then transit until an encounter or arrival.
    /// A jump (C# `btnJump_Click`) asks for `.useSingularity` consent and consumes the singularity before the checks.
    mutating func warp(viaSingularity: Bool, _ ack: Set<WarningID>) -> StepResult {
        guard docked else { return .rejected(.notAllowedInPhase) }
        let wildFirst = ruleset.flags.travel.warpCheckOrder == .wildFirst
        var destination = state.warpSystem
        if viaSingularity {
            let jump = state.jumpPreview
            if let error = jump.rejection { return .rejected(error) }
            guard ack.contains(.useSingularity) else {
                return .needsConfirmation(Confirmation(.useSingularity, amounts: [jump.destination]))
            }
            destination = jump.destination
            if !wildFirst, let blocker = jump.blocking {
                state.quests.canSuperWarp = false
                return StepResult(events: [.singularityLost, .departureBlocked(blocker)])
            }
        } else {
            let preview = state.warpTargetPreview(destination)
            if !preview.inRange { return .rejected(.destinationOutOfRange) }
            if !wildFirst, let blocker = preview.blocking { return .rejected(blocker) }
        }
        if state.wildWillLeave, !ack.contains(.wildLeavesWithoutLaser) {
            return .needsConfirmation(Confirmation(.wildLeavesWithoutLaser))
        }
        // Consent given: commit the jump target and the Wild departure (Palm checks the funds only afterwards, TRV-015).
        var events: [GameEvent] = []
        state.warpSystem = destination
        if viaSingularity { state.quests.canSuperWarp = false }
        if state.wildWillLeave {
            state.quests.wild = QuestStatus.Wild.notStarted
            events.append(.wildLeftShip)
        }
        if wildFirst, let blocker = state.warpBlocker() {
            if viaSingularity { events.insert(.singularityLost, at: 0) }
            if events.isEmpty { return .rejected(blocker) }
            return StepResult(events: events + [.departureBlocked(blocker)])
        }
        events += state.depart(viaSingularity: viaSingularity)
        state.phase = .inTransit(TransitState(destination: state.warpSystem, clicksRemaining: ruleset.flags.travel.transitClicks,
                                              viaWormhole: state.arrivedViaWormhole))
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
                state.encounterTransit = t
                events.append(startEncounter(enc))
                return events
            }
            t.clicksRemaining -= 1
        }
        if !t.hadEncounter { events.append(.uneventfulTrip) }
        state.phase = .docked
        events += state.arrival()
        return events
    }

    /// Enters the encounter phase for a shown encounter (C# FormEncounter constructor + EncounterActionInitial).
    mutating func startEncounter(_ shown: EncounterState) -> GameEvent {
        var enc = shown
        // ENC-110: the opponent starts fleeing only for an initial flee type.
        enc.oppFleeing = [.pirateFlee, .policeFlee, .traderFlee].contains(enc.type)
        // ENC-087: the cosmetic tribble-sprite draws of C# UpdateTribbles keep the game RNG in step.
        let toShow = min(36, Int((Double(state.commander.ship.tribbles) / 74.0).squareRoot()))
        for _ in 0..<toShow {
            _ = state.rng.next(below: 36)
            _ = state.rng.next(below: 8)
        }
        state.phase = .encounter(enc)
        // ENC-112: "doesn't notice you" applies to an ignore type caused by the player's cloak.
        let ignoreTypes: [EncounterType] = [.dragonflyIgnore, .pirateIgnore, .policeIgnore, .scarabIgnore, .scorpionIgnore,
                                            .spaceMonsterIgnore, .traderIgnore]
        return .encounterStarted(type: enc.type, opponent: enc.opponent.type, clicks: enc.clicks,
                                 playerCloaked: ignoreTypes.contains(enc.type) && state.commanderCloaked)
    }

    /// Ends the current encounter and resumes transit (C# `Clicks--` after the encounter form closes).
    mutating func finishEncounter(_ result: RoundResult) -> [GameEvent] {
        guard case let .encounter(enc) = state.phase, var t = state.encounterTransit else { return [] }
        // ENC-012: plunder/surrender changes to a quest ship persist too (rounds persist in executeRound).
        state.persistSpecialShip(enc.opponent)
        state.encounterTransit = nil
        switch result {
        case .killed:
            return [state.endGame(.killed)]
        case .escapePod:
            state.phase = .docked
            return state.arrivalAfterArrestOrPod(pod: true)
        case .arrested:
            state.phase = .docked
            return state.arrivalAfterArrestOrPod(pod: false)
        case .normal, .continue:
            t.clicksRemaining -= 1
            state.phase = .inTransit(t)
            return continueTransit()
        }
    }
}

public extension GameState {
    /// The departure after every check passed (C# `NormalDeparture` + the jump branch of `Warp`; Palm `DoWarp`, TRV-031).
    /// Ends with the fabric-rip test of `Travel()`; the transit flags are cleared.
    internal mutating func depart(viaSingularity: Bool) -> [GameEvent] {
        let tr = ruleset.flags.travel
        var events: [GameEvent] = []
        let from = commander.currentSystem, target = warpSystem
        let wormhole = galaxy.wormholeExists(from: from, to: target)
        let palmJump = viaSingularity && tr.singularitySideEffects == .palm
        arrivedViaWormhole = wormhole || palmJump
        if !viaSingularity {
            let distance = wormhole ? 0 : GalaxyGenerator.distance(galaxy.systems[from], galaxy.systems[target], rule: ruleset.flags.distance)
            commander.cash -= mercenaryCosts + insuranceCosts + wormholeCosts
            commander.ship.fuel -= min(distance, commander.ship.fuel)
        }
        if tr.shieldRechargeTiming == .atDeparture { rechargeShields() }
        if tr.newsResetBeforeDayAdvance { newsEvents.removeAll() }
        if viaSingularity {
            addNewsEvent(.experimentArrival)
        } else {
            payInterest()
            events += incDays(1)
            if commander.insurance, tr.noClaimTiming == .perWarp { setNoClaim(commander.noClaim + 1) }
        }
        if tr.monsterRegeneration == .perWarp, !viaSingularity || palmJump {
            let monsterMax = specialShips.spaceMonster.hullStrength(ruleset)
            specialShips.spaceMonster.hull = min(monsterMax, specialShips.spaceMonster.hull * 105 / 100)
        }
        if tr.policeRecordDecay == .perWarp { perWarpRecordDecay() }
        setDepartureCountdown()
        if !tr.newsResetBeforeDayAdvance { newsEvents.removeAll() }
        calculatePrices(for: target)
        events.append(.departed(from: from, to: target, viaWormhole: arrivedViaWormhole))
        // Travel(): fabric rip (Palm draws before testing for 25, TRV-037).
        let p = quests.fabricRipProbability
        if quests.experiment == QuestStatus.Experiment.performed, p > 0 {
            let rip = tr.fabricRipDrawFirst ? (rng.next(below: 100) < p || p == 25) : (p == 25 || rng.next(below: 100) < p)
            if rip {
                warpSystem = rng.next(below: galaxy.systems.count)
                targetWormhole = false
                events.append(.fabricRip(newDestination: warpSystem))
            }
        }
        raided = false
        inspected = false
        litterWarning = false
        return events
    }

    /// MOD-003 / Palm per-warp record decay (TRV-033), using `days` after the departure's day advance.
    internal mutating func perWarpRecordDecay() {
        let days = commander.days
        if days % 3 == 0, commander.policeRecordScore > 0 { commander.policeRecordScore -= 1 }
        if commander.policeRecordScore < -5 {
            if difficulty <= .normal || days % difficulty.rawValue == 0 { commander.policeRecordScore += 1 }
        }
    }

    /// Stores a news flag; Palm keeps at most `newsEventCapacity` (NEWS-035).
    mutating func addNewsEvent(_ event: NewsEvent) {
        if let cap = ruleset.flags.travel.newsEventCapacity, newsEvents.count >= cap { return }
        newsEvents.append(event)
    }

    /// A famous captain was destroyed: C# turns the last event into its "destroyed" successor; Palm
    /// `replaceNewsEvent(latest, latest + 10)` replaces every stored copy of the latest flag (NEWS-036).
    internal mutating func markFamousCaptainDestroyed() {
        guard let last = newsEvents.last else { return }
        guard ruleset.flags.travel.newsEventOrdering == .palmFixed else {
            if let destroyed = NewsEvent(rawValue: last.rawValue + 1) { newsEvents[newsEvents.count - 1] = destroyed }
            return
        }
        // Palm flag codes: 90 WILDARRESTED, 91 CAUGHTLITTERING, 92 EXPERIMENTPERFORMED, 100…102 attacked, 110…112 destroyed.
        let codes: [NewsEvent: Int] = [.wildArrested: 90, .caughtLittering: 91, .experimentPerformed: 92,
                                       .captHuieAttacked: 100, .captConradAttacked: 101, .captAhabAttacked: 102,
                                       .captHuieDestroyed: 110, .captConradDestroyed: 111, .captAhabDestroyed: 112]
        guard let code = codes[last], let replacement = codes.first(where: { $0.value == code + 10 })?.key else { return }
        newsEvents = newsEvents.map { $0 == last ? replacement : $0 }
    }
}
