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

    /// TRV-014: Wild leaves unless the ship carries a beam laser or better (C# `HasWeapon(BeamLaser, false)`).
    var wildWillLeave: Bool { wildOnBoard && !hasLaserForWild }

    /// RUL-111 (MOD-011): Wild accepts a Beam, Military or Morgan's laser; C# also accepts any higher enum (disruptors).
    var hasLaserForWild: Bool {
        guard ruleset.flags.encounter.wildRequiresRealLaser else { return commander.ship.has(.beamLaser, exact: false) }
        return commander.ship.weapons.contains { $0 == .beamLaser || $0 == .militaryLaser || $0 == .morgansLaser }
    }

    /// RUL-103 / POL-011 (MOD-003): Palm's per-warp record drift, run once per warp including singularity jumps.
    mutating func applyPerWarpRecordDecay() {
        guard ruleset.flags.encounter.policeRecordDecay == .perWarp else { return }
        if commander.days % 3 == 0, commander.policeRecordScore > 0 { commander.policeRecordScore -= 1 }
        if commander.policeRecordScore < -5, difficulty <= .normal || commander.days % difficulty.rawValue == 0 {
            commander.policeRecordScore += 1
        }
    }

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
    var jumpPreview: JumpPreview {
        let rejection: CommandError? = !quests.canSuperWarp ? .noSingularity
            : warpSystem == commander.currentSystem ? .singularityTargetIsCurrentSystem : nil
        return JumpPreview(destination: warpSystem, rejection: rejection, blocking: warpBlocker(), wildWillLeave: wildWillLeave)
    }

    /// TRV-088: the trip in progress (also while an encounter interrupts it); nil when docked or the game is over.
    var transitPreview: TransitState? {
        switch phase {
        case let .inTransit(t): t
        case .encounter: encounterTransit
        default: nil
        }
    }

    /// C# `Game.IncDays`.
    mutating func incDays(_ n: Int) -> [GameEvent] {
        var events: [GameEvent] = []
        commander.days += n
        if commander.insurance { setNoClaim(commander.noClaim + n) }
        if ruleset.flags.encounter.policeRecordDecay == .perWarp {
            // RUL-103: no drift inside IncDays (jail and escape-pod days included).
        } else if commander.policeRecordScore > 0 {
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
        if clicks == 1, quests.justLootedMarie, !ruleset.flags.encounter.postMarieCustomsAfterLoop {
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
            let rules = ruleset.flags.encounter
            if roll < pir {
                // RUL-071: Palm turns a raided pirate roll into a police encounter.
                if !raided { pirate = true } else if rules.raidedPirateRollBecomesPolice { police = true }
            } else if roll < pir + pol * policeMod {
                police = true
            } else if roll < pir + pol * policeMod + tra {
                trader = true
            } else if wildOnBoard, warpSystem == SystemID.kravat {
                police = rng.next(below: 100) < 100 / max(2, min(4, 5 - difficulty.rawValue))
            } else if !rules.artifactMantisWhenNoBand, artifactOnBoard, rng.next(below: 20) <= 3 {
                mantis = true
            }
            // RUL-072: Palm runs the Mantis roll whenever no band flag is set (also after a failed Kravat roll).
            if rules.artifactMantisWhenNoBand, !(pirate || police || trader), artifactOnBoard, rng.next(below: 20) <= 3 {
                mantis = true
            }
        }
        if police { return determinePolice(clicks: clicks) }
        if pirate || mantis { return determinePirate(mantis: mantis, clicks: clicks) }
        if trader { return determineTrader(clicks: clicks) }
        let allSix = ruleset.flags.encounter.veryRareSelection == .allSix
        if commander.days > 10, rng.next(below: 1000) < chanceOfVeryRareEncounter, allSix || !veryRareEncounters.isEmpty {
            return determineVeryRare(clicks: clicks)
        }
        return nil
    }

    mutating func determinePirate(mantis: Bool, clicks: Int) -> EncounterState? {
        let opp = generateOpponent(mantis ? .mantis : .pirate)
        lastOpponent = opp
        let type = mantis ? EncounterType.pirateAttack : pirateReaction(opp)
        let shown = type == .pirateAttack || !(opponentCloaked(opp) || options.alwaysIgnorePirates)
        return shown ? EncounterState(type: type, opponent: opp, clicks: clicks) : nil
    }

    /// ENC-100…103: how a (non-Mantis) pirate reacts to the commander.
    mutating func pirateReaction(_ opp: Ship) -> EncounterType {
        if commanderCloaked { return .pirateIgnore }
        if ruleset.flags.encounter.outclassCheckAfterReaction {
            // ENC-103: Palm draws unless the opponent is type ≥ 7, then a flee against a weaker player becomes attack.
            let attack = opp.type.rawValue >= ShipType.grasshopper.rawValue
                || rng.next(below: 1_500) > (commander.reputationScore * 4) / (1 + opp.type.rawValue)
            return attack || opp.type.rawValue > commander.ship.type.rawValue ? .pirateAttack : .pirateFlee
        }
        if opp.type.rawValue > commander.ship.type.rawValue || opp.type.rawValue >= ShipType.grasshopper.rawValue
            || rng.next(below: 1_500) > (commander.reputationScore * 4) / (1 + opp.type.rawValue) {
            return .pirateAttack
        }
        return .pirateFlee
    }

    mutating func determinePolice(clicks: Int) -> EncounterState? {
        let opp = generateOpponent(.police)
        lastOpponent = opp
        let type = policeReaction(opp)
        let shown = type == .policeAttack || type == .policeInspect || !(opponentCloaked(opp) || options.alwaysIgnorePolice)
        return shown ? EncounterState(type: type, opponent: opp, clicks: clicks) : nil
    }

    /// ENC-104…106: how police react to the commander (sets `inspected` for an inspection).
    mutating func policeReaction(_ opp: Ship) -> EncounterType {
        var type: EncounterType = .policeIgnore
        let rules = ruleset.flags.encounter
        let rec = commander.policeRecordScore
        if !commanderCloaked {
            if rec < -5 {
                // RUL-087: Palm police attack criminals even without weapons; RUL-086: no surrender demand in Palm.
                let armed = rules.unarmedPoliceAttack || opp.weaponStrength(ruleset) > 0
                let outclassed = opp.type.rawValue > commander.ship.type.rawValue
                let attackType: EncounterType = rules.policeSurrenderState && rec >= rules.policeConstants.criminal ? .policeSurrender : .policeAttack
                let draws = armed && (commander.reputationScore < 40
                    || rng.next(below: 1_500) > commander.reputationScore / (1 + opp.type.rawValue))
                if draws || (outclassed && !rules.outclassCheckAfterReaction) {
                    type = attackType
                } else if opponentCloaked(opp) {
                    type = .policeIgnore
                } else {
                    type = outclassed ? attackType : .policeFlee // ENC-106: Palm's flee → attack when outclassed
                }
            } else if rules.inspectionDrawWhenInspected {
                // ENC-106: Palm draws the clean / lawful inspection roll even when already inspected.
                if rec < 0, !inspected {
                    type = .policeInspect
                } else if rec < 5 {
                    if rng.next(below: 12 - difficulty.rawValue) < 1, !inspected { type = .policeInspect }
                } else if rng.next(below: 40) == rules.lawfulInspectionRoll, !inspected {
                    type = .policeInspect
                }
                if type == .policeInspect { inspected = true }
            } else if !inspected, rec < 0
                        || (rec < 5 && rng.next(below: 12 - difficulty.rawValue) < 1)
                        || (rec >= 5 && rng.next(below: 40) == rules.lawfulInspectionRoll) {
                type = .policeInspect
                inspected = true
            }
        }
        return type
    }

    mutating func determineTrader(clicks: Int) -> EncounterState? {
        let opp = generateOpponent(.trader)
        lastOpponent = opp
        var type: EncounterType = .traderIgnore
        if !commanderCloaked {
            if commander.policeRecordScore <= ruleset.flags.encounter.policeConstants.criminal, // RUL-089
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
        let rules = ruleset.flags.encounter
        let allSix = rules.veryRareSelection == .allSix
        let pick: VeryRareEncounter
        if allSix {
            // RUL-073 / ENC-046: Palm draws rand(6) over all six; an already-used entry yields nothing.
            pick = VeryRareEncounter.allCases[rng.next(below: VeryRareEncounter.allCases.count)]
            guard veryRareEncounters.contains(pick) else { return nil }
        } else {
            pick = veryRareEncounters[rng.next(below: veryRareEncounters.count)]
        }
        let cmdrRaw = mercenaries[CrewID.commander].skills
        let captainRecordOK = commander.policeRecordScore > rules.policeConstants.criminal // RUL-074
        func remove(_ v: VeryRareEncounter) { veryRareEncounters.removeAll { $0 == v } }
        switch pick {
        case .marieCeleste:
            if rules.marieCelesteRestricted {
                let here = ruleset.flags.marieCelesteChecksDestination ? warpSystem : commander.currentSystem
                guard clicks > 1, here != SystemID.acamar, here != SystemID.zalkon, here != SystemID.qonos else { return nil }
            }
            remove(.marieCeleste)
            var opp = generateOpponent(.trader)
            opp.cargo = Array(repeating: 0, count: 10)
            // ENC-046: Palm caps the narcotics with the ship type's base bays.
            let bays = allSix ? opp.spec(ruleset).cargoBays : opp.cargoBays(ruleset)
            opp.cargo[TradeItemType.narcotics.rawValue] = min(bays, 5)
            lastOpponent = opp
            return EncounterState(type: .marieCeleste, opponent: opp, clicks: clicks)
        case .captainAhab:
            guard commander.ship.has(.reflective), cmdrRaw[0] < 10, captainRecordOK else { return nil }
            remove(.captainAhab)
            return famous(.captainAhab, clicks)
        case .captainConrad:
            guard commander.ship.has(.militaryLaser), cmdrRaw[3] < 10, captainRecordOK else { return nil }
            remove(.captainConrad)
            return famous(.captainConrad, clicks)
        case .captainHuie:
            guard commander.ship.has(.militaryLaser), cmdrRaw[2] < 10, captainRecordOK else { return nil }
            remove(.captainHuie)
            return famous(.captainHuie, clicks)
        case .bottleOld, .bottleGood:
            remove(pick)
            var opp = generateOpponent(.bottle)
            if allSix {
                // ENC-046: Palm generates a full trader (consuming its draws), then makes it a bottle with hull 10.
                _ = generateOpponent(.trader)
                opp.hull = 10
            }
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

    /// C# `ArrivalCheckTribbles` (QST-TRIBBLES-005…010): branch notices, then `tribblesChanged`.
    mutating func arrivalTribbles() -> [GameEvent] {
        let before = commander.ship.tribbles
        guard before > 0 else { return [] }
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

    /// POL-107: Palm's `EscapeWithPod` (RUL-099 Scarab reset, short Arrival first, reactor and artifact lost).
    private mutating func escapeWithPodPalm() -> [GameEvent] {
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
        events.append(.arrived(system: commander.currentSystem))
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
                return events + [endGame(.killed)]
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
        state.warpSystem = state.galaxy.wormholes[(k + 1) % state.galaxy.wormholes.count]
        state.targetWormhole = true
        return StepResult()
    }

    /// C# `Game.SelectNextSystemWithinRange`.
    mutating func selectNextTarget(forward: Bool) -> StepResult {
        guard docked else { return .rejected(.notAllowedInPhase) }
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

    // MARK: Warp and jump

    /// C# `Game.Warp` (TRV): checks, departure, then transit until an encounter or arrival.
    /// A jump (C# `btnJump_Click`) asks for `.useSingularity` consent and consumes the singularity before the checks.
    mutating func warp(viaSingularity: Bool, _ ack: Set<WarningID>) -> StepResult {
        guard docked else { return .rejected(.notAllowedInPhase) }
        let target = state.warpSystem
        if viaSingularity {
            let jump = state.jumpPreview
            if let error = jump.rejection { return .rejected(error) }
            guard ack.contains(.useSingularity) else {
                return .needsConfirmation(Confirmation(.useSingularity, amounts: [target]))
            }
            if let blocker = jump.blocking {
                state.quests.canSuperWarp = false
                return StepResult(events: [.singularityLost, .departureBlocked(blocker)])
            }
        } else if let blocker = state.warpTargetPreview(target).blocking {
            return .rejected(blocker)
        }
        var events: [GameEvent] = []
        if state.wildWillLeave {
            guard ack.contains(.wildLeavesWithoutLaser) else {
                return .needsConfirmation(Confirmation(.wildLeavesWithoutLaser))
            }
            state.quests.wild = QuestStatus.Wild.notStarted
            events.append(.wildLeftShip)
        }
        let from = state.commander.currentSystem
        state.arrivedViaWormhole = state.galaxy.wormholeExists(from: from, to: target)
        if viaSingularity {
            state.quests.canSuperWarp = false
            state.newsEvents.append(.experimentArrival)
        } else {
            let distance = state.arrivedViaWormhole ? 0
                : GalaxyGenerator.distance(state.galaxy.systems[from], state.galaxy.systems[target], rule: ruleset.flags.distance)
            state.commander.cash -= state.mercenaryCosts + state.insuranceCosts + state.wormholeCosts
            state.commander.ship.fuel -= distance
            state.payInterest()
            events += state.incDays(1)
        }
        state.applyPerWarpRecordDecay()
        state.setDepartureCountdown()
        state.newsEvents.removeAll()
        state.calculatePrices(for: target)
        events.append(.departed(from: from, to: target, viaWormhole: state.arrivedViaWormhole))
        // Travel(): fabric rip
        if state.quests.experiment == QuestStatus.Experiment.performed, state.quests.fabricRipProbability > 0,
           state.quests.fabricRipProbability == 25 || state.rng.next(below: 100) < state.quests.fabricRipProbability {
            state.warpSystem = state.rng.next(below: state.galaxy.systems.count)
            state.targetWormhole = false
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
                state.encounterTransit = t
                events.append(startEncounter(enc))
                return events
            }
            t.clicksRemaining -= 1
        }
        if state.ruleset.flags.encounter.postMarieCustomsAfterLoop, state.quests.justLootedMarie {
            // RUL-070 / ENC-004: Palm's customs appear after the loop; `Clicks++` makes the resumed trip arrive at once.
            let opp = state.generateOpponent(.police)
            state.lastOpponent = opp
            state.quests.justLootedMarie = false
            t.clicksRemaining = 1
            t.hadEncounter = true
            state.encounterTransit = t
            events.append(startEncounter(EncounterState(type: .marieCelestePolice, opponent: opp, clicks: 1)))
            return events
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
            var events = state.escapeWithPod()
            state.phase = .docked
            // POL-110: Palm's pod runs only its own short Arrival.
            if !ruleset.flags.encounter.escapePodPalmSequence { events += state.arrival() }
            return events
        case .arrested:
            state.phase = .docked
            // POL-110: Palm's arrest ran its short Arrival inside the sequence.
            return ruleset.flags.encounter.arrestSequence == .palm ? [] : state.arrival()
        case .normal, .continue:
            t.clicksRemaining -= 1
            state.phase = .inTransit(t)
            return continueTransit()
        }
    }
}
