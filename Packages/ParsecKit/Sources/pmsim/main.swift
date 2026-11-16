// SPDX-License-Identifier: GPL-2.0-or-later
// pmsim — headless Parsec Merchant simulator: fuzz | bench | replay | scenario | bot | dump-galaxy.
import Foundation
import ParsecEngine

struct Args {
    var command: String
    var options: [String: String]

    init(_ argv: [String]) {
        command = argv.first ?? "help"
        var opts: [String: String] = [:]
        var i = 1
        while i < argv.count {
            let key = argv[i]
            if key.hasPrefix("--") {
                let name = String(key.dropFirst(2))
                if i + 1 < argv.count, !argv[i + 1].hasPrefix("--") {
                    opts[name] = argv[i + 1]
                    i += 2
                } else {
                    opts[name] = "true"
                    i += 1
                }
            } else {
                i += 1
            }
        }
        options = opts
    }

    func int(_ k: String, _ d: Int) -> Int { options[k].flatMap(Int.init) ?? d }
    func rulesets() -> [RulesetID] {
        switch options["ruleset"] ?? "windows201" {
        case "all": return RulesetID.allCases
        case let r: return RulesetID(rawValue: r).map { [$0] } ?? [.windows201]
        }
    }
}

let args = Args(Array(CommandLine.arguments.dropFirst()))

switch args.command {
case "dump-galaxy":
    // GAL-068: canonical JSON of the initial state for a ruleset and seed.
    let ruleset = args.rulesets().first ?? .windows201
    let difficulty = Difficulty(rawValue: args.int("difficulty", Difficulty.normal.rawValue)) ?? .normal
    let state = GameState(config: NewGameConfig(commanderName: "pmsim", difficulty: difficulty, ruleset: ruleset,
                                                seed: UInt64(args.int("seed", 1))))
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys]
    do {
        FileHandle.standardOutput.write(try enc.encode(state))
        print()
    } catch {
        FileHandle.standardError.write(Data("encode failed: \(error)\n".utf8))
        exit(1)
    }
case "fuzz":
    // Travel and encounters land in M3; until then fuzzing is a no-op PASS (PRD §8.1 step 3).
    print("pmsim fuzz: travel not implemented yet — no-op PASS")
case "bench":
    print("pmsim bench: benchmarks start in M8 — no-op PASS")
default:
    print("pmsim \(ParsecEngineInfo.version) — usage: pmsim fuzz|bench|replay|scenario|bot|dump-galaxy [--ruleset r|all] [--seed n]")
}
