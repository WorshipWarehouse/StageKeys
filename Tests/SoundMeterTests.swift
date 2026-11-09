import Foundation
import AVFoundation
import Darwin

@main struct SoundMeterTests {
    static func main() throws {
        // The bank is the production tap owner. Exercise the same topology as a
        // sound: fader/pan mixer, then a unity-gain mixer whose output is tapped.
        // A tap on the fader mixer itself observes audio before outputVolume.
        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let mixer = AVAudioMixerNode()
        let meterMixer = AVAudioMixerNode()
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
        engine.attach(meterMixer)
        mixer.outputVolume = 1
        mixer.pan = 0
        meterMixer.outputVolume = 1
        meterMixer.pan = 0
        engine.connect(source, to: mixer, format: format)
        engine.connect(mixer, to: meterMixer, format: format)
        engine.connect(meterMixer, to: engine.mainMixerNode, format: format)
        let bank = SoundMeterBank()
        bank.attach(meterMixer, channel: 0)
        bank.setEnabled(true)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
        try engine.start()
        defer { engine.stop() }

        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512)!
        for _ in 0..<16 {
            let status = try engine.renderOffline(512, to: buffer)
            assert(status == .success)
        }
        guard let reading = bank.reading(channel: 0) else {
            fatalError("Enabled per-sound meter did not produce a reading")
        }
        print("meter reading: peak=\(reading.peak) rms=\(reading.rms) frames=\(reading.frames)")
        assert(reading.frames > 0 && reading.invalid == 0 && reading.overload == 0)
        // AVAudioMixerNode may apply its own unity-gain/format conversion. Check
        // non-silent finite energy here; OutputMeterTests covers DSP exactness.
        assert(reading.peak > 0 && reading.rms > 0 && reading.rms <= reading.peak + 0.001,
               "Meter must report non-silent finite sample energy")
        let baselinePeak = reading.peak
        let baselineRMS = reading.rms

        bank.setEnabled(false)
        assert(bank.reading(channel: 0) == nil, "Disabled meters must not expose a stale reading")
        // Offline manual rendering does not apply a running mixer's
        // outputVolume change to the next render pass. Bind the half fader at
        // engine start so this checks the meter's signal point, not an offline
        // rendering limitation. The tap is installed again after disabling.
        engine.stop()
        mixer.outputVolume = 0.5
        bank.setEnabled(true)
        try engine.start()
        for _ in 0..<16 {
            let status = try engine.renderOffline(512, to: buffer)
            assert(status == .success)
        }
        guard let half = bank.reading(channel: 0) else {
            fatalError("Re-enabled per-sound meter did not produce a reading")
        }
        print("half-fader reading: peak=\(half.peak) rms=\(half.rms) frames=\(half.frames)")
        fflush(stdout)
        assert(half.frames > 0 && half.invalid == 0 && half.overload == 0)
        assert(abs(half.peak - baselinePeak * 0.5) < 0.01,
               "The tap must follow the channel fader")
        assert(abs(half.rms - baselineRMS * 0.5) < 0.01,
               "The tap must follow the channel fader")

        // Older settings have no key; the new option defaults off. Enabling it
        // persists and survives a fresh store, then can be disabled again.
        let store = PerformanceStore()
        assert(!store.showSoundMeters)
        store.showSoundMeters = true
        store.save()
        let restored = PerformanceStore()
        assert(restored.showSoundMeters)
        restored.setlist=TestFixtures.setlist()
        try restored.audio.prepareOffline()
        restored.start()
        assert(restored.soundMeter(0) != nil,"A restored enabled setting must install meters when audio starts")
        restored.stopAudio()
        restored.showSoundMeters = false
        restored.save()
        let legacy = PerformanceStore()
        assert(!legacy.showSoundMeters)

        print("PASS: per-sound meter taps measure only while enabled and the setting persists with an off default")
    }
}
