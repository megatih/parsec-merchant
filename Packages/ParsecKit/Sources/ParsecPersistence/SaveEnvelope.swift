// SPDX-License-Identifier: GPL-2.0-or-later
// Save file format (docs/specs/SAV.md, PRD §6.4): versioned JSON envelope, deterministic codec, raw-JSON migrator.
import Foundation
import ParsecEngine
import ParsecInsights

/// SAV-002: the summary shown in the save list. Always derived from the state; display data only.
public struct SaveSummary: Codable, Sendable, Equatable {
    public var commander: String
    public var day: Int
    public var worth: Int
    public var system: Int
    public var ironman: Bool
    public var cheatsUsed: Bool
    public var ended: Bool

    public init(_ s: GameState) {
        commander = s.commander.name
        day = s.commander.days
        worth = s.worth
        system = s.commander.currentSystem
        ironman = s.ironman
        cheatsUsed = s.cheatsUsed
        if case .gameOver = s.phase { ended = true } else { ended = false }
    }
}

/// SAV-001: `{format, schemaVersion, appVersion, rulesetID, gameID, generation, summary, state, journal}`.
public struct SaveEnvelope: Codable, Sendable, Equatable {
    public static let formatName = "parsec-merchant-save"
    public var format: String
    public var schemaVersion: Int
    public var appVersion: String
    public var rulesetID: RulesetID
    /// SAV-031: persistence metadata identifying the game across slots; never part of `GameState`.
    public var gameID: String
    /// SAV-032: stamped by `SlotStore` when the envelope is written.
    public var generation: Int
    public var summary: SaveSummary
    public var state: GameState
    /// LOG-001…004 / ADR-0003: the game journal (log, intel, open encounter), beside `state` and never inside it.
    public var journal: GameJournal

    enum CodingKeys: String, CodingKey {
        case format, schemaVersion, appVersion, rulesetID, gameID, generation, summary, state, journal
    }

    /// SAV-003. `gameID` and `generation` are normally assigned by `SlotStore` on write. Without a journal the
    /// envelope gets `GameJournal.bootstrap(from: state)` (LOG-006).
    public init(state: GameState, appVersion: String, gameID: String = "", generation: Int = 1, journal: GameJournal? = nil) {
        self.journal = journal ?? GameJournal.bootstrap(from: state)
        self.format = Self.formatName
        self.schemaVersion = SaveMigrator.currentSchemaVersion
        self.appVersion = appVersion
        self.rulesetID = state.rulesetID
        self.gameID = gameID
        self.generation = generation
        self.summary = SaveSummary(state)
        self.state = state
    }

    /// LOG-004: a save without `journal` (a pre-M10 development save) decodes with a bootstrapped journal; a present
    /// but undecodable journal fails like any other field.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decode(String.self, forKey: .format)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        appVersion = try c.decode(String.self, forKey: .appVersion)
        rulesetID = try c.decode(RulesetID.self, forKey: .rulesetID)
        gameID = try c.decode(String.self, forKey: .gameID)
        generation = try c.decode(Int.self, forKey: .generation)
        summary = try c.decode(SaveSummary.self, forKey: .summary)
        state = try c.decode(GameState.self, forKey: .state)
        journal = try c.decodeIfPresent(GameJournal.self, forKey: .journal) ?? GameJournal.bootstrap(from: state)
    }
}

/// SAV-011. The payloads are diagnostic only; the app maps every case to a localized `SystemAlert.openFailed`.
public enum SaveError: Error, Equatable, Sendable {
    case notASave
    case unsupportedFutureVersion(Int)
    case corrupt(String)
    case migrationFailed(from: Int)
}

/// SAV-004…010: deterministic UTF-8 JSON with sorted keys; decoding and re-encoding gives identical bytes.
public enum SaveCodec {
    public static func encode(_ envelope: SaveEnvelope) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try enc.encode(envelope)
    }

    /// Parses the top level and checks `format` (SAV-008).
    static func rawObject(_ data: Data) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let raw = object as? [String: Any],
              raw["format"] as? String == SaveEnvelope.formatName else {
            throw SaveError.notASave
        }
        return raw
    }

    public static func decode(_ data: Data) throws -> SaveEnvelope {
        let migrated = try SaveMigrator.migrate(rawObject(data))
        let envelope: SaveEnvelope
        do {
            let bytes = try JSONSerialization.data(withJSONObject: migrated, options: [.sortedKeys])
            envelope = try JSONDecoder().decode(SaveEnvelope.self, from: bytes)
        } catch {
            throw SaveError.corrupt("decode: \(error)")
        }
        try validate(envelope)
        return envelope
    }

    /// SAV-010, RNG-035: structural checks the typed decoder can't express.
    static func validate(_ e: SaveEnvelope) throws {
        let s = e.state
        guard e.rulesetID == s.rulesetID else { throw SaveError.corrupt("rulesetID differs from state") }
        guard !e.gameID.isEmpty, e.generation >= 1 else { throw SaveError.corrupt("gameID/generation") }
        let ruleset = s.ruleset
        guard s.rng.kind == ruleset.rngKind else { throw SaveError.corrupt("rng kind") }
        let count = ruleset.tables.systemNames.count
        guard s.galaxy.systems.count == count else { throw SaveError.corrupt("system count") }
        let valid = 0..<count
        guard valid.contains(s.commander.currentSystem), valid.contains(s.warpSystem) else {
            throw SaveError.corrupt("system index")
        }
        if let tracked = s.trackedSystem, !valid.contains(tracked) { throw SaveError.corrupt("tracked system") }
        // LOG-004: the journal's intel has one entry per system.
        guard e.journal.intel.systems.count == count else { throw SaveError.corrupt("journal intel") }
    }
}

/// SAV-012…016: upgrades raw save JSON one schema version at a time. Every past version keeps a fixture in the tests.
public enum SaveMigrator {
    public typealias Step = @Sendable ([String: Any]) throws -> [String: Any]

    /// Version 1 is the first released format.
    public static let currentSchemaVersion = 1

    /// `steps[n]` upgrades a version-n object to version n+1 (one entry for every n in 1..<currentSchemaVersion).
    public static let steps: [Int: Step] = [:]

    public static func migrate(_ raw: [String: Any]) throws -> [String: Any] {
        try migrate(raw, steps: steps, target: currentSchemaVersion)
    }

    /// The step chain with an injected table (SAV-016).
    public static func migrate(_ raw: [String: Any], steps: [Int: Step], target: Int) throws -> [String: Any] {
        guard let number = raw["schemaVersion"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              let version = raw["schemaVersion"] as? Int, version >= 1 else {
            throw SaveError.corrupt("schemaVersion")
        }
        if version > target { throw SaveError.unsupportedFutureVersion(version) }
        var object = raw
        var v = version
        while v < target {
            guard let step = steps[v] else { throw SaveError.migrationFailed(from: v) }
            do {
                object = try step(object)
            } catch {
                throw SaveError.migrationFailed(from: v)
            }
            v += 1
            object["schemaVersion"] = v
        }
        return object
    }
}
