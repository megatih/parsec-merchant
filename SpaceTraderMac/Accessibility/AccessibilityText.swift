// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import ParsecPersistence

/// Accessibility values (A11Y-004). Pure; each row of the spec table is a function.
enum AccessibilityText {
    /// Hull and shield bars: "78 percent".
    static func percent(_ value: Int) -> String { String(localized: "\(value) percent") }
    /// A shield bar without shields.
    static var noShields: String { String(localized: "No shields") }
    /// Status bar fuel and bays: "11 of 14".
    static func of(_ value: Int, _ total: Int) -> String { String(localized: "\(value) of \(total)") }
    /// Quest deadline gauges: "3 days left" / "due tomorrow" / "due today".
    static func deadline(daysLeft: Int) -> String {
        switch daysLeft {
        case ...0: String(localized: "due today")
        case 1: String(localized: "due tomorrow")
        default: String(localized: "\(daysLeft) days left")
        }
    }
    /// Transit progress: "Click N of 20" (UI-ENC-008).
    static func transitClick(_ click: Int, of total: Int = 20) -> String { String(localized: "Click \(click) of \(total)") }
    /// Market quantity field and steppers: "5 units".
    static func units(_ n: Int) -> String { n == 1 ? String(localized: "1 unit") : String(localized: "\(n) units") }
    /// Bridge fuel slider: "6 units, 120 credits".
    static func fuelSlider(units: Int, credits: Int) -> String {
        String(localized: "\(self.units(units)), \(credits) credits")
    }
    /// Bridge repair slider: "40 hull points, 200 credits".
    static func repairSlider(points: Int, credits: Int) -> String {
        String(localized: "\(points) hull points, \(credits) credits")
    }
    /// The Text Size picker: the selected size's title.
    static func textSize(_ setting: TextSizeSetting) -> String { String(localized: setting.title) }
    /// Sidebar badges.
    static var bridgeSpecialBadge: String { String(localized: "Special offer here") }
    static func crewBadge(mercenaries: Int) -> String {
        mercenaries == 1 ? String(localized: "1 mercenary for hire") : String(localized: "\(mercenaries) mercenaries for hire")
    }
    static var bankDebtBadge: String { String(localized: "Debt warning") }
    /// "Pilot 5, Fighter 3, Trader 7, Engineer 2".
    static func skills(_ skills: [Int]) -> String {
        zip(SkillType.allCases, skills).map { "\(String(localized: Names.skill($0))) \($1)" }.joined(separator: ", ")
    }
}

/// Hints on elements whose behaviour is not obvious from the label (A11Y-005).
enum AccessibilityHints {
    /// Market `+`/`−`.
    static var tradeModifiers: String { String(localized: "Shift for 5, Command for 20, Shift-Command for 100, Option for all") }
    /// `toolbar.warp` and `bridge.target.warp`.
    static func warp(to target: String) -> String { String(localized: "Warps to \(target). Warping can't be undone.") }
    /// Resolve.
    static var resolve: String { String(localized: "Attacks until the encounter is resolved") }
    /// Fill Up and Repair.
    static var fillUp: String { String(localized: "Buys as much as you can afford") }
}

/// One custom action of a compound row (A11Y-007).
nonisolated struct RowAction: Equatable, Sendable, Identifiable {
    enum Kind: String, Sendable {
        case buyOne, sellOne, buyMax, sellAll, whyThisPrice, buy, compare, hire, fire, open, delete
    }

    var kind: Kind
    var name: String
    var id: Kind { kind }
}

/// A compound row read as one element (A11Y-007).
nonisolated struct RowAccessibility: Equatable, Sendable {
    var label: String
    var value: String
    var actions: [RowAction]
}

/// Market row: label "<Item>", value "Buy p credits, sell q credits, held n, target t credits (estimate)".
enum MarketRowAccessibility {
    static func make(_ row: MarketRowModel, target: Int? = nil) -> RowAccessibility {
        var parts: [String] = []
        if let p = row.buyPrice { parts.append(String(localized: "Buy \(p) credits")) }
        if let q = row.sellPrice { parts.append(String(localized: "sell \(q) credits")) }
        parts.append(String(localized: "held \(row.row.held)"))
        if let t = target ?? row.target?.price { parts.append(String(localized: "target \(t) credits (estimate)")) }
        var value = parts.joined(separator: ", ")
        if let first = value.first { value = first.uppercased() + value.dropFirst() }
        let actions = [
            RowAction(kind: .buyOne, name: String(localized: "Buy 1")),
            RowAction(kind: .sellOne, name: String(localized: "Sell 1")),
            RowAction(kind: .buyMax, name: String(localized: "Buy Max")),
            RowAction(kind: .sellAll, name: String(localized: "Sell All")),
            RowAction(kind: .whyThisPrice, name: String(localized: "Why This Price")),
        ]
        return RowAccessibility(label: String(localized: Names.item(row.item)), value: value, actions: actions)
    }

    /// The command of a trade action (nil for Why This Price, or when the trade is not possible).
    static func command(_ kind: RowAction.Kind, row: MarketRowModel) -> Command? {
        switch kind {
        case .buyOne: row.buyCommand(requested: 1)
        case .sellOne: row.sellCommand(requested: 1)
        case .buyMax: row.buyMaxCommand
        case .sellAll: row.sellAllCommand
        default: nil
        }
    }
}

/// Ship card: label "<Ship type>", value price and "current ship", actions Buy and Compare.
enum ShipCardAccessibility {
    static func make(_ card: ShipCardModel) -> RowAccessibility {
        var value: String
        switch card.price {
        case let .pay(n)?: value = String(localized: "Costs \(n) credits")
        case let .receive(n)?: value = String(localized: "You get \(n) credits")
        case nil: value = ""
        }
        if card.isYours { value = value.isEmpty ? String(localized: "Current ship") : value + ", " + String(localized: "current ship") }
        let actions = card.isYours ? [RowAction(kind: .compare, name: String(localized: "Compare"))]
            : [RowAction(kind: .buy, name: String(localized: "Buy")), RowAction(kind: .compare, name: String(localized: "Compare"))]
        return RowAccessibility(label: String(localized: Names.ship(card.type)), value: value, actions: actions)
    }
}

/// Crew and mercenary rows: name, skills, daily cost, Hire or Fire.
enum CrewRowAccessibility {
    static func make(name: String, skills: [Int], dailyWage: Int?, action: RowAction.Kind?) -> RowAccessibility {
        var parts = [AccessibilityText.skills(skills)]
        if let dailyWage { parts.append(String(localized: "\(dailyWage) credits per day")) }
        let actions: [RowAction] = switch action {
        case .hire?: [RowAction(kind: .hire, name: String(localized: "Hire"))]
        case .fire?: [RowAction(kind: .fire, name: String(localized: "Fire"))]
        default: []
        }
        return RowAccessibility(label: name, value: parts.joined(separator: ", "), actions: actions)
    }

    static func make(_ seat: CrewModel.Seat) -> RowAccessibility? {
        switch seat.occupant {
        case let .commander(name, skills): make(name: name, skills: skills, dailyWage: nil, action: nil)
        case let .mercenary(_, name, skills, wage): make(name: name, skills: skills, dailyWage: wage, action: .fire)
        case let .passenger(_, name): RowAccessibility(label: name, value: String(localized: "Passenger"),
                                                       actions: [RowAction(kind: .fire, name: String(localized: "Fire"))])
        case .vacant: nil
        }
    }

    static func make(_ card: CrewModel.HireCard) -> RowAccessibility {
        make(name: card.name, skills: card.skills, dailyWage: card.dailyWage, action: .hire)
    }
}

/// Save-slot rows: the SAV-042 fields as one sentence, actions Open and Delete.
enum SaveSlotAccessibility {
    static func make(_ slot: SlotInfo) -> RowAccessibility {
        let s = slot.summary
        let ruleset = String(localized: Names.ruleset(slot.rulesetID))
        var sentence = String(localized: "\(s.commander), day \(s.day) at \(SlotText.systemName(slot)), worth \(s.worth) credits, \(ruleset) rules.")
        if s.ironman { sentence += " " + String(localized: "Ironman.") }
        if s.cheatsUsed { sentence += " " + String(localized: "Cheats used.") }
        if s.ended { sentence += " " + String(localized: "Ended.") }
        if slot.isAutosave { sentence += " " + String(localized: "Autosave.") }
        return RowAccessibility(label: sentence, value: "",
                                actions: [RowAction(kind: .open, name: String(localized: "Open")),
                                          RowAction(kind: .delete, name: String(localized: "Delete"))])
    }
}

/// High-score rows: rank, name, outcome and score, with Ironman and ↺ read as words.
enum HighScoreRowAccessibility {
    static func make(_ row: HighScoreRow) -> RowAccessibility {
        guard let e = row.entry else {
            return RowAccessibility(label: String(localized: "Rank \(row.rank), empty"), value: "", actions: [])
        }
        var label = String(localized: "Rank \(row.rank), \(e.name), score \(e.scoreText).")
        if e.ironman { label += " " + String(localized: "Ironman.") }
        if e.reloaded { label += " " + String(localized: "Reloaded.") }
        return RowAccessibility(label: label, value: e.line, actions: [])
    }
}
