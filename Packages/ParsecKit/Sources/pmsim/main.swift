// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine

let args = CommandLine.arguments.dropFirst()
switch args.first {
case "fuzz":
    print("pmsim fuzz: no rulesets implemented yet (M0) — PASS")
case "bench":
    print("pmsim bench: no engine yet (M0) — PASS")
default:
    print("pmsim \(ParsecEngineInfo.version) — usage: pmsim fuzz|bench|replay|scenario|bot|dump-galaxy")
}
