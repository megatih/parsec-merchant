// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine

/// The identifiers of the Bridge (UI-BRG-031): `bridge.‹region›.‹element›[.‹good›]`.
nonisolated enum BridgeID {
    static let root = "bridge.root"

    // The four regions.
    static let system = "bridge.system"
    static let cargo = "bridge.cargo"
    static let chart = "bridge.chart"
    static let target = "bridge.target"

    /// Region A.
    enum System {
        static let planet = "bridge.system.planet"
        static let name = "bridge.system.name"
        static let size = "bridge.system.size"
        static let tech = "bridge.system.tech"
        static let government = "bridge.system.government"
        static let resources = "bridge.system.resources"
        static let status = "bridge.system.status"
        static let police = "bridge.system.police"
        static let pirates = "bridge.system.pirates"
        static let fuel = "bridge.system.fuel"
        static let hull = "bridge.system.hull"
        static let fillTank = "bridge.system.fillTank"
        static let repairHull = "bridge.system.repairHull"
        static let news = "bridge.system.news"
        static let special = "bridge.system.special"
        static let hire = "bridge.system.hire"
        static let quest = "bridge.system.quest"

        static let facts = [name, size, tech, government, resources, status, police, pirates]
        static let gauges = [fuel, hull]
        static let services = [fillTank, repairHull]
        static let notices = [news, special, hire, quest]
        static let all = [planet] + facts + gauges + services + notices
    }

    /// Region B.
    enum Cargo {
        static let bays = "bridge.cargo.summary.bays"
        static let hold = "bridge.cargo.summary.hold"
        static let sellAll = "bridge.cargo.sellAll"
        static let header = "bridge.cargo.header"
        static let rows = "bridge.cargo.rows"

        static func row(_ item: TradeItemType) -> String { "bridge.cargo.row.\(item)" }
        static func good(_ item: TradeItemType) -> String { "bridge.cargo.good.\(item)" }
        static func hold(_ item: TradeItemType) -> String { "bridge.cargo.hold.\(item)" }
        static func paid(_ item: TradeItemType) -> String { "bridge.cargo.paid.\(item)" }
        static func sellPrice(_ item: TradeItemType) -> String { "bridge.cargo.sellPrice.\(item)" }
        static func buyPrice(_ item: TradeItemType) -> String { "bridge.cargo.buyPrice.\(item)" }
        static func stock(_ item: TradeItemType) -> String { "bridge.cargo.stock.\(item)" }
        static func target(_ item: TradeItemType) -> String { "bridge.cargo.target.\(item)" }
        static func delta(_ item: TradeItemType) -> String { "bridge.cargo.delta.\(item)" }
        static func quantity(_ item: TradeItemType) -> String { "bridge.cargo.quantity.\(item)" }
        static func buy(_ item: TradeItemType) -> String { "bridge.cargo.buy.\(item)" }
        static func max(_ item: TradeItemType) -> String { "bridge.cargo.max.\(item)" }
        static func sell(_ item: TradeItemType) -> String { "bridge.cargo.sell.\(item)" }
        static func all(_ item: TradeItemType) -> String { "bridge.cargo.all.\(item)" }

        /// The nine cells of a row (the row itself and its eight values).
        static func cells(_ item: TradeItemType) -> [String] {
            [row(item), good(item), hold(item), paid(item), sellPrice(item), buyPrice(item), stock(item), target(item), delta(item)]
        }

        /// The five controls of a row, left to right.
        static func controls(_ item: TradeItemType) -> [String] {
            [quantity(item), buy(item), max(item), sell(item), all(item)]
        }

        static let summary = [bays, hold, sellAll]
        static var all: [String] { summary + TradeItemType.allCases.flatMap { cells($0) + controls($0) } }
    }

    /// Region C.
    enum Chart {
        static let map = "bridge.miniChart.map"
        static let open = "bridge.chart.open"
        static let all = [map, open]
    }

    /// Region D.
    enum Target {
        static let name = "bridge.target.name"
        static let distance = "bridge.target.distance"
        static let badge = "bridge.target.badge"
        static let note = "bridge.target.note"
        static let size = "bridge.target.size"
        static let tech = "bridge.target.tech"
        static let government = "bridge.target.government"
        static let resources = "bridge.target.resources"
        static let police = "bridge.target.police"
        static let pirates = "bridge.target.pirates"
        static let mercenaries = "bridge.target.cost.mercenaries"
        static let insurance = "bridge.target.cost.insurance"
        static let interest = "bridge.target.cost.interest"
        static let wormholeTax = "bridge.target.cost.wormholeTax"
        static let total = "bridge.target.cost.total"
        static let fuelAfter = "bridge.target.fuelAfter"
        static let warp = "bridge.target.warp"
        static let previous = "bridge.target.previous"
        static let next = "bridge.target.next"
        static let track = "bridge.target.track"
        static let find = "bridge.target.find"
        /// Shown only while the portable singularity is aboard, so it is not in the manifest.
        static let jump = "bridge.target.jump"

        static let facts = [size, tech, government, resources, police, pirates]
        static let costs = [mercenaries, insurance, interest, wormholeTax, total]
        static let buttons = [warp, previous, next, track, find]
        static let all = [name, distance, badge, note] + facts + costs + [fuelAfter] + buttons
    }
}

/// UI-BRG-031: every element the Bridge shows at every window size, in every ruleset and state.
nonisolated enum BridgeManifest {
    static let regions = [BridgeID.system, BridgeID.cargo, BridgeID.chart, BridgeID.target]
    static var all: [String] { regions + BridgeID.System.all + BridgeID.Cargo.all + BridgeID.Chart.all + BridgeID.Target.all }

    /// The elements that take clicks or typing: each needs a 36 pt target (UI-BRG-032, assertion 6).
    static var controls: [String] {
        BridgeID.System.services + BridgeID.System.notices + [BridgeID.Cargo.sellAll] + TradeItemType.allCases.flatMap(BridgeID.Cargo.controls)
            + [BridgeID.Chart.open] + BridgeID.Target.buttons
    }

    /// The region an element lies in.
    static func region(of identifier: String) -> String? {
        if identifier == BridgeID.Chart.map { return BridgeID.chart }
        return regions.first { identifier.hasPrefix($0 + ".") }
    }
}
