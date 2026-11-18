// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine

/// Identifiers of the Shipyard (⌘3), the purchase review sheet, the Designer and the Outfitter (⌘4) (UI-SHELL §18).
nonisolated extension AXID {
    enum Shipyard {
        static func ship(_ t: ShipType) -> String { "shipyard.ship.\(t)" }
        static func buy(_ t: ShipType) -> String { "shipyard.ship.\(t).buy" }
        static func compareToggle(_ t: ShipType) -> String { "shipyard.ship.\(t).compare" }
        static let ships = "shipyard.ships"
        static let designer = "shipyard.designer"
        static let compare = "shipyard.compare"
        static let compareClear = "shipyard.compare.clear"
        static let escapePodBuy = "shipyard.escapePod.buy"
        static let insuranceBank = "shipyard.insurance.bank"
        static let all: [String] = [ships, designer, compare, compareClear, escapePodBuy, insuranceBank]
            + ShipType.allCases.flatMap { [ship($0), buy($0), compareToggle($0)] }
    }

    enum ShipPurchase {
        static let sheet = "shipPurchase.sheet"
        static func transfer(_ item: TransferItem) -> String { "shipPurchase.transfer.\(item.rawValue)" }
        static let buy = "shipPurchase.buy"
        static let cancel = "shipPurchase.cancel"
        static let all: [String] = [sheet, buy, cancel] + TransferItem.allCases.map(transfer)
    }

    /// `designer.*` (named `ShipDesigner` so it does not shadow the engine's `Designer`).
    enum ShipDesigner {
        static let root = "designer.root"
        static let name = "designer.name"
        static let size = "designer.size"
        static let silhouette = "designer.silhouette"
        static func increment(_ f: DesignerField) -> String { "designer.\(f.rawValue).increment" }
        static func decrement(_ f: DesignerField) -> String { "designer.\(f.rawValue).decrement" }
        static func value(_ f: DesignerField) -> String { "designer.\(f.rawValue).value" }
        static let units = "designer.units"
        static let construct = "designer.construct"
        static let template = "designer.template"
        static let saveTemplate = "designer.saveTemplate"
        static let all: [String] = [root, name, size, silhouette, units, construct, template, saveTemplate]
            + DesignerField.allCases.flatMap { [increment($0), decrement($0), value($0)] }
    }

    enum Outfitter {
        static func group(_ g: OutfitterGroup) -> String { "outfitter.group.\(g.rawValue)" }
        static func buy(_ item: EquipmentItem) -> String { "outfitter.buy.\(item.caseName)" }
        static func sell(_ g: OutfitterGroup, slot: Int) -> String { "outfitter.sell.\(g.rawValue).\(slot)" }
        static func offer(_ item: EquipmentItem) -> String { "outfitter.offer.\(item.caseName)" }
        static func slot(_ g: OutfitterGroup, slot: Int) -> String { "outfitter.slot.\(g.rawValue).\(slot)" }
        static let detail = "outfitter.detail"
        static let sellWell = "outfitter.sellWell"
        static let all: [String] = [detail, sellWell] + OutfitterGroup.allCases.map(group)
            + EquipmentItem.catalog.flatMap { [buy($0), offer($0)] }
            + OutfitterGroup.allCases.flatMap { g in (0..<OutfitterGroup.maxSlots).flatMap { [sell(g, slot: $0), slot(g, slot: $0)] } }
    }

    /// Everything this area adds to `AXID.all`.
    static var shipyardArea: [String] { Shipyard.all + ShipPurchase.all + ShipDesigner.all + Outfitter.all }
}
