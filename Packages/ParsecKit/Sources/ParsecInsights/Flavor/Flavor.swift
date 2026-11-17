// SPDX-License-Identifier: GPL-2.0-or-later
// Flavor text values and the provider protocol (docs/specs/LLM.md §1, LLM-001…005). Cosmetic only: no flavor value
// is ever read by the rules, the recorder (except to attach it), STAT, ACH or INT.
import ParsecEngine

/// LLM-005: who wrote a flavor text.
public enum FlavorSource: String, Codable, Sendable, Equatable {
    case template
    case foundationModels
}

/// LLM-004: a typed template argument; the app formats names and numbers.
public enum FlavorArg: Codable, Sendable, Equatable {
    case system(Int)
    case ship(ShipType)
    case item(TradeItemType)
    case count(Int)
    case credits(Int)
    case skill(SkillType)
}

/// LLM-004: a template line as a catalog key plus typed arguments (no prose in the package).
public struct FlavorLine: Codable, Sendable, Equatable {
    public var key: String
    public var args: [FlavorArg]

    public init(key: String, args: [FlavorArg] = []) {
        self.key = key
        self.args = args
    }
}

/// LLM-004: the flavor cached on a log entry.
public enum FlavorText: Codable, Sendable, Equatable {
    case template(FlavorLine)
    case generated(text: String)

    /// LLM-005.
    public var source: FlavorSource {
        switch self {
        case .template: .template
        case .generated: .foundationModels
        }
    }
}

/// LLM-003: the typed facts a flavor line is written about.
public enum FlavorSubject: Codable, Sendable, Equatable {
    case arrival(system: Int, viaWormhole: Bool, firstVisit: Bool, uneventful: Bool, encounterCount: Int)
    case encounter(type: EncounterType, opponent: ShipType, result: EncounterResultClass, rounds: Int, minHullPercent: Int)
    case quest(SpecialEventType)
    case gameEnded(GameEndType)
    case achievement(AchievementID)

    /// LLM-007 / LLM-010: the template group of the subject.
    public var group: FlavorGroup {
        switch self {
        case let .arrival(_, via, first, _, count):
            via ? .arrivalWormhole : first ? .arrivalFirstVisit : count > 0 ? .arrivalEventful : .arrivalQuiet
        case let .encounter(_, _, result, _, _):
            switch result {
            case .won: .encounterWon
            case .fled: .encounterFled
            case .surrendered: .encounterSurrendered
            case .lost: .encounterLost
            case .other: .encounterOther
            }
        case let .quest(event): FlavorGroup.questGroup(event)
        case let .gameEnded(end):
            switch end {
            case .killed: .gameEndedKilled
            case .retired: .gameEndedRetired
            case .boughtMoon, .boughtMoonGirl: .gameEndedMoon
            }
        case .achievement: .achievement
        }
    }

    /// LLM-007: a fixed code per case and variant group.
    public var code: UInt32 { group.code }
}

/// LLM-002: a flavor request, built from a log entry alone (no state, no engine).
public struct FlavorRequest: Codable, Sendable, Equatable {
    public var entryID: Int
    public var day: Int
    public var system: Int
    public var subject: FlavorSubject

    public init(entryID: Int, day: Int, system: Int, subject: FlavorSubject) {
        self.entryID = entryID
        self.day = day
        self.system = system
        self.subject = subject
    }

    /// LLM-002: the request for an entry, or nil when the entry carries no flavor (LOG-011).
    public init?(entry: LogEntry) {
        guard let subject = entry.kind.flavorSubject else { return nil }
        self.init(entryID: entry.id, day: entry.day, system: entry.system, subject: subject)
    }
}

/// LLM-001: a flavor provider. A nil result means "no flavor from this provider" (the template stays).
public protocol FlavorProvider: Sendable {
    var source: FlavorSource { get }
    func flavor(for request: FlavorRequest) async -> FlavorText?
}

/// LLM-007: FNV-1a 64 over the little-endian bytes of the entry id, day, system and subject code.
public enum FlavorSeed {
    static let offset: UInt64 = 0xCBF2_9CE4_8422_2325
    static let prime: UInt64 = 0x0000_0100_0000_01B3

    public static func make(_ request: FlavorRequest) -> UInt64 {
        var h = offset
        func mix(_ bytes: some Sequence<UInt8>) {
            for b in bytes {
                h ^= UInt64(b)
                h = h &* prime
            }
        }
        func le64(_ v: Int) -> [UInt8] { (0..<8).map { UInt8(truncatingIfNeeded: UInt64(bitPattern: Int64(v)) >> ($0 * 8)) } }
        mix(le64(request.entryID))
        mix(le64(request.day))
        mix(le64(request.system))
        mix((0..<4).map { UInt8(truncatingIfNeeded: request.subject.code >> ($0 * 8)) })
        return h
    }
}
