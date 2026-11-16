// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// Debug launch arguments (CHEAT-047…051). Read by the app only; the engine never sees them.
struct LaunchOptions: Equatable, Sendable {
    /// `-PMSeed <n>`: New Game and Quick Start use this seed (CHEAT-048).
    var seed: UInt64?
    /// `-PMScenario <name>`: start in a named fixture (CHEAT-049). `smoke` is honoured in Release too.
    var scenario: String?
    /// `-PMFlavor template`: force the template flavor provider (CHEAT-050, used from M10).
    var flavorTemplate = false
    /// `-PMFastTravel`: instant transit animation (CHEAT-050, used from M9).
    var fastTravel = false
    /// `-PMAudio off`: no audio or haptics output (CHEAT-050, used from M11).
    var audioOff = false
    /// `-PMResetState`: wipe the Debug build's Application Support folder and defaults before anything is read (CHEAT-051).
    var resetState = false

    static let none = LaunchOptions()

    /// AppKit's default for this is YES: leftover command-line words are opened as documents.
    static let treatUnknownArgumentsAsOpenKey = "NSTreatUnknownArgumentsAsOpen"

    /// The build flavour the arguments are honoured in.
    static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// The options of this process.
    static var current: LaunchOptions { parse(ProcessInfo.processInfo.arguments, isDebug: isDebugBuild) }

    /// Pure parser. In Release only `-PMScenario smoke` is accepted (CHEAT-047).
    static func parse(_ arguments: [String], isDebug: Bool) -> LaunchOptions {
        var o = LaunchOptions()
        var i = 0
        func value(after index: Int) -> String? {
            index + 1 < arguments.count ? arguments[index + 1] : nil
        }
        while i < arguments.count {
            let arg = arguments[i]
            switch arg {
            case "-PMSeed":
                if let v = value(after: i), let n = UInt64(v) { o.seed = n; i += 1 }
            case "-PMScenario":
                if let v = value(after: i), !v.hasPrefix("-") { o.scenario = v; i += 1 }
            case "-PMFlavor":
                if let v = value(after: i) { o.flavorTemplate = v == "template"; i += 1 }
            case "-PMAudio":
                if let v = value(after: i) { o.audioOff = v == "off"; i += 1 }
            case "-PMFastTravel":
                // Accept both a bare flag and the NSUserDefaults style `-PMFastTravel YES`.
                o.fastTravel = true
                if let v = value(after: i), ["YES", "NO", "1", "0", "true", "false"].contains(v) {
                    o.fastTravel = ["YES", "1", "true"].contains(v)
                    i += 1
                }
            case "-PMResetState":
                o.resetState = true
                if let v = value(after: i), ["YES", "NO", "1", "0", "true", "false"].contains(v) {
                    o.resetState = ["YES", "1", "true"].contains(v)
                    i += 1
                }
            default:
                break
            }
            i += 1
        }
        if !isDebug {
            let smoke = o.scenario == "smoke"
            o = LaunchOptions()
            if smoke { o.scenario = "smoke" }
        }
        return o
    }
}
