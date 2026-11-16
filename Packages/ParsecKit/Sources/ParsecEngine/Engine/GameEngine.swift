// SPDX-License-Identifier: GPL-2.0-or-later
// The engine API (PRD §6.2): commands in, typed events/decisions/rejections out. No UI, no strings.

/// A risky action that needs explicit consent (two-phase confirmation).
public enum WarningID: String, Codable, Sendable, Hashable, CaseIterable {
    case attackPolice, attackTrader, attackCaptain, fleeInspection, fleeMariePolice
    case submitWithNothingIllegal, surrenderToPolice, bribe
    case buyEquipment, sellEquipment, buyShip, fireMercenary, stopInsurance
    case wildLeavesWithoutLaser, wildLeavesForReactor, litteringWarning, useSingularity, retire
    case drinkTonic, boardMarieCeleste, takeMarieCargo, meetCaptain, buyEscapePod
}

/// A consent request returned instead of performing a command.
public struct Confirmation: Codable, Sendable, Equatable {
    public var warning: WarningID
    /// Numeric parameters for the message (e.g. a price or the resulting police record score).
    public var amounts: [Int]

    public init(_ warning: WarningID, amounts: [Int] = []) {
        self.warning = warning
        self.amounts = amounts
    }
}

/// Why a command was refused. The state is never changed when a command is rejected.
public enum CommandError: Codable, Sendable, Equatable, Error {
    case notAllowedInPhase
    case pendingDecisionFirst
    case invalidArgument
    // Economy
    case debtTooLargeToTrade
    case cargoNoneAvailable
    case noEmptyBays
    case insufficientFunds
    case invalidQuantity
    case cargoNoneToSell
    case marketNotInterested
    // Ships, equipment and services (SHP)
    case tankFull
    case noRepairsNeeded
    case notSoldHere
    case inDebt
    case noFreeSlot
    case equipmentAlreadyOwned
    case extraBaysInUse
    case notEnoughQuarters
    case passengersNeedQuarters
    case reactorOnBoard
    case alreadyHaveEscapePod
    case escapePodNotAvailable
    case alreadyOwnThisShipType
    case designNameEmpty
    case designOverCapacity
    // Bank (BNK-063)
    case debtTooLargeForLoan
    case noDebt
    case invalidAmount
    case exceedsAvailableLoan
    case exceedsRepayable
    case insuranceRequiresEscapePod
    case insuranceAlreadyActive
    case insuranceNotActive
    // Crew (CRW)
    case notForHire
    case commanderNameRequired
    case invalidSkillAllocation
    case noFreeQuarters
    case notInCrew
    case cannotFireSpecialPassenger
    case gameOver
}

/// Something that happened, for the feed, log, statistics and achievements.
public enum GameEvent: Codable, Sendable, Equatable {
    case gameStarted(ruleset: RulesetID, seed: UInt64)
    case boughtCargo(item: TradeItemType, quantity: Int, total: Int)
    case soldCargo(item: TradeItemType, quantity: Int, total: Int, profit: Int)
    case dumpedCargo(item: TradeItemType, quantity: Int, cost: Int)
    case jettisonedCargo(item: TradeItemType, quantity: Int)
    case caughtLittering(newRecord: Int)
    case boughtFuel(units: Int, cost: Int)
    case repairedHull(points: Int, cost: Int)
    case boughtEquipment(price: Int)
    case soldEquipment(price: Int)
    case boughtShip(type: ShipType, netPrice: Int)
    case cannotTransfer(TransferItem)
    case cannotAffordTransfer(TransferItem)
    case cannotAffordAllTransfers
    case boughtEscapePod(price: Int)
    case hired(crewID: Int)
    case fired(crewID: Int)
    case borrowed(amount: Int)
    case repaid(amount: Int)
    case insuranceBought
    case insuranceStopped
    case optionsChanged
    case orbitTradeCompleted(direction: OrbitTradeDirection, item: TradeItemType, quantity: Int, total: Int)
}

/// A decision the engine needs before it can continue.
public enum PendingDecision: Codable, Sendable, Equatable {
    case confirm(Confirmation)
    case tradeInOrbit(OrbitTradeOffer)
}

/// The result of performing a command.
public struct StepResult: Sendable, Equatable {
    public var events: [GameEvent] = []
    public var decision: PendingDecision?
    public var rejection: CommandError?

    public static func rejected(_ e: CommandError) -> StepResult { StepResult(events: [], decision: nil, rejection: e) }
    public static func needsConfirmation(_ c: Confirmation) -> StepResult {
        StepResult(events: [], decision: .confirm(c), rejection: nil)
    }
}

/// Player actions. Grows milestone by milestone; every case is logged for replays.
public enum Command: Codable, Sendable, Equatable {
    case setOptions(GameOptions)
    case buyCargo(TradeItemType, quantity: Int)
    case sellCargo(TradeItemType, quantity: Int)
    case dumpCargo(TradeItemType, quantity: Int)
    case jettisonCargo(TradeItemType, quantity: Int)
    case buyFuel(credits: Int)
    case repairHull(credits: Int)
    case borrow(Int)
    case repay(Int)
    case buyInsurance
    case stopInsurance
    case buyEscapePod
    case hire(crewID: Int)
    case fire(crewID: Int)
    case buyWeapon(WeaponType)
    case buyShield(ShieldType)
    case buyGadget(GadgetType)
    case sellWeapon(index: Int)
    case sellShield(index: Int)
    case sellGadget(index: Int)
    case buyShip(ShipType, transfers: [TransferItem])
    case resolveTradeInOrbit(quantity: Int)
    case buildDesign(ShipDesign, transfers: [TransferItem])
    case selectTarget(Int)
    case track(Int?)
}

/// The rules engine. A value type; copying it forks the game.
public struct GameEngine: Sendable {
    public internal(set) var state: GameState

    public init(state: GameState) {
        self.state = state
    }

    public init(config: NewGameConfig) {
        state = GameState(config: config)
    }

    public var ruleset: Ruleset { state.ruleset }

    /// Performs a command. A rejected command or a confirmation request leaves the state untouched.
    @discardableResult
    public mutating func perform(_ command: Command, acknowledging: Set<WarningID> = []) -> StepResult {
        var copy = self
        let result = copy.apply(command, acknowledging: acknowledging)
        if result.rejection == nil, !Self.isConfirmationRequest(result) {
            self = copy
        }
        return result
    }

    static func isConfirmationRequest(_ r: StepResult) -> Bool {
        if case .confirm = r.decision, r.events.isEmpty { return true }
        return false
    }

    mutating func apply(_ command: Command, acknowledging ack: Set<WarningID>) -> StepResult {
        if case .gameOver = state.phase { return .rejected(.gameOver) }
        switch command {
        case let .setOptions(o):
            state.options = o
            return StepResult(events: [.optionsChanged])
        case let .selectTarget(s):
            guard state.galaxy.systems.indices.contains(s) else { return .rejected(.invalidArgument) }
            state.warpSystem = s
            state.targetWormhole = false
            return StepResult()
        case let .track(s):
            if let s, !state.galaxy.systems.indices.contains(s) { return .rejected(.invalidArgument) }
            state.trackedSystem = s
            return StepResult()
        default:
            return applyEconomy(command, acknowledging: ack)
        }
    }

    /// ECO-081: opens a trade-in-orbit decision with the current encounter's trader (called when the player picks Trade).
    mutating func startOrbitTrade(direction: OrbitTradeDirection) -> StepResult {
        guard case let .encounter(enc) = state.phase else { return .rejected(.notAllowedInPhase) }
        guard let offer = state.makeOrbitTradeOffer(direction: direction, trader: enc.opponent) else {
            return .rejected(.cargoNoneToSell)
        }
        state.pendingOrbitTrade = offer
        return StepResult(events: [], decision: .tradeInOrbit(offer), rejection: nil)
    }

    /// ECO-081: accepts `0...maxQuantity` units of the pending offer (0 declines).
    mutating func resolveTradeInOrbit(_ q: Int) -> StepResult {
        guard let offer = state.pendingOrbitTrade, case var .encounter(enc) = state.phase else {
            return .rejected(.notAllowedInPhase)
        }
        guard q >= 0, q <= offer.maxQuantity else { return .rejected(.invalidQuantity) }
        state.pendingOrbitTrade = nil
        let event = state.resolveOrbitTrade(offer, quantity: q, trader: &enc.opponent)
        state.phase = .encounter(enc)
        return StepResult(events: event.map { [$0] } ?? [])
    }

    /// Economy and services commands (M2). Implemented in Systems/Economy and Systems/Services.
    mutating func applyEconomy(_ command: Command, acknowledging ack: Set<WarningID>) -> StepResult {
        switch command {
        case let .buyCargo(item, q): return buyCargo(item, quantity: q)
        case let .sellCargo(item, q): return sellCargo(item, quantity: q, dump: false)
        case let .dumpCargo(item, q): return sellCargo(item, quantity: q, dump: true)
        case let .jettisonCargo(item, q): return jettisonCargo(item, quantity: q, acknowledging: ack)
        case let .buyFuel(c): return buyFuel(credits: c)
        case let .repairHull(c): return repairHull(credits: c)
        case let .borrow(a): return borrow(a)
        case let .repay(a): return repay(a)
        case .buyInsurance: return buyInsurance()
        case .stopInsurance: return stopInsurance(ack)
        case .buyEscapePod: return buyEscapePod(ack)
        case let .hire(id): return hire(id)
        case let .fire(id): return fire(id, ack)
        case let .buyWeapon(w): return buyEquipment(weapon: w, ack)
        case let .buyShield(s): return buyEquipment(shield: s, ack)
        case let .buyGadget(g): return buyEquipment(gadget: g, ack)
        case let .sellWeapon(i): return sellEquipment(weaponIndex: i, ack)
        case let .sellShield(i): return sellEquipment(shieldIndex: i, ack)
        case let .sellGadget(i): return sellEquipment(gadgetIndex: i, ack)
        case let .buyShip(t, transfers): return buyShip(t, accepting: transfers, ack)
        case let .resolveTradeInOrbit(q): return resolveTradeInOrbit(q)
        case let .buildDesign(d, transfers): return buildDesign(d, accepting: transfers, ack)
        case .setOptions, .selectTarget, .track: return .rejected(.invalidArgument)
        }
    }
}
