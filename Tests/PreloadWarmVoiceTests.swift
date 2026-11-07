import Foundation
import AVFoundation

/// Detached preload voices (#109, D-P1 c): a warmed chain is fully built and
/// loaded, has no output path until it is adopted, and never accumulates more
/// than one entry per channel. These assertions cover construction, adoption
/// and discard; they say nothing about measured load time or memory.
@main struct PreloadWarmVoiceTests {
    static func main() throws {
        let scratch = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let library = scratch.appendingPathComponent("library")
        let engine = AVAudioEngine()
        let rack = try ExternalInstrumentRack(engine: engine, libraryURL: library)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let wave = scratch.appendingPathComponent("warm.wav")
        do {
            let samples = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 24000)!
            samples.frameLength = 24000
            for frame in 0..<24000 { samples.floatChannelData![0][frame] = 0.3 * sin(Float(frame) * 2 * .pi * 261.626 / 48000) }
            let file = try AVAudioFile(forWriting: wave, settings: format.settings)
            try file.write(from: samples)
        }
        let sound = try rack.importSound(wave)

        // A warmed chain is built but not playable, and repeating a warm for the
        // same channel replaces it instead of growing the set.
        try rack.warm(sound, channel: 0)
        assert(rack.warmVoiceCount == 1)
        assert(!rack.contains(0), "A detached chain must not be the playable voice")
        try rack.warm(sound, channel: 0)
        assert(rack.warmVoiceCount == 1, "One detached chain per channel")
        try rack.warm(sound, channel: 1)
        assert(rack.warmVoiceCount == 2, "Separate channels hold separate chains")
        rack.discardWarm(0)
        rack.discardWarm(1)
        assert(rack.warmVoiceCount == 0)

        // Audio Units are refused: no AU warming before #13 (D-P2).
        var refused = false
        do { try rack.warm(ExternalSound(kind: .audioUnit, name: "Test AU"), channel: 0) }
        catch { refused = true }
        assert(refused && rack.warmVoiceCount == 0)

        // Adoption is the only path to playback: the load takes the warm chain,
        // consumes it, and the adopted chain renders the expected signal.
        try rack.warm(sound, channel: 0)
        var loadError: Error?
        rack.load(sound, channel: 0) { if case .failure(let error) = $0 { loadError = error } }
        if let loadError { throw loadError }
        assert(rack.warmVoiceCount == 0, "Adoption consumes the entry")
        assert(rack.contains(0), "The adopted chain becomes the playable voice")
        let stereo = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        try engine.enableManualRenderingMode(.offline, format: stereo, maximumFrameCount: 512)
        engine.prepare(); try engine.start()
        let buffer = AVAudioPCMBuffer(pcmFormat: stereo, frameCapacity: 512)!
        for _ in 0..<10 { _ = try engine.renderOffline(512, to: buffer) }
        rack.noteOn(channel: 0, key: 60, pitch: 60, velocity: 0.8)
        var energy: Float = 0
        for _ in 0..<30 {
            _ = try engine.renderOffline(512, to: buffer)
            for frame in 0..<Int(buffer.frameLength) { energy += abs(buffer.floatChannelData![0][frame]) }
        }
        assert(energy > 0.1, "An adopted warm voice must produce audio")
        rack.noteOff(key: 60); rack.panic()
        rack.discardAllWarmVoices()
        assert(rack.warmVoiceCount == 0)
        print("PASS warm preload voices: detached build, one per channel, AU refusal, adoption and discard")
    }
}
