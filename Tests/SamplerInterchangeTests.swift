import Foundation
import AVFoundation

@main struct SamplerInterchangeTests {
    static func main() throws {
        let scratch = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let library = scratch.appendingPathComponent("library")
        let engine = AVAudioEngine()
        let rack = try ExternalInstrumentRack(engine: engine, libraryURL: library)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let wave = scratch.appendingPathComponent("source.wav")
        do {
            let samples = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000)!
            samples.frameLength = 48000
            for frame in 0..<48000 { samples.floatChannelData![0][frame] = 0.3 * sin(Float(frame) * 2 * .pi * 261.626 / 48000) }
            let file = try AVAudioFile(forWriting: wave, settings: format.settings)
            try file.write(from: samples)
        }
        let sound = try rack.importSound(wave)
        var loadError: Error?
        rack.load(sound, channel: 0) { if case .failure(let error) = $0 { loadError = error } }
        if let loadError { throw loadError }
        let original = library.appendingPathComponent("Original.aupreset")
        try rack.stateData(channel: 0)!.write(to: original)
        let presetSound = try rack.importPreset(original, sampleRoot: library)
        let exported = try SamplerInterchange.exportPreset(presetSound, libraryURL: library, to: scratch.appendingPathComponent("Exported"))
        let originalState = try PropertyListSerialization.propertyList(from: Data(contentsOf: library.appendingPathComponent(presetSound.fileName!)), options: [], format: nil) as! NSDictionary
        let exportedState = try PropertyListSerialization.propertyList(from: Data(contentsOf: exported), options: [], format: nil) as! NSDictionary
        assert(originalState["Instrument"] as? NSDictionary == exportedState["Instrument"] as? NSDictionary)
        let refs = exportedState["file-references"] as! [String: String]
        assert(refs.values.allSatisfy { $0.hasPrefix(exported.deletingLastPathComponent().appendingPathComponent("Samples").path + "/") && !$0.contains("..") })
        do { _ = try SamplerInterchange.exportPreset(presetSound, libraryURL: library, to: exported.deletingLastPathComponent()); assertionFailure("Existing folder overwritten") }
        catch SamplerInterchangeError.destinationExists {}
        let copiedSamples = try FileManager.default.contentsOfDirectory(atPath: exported.deletingLastPathComponent().appendingPathComponent("Samples").path)
        assert(copiedSamples.count == 1)
        var unsafeState = originalState as! [String: Any]
        unsafeState["file-references"] = ["Sample:outside": wave.path]
        let unsafePreset = library.appendingPathComponent("Unsafe.aupreset")
        try PropertyListSerialization.data(fromPropertyList: unsafeState, format: .xml, options: 0).write(to: unsafePreset)
        let unsafeSound = ExternalSound(kind: .samplerPreset, name: "Unsafe", fileName: unsafePreset.lastPathComponent)
        let refused = scratch.appendingPathComponent("Refused")
        do { _ = try SamplerInterchange.exportPreset(unsafeSound, libraryURL: library, to: refused); assertionFailure("External sample reference accepted") }
        catch SamplerInterchangeError.unsafePath {}
        assert(!FileManager.default.fileExists(atPath: refused.path))
        let sampleLink = library.appendingPathComponent("escape.wav")
        try FileManager.default.createSymbolicLink(at: sampleLink, withDestinationURL: wave)
        unsafeState["file-references"] = ["Sample:escape": sampleLink.path]
        try PropertyListSerialization.data(fromPropertyList: unsafeState, format: .xml, options: 0).write(to: unsafePreset)
        do { _ = try SamplerInterchange.exportPreset(unsafeSound, libraryURL: library, to: refused); assertionFailure("Escaping sample symlink accepted") }
        catch SamplerInterchangeError.unsafePath {}
        assert(!FileManager.default.fileExists(atPath: refused.path))
        let moved = scratch.appendingPathComponent("Moved")
        try FileManager.default.moveItem(at: exported.deletingLastPathComponent(), to: moved)
        let movedPreset = moved.appendingPathComponent("Instrument.aupreset")
        try SamplerInterchange.relinkPreset(at: movedPreset)
        // Verify Apple's loader directly, independently of StageKeys import.
        let directEngine = AVAudioEngine()
        let sampler = AVAudioUnitSampler()
        directEngine.attach(sampler)
        directEngine.connect(sampler, to: directEngine.mainMixerNode, format: nil)
        try sampler.loadInstrument(at: movedPreset)
        let stereo = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        try directEngine.enableManualRenderingMode(.offline, format: stereo, maximumFrameCount: 512)
        directEngine.prepare(); try directEngine.start()
        let buffer = AVAudioPCMBuffer(pcmFormat: stereo, frameCapacity: 512)!
        _ = try directEngine.renderOffline(512, to: buffer)
        sampler.startNote(60, withVelocity: 100, onChannel: 0)
        var energy: Float = 0
        for _ in 0..<30 {
            _ = try directEngine.renderOffline(512, to: buffer)
            for frame in 0..<Int(buffer.frameLength) { energy += abs(buffer.floatChannelData![0][frame]) }
        }
        assert(energy > 0.1, "Apple sampler must play the moved portable bundle")
        directEngine.stop()
        let movedSamples = moved.appendingPathComponent("Samples")
        let externalSamples = scratch.appendingPathComponent("OutsideSamples")
        try FileManager.default.moveItem(at: movedSamples, to: externalSamples)
        try FileManager.default.createSymbolicLink(at: movedSamples, withDestinationURL: externalSamples)
        do { _ = try SamplerInterchange.relinkPreset(at: movedPreset); assertionFailure("Escaping Samples directory symlink accepted") }
        catch SamplerInterchangeError.unsafePath {}
        try FileManager.default.removeItem(at: movedSamples)
        try FileManager.default.moveItem(at: externalSamples, to: movedSamples)

        print("PASS sampler bundle preserves Instrument, refuses overwrite, moves, relinks and renders directly in Apple sampler: \(energy)")
    }
}
