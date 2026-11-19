// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecArt
import ParsecEngine
import ParsecInsights

/// UI-ENC-017: the badge word and its vector glyph (ART-033).
struct EncounterBadgeModel: Equatable, Sendable {
    var badge: EncounterBadge

    var word: String {
        switch badge {
        case .pirate: String(localized: "Pirate")
        case .police: String(localized: "Police")
        case .trader: String(localized: "Trader")
        case .alien: String(localized: "Alien")
        case .special: String(localized: "Special")
        }
    }

    /// ART-033: the drawn badge glyph.
    var glyph: EncounterBadgeKind { ArtAdapters.badge(badge) }

    /// Special encounters get the gold capsule.
    var isSpecial: Bool { badge == .special }
}

/// UI-ENC-019: one hull or shield bar.
struct EncounterBarModel: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case hull, shields }

    var kind: Kind
    /// Nil for a ship without shields ("No shields").
    var percent: Int?

    var text: String {
        switch kind {
        case .hull: String(localized: "Hull \(percent ?? 0)%")
        case .shields: percent.map { String(localized: "Shields \($0)%") } ?? String(localized: "No shields")
        }
    }

    /// The accessibility value "N%".
    var value: String { "\(percent ?? 0)%" }
    var fraction: Double { Double(min(100, max(0, percent ?? 0))) / 100 }
    /// A hull at 25% or below adds a warning symbol to the red tint.
    var isCritical: Bool { kind == .hull && (percent ?? 0) <= 25 }
}

/// UI-ENC-018/020: a ship pane (title, portrait, bars, accessibility label).
struct ShipPaneModel: Equatable, Sendable {
    enum Facing: Equatable, Sendable { case right, left }

    var title: String
    var shipType: ShipType
    var size: SystemSize
    var facing: Facing
    var hull: EncounterBarModel
    var shields: EncounterBarModel
    var isDisabled: Bool
    var accessibilityLabel: String
    /// UI-ENC-098, ART-008: the portrait input (phase and accessibility are applied by the view).
    var art: ShipArtInput

    static func player(state: GameState, preview: EncounterPreview, cloaked: Bool = false) -> ShipPaneModel {
        let ship = state.commander.ship
        let type = String(localized: Names.ship(ship.type))
        let name = state.commander.shipName.flatMap { $0.isEmpty ? nil : $0 }
        let title = name.map { String(localized: "You: \(type) “\($0)”") } ?? String(localized: "You: \(type)")
        let hull = EncounterBarModel(kind: .hull, percent: preview.playerHullPercent)
        let shields = EncounterBarModel(kind: .shields, percent: ship.shields.isEmpty ? nil : preview.playerShieldPercent)
        // A11Y-009: the portrait label comes from its ArtSurface.
        let label = ArtSurface.playerPortrait(ship: type, hull: hull.percent ?? 0, shields: shields.percent).label ?? ""
        return ShipPaneModel(title: title, shipType: ship.type, size: ship.spec(state.ruleset).size, facing: .right, hull: hull,
                             shields: shields, isDisabled: false, accessibilityLabel: label,
                             art: ArtAdapters.playerShipInput(state, facing: .right, cloaked: cloaked))
    }

    static func opponent(state: GameState, preview: EncounterPreview) -> ShipPaneModel? {
        guard case let .encounter(enc) = state.phase else { return nil }
        let type = String(localized: Names.ship(enc.opponent.type))
        let hull = EncounterBarModel(kind: .hull, percent: preview.opponentHullPercent)
        let shields = EncounterBarModel(kind: .shields, percent: enc.opponent.shields.isEmpty ? nil : preview.opponentShieldPercent)
        let word = EncounterBadgeModel(badge: preview.badge).word
        var label = ArtSurface.opponentPortrait(kind: word, ship: type, hull: hull.percent ?? 0, shields: shields.percent).label ?? ""
        if enc.opponentDisabled { label += String(localized: ", disabled") }
        return ShipPaneModel(title: String(localized: "Opponent: \(type)"), shipType: enc.opponent.type,
                             size: enc.opponent.spec(state.ruleset).size, facing: .left, hull: hull, shields: shields,
                             isDisabled: enc.opponentDisabled, accessibilityLabel: label,
                             art: ArtAdapters.opponentShipInput(state, encounter: enc))
    }
}

/// UI-ENC-026: tribble sprites scattered over the ship area, positioned by an app-side hash (never the game RNG).
enum TribbleLayout {
    /// The ENC-087 count: `min(36, ⌊√(tribbles / 74)⌋)`.
    static func count(tribbles: Int) -> Int {
        guard tribbles > 0 else { return 0 }
        return min(36, Int((Double(tribbles) / 74).squareRoot()))
    }

    /// Unit positions (0…1 on both axes) for `count` tribbles, stable for the same inputs.
    static func positions(seed: UInt64, days: Int, clicks: Int, count: Int) -> [UnitPoint2D] {
        (0..<count).map { index in
            var h = splitMix(seed ^ splitMix(UInt64(bitPattern: Int64(days)) &* 31 &+ UInt64(bitPattern: Int64(clicks))))
            h = splitMix(h ^ UInt64(index))
            let x = Double(h & 0xFFFF) / Double(0xFFFF)
            let y = Double((h >> 16) & 0xFFFF) / Double(0xFFFF)
            return UnitPoint2D(x: 0.05 + 0.9 * x, y: 0.1 + 0.8 * y)
        }
    }

    static func splitMix(_ v: UInt64) -> UInt64 {
        var z = v &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A unit-square point (kept free of CoreGraphics so the layout stays a plain value).
struct UnitPoint2D: Equatable, Sendable {
    var x: Double
    var y: Double
}

/// INT-039: how often this ship type was met before and how many of those encounters were won (journal only; it
/// reveals nothing hidden).
struct MetBefore: Equatable, Sendable {
    var met: Int
    var won: Int

    static func make(opponent: ShipType, journal: GameJournal?) -> MetBefore {
        var m = MetBefore(met: 0, won: 0)
        for e in journal?.entries ?? [] {
            guard case let .encounter(record) = e.kind, record.opponent == opponent else { continue }
            m.met += 1
            if record.result == .won { m.won += 1 }
        }
        return m
    }
}

/// UI-ENC-042: the tactical readout's text over `GameEngine.tacticalReadout`.
enum TacticalText {
    /// "Gnat (Small)".
    static func shipClass(_ readout: TacticalReadout, ruleset: Ruleset) -> String {
        let size = ruleset.tables.ship(readout.opponentType).size
        return String(localized: "\(String(localized: Names.ship(readout.opponentType))) (\(String(localized: Names.size(size))))")
    }

    /// "2 × Pulse laser, Energy shield", or "Unarmed" (plus any shields).
    static func equipment(_ readout: TacticalReadout) -> String {
        var parts = grouped(readout.weapons).map { w, n in counted(String(localized: Names.weapon(w)), n) }
        if parts.isEmpty { parts.append(String(localized: "Unarmed")) }
        parts += grouped(readout.shields).map { s, n in counted(String(localized: Names.shield(s)), n) }
        return parts.joined(separator: ", ")
    }

    /// "Good", "Fair" or "Poor"; nil when Flee is not offered.
    static func fleeOdds(_ readout: TacticalReadout) -> String? {
        readout.fleeOdds.map { odds in
            switch odds {
            case .good: String(localized: "Good")
            case .fair: String(localized: "Fair")
            case .poor: String(localized: "Poor")
            }
        }
    }

    /// INT-039: "Met before: N times, won M" for the opponent's ship type, from the journal's encounter records (nil
    /// when never met).
    static func metBefore(_ record: MetBefore?) -> String? {
        guard let record, record.met > 0 else { return nil }
        return String(localized: "Met before: \(record.met) times, won \(record.won)")
    }

    private static func counted(_ name: String, _ n: Int) -> String { n > 1 ? "\(n) × \(name)" : name }

    /// Counts per value, in first-seen (slot) order.
    private static func grouped<T: Equatable>(_ values: [T]) -> [(T, Int)] {
        var out: [(T, Int)] = []
        for v in values {
            if let i = out.firstIndex(where: { $0.0 == v }) { out[i].1 += 1 } else { out.append((v, 1)) }
        }
        return out
    }
}

/// UI-ENC-027, -029, -031…033: the action bar's buttons.
struct EncounterActionBarModel: Equatable, Sendable {
    struct Button: Equatable, Sendable {
        var action: EncounterAction
        var label: String
        var keyCap: String?
        var help: String
        var isEnabled: Bool
        /// Only the enabled default action carries Return (UI-ENC-029).
        var isDefault: Bool
    }

    var buttons: [Button]
    var resolve: Button?
    var stop: Button
    var autoRepeatAvailable: Bool
    var autoRepeatHelp: String

    static func make(preview: EncounterPreview, menu: EncounterMenuState, inputLocked: Bool) -> EncounterActionBarModel {
        let buttons = preview.actions.map { p in
            button(p.action, label: String(localized: Names.encounterAction(p.action)), rejection: p.rejection,
                   isDefault: p.action == preview.defaultAction, inputLocked: inputLocked)
        }
        let resolve = menu.resolveShown
            ? button(.resolve, label: String(localized: "Resolve"), rejection: menu.resolveRejection, isDefault: false,
                     inputLocked: inputLocked, help: String(localized: "Attack until the encounter is resolved (R)"))
            : nil
        let stop = button(.stop, label: String(localized: "Stop"), rejection: menu.canStop ? nil : .encounterActionUnavailable,
                          isDefault: false, inputLocked: inputLocked)
        let autoHelp = menu.autoRepeatAvailable ? String(localized: "Repeat the last action every 0.6 seconds (⌥A)")
            : String(localized: "Turn on Continuous attack in Game › Options…, or use Resolve.")
        return EncounterActionBarModel(buttons: buttons, resolve: resolve, stop: stop,
                                       autoRepeatAvailable: menu.autoRepeatAvailable && !inputLocked, autoRepeatHelp: autoHelp)
    }

    private static func button(_ action: EncounterAction, label: String, rejection: CommandError?, isDefault: Bool,
                               inputLocked: Bool, help: String? = nil) -> Button {
        let cap = EncounterKeys.keyCap(for: action)
        let tag = rejection.map(ReasonText.string(for:)) ?? help ?? cap.map { String(localized: "\(label) (\($0))") } ?? label
        let enabled = rejection == nil && !inputLocked
        return Button(action: action, label: label, keyCap: cap, help: tag, isEnabled: enabled, isDefault: isDefault && enabled)
    }
}
