// SPDX-License-Identifier: GPL-2.0-or-later
import AVFoundation
import Testing
@testable import ParsecAudio

@Suite("Audio output")
struct AudioOutputTests {
    @Test("AUD-008 the nonisolated render block fills both channels from the core and reports silence")
    func renderBlock() {
        let core = SynthCore(sampleRate: 48_000, seed: 1)
        let block = AudioOutput.makeRenderBlock(core: core)
        let frames = 512
        let list = AudioBufferList.allocate(maximumBuffers: 2)
        let l = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        let r = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        defer {
            l.deallocate()
            r.deallocate()
            free(list.unsafeMutablePointer)
        }
        let bytes = UInt32(frames * MemoryLayout<Float>.size)
        list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: bytes, mData: l)
        list[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: bytes, mData: r)
        var silence = ObjCBool(false)
        var stamp = AudioTimeStamp()
        #expect(block(&silence, &stamp, AVAudioFrameCount(frames), list.unsafeMutablePointer) == noErr)
        #expect(silence.boolValue)
        core.enqueue(CueRequest(cue: .coinIn, pan: 0.5))
        #expect(block(&silence, &stamp, AVAudioFrameCount(frames), list.unsafeMutablePointer) == noErr)
        #expect(!silence.boolValue)
        let left = (0..<frames).map { abs(l[$0]) }.max() ?? 0
        let right = (0..<frames).map { abs(r[$0]) }.max() ?? 0
        #expect(left > 0 && right > left)
        #expect(core.renderCount == 2)
    }

    @Test("AUD-009 before a start the output has no core: requests are refused and counters read zero")
    func beforeStart() {
        let output = AudioOutput(seed: 1)
        #expect(output.core == nil && output.sampleRate == 0)
        #expect(!output.enqueue(CueRequest(cue: .uiTick)))
        #expect(output.renderCount == 0 && output.droppedRequests == 0 && output.activeVoices == 0)
        output.setGains(overall: 0, effects: 1, music: 1)
        output.setMusic(enabled: false, mood: .calm)
        output.stopAll()
        output.stop()
        #expect(!output.isRunning)
    }
}
