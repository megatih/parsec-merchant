// SPDX-License-Identifier: GPL-2.0-or-later
// Save file format (docs/specs/SAV.md, PRD §6.4): versioned JSON envelope, deterministic codec, raw-JSON migrator.
import Foundation
import ParsecEngine

/// The summary shown in the save list without decoding the whole state.
public struct SaveSummary: Codable, Sendable, Equatable {
    public var commander: String
    public var day: Int
    public var worth: Int
    public var system: Int
    public var ironman: Bool

    public init(commander: String, day: Int, worth: Int, system: Int, ironman: Bool) {
        self.commander = commander
        self.day = day
        self.worth = worth
        self.system = system
        self.ironman = ironman
    }

    public init(_ s: GameState) {
        self.init(commander: s.commander.name, day: s.commander.days, worth: s.worth, system: s.commander.currentSystem,
                  ironman: s.ironman)
    }
}

/// `{format, schemaVersion, appVersion, rulesetID, summary, state}`.
public struct SaveEnvelope: Codable, Sendable, Equatable {
    public static let formatName = "parsec-merchant-save"
    public var format: String
    public var schemaVersion: Int
    public var appVersion: String
    public var rulesetID: RulesetID
    public var summary: SaveSummary
    public var state: GameState

    public init(state: GameState, appVersion: String) {
        self.format = Self.formatName
        self.schemaVersion = SaveMigrator.currentSchemaVersion
        self.appVersion = appVersion
        self.rulesetID = state.rulesetID
        self.summary = SaveSummary(state)
        self.state = state
    }
}

public enum SaveError: Error, Equatable, Sendable {
    case notASave
    case unsupportedFutureVersion(Int)
    case corrupt(String)
    case migrationFailed(from: Int)
}

/// Deterministic UTF-8 JSON with sorted keys: decoding and re-encoding gives identical bytes.
public enum SaveCodec {
    public static func encode(_ envelope: SaveEnvelope) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try enc.encode(envelope)
    }

    public static func decode(_ data: Data) throws -> SaveEnvelope {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw SaveError.corrupt("not JSON")
        }
        guard let raw = object as? [String: Any], raw["format"] as? String == SaveEnvelope.formatName else {
            throw SaveError.notASave
        }
        let migrated = try SaveMigrator.migrate(raw)
        do {
            let bytes = try JSONSerialization.data(withJSONObject: migrated, options: [.sortedKeys])
            return try JSONDecoder().decode(SaveEnvelope.self, from: bytes)
        } catch {
            throw SaveError.corrupt("\(error)")
        }
    }
}

/// Upgrades raw save JSON one schema version at a time. Every past version keeps a fixture in the tests.
public enum SaveMigrator {
    /// Version 1 is the first released format.
    public static let currentSchemaVersion = 1

    /// `steps[n]` upgrades a version-n object to version n+1.
    static let steps: [Int: @Sendable ([String: Any]) throws -> [String: Any]] = [:]

    public static func migrate(_ raw: [String: Any]) throws -> [String: Any] {
        guard let version = raw["schemaVersion"] as? Int, version >= 1 else { throw SaveError.corrupt("schemaVersion") }
        if version > currentSchemaVersion { throw SaveError.unsupportedFutureVersion(version) }
        var object = raw
        var v = version
        while v < currentSchemaVersion {
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
