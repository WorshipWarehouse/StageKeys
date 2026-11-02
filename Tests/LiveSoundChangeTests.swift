import Foundation
import AVFoundation

@main struct LiveSoundChangeTests {
    static func main() throws {
        let store = PerformanceStore()
        store.setlist = TestFixtures.setlist()
        try store.audio.prepareOffline()
        defer { store.stopAudio() }
        store.start()
        store.audio.space(0)
        store.captureSnapshot(0)
        store.save()
        let original = store.patch.layers[0]
        let oldUnit = store.audio.externalRack!.unit(channel: 0)!
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let savedState = try encoder.encode(store.setlist)
        let savedSnapshot = store.activeSnapshot
        let dataRoot = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        let session = dataRoot.appendingPathComponent("setlist.json")
        let savedBytes = try Data(contentsOf: session)

        func energy(_ blocks: Int = 20) throws -> Double {
            var total = 0.0
            for _ in 0..<blocks {
                let buffer = try store.audio.offlineBlock()
                for channel in 0..<2 {
                    for frame in 0..<Int(buffer.frameLength) {
                        let sample = buffer.floatChannelData![channel][frame]
                        assert(sample.isFinite)
                        total += Double(sample * sample)
                    }
                }
            }
            return total
        }
        store.noteOn(60)
        store.setSustain(true)
        _ = try energy()
        let before = try energy()
        assert(before > 0.01)
        let generation = store.audio.externalRack!.graphGeneration
        let otherUnit = store.audio.externalRack!.unit(channel: 1)!

        var missing = original
        missing.name = "Missing replacement"
        missing.external!.fileName = "does-not-exist.wav"
        missing.pan = 1; missing.gain = 0
        store.commitLayer(0, missing)
        assert(store.patch.layers[0] == original, "A rejected replacement must retain the previous layer and fader")
        assert(store.audio.externalRack!.unit(channel: 0) === oldUnit, "A failed prepare must not remove the playing instrument")
        assert(store.held.contains(60), "A failed prepare must not panic held notes")
        assert(store.sustain && store.audio.externalRack!.unit(channel: 1) === otherUnit)
        assert(store.activeSnapshot == savedSnapshot)
        assert(try! encoder.encode(store.setlist) == savedState, "Rejected replacement must not rewrite snapshot parameters")
        assert(try! Data(contentsOf: session) == savedBytes, "Rejected replacement must not autosave")
        let after = try energy()
        assert(after > before * 0.8 && after < before * 1.2, "The previously held sound must continue at its original level")
        assert(store.audio.externalRack!.graphGeneration == generation, "Rejected preparation must not stop or rebuild the graph")
        assert(store.audio.lastChangeFailure?.phase == .prepareSound)
        assert(store.audio.lastChangeFailure?.previousSoundRetained == true)
        assert(store.message?.contains("previous sound") == true)
        // Direct controller callers also reject preparation before touching the
        // channel's gain/pan or the cached identity used by the next attempt.
        store.audio.configure(0, missing)
        assert(store.audio.externalRack!.unit(channel: 0) === oldUnit)
        assert(store.audio.externalRack!.graphGeneration == generation)
        assert(try! energy() > before * 0.8)

        // Inject the reported numeric code before graph mutation. This does not
        // reproduce the user's real -1 trigger or prove post-mutation rollback.
        store.audio.debugSoundPreparationFailure = NSError(domain: "com.apple.coreaudio.avfaudio", code: -1,
            userInfo: [NSLocalizedDescriptionKey: "/private/PRIVATE-SOURCE PluginState=SECRET"])
        let replacement = TestFixtures.layer(1, gain: 0.1)
        store.commitLayer(0, replacement)
        assert(store.audio.lastChangeFailure?.errorCode == -1)
        assert(store.audio.lastChangeFailure?.soundSlot == 1)
        assert(store.audio.lastChangeFailure?.graphGeneration == generation)
        assert(store.patch.layers[0] == original && store.held.contains(60))
        assert(store.audio.externalRack!.unit(channel: 0) === oldUnit)
        assert(try! encoder.encode(store.setlist) == savedState)
        assert(try! Data(contentsOf: session) == savedBytes)
        assert(try! energy() > before * 0.8)
        assert(store.message?.contains("PRIVATE-SOURCE") == false)
        store.audio.debugSoundPreparationFailure = nil

        // A preset with known missing original samples is also rejected before
        // the old voice is panicked or detached, even though its own file exists.
        let brokenPreset = store.audio.externalRack!.libraryURL.appendingPathComponent("missing-samples.aupreset")
        let preset: [String: Any] = ["file-references": ["Sample:0": dataRoot.appendingPathComponent("PRIVATE-MISSING.wav").path]]
        try PropertyListSerialization.data(fromPropertyList: preset, format: .xml, options: 0).write(to: brokenPreset)
        var unavailable = original
        unavailable.external = ExternalSound(kind: .samplerPreset, name: "Unavailable preset", fileName: brokenPreset.lastPathComponent)
        store.commitLayer(0, unavailable)
        assert(store.patch.layers[0] == original && store.held.contains(60))
        assert(store.audio.externalRack!.unit(channel: 0) === oldUnit)
        assert(store.audio.externalRack!.graphGeneration == generation)
        assert(try! energy() > before * 0.8)
        assert(store.message?.contains("PRIVATE-MISSING") == false)
        assert(store.audio.running)
        store.noteOff(60)
        store.setSustain(false)

        // Preparation failure must not poison identity caches: after correction
        // the next valid sound selection commits and remains playable.
        store.commitLayer(0, replacement)
        assert(store.patch.layers[0] == replacement)
        assert(store.audio.externalRack!.unit(channel: 0) !== oldUnit)
        store.noteOn(64)
        assert(try! energy() > 0.001)
        store.noteOff(64)

        // Capture a graph-transaction error without changing its original type
        // or implying that a failed mutation has been rolled back.
        do {
            try store.audio.withGraphChanges {
                throw NSError(domain: "com.apple.coreaudio.avfaudio", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "PRIVATE-GRAPH-PATH"])
            }
            assertionFailure("Expected the injected transaction failure")
        } catch {
            assert((error as NSError).domain == "com.apple.coreaudio.avfaudio" && (error as NSError).code == -1)
        }
        assert(store.audio.lastChangeFailure?.phase == .finishGraph)
        assert(store.audio.lastChangeFailure?.previousSoundRetained == nil, "Do not promise general rollback")
        assert(store.audio.running)
        print("PASS: rejected sound replacement retains graph identity, held audio, fader, snapshots and saved session bytes")
    }
}
