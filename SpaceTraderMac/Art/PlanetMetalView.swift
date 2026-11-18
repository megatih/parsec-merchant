// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import Metal
import ParsecArt
import QuartzCore
import SwiftUI

/// ART-075, ART-076: the pure rules of the live planet.
enum PlanetLiveSupport {
    enum Mode: Equatable {
        case live, still
    }

    /// ART-075: the live Metal view only without Reduce Motion, with a device and a compiled pipeline.
    static func mode(reduceMotion: Bool, deviceAvailable: Bool, pipelineReady: Bool) -> Mode {
        !reduceMotion && deviceAvailable && pipelineReady ? .live : .still
    }

    /// ART-076: the display link rests when the window is inactive, hidden or absent.
    static func isPaused(appearsActive: Bool, windowVisible: Bool, inWindow: Bool) -> Bool {
        !(appearsActive && windowVisible && inWindow)
    }

    /// ART-076: display-link time to art phase; ParsecArt never reads the clock.
    static func phase(timestamp: CFTimeInterval) -> Double {
        let p = timestamp.truncatingRemainder(dividingBy: PlanetSphere.phaseWrap)
        return p < 0 ? p + PlanetSphere.phaseWrap : p
    }
}

/// ART-074: the Metal pipeline of the live planet: the shader compiled once from its source string.
final class PlanetMetalRenderer {
    static let pixelFormat = MTLPixelFormat.bgra8Unorm

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState

    private enum Shared {
        case unloaded, ready(PlanetMetalRenderer), failed
    }

    private static var sharedState = Shared.unloaded

    /// The app's renderer; nil when there is no Metal device or the shader does not compile (ART-075).
    static var shared: PlanetMetalRenderer? {
        switch sharedState {
        case let .ready(r): return r
        case .failed: return nil
        case .unloaded:
            let made = MTLCreateSystemDefaultDevice().flatMap { try? PlanetMetalRenderer(device: $0) }
            sharedState = made.map(Shared.ready) ?? .failed
            return made
        }
    }

    init(device: MTLDevice, source: String = PlanetSphereShader.source) throws {
        self.device = device
        let library = try device.makeLibrary(source: source, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: PlanetSphereShader.vertexFunction)
        descriptor.fragmentFunction = library.makeFunction(name: PlanetSphereShader.fragmentFunction)
        descriptor.colorAttachments[0].pixelFormat = Self.pixelFormat
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let s = MTLSamplerDescriptor()
        s.minFilter = .linear
        s.magFilter = .linear
        s.sAddressMode = .repeat
        s.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: s), let queue = device.makeCommandQueue() else {
            throw CocoaError(.featureUnsupported)
        }
        self.sampler = sampler
        self.queue = queue
    }

    /// The two baked maps as textures.
    struct Textures {
        let albedo: MTLTexture
        let aux: MTLTexture
    }

    func textures(for maps: PlanetMaps) -> Textures? {
        func make(_ bytes: [UInt8]) -> MTLTexture? {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: maps.width, height: maps.height, mipmapped: false)
            d.usage = .shaderRead
            guard let t = device.makeTexture(descriptor: d) else { return nil }
            bytes.withUnsafeBytes { raw in
                if let base = raw.baseAddress {
                    t.replace(region: MTLRegionMake2D(0, 0, maps.width, maps.height), mipmapLevel: 0, withBytes: base, bytesPerRow: maps.width * 4)
                }
            }
            return t
        }
        guard let a = make(maps.albedo), let x = make(maps.aux) else { return nil }
        return Textures(albedo: a, aux: x)
    }

    /// Draws one frame into `target` and returns the committed command buffer.
    @discardableResult
    func draw(_ textures: Textures, uniforms: PlanetSphere.Uniforms, into target: MTLTexture, present drawable: MTLDrawable? = nil) -> MTLCommandBuffer? {
        guard let buffer = queue.makeCommandBuffer() else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encoder.setRenderPipelineState(pipeline)
        var u = uniforms
        withUnsafeBytes(of: &u) { raw in
            if let base = raw.baseAddress { encoder.setFragmentBytes(base, length: raw.count, index: 0) }
        }
        encoder.setFragmentTexture(textures.albedo, index: 0)
        encoder.setFragmentTexture(textures.aux, index: 1)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        if let drawable { buffer.present(drawable) }
        buffer.commit()
        return buffer
    }

    /// ART-074: an offscreen frame as premultiplied RGBA8 bytes, rows top to bottom (the CPU projector's format).
    func offscreen(_ maps: PlanetMaps, uniforms: PlanetSphere.Uniforms, pixelSize n: Int) -> [UInt8]? {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.pixelFormat, width: n, height: n, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .shared
        guard let target = device.makeTexture(descriptor: d), let textures = textures(for: maps),
              let buffer = draw(textures, uniforms: uniforms, into: target) else { return nil }
        buffer.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: n * n * 4)
        bytes.withUnsafeMutableBytes { raw in
            if let base = raw.baseAddress {
                target.getBytes(base, bytesPerRow: n * 4, from: MTLRegionMake2D(0, 0, n, n), mipmapLevel: 0)
            }
        }
        for i in stride(from: 0, to: bytes.count, by: 4) { bytes.swapAt(i, i + 2) }
        return bytes
    }
}

/// ART-076: the live planet: a `CAMetalLayer` drawn from the view's display link, outside SwiftUI's update cycle.
struct PlanetMetalView: NSViewRepresentable {
    static let framesPerSecond: Float = 30

    let renderer: PlanetMetalRenderer
    let recipe: PlanetRecipe
    let maps: PlanetMaps
    let accessibility: ArtAccessibility
    let appearsActive: Bool

    func makeNSView(context: Context) -> PlanetMetalNSView {
        PlanetMetalNSView(renderer: renderer)
    }

    func updateNSView(_ view: PlanetMetalNSView, context: Context) {
        view.show(recipe: recipe, maps: maps, accessibility: accessibility)
        view.appearsActive = appearsActive
    }
}

final class PlanetMetalNSView: NSView {
    private let renderer: PlanetMetalRenderer
    private let metalLayer = CAMetalLayer()
    private var link: CADisplayLink?
    private var recipe: PlanetRecipe?
    private var maps: PlanetMaps?
    private var textures: PlanetMetalRenderer.Textures?
    private var accessibility = ArtAccessibility.standard
    private var observers: [any NSObjectProtocol] = []
    var appearsActive = true {
        didSet { updatePause() }
    }

    init(renderer: PlanetMetalRenderer) {
        self.renderer = renderer
        super.init(frame: .zero)
        wantsLayer = true
        metalLayer.device = renderer.device
        metalLayer.pixelFormat = PlanetMetalRenderer.pixelFormat
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        metalLayer.isOpaque = false
        metalLayer.framebufferOnly = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PlanetMetalNSView is created in code") }

    override func makeBackingLayer() -> CALayer { metalLayer }

    /// The live planet is decoration: clicks go to the views around it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(recipe: PlanetRecipe, maps: PlanetMaps, accessibility: ArtAccessibility) {
        if self.maps != maps {
            textures = renderer.textures(for: maps)
            self.maps = maps
        }
        self.recipe = recipe
        self.accessibility = accessibility
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        link?.invalidate()
        link = nil
        for token in observers { NotificationCenter.default.removeObserver(token) }
        observers = []
        guard let window else { return }
        let rate = PlanetMetalView.framesPerSecond
        let made = displayLink(target: self, selector: #selector(tick(_:)))
        made.preferredFrameRateRange = CAFrameRateRange(minimum: rate, maximum: rate, preferred: rate)
        made.add(to: .main, forMode: .common)
        link = made
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updatePause() }
            })
        }
        updatePause()
    }

    private func updatePause() {
        let visible = window.map { $0.occlusionState.contains(.visible) && !$0.isMiniaturized } ?? false
        link?.isPaused = PlanetLiveSupport.isPaused(appearsActive: appearsActive, windowVisible: visible, inWindow: window != nil)
    }

    override func layout() {
        super.layout()
        let scale = window?.backingScaleFactor ?? 2
        metalLayer.contentsScale = scale
        // The host keeps this view square (PlanetPortrait), so the square drawable is never stretched.
        let side = (min(bounds.width, bounds.height) * scale).rounded()
        metalLayer.drawableSize = CGSize(width: side, height: side)
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let recipe, let maps, let textures, metalLayer.drawableSize.width >= 1, let drawable = metalLayer.nextDrawable() else { return }
        let pixels = Int(metalLayer.drawableSize.width)
        let scale = metalLayer.contentsScale
        let frame = PlanetRenderer.Frame(size: CGSize(width: Double(pixels) / scale, height: Double(pixels) / scale), recipe: recipe, fills: false)
        let uniforms = PlanetSphere.uniforms(recipe: recipe, phase: PlanetLiveSupport.phase(timestamp: link.targetTimestamp),
                                             accessibility: accessibility, pixelSize: pixels, radius: frame.radius * scale, mapWidth: maps.width)
        renderer.draw(textures, uniforms: uniforms, into: drawable.texture, present: drawable)
    }
}
