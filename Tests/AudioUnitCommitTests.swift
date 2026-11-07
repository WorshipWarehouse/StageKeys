import Foundation
import AVFoundation

@main struct AudioUnitCommitTests {
    static func main() throws {
        let store = PerformanceStore()
        store.setlist = TestFixtures.setlist()
        try store.audio.prepareOffline(); store.start()
        defer { store.stopAudio() }
        store.captureSnapshot(0); store.save()
        let rack = store.audio.externalRack!
        var replies: [(AVAudioUnit?, Error?) -> Void] = []
        rack.debugInstantiate = { _, reply in replies.append(reply) }
        let identity = ExternalAUIdentity(type: 0x61756d75, subtype: 0x74657374, manufacturer: 0x54657374, name: "Generated AU")
        var proposed = Layer(name: identity.name, instrument: -1, gain: 0.2)
        proposed.id = store.patch.layers[0].id
        proposed.external = ExternalSound(kind: .audioUnit, name: identity.name, component: identity)
        let previous = store.patch.layers[0]
        let unit = rack.unit(channel: 0)!
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        let path = root.appendingPathComponent("setlist.json")
        let saved = try Data(contentsOf: path)
        func reply(_ candidate: AVAudioUnit?, _ error: Error? = nil) {
            let expected = rack.debugInstantiationCallbacks + 1
            assert(!replies.isEmpty, "Expected a generated instantiate request")
            replies.removeFirst()(candidate, error)
            let deadline = Date().addingTimeInterval(2)
            while rack.debugInstantiationCallbacks < expected && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.005))
            }
            assert(rack.debugInstantiationCallbacks == expected)
        }
        // A calibration draft is a candidate, not necessarily the instrument
        // still installed in this channel. Its authored bytes must survive.
        var calibrationDraft = proposed
        let authoredState = try PropertyListSerialization.data(fromPropertyList: ["GeneratedCalibrationState": "candidate"], format: .binary, options: 0)
        calibrationDraft.pluginState = authoredState
        func assertCandidatePreserved() throws {
            let source = try store.audio.calibrationSource(calibrationDraft, channel: 0)
            assert(source == calibrationDraft, "Calibration must not borrow the previous instrument's state")
            assert(try! store.audio.calibrationSource(previous, channel: 0) == previous)
            assert(try! store.audio.calibrationSource(calibrationDraft, channel: 15) == calibrationDraft)
        }
        try assertCandidatePreserved()
        store.noteOn(60); store.setSustain(true)
        try ExternalInstrumentRack.allowBlockedLoads()
        store.commitLayer(0, proposed)
        assert(replies.count == 1 && store.patch.layers[0] == previous && rack.unit(channel: 0) === unit)
        try assertCandidatePreserved()
        var retainedEnergy = 0.0
        for _ in 0..<32 {
            let buffer = try store.audio.offlineBlock()
            for frame in 0..<Int(buffer.frameLength) {
                retainedEnergy += Double(abs(buffer.floatChannelData![0][frame]))
            }
        }
        assert(retainedEnergy > 0.01, "Calibration capture must retain the previous instrument's audio while replacement is pending")
        assert((try! Data(contentsOf: path)) == saved && store.held.contains(60) && store.sustain)
        reply(nil, NSError(domain: NSOSStatusErrorDomain, code: -1))
        assert(store.patch.layers[0] == previous && rack.unit(channel: 0) === unit)
        try assertCandidatePreserved()
        assert((try! Data(contentsOf: path)) == saved && store.held.contains(60) && store.sustain)

        // State validation executes inside candidate installation, before a
        // successful completion can publish or persist the new document.
        var malformed = proposed; malformed.pluginState = Data("generated invalid plist".utf8)
        try ExternalInstrumentRack.allowBlockedLoads()
        store.commitLayer(0, malformed)
        let rejected = AVAudioUnitSampler()
        reply(rejected)
        assert(store.patch.layers[0] == previous && rack.unit(channel: 0) === unit && rejected.engine == nil)
        assert(store.started && store.audio.running && rack.lastGraphFailure?.rollbackSucceeded == true)
        assert((try! Data(contentsOf: path)) == saved && store.held.contains(60))

        // The state setter has run, but the staged candidate is rejected before
        // installation completion. This is a deterministic boundary fault, not
        // evidence that an arbitrary third-party setter exception is catchable.
        try ExternalInstrumentRack.allowBlockedLoads()
        var stateful = proposed
        stateful.pluginState = try rack.stateData(channel: 0)
        rack.debugGraphFault = { point in
            if case .pluginStateApplied = point { return NSError(domain: NSOSStatusErrorDomain, code: 803) }
            return nil
        }
        store.commitLayer(0, stateful)
        reply(AVAudioUnitSampler())
        assert(store.patch.layers[0] == previous && rack.unit(channel: 0) === unit && store.audio.running)
        assert(rack.lastGraphFailure?.operation?.code == 803 && rack.lastGraphFailure?.rollbackSucceeded == true)
        assert((try! Data(contentsOf: path)) == saved)
        rack.debugGraphFault = nil

        // A user edit while loading invalidates the pending proposal. It must
        // preserve that newer edit rather than installing a stale AU over it.
        try ExternalInstrumentRack.allowBlockedLoads()
        store.commitLayer(0, proposed)
        store.setGain(0, 0.4)
        let edited = store.patch.layers[0]
        reply(AVAudioUnitSampler())
        assert(store.patch.layers[0] == edited && rack.unit(channel: 0) === unit)

        // Newer native selection supersedes an older callback entirely.
        try ExternalInstrumentRack.allowBlockedLoads()
        store.commitLayer(0, proposed)
        let native = TestFixtures.layer(1)
        store.commitLayer(0, native)
        let nativeUnit = rack.unit(channel: 0)!
        reply(AVAudioUnitSampler())
        assert(store.patch.layers[0] == native && rack.unit(channel: 0) === nativeUnit)

        // Publish exactly once on accepted completion, including editor intent
        // registered while the library sheet was still open.
        try ExternalInstrumentRack.allowBlockedLoads()
        store.commitLayer(0, proposed)
        store.requestPluginInterface(0)
        assert(store.takePluginInterfaceRequest() == nil)
        let accepted = AVAudioUnitSampler()
        reply(accepted)
        assert(store.patch.layers[0].external == proposed.external && store.patch.layers[0].gain == proposed.gain && rack.unit(channel: 0) === accepted)
        assert(store.patch.layers[0].pluginState != nil, "The successful save captures the accepted plugin state")
        assert(store.audio.loadedUnit(channel: 0, sound: proposed.external) === accepted)
        assert(store.takePluginInterfaceRequest() == 0 && store.takePluginInterfaceRequest() == nil)
        assert((try! Data(contentsOf: path)) != saved)
        assert(!store.held.isEmpty, "Existing Store held-key policy is preserved; per-layer voices are panicked at commit")
        store.noteOff(60); store.noteOff(64); store.noteOff(67); store.setSustain(false)
        store.noteOn(60); store.noteOn(64); store.noteOn(67)
        store.setSustain(true); store.noteOff(64)
        let activeNotes=rack.debugActiveNoteCount(0),noteIntents=rack.debugNoteIntentCount(0)
        let generation=rack.graphGeneration
        rack.debugClearMIDIEvents()
        func assertAUVoiceContinuity(_ phase:String) {
            let disruptive=rack.debugMIDIEvents.contains {
                let kind=$0.status & 0xf0
                return kind == 0x80 || kind == 0x90 ||
                    ($0.status & 0xf0 == 0xb0 && ($0.data1 == 120 || $0.data1 == 123 || ($0.data1 == 64 && $0.data2 < 64)))
            }
            assert(!disruptive, "\(phase) must not send note, panic, or sustain-off MIDI events")
            assert(rack.debugActiveNoteCount(0)==activeNotes && rack.debugNoteIntentCount(0)==noteIntents,
                   "\(phase) must preserve active Audio Unit notes")
            assert(rack.unit(channel:0) === accepted && rack.graphGeneration==generation)
        }
        var settingsDraft=store.patch.layers[0]
        settingsDraft.channelSettings.resonance=2
        let discardToken=store.beginAudition(0)!
        store.previewLayer(0,settingsDraft,token:discardToken)
        assertAUVoiceContinuity("Audio Unit settings preview")
        store.endAudition(discardToken)
        assertAUVoiceContinuity("Audio Unit settings discard")
        let confirmToken=store.beginAudition(0)!
        store.previewLayer(0,settingsDraft,token:confirmToken)
        store.confirmAudition(confirmToken,index:0,layer:settingsDraft)
        assertAUVoiceContinuity("Audio Unit settings confirm")
        store.noteOff(60); store.noteOff(67); store.setSustain(false)
        let bytesBeforeCapture = try Data(contentsOf: path)
        let captured = try store.audio.calibrationSource(calibrationDraft, channel: 0)
        assert(captured.pluginState != nil && captured.pluginState != authoredState)
        var expectedFields = calibrationDraft, actualFields = captured
        expectedFields.pluginState = nil; actualFields.pluginState = nil
        assert(actualFields == expectedFields && calibrationDraft.pluginState == authoredState)
        let liveState = try PropertyListSerialization.propertyList(from: rack.stateData(channel: 0)!, options: [], format: nil) as! NSDictionary
        let captureState = try PropertyListSerialization.propertyList(from: captured.pluginState!, options: [], format: nil) as! NSDictionary
        assert(liveState.isEqual(captureState))
        assert(try! Data(contentsOf: path) == bytesBeforeCapture)

        // Export captures live state into an independent copy, including while
        // another layer is auditioned, without changing the authored document.
        let library = try SetlistLibrary(root: root.appendingPathComponent("Setlists"))
        let storedState = store.patch.layers[0].pluginState
        store.setlist.patches[store.selected].layers[0].pluginState = authoredState
        let beforeExport = store.setlist
        let exportEncoder = JSONEncoder(); exportEncoder.outputFormatting = .sortedKeys
        for auditionIndex in [nil, 1, 0] as [Int?] {
            let token = auditionIndex.flatMap { store.beginAudition($0) }
            let id = store.exportCurrentPatchToLibrary()!
            let exported = try library.load(id: id).patches[0]
            if auditionIndex == 0 {
                assert(exported.layers[0].pluginState == authoredState, "Keep authored state for the auditioned layer")
            } else {
                let state = try PropertyListSerialization.propertyList(from: exported.layers[0].pluginState!, options: [], format: nil) as! NSDictionary
                assert(state.isEqual(liveState), "Export must capture the current installed AU")
            }
            assert(try! exportEncoder.encode(store.setlist) == exportEncoder.encode(beforeExport))
            assert(store.audio.running)
            assert(try! Data(contentsOf: path) == bytesBeforeCapture)
            if let token { store.endAudition(token) }
            store.setlist = beforeExport
        }
        store.setlist.patches[store.selected].layers[0].pluginState = storedState

        // An installed AU must not supply state to another AU's pending draft,
        // even when the two components use the same display name.
        var other = proposed
        other.external?.component?.subtype = 0x74657332
        other.pluginState = nil
        try ExternalInstrumentRack.allowBlockedLoads()
        store.commitLayer(0, other)
        var otherDraft = other; otherDraft.pluginState = authoredState
        assert(try! store.audio.calibrationSource(otherDraft, channel: 0) == otherDraft)
        assert(rack.unit(channel: 0) === accepted)
        reply(nil, NSError(domain: NSOSStatusErrorDomain, code: -1))
        assert(try! store.audio.calibrationSource(otherDraft, channel: 0) == otherDraft)
        assert(store.audio.running && rack.unit(channel: 0) === accepted)
        assert(try! Data(contentsOf: path) == bytesBeforeCapture)
        print("PASS deferred AU document commit, rejected state rollback, supersession, editor intent and calibration source identity")
    }
}
