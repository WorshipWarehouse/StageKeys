import AVFoundation
import Foundation

@main
struct ExternalGraphTailTests {
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("stagekeys-tail-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let audio = AudioController()
        defer { audio.stop() }
        guard let rack = audio.externalRack else {
            throw NSError(domain: "StageKeysTail", code: 1, userInfo: [NSLocalizedDescriptionKey: "The external instrument rack was unavailable"])
        }
        audio.master(1)
        audio.space(0)

        try audio.prepareOffline()
        let piano = try importTone(folder.appendingPathComponent("Piano.wav"), frequency: 261.626, rack: rack)
        let organ = try importTone(folder.appendingPathComponent("Organ.wav"), frequency: 329.628, rack: rack)
        let pad = try importTone(folder.appendingPathComponent("Pad.wav"), frequency: 392.0, rack: rack)
        let keys = try importTone(folder.appendingPathComponent("Keys.wav"), frequency: 523.251, rack: rack)

        func load(_ sound: ExternalSound, channel: Int) throws {
            var failure: Error?
            rack.load(sound, channel: channel) { if case .failure(let error) = $0 { failure = error } }
            if let failure { throw failure }
            assert(rack.contains(channel))
        }
        func render(_ blocks: Int) throws -> Double {
            var energy = 0.0
            for _ in 0..<blocks {
                let buffer = try audio.offlineBlock()
                for frame in 0..<Int(buffer.frameLength) {
                    let sample = buffer.floatChannelData![0][frame]
                    assert(sample.isFinite)
                    energy += Double(sample * sample)
                }
            }
            return energy
        }
        func reverb() -> AudioEffect {
            var effect = AudioEffect.factoryDefault(kind: 15)
            var values = effect.values
            values[8] = 0
            values[9] = 1
            values[2] = 0.9
            effect.parameters = values
            return effect
        }
        func gain(_ db: Float) -> AudioEffect {
            var effect = AudioEffect()
            effect.kind = 9
            effect.parameters = [db]
            return effect
        }
        func play(_ channel: Int) throws {
            rack.noteOn(channel: channel, key: 60, pitch: 60, velocity: 0.8)
            _ = try render(100)
            rack.noteOff(channel: channel, key: 60)
            _ = try render(80)
        }

        // A changed imported-rack topology must keep its old graph's wet tail.
        try load(piano, channel: 0)
        try rack.configureImported(channel: 0, rack: ImportedRack(effects: [reverb()]), tempo: 120)
        rack.volume(channel: 0, gain: 1, pan: 0)
        try play(0)
        let graphBefore = try render(40)
        try rack.configureImported(channel: 0, rack: ImportedRack(effects: [reverb(), gain(0)]), tempo: 120)
        let graphAfter = try render(40)
        FileHandle.standardError.write(Data("graph tail before/after: \(graphBefore) / \(graphAfter)\n".utf8))
        assert(graphBefore > 1e-8 && graphAfter > 1e-9, "An incompatible rack replacement must retain its reverb tail")
        rack.panic(0)
        _ = try render(8)
        let graphCleared = try render(40)
        assert(graphCleared < graphBefore * 0.0001, "Panic must suppress a retired graph tail")

        // Replacing the instrument itself must keep the old voice's tail, while
        // the new instrument starts on its own dry path.
        try load(piano, channel: 1)
        try rack.configureImported(channel: 1, rack: ImportedRack(effects: [reverb()]), tempo: 120)
        rack.sustain(channel: 1, on: true)
        try play(1)
        rack.sustain(channel: 1, on: false)
        let voiceBefore = try render(40)
        try load(organ, channel: 1)
        let voiceAfter = try render(40)
        FileHandle.standardError.write(Data("voice tail before/after: \(voiceBefore) / \(voiceAfter)\n".utf8))
        assert(voiceBefore > 1e-8 && voiceAfter > 1e-9, "A replaced instrument must retain its old reverb tail")
        rack.panic(1)
        _ = try render(8)
        let voiceCleared = try render(40)
        assert(voiceCleared < voiceBefore * 0.0001, "Panic must suppress a retired voice tail")

        // Stacked reverbs should also survive a topology change.
        try load(pad, channel: 2)
        try rack.configureImported(channel: 2, rack: ImportedRack(effects: [reverb(), reverb()]), tempo: 120)
        try play(2)
        let stackedBefore = try render(40)
        try rack.configureImported(channel: 2, rack: ImportedRack(effects: [reverb(), reverb(), gain(0)]), tempo: 120)
        let stackedAfter = try render(40)
        assert(stackedBefore > 1e-8 && stackedAfter > 1e-9, "Stacked retired reverbs must retain their tail")
        rack.panic(2)

        // Repeated switches are capped; old samplers must not accumulate or be
        // restored on every later transaction.
        for sound in [piano, organ, pad, keys] {
            try load(sound, channel: 2)
            _ = try render(1)
            assert(rack.debugRetiredTailCount <= 2, "Retired graph memory/CPU must be bounded")
        }
        assert(rack.debugRetiredTailCount == 2, "The cap should retain only the two newest tails")
        print("PASS: synthetic piano/organ/pad graph and instrument switches retain reverb tails, Panic clears them, and the tail pool stays bounded")
    }

    private static func importTone(_ url: URL, frequency: Double, rack: ExternalInstrumentRack) throws -> ExternalSound {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000)!
        buffer.frameLength = 48_000
        for frame in 0..<48_000 {
            buffer.floatChannelData![0][frame] = 0.2 * sin(Float(frame) * 2 * .pi * Float(frequency) / 48_000)
        }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        return try rack.importSound(url)
    }
}
