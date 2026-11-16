// SPDX-License-Identifier: GPL-2.0-or-later
// The outfitter's aggregate preview (SHP-077, UI-SHELL-120): every buyable item and every installed item with its price
// and the error the matching command would return. Pure; draws no random numbers.

/// A weapon, shield or gadget type.
public enum EquipmentItem: Hashable, Codable, Sendable {
    case weapon(WeaponType)
    case shield(ShieldType)
    case gadget(GadgetType)
}

/// An item of the ruleset's equipment tables as the current system offers it.
public struct EquipmentOffer: Sendable, Equatable {
    public var item: EquipmentItem
    /// The buy price here (SHP-011…013); 0 = not sold here.
    public var buyPrice: Int
    /// The rejection of the matching `buy…` command (SHP-020/SHP-021 order), or nil when it would ask to confirm.
    public var buyBlocker: CommandError?
}

/// An item installed on the commander's ship.
public struct InstalledEquipment: Sendable, Equatable {
    public var item: EquipmentItem
    /// The index within its kind's slots (the `index` of `sellWeapon`/`sellShield`/`sellGadget`).
    public var slot: Int
    /// `price × 3 / 4` (SHP-024).
    public var sellPrice: Int
    /// The rejection of the matching `sell…` command (SHP-025/SHP-026), or nil.
    public var sellBlocker: CommandError?
}

/// SHP-077 / UI-SHELL-120: the equipment market of the current system.
public struct EquipmentMarket: Sendable, Equatable {
    /// Every weapon, then shield, then gadget of the ruleset's tables, in table order.
    public var offers: [EquipmentOffer]
    /// Installed weapons, then shields, then gadgets, each in slot order.
    public var installed: [InstalledEquipment]
}

public extension GameState {
    /// SHP-077 / UI-SHELL-120.
    var equipmentMarket: EquipmentMarket {
        let t = ruleset.tables
        let items: [EquipmentItem] = t.weapons.indices.compactMap { WeaponType(rawValue: $0).map(EquipmentItem.weapon) }
            + t.shields.indices.compactMap { ShieldType(rawValue: $0).map(EquipmentItem.shield) }
            + t.gadgets.indices.compactMap { GadgetType(rawValue: $0).map(EquipmentItem.gadget) }
        let offers = items.map {
            EquipmentOffer(item: $0, buyPrice: equipmentBuyPrice($0), buyBlocker: equipmentBuyBlocker($0))
        }
        let ship = commander.ship
        let installed: [(EquipmentItem, Int)] = ship.weapons.enumerated().map { (.weapon($1), $0) }
            + ship.shields.enumerated().map { (.shield($1.type), $0) }
            + ship.gadgets.enumerated().map { (.gadget($1), $0) }
        return EquipmentMarket(offers: offers, installed: installed.map { item, slot in
            InstalledEquipment(item: item, slot: slot, sellPrice: equipmentSellPrice(item),
                               sellBlocker: equipmentSellBlocker(item))
        })
    }

    /// SHP-011…013: the buy price of an item here (0 = not sold).
    func equipmentBuyPrice(_ item: EquipmentItem) -> Int {
        switch item {
        case let .weapon(w): equipmentBuyPrice(weapon: w)
        case let .shield(s): equipmentBuyPrice(shield: s)
        case let .gadget(g): equipmentBuyPrice(gadget: g)
        }
    }

    /// SHP-024: what selling an installed item pays.
    func equipmentSellPrice(_ item: EquipmentItem) -> Int {
        let t = ruleset.tables
        switch item {
        case let .weapon(w): return t.weapon(w).price * 3 / 4
        case let .shield(s): return t.shield(s).price * 3 / 4
        case let .gadget(g): return t.gadget(g).price * 3 / 4
        }
    }

    /// SHP-020/SHP-021: the first error buying `item` raises before its confirmation, or nil.
    func equipmentBuyBlocker(_ item: EquipmentItem) -> CommandError? {
        if let phaseError = dockedCommandError { return phaseError }
        let ship = commander.ship
        let freeSlots: Int
        switch item {
        case .weapon: freeSlots = ship.freeWeaponSlots(ruleset)
        case .shield: freeSlots = ship.freeShieldSlots(ruleset)
        case let .gadget(g):
            if g != .extraCargoBays, ship.has(g) { return .equipmentAlreadyOwned }
            freeSlots = ship.freeGadgetSlots(ruleset)
        }
        let price = equipmentBuyPrice(item)
        if price <= 0 { return .notSoldHere }
        if commander.debt > 0 { return .inDebt }
        if price > cashToSpend { return .insufficientFunds }
        if freeSlots <= 0 { return .noFreeSlot }
        return nil
    }

    /// SHP-025/SHP-026: the error selling an installed `item` raises, or nil.
    func equipmentSellBlocker(_ item: EquipmentItem) -> CommandError? {
        if let phaseError = dockedCommandError { return phaseError }
        if case let .gadget(g) = item, g == .extraCargoBays || g == .hiddenCargoBays, freeCargoBays < 5 {
            return .extraBaysInUse
        }
        return nil
    }

    /// The phase error of a docked-only command: `.gameOver` after the end, `.notAllowedInPhase` away from a dock.
    internal var dockedCommandError: CommandError? {
        switch phase {
        case .gameOver: .gameOver
        case .docked: nil
        default: .notAllowedInPhase
        }
    }
}
