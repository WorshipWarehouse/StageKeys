import Foundation
import AVFoundation

@main struct SoundMeterTests {
    static func main() throws {
        // The bank is the production tap owner. Exercise the same mixer output
        // point used after each sound's effects, fader and pan.
        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let mixer = AVAudioMixerNode()
        let source = AVAudioSourceNode(format: format) { _, _, frames, list in
            let buffers = UnsafeMutableAudioBufferListPointer(list)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return -1 }
            for frame in 0..<Int(frames) {
                left[frame] = 0.25
                right[frame] = 0.125
            }
            return noErr
        }
        engine.attach(source)
        engine.attach(mixer)
        engine.connect(source, to: mixer, format: format)
        engine.connect(mixer, to: engine.mainMixerNode, format: format)
        let bank = SoundMeterBank()
        bank.attach(mixer, channel: 0)
        bank.setEnabled(true)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
        try engine.start()
        defer { engine.stop() }

        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512)!
        for _ in 0..<8 {
            let status = try engine.renderOffline(512, to: buffer)
            assert(status == .success)
        }
        guard let reading = bank.reading(channel: 0) else {
            fatalError("Enabled per-sound meter did not produce a reading")
        }
        assert(reading.frames > 0 && reading.invalid == 0 && reading.overload == 0)
        assert(abs(reading.peak - 0.25) < 0.001 && abs(reading.rms - 0.197642) < 0.001)

        bank.setEnabled(false)
        assert(bank.reading(channel: 0) == nil, "Disabled meters must not expose a stale reading")
        bank.setEnabled(true)
        for _ in 0..<4 {
            let status = try engine.renderOffline(512, to: buffer)
            assert(status == .success)
        }
        assert((bank.reading(channel: 0)?.frames ?? 0) > 0, "Re-enabling a meter must install its tap again")

        // Older settings have no key; the new option defaults off. Enabling it
        // persists and survives a fresh store, then can be disabled again.
        let store = PerformanceStore()
        assert(!store.showSoundMeters)
        store.showSoundMeters = true
        store.save()
        let restored = PerformanceStore()
        assert(restored.showSoundMeters)
        restored.showSoundMeters = false
        restored.save()
        let legacy = PerformanceStore()
        assert(!legacy.showSoundMeters)

        print("PASS: per-sound meter taps measure only while enabled and the setting persists with an off default")
    }
}
