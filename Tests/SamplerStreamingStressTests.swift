import Foundation
import AVFoundation
#if os(macOS)
import Darwin
#endif

/// Stress regression for the streaming/preload gate. A loaded converted
/// instrument must keep rendering when its sample storage goes away, missing
/// preset/sample files must be reported instead of playing stale audio, and
/// repeated rapid patch changes must not leak memory or leave stuck voices.
@main struct SamplerStreamingStressTests {
    static let sampleRate = 48_000.0
    static let toneFrames = 24_000                  // 0.5 s
    static let blockSize = 512

    static func makeTone(_ url: URL, frequency: Double) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true)!
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(toneFrames))!
        pcm.frameLength = AVAudioFrameCount(toneFrames)
        let samples = pcm.int16ChannelData![0]
        for frame in 0..<toneFrames {
            samples[frame] = Int16(10_000 * sin(Double(frame) * 2 * .pi * frequency / sampleRate))
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true)
        try file.write(from: pcm)
    }

    static func makePreset(at presetURL: URL, source: URL) throws {
        let sampler = AVAudioUnitSampler()
        try sampler.loadAudioFiles(at: [source])
        guard var state = sampler.auAudioUnit.fullStateForDocument,
              var instrument = state["Instrument"] as? [String: Any],
              var layer = (instrument["Layers"] as? [[String: Any]])?.first,
              var zone = (layer["Zones"] as? [[String: Any]])?.first else {
            throw ExternalInstrumentError.unsupportedFormat
        }
        zone["min key"] = 0
        zone["max key"] = 127
        zone["root key"] = 60
        zone["min vel"] = 1
        zone["max vel"] = 127
        zone["sample start"] = 0
        zone["sample end"] = toneFrames - 1
        zone["loop enabled"] = true
        zone["loop start"] = 0
        zone["loop end"] = toneFrames - 1
        layer["Zones"] = [zone]
        EXSNative.applyEnvelope(.init(attack: 0.001, lowVelocityAttack: 0.001, decay: 10, sustain: 1, release: 0.05),
                                group: Array(repeating: UInt8(0), count: 120), to: &layer)
        instrument["Layers"] = [layer]
        state["Instrument"] = instrument
        try PropertyListSerialization.data(fromPropertyList: state, format: .xml, options: 0).write(to: presetURL, options: .atomic)
    }

    static func samples(_ audio: AudioController, blocks count: Int) throws -> [Float] {
        var output: [Float] = []
        output.reserveCapacity(count * blockSize)
        for _ in 0..<count {
            let buffer = try audio.offlineBlock()
            let channel = buffer.floatChannelData![0]
            for i in 0..<Int(buffer.frameLength) {
                assert(channel[i].isFinite)
                output.append(channel[i])
            }
        }
        return output
    }

    static func rms(_ samples: ArraySlice<Float>) -> Double {
        guard !samples.isEmpty else { return 0 }
        return sqrt(samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(samples.count))
    }

    static func peak(_ samples: ArraySlice<Float>) -> Float {
        samples.reduce(Float(0)) { max($0, abs($1)) }
    }

    #if os(macOS)
    /// Resident size, used only to catch gross growth across load/reload cycles.
    static func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? info.resident_size : 0
    }
    #endif

    static func main() throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let toneA = work.appendingPathComponent("tone-a.caf"), toneB = work.appendingPathComponent("tone-b.caf")
        let toneC = work.appendingPathComponent("tone-c.caf")
        try makeTone(toneA, frequency: 400)
        try makeTone(toneB, frequency: 600)
        try makeTone(toneC, frequency: 500)
        let toneABytes = try Data(contentsOf: toneA)

        let library = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
            .appendingPathComponent("Imported Sounds", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let presetA = library.appendingPathComponent("stress-a.aupreset")
        let presetB = library.appendingPathComponent("stress-b.aupreset")
        let presetC = library.appendingPathComponent("stress-c.aupreset")
        try makePreset(at: presetA, source: toneA)
        try makePreset(at: presetB, source: toneB)
        try makePreset(at: presetC, source: toneC)
        let presetABytes = try Data(contentsOf: presetA)

        func layer(_ name: String, _ file: URL) -> Layer {
            var layer = Layer(name: name, instrument: -1, gain: 1)
            layer.external = ExternalSound(kind: .samplerPreset, name: name, fileName: file.lastPathComponent)
            return layer
        }
        let layerA = layer("Stress A", presetA), layerB = layer("Stress B", presetB), layerC = layer("Stress C", presetC)

        let audio = AudioController()
        try audio.prepareOffline()
        defer { audio.stop() }
        audio.modulation(0,value:0)
        audio.configure(0, layerA)
        audio.master(1)
        audio.space(0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        // 1. The load must not leave a render-time file dependency. Move the
        // sample out of reach while the note is held; resident playback keeps
        // going, a streaming read would stall or drop out.
        audio.noteOn(key: 60, pitch: 60, instrument: -1, layer: 0, velocity: 100.0 / 127)
        let baseline = try samples(audio, blocks: 40)
        let parked = work.appendingPathComponent("parked-a.caf")
        try FileManager.default.moveItem(at: toneA, to: parked)
        let continued = try samples(audio, blocks: 200)
        try FileManager.default.moveItem(at: parked, to: toneA)
        let baselineRMS = rms(baseline[0..<baseline.count]), continuedRMS = rms(continued[0..<continued.count])
        assert(continuedRMS > baselineRMS * 0.7,
               "Held note lost level when its sample file became unavailable: \(20 * log10(continuedRMS / baselineRMS)) dB")
        assert(peak(continued[0..<continued.count]) < 0.95, "Held note ran away while storage was unavailable")
        audio.noteOff(key: 60, channel: 0)
        audio.panic()
        print("Offline-storage hold: baseline RMS \(baselineRMS), with sample moved \(continuedRMS)")

        // 2. Rapid patch changes with overlapping release tails. Every switch
        // tears down and reloads the imported instrument branch.
        var errors: [String] = []
        audio.onError = { errors.append($0) }
        for cycle in 0..<24 {
            let current = cycle.isMultiple(of: 2) ? layerA : layerB
            audio.configure(0, current)
            audio.sustain(cycle.isMultiple(of: 3), layers: [current])
            audio.noteOn(key: 60, pitch: 60, instrument: -1, layer: 0, velocity: 0.8)
            let hit = try samples(audio, blocks: 4)
            assert(peak(hit[0..<hit.count]) > 0.001, "Cycle \(cycle): rapid patch change left the channel silent")
            // Release rather than panic so the previous tail can overlap.
            audio.noteOff(key: 60, channel: 0)
        }
        audio.sustain(false, layers: [layerA])
        assert(errors.isEmpty, "Rapid patch changes reported errors: \(errors)")
        audio.panic()
        _ = try samples(audio, blocks: 8) // Drain already-rendered host buffers and the short release.
        let settled = try samples(audio, blocks: 32)
        assert(peak(settled[0..<settled.count]) < 0.001, "Voices kept sounding after Panic")

        // 3. A missing preset must be reported and must not keep stale audio.
        try FileManager.default.removeItem(at: presetB)
        errors.removeAll()
        audio.configure(0, layerB)
        assert(!errors.isEmpty, "Missing preset file was not reported")
        audio.noteOn(key: 60, pitch: 60, instrument: -1, layer: 0, velocity: 0.8)
        let missingPreset = try samples(audio, blocks: 16)
        assert(peak(missingPreset[0..<missingPreset.count]) < 0.001, "Missing preset still produced audio")
        audio.noteOff(key: 60, channel: 0)

        // 4. A preset whose samples are offline must be rejected at load.
        try FileManager.default.removeItem(at: toneC)
        errors.removeAll()
        audio.configure(0, layerC)
        assert(!errors.isEmpty, "Preset with missing samples was not reported")
        assert(errors.contains { $0.lowercased().contains("missing") }, "Missing-sample error was not actionable: \(errors)")

        // 5. Repeated load/reload must not grow memory without bound.
        #if os(macOS)
        audio.configure(0, layerA)
        let before = residentBytes()
        for _ in 0..<20 {
            audio.configure(0, Layer.empty())
            audio.configure(0, layerA)
        }
        let after = residentBytes()
        let growth = Int64(after) - Int64(before)
        assert(growth < 128 * 1024 * 1024, "Load/reload growth \(growth) bytes exceeds the 128 MB bound")
        print("Resident growth across 20 load/reload cycles: \(growth) bytes")
        #endif
        audio.configure(0, layerA)
        audio.noteOn(key: 60, pitch: 60, instrument: -1, layer: 0, velocity: 0.8)
        let recovered = try samples(audio, blocks: 16)
        assert(peak(recovered[0..<recovered.count]) > 0.001, "Channel did not recover after the stress sequence")
        audio.noteOff(key: 60, channel: 0)

        let retainedTone = try Data(contentsOf: toneA), retainedPreset = try Data(contentsOf: presetA)
        assert(retainedTone == toneABytes, "Original sample bytes must be preserved")
        assert(retainedPreset == presetABytes, "Managed preset must not be rewritten by playback")
        print("PASS: offline storage hold, rapid patch changes with overlapping tails, missing preset/sample reporting, bounded reload growth")
    }
}
