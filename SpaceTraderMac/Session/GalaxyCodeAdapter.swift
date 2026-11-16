// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine

/// The galaxy code as the wizard, Bridge and Settings use it (UI-SHELL-028, -103, -104).
///
/// ADAPTER: `ParsecEngine.GalaxyCode` (UI-SHELL-116/117) is being added on a parallel engine branch. Until it lands,
/// this adapter implements the same format locally. When it is merged, replace the two function bodies with
/// `GalaxyCode(ruleset:difficulty:seed:).string` and `GalaxyCode(string:)` and delete `Local`; callers don't change.
enum GalaxyCodeAdapter {
    struct Value: Equatable, Sendable {
        var ruleset: RulesetID
        var difficulty: Difficulty
        var seed: UInt64
    }

    static func string(ruleset: RulesetID, difficulty: Difficulty, seed: UInt64) -> String {
        Local.string(Value(ruleset: ruleset, difficulty: difficulty, seed: seed))
    }

    static func parse(_ text: String) -> Value? {
        Local.parse(text)
    }

    /// Local implementation of the UI-SHELL-116/117 format (Crockford base 32, check symbol, groups of 4).
    enum Local {
        static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

        static func letter(_ r: RulesetID) -> Character {
            switch r {
            case .modern: "M"
            case .windows201: "W"
            case .palm122: "P"
            }
        }

        static func ruleset(_ c: Character) -> RulesetID? {
            RulesetID.allCases.first { letter($0) == c }
        }

        static func value(_ c: Character) -> Int? { alphabet.firstIndex(of: c) }

        static func check(_ symbols: [Character]) -> Character {
            var sum = 0
            for (k, c) in symbols.enumerated() { sum += (k + 1) * (value(c) ?? 0) }
            return alphabet[sum % 32]
        }

        static func seedSymbols(_ seed: UInt64) -> [Character] {
            if seed == 0 { return ["0"] }
            var out: [Character] = []
            var s = seed
            while s > 0 {
                out.append(alphabet[Int(s & 31)])
                s >>= 5
            }
            return out.reversed()
        }

        static func string(_ v: Value) -> String {
            let head: [Character] = [letter(v.ruleset), alphabet[v.difficulty.rawValue]]
            let seed = seedSymbols(v.seed)
            let c = check(head + seed)
            var groups: [String] = []
            var i = 0
            while i < seed.count {
                groups.append(String(seed[i..<min(i + 4, seed.count)]))
                i += 4
            }
            return String(head) + "-" + groups.joined(separator: "-") + "-" + String(c)
        }

        static func parse(_ text: String) -> Value? {
            let mapped: [Character] = text.uppercased().compactMap { ch in
                switch ch {
                case " ", "-": nil
                case "O": "0"
                case "I", "L": "1"
                default: ch
                }
            }
            guard mapped.count >= 4, let r = ruleset(mapped[0]), let dv = value(mapped[1]),
                  let d = Difficulty(rawValue: dv), mapped[1].isNumber else { return nil }
            let seedPart = Array(mapped[2..<(mapped.count - 1)])
            guard !seedPart.isEmpty, seedPart.count <= 13 else { return nil }
            var seed: UInt64 = 0
            for c in seedPart {
                guard let v = value(c) else { return nil }
                guard seed <= (UInt64.max >> 5) else { return nil }
                seed = (seed << 5) | UInt64(v)
            }
            guard let last = mapped.last, value(last) != nil, check(Array(mapped.dropLast())) == last else { return nil }
            return Value(ruleset: r, difficulty: d, seed: seed)
        }
    }
}
