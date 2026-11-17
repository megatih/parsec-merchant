// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecArt
import ParsecEngine

/// ART conventions "No game state": engine values → ParsecArt inputs. Every enum mapping is an exhaustive `switch` with no
/// `default`, so a new engine case fails to compile here.
nonisolated enum ArtAdapters {
    // MARK: Ships (ART-007, ART-008, ART-012)

    static func shipKind(_ t: ShipType) -> ShipArtKind {
        switch t {
        case .flea: .flea
        case .gnat: .gnat
        case .firefly: .firefly
        case .mosquito: .mosquito
        case .bumblebee: .bumblebee
        case .beetle: .beetle
        case .hornet: .hornet
        case .grasshopper: .grasshopper
        case .termite: .termite
        case .wasp: .wasp
        case .spaceMonster: .spaceMonster
        case .dragonfly: .dragonfly
        case .mantis: .mantis
        case .scarab: .scarab
        case .bottle: .bottle
        case .custom: .custom
        case .scorpion: .scorpion
        }
    }

    static func shieldKind(_ s: ShieldType) -> ShieldDisplay.Kind {
        switch s {
        case .energy: .energy
        case .reflective: .reflective
        case .lightning: .lightning
        }
    }

    /// The strongest installed shield and the summed charge over the summed power (nil without shields).
    static func shield(_ ship: Ship, ruleset: Ruleset) -> ShieldDisplay? {
        guard let strongest = ship.shields.map(\.type).max() else { return nil }
        let power = ship.shieldStrength(ruleset)
        return ShieldDisplay(kind: shieldKind(strongest), fraction: power > 0 ? Double(ship.shieldCharge) / Double(power) : 0)
    }

    /// ART-012: the custom-ship parameters of a spec (saved `Ship.customSpec` or the designer draft).
    static func customParams(_ spec: ShipSpec, base: ShipType? = nil) -> CustomShipParams {
        CustomShipParams(sizeClass: spec.size.rawValue, weaponSlots: spec.weaponSlots, shieldSlots: spec.shieldSlots,
                         gadgetSlots: spec.gadgetSlots, crewQuarters: spec.crewQuarters, fuelTanks: spec.fuelTanks,
                         cargoBays: spec.cargoBays, hullStrength: spec.hullStrength, base: base.map(shipKind))
    }

    /// ART-008: the portrait input of an engine ship; sizes come from `ShipMath`'s spec (custom ships use `customSpec`).
    static func shipInput(_ ship: Ship, ruleset: Ruleset, facing: ShipFacing, disabled: Bool = false, cloaked: Bool = false,
                          phase: Double = 0, accessibility: ArtAccessibility = .standard) -> ShipArtInput {
        let spec = ship.spec(ruleset)
        let maxHull = max(1, ship.hullStrength(ruleset))
        return ShipArtInput(kind: shipKind(ship.type), sizeClass: spec.size.rawValue, facing: facing,
                            hullFraction: Double(max(0, ship.hull)) / Double(maxHull), shield: shield(ship, ruleset: ruleset),
                            disabled: disabled, cloaked: cloaked, custom: ship.type == .custom ? customParams(spec) : nil, phase: phase,
                            accessibility: accessibility)
    }

    /// A pristine portrait of a ship type (shipyard cards, designer silhouettes).
    static func typeInput(_ type: ShipType, ruleset: Ruleset, custom: ShipSpec? = nil, base: ShipType? = nil) -> ShipArtInput {
        let spec = custom ?? ruleset.tables.ship(type)
        return ShipArtInput(kind: shipKind(type), sizeClass: spec.size.rawValue, custom: type == .custom ? customParams(spec, base: base) : nil)
    }

    // MARK: Planets (ART-020)

    /// ART-020: seed from the galaxy seed and system index; the known resource only (never `specialResource` of an
    /// unvisited system); the pressure only where the UI shows it as text.
    static func planetInput(system index: Int, state: GameState, showPressure: Bool, phase: Double = 0,
                            accessibility: ArtAccessibility = .standard) -> PlanetArtInput {
        let s = state.galaxy.systems[index]
        return PlanetArtInput(seed: ArtSeed.system(galaxySeed: state.seed, index: index), sizeClass: s.size.rawValue,
                              tech: min(7, s.techLevel.rawValue), government: s.politics.rawValue,
                              resource: s.visited ? s.knownResource.rawValue : nil,
                              pressure: showPressure && s.pressure != .none ? s.pressure.rawValue : nil, phase: phase, accessibility: accessibility)
    }

    // MARK: Glyphs (ART-031…035)

    static func commodity(_ t: TradeItemType) -> CommodityGlyphKind {
        switch t {
        case .water: .water
        case .furs: .furs
        case .food: .food
        case .ore: .ore
        case .games: .games
        case .firearms: .firearms
        case .medicine: .medicine
        case .machines: .machines
        case .narcotics: .narcotics
        case .robots: .robots
        }
    }

    static func weapon(_ w: WeaponType) -> EquipmentGlyphKind {
        switch w {
        case .pulseLaser: .weapon(0)
        case .beamLaser: .weapon(1)
        case .militaryLaser: .weapon(2)
        case .morgansLaser: .weapon(3)
        case .photonDisruptor: .weapon(4)
        case .quantumDisruptor: .weapon(5)
        }
    }

    static func shieldGlyph(_ s: ShieldType) -> EquipmentGlyphKind {
        switch s {
        case .energy: .shield(0)
        case .reflective: .shield(1)
        case .lightning: .shield(2)
        }
    }

    static func gadget(_ g: GadgetType) -> EquipmentGlyphKind {
        switch g {
        case .extraCargoBays: .gadget(0)
        case .autoRepairSystem: .gadget(1)
        case .navigatingSystem: .gadget(2)
        case .targetingSystem: .gadget(3)
        case .cloakingDevice: .gadget(4)
        case .fuelCompactor: .gadget(5)
        case .hiddenCargoBays: .gadget(6)
        }
    }

    static func beam(_ w: WeaponType) -> BeamKind {
        switch w {
        case .pulseLaser: .pulse
        case .beamLaser: .beam
        case .militaryLaser: .military
        case .morgansLaser: .morgans
        case .photonDisruptor: .photon
        case .quantumDisruptor: .quantum
        }
    }

    static func badge(_ b: EncounterBadge) -> EncounterBadgeKind {
        switch b {
        case .special: .special
        case .pirate: .pirate
        case .alien: .alien
        case .police: .police
        case .trader: .trader
        }
    }

    static func gameEnd(_ e: GameEndType) -> GameEndArt {
        switch e {
        case .killed: .killed
        case .retired: .retired
        case .boughtMoon: .boughtMoon
        case .boughtMoonGirl: .boughtMoonGirl
        }
    }

    /// ART-034: special passengers get a fixed avatar; everyone else a seeded bust.
    static func avatarRole(crewID: Int) -> CrewAvatarRole? {
        switch crewID {
        case CrewID.wild: .wild
        case CrewID.jarek: .jarek
        case CrewID.princess: .princess
        default: nil
        }
    }

    static func avatarSeed(crewID: Int, state: GameState) -> UInt64 {
        ArtSeed.crew(galaxySeed: state.seed, crewID: crewID)
    }

    /// A pristine portrait of a ship type with a known spec (shipyard cards).
    static func specInput(_ type: ShipType, spec: ShipSpec) -> ShipArtInput {
        ShipArtInput(kind: shipKind(type), sizeClass: spec.size.rawValue, custom: type == .custom ? customParams(spec) : nil)
    }

    /// ART-012: the designer draft's live preview (the silhouette picks the hull profile).
    static func customParams(design: ShipDesign, base: ShipType) -> CustomShipParams {
        CustomShipParams(sizeClass: design.size.rawValue, weaponSlots: design.weaponSlots, shieldSlots: design.shieldSlots,
                         gadgetSlots: design.gadgetSlots, crewQuarters: design.crewQuarters, fuelTanks: design.fuelTanks,
                         cargoBays: design.cargoBays, hullStrength: design.hull, base: shipKind(base))
    }
}

extension SystemText {
    /// ART-049: the planet portrait's label.
    static func planetLabel(_ model: SystemCardModel) -> String {
        String(localized: "Planet of \(model.name), \(String(localized: Names.size(model.size))), \(String(localized: techLevel(model.techLevel)))")
    }
}
