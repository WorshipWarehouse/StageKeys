import Foundation
import AVFoundation

/// Public-release regression for the repaired streaming, loop and note
/// lifecycle paths. Representative low, middle and high zones (plus one
/// transposed note and one one-shot tail zone) are held well past their source
/// loop/sample boundary and compared with the source waveform, not only by RMS.
@main struct SamplerBoundaryRegressionTests {
    static let sampleRate = 48_000.0
    static let periodFrames = 120                  // 400 Hz at 48 kHz
    static let attackFrames = 4_800                // 0.1 s loud attack
    static let loopFrames = 19_200                 // 0.4 s = 160 whole periods
    static let tailFrames = 4_800                  // post-loop source content
    static let blockSize = 512
    static let second = 48_000

    struct Spec {
        var low: Int
        var high: Int
        var root: Int
        var start: Int
        var end: Int
        var looped: Bool
    }
    struct Held {
        var note: Int
        var label: String
        /// Frequency the played zone must produce at unity, in Hz.
        var expected: Double
        /// Pitches a wrongly selected neighboring zone would produce.
        var neighbors: [Double]
        /// The fixture loop is a whole number of periods, so a correct wrap at
        /// unity playback is continuous.
        var phaseAligned: Bool
    }

    static func makeSource(_ url: URL) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true)!
        let total = attackFrames + loopFrames + tailFrames
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total))!
        pcm.frameLength = AVAudioFrameCount(total)
        let samples = pcm.int16ChannelData![0]
        for frame in 0..<total {
            let amplitude: Double
            let phase: Int
            if frame < attackFrames { amplitude = 12_000; phase = frame }
            else if frame < attackFrames + loopFrames { amplitude = 8_000; phase = frame - attackFrames }
            else { amplitude = 2_000; phase = frame - attackFrames - loopFrames }
            samples[frame] = Int16(amplitude * sin(Double(phase) * 2 * .pi / Double(periodFrames)))
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
              let template = (layer["Zones"] as? [[String: Any]])?.first else {
            throw ExternalInstrumentError.unsupportedFormat
        }
        let loopEnd = attackFrames + loopFrames - 1
        let specs = [
            Spec(low: 48, high: 59, root: 48, start: 0, end: loopEnd, looped: true),
            Spec(low: 60, high: 71, root: 60, start: 0, end: loopEnd, looped: true),
            Spec(low: 72, high: 83, root: 72, start: 0, end: loopEnd, looped: true),
            Spec(low: 84, high: 95, root: 84, start: loopEnd + 1, end: loopEnd + tailFrames, looped: false)
        ]
        var zones: [[String: Any]] = []
        for (index, spec) in specs.enumerated() {
            var zone = template
            zone["ID"] = index
            zone["min key"] = spec.low
            zone["max key"] = spec.high
            zone["root key"] = spec.root
            zone["min vel"] = 1
            zone["max vel"] = 127
            zone["sample start"] = spec.start
            zone["sample end"] = spec.end
            zone["loop enabled"] = spec.looped
            if spec.looped {
                zone["loop start"] = attackFrames
                zone["loop end"] = spec.end
            } else {
                zone.removeValue(forKey: "loop start")
                zone.removeValue(forKey: "loop end")
            }
            zones.append(zone)
        }
        layer["Zones"] = zones
        // Authored-shaped envelope: immediate attack, full sustain and a short
        // release so held level and release timing are comparable.
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

    static func maximumStep(_ samples: ArraySlice<Float>) -> Float {
        zip(samples.dropFirst(), samples).reduce(Float(0)) { max($0, abs($1.0 - $1.1)) }
    }

    /// First render block containing audio, so note-on timing is checked
    /// instead of being inferred from a sustained average.
    static func onsetBlock(_ samples: [Float]) -> Int {
        for block in 0..<(samples.count / blockSize) {
            let range = (block * blockSize)..<((block + 1) * blockSize)
            if samples[range].contains(where: { abs($0) > 0.0001 }) { return block }
        }
        return Int.max
    }

    static func magnitude(_ samples: ArraySlice<Float>, frequency: Double) -> Double {
        guard samples.count > 1 else { return 0 }
        let omega = 2 * Double.pi * frequency / sampleRate
        var real = 0.0, imaginary = 0.0
        for (index, value) in samples.enumerated() {
            let window = 0.5 - 0.5 * cos(2 * Double.pi * Double(index) / Double(samples.count - 1))
            let scaled = Double(value) * window
            real += scaled * cos(omega * Double(index))
            imaginary += scaled * sin(omega * Double(index))
        }
        return hypot(real, imaginary)
    }

    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("loop-fixture.caf")
        try makeSource(source)
        let sourceBytes = try Data(contentsOf: source)
        let preset = root.appendingPathComponent("loop-fixture.aupreset")
        try makePreset(at: preset, source: source)

        // Source reference: the loop region and its own slope, so a rendered
        // boundary step is judged against the waveform, not a magic limit.
        let reader = try AVAudioFile(forReading: source)
        let sourceBuffer = AVAudioPCMBuffer(pcmFormat: reader.processingFormat, frameCapacity: AVAudioFrameCount(reader.length))!
        try reader.read(into: sourceBuffer)
        let sourceSamples = Array(UnsafeBufferPointer(start: sourceBuffer.floatChannelData![0], count: Int(sourceBuffer.frameLength)))
        let sourceLoop = sourceSamples[attackFrames..<(attackFrames + loopFrames)]
        let sourceLoopRMS = rms(sourceLoop), sourceLoopStep = maximumStep(sourceLoop)
        assert(sourceLoopStep > 0.001, "Fixture loop must contain the expected waveform")

        let library = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
            .appendingPathComponent("Imported Sounds", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let installed = library.appendingPathComponent(preset.lastPathComponent)
        try Data(contentsOf: preset).write(to: installed, options: .atomic)

        var layer = Layer(name: "Loop boundary fixture", instrument: -1, gain: 1)
        layer.external = ExternalSound(kind: .samplerPreset, name: layer.name, fileName: installed.lastPathComponent)
        let audio = AudioController()
        try audio.prepareOffline()
        defer { audio.stop() }
        audio.modulation(0,value:0) // Keep the phase-aligned fixture free of Sampler CC1 vibrato.
        audio.configure(0, layer)
        audio.master(1)
        audio.space(0)

        // Hold each representative zone for six seconds: fifteen loop wraps and
        // far beyond the 0.5 s source region.
        let holdBlocks = (6 * second + blockSize - 1) / blockSize
        let notes = [
            Held(note: 48, label: "low root", expected: 400, neighbors: [200, 800], phaseAligned: true),
            Held(note: 60, label: "middle root", expected: 400, neighbors: [200, 800], phaseAligned: true),
            Held(note: 72, label: "high root", expected: 400, neighbors: [200, 800], phaseAligned: true),
            Held(note: 78, label: "transposed high", expected: 400 * pow(2, 6.0 / 12), neighbors: [400, 800], phaseAligned: false)
        ]
        var rootReferenceGain:Double?
        for entry in notes {
            audio.panic()
            _ = try samples(audio, blocks: 8)
            audio.noteOn(key: entry.note, pitch: entry.note, instrument: -1, layer: 0, velocity: 100.0 / 127)
            let held = try samples(audio, blocks: holdBlocks)
            let onset = onsetBlock(held)
            assert(onset <= 1, "\(entry.label): note-on reached audio only after \(onset) render blocks")

            let perSecond = (1..<6).map { rms(held[($0 * second)..<(($0 + 1) * second)]) }
            let quietest = perSecond.min()!, loudest = perSecond.max()!
            assert(quietest > 0.001, "\(entry.label): held note became silent before release (truncated decay)")
            assert(loudest / quietest < 1.1,
                   "\(entry.label): held level moved \(20 * log10(loudest / quietest)) dB; a retrigger or truncated decay is present")

            let gain = perSecond[0] / sourceLoopRMS
            assert(gain.isFinite && gain>0)
            // AUSampler's default velocity law/normalization is host-defined.
            // Gate equal authored root zones against each other, rather than
            // an uncalibrated absolute source-to-host gain assumption.
            if entry.phaseAligned {
                if let reference=rootReferenceGain {assert(abs(gain/reference-1)<0.03,"Equal authored root zones must retain equal gain")}
                else {rootReferenceGain=gain}
            }
            if entry.phaseAligned {
                let heldStep = maximumStep(held[(second)..<(6 * second)])
                assert(heldStep <= sourceLoopStep * Float(gain) * 1.3,
                       "\(entry.label): loop-boundary discontinuity \(heldStep) exceeds source \(sourceLoopStep * Float(gain))")
            }

            let tail = held[(5 * second)..<(6 * second)]
            let fundamental = magnitude(tail, frequency: entry.expected)
            let strongestNeighbor = entry.neighbors.map { magnitude(tail, frequency: $0) }.max() ?? 0
            assert(fundamental > 0.001, "\(entry.label): held tail lost its fundamental")
            assert(strongestNeighbor < fundamental * 0.2,
                   "\(entry.label): tail contains a neighboring-zone pitch (\(strongestNeighbor) vs \(fundamental))")

            let heldPeak = peak(held[(second)..<(6 * second)])
            assert(heldPeak < 0.95, "\(entry.label): runaway voice level \(heldPeak)")
            audio.noteOff(key: entry.note, channel: 0)
            let released = try samples(audio, blocks: (second + blockSize - 1) / blockSize)
            let early = peak(released[0..<960])
            let late = peak(released[(second - 4_800)..<second])
            assert(early > heldPeak * 0.05, "\(entry.label): release cut the note off instead of decaying")
            assert(late < heldPeak * 0.02, "\(entry.label): release tail \(late) did not decay")
            print("Held \(entry.label) MIDI \(entry.note): onset block \(onset), level spread \(20 * log10(loudest / quietest)) dB, peak \(heldPeak), release \(late)")
        }

        // One-shot tail zone: the authored 0.1 s must sound fully and then stop;
        // neither an early truncation nor a looping/hung voice is acceptable.
        audio.panic()
        _ = try samples(audio, blocks: 8)
        audio.noteOn(key: 84, pitch: 84, instrument: -1, layer: 0, velocity: 100.0 / 127)
        let oneShot = try samples(audio, blocks: (second + blockSize - 1) / blockSize)
        assert(onsetBlock(oneShot) <= 1, "One-shot zone started late")
        let oneShotStart = peak(oneShot[0..<3_840])
        let oneShotEnd = peak(oneShot[(24_000 + 9_600)..<second])
        assert(oneShotStart > 0.01, "One-shot zone did not sound")
        assert(oneShotEnd < 0.005, "One-shot zone kept sounding past its sample end: \(oneShotEnd)")
        audio.noteOff(key: 84, channel: 0)
        print("One-shot zone: start peak \(oneShotStart), after sample end \(oneShotEnd)")

        // Out-of-range region offsets are rejected with an error, never a
        // Data.subdata exception that would terminate the process.
        do {
            _ = try SamplerSplitRegions.assemble(source, attack: 0..<999_999, loop: 0..<1)
            assertionFailure("Out-of-range attack region was accepted")
        } catch {}
        do {
            _ = try SamplerSplitRegions.assemble(source, attack: 0..<1, loop: 0..<9_999_999)
            assertionFailure("Out-of-range loop region was accepted")
        } catch {}

        let retained = try Data(contentsOf: source)
        assert(retained == sourceBytes, "Original sample bytes must be preserved")
        print("PASS: representative zones held beyond their loop/sample boundary; note-on timing, level, pitch, release and source-byte retention")
    }
}
