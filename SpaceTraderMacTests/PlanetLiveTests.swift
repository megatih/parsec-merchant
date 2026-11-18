// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Metal
import ParsecArt
import SwiftUI
import Testing
@testable import ParsecMerchant

@MainActor
@Suite("Live planet")
struct PlanetLiveTests {
    /// The first seed whose seed-weighted class is `cls` at size class 4 and whose ring presence is `ringed`.
    static func recipe(_ cls: PlanetClass, ringed: Bool = false) -> PlanetRecipe {
        var seed: UInt64 = 1
        while true {
            let rc = PlanetRecipe.make(PlanetArtInput(seed: seed, sizeClass: 4, tech: 6, pressure: cls == .terran ? 1 : nil))
            if rc.planetClass == cls, (rc.ring != nil) == ringed { return rc }
            seed += 1
        }
    }

    @Test("ART-074 the shader source compiles, and the Metal frame agrees with the CPU projection")
    func parity() throws {
        #expect(!PlanetSphereShader.source.isEmpty && PlanetSphereShader.source.contains("struct Uniforms"))
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("ART-074 SKIPPED: this host has no Metal device; the CPU still is the only path (ART-075)")
            return
        }
        let renderer = try PlanetMetalRenderer(device: device)
        let n = 256
        for (rc, phase) in [(Self.recipe(.terran), 3.0), (Self.recipe(.gasGiant, ringed: true), 7.0), (Self.recipe(.volcanic), 11.0)] {
            let maps = PlanetTextureBaker.bake(rc, lod: .hero)
            let frame = PlanetRenderer.Frame(size: CGSize(width: n, height: n), recipe: rc, fills: false)
            let uniforms = PlanetSphere.uniforms(recipe: rc, phase: phase, pixelSize: n, radius: frame.radius, mapWidth: maps.width)
            let cpu = PlanetSphere.pixels(maps, uniforms: uniforms, pixelSize: n)
            let gpu = try #require(renderer.offscreen(maps, uniforms: uniforms, pixelSize: n))
            #expect(cpu.count == gpu.count)
            var total = 0, lit = 0
            for (a, b) in zip(cpu, gpu) {
                total += abs(Int(a) - Int(b))
                if a > 0 { lit += 1 }
            }
            let mad = Double(total) / Double(cpu.count)
            print("ART-074 \(rc.planetClass) mean absolute difference \(mad) of 255")
            #expect(mad <= 3, "\(rc.planetClass)")
            #expect(lit > cpu.count / 8, "the frame is not empty")
        }
        // A broken shader is reported, not drawn (ART-075).
        #expect(throws: (any Error).self) { try PlanetMetalRenderer(device: device, source: "this is not Metal") }
    }

    @Test("ART-075 the live view needs motion, a device and a pipeline; everything else shows the still")
    func fallback() throws {
        #expect(PlanetLiveSupport.mode(reduceMotion: false, deviceAvailable: true, pipelineReady: true) == .live)
        #expect(PlanetLiveSupport.mode(reduceMotion: true, deviceAvailable: true, pipelineReady: true) == .still)
        #expect(PlanetLiveSupport.mode(reduceMotion: false, deviceAvailable: false, pipelineReady: false) == .still)
        #expect(PlanetLiveSupport.mode(reduceMotion: false, deviceAvailable: true, pipelineReady: false) == .still)
        // The live layer fills its view, so the view must be the square the projection covers, also in the wide stage.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("SpaceTraderMac")
        let portrait = try String(contentsOf: root.appendingPathComponent("Art/PlanetPortrait.swift"), encoding: .utf8)
        #expect(portrait.contains(".aspectRatio(1, contentMode: .fit)"))
        // The still is the CPU projection at phase 0, with or without the hero maps.
        let input = PlanetArtInput(seed: 31, sizeClass: 3, tech: 5, resource: 5, phase: 123)
        #expect(PlanetPortrait.with(input, ArtAccessibility(reduceMotion: true)).phase == 0)
        let small = AppArtSnapshot.render(PlanetArt(PlanetPortrait.with(input, .standard), lod: .still), size: CGSize(width: 240, height: 240))
        let hero = AppArtSnapshot.render(PlanetArt(PlanetPortrait.with(input, .standard)), size: CGSize(width: 240, height: 240))
        #expect(AppArtSnapshot.coverage(small) > 0.3 && AppArtSnapshot.coverage(hero) > 0.3)
        #expect(small != hero, "the hero maps are sharper than the stand-in")
    }

    @Test("ART-076 the display link runs at 30 fps, rests when the window is inactive or hidden, and wraps the phase at 600 s")
    func displayLink() {
        #expect(PlanetMetalView.framesPerSecond == 30)
        #expect(!PlanetLiveSupport.isPaused(appearsActive: true, windowVisible: true, inWindow: true))
        #expect(PlanetLiveSupport.isPaused(appearsActive: false, windowVisible: true, inWindow: true))
        #expect(PlanetLiveSupport.isPaused(appearsActive: true, windowVisible: false, inWindow: true))
        #expect(PlanetLiveSupport.isPaused(appearsActive: true, windowVisible: true, inWindow: false))
        #expect(PlanetLiveSupport.phase(timestamp: 0) == 0 && PlanetLiveSupport.phase(timestamp: 600) == 0)
        #expect(PlanetLiveSupport.phase(timestamp: 1234.5) == 34.5 && PlanetLiveSupport.phase(timestamp: -1) == 599)
        // Nothing jumps at the wrap: each period divides it.
        let rc = Self.recipe(.terran)
        func turn(_ t: Double) -> SIMD4<Float> {
            PlanetSphere.uniforms(recipe: rc, phase: PlanetLiveSupport.phase(timestamp: t), pixelSize: 64, radius: 30, mapWidth: 128).turn
        }
        #expect(turn(600) == turn(0) && turn(1800) == turn(0) && turn(599.99) != turn(0))
    }

    @Test("ART-077 the hero stage: 240 pt beside the facts from 506 pt of card width, 230 pt high above them otherwise")
    func heroStage() throws {
        #expect(PlanetHero.besideSide == 240 && PlanetHero.stackedHeight == 230 && PlanetHero.factsMinWidth == 250 && PlanetHero.spacing == 16)
        #expect(PlanetHero.besideMinWidth == 506)
        #expect(min(PlanetHero.besideSide, PlanetHero.stackedHeight) >= 220)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("SpaceTraderMac")
        let bridge = try String(contentsOf: root.appendingPathComponent("Views/Sections/BridgeSectionView.swift"), encoding: .utf8)
        #expect(bridge.contains("hero.frame(width: PlanetHero.besideSide, height: PlanetHero.besideSide)"))
        #expect(bridge.contains("hero.frame(maxWidth: .infinity).frame(height: PlanetHero.stackedHeight)"))
        #expect(bridge.contains("facts.frame(minWidth: PlanetHero.factsMinWidth, alignment: .leading)"))
        // The stage draws: backdrop plus planet cover the whole stage.
        let stage = AppArtSnapshot.render(PlanetHero(input: PlanetArtInput(seed: 5, sizeClass: 3, resource: 5))
            .environment(\.artAccessibilityOverride, ArtAccessibility(reduceMotion: true)), size: CGSize(width: 300, height: 230))
        #expect(AppArtSnapshot.coverage(stage) > 0.95)
    }
}
