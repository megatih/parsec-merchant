// SPDX-License-Identifier: GPL-2.0-or-later
import CoreTransferable
import Foundation
import ParsecEngine
import UniformTypeIdentifiers

// Pure models of the Outfitter section (UI-SHELL-077/078), built from `GameState.equipmentMarket` (UI-SHELL-120).

nonisolated extension EquipmentItem {
    /// Every weapon, shield and gadget type (the identifier catalog expands over these).
    static var catalog: [EquipmentItem] {
        WeaponType.allCases.map(EquipmentItem.weapon) + ShieldType.allCases.map(EquipmentItem.shield)
            + GadgetType.allCases.map(EquipmentItem.gadget)
    }

    /// The engine case name, used in identifiers (`pulseLaser`, `energy`, `navigatingSystem`, …).
    var caseName: String {
        switch self {
        case let .weapon(w): "\(w)"
        case let .shield(s): "\(s)"
        case let .gadget(g): "\(g)"
        }
    }

    /// The command a Buy button sends (UI-SHELL-078).
    var buyCommand: Command {
        switch self {
        case let .weapon(w): .buyWeapon(w)
        case let .shield(s): .buyShield(s)
        case let .gadget(g): .buyGadget(g)
        }
    }

    var group: OutfitterGroup {
        switch self {
        case .weapon: .weapons
        case .shield: .shields
        case .gadget: .gadgets
        }
    }
}

nonisolated extension InstalledEquipment {
    /// The command a Sell button sends (UI-SHELL-078).
    var sellCommand: Command {
        switch item {
        case .weapon: .sellWeapon(index: slot)
        case .shield: .sellShield(index: slot)
        case .gadget: .sellGadget(index: slot)
        }
    }
}

/// The three Outfitter groups.
nonisolated enum OutfitterGroup: String, CaseIterable, Sendable {
    case weapons, shields, gadgets

    /// The most slots any ship has of one kind (designs allow 5).
    static let maxSlots = 5

    var title: LocalizedStringResource {
        switch self {
        case .weapons: "Weapons"
        case .shields: "Shields"
        case .gadgets: "Gadgets"
        }
    }

    func capacity(_ spec: ShipSpec) -> Int {
        switch self {
        case .weapons: spec.weaponSlots
        case .shields: spec.shieldSlots
        case .gadgets: spec.gadgetSlots
        }
    }
}

/// A slot tile: an installed item or a free slot.
nonisolated struct SlotTile: Identifiable, Equatable, Sendable {
    let slot: Int
    let installed: InstalledEquipment?
    /// Current charge of an installed shield.
    let charge: Int?
    var id: Int { slot }
}

nonisolated struct OutfitterGroupModel: Identifiable, Equatable, Sendable {
    let group: OutfitterGroup
    /// One tile per slot; empty when the ship has no slots of this kind ("No slots").
    let tiles: [SlotTile]
    /// Items sold here (buy price > 0), in table order. Unbuyable unique items appear only as installed tiles.
    let offers: [EquipmentOffer]
    var id: OutfitterGroup { group }
}

nonisolated struct OutfitterModel: Equatable, Sendable {
    let groups: [OutfitterGroupModel]

    /// UI-SHELL-039: "No equipment for sale here." when nothing is sold.
    var hasEquipmentForSale: Bool { groups.contains { !$0.offers.isEmpty } }

    static func make(state: GameState) -> OutfitterModel {
        let market = state.equipmentMarket
        let ship = state.commander.ship
        let spec = ship.spec(state.ruleset)
        let groups = OutfitterGroup.allCases.map { g in
            let installed = market.installed.filter { $0.item.group == g }
            let capacity = max(g.capacity(spec), installed.count)
            let tiles = (0..<capacity).map { slot in
                let item = installed.first { $0.slot == slot }
                let charge: Int? = g == .shields && ship.shields.indices.contains(slot) ? ship.shields[slot].charge : nil
                return SlotTile(slot: slot, installed: item, charge: item == nil ? nil : charge)
            }
            return OutfitterGroupModel(group: g, tiles: tiles,
                                       offers: market.offers.filter { $0.item.group == g && $0.buyPrice > 0 })
        }
        return OutfitterModel(groups: groups)
    }
}

/// What the detail pane shows (UI-SHELL-078).
nonisolated struct EquipmentDetail: Equatable, Sendable {
    /// How the item compares with what is installed.
    enum Comparison: Equatable, Sendable {
        /// Nothing of this kind is installed.
        case nothingInstalled
        /// Power difference against the strongest installed weapon or shield.
        case power(best: EquipmentItem, delta: Int)
        /// A gadget: how many of this type are installed.
        case owned(count: Int)
    }

    let item: EquipmentItem
    /// Weapon or shield power.
    let power: Int?
    /// The installed shield's current charge, when the selection is an installed shield.
    let charge: Int?
    let skillBonus: SkillType?
    /// Price here, nil when not sold here.
    let buyPrice: Int?
    /// `price × 3 / 4` (SHP-024).
    let sellPrice: Int
    let comparison: Comparison

    static func make(item: EquipmentItem, installedSlot: Int?, state: GameState) -> EquipmentDetail {
        let t = state.ruleset.tables
        let ship = state.commander.ship
        let price = state.equipmentBuyPrice(item)
        let power: Int?
        let comparison: Comparison
        var charge: Int?
        var bonus: SkillType?
        switch item {
        case let .weapon(w):
            power = t.weapon(w).power
            let best = ship.weapons.max { t.weapon($0).power < t.weapon($1).power }
            comparison = best.map { .power(best: .weapon($0), delta: t.weapon(w).power - t.weapon($0).power) } ?? .nothingInstalled
        case let .shield(s):
            power = t.shield(s).power
            let best = ship.shields.map(\.type).max { t.shield($0).power < t.shield($1).power }
            comparison = best.map { .power(best: .shield($0), delta: t.shield(s).power - t.shield($0).power) } ?? .nothingInstalled
            if let slot = installedSlot, ship.shields.indices.contains(slot) { charge = ship.shields[slot].charge }
        case let .gadget(g):
            power = nil
            bonus = t.gadget(g).skillBonus
            comparison = .owned(count: ship.count(g))
        }
        return EquipmentDetail(item: item, power: power, charge: charge, skillBonus: bonus, buyPrice: price > 0 ? price : nil,
                               sellPrice: state.equipmentSellPrice(item), comparison: comparison)
    }
}

/// The Outfitter's selection: an item for sale or an installed one.
nonisolated enum OutfitterSelection: Hashable, Sendable {
    case offer(EquipmentItem)
    case installed(EquipmentItem, slot: Int)

    var item: EquipmentItem {
        switch self {
        case let .offer(i), let .installed(i, _): i
        }
    }

    var slot: Int? {
        if case let .installed(_, slot) = self { return slot }
        return nil
    }
}

/// UI-PTR-010: what an Outfitter drag carries: an item for sale, or an installed item with its slot.
nonisolated struct OutfitterDragItem: Codable, Hashable, Sendable, Transferable {
    enum Source: Codable, Hashable, Sendable {
        case offer
        case installed(slot: Int)
    }

    var item: EquipmentItem
    var source: Source

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

/// UI-PTR-010: the pure drop rules. A drop does what the Buy or Sell button does, or nothing.
nonisolated enum OutfitterDrop {
    enum Target: Equatable, Sendable {
        /// A slot tile of `group`; `free` when nothing is installed in it.
        case slot(OutfitterGroup, free: Bool)
        case sellWell
    }

    enum Action: Equatable, Sendable {
        case buy(EquipmentItem)
        case sell(EquipmentItem, slot: Int)
        case none
    }

    static func group(of item: EquipmentItem) -> OutfitterGroup {
        switch item {
        case .weapon: .weapons
        case .shield: .shields
        case .gadget: .gadgets
        }
    }

    /// An item for sale dropped on a free slot of its own group buys it (unless the buy check blocks it); an installed item
    /// dropped on the sell well sells it. Everything else does nothing.
    static func action(for drag: OutfitterDragItem, onto target: Target, buyBlocked: Bool) -> Action {
        switch (drag.source, target) {
        case let (.offer, .slot(group, free)):
            return free && group == Self.group(of: drag.item) && !buyBlocked ? .buy(drag.item) : .none
        case let (.installed(slot), .sellWell):
            return .sell(drag.item, slot: slot)
        case (.offer, .sellWell), (.installed, .slot):
            return .none
        }
    }
}
