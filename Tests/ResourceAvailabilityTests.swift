import Foundation
import AVFoundation

@main struct ResourceAvailabilityTests {
    static func main() throws {
        let store = PerformanceStore()
        store.setlist = TestFixtures.setlist()
        try store.audio.prepareOffline(); store.start()
        defer { store.stopAudio() }
        store.audio.space(0)
        for index in 1..<15 { store.setGain(index, 0) }
        let rack = store.audio.externalRack!
        var missing = TestFixtures.layer(2)
        missing.external!.fileName = "Generated unavailable.wav"
        store.setlist.patches[1].layers[2] = missing
        store.captureSnapshot(0); store.save()
        let previous = store.patch.layers
        let snapshot = store.activeSnapshot
        let unit = rack.unit(channel: 0)!
        let generation = rack.graphGeneration
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        let session = root.appendingPathComponent("setlist.json")
        let saved = try Data(contentsOf: session)
        store.noteOn(60); store.setSustain(true)
        func energy() throws -> Double {
            var sum = 0.0
            for _ in 0..<20 {
                let block = try store.audio.offlineBlock()
                for frame in 0..<Int(block.frameLength) { let v = block.floatChannelData![0][frame]; assert(v.isFinite); sum += Double(v * v) }
            }
            return sum
        }
        _ = try energy()
        let before = try energy(); assert(before > 0.01)
        store.choose(1)
        assert(store.selected == 0 && store.patch.layers == previous && store.activeSnapshot == snapshot)
        assert(store.held.contains(60) && store.sustain && store.started && rack.unit(channel: 0) === unit)
        assert(rack.graphGeneration == generation && (try! Data(contentsOf: session)) == saved)
        assert((try! energy()) > before * 0.8)

        // Known references beyond the old 4,096-entry prefix must be checked.
        let original = root.appendingPathComponent("Generated Fixture 0.wav")
        var refs: [String: String] = [:]
        for index in 0..<4097 { refs[String(format: "Sample:%05d", index)] = original.path }
        refs["Sample:04096"] = root.appendingPathComponent("Generated absent reference.wav").path
        let preset = rack.libraryURL.appendingPathComponent("Generated reference inventory.aupreset")
        try PropertyListSerialization.data(fromPropertyList: ["file-references": refs], format: .xml, options: 0).write(to: preset)
        var proposal = previous[0]
        proposal.external = ExternalSound(kind: .samplerPreset, name: "Generated inventory", fileName: preset.lastPathComponent)
        do { try store.audio.prepareSoundChange(0, proposal); assertionFailure("Missing final reference was skipped") }
        catch { assert(store.audio.lastChangeFailure?.phase == .prepareSound) }
        let directory = rack.libraryURL.appendingPathComponent("Generated directory.wav")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        proposal.external = ExternalSound(kind: .sample, name: "Generated directory", fileName: directory.lastPathComponent)
        do { try store.audio.prepareSoundChange(0, proposal); assertionFailure("Directory is not an audio file") } catch {}
        let link = rack.libraryURL.appendingPathComponent("Generated readable link.wav")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        proposal.external!.fileName = link.lastPathComponent
        try store.audio.prepareSoundChange(0, proposal) // Valid file symlinks remain usable.

        // Simulate loss of an active managed sample while its resident voice is
        // sounding. A structural edit must fail before stopping/reloading it.
        let references = rack.state(channel: 0)!["file-references"] as! [String: String]
        let reference = references.values.first!
        let activeFile = reference.hasPrefix("file://") ? URL(string: reference)! : URL(fileURLWithPath: reference)
        let activeBytes = try Data(contentsOf: activeFile)
        let backup = root.appendingPathComponent("Generated disconnected active.wav")
        try FileManager.default.moveItem(at: activeFile, to: backup)
        defer { if FileManager.default.fileExists(atPath: backup.path) { try? FileManager.default.moveItem(at: backup, to: activeFile) } }
        let split = ImportedRack(audioRacks: [ImportedAudioRack(beforeEffect: 0, name: "Generated topology", branches: [ImportedAudioBranch(name: "A", rack: ImportedRack())])])
        var states = [0: SnapshotSoundState(previous[0]), 1: SnapshotSoundState(previous[1])]
        var gain = AudioEffect.factoryDefault(kind: 9); gain.parameters = [-24]
        states[0]!.effects[0] = gain; states[0]!.pan = 0.7
        states[1]!.importedRack = split
        assert(!store.audio.applySnapshotStates(states))
        assert(rack.graphGeneration == generation && rack.unit(channel: 0) === unit && store.audio.running && store.started)
        assert(store.held.contains(60) && store.sustain && (try! Data(contentsOf: session)) == saved)
        let after = try energy()
        assert(after > before * 0.7 && after < before * 1.3, "Earlier controls must roll back without reloading missing resident samples")
        assert(rack.lastGraphFailure?.edited == false && rack.lastGraphFailure?.rollbackSucceeded == true)

        // Reconnect exact original bytes; the same processing request can retry.
        try FileManager.default.moveItem(at: backup, to: activeFile)
        assert((try! Data(contentsOf: activeFile)) == activeBytes)
        assert(store.audio.applySnapshotStates(states))
        assert(rack.graphGeneration > generation && (try! energy()) < before * 0.05)
        // Lost old samples must not permanently wedge a different valid patch:
        // first rejection stops safely; manual retry discards abandoned nodes.
        try FileManager.default.moveItem(at: activeFile, to: backup)
        store.setlist.patches[1].layers = [TestFixtures.layer(1)] + (0..<14).map { _ in Layer.empty() }
        store.choose(1)
        assert(store.selected == 1 && !store.started && store.audioFailed && !store.audio.running)
        store.start()
        assert(store.started && store.audio.running && rack.unit(channel: 0) !== unit)
        store.noteOn(64); assert((try! energy()) > 0.01); store.noteOff(64)
        assert((try! Data(contentsOf: session)) == saved)
        // Stopped users can navigate to an unavailable authored patch and fix
        // its layer documents without loading the old missing source.
        store.stopAudio()
        store.choose(0)
        assert(store.selected == 0 && !store.started && !store.audio.running)
        let replacement = TestFixtures.layer(1, gain: 0.4)
        store.commitLayer(0, replacement)
        assert(store.patch.layers[0] == replacement && !store.audio.running && !store.patchLoading)
        store.setEffect(0, 0, AudioEffect.factoryDefault(kind: 9))
        assert(store.patch.layers[0].effects[0].kind == 9 && !store.audio.running)
        store.start()
        assert(store.started && store.audio.running && !store.patchLoading)
        store.noteOn(67); assert((try! energy()) > 0.001); store.noteOff(67)
        do {
        let unit = rack.unit(channel: 0)!
        let generation = rack.graphGeneration
        store.save()
        let saved = try Data(contentsOf: session)
        // A refused library preview must not panic, isolate other channels, or
        // replace an existing editor session before resource preflight succeeds.
        let editor = store.beginAudition(0)!
        let draft = store.playbackLayer(0)
        store.noteOn(64); store.setSustain(true)
        assert(store.auditionLibrarySound(0, missing) == nil)
        assert(store.playbackLayer(0) == draft && store.held.contains(64) && store.sustain)
        assert(rack.unit(channel: 0) === unit && rack.graphGeneration == generation)
        store.previewLayer(0, missing, token: editor)
        assert(store.playbackLayer(0) == draft && store.held.contains(64) && store.sustain)
        assert((try! Data(contentsOf: session)) == saved && (try! energy()) > 0.01)
        var validDraft = draft; validDraft.pan = 0.25
        store.previewLayer(0, validDraft, token: editor)
        assert(store.playbackLayer(0).pan == 0.25, "Rejected library preview must retain the existing editor token")
        store.endAudition(editor)

        }
        print("PASS resource recovery: pre-selection retention, all known refs, regular files, symlinks, resident playback, reconnect and abandoned-graph retry")
    }
}
