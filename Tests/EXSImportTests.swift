import Foundation
import AVFoundation

/// Local installed EXS fixture only. Usage: test private-scratch exs-file sample-root.
/// Never include the resulting managed library or Apple's samples in app outputs.
@main struct EXSImportTests {
    static func main() throws {
        guard CommandLine.arguments.count == 4 else { print("SKIP EXS test: provide scratch directory, installed EXS, and explicit sample root"); return }
        let scratch = URL(fileURLWithPath: CommandLine.arguments[1])
        let fixture = URL(fileURLWithPath: CommandLine.arguments[2])
        let root = URL(fileURLWithPath: CommandLine.arguments[3])
        let engine = AVAudioEngine()
        let rack = try ExternalInstrumentRack(engine: engine, libraryURL: scratch.appendingPathComponent("library"))
        let sound = try rack.importEXS(fixture, sampleRoot: root)
        assert(sound.kind == .samplerPreset && sound.name == fixture.deletingPathExtension().lastPathComponent)
        let document = try PropertyListSerialization.propertyList(from: Data(contentsOf: rack.libraryURL.appendingPathComponent(sound.fileName!)), options: [], format: nil) as! [String: Any]
        let references = document["file-references"] as! [String: String]
        assert(!references.isEmpty)
        for reference in references.values {
            assert(reference.hasPrefix(rack.libraryURL.path + "/"))
            assert(FileManager.default.fileExists(atPath: reference))
        }
        var failure: Error?
        rack.load(sound, channel: 0) { if case .failure(let error) = $0 { failure = error } }
        if let failure { throw failure }
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
        engine.prepare(); try engine.start()
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512)!
        _ = try engine.renderOffline(512, to: buffer)
        var energy: Float = 0
        for pitch in [36, 48, 60, 72] {
            rack.noteOn(channel: 0, key: pitch, pitch: pitch, velocity: 0.8)
            for _ in 0..<20 {
                _ = try engine.renderOffline(512, to: buffer)
                for frame in 0..<Int(buffer.frameLength) {
                    let sample = buffer.floatChannelData![0][frame]
                    assert(sample.isFinite); energy += abs(sample)
                }
            }
            rack.noteOff(channel: 0, key: pitch, forceRelease: true)
        }
        assert(energy > 0.1, "Relocated EXS samples must render audio")
        rack.panic(); engine.stop()
        // Restricting the root to a known-empty directory must reject references,
        // and must clean up any partially copied assets.
        let empty = scratch.appendingPathComponent("empty-root")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let before = try FileManager.default.contentsOfDirectory(atPath: rack.libraryURL.path)
        do { _ = try rack.importEXS(fixture, sampleRoot: empty); assertionFailure("EXS references escaped selected root") }
        catch {}
        let after = try FileManager.default.contentsOfDirectory(atPath: rack.libraryURL.path)
        assert(Set(before) == Set(after), "Failed EXS import must not leave partial assets")
        print("PASS EXS24 import, \(references.count) relocated sample references, finite offline audio energy \(energy), and selected-root confinement")
    }
}
