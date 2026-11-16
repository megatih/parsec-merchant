// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

/// Localized names, kinds and descriptions of equipment for the Outfitter and the purchase review.
enum EquipmentText {
    static func name(_ item: EquipmentItem) -> LocalizedStringResource {
        switch item {
        case let .weapon(w): Names.weapon(w)
        case let .shield(s): Names.shield(s)
        case let .gadget(g): Names.gadget(g)
        }
    }

    static func kind(_ item: EquipmentItem) -> LocalizedStringResource {
        switch item {
        case .weapon: "Weapon"
        case .shield: "Shield"
        case .gadget: "Gadget"
        }
    }

    static func description(_ item: EquipmentItem) -> LocalizedStringResource {
        switch item {
        case let .weapon(w): weapon(w)
        case let .shield(s): shield(s)
        case let .gadget(g): gadget(g)
        }
    }

    private static func weapon(_ w: WeaponType) -> LocalizedStringResource {
        switch w {
        case .pulseLaser: "A cheap, light laser. Better than nothing."
        case .beamLaser: "A solid all-round laser, stronger than a pulse laser."
        case .militaryLaser: "The strongest laser on the open market."
        case .morgansLaser: "Henry Morgan's custom laser. It can't be bought anywhere."
        case .photonDisruptor: "Disables an opponent's systems instead of destroying the ship."
        case .quantumDisruptor: "A prototype disruptor of great power. It can't be bought anywhere."
        }
    }

    private static func shield(_ s: ShieldType) -> LocalizedStringResource {
        switch s {
        case .energy: "A basic energy shield that absorbs incoming fire."
        case .reflective: "Reflects much of the incoming fire. Stronger than an energy shield."
        case .lightning: "An experimental shield of unmatched strength. It can't be bought anywhere."
        }
    }

    private static func gadget(_ g: GadgetType) -> LocalizedStringResource {
        switch g {
        case .extraCargoBays: "Adds five cargo bays to your ship."
        case .autoRepairSystem: "Repairs the hull during flight and improves your engineer skill."
        case .navigatingSystem: "Improves your pilot skill."
        case .targetingSystem: "Improves your fighter skill."
        case .cloakingDevice: "Lets you slip past other ships when your engineer outclasses theirs."
        case .fuelCompactor: "Extends your ship's range."
        case .hiddenCargoBays: "Five bays that police inspections don't find."
        }
    }
}
