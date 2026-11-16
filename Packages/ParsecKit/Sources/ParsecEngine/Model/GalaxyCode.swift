// SPDX-License-Identifier: GPL-2.0-or-later
// The shareable galaxy code (PRD §6.6; docs/specs/UI-SHELL.md UI-SHELL-116…118): ruleset, difficulty and seed in
// Crockford base 32 with a check symbol. Universe generation depends on all three, so equal codes give equal galaxies.

/// A galaxy code: the inputs of universe generation, as a short string friends can exchange.
public struct GalaxyCode: Sendable, Equatable, Hashable {
    public var ruleset: RulesetID
    public var difficulty: Difficulty
    public var seed: UInt64

    /// Crockford base 32 (no I, L, O, U).
    static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    /// At most 13 symbols hold a UInt64 (64 = 12 × 5 + 4 bits).
    static let maxSeedSymbols = 13

    public init(ruleset: RulesetID, difficulty: Difficulty, seed: UInt64) {
        self.ruleset = ruleset
        self.difficulty = difficulty
        self.seed = seed
    }

    /// The code of a game's galaxy.
    public init(_ state: GameState) {
        self.init(ruleset: state.rulesetID, difficulty: state.difficulty, seed: state.seed)
    }

    static func letter(_ id: RulesetID) -> Character { Ruleset.named(id).galaxyCodeLetter }

    /// UI-SHELL-116: the display form, e.g. `W2-3FAV-FQF-1`.
    public var string: String {
        var seedSymbols: [Character] = []
        var rest = seed
        repeat {
            seedSymbols.insert(Self.alphabet[Int(rest % 32)], at: 0)
            rest /= 32
        } while rest > 0
        let head: [Character] = [Self.letter(ruleset), Self.alphabet[difficulty.rawValue]]
        let check = Self.alphabet[Self.checkValue(head + seedSymbols)]
        let groups = stride(from: 0, to: seedSymbols.count, by: 4).map {
            String(seedSymbols[$0..<min($0 + 4, seedSymbols.count)])
        }
        return String(head) + "-" + groups.joined(separator: "-") + "-" + String(check)
    }

    /// UI-SHELL-117: parses a code, tolerating case, spaces, hyphens and the Crockford look-alikes (O→0, I/L→1).
    public init?(string: String) {
        let symbols: [Character] = string.uppercased().compactMap { c -> Character? in
            switch c {
            case " ", "-": nil
            case "O": "0"
            case "I", "L": "1"
            default: c
            }
        }
        guard symbols.count >= 4,
              let ruleset = RulesetID.allCases.first(where: { Self.letter($0) == symbols[0] }),
              let digit = symbols[1].wholeNumberValue, symbols[1].isASCII,
              let difficulty = Difficulty(rawValue: digit) else { return nil }
        let seedSymbols = symbols[2..<(symbols.count - 1)]
        guard seedSymbols.count <= Self.maxSeedSymbols else { return nil }
        var seed: UInt64 = 0
        for c in seedSymbols {
            guard let v = Self.alphabet.firstIndex(of: c) else { return nil }
            let (shifted, overflow) = seed.multipliedReportingOverflow(by: 32)
            guard !overflow else { return nil }
            seed = shifted | UInt64(v)
        }
        guard let check = Self.alphabet.firstIndex(of: symbols[symbols.count - 1]),
              check == Self.checkValue(Array(symbols.dropLast())) else { return nil }
        self.init(ruleset: ruleset, difficulty: difficulty, seed: seed)
    }

    /// `(Σ_k (k+1) · v_k) mod 32` over the symbol values (a letter's value is its alphabet index).
    static func checkValue(_ symbols: [Character]) -> Int {
        var sum = 0
        for (k, c) in symbols.enumerated() {
            sum += (k + 1) * (alphabet.firstIndex(of: c) ?? 0)
        }
        return sum % 32
    }
}
