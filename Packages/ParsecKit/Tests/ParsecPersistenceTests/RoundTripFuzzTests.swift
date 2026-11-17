// SPDX-License-Identifier: GPL-2.0-or-later
// SAV §1: canonical JSON and round trips over fuzz-played states (PRD §9 M6 exit: 500 byte-identical round trips).
import Foundation
import Testing
@testable import ParsecEngine
import ParsecInsights
@testable import ParsecPersistence

/// Every JSON number token in `data` (outside strings), as written.
private func numberTokens(_ data: Data) -> [String] {
    var out: [String] = []
    var inString = false, escaped = false
    var current: String?
    for byte in data {
        let c = Character(UnicodeScalar(byte))
        if inString {
            if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
            continue
        }
        if var token = current, c.isNumber || "+-.eE".contains(c) {
            token.append(c)
            current = token
            continue
        }
        if let token = current { out.append(token) }
        current = nil
        if c == "\"" { inString = true } else if c.isNumber || c == "-" { current = String(c) }
    }
    if let token = current { out.append(token) }
    return out
}

@Suite("SAV round trips over fuzzed states")
struct RoundTripFuzzTests {
    @Test("SAV-005 LOG-003 500 fuzzed states with their journals across all rulesets and phases round-trip byte-identically")
    func fuzzedRoundTrips() throws {
        var categories: Set<String> = []
        var total = 0
        var openLedgers = 0
        for (i, ruleset) in RulesetID.allCases.enumerated() {
            let games = FuzzPlayer.sampleGames(ruleset, count: i == 0 ? 168 : 166, seed: 50_000 + UInt64(i) * 1_000)
            for (state, journal) in games {
                categories.insert(FuzzPlayer.category(state))
                if journal.openEncounter != nil { openLedgers += 1 }
                let envelope = SaveEnvelope(state: state, appVersion: "test", gameID: SlotStore.newSlotID(), generation: 1 + total % 7,
                                            journal: journal)
                let bytes = try SaveCodec.encode(envelope)
                let decoded = try SaveCodec.decode(bytes)
                #expect(decoded == envelope)
                #expect(try SaveCodec.encode(decoded) == bytes)
                total += 1
            }
        }
        #expect(total == 500 && openLedgers > 0)
        // Docked, mid-encounter, pending scoop / plunder and game over all appear in the sample.
        for needed in ["docked", "encounter", "scoop", "plunder", "gameOver"] {
            #expect(categories.contains(needed), "missing \(needed) in \(categories)")
        }
        // Transit is not a resting phase between commands; one is built explicitly.
        var transit = newState(.palm122)
        transit.phase = .inTransit(TransitState(destination: 3, clicksRemaining: 12, viaWormhole: true, raided: true))
        let te = SaveEnvelope(state: transit, appVersion: "t", gameID: "g", generation: 2)
        #expect(try SaveCodec.decode(SaveCodec.encode(te)) == te)
    }

    @Test("SAV-004 encoding is deterministic: sorted keys at every level, UTF-8 text, unescaped slashes")
    func canonicalJSON() throws {
        var state = newState(.windows201, name: "Zoë/🚀")
        state.commander.shipName = "Ünïcode/Ship"
        let envelope = SaveEnvelope(state: state, appVersion: "1.0/beta", gameID: "abc", generation: 3)
        let a = try SaveCodec.encode(envelope)
        let b = try SaveCodec.encode(envelope)
        #expect(a == b)
        let text = try #require(String(data: a, encoding: .utf8))
        #expect(text.contains("Zoë/🚀") && text.contains("1.0/beta"))
        #expect(!text.contains("\\/") && !text.contains("\\u"))
        // Keys are sorted at every level: re-serializing with sorted keys yields the same key order.
        let raw = try JSONSerialization.jsonObject(with: a)
        let resorted = try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
        #expect(try SaveCodec.encode(SaveCodec.decode(resorted)) == a)
        let top = try #require(raw as? [String: Any])
        #expect(Set(top.keys) == ["format", "schemaVersion", "appVersion", "rulesetID", "gameID", "generation", "summary", "state",
                                  "journal"])
        // Top-level keys appear in lexicographic order in the bytes.
        let order = ["appVersion", "format", "gameID", "generation", "journal", "rulesetID", "schemaVersion", "state", "summary"]
        let positions = order.compactMap { text.range(of: "\n  \"\($0)\"")?.lowerBound }
        #expect(positions.count == order.count && positions == positions.sorted())
    }

    @Test("SAV-006 integer extremes survive encode, decode and the migrator path; the state has no fractional numbers")
    func integerFidelity() throws {
        for ruleset in RulesetID.allCases {
            var state = newState(ruleset, seed: UInt64.max)
            state.seed = UInt64.max
            // Extremes go in fields outside the worth sum (worth would overflow).
            state.commander.policeRecordScore = Int.min
            state.commander.reputationScore = Int.max
            state.commander.days = Int.max
            state.reloadCount = Int.max
            if case .xoshiro = state.rng {
                let words = #"{"s":["FFFFFFFFFFFFFFFF","8000000000000000","0000000000000001","FFFFFFFFFFFFFFFE"]}"#
                state.rng = .xoshiro(try JSONDecoder().decode(Xoshiro256StarStar.self, from: Data(words.utf8)))
            }
            let envelope = SaveEnvelope(state: state, appVersion: "t", gameID: "g", generation: Int.max)
            let bytes = try SaveCodec.encode(envelope)
            let decoded = try SaveCodec.decode(bytes)
            #expect(decoded == envelope)
            #expect(decoded.state.seed == UInt64.max && decoded.state.commander.policeRecordScore == Int.min)
            #expect(decoded.state.rng == state.rng)
            // Through an injected migration step (raw JSON in, raw JSON out).
            let identity: SaveMigrator.Step = { $0 }
            var raw = try SaveCodec.rawObject(bytes)
            raw["schemaVersion"] = 1
            let migrated = try SaveMigrator.migrate(raw, steps: [1: identity], target: 2)
            var viaStep = try JSONDecoder().decode(SaveEnvelope.self,
                                                   from: JSONSerialization.data(withJSONObject: migrated, options: [.sortedKeys]))
            #expect(viaStep.schemaVersion == 2)
            viaStep.schemaVersion = 1
            #expect(viaStep == envelope)
            // No number in the encoded state has a fraction or an exponent.
            let stateBytes = try JSONEncoder().encode(decoded.state)
            #expect(!numberTokens(stateBytes).contains { $0.contains(".") || $0.contains("e") || $0.contains("E") })
        }
    }

    @Test("SAV-007 names with non-ASCII and JSON-special characters round-trip exactly")
    func specialNames() throws {
        for name in ["Zoë 🚀", "Quote \" back\\slash / slash", "日本語の名前", "tab\tnew\nline"] {
            var state = newState(.modern, name: name)
            state.commander.shipName = name + " II"
            let envelope = SaveEnvelope(state: state, appVersion: "t", gameID: "g", generation: 1)
            let bytes = try SaveCodec.encode(envelope)
            let decoded = try SaveCodec.decode(bytes)
            #expect(decoded.state.commander.name == name && decoded.state.commander.shipName == name + " II")
            #expect(decoded.summary.commander == name)
            #expect(try SaveCodec.encode(decoded) == bytes)
        }
    }
}
