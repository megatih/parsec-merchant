// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// The Game › Options sheet model (UI-SHELL-099, OPT-025…027). Pure; the sheet only renders it.
nonisolated struct OptionsDraft: Equatable, Sendable {
    /// The sheet's controls, in the C# dialog's group order (OPT-025). Raw values are the identifier suffixes.
    enum Field: String, CaseIterable, Sendable {
        case autoFuel, autoRepair
        case newsAutoPay, newsAutoShow
        case showTrackedRange, trackAutoOff
        case remindLoans, reserveMoney, leaveEmpty
        case alwaysIgnorePirates, alwaysIgnorePolice, alwaysIgnoreTraders, alwaysIgnoreTradeInOrbit
        case continuousAttack, continuousAttackFleeing, disableOpponents

        var keyPath: WritableKeyPath<GameOptions, Bool>? {
            switch self {
            case .autoFuel: \.autoFuel
            case .autoRepair: \.autoRepair
            case .newsAutoPay: \.newsAutoPay
            case .newsAutoShow: \.newsAutoShow
            case .showTrackedRange: \.showTrackedRange
            case .trackAutoOff: \.trackAutoOff
            case .remindLoans: \.remindLoans
            case .reserveMoney: \.reserveMoney
            case .leaveEmpty: nil
            case .alwaysIgnorePirates: \.alwaysIgnorePirates
            case .alwaysIgnorePolice: \.alwaysIgnorePolice
            case .alwaysIgnoreTraders: \.alwaysIgnoreTraders
            case .alwaysIgnoreTradeInOrbit: \.alwaysIgnoreTradeInOrbit
            case .continuousAttack: \.continuousAttack
            case .continuousAttackFleeing: \.continuousAttackFleeing
            case .disableOpponents: \.disableOpponents
            }
        }

        /// OPT-008: the parent a dependent control follows (Form_Options.cs:409-431).
        var parent: Field? {
            switch self {
            case .newsAutoShow: .newsAutoPay
            case .alwaysIgnoreTradeInOrbit: .alwaysIgnoreTraders
            case .continuousAttackFleeing: .continuousAttack
            default: nil
            }
        }
    }

    /// The groups of the sheet, in order (OPT-025).
    enum Group: CaseIterable, Sendable {
        case arrival, newspaper, tracking, money, ignore, combat

        var fields: [Field] {
            switch self {
            case .arrival: [.autoFuel, .autoRepair]
            case .newspaper: [.newsAutoPay, .newsAutoShow]
            case .tracking: [.showTrackedRange, .trackAutoOff]
            case .money: [.remindLoans, .reserveMoney, .leaveEmpty]
            case .ignore: [.alwaysIgnorePirates, .alwaysIgnorePolice, .alwaysIgnoreTraders, .alwaysIgnoreTradeInOrbit]
            case .combat: [.continuousAttack, .continuousAttackFleeing, .disableOpponents]
            }
        }
    }

    static let leaveEmptyRange = 0...99

    let rulesetID: RulesetID
    private(set) var options: GameOptions

    init(options: GameOptions, ruleset: RulesetID) {
        rulesetID = ruleset
        self.options = options.normalized(for: Ruleset.named(ruleset))
    }

    private var ruleset: Ruleset { Ruleset.named(rulesetID) }

    /// OPT-009: controls that do not exist in the ruleset are hidden (Palm: news auto-show and disable opponents).
    func isVisible(_ f: Field) -> Bool {
        switch f {
        case .newsAutoShow: ruleset.flags.travel.newsAutoShowAvailable
        case .disableOpponents: ruleset.content.hasDisruptors
        default: true
        }
    }

    /// OPT-008/026: in rulesets with option dependencies a dependent control is disabled while its parent is off.
    func isEnabled(_ f: Field) -> Bool {
        guard isVisible(f) else { return false }
        guard ruleset.flags.optionDependencies, let parent = f.parent else { return true }
        return value(parent)
    }

    func value(_ f: Field) -> Bool {
        guard let kp = f.keyPath else { return options.leaveEmpty > 0 }
        return options[keyPath: kp]
    }

    var leaveEmpty: Int { options.leaveEmpty }

    /// Sets a checkbox; dependents of a parent turned off are shown off at once (OPT-026).
    mutating func set(_ f: Field, _ on: Bool) {
        guard let kp = f.keyPath, isEnabled(f) else { return }
        options[keyPath: kp] = on
        options = options.normalized(for: ruleset)
    }

    mutating func setLeaveEmpty(_ n: Int) {
        options.leaveEmpty = min(Self.leaveEmptyRange.upperBound, max(Self.leaveEmptyRange.lowerBound, n))
    }

    /// OK: the command the sheet sends (the engine stores it normalized, OPT-007).
    func commit() -> Command { .setOptions(options) }

    /// OPT-027: Save as Defaults.
    @MainActor
    func saveAsDefaults(_ defaults: UserDefaults) {
        OptionsTemplate.save(options, for: rulesetID, defaults: defaults)
    }

    /// OPT-027: Load from Defaults (the stored template, else the ruleset's defaults).
    @MainActor
    mutating func loadDefaults(_ defaults: UserDefaults) {
        options = (OptionsTemplate.load(for: rulesetID, defaults: defaults) ?? GameOptions.defaults(for: rulesetID))
            .normalized(for: ruleset)
    }
}
