// SPDX-License-Identifier: GPL-2.0-or-later
import AVFoundation
import Foundation

/// Why the output could not start (AUD-009).
public enum AudioOutputError: Error, Equatable, Sendable {
    /// The output hardware reports no sample rate or no channels.
    case noOutputDevice
    /// `AVAudioEngine` threw; the code is the `NSError` code.
    case engineFailed(code: Int)
}

/// AUD-008…010: the one place that touches `AVAudioEngine`. Owns an engine and one `AVAudioSourceNode` whose render
/// block (made by the `nonisolated` factory below) captures only the `SynthCore`. Used by the app from the main actor;
/// every engine call happens there, never in the render block.
public nonisolated final class AudioOutput {
    public private(set) var core: SynthCore?
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private let seed: UInt64
    private var gains: (overall: Float, effects: Float, music: Float) = (1, 1, 1)
    private var music: (enabled: Bool, mood: MusicMood) = (false, .calm)
    private var observer: (any NSObjectProtocol)?

    public init(seed: UInt64 = 0x5EED_A0D1) {
        self.seed = seed
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        engine.stop()
    }

    /// True while the engine renders.
    public var isRunning: Bool { engine.isRunning }

    /// The rate the core renders at (0 before the first successful start).
    public var sampleRate: Double { core?.sampleRate ?? 0 }

    /// Reads the hardware format, builds the core at its rate, attaches and starts (AUD-009).
    public func start() throws(AudioOutputError) {
        if source != nil { stop() }
        let hardware = engine.outputNode.outputFormat(forBus: 0)
        guard hardware.sampleRate > 0, hardware.channelCount > 0 else { throw .noOutputDevice }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: hardware.sampleRate, channels: 2) else {
            throw .engineFailed(code: -1)
        }
        let core = SynthCore(sampleRate: hardware.sampleRate, seed: seed)
        core.setGains(overall: gains.overall, effects: gains.effects, music: gains.music)
        core.setMusic(enabled: music.enabled, mood: music.mood)
        let node = AVAudioSourceNode(format: format, renderBlock: Self.makeRenderBlock(core: core))
        engine.attach(node)
        self.core = core
        source = node
        do {
            try engine.connectNode(node, to: engine.mainMixerNode, format: format)
            engine.prepare()
            try engine.start()
        } catch {
            stop()
            throw .engineFailed(code: (error as NSError).code)
        }
    }

    /// Stops the engine and detaches the node.
    public func stop() {
        engine.stop()
        if let source {
            engine.detach(source)
        }
        source = nil
    }

    /// Pauses rendering (the core and its node stay attached).
    public func pause() {
        engine.pause()
    }

    /// Resumes after `pause`.
    public func resume() throws(AudioOutputError) {
        guard source != nil else {
            try start()
            return
        }
        do {
            try engine.start()
        } catch {
            throw .engineFailed(code: (error as NSError).code)
        }
    }

    /// AUD-010: stop, rebuild the core at the (new) hardware rate, keep gains and music settings, restart.
    public func rebuild() throws(AudioOutputError) {
        stop()
        core = nil
        try start()
    }

    /// Calls `handler` on the main queue after every `AVAudioEngineConfigurationChange` of this engine.
    public func observeConfigurationChanges(_ handler: @escaping @Sendable () -> Void) {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                                          queue: .main) { _ in handler() }
    }

    // MARK: Forwarding to the core

    @discardableResult
    public func enqueue(_ request: CueRequest) -> Bool {
        core?.enqueue(request) ?? false
    }

    public func setGains(overall: Float, effects: Float, music volume: Float) {
        gains = (overall, effects, volume)
        core?.setGains(overall: overall, effects: effects, music: volume)
    }

    public func setMusic(enabled: Bool, mood: MusicMood) {
        music = (enabled, mood)
        core?.setMusic(enabled: enabled, mood: mood)
    }

    public func stopAll() { core?.stopAll() }

    public var renderCount: Int { core?.renderCount ?? 0 }
    public var droppedRequests: Int { core?.droppedRequests ?? 0 }
    public var activeVoices: Int { core?.activeVoices ?? 0 }

    // MARK: Render block (AUD-008)

    /// Builds the source-node block. It is `nonisolated` and captures only `core`, so no actor isolation applies to it.
    public nonisolated static func makeRenderBlock(core: SynthCore) -> AVAudioSourceNodeRenderBlock {
        { isSilence, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard buffers.count > 0, let l = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let r = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) ?? l : l
            let silent = core.render(frameCount: Int(frameCount), left: l, right: r)
            isSilence.pointee = ObjCBool(silent)
            return noErr
        }
    }
}
