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
        func frequencyEnergies(_ frequencies: [Double], blocks: Int) throws -> [Double] {
            var cosine = Array(repeating: 0.0, count: frequencies.count)
            var sine = Array(repeating: 0.0, count: frequencies.count)
            var sampleCount = 0
            for _ in 0..<blocks {
                let buffer = try audio.offlineBlock()
                let rate = buffer.format.sampleRate
                for frame in 0..<Int(buffer.frameLength) {
                    let sample = Double(buffer.floatChannelData![0][frame])
                    for index in frequencies.indices {
                        let phase = 2 * Double.pi * frequencies[index] * Double(sampleCount) / rate
                        cosine[index] += sample * cos(phase)
                        sine[index] += sample * sin(phase)
                    }
                    sampleCount += 1
                }
            }
            return frequencies.indices.map {
                (cosine[$0] * cosine[$0] + sine[$0] * sine[$0]) / Double(sampleCount * sampleCount)
            }
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

        // Establish a matched dry reference for the replacement's generated pitch.
        try load(organ, channel: 4)
        rack.volume(channel: 4, gain: 1, pan: 0)
        rack.noteOn(channel: 4, key: 60, pitch: 60, velocity: 0.8)
        let dryOrganEnergy = try frequencyEnergies([329.628], blocks: 40)[0]
        rack.noteOff(channel: 4, key: 60)
        _ = try render(80)

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
        rack.noteOn(channel: 1, key: 60, pitch: 60, velocity: 0.8, sourceID: 42)
        let replacementEnergies = try frequencyEnergies([329.628, 261.626], blocks: 40)
        let newOrganEnergy = replacementEnergies[0]
        let retiredPianoEnergy = replacementEnergies[1]
        assert(rack.debugNoteIntentCount(1) == 1, "The replacement note must have one active owner")
        assert(retiredPianoEnergy > 1e-12, "The old instrument's generated tail must still be audible during the replacement note")
        assert(newOrganEnergy > dryOrganEnergy * 0.5 && newOrganEnergy < dryOrganEnergy * 2,
               "The replacement must render at the matched dry-reference level rather than silence or double its note")
        assert(newOrganEnergy > retiredPianoEnergy * 4,
               "The replacement's pitch must dominate while the retired voice tail remains connected")
        rack.noteOff(channel: 1, key: 60)
        _ = try render(40)
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
        var nodeCountBound: Int?
        for (index, sound) in [piano, organ, pad, keys].enumerated() {
            try load(sound, channel: 2)
            _ = try render(1)
            assert(rack.debugRetiredTailCount <= 2, "Retired graph memory/CPU must be bounded")
            if index >= 2 {
                let nodeCount = rack.debugOwnedNodeCount
                if let nodeCountBound {
                    assert(nodeCount <= nodeCountBound, "Repeated same-size replacements must not accumulate graph nodes")
                } else {
                    nodeCountBound = nodeCount
                }
            }
        }
        assert(rack.debugRetiredTailCount == 2, "The cap should retain only the two newest tails")
        // Start with clean slots, then create one real wet tail per channel.
        rack.panic()
        try rack.withGraphChanges {
            try rack.remove(0); try rack.remove(1); try rack.remove(2)
        }
        rack.panic()
        try load(keys, channel: 2)
        for channel in [0,1] {
            try load(piano, channel: channel)
            try rack.configureImported(channel: channel, rack: ImportedRack(effects: [reverb()]), tempo: 120)
            rack.volume(channel: channel, gain: 1, pan: 0)
            try play(channel)
            try rack.configureImported(channel: channel, rack: ImportedRack(effects: [reverb(),gain(0)]), tempo: 120)
        }
        assert(rack.debugRetiredTailCount == 2)
        assert(Set(rack.debugRetiredTailStates.map(\.channel)) == Set([0,1]))
        rack.panic(0, preserveEffectTails: true)
        assert(rack.debugRetiredTailStates.allSatisfy{!$0.silent && $0.gain > 0})
        let originalUnit = rack.unit(channel: 2)!
        let originalNodes = rack.debugOwnedNodeCount
        rack.volume(channel: 2, gain: 0.2, pan: 0)
        rack.noteOn(channel: 2, key: 67, pitch: 67, velocity: 0.7, sourceID: 77)
        do {
            try rack.withGraphChanges {
                // Adding this third tail evicts channel 0 before Panic. Rollback
                // must still remember the later channel-specific silence intent.
                try rack.remove(2)
                assert(!rack.debugRetiredTailStates.contains{$0.channel == 0})
                rack.panic(0)
                throw NSError(domain: "StageKeysGeneratedTailFailure", code: 941)
            }
            assertionFailure("Expected generated graph edit failure")
        } catch { assert((error as NSError).code == 941) }
        assert(rack.lastGraphFailure?.rollbackSucceeded == true && rack.unit(channel: 2) === originalUnit)
        assert(rack.debugOwnedNodeCount == originalNodes && rack.debugRetiredTailCount == 2)
        let restoredMuted = rack.debugRetiredTailStates.filter{$0.channel == 0}
        assert(restoredMuted.count == 1 && restoredMuted.allSatisfy{$0.silent && $0.gain == 0}, "Rollback must not revive a tail silenced after its snapshot")
        assert(rack.debugRetiredTailStates.filter{$0.channel == 1}.allSatisfy{!$0.silent && $0.gain > 0}, "Channel Panic must preserve unrelated tail intent")
        rack.panic(1) // Exclude the unrelated wet tail from the held-note audio check.
        assert(rack.debugNoteIntentCount(2) == 1 && (try! render(20)) > 0.000001, "An unrelated held instrument must recover and render")

        // Forward completion also restores mixer settings captured before the
        // old voice became a tail; it must not undo an in-transaction Panic.
        rack.panic()
        try load(piano, channel: 3)
        try rack.configureImported(channel: 3, rack: ImportedRack(effects: [reverb()]), tempo: 120)
        rack.volume(channel: 3, gain: 1, pan: 0)
        try play(3)
        try rack.withGraphChanges {
            try load(organ, channel: 3)
            rack.panic(3)
        }
        let forwardMuted = rack.debugRetiredTailStates.filter{$0.channel == 3}
        assert(!forwardMuted.isEmpty && forwardMuted.allSatisfy{$0.silent && $0.gain == 0}, "Graph completion must not restore a muted tail's gain")
        _ = try render(8)
        assert(try! render(40) < 0.000001)
        print("PASS: new voice renders over retired tail, generated tail cap, Panic rollback/forward completion, and retained unrelated notes")
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
