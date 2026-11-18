// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import Foundation
import ParsecArt
import ParsecEngine
import ParsecInsights
import SwiftUI
import Testing
@testable import ParsecMerchant

/// Renders a view with `ImageRenderer` into an RGBA buffer (Core Graphics route, deterministic).
@MainActor
enum AppArtSnapshot {
    static func render<V: View>(_ view: V, size: CGSize, scale: CGFloat = 1) -> [UInt8] {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.proposedSize = ProposedViewSize(size)
        let w = Int(size.width * scale), h = Int(size.height * scale)
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        bytes.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            renderer.render(rasterizationScale: scale) { _, draw in
                ctx.scaleBy(x: scale, y: scale)
                draw(ctx)
            }
        }
        return bytes
    }

    static func coverage(_ bytes: [UInt8]) -> Double {
        var n = 0
        for i in stride(from: 3, to: bytes.count, by: 4) where bytes[i] > 0 { n += 1 }
        return Double(n) / Double(max(1, bytes.count / 4))
    }
}

@MainActor
@Suite("Art integration")
struct ArtIntegrationTests {
    @Test("ART-007 the ship-kind adapter maps every ShipType to the art kind with the same raw value (17 both)")
    func shipKinds() {
        #expect(ShipType.allCases.count == 17 && ShipArtKind.allCases.count == 17)
        for t in ShipType.allCases { #expect(ArtAdapters.shipKind(t).rawValue == t.rawValue) }
    }

    @Test("ART-008 ART-088 the adapter passes every statistic of the ruleset's ShipSpec, the tiers and the installed equipment")
    func shipInputs() throws {
        for id in RulesetID.allCases {
            let ruleset = Ruleset.named(id)
            for t in ShipType.allCases where t != .custom {
                let spec = ruleset.tables.ship(t)
                var ship = Ship(type: t, spec: spec)
                ship.hull /= 2
                let input = ArtAdapters.shipInput(ship, ruleset: ruleset, facing: .left)
                let s = input.stats
                #expect(input.sizeClass == spec.size.rawValue && s.sizeClass == spec.size.rawValue, "\(id) \(t)")
                #expect(s.cargoBays == spec.cargoBays && s.weaponSlots == spec.weaponSlots && s.shieldSlots == spec.shieldSlots
                    && s.gadgetSlots == spec.gadgetSlots && s.crewQuarters == spec.crewQuarters && s.fuelTanks == spec.fuelTanks
                    && s.hullStrength == spec.hullStrength, "\(id) \(t)")
                #expect(s.priceTier == [5000, 20000, 50000, 90000, 200_000].filter { spec.price >= $0 }.count)
                #expect(s.techTier == min(7, spec.minTechLevel.rawValue))
                #expect(s.weapons == [] && s.shields == [] && s.gadgets == [], "a bare ship has nothing installed")
                #expect(input.kind.rawValue == t.rawValue && input.facing == .left)
                #expect(abs(input.hullFraction - Double(ship.hull) / Double(ship.hullStrength(ruleset))) < 1e-9)
                // A type portrait has no ship instance: the equipment is unknown, so every slot is drawn filled.
                let pristine = ArtAdapters.specInput(t, spec: spec).stats
                #expect(pristine.weapons == nil && pristine.cargoBays == spec.cargoBays)
                // ART-088: the art's reference table is the Windows 2.01 table.
                if id == .windows201 { #expect(pristine == ShipArtStats.standard(ArtAdapters.shipKind(t)), "\(t)") }
            }
        }
        let ruleset = Ruleset.named(.modern)
        var spec = ruleset.tables.ship(.wasp)
        spec.size = .tiny
        spec.weaponSlots = 4
        var custom = Ship(type: .custom, spec: spec)
        custom.customSpec = spec
        custom.weapons = [.pulseLaser, .militaryLaser]
        custom.gadgets = [.navigatingSystem]
        let input = ArtAdapters.shipInput(custom, ruleset: ruleset, facing: .right)
        #expect(input.sizeClass == 0 && input.stats.weaponSlots == 4)
        #expect(input.stats.weapons == [WeaponType.pulseLaser.rawValue, WeaponType.militaryLaser.rawValue])
        #expect(input.stats.gadgets == [GadgetType.navigatingSystem.rawValue] && input.stats.shields == [])
        // The installed weapons show: two barrels on four mounts, and arming a third changes the picture.
        var armed = custom
        armed.weapons.append(.beamLaser)
        #expect(ArtAdapters.shipInput(armed, ruleset: ruleset, facing: .right).blueprint != input.blueprint)
        // ART-012: the designer preview follows the draft's statistics; the hull style is only a variant.
        let design = ShipDesign(name: "T", size: .medium, cargoBays: 30, fuelTanks: 14, hull: 120, weaponSlots: 2, shieldSlots: 1, gadgetSlots: 1,
                                crewQuarters: 2)
        let preview = ArtAdapters.designInput(design, style: .hornet, price: 60000)
        #expect(preview.kind == .custom && preview.stats.cargoBays == 30 && preview.stats.priceTier == 3 && preview.variant == ArtSeed.kind(.hornet))
        #expect(preview.blueprint.livery.primary == .brass)
        var bigger = design
        bigger.cargoBays = 60
        #expect(ArtAdapters.designInput(bigger, style: .hornet, price: 60000).blueprint != preview.blueprint)
        var shielded = Ship(type: .gnat, spec: ruleset.tables.ship(.gnat))
        shielded.shields = [EffectFx.shield(.energy, charge: 10), EffectFx.shield(.reflective, charge: 50)]
        let shield = try #require(ArtAdapters.shield(shielded, ruleset: ruleset))
        #expect(shield.kind == .reflective)
        #expect(abs(shield.fraction - 60.0 / Double(shielded.shieldStrength(ruleset))) < 1e-9)
    }

    static func components(_ color: Color, dark: Bool) -> [Double] {
        var out: [Double] = []
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua) ?? NSAppearance.currentDrawing()
        appearance.performAsCurrentDrawingAppearance {
            let c = NSColor(color).usingColorSpace(.sRGB) ?? .black
            out = [c.redComponent, c.greenComponent, c.blueComponent]
        }
        return out
    }

    @Test("ART-003 the map palette equals ArtPalette's map tokens (MAP-024, MAP-037)")
    func mapPalette() {
        let pairs: [(Color, ArtToken)] = [(MapStyle.spaceTop, .spaceTop), (MapStyle.spaceBottom, .spaceBottom), (MapStyle.visited, .visited),
                                          (MapStyle.unvisited, .unvisited), (MapStyle.brass, .brass), (MapStyle.wormholeA, .wormholeA),
                                          (MapStyle.wormholeB, .wormholeB)]
        for (color, token) in pairs {
            for dark in [false, true] {
                let art = ArtPalette.rgb(token, scheme: dark ? .dark : .light)
                let map = Self.components(color, dark: dark)
                #expect(zip(map, [art.r, art.g, art.b]).allSatisfy { abs($0 - $1) < 0.005 }, "\(token) dark: \(dark) \(map)")
            }
        }
    }

    @Test("ART-020 planet inputs: galaxy-seeded, known resource only (fair), pressure only where shown")
    func planetFairness() throws {
        let state = try #require(try TestSessions.playing(seed: 7).state)
        let target = try #require(state.galaxy.systems.indices.first { !state.galaxy.systems[$0].visited })
        var other = state
        other.galaxy.systems[target].specialResource = state.galaxy.systems[target].specialResource == .desert ? .lifeless : .desert
        #expect(ArtAdapters.planetInput(system: target, state: state, showPressure: false)
            == ArtAdapters.planetInput(system: target, state: other, showPressure: false))
        #expect(ArtAdapters.planetInput(system: target, state: state, showPressure: false).resource == nil)
        let here = state.commander.currentSystem
        let input = ArtAdapters.planetInput(system: here, state: state, showPressure: true)
        #expect(input.seed == ArtSeed.system(galaxySeed: state.seed, index: here))
        #expect(input.resource == state.galaxy.systems[here].knownResource.rawValue)
        var war = state
        war.galaxy.systems[here].pressure = .war
        #expect(ArtAdapters.planetInput(system: here, state: war, showPressure: true).pressure == SystemPressure.war.rawValue)
        #expect(ArtAdapters.planetInput(system: here, state: war, showPressure: false).pressure == nil)
    }

    @Test("MAP-095 ART-029 ART-030 map art: mini-planets from zoom 4 with the Bridge input, galaxy-seeded space, vortex geometry")
    func mapArt() throws {
        let session = try TestSessions.playing(seed: 7)
        let state = try #require(session.state)
        let snapshot = try #require(session.mapSnapshot)
        let visited = try #require(snapshot.systems.first { $0.visited })
        #expect(MapArtRenderer.planetInput(visited, galaxySeed: state.seed)
            == ArtAdapters.planetInput(system: visited.index, state: state, showPressure: false))
        #expect(!MapArtRenderer.drawsPlanets(zoom: 3.9) && MapArtRenderer.drawsPlanets(zoom: 4))
        let unvisited = try #require(snapshot.systems.first { !$0.visited })
        #expect(MapArtRenderer.planetInput(unvisited, galaxySeed: state.seed).resource == nil)
        // The static vortex is the M8 geometry; the art renders deterministically and non-empty.
        let space = AppArtSnapshot.render(Canvas { ctx, size in
            MapArtRenderer.drawSpace(&ctx, size: size, projection: MapProjection(scale: 6, origin: CGPoint(x: 10, y: 10)),
                                     art: MapArt(galaxySeed: state.seed, reduceTransparency: false, vorticesInOverlay: false))
        }, size: CGSize(width: 200, height: 120))
        let again = AppArtSnapshot.render(Canvas { ctx, size in
            MapArtRenderer.drawSpace(&ctx, size: size, projection: MapProjection(scale: 6, origin: CGPoint(x: 10, y: 10)),
                                     art: MapArt(galaxySeed: state.seed, reduceTransparency: false, vorticesInOverlay: false))
        }, size: CGSize(width: 200, height: 120))
        #expect(space == again && AppArtSnapshot.coverage(space) > 0.05)
        let planet = AppArtSnapshot.render(Canvas { ctx, _ in
            MapArtRenderer.drawPlanet(&ctx, system: visited, center: CGPoint(x: 20, y: 20), radius: 12, filled: true,
                                      art: MapArt(galaxySeed: state.seed, reduceTransparency: false, vorticesInOverlay: false))
        }, size: CGSize(width: 40, height: 40))
        #expect(AppArtSnapshot.coverage(planet) > 0.2)
    }

    @Test("ART-040 every special event maps to a vignette (planet, quest ship or object)")
    func vignettes() throws {
        let state = try #require(try TestSessions.playing().state)
        for type in SpecialEventType.allCases {
            let input = NarrativeVignette.input(for: type, state: state)
            switch (NarrativeVignette.kind(for: type), input) {
            case (.planet, .planet), (.object, .object): break
            case let (.ship(t), .ship(i)): #expect(i.kind == ArtAdapters.shipKind(t))
            default: Issue.record("\(type) maps inconsistently")
            }
        }
        #expect(NarrativeVignette.kind(for: .scarab) == .ship(.scarab))
        #expect(NarrativeVignette.kind(for: .spaceMonster) == .ship(.spaceMonster))
        #expect(NarrativeVignette.kind(for: .reactor) == .object(.reactor))
        #expect(NarrativeVignette.kind(for: .lottery) == .planet)
    }

    @Test("ACH-023 every achievement has its own drawn emblem and a locked variant")
    func achievementArt() {
        let all = AchievementID.allCases.map { AchievementArt.badge($0).emblem }
        #expect(Set(all).count == AchievementID.allCases.count)
        let size = CGSize(width: 40, height: 40)
        let a = AppArtSnapshot.render(AchievementBadgeView(id: .moon, unlocked: true), size: size)
        let b = AppArtSnapshot.render(AchievementBadgeView(id: .moon, unlocked: false), size: size)
        #expect(a != b && AppArtSnapshot.coverage(a) > 0.3)
        #expect(a == AppArtSnapshot.render(AchievementBadgeView(id: .moon, unlocked: true), size: size))
    }

    @Test("UI-ENC-101 ART-060 every ShipType portrait renders in both facings, non-empty and deterministic")
    func encounterPortraits() {
        let ruleset = Ruleset.named(.modern)
        let size = CGSize(width: 180, height: 120)
        for t in ShipType.allCases {
            // A custom ship is drawn from its saved spec (the table row of `.custom` is empty).
            var spec = ruleset.tables.ship(t == .custom ? .hornet : t)
            spec.type = t
            var ship = Ship(type: t, spec: spec)
            if t == .custom { ship.customSpec = spec }
            for facing in [ShipFacing.right, .left] {
                let input = ArtAdapters.shipInput(ship, ruleset: ruleset, facing: facing)
                let a = AppArtSnapshot.render(ShipArt(input, scaleMode: .relative), size: size)
                #expect(a == AppArtSnapshot.render(ShipArt(input, scaleMode: .relative), size: size), "\(t)")
                #expect(AppArtSnapshot.coverage(a) > 0.01, "\(t) \(facing)")
            }
        }
    }

    @Test("ART-051 UI-ENC-101 the M7–M9 art placeholders and the UI-ENC-017 SF Symbol stand-ins are gone")
    func placeholdersRemoved() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("SpaceTraderMac")
        let files = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "swift" }
        #expect(files.count > 50)
        let banned = ["ShipPlaceholder(", "PlanetPlaceholder(", "NarrativeVignette(kind:", "badge.symbol", "\"flag.fill\"", "\"circle.hexagongrid.fill\"",
                      "Image(systemName: \"airplane\")", "\"globe.americas.fill\""]
        for f in files {
            let text = try String(contentsOf: f, encoding: .utf8)
            for word in banned { #expect(!text.contains(word), "\(f.lastPathComponent) contains \(word)") }
        }
    }
}
