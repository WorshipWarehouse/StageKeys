import Foundation
import AVFoundation

@main struct SnapshotProcessingTests {
    static func main() throws {
        func bytes(_ patch: Patch) -> Data {
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            return try! encoder.encode(patch)
        }
        let store = PerformanceStore()
        store.setlist = TestFixtures.setlist()
        try store.audio.prepareOffline(); store.start()
        defer { store.stopAudio() }
        store.audio.space(0)
        for index in 1..<15 { store.setGain(index, 0) }
        store.captureSnapshot(0); store.save()
        let rack = store.audio.externalRack!
        let previous = store.patch
        let oldSnapshot = store.activeSnapshot
        let oldUnit = rack.unit(channel: 0)!
        let nodes = rack.debugOwnedNodeCount
        let path = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!).appendingPathComponent("setlist.json")
        let saved = try Data(contentsOf: path)
        var gain = AudioEffect.factoryDefault(kind: 9); gain.parameters = [-24]
        let split = ImportedRack(audioRacks: [ImportedAudioRack(beforeEffect: 0, name: "Generated parallel", branches: [
            ImportedAudioBranch(name: "A", rack: ImportedRack()), ImportedAudioBranch(name: "B", rack: ImportedRack())
        ])])
        var target = Snapshot(name: "Generated processing target", gains: store.patch.layers.map(\.gain))
        target.seconds = 0.05
        target.sounds = store.patch.layers.map(SnapshotSoundState.init)
        target.sounds![0].effects[0] = gain
        target.sounds![0].pan = 0.6
        target.sounds![1].importedRack = split
        target.gains[0] = 0.25
        store.noteOn(60); store.setSustain(true)
        func energy() throws -> Double {
            var sum = 0.0
            for _ in 0..<30 {
                let block = try store.audio.offlineBlock()
                for frame in 0..<Int(block.frameLength) {
                    let value = block.floatChannelData![0][frame]
                    assert(value.isFinite); sum += Double(value * value)
                }
            }
            return sum
        }
        _ = try energy()
        let before = try energy(); assert(before > 0.01)
        rack.debugGraphFault = { point in
            if case .graphConnected = point { return NSError(domain: NSOSStatusErrorDomain, code: 901) }
            return nil
        }
        store.recall(target)
        assert(bytes(store.patch) == bytes(previous) && store.activeSnapshot == oldSnapshot, "Rejected initial processing must not publish any layer or snapshot selection")
        assert((try! Data(contentsOf: path)) == saved && store.held.contains(60) && store.sustain)
        assert(store.started && store.audio.running && rack.unit(channel: 0) === oldUnit && rack.debugOwnedNodeCount == nodes)
        assert(rack.lastGraphFailure?.rollbackSucceeded == true)
        let after = try energy()
        assert(after > before * 0.7 && after < before * 1.3, "Earlier-layer gain/pan controls must roll back when a later-layer topology fails")
        RunLoop.current.run(until: Date().addingTimeInterval(0.12))
        assert(bytes(store.patch) == bytes(previous), "A rejected recall must not leave a morph timer running")
        rack.debugGraphFault = nil
        store.recall(target)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        assert(store.activeSnapshot == target.id)
        assert(store.patch.layers[0].effects[0].kind == 9 && store.patch.layers[0].effects[0].values[0] == -24)
        assert(abs(store.patch.layers[0].pan - 0.6) < 0.001 && abs(store.patch.layers[0].gain - 0.25) < 0.001)
        assert(store.patch.layers[1].importedRack == split)
        assert((try! energy()) < before * 0.05, "Accepted effects must actually change rendered audio")

        // A rejected edit must not alter snapshots or the saved session. Force
        // a topology edit through the live layer's authored processing state.
        var changed = store.patch.layers[0]
        changed.importedRack = split
        store.setlist.patches[store.selected].layers[0] = changed
        store.save()
        let editBefore = store.patch
        let editSaved = try Data(contentsOf: path)
        rack.debugGraphFault = { point in
            if case .graphConnected = point { return NSError(domain: NSOSStatusErrorDomain, code: 902) }
            return nil
        }
        store.setEffect(0, 0, AudioEffect.factoryDefault(kind: 1))
        assert(bytes(store.patch) == bytes(editBefore) && (try! Data(contentsOf: path)) == editSaved)
        rack.debugGraphFault = nil
        store.setEffect(0, 0, AudioEffect.factoryDefault(kind: 1))
        assert(store.patch.layers[0].effects[0].kind == 1)
        assert(store.patch.snapshots.allSatisfy { $0.sounds?[0].effects[0].kind == 1 })
        var malformed = target; malformed.gains = []
        let valid = store.patch
        store.recall(malformed)
        assert(bytes(store.patch) == bytes(valid) && store.message?.contains("invalid") == true)
        // Two generated AU candidates exercise serialized state restoration
        // across layers. This is an Apple sampler boundary test, not vendor AU
        // fault containment or a claim of phase-continuous restoration.
        var replies: [(AVAudioUnit?, Error?) -> Void] = []
        rack.debugInstantiate = { _, reply in replies.append(reply) }
        let identity = ExternalAUIdentity(type: 0x61756d75, subtype: 0x74786e73, manufacturer: 0x54657374, name: "Generated snapshot AU")
        for channel in [3, 4] {
            var layer = Layer(name: identity.name, instrument: -1, gain: 0)
            layer.id = store.patch.layers[channel].id
            layer.external = ExternalSound(kind: .audioUnit, name: identity.name, component: identity)
            store.commitLayer(channel, layer)
            assert(replies.count == 1)
            let expected = rack.debugInstantiationCallbacks + 1
            let sampler = AVAudioUnitSampler()
            sampler.auAudioUnit.fullStateForDocument = rack.state(channel: 0)!
            replies.removeFirst()(sampler, nil)
            let deadline = Date().addingTimeInterval(2)
            while rack.debugInstantiationCallbacks < expected && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
            assert(rack.debugInstantiationCallbacks == expected && store.patch.layers[channel].external?.kind == .audioUnit)
        }
        let auBefore = bytes(store.patch)
        let auSaved = try Data(contentsOf: path)
        let statesBefore = [rack.state(channel: 3)!, rack.state(channel: 4)!]
        var serialized = rack.state(channel: 0)!
        serialized["StageKeys.GeneratedBoundary"] = 903
        let data = try PropertyListSerialization.data(fromPropertyList: serialized, format: .binary, options: 0)
        var auTarget = Snapshot(name: "Generated AU state transaction", gains: store.patch.layers.map(\.gain))
        auTarget.sounds = store.patch.layers.map(SnapshotSoundState.init)
        auTarget.sounds![3].pluginState = data; auTarget.sounds![4].pluginState = data
        var applied = 0
        rack.debugGraphFault = { point in
            if case .pluginStateApplied = point {
                applied += 1
                if applied == 2 { return NSError(domain: NSOSStatusErrorDomain, code: 903) }
            }
            return nil
        }
        store.recall(auTarget)
        assert(applied == 2 && bytes(store.patch) == auBefore && (try! Data(contentsOf: path)) == auSaved)
        assert(store.started && store.audio.running && rack.lastGraphFailure?.rollbackSucceeded == true)
        for (index, channel) in [3, 4].enumerated() {
            assert(NSDictionary(dictionary: statesBefore[index]).isEqual(to: rack.state(channel: channel)!))
        }
        rack.debugGraphFault = nil
        store.recall(auTarget)
        assert(store.patch.layers[3].pluginState == data && store.patch.layers[4].pluginState == data)
        print("PASS snapshot processing: cross-layer rollback, held audio, saved bytes, retry, effect edits and malformed recall")
    }
}
