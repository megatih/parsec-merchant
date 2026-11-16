// SPDX-License-Identifier: GPL-2.0-or-later
// The complete, serializable game state (PRD §6.2). Pure values; no references or singletons.

/// Per-save game options (C# `GameOptions`, defaults from GameOptions.cs:34-49).
public struct GameOptions: Codable, Sendable, Equatable {
    public var alwaysIgnorePirates = false
    public var alwaysIgnorePolice = false
    public var alwaysIgnoreTradeInOrbit = false
    public var alwaysIgnoreTraders = true
    public var autoFuel = false
    public var autoRepair = false
    public var continuousAttack = false
    public var continuousAttackFleeing = false
    public var disableOpponents = false
    public var newsAutoPay = false
    public var newsAutoShow = false
    public var remindLoans = true
    public var reserveMoney = false
    public var showTrackedRange = true
    public var trackAutoOff = true
    /// Cargo bays to leave empty when buying in a market.
    public var leaveEmpty = 0

    public init() {}

    /// OPT-004: the defaults of a ruleset (C# class defaults for Modern and Windows 2.01, Palm first-launch globals).
    public static func defaults(for ruleset: RulesetID) -> GameOptions {
        Ruleset.named(ruleset).flags.defaultOptions
    }

    /// OPT-008…010: the options as the ruleset's Options dialog allows them.
    public func normalized(for ruleset: Ruleset) -> GameOptions {
        var o = self
        if ruleset.flags.optionDependencies {
            // Form_Options.cs:381-431: a dependent checkbox is unchecked and disabled while its parent is off.
            if !o.continuousAttack { o.continuousAttackFleeing = false }
            if !o.alwaysIgnoreTraders { o.alwaysIgnoreTradeInOrbit = false }
            if !o.newsAutoPay { o.newsAutoShow = false }
        }
        // OPT-009: options that do not exist in the ruleset (NEWS-013; RUL-015/CMB-041: no disruptors, no disable attempt).
        if !ruleset.flags.travel.newsAutoShowAvailable { o.newsAutoShow = false }
        if !ruleset.content.hasDisruptors { o.disableOpponents = false }
        o.leaveEmpty = min(99, max(0, o.leaveEmpty))
        return o
    }
}

/// Quest progress. Status integers keep the original codes (SpecialEvent.cs) so day-counting logic ports exactly.
public struct QuestState: Codable, Sendable, Equatable {
    public var artifact = 0
    public var dragonfly = 0
    public var experiment = 0
    public var gemulon = 0
    public var japori = 0
    public var jarek = 0
    public var moon = 0
    public var princess = 0
    public var reactor = 0
    public var scarab = 0
    public var sculpture = 0
    public var spaceMonster = 0
    public var wild = 0
    /// Chance (percent) that a warp misfires after the experiment; starts at 25 when it is performed.
    public var fabricRipProbability = 0
    /// Portable singularity available (one free jump).
    public var canSuperWarp = false
    public var justLootedMarie = false

    public init() {}
}

/// Quest status codes (SpecialEvent.cs).
public enum QuestStatus {
    public static let moonCost = 500_000
    public enum Artifact { public static let notStarted = 0, onBoard = 1, done = 2 }
    public enum Dragonfly { public static let notStarted = 0, flyBaratas = 1, flyMelina = 2, flyRegulas = 3, flyZalkon = 4, destroyed = 5, done = 6 }
    public enum Experiment { public static let notStarted = 0, started = 1, date = 11, performed = 12, cancelled = 13 }
    public enum Gemulon { public static let notStarted = 0, started = 1, date = 7, tooLate = 8, fuel = 9, done = 10 }
    public enum Japori { public static let notStarted = 0, inTransit = 1, done = 2 }
    public enum Jarek { public static let notStarted = 0, started = 1, impatient = 11, done = 12 }
    public enum Moon { public static let notStarted = 0, bought = 1, done = 2 }
    public enum Princess {
        public static let notStarted = 0, flyCentauri = 1, flyInthara = 2, flyQonos = 3, rescued = 4
        public static let impatient = 14, returned = 15, done = 16
    }
    public enum Reactor { public static let notStarted = 0, fuelOK = 1, date = 20, delivered = 21, done = 22 }
    public enum Scarab { public static let notStarted = 0, hunting = 1, destroyed = 2, done = 3 }
    public enum Sculpture { public static let notStarted = 0, inTransit = 1, delivered = 2, done = 3 }
    public enum SpaceMonster { public static let notStarted = 0, atAcamar = 1, destroyed = 2, done = 3 }
    public enum Wild { public static let notStarted = 0, started = 1, impatient = 11, done = 12 }
}

/// Where the game currently is.
public enum GamePhase: Codable, Sendable, Equatable {
    case docked
    case inTransit(TransitState)
    case encounter(EncounterState)
    case gameOver(GameEndType)
}

/// Resumable transit between systems (replaces the modal loop in C# `Game.Travel`).
public struct TransitState: Codable, Sendable, Equatable {
    public var destination: Int
    public var clicksRemaining: Int
    public var viaWormhole: Bool
    public var raided = false
    public var inspected = false
    public var litterWarning = false
    public var hadEncounter = false
}

/// An ongoing encounter (C# encounter fields of `Game`).
public struct EncounterState: Codable, Sendable, Equatable {
    public var type: EncounterType
    public var opponent: Ship
    public var opponentDisabled = false
    public var round = 0
    /// Clicks from the destination when the encounter began.
    public var clicks = 0
    public var cmdrFleeing = false
    public var oppFleeing = false
    public var oppFleeingPrev = false
    public var cmdrHit = false
    public var oppHit = false
    /// Auto-repeat flags (C# `EncounterContinueAttacking` / `EncounterContinueFleeing`); the UI repeats the action.
    public var continueAttacking = false
    public var continueFleeing = false
    /// ENC-190: set by `resolve`; auto-repeat is evaluated as if both continuous options were on.
    public var forceContinuous = false

    public init(type: EncounterType, opponent: Ship, clicks: Int = 0) {
        self.type = type
        self.opponent = opponent
        self.clicks = clicks
    }
}

/// The full game state.
public struct GameState: Codable, Sendable, Equatable {
    public internal(set) var rulesetID: RulesetID
    public var difficulty: Difficulty
    public var seed: UInt64
    public var rng: RNGState
    public var galaxy: Galaxy
    public var mercenaries: [CrewMember]
    public var commander: Commander
    public var specialShips: SpecialShips
    public var quests = QuestState()
    public var options = GameOptions()
    /// Current market prices at the current system (C# `PriceCargoBuy/PriceCargoSell`).
    public var buyPrices: [Int]
    public var sellPrices: [Int]
    public var veryRareEncounters: [VeryRareEncounter]
    /// Out of 1000 per encounter (C# `_chanceOfTradeInOrbit`).
    public var chanceOfTradeInOrbit = 100
    /// Out of 1000 per click (C# `_chanceOfVeryRareEncounter`).
    public var chanceOfVeryRareEncounter = 5
    public var newsEvents: [NewsEvent] = []
    public var paidForNewspaper = false
    public var arrivedViaWormhole = false
    public var tribbleMessage = false
    public var litterWarning = false
    /// Selected (warp) target system and tracked system.
    public var warpSystem: Int
    public var trackedSystem: Int?
    public var targetWormhole = false
    /// A trade-in-orbit offer awaiting the player's quantity (ECO-081).
    public var pendingOrbitTrade: OrbitTradeOffer?
    /// A floating canister the player may scoop after a kill (C# `EncounterScoop`).
    public var pendingScoop: TradeItemType?
    /// A plunder (or Marie Celeste boarding) awaiting the player's choices.
    public var pendingPlunder: PlunderOffer?
    /// The encounter result to apply once a pending scoop is answered.
    public var pendingEncounterResult: RoundResult?
    /// The most recent opponent (C# `Game.Opponent` persists between encounters and feeds the cloak test).
    public var lastOpponent: Ship?
    /// Transit flags of the current or last trip (C# `Raided`, `Inspected`).
    public var raided = false
    public var inspected = false
    /// The transit to resume after the current encounter ends.
    public var encounterTransit: TransitState?
    public var phase: GamePhase = .docked
    public var cheatsUsed = false
    /// CHEAT-037: C# `EasyEncounters` (the "Yellow" cheat): encounters can be dismissed with `.cheat(.dismissEncounter)`.
    public var easyEncounters = false
    public var reloadCount = 0
    public var ironman = false

    public var ruleset: Ruleset { .named(rulesetID) }
    public var currentSystem: StarSystem { galaxy.systems[commander.currentSystem] }
}

/// Parameters for starting a game.
public struct NewGameConfig: Codable, Sendable, Equatable {
    public var commanderName: String
    public var difficulty: Difficulty
    /// Pilot, fighter, trader, engineer (each 1…10, total 20).
    public var skills: [Int]
    public var ruleset: RulesetID
    public var seed: UInt64
    public var ironman: Bool
    public var shipName: String?
    /// OPT-004: the options to start with (the app's defaults template); nil uses `GameOptions.defaults(for:)`.
    public var options: GameOptions?

    public init(commanderName: String, difficulty: Difficulty = .normal, skills: [Int] = [5, 5, 5, 5],
                ruleset: RulesetID = .modern, seed: UInt64, ironman: Bool = false, shipName: String? = nil,
                options: GameOptions? = nil) {
        self.options = options
        self.commanderName = commanderName
        self.difficulty = difficulty
        self.skills = skills
        self.ruleset = ruleset
        self.seed = seed
        self.ironman = ironman
        self.shipName = shipName
    }
}

public extension GameState {
    /// Builds the initial state for a new game.
    init(config: NewGameConfig) {
        let ruleset = Ruleset.named(config.ruleset)
        let g = GalaxyGenerator.newGame(ruleset: ruleset, difficulty: config.difficulty, seed: config.seed,
                                        commanderName: config.commanderName, skills: config.skills)
        rulesetID = config.ruleset
        difficulty = config.difficulty
        seed = config.seed
        rng = g.rng
        galaxy = g.galaxy
        mercenaries = g.mercenaries
        commander = g.commander
        commander.shipName = config.shipName
        specialShips = g.specialShips
        buyPrices = g.buyPrices
        sellPrices = g.sellPrices
        veryRareEncounters = g.veryRareEncounters
        warpSystem = g.commander.currentSystem
        ironman = config.ironman
        options = config.options?.normalized(for: ruleset) ?? ruleset.flags.defaultOptions
        if ruleset.flags.newGameForcesReminderOptions {
            options.remindLoans = true
            options.showTrackedRange = true
        }
        lastOpponent = Ship(type: .gnat, spec: ruleset.tables.ship(.gnat))
    }
}
