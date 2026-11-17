// SPDX-License-Identifier: GPL-2.0-or-later
// The open encounter ledger and closed encounter records (docs/specs/LOG.md §4, LOG-019…021).
import ParsecEngine

/// LOG-020: one finished encounter's outcome, by the precedence of UI-ENC-052.
public enum EncounterOutcomeKind: Codable, Sendable, Equatable {
    case destroyed(ShipType)
    case disabled
    case escaped
    case opponentEscaped
    case plundered
    case traded
    case bribed(Int)
    case fined(Int)
    case inspectedClean
    case yielded
    case arrested
    case raided(units: Int)
    case artifactSurrendered
    case drank(good: Bool)
    case trained(SkillType)
    case escapePod
    case killed
    case passed
}

/// LOG-021: the coarse result class STAT counts.
public enum EncounterResultClass: String, Codable, Sendable, Equatable, CaseIterable {
    case won, fled, surrendered, lost, other
}

/// LOG-019: a closed encounter.
public struct EncounterRecord: Codable, Sendable, Equatable {
    public var type: EncounterType
    public var opponent: ShipType
    public var rounds: Int
    public var outcome: EncounterOutcomeKind
    /// Bounty paid in the encounter (0 when none).
    public var bounty: Int
    public var minHullPercent: Int
    public var killsAfter: Kills
    /// The ledger saw an accepted `.encounter(.surrender)`.
    public var surrendered: Bool

    public init(type: EncounterType, opponent: ShipType, rounds: Int, outcome: EncounterOutcomeKind, bounty: Int,
                minHullPercent: Int, killsAfter: Kills, surrendered: Bool = false) {
        self.type = type
        self.opponent = opponent
        self.rounds = rounds
        self.outcome = outcome
        self.bounty = bounty
        self.minHullPercent = minHullPercent
        self.killsAfter = killsAfter
        self.surrendered = surrendered
    }

    /// LOG-021, checked in the order won, fled, surrendered, lost, other.
    public var result: EncounterResultClass {
        switch outcome {
        case .destroyed, .disabled: return .won
        case .escaped: return .fled
        case .raided, .artifactSurrendered: return .surrendered
        case .killed, .escapePod, .arrested: return surrendered ? .surrendered : .lost
        case .opponentEscaped, .plundered, .traded, .bribed, .fined, .inspectedClean, .yielded, .drank, .trained, .passed:
            return surrendered ? .surrendered : .other
        }
    }
}

/// LOG-019: the encounter in progress, saved with the journal so a game saved mid-encounter resumes it.
public struct EncounterLedger: Codable, Sendable, Equatable {
    public var type: EncounterType
    public var opponent: ShipType
    public var startDay: Int
    public var startSystem: Int
    public var clicks: Int
    public var rounds: Int
    public var minPlayerHull: Int
    public var playerHullStrength: Int
    /// The encounter's events (combat, outcomes, plunder, police), in order.
    public var events: [GameEvent]
    public var surrendered: Bool

    public init(type: EncounterType, opponent: ShipType, startDay: Int, startSystem: Int, clicks: Int, rounds: Int = 0,
                minPlayerHull: Int, playerHullStrength: Int, events: [GameEvent] = [], surrendered: Bool = false) {
        self.type = type
        self.opponent = opponent
        self.startDay = startDay
        self.startSystem = startSystem
        self.clicks = clicks
        self.rounds = rounds
        self.minPlayerHull = minPlayerHull
        self.playerHullStrength = playerHullStrength
        self.events = events
        self.surrendered = surrendered
    }

    /// Adds one encounter event.
    mutating func fold(_ event: GameEvent) {
        if case let .combatRound(_, _, _, hull, _) = event {
            rounds += 1
            minPlayerHull = min(minPlayerHull, hull)
        }
        events.append(event)
    }

    /// LOG-019: the record appended when the ledger closes.
    func close(killsAfter: Kills) -> EncounterRecord {
        var bounty = 0
        for case let .bountyPaid(amount) in events { bounty += amount }
        let percent = playerHullStrength > 0 ? max(0, minPlayerHull) * 100 / playerHullStrength : 0
        return EncounterRecord(type: type, opponent: opponent, rounds: rounds, outcome: Self.outcome(of: events),
                               bounty: bounty, minHullPercent: percent, killsAfter: killsAfter, surrendered: surrendered)
    }

    // swiftlint:disable cyclomatic_complexity
    /// LOG-020: the UI-ENC-052 precedence (endings, arrest, combat, plunder, trade, police, pirates, very rare).
    public static func outcome(of events: [GameEvent]) -> EncounterOutcomeKind {
        var destroyed: ShipType?
        var disabled = false, escaped = false, opponentEscaped = false, plundered = false, traded = false
        var bribe: Int?, fine: Int?, clean = false, yielded = false, arrested = false
        var raided: Int?, artifact = false, drank: Bool?, trained: SkillType?, pod = false, killed = false
        for e in events {
            switch e {
            case let .opponentDestroyed(type): destroyed = type
            case .opponentDisabled: disabled = true
            case .playerEscaped: escaped = true
            case .opponentEscaped: opponentEscaped = true
            case .plundered: plundered = true
            case .orbitTradeCompleted: traded = true
            case let .bribed(amount): bribe = amount
            case let .fined(amount): fine = amount
            case .inspectionClean: clean = true
            case .yielded, .reactorConfiscated: yielded = true
            case .arrested: arrested = true
            case let .looted(units): raided = (raided ?? 0) + units
            case .blackmailed, .sculptureTaken, .preciousHidden, .wildJoinedPirates: raided = raided ?? 0
            case .artifactRelinquished: artifact = true
            case let .tonicConsumed(good): drank = good
            case let .captainTraining(skill): trained = skill
            case .escapePodUsed: pod = true
            case .playerDestroyed, .bothDestroyed: killed = true
            default: break
            }
        }
        if pod { return .escapePod }
        if killed { return .killed }
        if arrested { return .arrested }
        if let destroyed { return .destroyed(destroyed) }
        if plundered { return .plundered }
        if disabled { return .disabled }
        if escaped { return .escaped }
        if opponentEscaped { return .opponentEscaped }
        if traded { return .traded }
        if let bribe { return .bribed(bribe) }
        if let fine { return .fined(fine) }
        if clean { return .inspectedClean }
        if yielded { return .yielded }
        if let raided { return .raided(units: raided) }
        if artifact { return .artifactSurrendered }
        if let drank { return .drank(good: drank) }
        if let trained { return .trained(trained) }
        return .passed
    }
    // swiftlint:enable cyclomatic_complexity
}
