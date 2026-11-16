// SPDX-License-Identifier: GPL-2.0-or-later
// SAV §1–3: the envelope, decoding and validation errors, schema migration and the versioned fixtures.
import Foundation
import Testing
@testable import ParsecEngine
@testable import ParsecPersistence

/// The encoded envelope of `state` with its top-level JSON object edited by `edit`.
func editedSave(_ state: GameState = newState(), _ edit: (inout [String: Any]) -> Void) throws -> Data {
    var raw = try SaveCodec.rawObject(SaveCodec.encode(SaveEnvelope(state: state, appVersion: "t", gameID: "g", generation: 1)))
    edit(&raw)
    return try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys])
}

/// `body`'s error as a `SaveError`, or nil when it did not throw one.
func saveError(_ body: () throws -> Void) -> SaveError? {
    do {
        try body()
        return nil
    } catch let e as SaveError {
        return e
    } catch {
        return nil
    }
}

/// `Packages/ParsecKit/Tests/Fixtures/saves`.
let saveFixturesRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Fixtures/saves", isDirectory: true)

@Suite("SAV envelope and summary (SAV §1)")
struct SaveEnvelopeSpecTests {
    @Test("SAV-001 SAV-003 the envelope has exactly the eight keys; format, schema and ruleset come from the state")
    func envelopeKeys() throws {
        let state = newState(.palm122)
        let e = SaveEnvelope(state: state, appVersion: "9.9", gameID: "game-1", generation: 4)
        #expect(e.format == "parsec-merchant-save" && e.schemaVersion == SaveMigrator.currentSchemaVersion)
        #expect(e.rulesetID == .palm122 && e.appVersion == "9.9" && e.gameID == "game-1" && e.generation == 4)
        let raw = try SaveCodec.rawObject(SaveCodec.encode(e))
        #expect(Set(raw.keys) == ["format", "schemaVersion", "appVersion", "rulesetID", "gameID", "generation", "summary", "state"])
        #expect(raw["rulesetID"] as? String == "palm122" && raw["format"] as? String == "parsec-merchant-save")
        // appVersion is informational: a different value decodes the same state.
        let other = try SaveCodec.decode(editedSave(state) { $0["appVersion"] = "0.0.1-ancient" })
        #expect(other.state == state)
    }

    @Test("SAV-002 the summary is derived from the state: name, day, worth, system, Ironman, cheats, ended")
    func summary() throws {
        var state = newState(.windows201, ironman: true)
        state.commander.days = 77
        state.commander.cash = 12_345
        state.cheatsUsed = true
        let s = SaveSummary(state)
        #expect(s.commander == "Tester" && s.day == 77 && s.worth == state.worth && s.system == state.commander.currentSystem)
        #expect(s.ironman && s.cheatsUsed && !s.ended)
        state.phase = .gameOver(.killed)
        #expect(SaveSummary(state).ended)
        // A decoded summary that disagrees with the state is display data only: the state is what loads.
        let tampered = try SaveCodec.decode(editedSave(state) { raw in
            var summary = raw["summary"] as? [String: Any] ?? [:]
            summary["worth"] = 999_999_999
            raw["summary"] = summary
        })
        #expect(tampered.state == state && tampered.summary.worth == 999_999_999)
        #expect(SaveEnvelope(state: tampered.state, appVersion: "t").summary.worth == state.worth)
    }
}

@Suite("SAV decoding and validation (SAV §2)")
struct SaveDecodingSpecTests {
    @Test("SAV-008 non-JSON, non-objects, classic binary saves and a wrong or missing format are notASave")
    func notASave() throws {
        let classicCSharp = Data([0x00, 0x01, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0x01, 0x00, 0x00, 0x00])
        let palmDB = Data("SpaceTraderDatabase\0\0\0\0\0SAVEMERC".utf8)
        for data in [Data(), Data("not json".utf8), Data("[1,2,3]".utf8), Data("42".utf8), classicCSharp, palmDB] {
            #expect(saveError { _ = try SaveCodec.decode(data) } == .notASave)
        }
        #expect(saveError { _ = try SaveCodec.decode(editedSave { $0["format"] = "space-trader" }) } == .notASave)
        #expect(saveError { _ = try SaveCodec.decode(editedSave { $0.removeValue(forKey: "format") }) } == .notASave)
    }

    @Test("SAV-009 schemaVersion missing, non-integer or below 1 is corrupt; above current is unsupportedFutureVersion first")
    func schemaVersion() throws {
        for bad: Any in ["1", 0, -3, true, 1.5] {
            let e = saveError { _ = try SaveCodec.decode(editedSave { $0["schemaVersion"] = bad }) }
            #expect({ if case .corrupt = e { true } else { false } }(), "\(bad)")
        }
        #expect({ if case .corrupt = saveError({ _ = try SaveCodec.decode(editedSave { $0.removeValue(forKey: "schemaVersion") }) }) {
            true
        } else { false } }())
        // A future version is reported before any other validation, even with a broken state.
        let future = try editedSave { raw in
            raw["schemaVersion"] = SaveMigrator.currentSchemaVersion + 5
            raw["state"] = "garbage"
        }
        #expect(saveError { _ = try SaveCodec.decode(future) } == .unsupportedFutureVersion(SaveMigrator.currentSchemaVersion + 5))
    }

    @Test("SAV-010 RNG-035 undecodable or inconsistent saves are corrupt: ruleset, system count, indices, RNG kind")
    func validation() throws {
        func isCorrupt(_ data: Data) -> Bool {
            if case .corrupt = saveError({ _ = try SaveCodec.decode(data) }) { return true }
            return false
        }
        func editState(_ edit: @escaping (inout [String: Any]) -> Void) throws -> Data {
            try editedSave { raw in
                var state = raw["state"] as? [String: Any] ?? [:]
                edit(&state)
                raw["state"] = state
            }
        }
        #expect(try isCorrupt(editedSave { $0["state"] = ["nonsense": 1] }))
        #expect(try isCorrupt(editedSave { $0["rulesetID"] = "atari2600" }))
        #expect(try isCorrupt(editedSave { $0["rulesetID"] = "windows201" }))  // state is modern
        #expect(try isCorrupt(editedSave { $0["generation"] = 0 }))
        #expect(try isCorrupt(editState { s in
            var galaxy = s["galaxy"] as? [String: Any] ?? [:]
            galaxy["systems"] = Array((galaxy["systems"] as? [Any] ?? []).dropLast())
            s["galaxy"] = galaxy
        }))
        #expect(try isCorrupt(editState { s in s["warpSystem"] = 5_000 }))
        #expect(try isCorrupt(editState { s in s["trackedSystem"] = -1 }))
        #expect(try isCorrupt(editState { s in
            var commander = s["commander"] as? [String: Any] ?? [:]
            commander["currentSystem"] = 9_999
            s["commander"] = commander
        }))
        // RNG-035: a modern (xoshiro) save carrying a .NET RNG state is rejected, never reseeded.
        let dotNet = try JSONSerialization.jsonObject(with: JSONEncoder().encode(newState(.windows201).rng))
        #expect(try isCorrupt(editState { s in s["rng"] = dotNet }))
        // The untouched save decodes.
        #expect(try SaveCodec.decode(editedSave { _ in }).state == newState())
    }

    @Test("SAV-011 SaveError has exactly notASave, unsupportedFutureVersion, corrupt and migrationFailed")
    func errorCases() {
        let all: [SaveError] = [.notASave, .unsupportedFutureVersion(2), .corrupt("x"), .migrationFailed(from: 1)]
        for e in all {
            switch e {
            case .notASave, .unsupportedFutureVersion, .corrupt, .migrationFailed: break  // exhaustive: no other case
            }
        }
        #expect(Set(all.map { String(describing: $0).prefix(while: { $0 != "(" }) }).count == 4)
    }
}

@Suite("SAV schema migration and fixtures (SAV §3)")
struct SaveMigrationSpecTests {
    @Test("SAV-012 decoding parses raw JSON, migrates it, then decodes the migrated object")
    func rawThenTyped() throws {
        let raw = try SaveCodec.rawObject(editedSave { _ in })
        let migrated = try SaveMigrator.migrate(raw)
        #expect(migrated["schemaVersion"] as? Int == SaveMigrator.currentSchemaVersion)
        // A step that rewrites the raw object is what the typed decoder sees.
        let rename: SaveMigrator.Step = { old in
            var o = old
            var state = o["state"] as? [String: Any] ?? [:]
            var commander = state["commander"] as? [String: Any] ?? [:]
            commander["name"] = "Migrated"
            state["commander"] = commander
            o["state"] = state
            return o
        }
        let out = try SaveMigrator.migrate(raw, steps: [1: rename], target: 2)
        let bytes = try JSONSerialization.data(withJSONObject: out)
        let typed = try JSONDecoder().decode(SaveEnvelope.self, from: bytes)
        #expect(typed.state.commander.name == "Migrated" && typed.schemaVersion == 2)
    }

    @Test("SAV-013 currentSchemaVersion is 1 and the step table has one step per version below it, no gaps")
    func stepTable() {
        #expect(SaveMigrator.currentSchemaVersion == 1)
        #expect(SaveMigrator.steps.keys.sorted() == Array(1..<SaveMigrator.currentSchemaVersion))
        // Every version up to the current one has a fixture directory.
        for v in 1...SaveMigrator.currentSchemaVersion {
            #expect(FileOps.exists(saveFixturesRoot.appendingPathComponent("v\(v)")), "missing fixtures for v\(v)")
        }
    }

    @Test("SAV-014 a missing or throwing step is migrationFailed(from:); the current version migrates unchanged")
    func failures() throws {
        let raw = try SaveCodec.rawObject(editedSave { _ in })
        let unchanged = try SaveMigrator.migrate(raw)
        #expect(try JSONSerialization.data(withJSONObject: unchanged, options: [.sortedKeys])
                == JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys]))
        #expect(saveError { _ = try SaveMigrator.migrate(raw, steps: [:], target: 2) } == .migrationFailed(from: 1))
        struct Boom: Error {}
        let boom: SaveMigrator.Step = { _ in throw Boom() }
        #expect(saveError { _ = try SaveMigrator.migrate(raw, steps: [1: boom], target: 2) } == .migrationFailed(from: 1))
    }

    @Test("SAV-015 every fixture of every schema version decodes, satisfies SAV-010 and re-encodes deterministically")
    func fixtures() throws {
        var seen: Set<RulesetID> = []
        for v in 1...SaveMigrator.currentSchemaVersion {
            let dir = saveFixturesRoot.appendingPathComponent("v\(v)")
            var perVersion: Set<RulesetID> = []
            for name in fileNames(dir) where name.hasSuffix(".parsecsave") {
                let data = try Data(contentsOf: dir.appendingPathComponent(name))
                let raw = try SaveCodec.rawObject(data)
                #expect(raw["schemaVersion"] as? Int == v)
                let envelope = try SaveCodec.decode(data)  // includes SAV-010 validation
                #expect(envelope.schemaVersion == SaveMigrator.currentSchemaVersion)
                let once = try SaveCodec.encode(envelope)
                #expect(try SaveCodec.encode(SaveCodec.decode(once)) == once)
                if v == SaveMigrator.currentSchemaVersion { #expect(once == data, "\(name) is not canonical") }
                perVersion.insert(envelope.rulesetID)
            }
            #expect(perVersion == Set(RulesetID.allCases), "v\(v) needs one fixture per ruleset")
            seen.formUnion(perVersion)
        }
        #expect(seen.count == 3)
    }

    @Test("SAV-016 injected steps run in order v1 → v3, each sees the previous output; a throwing second step fails from 2")
    func injectedSteps() throws {
        let start: [String: Any] = ["format": "parsec-merchant-save", "schemaVersion": 1, "trail": [String]()]
        let one: SaveMigrator.Step = { o in
            var n = o
            #expect(o["schemaVersion"] as? Int == 1)
            n["trail"] = (o["trail"] as? [String] ?? []) + ["1→2"]
            return n
        }
        let two: SaveMigrator.Step = { o in
            var n = o
            #expect(o["schemaVersion"] as? Int == 2 && o["trail"] as? [String] == ["1→2"])
            n["trail"] = (o["trail"] as? [String] ?? []) + ["2→3"]
            return n
        }
        let out = try SaveMigrator.migrate(start, steps: [1: one, 2: two], target: 3)
        #expect(out["schemaVersion"] as? Int == 3 && out["trail"] as? [String] == ["1→2", "2→3"])
        struct Boom: Error {}
        let bad: SaveMigrator.Step = { _ in throw Boom() }
        #expect(saveError { _ = try SaveMigrator.migrate(start, steps: [1: one, 2: bad], target: 3) } == .migrationFailed(from: 2))
        #expect(saveError { _ = try SaveMigrator.migrate(start, steps: [1: one, 2: two], target: 2) } == nil)
    }
}
