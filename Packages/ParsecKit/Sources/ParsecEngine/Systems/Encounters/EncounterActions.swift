// SPDX-License-Identifier: GPL-2.0-or-later
// Player actions during encounters: C# EncounterVerify* / Plunder / Meet / Drink / Trade and Arrested.
// docs/specs/ENC.md, CMB.md, POL.md. Dialog "Yes/No" prompts become two-phase confirmations.

/// The actions offered by the encounter screen (C# Form_Encounter buttons).
public enum EncounterAction: String, Codable, Sendable, CaseIterable {
    case attack, flee, surrender, bribe, submit, yield, ignore, plunder, trade, board, drink, meet, stop
    /// ENC-187: the auto-repeat tick (one more round without re-verification).
    case autoRepeat
    /// ENC-190: attack and keep attacking until the encounter resolves.
    case resolve
}

public extension EncounterType {
    /// ENC-130: the actions offered for this type (table 6.1, C# Form_Encounter.UpdateButtons).
    var actions: [EncounterAction] {
        switch self {
        case .bottleGood, .bottleOld: return [.drink, .ignore]
        case .captainAhab, .captainConrad, .captainHuie: return [.attack, .ignore, .meet]
        case .dragonflyAttack, .famousCaptainAttack, .scorpionAttack, .spaceMonsterAttack, .traderAttack: return [.attack, .flee]
        case .marieCeleste: return [.board, .ignore]
        case .marieCelestePolice: return [.attack, .flee, .yield, .bribe]
        case .pirateAttack, .policeAttack, .policeSurrender, .scarabAttack: return [.attack, .flee, .surrender]
        case .pirateSurrender, .pirateDisabled, .traderSurrender, .traderDisabled: return [.attack, .plunder]
        case .policeInspect: return [.attack, .flee, .submit, .bribe]
        case .traderBuy, .traderSell: return [.attack, .ignore, .trade]
        case .dragonflyIgnore, .famousCaptDisabled, .pirateIgnore, .pirateFlee, .policeIgnore, .policeFlee, .policeDisabled,
             .scarabIgnore, .scorpionIgnore, .spaceMonsterIgnore, .traderIgnore, .traderFlee:
            return [.attack, .ignore]
        }
    }

    /// ENC-132: the safe default action bound to Return (nil when every action is destructive or penalised).
    var defaultAction: EncounterAction? {
        switch self {
        case .pirateSurrender, .traderSurrender, .traderDisabled: return nil
        case .pirateDisabled: return .plunder
        case .marieCelestePolice: return .yield
        case .policeInspect: return .submit
        default:
            let a = actions
            return a.contains(.flee) ? .flee : (a.contains(.ignore) ? .ignore : a.first)
        }
    }
}

/// ENC-113: the badge category of an encounter.
public enum EncounterBadge: String, Codable, Sendable {
    case special, pirate, alien, police, trader
}

public extension EncounterType {
    /// ENC-113: the badge for this type against an opponent of `opponent` ship type.
    func badge(opponent: ShipType) -> EncounterBadge {
        switch self {
        case .bottleGood, .bottleOld, .captainAhab, .captainConrad, .captainHuie, .famousCaptainAttack, .famousCaptDisabled,
             .marieCeleste:
            return .special
        case .spaceMonsterAttack, .spaceMonsterIgnore: return .alien
        case .marieCelestePolice, .policeAttack, .policeIgnore, .policeFlee, .policeSurrender, .policeDisabled, .policeInspect:
            return .police
        case .traderAttack, .traderIgnore, .traderFlee, .traderSurrender, .traderDisabled, .traderBuy, .traderSell: return .trader
        case .pirateAttack, .pirateIgnore, .pirateFlee, .pirateSurrender, .pirateDisabled: return opponent == .mantis ? .alien : .pirate
        case .dragonflyAttack, .dragonflyIgnore, .scarabAttack, .scarabIgnore, .scorpionAttack, .scorpionIgnore: return .pirate
        }
    }
}

/// ENC-186 / CMB-098: one action's availability for the current encounter.
public struct EncounterActionPreview: Sendable, Equatable {
    public var action: EncounterAction
    /// The rejection the command would return now, if any.
    public var rejection: CommandError?
    /// The first confirmation the command would ask for, if any.
    public var confirmation: Confirmation?
    public var enabled: Bool { rejection == nil }
}

/// ENC-186: pure description of the current encounter for the encounter screen.
public struct EncounterPreview: Sendable, Equatable {
    public var type: EncounterType
    /// ENC-113: the badge category.
    public var badge: EncounterBadge
    public var opponentType: ShipType
    public var playerHullPercent, playerShieldPercent, opponentHullPercent, opponentShieldPercent: Int
    public var actions: [EncounterActionPreview]
    public var defaultAction: EncounterAction?
    public var canStop: Bool
    public var canAutoRepeat: Bool
}

public extension GameState {
    /// C# `Ship.DetectableIllegalCargo`: illegal units beyond the hidden bays.
    var detectableIllegalCargo: Bool { commander.ship.illegalCargoUnits - commander.ship.hiddenCargoBays > 0 }
    /// C# `Ship.IllegalSpecialCargo`.
    var illegalSpecialCargo: Bool { wildOnBoard || reactorOnBoard || sculptureOnBoard }
    var detectableIllegalCargoOrPassengers: Bool { detectableIllegalCargo || illegalSpecialCargo }

    /// C# `Ship.RemoveIllegalGoods` (also clears their cost basis unless `keepCostBasis`, RUL-138).
    mutating func removeIllegalGoods(keepCostBasis: Bool = false) {
        for item in TradeItemType.allCases where item.isIllegal {
            commander.ship.cargo[item.rawValue] = 0
            if !keepCostBasis { commander.priceCargo[item.rawValue] = 0 }
        }
    }

    /// POL-052 / POL-054: Palm's "illegal goods" test: Firearms or Narcotics in the hold.
    var carriesIllegalGoods: Bool {
        commander.ship.cargo[TradeItemType.firearms.rawValue] > 0 || commander.ship.cargo[TradeItemType.narcotics.rawValue] > 0
    }

    /// POL-054: whether the nothing-illegal confirmation applies to `action` (C#: one rule for attack, flee and bribe).
    func nothingIllegal(for action: EncounterAction) -> Bool {
        guard ruleset.flags.encounter.nothingIllegalPerAction else { return !detectableIllegalCargoOrPassengers }
        switch action {
        case .flee: return !carriesIllegalGoods && !wildOnBoard && !reactorOnBoard
        case .bribe: return !carriesIllegalGoods && !wildOnBoard
        default: return !carriesIllegalGoods
        }
    }

    /// POL: the bribe amount demanded by police at the destination (C# EncounterVerifyBribe; RUL-140).
    var bribeAmount: Int? {
        let level = ruleset.tables.politics(galaxy.systems[warpSystem].politics).bribeLevel
        guard level > 0 else { return nil }
        let diffMod = 10 + 5 * (Difficulty.impossible.rawValue - difficulty.rawValue)
        let k = difficulty <= .normal ? 2 : 3
        switch ruleset.flags.encounter.bribeComputation {
        case .realCeiling:
            let passMod = illegalSpecialCargo ? k : 1
            let base = Int((Double(worth) / Double(level) / Double(diffMod) / 100).rounded(.up)) * 100 * passMod
            return max(100, min(10_000, base))
        case .integerModulo:
            // POL-067: integer quotient, rounded up to 100 with C `%`; ×k only with Wild or the reactor.
            var bribe = worth / (diffMod * level)
            if bribe % 100 != 0 { bribe += 100 - bribe % 100 }
            if wildOnBoard || reactorOnBoard { bribe *= k }
            return max(100, min(10_000, bribe))
        }
    }

    /// POL: the inspection fine (C# EncounterVerifySubmit; POL-061 Palm integer rounding).
    var inspectionFine: Int {
        let divisorInt = (Difficulty.impossible.rawValue - difficulty.rawValue + 2) * 10
        if ruleset.flags.encounter.inspectionFineIntegerRounding {
            var fine = worth / divisorInt
            if fine % 50 != 0 { fine += 50 - fine % 50 }
            return max(100, min(10_000, fine))
        }
        let divisor = Double(divisorInt)
        return Int(max(100, min(10_000, (Double(worth) / divisor / 50).rounded(.up) * 50)))
    }

    /// POL-098 / POL-110: Palm's short `Arrival()`: system, status shuffle, quantities, prices.
    mutating func shortArrival() {
        commander.currentSystem = warpSystem
        galaxy.systems[warpSystem].visited = true
        updatePressuresAndQuantities(arrival: commander.currentSystem)
        calculatePrices(for: commander.currentSystem)
        paidForNewspaper = false
    }

    /// RUL-137 / POL-098: Palm's arrest sequence.
    private mutating func arrestedPalm(term: Int, fine: Int) -> [GameEvent] {
        let keep = ruleset.flags.encounter.impoundedGoodsKeepCostBasis
        let jarek = jarekOnBoard, wild = wildOnBoard
        if carriesIllegalGoods { removeIllegalGoods(keepCostBasis: keep) }
        if commander.insurance {
            commander.insurance = false
            commander.noClaim = 0
        }
        if commander.ship.crew.count > 1, commander.ship.crew[1] != nil {
            for i in 1..<commander.ship.crew.count { commander.ship.crew[i] = nil }
        }
        if quests.japori == QuestStatus.Japori.inTransit { quests.japori = QuestStatus.Japori.done }
        if jarek { quests.jarek = QuestStatus.Jarek.notStarted }
        if wild {
            newsEvents.append(.wildArrested)
            quests.wild = QuestStatus.Wild.notStarted
        }
        if reactorOnBoard { quests.reactor = QuestStatus.Reactor.notStarted }
        shortArrival()
        var events: [GameEvent] = []
        var tail = incDays(term)
        var shipSold = false
        if commander.cash >= fine {
            commander.cash -= fine
        } else {
            commander.cash += shipWorth(forInsurance: true)
            commander.cash = commander.cash >= fine ? commander.cash - fine : 0
            createFlea()
            // POL-099: CreateFlea leaves the Scarab status, so a hardened commander keeps +50 hull on the Flea.
            commander.ship.hullUpgraded = quests.scarab == QuestStatus.Scarab.done
            shipSold = true
        }
        commander.policeRecordScore = -5
        if commander.debt > 0 {
            let paydown = min(commander.cash, commander.debt)
            commander.debt -= paydown
            commander.cash -= paydown
        }
        for _ in 0..<term { payInterest() }
        events.append(.arrested(term: term, fine: fine, shipSold: shipSold))
        tail.append(.arrived(system: commander.currentSystem))
        return events + tail
    }

    /// C# `Game.Arrested`.
    mutating func arrested() -> [GameEvent] {
        var events: [GameEvent] = []
        let term = arrestTerm
        let fine = arrestFine
        if ruleset.flags.encounter.arrestSequence == .palm { return arrestedPalm(term: term, fine: fine) }
        commander.ship.gadgets.removeAll { $0 == .hiddenCargoBays }
        if reactorOnBoard { quests.reactor = QuestStatus.Reactor.notStarted }
        if sculptureOnBoard { quests.sculpture = QuestStatus.Sculpture.notStarted }
        if wildOnBoard {
            newsEvents.append(.wildArrested)
            quests.wild = QuestStatus.Wild.notStarted
        }
        if commander.ship.illegalCargoUnits > 0 { removeIllegalGoods(keepCostBasis: ruleset.flags.encounter.impoundedGoodsKeepCostBasis) }
        if commander.insurance {
            commander.insurance = false
            commander.noClaim = 0
        }
        let crewIDs = commander.ship.crew.compactMap { $0 }
        let special = crewIDs.filter { [CrewID.commander, CrewID.jarek, CrewID.princess, CrewID.wild].contains($0) }.count
        if crewIDs.count - special > 1 {
            for i in 1..<commander.ship.crew.count { commander.ship.crew[i] = nil }
        }
        if jarekOnBoard { quests.jarek = QuestStatus.Jarek.notStarted }
        if princessOnBoard { quests.princess = QuestStatus.Princess.notStarted }
        if quests.japori == QuestStatus.Japori.inTransit { quests.japori = QuestStatus.Japori.done }
        var shipSold = false
        if commander.cash >= fine {
            commander.cash -= fine
        } else {
            commander.cash = max(0, commander.cash + shipWorth(forInsurance: true) - fine)
            createFlea()
            shipSold = true
        }
        if commander.debt > 0 {
            let paydown = min(commander.cash, commander.debt)
            commander.debt -= paydown
            commander.cash -= paydown
            if commander.debt > 0 { for _ in 0..<term { payInterest() } }
        }
        commander.policeRecordScore = -5
        events.append(.arrested(term: term, fine: fine, shipSold: shipSold))
        events += incDays(term)
        return events
    }
}

/// A pending plunder of the opponent's cargo (C# FormPlunder).
public struct PlunderOffer: Codable, Sendable, Equatable {
    public var victimCargo: [Int]
    /// True when boarding the Marie Celeste (narcotics taken trigger the customs police).
    public var marieCeleste: Bool
    /// ENC-161: the commander's narcotics before boarding (C# EncounterVerifyBoard `narcs`).
    public var narcoticsBefore = 0
}

extension GameEngine {
    var encounter: EncounterState? { if case let .encounter(e) = state.phase { e } else { nil } }

    mutating func setEncounter(_ e: EncounterState) { state.phase = .encounter(e) }

    /// Entry point for `Command.encounter`.
    mutating func encounterAction(_ action: EncounterAction, _ ack: Set<WarningID>) -> StepResult {
        guard var enc = encounter else { return .rejected(.notAllowedInPhase) }
        if state.pendingPlunder != nil || state.pendingOrbitTrade != nil || state.pendingScoop != nil {
            return .rejected(.pendingDecisionFirst)
        }
        let repeating = enc.continueAttacking || enc.continueFleeing
        switch action {
        case .stop, .autoRepeat: if !repeating { return .rejected(.encounterActionUnavailable) }
        case .resolve: if !enc.type.actions.contains(.attack) { return .rejected(.encounterActionUnavailable) }
        default: if !enc.type.actions.contains(action) { return .rejected(.encounterActionUnavailable) }
        }
        if action != .autoRepeat, action != .stop, repeating {
            // CMB-068: every command except the auto-repeat tick (and `stop` itself) interrupts continuous combat. A rejected or
            // confirmation-requesting command must not change state, so the flags are cleared on a copy first.
            var probe = self
            var cleared = enc
            cleared.continueAttacking = false
            cleared.continueFleeing = false
            probe.setEncounter(cleared)
            let r = probe.encounterAction(action, ack)
            if r.rejection == nil, !Self.isConfirmationRequest(r) { self = probe }
            return r
        }
        switch action {
        case .autoRepeat:
            let fleeing = enc.continueFleeing
            enc.continueAttacking = false
            enc.continueFleeing = false
            if ruleset.flags.encounter.continuousAttackRule == .palm {
                // CMB-067 / ENC-189: Palm's tick re-enters the full Attack (or Flee) handler, verification included.
                return fleeing ? flee(&enc, ack) : attack(&enc, ack)
            }
            return runRound(&enc, events: [])
        case .resolve:
            var forced = enc
            forced.forceContinuous = true
            if let stop = verifyAttack(&forced, ack) { return stop }
            return runRound(&forced, events: [.playerAttacked])
        case .attack: return attack(&enc, ack)
        case .flee: return flee(&enc, ack)
        case .surrender: return surrender(enc, ack)
        case .bribe: return bribe(enc, ack)
        case .submit: return submit(enc, ack)
        case .yield: return yieldToPolice(enc, ack)
        case .ignore: return finish(.normal)
        case .plunder:
            if ruleset.flags.encounter.plunderPenaltyOnPress {
                // RUL-096 / CMB-092: Palm applies the record change when Plunder is pressed.
                state.commander.policeRecordScore += enc.type.rawValue >= EncounterType.traderAttack.rawValue ? -2 : -1
            }
            state.pendingPlunder = PlunderOffer(victimCargo: enc.opponent.cargo, marieCeleste: false)
            return StepResult(events: [], decision: .plunder(enc.opponent.cargo), rejection: nil)
        case .trade:
            return startOrbitTrade(direction: enc.type == .traderBuy ? .traderBuys : .traderSells)
        case .board:
            guard enc.type == .marieCeleste else { return .rejected(.invalidArgument) }
            guard ack.contains(.boardMarieCeleste) else { return .needsConfirmation(Confirmation(.boardMarieCeleste)) }
            state.pendingPlunder = PlunderOffer(victimCargo: enc.opponent.cargo, marieCeleste: true,
                                                narcoticsBefore: state.commander.ship.cargo[TradeItemType.narcotics.rawValue])
            return StepResult(events: [], decision: .plunder(enc.opponent.cargo), rejection: nil)
        case .drink: return drink(enc, ack)
        case .meet: return meet(enc, ack)
        case .stop:
            enc.continueAttacking = false
            enc.continueFleeing = false
            setEncounter(enc)
            return StepResult()
        }
    }

    /// ENC-186 / CMB-098: pure preview of the current encounter (nil outside the encounter phase).
    public var encounterPreview: EncounterPreview? {
        guard let enc = encounter else { return nil }
        let r = ruleset
        func pct(_ v: Int, _ m: Int) -> Int { m <= 0 ? 0 : 100 * v / m }
        let me = state.commander.ship, opp = enc.opponent
        let previews = enc.type.actions.map { action -> EncounterActionPreview in
            var probe = self
            let res = probe.encounterAction(action, [])
            var conf: Confirmation?
            if case let .confirm(c) = res.decision { conf = c }
            return EncounterActionPreview(action: action, rejection: res.rejection, confirmation: conf)
        }
        return EncounterPreview(type: enc.type, badge: enc.type.badge(opponent: opp.type), opponentType: opp.type,
                                playerHullPercent: pct(me.hull, me.hullStrength(r)),
                                playerShieldPercent: pct(me.shieldCharge, me.shieldStrength(r)),
                                opponentHullPercent: pct(opp.hull, opp.hullStrength(r)),
                                opponentShieldPercent: pct(opp.shieldCharge, opp.shieldStrength(r)),
                                actions: previews, defaultAction: enc.type.defaultAction,
                                canStop: enc.continueAttacking || enc.continueFleeing,
                                canAutoRepeat: enc.continueAttacking || enc.continueFleeing)
    }

    /// Ends the encounter with `result` and resumes transit / arrival.
    mutating func finish(_ result: RoundResult, events: [GameEvent] = []) -> StepResult {
        StepResult(events: events + finishEncounter(result))
    }

    /// Applies a combat round and finishes the encounter if it ended.
    mutating func runRound(_ enc: inout EncounterState, events prior: [GameEvent]) -> StepResult {
        let (result, events) = state.executeRound(&enc)
        setEncounter(enc)
        if result == .continue { return StepResult(events: prior + events) }
        if result == .normal, let item = state.pendingScoop {
            // The scoop question comes before the encounter closes (C# EncounterScoop inside EncounterWon).
            state.pendingEncounterResult = .normal
            return StepResult(events: prior + events, decision: .scoop(item), rejection: nil)
        }
        return finish(result, events: prior + events)
    }

    // MARK: Attack (C# EncounterVerifyAttack)
    mutating func attack(_ enc: inout EncounterState, _ ack: Set<WarningID>) -> StepResult {
        if let stop = verifyAttack(&enc, ack) { return stop }
        return runRound(&enc, events: [.playerAttacked])
    }

    /// C# `EncounterVerifyAttack`: returns a rejection/confirmation, or nil when the attack may proceed.
    mutating func verifyAttack(_ enc: inout EncounterState, _ ack: Set<WarningID>) -> StepResult? {
        let r = ruleset
        let ship = state.commander.ship
        if ship.weaponStrength(r) == 0 { return .rejected(.noWeapons) }
        if !state.disableable(enc.opponent), ship.weaponStrength(r, from: .pulseLaser, to: .morgansLaser) == 0 { return .rejected(.noLasers) }
        if enc.opponent.type == .scorpion, ship.weaponStrength(r, from: .photonDisruptor, to: .quantumDisruptor) == 0 {
            return .rejected(.noDisruptors)
        }
        let rules = r.flags.encounter
        let k = rules.policeConstants
        switch enc.type {
        case .dragonflyIgnore, .pirateIgnore, .scarabIgnore, .scorpionIgnore, .spaceMonsterIgnore:
            enc.type = EncounterType(rawValue: enc.type.rawValue - 1) ?? enc.type
        case .policeInspect, .marieCelestePolice, .policeFlee, .policeIgnore, .policeSurrender, .policeAttack:
            // POL-031 / ENC-147: Palm also charges an ongoing police fight (attack type) on every click.
            if enc.type == .policeAttack, !rules.attackReverification { break }
            if enc.type == .policeInspect, state.nothingIllegal(for: .attack), !ack.contains(.submitWithNothingIllegal) {
                return .needsConfirmation(Confirmation(.submitWithNothingIllegal))
            }
            // RUL-131: confirm above the criminal constant, then record = min(record, criminal) − 3.
            if state.commander.policeRecordScore > k.criminal, !ack.contains(.attackPolice) {
                return .needsConfirmation(Confirmation(.attackPolice, amounts: [k.criminal - 3]))
            }
            if state.commander.policeRecordScore > k.criminal { state.commander.policeRecordScore = k.criminal }
            state.commander.policeRecordScore -= 3
            if enc.type != .policeFlee { enc.type = .policeAttack }
        case .famousCaptainAttack:
            // POL-034: Palm applies the captain clamp on every attack round (no confirmation, no news).
            guard rules.attackReverification else { break }
            if state.commander.policeRecordScore > k.villain { state.commander.policeRecordScore = k.villain }
            state.commander.policeRecordScore -= 2
        case .traderBuy, .traderIgnore, .traderSell, .traderAttack, .traderSurrender:
            if [.traderBuy, .traderIgnore, .traderSell].contains(enc.type) {
                if state.commander.policeRecordScore < 0 {
                    state.commander.policeRecordScore -= 2
                } else {
                    guard ack.contains(.attackTrader) else { return .needsConfirmation(Confirmation(.attackTrader, amounts: [-5])) }
                    state.commander.policeRecordScore = -5
                }
            }
            if rules.attackReverification {
                // CMB-008: Palm tests the opponent's weapons first (no draw when unarmed).
                let flees = enc.opponent.weaponStrength(r) == 0
                    || state.rng.next(below: 1_500) <= state.commander.reputationScore * 10 / (enc.opponent.type.rawValue + 1)
                enc.type = flees ? .traderFlee : .traderAttack
            } else if state.rng.next(below: 1_500) <= state.commander.reputationScore * 10 / (enc.opponent.type.rawValue + 1)
                || enc.opponent.weaponStrength(r) == 0 {
                enc.type = .traderFlee
            } else {
                enc.type = .traderAttack
            }
        case .captainAhab, .captainConrad, .captainHuie:
            guard ack.contains(.attackCaptain) else { return .needsConfirmation(Confirmation(.attackCaptain)) }
            // RUL-132: record = min(record, villain) − 2.
            if state.commander.policeRecordScore > k.villain { state.commander.policeRecordScore = k.villain }
            state.commander.policeRecordScore -= 2
            state.newsEvents.append(enc.type == .captainAhab ? .captAhabAttacked : (enc.type == .captainConrad ? .captConradAttacked : .captHuieAttacked))
            enc.type = .famousCaptainAttack
        default:
            break
        }
        enc.cmdrFleeing = false
        setEncounter(enc)
        return nil
    }

    // MARK: Flee (C# EncounterVerifyFlee)
    mutating func flee(_ enc: inout EncounterState, _ ack: Set<WarningID>) -> StepResult {
        if let stop = verifyFlee(&enc, ack) { return stop }
        return runRound(&enc, events: [.playerFled])
    }

    /// C# `EncounterVerifyFlee`: returns a confirmation, or nil when fleeing may proceed.
    mutating func verifyFlee(_ enc: inout EncounterState, _ ack: Set<WarningID>) -> StepResult? {
        if enc.type == .policeInspect, state.nothingIllegal(for: .flee), !ack.contains(.fleeInspection) {
            return .needsConfirmation(Confirmation(.fleeInspection))
        }
        if enc.type == .marieCelestePolice, !ack.contains(.fleeMariePolice) {
            return .needsConfirmation(Confirmation(.fleeMariePolice))
        }
        if enc.type == .policeInspect || enc.type == .marieCelestePolice {
            let inspect = enc.type == .policeInspect
            let rec = state.commander.policeRecordScore
            enc.type = .policeAttack
            if ruleset.flags.encounter.palmFleePenalties {
                // RUL-134 / RUL-135: Palm resets a mild record to the floor, else subtracts.
                let criminal = ruleset.flags.encounter.policeConstants.criminal
                if inspect {
                    state.commander.policeRecordScore = rec > -5 ? -5 - (state.difficulty >= .normal ? 1 : 0) : rec - 2
                } else {
                    state.commander.policeRecordScore = rec >= criminal ? criminal : rec - 3
                }
            } else {
                let mod = inspect ? -2 : -3
                let minScore = inspect ? -5 - (state.difficulty < .normal ? 0 : 1) : -30
                state.commander.policeRecordScore = min(rec + mod, minScore)
            }
        }
        enc.cmdrFleeing = true
        setEncounter(enc)
        return nil
    }

    // MARK: Surrender (C# EncounterVerifySurrender)
    mutating func surrender(_ enc: EncounterState, _ ack: Set<WarningID>) -> StepResult {
        var enc = enc
        if enc.opponent.type == .mantis {
            guard state.artifactOnBoard else { return .rejected(.surrenderRefused) }
            guard ack.contains(.surrenderArtifact) else { return .needsConfirmation(Confirmation(.surrenderArtifact)) }
            state.quests.artifact = QuestStatus.Artifact.notStarted
            return finish(.normal, events: [.artifactRelinquished])
        }
        if enc.type == .policeAttack || enc.type == .policeSurrender {
            // RUL-133: refused at the psychopath constant.
            if state.commander.policeRecordScore <= ruleset.flags.encounter.policeConstants.psychopath { return .rejected(.surrenderRefused) }
            guard ack.contains(.surrenderToPolice) else { return .needsConfirmation(Confirmation(.surrenderToPolice)) }
            let events = state.arrested()
            return finish(.arrested, events: events)
        }
        if state.princessOnBoard, !state.commander.ship.has(.hiddenCargoBays) { return .rejected(.surrenderPrincess) }
        var events: [GameEvent] = []
        state.raided = true
        if ruleset.flags.encounter.pirateStealPolicy == .allOrRandom { return raidPalm(enc, events: events) }
        if state.commander.ship.has(.hiddenCargoBays) {
            events.append(.preciousHidden)
        } else if state.sculptureOnBoard {
            state.quests.sculpture = QuestStatus.Sculpture.notStarted
            events.append(.sculptureTaken)
        }
        var steal: [Int] = []
        for item in 0..<10 { steal += Array(repeating: item, count: state.commander.ship.cargo[item]) }
        steal.sort(by: >)
        var hidden = state.commander.ship.hiddenCargoBays
        if state.princessOnBoard { hidden -= 1 }
        if state.sculptureOnBoard { hidden -= 1 }
        // C# `RemoveRange(0, hidden)` throws when hidden bays exceed the cargo (POL-080): the surrender aborts and
        // the encounter stays open. MOD-012 (`pirateLootHiddenBaysClamp`) clamps instead.
        if hidden > steal.count, !ruleset.flags.pirateLootHiddenBaysClamp {
            setEncounter(enc)
            return StepResult(events: events)
        }
        if hidden > 0 { steal.removeFirst(min(hidden, steal.count)) }
        if steal.isEmpty {
            let blackmail = min(25_000, max(500, state.worth / 20))
            let cashPayment = min(state.commander.cash, blackmail)
            state.commander.debt += blackmail - cashPayment
            state.commander.cash -= cashPayment
            events.append(.blackmailed(blackmail))
        } else {
            var stolen = 0
            while enc.opponent.cargoBays(ruleset) - enc.opponent.filledNormalCargoBays > 0, !steal.isEmpty {
                let item = steal.removeFirst()
                state.commander.priceCargo[item] -= state.commander.priceCargo[item] / state.commander.ship.cargo[item]
                state.commander.ship.cargo[item] -= 1
                enc.opponent.cargo[item] += 1
                stolen += 1
            }
            events.append(.looted(units: stolen))
        }
        if state.wildOnBoard {
            if enc.opponent.crew.count > 1 {
                state.quests.wild = QuestStatus.Wild.notStarted
                events.append(.wildJoinedPirates)
            }
        }
        setEncounter(enc)
        return finish(.normal, events: events)
    }

    /// RUL-098 / POL-083 / POL-085: Palm's raid: everything if it fits, else random units; nothing goes to the pirate.
    private mutating func raidPalm(_ enc: EncounterState, events prior: [GameEvent]) -> StepResult {
        var events = prior
        let total = state.commander.ship.cargo.reduce(0, +)
        if total <= 0 {
            let blackmail = min(25_000, max(500, state.worth / 20))
            let cashPayment = min(state.commander.cash, blackmail)
            state.commander.debt += blackmail - cashPayment
            state.commander.cash -= cashPayment
            events.append(.blackmailed(blackmail))
        } else {
            var bays = enc.opponent.cargoBays(ruleset) - enc.opponent.cargo.reduce(0, +)
            var stolen = 0
            if bays >= total {
                stolen = total
                state.commander.ship.cargo = Array(repeating: 0, count: 10)
                state.commander.priceCargo = Array(repeating: 0, count: 10)
            } else {
                while bays > 0 {
                    let i = state.rng.next(below: 10)
                    let c = state.commander.ship.cargo[i]
                    guard c > 0 else { continue }
                    state.commander.priceCargo[i] = state.commander.priceCargo[i] * (c - 1) / c
                    state.commander.ship.cargo[i] -= 1
                    bays -= 1
                    stolen += 1
                }
            }
            events.append(.looted(units: stolen))
        }
        if state.wildOnBoard, enc.opponent.spec(ruleset).crewQuarters > 1 {
            state.quests.wild = QuestStatus.Wild.notStarted
            state.removeSpecialCrew(CrewID.wild) // POL-085: Palm's Wild exists only through his status
            events.append(.wildJoinedPirates)
        }
        setEncounter(enc)
        return finish(.normal, events: events)
    }

    // MARK: Bribe / submit / yield (POL)
    mutating func bribe(_ enc: EncounterState, _ ack: Set<WarningID>) -> StepResult {
        // POL-067: Palm tests the bribe level before the customs refusal.
        if ruleset.flags.encounter.bribeComputation == .integerModulo, state.bribeAmount == nil { return .rejected(.bribeNotPossible) }
        if enc.type == .marieCelestePolice { return .rejected(.bribeNotAccepted) }
        guard let amount = state.bribeAmount else { return .rejected(.bribeNotPossible) }
        if state.nothingIllegal(for: .bribe), !ack.contains(.submitWithNothingIllegal) {
            return .needsConfirmation(Confirmation(.submitWithNothingIllegal))
        }
        guard ack.contains(.bribe) else { return .needsConfirmation(Confirmation(.bribe, amounts: [amount])) }
        guard state.commander.cash >= amount else { return .rejected(.insufficientFunds) }
        state.commander.cash -= amount
        return finish(.normal, events: [.bribed(amount)])
    }

    /// RUL-139 / POL-060…062: Palm's submit (reactor confiscated without arrest; Wild still arrests).
    private mutating func submitPalm(_ ack: Set<WarningID>) -> StepResult {
        var events: [GameEvent] = []
        let warn = state.carriesIllegalGoods || state.wildOnBoard
            || (state.quests.reactor > QuestStatus.Reactor.fuelOK && state.quests.reactor < QuestStatus.Reactor.delivered)
        if warn, !ack.contains(.submitInspection) { return .needsConfirmation(Confirmation(.submitInspection)) }
        if state.carriesIllegalGoods {
            state.removeIllegalGoods()
            let fine = state.inspectionFine
            let cash = min(state.commander.cash, fine)
            state.commander.debt += fine - cash
            state.commander.cash -= cash
            state.commander.policeRecordScore -= 1
            events.append(.fined(fine))
        } else if !state.wildOnBoard {
            state.commander.policeRecordScore += 1
            events.append(.inspectionClean)
        }
        if state.wildOnBoard {
            events += state.arrested()
            return finish(.arrested, events: events)
        }
        if state.reactorOnBoard {
            state.quests.reactor = QuestStatus.Reactor.notStarted
            events.append(.reactorConfiscated)
        }
        return finish(.normal, events: events)
    }

    mutating func submit(_ enc: EncounterState, _ ack: Set<WarningID>) -> StepResult {
        if ruleset.flags.encounter.reactorConfiscatedOnSubmit { return submitPalm(ack) }
        var events: [GameEvent] = []
        if state.detectableIllegalCargoOrPassengers {
            guard ack.contains(.submitInspection) else { return .needsConfirmation(Confirmation(.submitInspection)) }
            if state.detectableIllegalCargo {
                state.removeIllegalGoods()
                let fine = state.inspectionFine
                let cash = min(state.commander.cash, fine)
                state.commander.debt += fine - cash
                state.commander.cash -= cash
                state.commander.policeRecordScore -= 1
                events.append(.fined(fine))
            }
        } else {
            state.commander.policeRecordScore += 1
            events.append(.inspectionClean)
        }
        if state.illegalSpecialCargo {
            events += state.arrested()
            return finish(.arrested, events: events)
        }
        return finish(.normal, events: events)
    }

    mutating func yieldToPolice(_ enc: EncounterState, _ ack: Set<WarningID>) -> StepResult {
        if state.illegalSpecialCargo {
            guard ack.contains(.surrenderToPolice) else { return .needsConfirmation(Confirmation(.surrenderToPolice)) }
            let events = state.arrested()
            return finish(.arrested, events: events)
        }
        // POL-073: Palm yields without confirmation and keeps the goods' cost basis (RUL-138).
        let rules = ruleset.flags.encounter
        if !rules.yieldWithoutConfirmation, !ack.contains(.submitInspection) {
            return .needsConfirmation(Confirmation(.submitInspection))
        }
        if state.commander.policeRecordScore > -5 { state.commander.policeRecordScore = -5 }
        state.removeIllegalGoods(keepCostBasis: rules.impoundedGoodsKeepCostBasis)
        return finish(.normal, events: [.yielded])
    }

    // MARK: Drink / meet (very rare encounters)
    mutating func drink(_ enc: EncounterState, _ ack: Set<WarningID>) -> StepResult {
        guard enc.type == .bottleGood || enc.type == .bottleOld else { return .rejected(.invalidArgument) }
        guard ack.contains(.drinkTonic) else { return .needsConfirmation(Confirmation(.drinkTonic)) }
        if enc.type == .bottleGood {
            state.changeRandomSkill(1)
            if state.difficulty <= .normal { state.changeRandomSkill(1) }
        } else {
            let old = state.mercenaries[CrewID.commander].skills
            if state.difficulty < .hard {
                while state.mercenaries[CrewID.commander].skills == old {
                    state.changeRandomSkill(1)
                    state.changeRandomSkill(-1)
                }
            } else {
                state.changeRandomSkill(1)
                state.changeRandomSkill(1)
                state.changeRandomSkill(-3)
            }
        }
        return finish(.normal, events: [.tonicConsumed(good: enc.type == .bottleGood)])
    }

    mutating func meet(_ enc: EncounterState, _ ack: Set<WarningID>) -> StepResult {
        let skill: SkillType
        switch enc.type {
        case .captainAhab: skill = .pilot
        case .captainConrad: skill = .engineer
        case .captainHuie: skill = .trader
        default: return .rejected(.invalidArgument)
        }
        guard ack.contains(.meetCaptain) else { return .needsConfirmation(Confirmation(.meetCaptain)) }
        if enc.type == .captainAhab {
            if let i = state.commander.ship.shields.firstIndex(where: { $0.type == .reflective }) { state.commander.ship.shields.remove(at: i) }
        } else if let i = state.commander.ship.weapons.firstIndex(of: .militaryLaser) {
            state.commander.ship.weapons.remove(at: i)
        }
        let gain = state.difficulty <= .normal ? 2 : 1
        state.mercenaries[CrewID.commander].skills[skill.rawValue] = min(10, state.mercenaries[CrewID.commander].skills[skill.rawValue] + gain)
        return finish(.normal, events: [.captainTraining(skill: skill)])
    }

    // MARK: Plunder (C# FormPlunder + EncounterPlunder) and scoop
    mutating func plunderTake(_ item: TradeItemType, _ q: Int) -> StepResult {
        guard var offer = state.pendingPlunder, var enc = encounter else { return .rejected(.notAllowedInPhase) }
        let i = item.rawValue
        if enc.opponent.cargo[i] <= 0 { return .rejected(.cargoNoneAvailable) }
        if state.freeCargoBays == 0 { return .rejected(.noEmptyBays) }
        guard q >= 1, q <= min(state.freeCargoBays, enc.opponent.cargo[i]) else { return .rejected(.invalidQuantity) }
        state.commander.ship.cargo[i] += q
        enc.opponent.cargo[i] -= q
        offer.victimCargo = enc.opponent.cargo
        state.pendingPlunder = offer
        setEncounter(enc)
        return StepResult(events: [.plundered(item: item, quantity: q)], decision: .plunder(enc.opponent.cargo), rejection: nil)
    }

    mutating func plunderDone() -> StepResult {
        guard let offer = state.pendingPlunder, let enc = encounter else { return .rejected(.notAllowedInPhase) }
        state.pendingPlunder = nil
        if offer.marieCeleste {
            if state.commander.ship.cargo[TradeItemType.narcotics.rawValue] > offer.narcoticsBefore { state.quests.justLootedMarie = true }
            return finish(.normal)
        }
        if ruleset.flags.encounter.plunderPenaltyOnPress { return finish(.normal) } // RUL-096: no reputation, kills or bounty
        var events: [GameEvent] = []
        if enc.type.rawValue >= EncounterType.traderAttack.rawValue {
            state.commander.policeRecordScore -= 2
            if enc.opponentDisabled { state.commander.kills.traders += 1 }
        } else if enc.opponentDisabled {
            if state.commander.policeRecordScore >= -5 {
                let b = state.bounty(of: enc.opponent)
                state.commander.cash += b
                events.append(.bountyPaid(b))
            }
            state.commander.kills.pirates += 1
            state.commander.policeRecordScore += 1
        } else {
            state.commander.policeRecordScore -= 1
        }
        state.commander.reputationScore += enc.opponent.type.rawValue / 2 + 1
        return finish(.normal, events: events)
    }

    /// Accepts or declines a pending scoop (C# EncounterScoop answer).
    mutating func resolveScoop(accept: Bool) -> StepResult {
        guard let item = state.pendingScoop else { return .rejected(.notAllowedInPhase) }
        var events: [GameEvent] = []
        if accept {
            if state.freeCargoBays > 0 {
                state.commander.ship.cargo[item.rawValue] += 1
                events.append(.scooped(item))
            } else {
                events.append(.scoopNoRoom)
            }
        }
        state.pendingScoop = nil
        if let pending = state.pendingEncounterResult {
            state.pendingEncounterResult = nil
            return finish(pending, events: events)
        }
        return StepResult(events: events)
    }
}
