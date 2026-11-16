// SPDX-License-Identifier: GPL-2.0-or-later
// Ruleset switches for quest chains and special events (RUL-006, -037, -111, -115, -141…143, -171…173 and the QST
// {M5} flags). docs/specs/RUL.md is normative.

/// When the moon offer appears (RUL-142).
public enum MoonOfferThreshold: String, Codable, Sendable {
    /// C#: worth > 4/5 of the moon's cost.
    case aboveFourFifths
    /// Palm: worth ≥ 4/5 of the moon's cost.
    case atLeastFourFifths
}

/// When a special event's price is charged (RUL-143).
public enum SpecialEventPriceTiming: String, Codable, Sendable {
    /// C#: after the effect; an early refusal charges nothing.
    case afterEffect
    /// Palm: before the effect and before any refusal check; a refusal keeps the charge.
    case beforeEffect
}

/// The police record after Wild is delivered (RUL-037).
public enum WildDeliveredRecordRule: String, Codable, Sendable {
    /// C#: the record becomes exactly 0 (a hero drops to 0).
    case resetToZero
    /// Palm: the record becomes max(record, 0).
    case raiseToZero
}

/// When Erase Record and Wild's delivery multiply sell prices by 100/90 (RUL-115, MOD-015).
public enum SellPriceRecalcRule: String, Codable, Sendable {
    /// Windows 2.01: always, after both events.
    case always
    /// Modern: only if the record was below −5 before the event.
    case onlyIfCriminal
    /// Palm: always after Erase Record, never after Wild's delivery.
    case eraseRecordOnly
}

/// How damage to the quest ships carries over between meetings (RUL-173, ENC-012/013).
public enum SpecialShipDamageRule: String, Codable, Sendable {
    /// C#: the encounter fights the shared ship, so every change persists.
    case allShips
    /// Palm: a copy is fought; only the Space Monster's hull is written back, and only when the player escapes.
    case monsterHullOnEscape
}

/// Quest behaviour switches. Each case of every switch is selected by the ruleset presets below; engine code reads
/// these values and never branches on the ruleset id.
public struct QuestRules: Sendable, Equatable {
    /// RUL-141: hide the 11 quest starts while more than this many quests are open (nil: never hide).
    public var openQuestCap: Int?
    /// RUL-142.
    public var moonOfferThreshold: MoonOfferThreshold = .aboveFourFifths
    /// RUL-143.
    public var specialEventPriceTiming: SpecialEventPriceTiming = .afterEffect
    /// RUL-171: the Japori pickup stays after acceptance, so a failed delivery can be restarted.
    public var japoriPickupPersists = true
    /// RUL-172: installing the Gemulon fuel compactor fills the tank to the new capacity.
    public var gemulonRewardRefuels = false
    /// RUL-006: retiring to the moon after the Princess quest ends with `.boughtMoonGirl`.
    public var moonGirlEnding = false
    /// RUL-037.
    public var wildDeliveredRecord: WildDeliveredRecordRule = .resetToZero
    /// RUL-115.
    public var sellPriceRecalc: SellPriceRecalcRule = .always
    /// RUL-111: Wild boards and stays only with a Beam, Military or Morgan's laser (C#: Beam or any higher enum).
    public var wildRequiresRealLaser = false
    /// RUL-173.
    public var specialShipDamagePersists: SpecialShipDamageRule = .allShips

    /// Windows 2.01 (faithful C# port).
    public static let windows201 = QuestRules()

    /// Modern: Windows 2.01 with the PRD §4.3 fixes in this area.
    public static let modern: QuestRules = {
        var q = QuestRules()
        q.moonGirlEnding = true
        q.sellPriceRecalc = .onlyIfCriminal
        q.wildRequiresRealLaser = true
        return q
    }()

    /// Original Palm 1.2.2.
    public static let palm122: QuestRules = {
        var q = QuestRules()
        q.openQuestCap = 3
        q.moonOfferThreshold = .atLeastFourFifths
        q.specialEventPriceTiming = .beforeEffect
        q.japoriPickupPersists = false
        q.gemulonRewardRefuels = true
        q.wildDeliveredRecord = .raiseToZero
        q.sellPriceRecalc = .eraseRecordOnly
        q.wildRequiresRealLaser = true
        q.specialShipDamagePersists = .monsterHullOnEscape
        return q
    }()
}
