import Foundation
import AVFoundation

@main struct MissingAudioUnitTests {
    static func main() throws {
        var missing = ExternalAUIdentity(type: 0x61756d75, subtype: 0x6d697373, manufacturer: 0x54657374, name: "Generated missing instrument")
        missing.isV3 = false
        missing.unavailableReason = "Generated stale blocked metadata"
        assert(ExternalAUCatalog.unavailableReason(for: missing, installed: [], isMobile: false)?.contains("not installed") == true)
        assert(ExternalAUCatalog.unavailableReason(for: missing, installed: [], isMobile: true)?.contains("AUv3") == true)
        var installed = missing
        installed.name = "Generated current display name"; installed.isV3 = true; installed.unavailableReason = nil
        assert(ExternalAUCatalog.unavailableReason(for: missing, installed: [installed], isMobile: false) == nil)
        assert(ExternalAUCatalog.unavailableReason(for: missing, installed: [installed], isMobile: true) == nil, "Fresh installed AUv3 metadata wins over saved Mac metadata")
        installed.unavailableReason = "Generated unsupported architecture"
        assert(ExternalAUCatalog.unavailableReason(for: missing, installed: [installed], isMobile: false) == installed.unavailableReason)
        installed.unavailableReason = nil
        let state = try PropertyListSerialization.data(fromPropertyList: ["Generated saved setting": 42], format: .binary, options: 0)
        var layer = Layer(name: missing.name, instrument: -1, gain: 0.4)
        layer.external = ExternalSound(kind: .audioUnit, name: missing.name, component: missing)
        layer.pluginState = state
        let entry = LibrarySound(id: "generated-missing", name: layer.name, collection: "My Sounds", sound: layer.external, layer: layer)
        let row = BrowserSound.library(entry).checkingAudioUnitAvailability(installed: [], isMobile: false)
        assert(row.isAudioUnit && !row.playable && row.unavailableReason?.contains("not installed") == true)
        let refreshed = row.checkingAudioUnitAvailability(installed: [installed], isMobile: false)
        assert(refreshed.playable && refreshed.entry == entry && refreshed.entry?.layer?.pluginState == state)

        let store = PerformanceStore()
        store.setlist = TestFixtures.setlist()
        store.setlist.patches[1].layers[0] = layer
        store.setlist.patches[1].snapshots[0].sounds = store.setlist.patches[1].layers.map(SnapshotSoundState.init)
        try store.audio.prepareOffline(); store.start()
        defer { store.stopAudio() }
        store.audio.space(0); store.save()
        let rack = store.audio.externalRack!
        let unit = rack.unit(channel: 0)!
        let generation = rack.graphGeneration
        let path = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!).appendingPathComponent("setlist.json")
        let saved = try Data(contentsOf: path)
        var attempts = 0
        rack.debugInstantiate = { _, _ in attempts += 1 }
        rack.debugInstrumentCatalog = { [] }
        store.noteOn(60); store.setSustain(true)
        store.choose(1)
        assert(store.selected == 0 && store.held.contains(60) && store.sustain && store.audio.running)
        assert(rack.unit(channel: 0) === unit && rack.graphGeneration == generation && attempts == 0)
        var rejected = false
        rack.load(layer.external!, channel: 3) { if case .failure = $0 { rejected = true } }
        assert(rejected && attempts == 0 && !rack.contains(3))
        assert(!(try! ExternalInstrumentRack.blockedComponentIDs()).contains(missing.id), "Absence is not a failed plugin execution")
        assert((try! Data(contentsOf: path)) == saved && store.setlist.patches[1].layers[0].pluginState == state)
        store.stopAudio(); store.choose(1)
        assert(store.selected == 1 && store.patch.layers[0].pluginState == state)
        store.refreshUnavailablePatchInstruments(installed: [])
        assert(store.unavailablePatchInstruments.count == 1 && store.unavailablePatchInstruments[0].slot == 1)
        assert(store.unavailablePatchInstruments[0].name == missing.name)
        store.refreshUnavailablePatchInstruments(installed: [installed])
        assert(store.unavailablePatchInstruments.isEmpty && store.patch.layers[0].pluginState == state)
        store.start()
        assert(store.audioFailed && !store.audio.running && !store.started && attempts == 0)
        assert(store.message?.contains("availability") == true && store.message?.contains("previous sound remains") != true)
        assert(!(try! ExternalInstrumentRack.blockedComponentIDs()).contains(missing.id))
        assert(store.patch.layers[0].pluginState == state && store.patch.snapshots[0].sounds![0].pluginState == state)
        assert((try! Data(contentsOf: path)) == saved)
        // Explicitly retain the unavailable preset as a library entry before
        // replacing it. State capture must not substitute a different unit.
        assert(store.saveSoundToLibrary(store.patch.layers[0], index: 0))
        assert(store.librarySounds.last?.layer?.pluginState == state)
        store.stopAudio()
        let replacement = TestFixtures.layer(1)
        store.commitLayer(0, replacement)
        assert(store.patch.layers[0] == replacement && !store.audio.running)
        store.start()
        assert(store.started && store.audio.running && !store.patchLoading)
        store.noteOn(64)
        var energy = 0.0
        for _ in 0..<20 {
            let block = try store.audio.offlineBlock()
            for frame in 0..<Int(block.frameLength) { let value = block.floatChannelData![0][frame]; assert(value.isFinite); energy += Double(value * value) }
        }
        assert(energy > 0.01)
        assert(store.librarySounds.last?.layer?.pluginState == state)
        print("PASS missing AU: fresh catalog identity, library status, no quarantine, preserved state, offline replacement and rendered recovery")
    }
}
