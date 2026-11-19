// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// `-PMWindowSize` values (A11Y-002).
nonisolated enum LaunchWindowSize: String, Sendable {
    case minimum = "min"
    case standard = "default"
}

/// `-PMAppearance` values (A11Y-002): the app appearance, independent of the Mac's.
nonisolated enum LaunchAppearance: String, Sendable {
    case light
    case dark
}

/// `-PMTips` values (A11Y-002, A11Y-047).
nonisolated enum TipsLaunchMode: String, Sendable {
    /// `Tips.hideAllTipsForTesting()` before `configure` (every UI test).
    case off
    /// `Tips.showAllTipsForTesting()` before `configure` (TipsUITests).
    case all
}

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
    /// `-PMSlowTravel <factor>`: multiplies the transit tick interval, clamped to 1…50 (CHEAT-050, UI-ENC-096).
    var slowTravel = 1
    /// `-PMAudio off`: no audio or haptics output (CHEAT-050, used from M11).
    var audioOff = false
    /// `-PMResetState`: wipe the Debug build's Application Support folder and defaults before anything is read (CHEAT-051).
    var resetState = false
    /// `-PMA11y <list>`: forces accessibility display settings on (A11Y-002), OR'd with the system's (A11Y-001).
    var accessibility = AccessibilityPreferences.standard
    /// `-PMTips off|all`: hides every tip or shows all of them (A11Y-047). Nil: TipKit's own rules.
    var tips: TipsLaunchMode?
    /// `-PMWindowSize min|default`: opens the main window at its 1100×720 minimum (A11Y-002) or its 1320×860 default size,
    /// centred, ignoring the restored frame (UI tests use `default` so every run starts from the same frame).
    var windowSize: LaunchWindowSize?
    /// `-PMWindowPoints <width>x<height>`: opens the main window at this content size (the layout tests, UI-BRG-033).
    var windowPoints: CGSize?
    var minimumWindow: Bool { windowSize == .minimum }
    /// `-PMAppearance light|dark`: forces the app's appearance (A11Y-002). Nil: follow the system.
    var appearance: LaunchAppearance?

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
            case "-PMSlowTravel":
                if let v = value(after: i), let n = Int(v) { o.slowTravel = min(max(n, 1), 50); i += 1 }
            case "-PMResetState":
                o.resetState = true
                if let v = value(after: i), ["YES", "NO", "1", "0", "true", "false"].contains(v) {
                    o.resetState = ["YES", "1", "true"].contains(v)
                    i += 1
                }
            case "-PMA11y":
                if let v = value(after: i), !v.hasPrefix("-") {
                    o.accessibility = AccessibilityPreferences.parse(list: v)
                    i += 1
                }
            case "-PMTips":
                if let v = value(after: i), !v.hasPrefix("-") {
                    o.tips = TipsLaunchMode(rawValue: v)
                    i += 1
                }
            case "-PMWindowSize":
                if let v = value(after: i), !v.hasPrefix("-") {
                    o.windowSize = LaunchWindowSize(rawValue: v)
                    i += 1
                }
            case "-PMWindowPoints":
                if let v = value(after: i), !v.hasPrefix("-") {
                    let parts = v.lowercased().split(separator: "x").compactMap { Double($0) }
                    if parts.count == 2, parts[0] >= 200, parts[1] >= 200 { o.windowPoints = CGSize(width: parts[0], height: parts[1]) }
                    i += 1
                }
            case "-PMAppearance":
                if let v = value(after: i), !v.hasPrefix("-") {
                    o.appearance = LaunchAppearance(rawValue: v)
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
